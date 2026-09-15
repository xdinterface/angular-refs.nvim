local M = {}

M.TS_CLIENT_NAMES = { "typescript-tools", "ts_ls", "vtsls", "typescript-language-server", "tsserver" }
M.ANGULAR_CLIENT_NAMES = { "angularls", "angular" }

---Select a client in preference order. Global fallback is opt-in because attachment
---checks must only consider the requested buffer.
---@param bufnr number|nil
---@param names string[]
---@param fallback boolean|nil
---@return table|nil
local function find(bufnr, names, fallback)
  if bufnr then
    for _, name in ipairs(names) do
      local clients = vim.lsp.get_clients({ bufnr = bufnr, name = name })
      if #clients > 0 then
        return clients[1]
      end
    end
  end
  if fallback then
    for _, name in ipairs(names) do
      local clients = vim.lsp.get_clients({ name = name })
      if #clients > 0 then
        return clients[1]
      end
    end
  end
end

function M.get_typescript(bufnr)
  return find(bufnr, M.TS_CLIENT_NAMES)
end

function M.get_angular(bufnr, fallback)
  return find(bufnr, M.ANGULAR_CLIENT_NAMES, fallback)
end

function M.is_angular(client)
  return client ~= nil and vim.tbl_contains(M.ANGULAR_CLIENT_NAMES, client.name)
end

return M
