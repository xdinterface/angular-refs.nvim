local M = {}

-- Cache TCB symbols per buffer to avoid repeated LSP calls
---@type table<number, table<string, number>>
local tcb_cache = {}

---@class TemplateRef
---@field file string Full file path
---@field line number 1-indexed line number
---@field column number 1-indexed column number
---@field context string Line content for preview

---Get the Angular LSP client (check all buffers since it might only be attached to HTML)
---@param bufnr number|nil Optional buffer to check first
---@return table|nil
local function get_angular_client(bufnr)
  -- First try the specific buffer
  if bufnr then
    local clients = vim.lsp.get_clients({ bufnr = bufnr, name = "angularls" })
    if #clients > 0 then
      return clients[1]
    end
    clients = vim.lsp.get_clients({ bufnr = bufnr, name = "angular" })
    if #clients > 0 then
      return clients[1]
    end
  end

  -- Fall back to any attached Angular client
  local clients = vim.lsp.get_clients({ name = "angularls" })
  if #clients > 0 then
    return clients[1]
  end
  clients = vim.lsp.get_clients({ name = "angular" })
  return clients[1]
end

---Find the template file path for a component
---@param component_path string Path to the .ts component file
---@return string|nil template_path
local function find_template_file(component_path)
  -- Read component file content
  local file = io.open(component_path, "r")
  if not file then
    return nil
  end
  local content = file:read("*all")
  file:close()

  -- Look for templateUrl: './xxx.html' or templateUrl: "xxx.html"
  local template_url = content:match("templateUrl%s*:%s*['\"]([^'\"]+)['\"]")
  if template_url then
    -- Resolve relative path
    local component_dir = vim.fn.fnamemodify(component_path, ":h")
    return vim.fn.simplify(component_dir .. "/" .. template_url)
  end

  -- Try convention: component.ts -> component.html
  local html_path = component_path:gsub("%.ts$", ".html")
  if vim.fn.filereadable(html_path) == 1 then
    return html_path
  end

  return nil
end

---Parse TCB TypeScript content to extract referenced symbols
---@param tcb_content string
---@return table<string, number> symbol_name to count mapping
function M.parse_tcb_symbols(tcb_content)
  local symbols = {}

  -- Angular TCB generates code with patterns like:
  -- ((this).propertyName)   - most common in modern Angular
  -- (this).propertyName     - also common
  -- this.propertyName       - less common
  -- ((_ctx).propertyName)   - older Angular versions

  -- Match ((this).xxx) patterns - most common in modern Angular
  for symbol in tcb_content:gmatch("%(%(this%)%)%.([a-zA-Z_][a-zA-Z0-9_]*)") do
    symbols[symbol] = (symbols[symbol] or 0) + 1
  end

  -- Match (this).xxx patterns
  for symbol in tcb_content:gmatch("%(this%)%.([a-zA-Z_][a-zA-Z0-9_]*)") do
    symbols[symbol] = (symbols[symbol] or 0) + 1
  end

  -- Match this.xxx patterns (without parentheses)
  for symbol in tcb_content:gmatch("[^%w_]this%.([a-zA-Z_][a-zA-Z0-9_]*)") do
    symbols[symbol] = (symbols[symbol] or 0) + 1
  end

  -- Legacy: Match ((_ctx).xxx) patterns - older Angular versions
  for symbol in tcb_content:gmatch("%(%(_ctx%)%)%.([a-zA-Z_][a-zA-Z0-9_]*)") do
    symbols[symbol] = (symbols[symbol] or 0) + 1
  end

  -- Legacy: Match _ctx.xxx patterns
  for symbol in tcb_content:gmatch("_ctx%.([a-zA-Z_][a-zA-Z0-9_]*)") do
    symbols[symbol] = (symbols[symbol] or 0) + 1
  end

  return symbols
end

