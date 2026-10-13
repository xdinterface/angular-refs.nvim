local M = {}

local config = require("angular-refs.config")
local classify = require("angular-refs.classify")

local ns_id = vim.api.nvim_create_namespace("angular-refs")

local HIGHLIGHT_GROUPS = { "AngularRefsCount", "AngularRefsUnused", "AngularRefsTestsOnly", "AngularRefsFramework" }

---@class AngularRefsEntry
---@field symbol AngularRefsSymbol
---@field counts AngularRefsCounts

---@type table<integer, {symbol: AngularRefsSymbol, state: AngularRefsState}[]>
local rendered = {}

function M.setup_highlights()
  for _, group in ipairs(HIGHLIGHT_GROUPS) do
    vim.api.nvim_set_hl(0, group, { link = "Comment", default = true })
  end
end

---@param text string
---@return integer
local function indent_width(text)
  return vim.fn.strdisplaywidth(text:match("^%s*"))
end

---Whether a line between two labelled lines keeps them in one block: blank lines, JSDoc
---continuation lines and lines at the block's indent (fields, comments, decorators).
---Nested code such as a method body is indented deeper and ends the block.
---@param text string
---@param indent integer
---@return boolean
local function continues_block(text, indent)
  return text:match("^%s*$") ~= nil or text:match("^%s*%*") ~= nil or indent_width(text) == indent
end

---Spaces to add after each labelled row so the labels of a block share one column
---@param bufnr integer
---@param rows integer[] Sorted, distinct, 0-indexed
---@return table<integer, integer>
local function block_padding(bufnr, rows)
  local padding = {}
  -- strdisplaywidth measures tabs with the current buffer's 'tabstop'
  vim.api.nvim_buf_call(bufnr, function()
    local first = rows[1]
    local lines = vim.api.nvim_buf_get_lines(bufnr, first, rows[#rows] + 1, false)
    local function line_at(row)
      return lines[row - first + 1]
    end

    local block, widest = {}, 0
    local function close_block()
      for _, item in ipairs(block) do
        padding[item.row] = widest - item.width
      end
      block, widest = {}, 0
    end

    for i, row in ipairs(rows) do
      local text = line_at(row)
      local indent = indent_width(text)
      if i > 1 then
        local previous = rows[i - 1]
        local joins = indent_width(line_at(previous)) == indent
        for between = previous + 1, row - 1 do
          joins = joins and continues_block(line_at(between), indent)
        end
        if not joins then
          close_block()
        end
      end
      local width = vim.fn.strdisplaywidth(text)
      table.insert(block, { row = row, width = width })
      widest = math.max(widest, width)
    end
    close_block()
  end)
  return padding
end

---@param bufnr integer
---@param row integer
---@return string
local function indentation(bufnr, row)
  local text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  return string.rep(" ", vim.api.nvim_buf_call(bufnr, function()
    return indent_width(text)
  end))
end

---Replace a buffer's labels
---@param bufnr integer
---@param entries AngularRefsEntry[]
function M.render(bufnr, entries)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  local display = config.get().display
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local above = display.position == "above"
  local states = {}

  local rows, seen = {}, {}
  for _, entry in ipairs(entries) do
    local row = entry.symbol.line
    if row < line_count and not seen[row] then
      seen[row] = true
      table.insert(rows, row)
    end
  end
  table.sort(rows)
  local padding = (display.align and not above and #rows > 0) and block_padding(bufnr, rows) or {}

  for _, entry in ipairs(entries) do
    local state, text, hl = classify.label(entry.symbol, entry.counts)
    table.insert(states, { symbol = entry.symbol, state = state })

    local row = entry.symbol.line
    if row < line_count then
      local opts = { hl_mode = "combine" }
      if above then
        opts.virt_lines = { { { indentation(bufnr, row) .. text, hl } } }
        opts.virt_lines_above = true
      else
        -- Only the first label on a row is padded; later ones follow it
        local pad = padding[row] or 0
        padding[row] = 0
        opts.virt_text = { { string.rep(" ", pad) .. display.separator .. text, hl } }
        opts.virt_text_pos = "eol"
      end
      vim.api.nvim_buf_set_extmark(bufnr, ns_id, row, 0, opts)
    end
  end

  rendered[bufnr] = states
end

---@param bufnr integer
function M.clear(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  end
  rendered[bufnr] = nil
end

function M.clear_all()
  for bufnr in pairs(rendered) do
    M.clear(bufnr)
  end
end

---Deletion candidates of the last render: unused and tests-only symbols
---@param bufnr integer
---@return {name: string, line: integer, kind: string, tests_only: boolean}[]
function M.unused(bufnr)
  local list = {}
  for _, item in ipairs(rendered[bufnr] or {}) do
    if item.state == "unused" or item.state == "tests_only" then
      table.insert(list, {
        name = item.symbol.name,
        line = item.symbol.line + 1,
        kind = item.symbol.kind,
        tests_only = item.state == "tests_only",
      })
    end
  end
  table.sort(list, function(a, b)
    return a.line < b.line
  end)
  return list
end

return M
