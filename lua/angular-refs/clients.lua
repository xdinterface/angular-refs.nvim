local M = {}

M.TS_CLIENT_NAMES = { "typescript-tools", "ts_ls", "vtsls", "typescript-language-server", "tsserver" }
M.ANGULAR_CLIENT_NAMES = { "angularls", "angular" }

---Select an attached client in preference order. Never cross workspace boundaries.
---@param bufnr number|nil
---@param names string[]
---@return table|nil
local function find(bufnr, names)
	if bufnr then
		for _, name in ipairs(names) do
			local clients = vim.lsp.get_clients({ bufnr = bufnr, name = name })
			if #clients > 0 then
				return clients[1]
			end
		end
	end
end

function M.get_typescript(bufnr)
	return find(bufnr, M.TS_CLIENT_NAMES)
end

function M.get_angular(bufnr)
	return find(bufnr, M.ANGULAR_CLIENT_NAMES)
end

return M
