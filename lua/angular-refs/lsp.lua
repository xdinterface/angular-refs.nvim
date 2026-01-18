local M = {}

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
function M.get_references(bufnr, line, col, callback)
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
    position = { line = line, character = col },
    context = { includeDeclaration = false },
  }

  -- Get all LSP clients attached to this buffer that support references
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  local ts_client = nil

  for _, client in ipairs(clients) do
    if client.name == "typescript-tools" or client.name == "ts_ls" or client.name == "vtsls" then
      ts_client = client
      break
    end
  end

  if not ts_client then
    -- No TypeScript LSP client found
    callback({})
    return
  end

  ts_client.request("textDocument/references", params, function(err, result)
    local cfg = require("angular-refs.config").get()

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

        -- Skip node_modules (framework noise like Angular lifecycle hook calls)
        if file:match("node_modules") then
          filtered_count = filtered_count + 1
        else
          local ref_line = range.start.line + 1 -- Convert to 1-indexed
          local ref_col = range.start.character + 1

          -- Skip the definition itself (same file and same line)
          local is_definition = file == current_file and range.start.line == line

          if not is_definition then
            -- Get context (line content)
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
      vim.notify("angular-refs: Line " .. line .. ": " .. #refs .. " refs (filtered " .. filtered_count .. " from node_modules)", vim.log.levels.DEBUG)
    end

    callback(refs)
  end, bufnr)
end

---Get line content from a file
---@param file string File path
---@param line_num number 1-indexed line number
---@return string
function M.get_line_content(file, line_num)
  -- Check if file is loaded in a buffer
  local bufnr = vim.fn.bufnr(file)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    local lines = vim.api.nvim_buf_get_lines(bufnr, line_num - 1, line_num, false)
    if #lines > 0 then
      return vim.trim(lines[1])
    end
  end

  -- Read from disk
  local ok, lines = pcall(vim.fn.readfile, file, "", line_num)
  if ok and lines and #lines >= line_num then
    return vim.trim(lines[line_num])
  end

  return ""
end

return M
