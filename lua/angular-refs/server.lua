-- Compiler diagnostics only. Generated TCB occurrences are not usage counts.
local M = {}

function M.dump_tcb(bufnr)
	local client = require("angular-refs.clients").get_angular(bufnr)
	if not client then
		vim.notify("angular-refs: Angular LSP is not attached to this buffer", vim.log.levels.WARN)
		return
	end
	local win = vim.fn.bufwinid(bufnr)
	if win == -1 then
		vim.notify("angular-refs: Open the component or template in a window first", vim.log.levels.WARN)
		return
	end
	local params = vim.lsp.util.make_position_params(win, client.offset_encoding)
	local group = require("angular-refs.requests").new(1)
	local timer = vim.fn.timer_start(require("angular-refs.config").get().analysis.timeout_ms, function()
		group:cancel()
		vim.schedule(function()
			vim.notify("angular-refs: TCB request timed out", vim.log.levels.WARN)
		end)
	end)
	group:request(client, "angular/getTcb", params, function(err, result)
		vim.fn.timer_stop(timer)
		group:cancel()
		if err or not result or not result.content then
			vim.notify(
				"angular-refs: No TCB at this position; place the cursor inside a component or its template",
				vim.log.levels.WARN
			)
			return
		end
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(result.content, "\n"))
		vim.bo[buf].filetype = "typescript"
		vim.bo[buf].modifiable = false
		vim.cmd("vsplit")
		vim.api.nvim_win_set_buf(0, buf)
	end, bufnr)
end

return M