---Call angular/getTcb LSP request on the template file and parse response
---@param bufnr number The component TS buffer
---@param callback fun(symbols: table<string, number>)
function M.get_tcb_symbols(bufnr, callback)
  -- Check cache first
  if tcb_cache[bufnr] then
    callback(tcb_cache[bufnr])
    return
  end

  local cfg = require("angular-refs.config").get()
  local component_path = vim.api.nvim_buf_get_name(bufnr)

  -- Find the template file for this component
  local template_path = find_template_file(component_path)
  if not template_path then
    if cfg.debug then
      vim.notify("angular-refs: No template file found for " .. component_path, vim.log.levels.DEBUG)
    end
    callback({})
    return
  end

  if cfg.debug then
    vim.notify("angular-refs: Found template: " .. template_path, vim.log.levels.DEBUG)
  end

  -- Get Angular client (might be attached to template buffer)
  local client = get_angular_client(bufnr)
  if not client then
    if cfg.debug then
      vim.notify("angular-refs: Angular LSP client not found", vim.log.levels.DEBUG)
    end
    callback({})
    return
  end

  -- Call getTcb on the template file
  local template_uri = vim.uri_from_fname(template_path)
  local params = {
    textDocument = { uri = template_uri },
    position = { line = 0, character = 0 },
  }

  if cfg.debug then
    vim.notify("angular-refs: Calling getTcb on " .. template_uri, vim.log.levels.DEBUG)
  end

  client.request("angular/getTcb", params, function(err, result)
    if err then
      if cfg.debug then
        vim.notify("angular-refs: getTcb error: " .. vim.inspect(err), vim.log.levels.DEBUG)
      end
      callback({})
      return
    end

    if not result or not result.content then
      if cfg.debug then
        vim.notify("angular-refs: getTcb returned no content for " .. template_path, vim.log.levels.DEBUG)
      end
      callback({})
      return
    end

    if cfg.debug then
      vim.notify("angular-refs: TCB content length: " .. #result.content, vim.log.levels.DEBUG)
    end

    -- Parse TCB content to extract symbol references
    local symbols = M.parse_tcb_symbols(result.content)

    -- Cache the result
    tcb_cache[bufnr] = symbols

    if cfg.debug then
      vim.notify("angular-refs: TCB symbols found: " .. vim.inspect(symbols), vim.log.levels.DEBUG)
    end

    callback(symbols)
  end, bufnr)
end

---Get template references for a symbol
---@param bufnr number
---@param symbol_name string
---@param callback fun(refs: TemplateRef[])
function M.get_template_refs(bufnr, symbol_name, callback)
  M.get_tcb_symbols(bufnr, function(symbols)
    local count = symbols[symbol_name] or 0

    if count > 0 then
      -- Symbol found in template
      -- TCB doesn't give exact line numbers, so we return placeholder refs
      local refs = {}
      local filename = vim.api.nvim_buf_get_name(bufnr)

      for _ = 1, count do
        table.insert(refs, {
          file = filename,
          line = 0,
          column = 0,
          context = "(template reference)",
        })
      end

      callback(refs)
    else
      callback({})
    end
  end)
end

---Invalidate cache for a buffer
---@param bufnr number|string Buffer number or file path
function M.invalidate(bufnr)
  if type(bufnr) == "string" then
    -- File path passed, find buffer
    for buf, _ in pairs(tcb_cache) do
      if vim.api.nvim_buf_is_valid(buf) then
        local name = vim.api.nvim_buf_get_name(buf)
        if name == bufnr or name:match(vim.pesc(bufnr)) then
          tcb_cache[buf] = nil
        end
      end
    end
  else
    tcb_cache[bufnr] = nil
  end
end

---Clear entire cache
function M.clear_cache()
  tcb_cache = {}
end

---Dump raw TCB content for debugging
---@param bufnr number
function M.dump_tcb(bufnr)
  local component_path = vim.api.nvim_buf_get_name(bufnr)
  local template_path = find_template_file(component_path)

  if not template_path then
    vim.notify("angular-refs: No template file found for " .. component_path, vim.log.levels.ERROR)
    return
  end

  vim.notify("angular-refs: Template: " .. template_path, vim.log.levels.INFO)

  local client = get_angular_client(bufnr)
  if not client then
    vim.notify("angular-refs: Angular LSP client not found", vim.log.levels.ERROR)
    return
  end

  vim.notify("angular-refs: Using client: " .. client.name, vim.log.levels.INFO)

  local template_uri = vim.uri_from_fname(template_path)
  client.request("angular/getTcb", {
    textDocument = { uri = template_uri },
    position = { line = 0, character = 0 },
  }, function(err, result)
    if err then
      vim.notify("angular-refs: getTcb error: " .. vim.inspect(err), vim.log.levels.ERROR)
      return
    end

    if not result or not result.content then
      vim.notify("angular-refs: getTcb returned no content", vim.log.levels.WARN)
      return
    end

    vim.notify("angular-refs: TCB content length: " .. #result.content, vim.log.levels.INFO)

    -- Show in a scratch buffer
    local lines = vim.split(result.content, "\n")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = "typescript"
    vim.api.nvim_buf_set_name(buf, "TCB Debug Output")

    vim.cmd("vsplit")
    vim.api.nvim_win_set_buf(0, buf)

    -- Also show parsed symbols
    local symbols = M.parse_tcb_symbols(result.content)
    local symbol_list = {}
    for name, count in pairs(symbols) do
      table.insert(symbol_list, string.format("  %s: %d", name, count))
    end
    table.sort(symbol_list)

    if #symbol_list > 0 then
      vim.notify("angular-refs: Parsed symbols:\n" .. table.concat(symbol_list, "\n"), vim.log.levels.INFO)
    else
      vim.notify("angular-refs: No symbols parsed from TCB content", vim.log.levels.WARN)
    end
  end, bufnr)
end

return M
