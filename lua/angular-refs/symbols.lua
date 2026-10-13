local M = {}

local config = require("angular-refs.config")
local clients = require("angular-refs.clients")

local SK = vim.lsp.protocol.SymbolKind

local TOP_LEVEL_KINDS = {
  [SK.Function] = true,
  [SK.Constant] = true,
  [SK.Variable] = true,
  [SK.Enum] = true,
}

local CONTAINER_KINDS = {
  [SK.Class] = true,
  [SK.Interface] = true,
}

local MEMBER_KINDS = {
  [SK.Method] = true,
  [SK.Property] = true,
  [SK.Field] = true,
}

---@class AngularRefsDecorators
---@field host_listener boolean
---@field host_binding boolean
---@field input_transform boolean
---@field input_alias string|nil

---@class AngularRefsSymbol
---@field name string
---@field line integer 0-indexed, from selectionRange
---@field col integer 0-indexed LSP character, from selectionRange
---@field decl_start {line: integer, character: integer} Start of the declaration incl. decorators
---@field kind string
---@field container string|nil
---@field container_pos {line: integer, character: integer}|nil
---@field container_related boolean Container is an interface or a class with implements/extends
---@field decorators AngularRefsDecorators

---@param name string
---@return boolean
local function is_ignored(name)
  for _, pattern in ipairs(config.get().symbols.ignore) do
    if name:match(pattern) then
      return true
    end
  end
  return false
end

---Buffer text from a symbol's range start up to its name: where its decorators live
---@param item table DocumentSymbol
---@param lines string[]
---@param encoding string
---@return string
local function declaration_prefix(item, lines, encoding)
  local from, to = item.range.start, item.selectionRange.start
  local parts = {}
  for line = from.line, to.line do
    local text = lines[line + 1] or ""
    local first = line == from.line and clients.byte_col(text, from.character, encoding) + 1 or 1
    local last = line == to.line and clients.byte_col(text, to.character, encoding) or #text
    table.insert(parts, text:sub(first, last))
  end
  return table.concat(parts, "\n")
end

---@param prefix string
---@return AngularRefsDecorators
local function parse_decorators(prefix)
  local input_args = prefix:match("@Input%s*(%b())")
  return {
    host_listener = prefix:match("@HostListener%s*%(") ~= nil,
    host_binding = prefix:match("@HostBinding%s*%(") ~= nil,
    input_transform = input_args ~= nil and input_args:match("transform%s*:") ~= nil,
    input_alias = input_args
      and (input_args:match("^%(%s*['\"]([^'\"]+)['\"]") or input_args:match("alias%s*:%s*['\"]([^'\"]+)['\"]")),
  }
end

---Whether the class header (name up to the opening brace) has implements/extends
---@param item table DocumentSymbol of the class
---@param lines string[]
---@return boolean
local function has_heritage(item, lines)
  local header = {}
  for line = item.selectionRange.start.line, #lines - 1 do
    local text = lines[line + 1] or ""
    local brace = text:find("{", 1, true)
    table.insert(header, brace and text:sub(1, brace - 1) or text)
    if brace then
      break
    end
  end
  local text = " " .. table.concat(header, " ") .. " "
  return text:match("%simplements%s") ~= nil or text:match("%sextends%s") ~= nil
end

---@param item table DocumentSymbol
---@param lines string[]
---@param encoding string
---@param container table|nil
---@return AngularRefsSymbol
local function to_symbol(item, lines, encoding, container)
  return {
    name = item.name,
    line = item.selectionRange.start.line,
    col = item.selectionRange.start.character,
    decl_start = { line = item.range.start.line, character = item.range.start.character },
    kind = SK[item.kind] or "unknown",
    container = container and container.item.name,
    container_pos = container and {
      line = container.item.selectionRange.start.line,
      character = container.item.selectionRange.start.character,
    },
    container_related = container ~= nil and container.related,
    decorators = parse_decorators(declaration_prefix(item, lines, encoding)),
  }
end

---Labelled symbols from a hierarchical documentSymbol result
---@param result table[] DocumentSymbol[]
---@param lines string[] Buffer lines
---@param encoding string|nil Client offset encoding, defaults to "utf-16"
---@return AngularRefsSymbol[]
function M.extract(result, lines, encoding)
  encoding = encoding or "utf-16"
  local list = {}
  for _, item in ipairs(result) do
    if item.selectionRange and not is_ignored(item.name) and TOP_LEVEL_KINDS[item.kind] then
      table.insert(list, to_symbol(item, lines, encoding, nil))
    end
    if CONTAINER_KINDS[item.kind] and item.children then
      -- Interface members share references with their implementations, classes through implements/extends
      local container = { item = item, related = item.kind == SK.Interface or has_heritage(item, lines) }
      for _, child in ipairs(item.children) do
        if child.selectionRange and MEMBER_KINDS[child.kind] and not is_ignored(child.name) then
          table.insert(list, to_symbol(child, lines, encoding, container))
        end
      end
    end
  end
  return list
end

---@param bufnr integer
---@param ts_client table
---@param callback fun(symbols: AngularRefsSymbol[]|nil)
function M.fetch(bufnr, ts_client, callback)
  local params = { textDocument = vim.lsp.util.make_text_document_params(bufnr) }
  local ok = clients.request(ts_client, "textDocument/documentSymbol", params, function(err, result)
    if err or not result or not vim.api.nvim_buf_is_valid(bufnr) then
      callback(nil)
      return
    end
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    callback(M.extract(result, lines, ts_client.offset_encoding))
  end, bufnr)
  if not ok then
    callback(nil)
  end
end

return M
