---@class TestHelpers
local M = {}

local plugin_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
M.fixtures_path = plugin_path .. '/test/fixtures/angular-test-app/src/app'

---@param relative_path string
---@return string
function M.get_fixture_path(relative_path)
  return M.fixtures_path .. '/' .. relative_path
end

---@param relative_path string
---@return number bufnr
function M.open_fixture(relative_path)
  local full_path = M.get_fixture_path(relative_path)
  vim.cmd('edit ' .. vim.fn.fnameescape(full_path))
  return vim.api.nvim_get_current_buf()
end

---@param content string
---@return number bufnr
function M.create_buffer_with_content(content)
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = vim.split(content, '\n')
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

---@param bufnr number
---@param pattern string
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

---@param bufnr number
---@param symbol_name string
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
