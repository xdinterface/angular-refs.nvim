---@class TestHelpers
local M = {}

local plugin_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
M.fixtures_path = plugin_path .. '/test/fixtures/angular-test-app/src/app'

---Get full path to a fixture file
---@param relative_path string
---@return string
function M.get_fixture_path(relative_path)
  return M.fixtures_path .. '/' .. relative_path
end

---Open a fixture file and return its buffer number
---@param relative_path string
---@return number bufnr
function M.open_fixture(relative_path)
  local full_path = M.get_fixture_path(relative_path)
  vim.cmd('edit ' .. vim.fn.fnameescape(full_path))
  return vim.api.nvim_get_current_buf()
end

---Create a scratch buffer with the given content
---@param content string Content to set (newline-separated)
---@return number bufnr
function M.create_buffer_with_content(content)
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = vim.split(content, '\n')
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

---Wait for a condition to be true
---@param condition fun(): boolean
---@param timeout_ms number|nil Timeout in milliseconds (default 5000)
---@param interval_ms number|nil Check interval in milliseconds (default 50)
---@return boolean success
function M.wait_for(condition, timeout_ms, interval_ms)
  timeout_ms = timeout_ms or 5000
  interval_ms = interval_ms or 50
  local start = vim.loop.hrtime()

  while (vim.loop.hrtime() - start) / 1e6 < timeout_ms do
    if condition() then
      return true
    end
    vim.wait(interval_ms)
  end

  return false
end

---Wait for a TypeScript LSP client to attach to a buffer
---@param bufnr number Buffer number
---@param timeout_ms number|nil Timeout in milliseconds (default 10000)
---@return boolean success
function M.wait_for_lsp(bufnr, timeout_ms)
  timeout_ms = timeout_ms or 10000

  return M.wait_for(function()
    local clients = vim.lsp.get_clients({ bufnr = bufnr })
    for _, client in ipairs(clients) do
      if client.name == 'ts_ls' or client.name == 'typescript-tools' or client.name == 'vtsls' then
        return true
      end
    end
    return false
  end, timeout_ms)
end

---Wait for an Angular LSP client to attach to a buffer
---@param bufnr number Buffer number
---@param timeout_ms number|nil Timeout in milliseconds (default 15000)
---@return boolean success
function M.wait_for_angular_lsp(bufnr, timeout_ms)
  timeout_ms = timeout_ms or 15000

  return M.wait_for(function()
    local clients = vim.lsp.get_clients({ bufnr = bufnr })
    for _, client in ipairs(clients) do
      if client.name == 'angularls' or client.name == 'angular' then
        return true
      end
    end
    return false
  end, timeout_ms)
end

---Get all extmarks in a buffer
---@param bufnr number Buffer number
---@param namespace number|nil Namespace ID (default: angular-refs namespace)
---@return table[] extmarks
function M.get_extmarks(bufnr, namespace)
  namespace = namespace or vim.api.nvim_create_namespace('angular-refs')
  return vim.api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, { details = true })
end

---Get virtual text at a specific line
---@param bufnr number Buffer number
---@param line number Line number (0-indexed)
---@param namespace number|nil Namespace ID
---@return string|nil text
function M.get_virtual_text_at_line(bufnr, line, namespace)
  local extmarks = M.get_extmarks(bufnr, namespace)
  for _, mark in ipairs(extmarks) do
    if mark[2] == line then
      local details = mark[4]
      if details and details.virt_text then
        local text_parts = {}
        for _, part in ipairs(details.virt_text) do
          table.insert(text_parts, part[1])
        end
        return table.concat(text_parts, '')
      end
    end
  end
  return nil
end

---Find the first line matching a pattern
---@param bufnr number Buffer number
---@param pattern string Lua pattern
---@return number|nil line 0-indexed line number
function M.find_line_with_pattern(bufnr, pattern)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    if line:match(pattern) then
      return i - 1
    end
  end
  return nil
end

---Find the line where a symbol is defined
---@param bufnr number Buffer number
---@param symbol_name string Symbol name
---@return number|nil line 0-indexed line number
function M.find_symbol_line(bufnr, symbol_name)
  local patterns = {
    symbol_name .. '%s*=',
    symbol_name .. '%s*:',
    symbol_name .. '%s*%(',
    'function%s+' .. symbol_name,
    'get%s+' .. symbol_name,
    'set%s+' .. symbol_name,
  }

  for _, pattern in ipairs(patterns) do
    local line = M.find_line_with_pattern(bufnr, pattern)
    if line then
      return line
    end
  end

  return nil
end

---Setup angular-refs with optional config
---@param opts table|nil Configuration options
---@return table|nil module
function M.setup_angular_refs(opts)
  local ok, angular_refs = pcall(require, 'angular-refs')
  if ok and angular_refs then
    angular_refs.setup(opts or {})
    return angular_refs
  end
  return nil
end

---Refresh angular-refs and wait for completion
function M.refresh_angular_refs()
  vim.cmd('AngularRefsRefresh')
  vim.wait(1000)
end

---Get display results for a buffer
---@param bufnr number Buffer number
---@return table|nil results
function M.get_display_results(bufnr)
  local ok, display = pcall(require, 'angular-refs.display')
  if ok and display.get_results then
    return display.get_results(bufnr)
  end
  return nil
end

---Assert that a symbol has a specific reference count
---@param bufnr number Buffer number
---@param symbol_name string Symbol name
---@param expected_count number Expected count
function M.assert_ref_count(bufnr, symbol_name, expected_count)
  local results = M.get_display_results(bufnr)
  if not results then
    error('Could not get display results')
  end

  local actual = results[symbol_name]
  if actual ~= expected_count then
    error(
      string.format(
        'Expected %s to have %d refs, but got %s',
        symbol_name,
        expected_count,
        actual and tostring(actual) or 'nil'
      )
    )
  end
end

---Assert that virtual text at a line contains expected text
---@param bufnr number Buffer number
---@param line number Line number (0-indexed)
---@param expected_text string Text to find
function M.assert_virtual_text_contains(bufnr, line, expected_text)
  local virt_text = M.get_virtual_text_at_line(bufnr, line)
  if not virt_text then
    error(string.format('No virtual text found at line %d', line))
  end
  if not virt_text:find(expected_text, 1, true) then
    error(string.format('Expected virtual text to contain "%s", but got "%s"', expected_text, virt_text))
  end
end

---Create a test context for managing test buffers
---@return table context
function M.create_test_context()
  return {
    buffers = {},
    add_buffer = function(self, bufnr)
      table.insert(self.buffers, bufnr)
    end,
    cleanup = function(self)
      for _, bufnr in ipairs(self.buffers) do
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_delete(bufnr, { force = true })
        end
      end
      self.buffers = {}
    end,
  }
end

return M
