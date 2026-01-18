local M = {}

local ns_id = vim.api.nvim_create_namespace("angular-refs")

-- Debounce timers per buffer
---@type table<number, any>
local debounce_timers = {}

-- Active refresh flag per buffer (codelens pattern - prevents concurrent requests)
---@type table<number, true>
local active_refreshes = {}

-- Track extmark IDs per buffer: { [bufnr] = { [line] = extmark_id } }
---@type table<number, table<number, number>>
local extmark_ids = {}

-- Store last computed results per buffer for querying
---@type table<number, table<number, {symbol: Symbol, ts_count: number, template_count: number}>>
local last_results = {}

-- Generation counter per buffer to handle async race conditions
---@type table<number, number>
local update_generation = {}

---@class Symbol
---@field name string
---@field line number 0-indexed line number
---@field col number 0-indexed column
---@field kind string Symbol kind

---Get symbols via LSP documentSymbol
---@param bufnr number
---@param callback fun(symbols: Symbol[])
local function get_symbols_async(bufnr, callback)
  local params = { textDocument = vim.lsp.util.make_text_document_params(bufnr) }

  -- Get TypeScript LSP client
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  local ts_client = nil
  for _, client in ipairs(clients) do
    if client.name == "typescript-tools" or client.name == "ts_ls" or client.name == "vtsls" then
      ts_client = client
      break
    end
  end

  if not ts_client then
    callback({})
    return
  end

  ts_client.request("textDocument/documentSymbol", params, function(err, result)
    if err or not result then
      callback({})
      return
    end

    local symbols = {}
    local SK = vim.lsp.protocol.SymbolKind

    -- Top-level symbols to track (exported functions, constants, enums)
    local TOP_LEVEL_KINDS = {
      [SK.Function] = true,
      [SK.Constant] = true,
      [SK.Enum] = true,
    }

    -- Class/interface member kinds to track
    local MEMBER_KINDS = {
      [SK.Method] = true,
      [SK.Property] = true,
      [SK.Field] = true,
    }

    -- Container kinds that have trackable children
    local CONTAINER_KINDS = {
      [SK.Class] = true,
      [SK.Interface] = true,
    }

    for _, item in ipairs(result) do
      local range = item.range or item.location and item.location.range
      if not range then
        goto continue
      end

      local kind = item.kind
      local name = item.name

      -- Skip private (underscore prefix convention)
      if name:match("^_") then
        goto continue
      end

      -- Track top-level exports (functions, constants, enums)
      if TOP_LEVEL_KINDS[kind] then
        table.insert(symbols, {
          name = name,
          line = range.start.line,
          col = range.start.character,
          kind = SK[kind] or "unknown",
        })
      end

      -- Track class/interface members (but not their internal variables)
      if CONTAINER_KINDS[kind] and item.children then
        for _, child in ipairs(item.children) do
          local child_range = child.range or child.location and child.location.range
          if child_range and child.kind and MEMBER_KINDS[child.kind] then
            local child_name = child.name
            -- Skip private members only
            if not child_name:match("^_") then
              table.insert(symbols, {
                name = child_name,
                line = child_range.start.line,
                col = child_range.start.character,
                kind = SK[child.kind] or "unknown",
              })
            end
          end
        end
      end

      ::continue::
    end

    local cfg = require("angular-refs.config").get()
    if cfg.debug then
      vim.notify("angular-refs: Found " .. #symbols .. " symbols", vim.log.levels.DEBUG)
      for _, s in ipairs(symbols) do
        vim.notify("angular-refs:   [" .. s.kind .. "] " .. s.name .. " at line " .. s.line, vim.log.levels.DEBUG)
      end
    end

    callback(symbols)
  end, bufnr)
end

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

  -- Codelens pattern: prevent concurrent requests for same buffer
  if active_refreshes[bufnr] then
    return
  end
  active_refreshes[bufnr] = true

  -- Increment generation to invalidate any in-flight async operations
  update_generation[bufnr] = (update_generation[bufnr] or 0) + 1
  local current_gen = update_generation[bufnr]

  -- Get symbols via LSP (extmarks cleared in render_results, not here)
  get_symbols_async(bufnr, function(symbols)
    -- Check if this update is still current
    if update_generation[bufnr] ~= current_gen then
      active_refreshes[bufnr] = nil
      return
    end

    if #symbols == 0 then
      active_refreshes[bufnr] = nil
      return
    end

    local lsp = require("angular-refs.lsp")
    local server = require("angular-refs.server")

    -- Process each symbol
    local pending_count = #symbols
    local results = {}

    for _, symbol in ipairs(symbols) do
      -- Get TS references via LSP (async)
      lsp.get_references(bufnr, symbol.line, symbol.col, function(ts_refs)
        -- Check if this update is still current
        if update_generation[bufnr] ~= current_gen then
          return
        end

        -- Get template references via Angular LSP
        server.get_template_refs(bufnr, symbol.name, function(template_refs)
          -- Check if this update is still current
          if update_generation[bufnr] ~= current_gen then
            return
          end

          results[symbol.line] = {
            symbol = symbol,
            ts_count = ts_refs and #ts_refs or 0,
            template_count = template_refs and #template_refs or 0,
          }

          pending_count = pending_count - 1

          -- When all symbols are processed, update display
          if pending_count == 0 then
            active_refreshes[bufnr] = nil
            M.render_results(bufnr, results)
          end
        end)
      end)
    end

    -- Timeout fallback
    vim.defer_fn(function()
      if update_generation[bufnr] == current_gen and pending_count > 0 then
        pending_count = 0
        active_refreshes[bufnr] = nil
        M.render_results(bufnr, results)
      end
    end, 5000)
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
  extmark_ids[bufnr] = {}

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

    local ext_id = vim.api.nvim_buf_set_extmark(bufnr, ns_id, line, 0, virt_text_opts)
    extmark_ids[bufnr][line] = ext_id
  end
end

---Schedule an update with debouncing
---@param bufnr number
function M.schedule_update(bufnr)
  local cfg = require("angular-refs.config").get()

  -- Cancel existing timer for this buffer
  if debounce_timers[bufnr] then
    vim.fn.timer_stop(debounce_timers[bufnr])
  end

  -- Schedule new update
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
  extmark_ids[bufnr] = nil
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
