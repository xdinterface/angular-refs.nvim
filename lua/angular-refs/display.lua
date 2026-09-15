local M = {}

local ns_id = vim.api.nvim_create_namespace("angular-refs")

---@type table<number, any>
local debounce_timers = {}

-- Active refresh flag per buffer (codelens pattern - prevents concurrent requests)
---@type table<number, true>
local active_refreshes = {}

---@type table<number, table<number, {symbol: Symbol, ts_count: number, template_count: number}>>
local last_results = {}

---@type table<number, number>
local update_generation = {}

---Format the usage display text
---@param total number Total usage count
---@return string text, string highlight
local function format_usage_text(total)
  local cfg = require("angular-refs.config").get()

  if total == 0 then
    return cfg.display.format_zero, cfg.display.zero_refs_highlight
  elseif total == 1 then
    return string.format(cfg.display.format_singular, total), cfg.display.highlight
  else
    return string.format(cfg.display.format, total), cfg.display.highlight
  end
end

---Update reference display for a buffer
---@param bufnr number
function M.update(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local filename = vim.api.nvim_buf_get_name(bufnr)
  if filename == "" then
    return
  end

  -- Skip files in excluded paths (node_modules, dist, gitignored, etc.)
  local filter = require("angular-refs.filter")
  if filter.should_exclude(filename) then
    return
  end

  -- Codelens pattern: prevent concurrent requests for same buffer
  if active_refreshes[bufnr] then
    return
  end
  active_refreshes[bufnr] = true

  -- Increment generation to invalidate any in-flight async operations
  update_generation[bufnr] = (update_generation[bufnr] or 0) + 1
  local current_gen = update_generation[bufnr]

  -- Get symbols via LSP (extmarks cleared in render_results, not here)
  require("angular-refs.lsp").get_symbols(bufnr, function(symbols)
    -- Check if this update is still current
    if update_generation[bufnr] ~= current_gen then
      active_refreshes[bufnr] = nil
      return
    end

    if #symbols == 0 then
      active_refreshes[bufnr] = nil
      return
    end

    local server = require("angular-refs.server")
    local lsp = require("angular-refs.lsp")
    local cfg = require("angular-refs.config").get()

    -- Comprehensive mode: Use WebStorm-style counting (includes parent usages)
    if cfg.comprehensive_mode then
      server.get_comprehensive_counts(bufnr, function(comprehensive_counts)
        if update_generation[bufnr] ~= current_gen then
          active_refreshes[bufnr] = nil
          return
        end

        local results = {}
        for _, symbol in ipairs(symbols) do
          local count = comprehensive_counts[symbol.name] or 0
          results[symbol.line] = {
            symbol = symbol,
            ts_count = 0,
            template_count = count,
          }
        end

        active_refreshes[bufnr] = nil
        M.render_results(bufnr, results)
      end)
      return
    end

    -- Analyze the template once per refresh, then share its counts across symbols.
    -- Lifecycle hooks retain local-only TS references and decorator references.
    local function collect_references(template_symbols)
      if update_generation[bufnr] ~= current_gen then
        return
      end

      local results = {}
      local pending_count = #symbols
      for _, symbol in ipairs(symbols) do
        local is_lifecycle = server.is_lifecycle_method(symbol.name)
        lsp.get_references(bufnr, symbol.line, symbol.col, function(ts_refs)
          if update_generation[bufnr] ~= current_gen then
            return
          end

          local template_count = is_lifecycle and 0 or (template_symbols[symbol.name] or 0)
          results[symbol.line] = {
            symbol = symbol,
            ts_count = ts_refs and #ts_refs or 0,
            template_count = template_count + server.get_decorator_refs(bufnr, symbol.name),
          }

          pending_count = pending_count - 1
          if pending_count == 0 then
            active_refreshes[bufnr] = nil
            M.render_results(bufnr, results)
          end
        end, is_lifecycle)
      end
    end

    local needs_template = false
    for _, symbol in ipairs(symbols) do
      if not server.is_lifecycle_method(symbol.name) then
        needs_template = true
        break
      end
    end
    if needs_template then
      server.get_all_template_symbols(bufnr, collect_references)
    else
      collect_references({})
    end

    -- Timeout fallback: clear stale state after 10 seconds if LSP hasn't responded
    vim.defer_fn(function()
      if update_generation[bufnr] == current_gen and active_refreshes[bufnr] then
        active_refreshes[bufnr] = nil
        vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
      end
    end, 10000)
  end)
end

---Render reference results as virtual text
---@param bufnr number
---@param results table<number, {symbol: Symbol, ts_count: number, template_count: number}>
function M.render_results(bufnr, results)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Clear existing extmarks before adding new ones (moved from update())
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  -- Store results for later querying (e.g., get_unused)
  last_results[bufnr] = results

  local cfg = require("angular-refs.config").get()

  for line, data in pairs(results) do
    local total = data.ts_count + data.template_count
    local text, hl = format_usage_text(total)
    text = cfg.display.separator .. text

    local virt_text_opts = {
      virt_text = { { text, hl } },
      hl_mode = "combine",
    }

    if cfg.display.position == "above" then
      virt_text_opts.virt_lines = { { { text, hl } } }
      virt_text_opts.virt_lines_above = true
      virt_text_opts.virt_text = nil
    else
      virt_text_opts.virt_text_pos = "eol"
    end

    vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, virt_text_opts)
  end
end

---Schedule an update with debouncing
---@param bufnr number
function M.schedule_update(bufnr)
  -- Skip files in excluded paths
  local filename = vim.api.nvim_buf_get_name(bufnr)
  if filename ~= "" then
    local filter = require("angular-refs.filter")
    if filter.should_exclude(filename) then
      return
    end
  end

  local cfg = require("angular-refs.config").get()

  if debounce_timers[bufnr] then
    vim.fn.timer_stop(debounce_timers[bufnr])
  end

  debounce_timers[bufnr] = vim.fn.timer_start(cfg.trigger.debounce_ms, function()
    debounce_timers[bufnr] = nil
    vim.schedule(function()
      M.update(bufnr)
    end)
  end)
end

---Clear all virtual text in a buffer
---@param bufnr number|nil
function M.clear(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  last_results[bufnr] = nil
  active_refreshes[bufnr] = nil
end

---Get all unused symbols in a buffer
---@param bufnr number
---@return {name: string, line: number, kind: string}[]
function M.get_unused(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local results = last_results[bufnr]
  if not results then
    return {}
  end

  local unused = {}
  for _, data in pairs(results) do
    if data.ts_count + data.template_count == 0 then
      table.insert(unused, {
        name = data.symbol.name,
        line = data.symbol.line + 1, -- Convert to 1-indexed
        kind = data.symbol.kind,
      })
    end
  end

  table.sort(unused, function(a, b)
    return a.line < b.line
  end)
  return unused
end

return M
