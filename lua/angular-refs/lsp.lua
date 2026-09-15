local M = {}
local clients = require("angular-refs.clients")

---@class Symbol
---@field name string
---@field line number 0-indexed line number
---@field col number 0-indexed column
---@field kind string Symbol kind

---Get symbols via LSP documentSymbol
---@param bufnr number
---@param callback fun(symbols: Symbol[])
function M.get_symbols(bufnr, callback)
  local params = { textDocument = vim.lsp.util.make_text_document_params(bufnr) }

  local ts_client = clients.get_typescript(bufnr)

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
            local child_line = child_range.start.line
            -- Skip underscore-prefixed members (convention for private)
            if not child_name:match("^_") then
              table.insert(symbols, {
                name = child_name,
                line = child_line,
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


---@class LspReference
---@field file string Full file path
---@field line number 1-indexed line number
---@field column number 1-indexed column number
---@field context string Line content for preview

---Get references for a symbol via LSP
---@param bufnr number Buffer number
---@param line number 0-indexed line number
---@param col number 0-indexed column number
---@param callback fun(refs: LspReference[])
---@param local_only boolean|nil If true, only return refs from the same file (for lifecycle methods)
function M.get_references(bufnr, line, col, callback, local_only)
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
    position = { line = line, character = col },
    context = { includeDeclaration = false },
  }

  local ts_client = clients.get_typescript(bufnr)

  if not ts_client then
    callback({})
    return
  end

  ts_client.request("textDocument/references", params, function(err, result)
    local cfg = require("angular-refs.config").get()
    local filter = require("angular-refs.filter")

    if err or not result then
      if cfg.debug then
        vim.notify("angular-refs: References error or no result for line " .. line, vim.log.levels.DEBUG)
      end
      callback({})
      return
    end

    if cfg.debug then
      vim.notify("angular-refs: Raw references count: " .. #result .. " for line " .. line, vim.log.levels.DEBUG)
    end

    local refs = {}
    local current_file = vim.api.nvim_buf_get_name(bufnr)
    local filtered_count = 0

    for _, location in ipairs(result) do
      local uri = location.uri or location.targetUri
      local range = location.range or location.targetRange

      if uri and range then
        local file = vim.uri_to_fname(uri)

        -- Skip excluded paths (node_modules, dist, gitignored files, etc.)
        -- For local_only mode, also skip files that aren't the current file
        local skip = filter.should_exclude(file)
        if local_only and file ~= current_file then
          skip = true
        end

        if skip then
          filtered_count = filtered_count + 1
        else
          local ref_line = range.start.line + 1 -- Convert to 1-indexed
          local ref_col = range.start.character + 1

          -- Skip the definition itself (same file and same line)
          local is_definition = file == current_file and range.start.line == line

          if not is_definition then
            local context = M.get_line_content(file, ref_line)

            table.insert(refs, {
              file = file,
              line = ref_line,
              column = ref_col,
              context = context,
            })
          end
        end
      end
    end

    if cfg.debug then
      vim.notify("angular-refs: Line " .. line .. ": " .. #refs .. " refs (filtered " .. filtered_count .. " excluded)", vim.log.levels.DEBUG)
    end

    callback(refs)
  end, bufnr)
end

---Get line content from a file
---@param file string File path
---@param line_num number 1-indexed line number
---@return string
function M.get_line_content(file, line_num)
  local bufnr = vim.fn.bufnr(file)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    local lines = vim.api.nvim_buf_get_lines(bufnr, line_num - 1, line_num, false)
    if #lines > 0 then
      return vim.trim(lines[1])
    end
  end

  local ok, lines = pcall(vim.fn.readfile, file, "", line_num)
  if ok and lines and #lines >= line_num then
    return vim.trim(lines[line_num])
  end

  return ""
end

return M
