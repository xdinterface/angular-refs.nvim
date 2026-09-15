local M = {}
local config = require("angular-refs.config")
local clients = require("angular-refs.clients")
local display = require("angular-refs.display")

local function eligible(buf)
	local name = vim.api.nvim_buf_get_name(buf)
	return name:match("%.ts$")
		and not name:match("%.spec%.ts$")
		and not name:match("%.test%.ts$")
		and clients.get_angular(buf) ~= nil
end

function M.setup(opts)
	config.setup(opts)
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		display.clear(buf)
	end
	if opts and opts.comprehensive_mode ~= nil then
		vim.notify(
			"angular-refs: comprehensive_mode is deprecated; TS and Angular references are always combined",
			vim.log.levels.WARN
		)
	end
	local group = vim.api.nvim_create_augroup("AngularRefs", { clear = true })
	local function autocmd(events, pattern, callback)
		vim.api.nvim_create_autocmd(events, { group = group, pattern = pattern, callback = callback })
	end
	local function refresh(args)
		if config.is_enabled() and eligible(args.buf) then
			display.schedule_update(args.buf)
		end
	end
	if config.get().trigger.on_open then
		autocmd("BufEnter", "*.ts", refresh)
	end
	autocmd({ "CursorHold", "InsertLeave" }, "*.ts", refresh)
	autocmd("LspAttach", nil, refresh)
	autocmd("LspDetach", nil, function(args)
		display.clear(args.buf)
		vim.schedule(function()
			if vim.api.nvim_buf_is_valid(args.buf) then
				refresh(args)
			end
		end)
	end)
	autocmd("BufWipeout", nil, function(args)
		display.clear(args.buf)
	end)
	autocmd({ "TextChanged", "TextChangedI", "FileChangedShellPost" }, { "*.ts", "*.html" }, function()
		display.invalidate()
	end)
	if config.get().trigger.on_save then
		autocmd("BufWritePost", { "*.ts", "*.html" }, function(args)
			display.invalidate()
			refresh(args)
		end)
	end
	autocmd("BufWritePost", { ".gitignore", "tsconfig*.json", "angular.json", "package.json" }, function()
		require("angular-refs.filter").clear_cache()
		display.invalidate()
	end)
	autocmd("FocusGained", nil, function()
		require("angular-refs.filter").clear_cache()
		display.invalidate()
	end)
	local function command(name, fn, desc)
		vim.api.nvim_create_user_command("AngularRefs" .. name, fn, { desc = desc, force = true })
	end
	command("Refresh", function()
		require("angular-refs.filter").clear_cache()
		display.invalidate()
		display.update(vim.api.nvim_get_current_buf())
	end, "Invalidate and refresh reference analysis")
	command("Status", function()
		local buf = vim.api.nvim_get_current_buf()
		local report = display.get_report(buf)
		local ts, angular = clients.get_typescript(buf), clients.get_angular(buf)
		local function describe(client)
			if not client then
				return "unavailable"
			end
			local info = client.server_info or {}
			return client.name
				.. (info.version and " " .. info.version or "")
				.. (client.initialized and " (initialized)" or " (starting)")
		end
		local lines = {
			"Angular refs: " .. (config.is_enabled() and "enabled" or "disabled"),
			"TypeScript: " .. describe(ts) .. "; Angular: " .. describe(angular),
			"Analysis: " .. (report and report.state or "not analyzed"),
		}
		local reasons = {}
		if report then
			if report.scope then
				table.insert(lines, "Scope: " .. report.scope)
			end
			for _, message in ipairs(report.reasons or {}) do
				reasons[message] = true
			end
			for _, result in ipairs(report.results) do
				for _, message in ipairs(result.reasons) do
					reasons[message] = true
				end
			end
		end
		for _, message in ipairs(vim.fn.sort(vim.tbl_keys(reasons))) do
			table.insert(lines, "- " .. message)
		end
		vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
	end, "Show providers, scope and incomplete analysis reasons")
	command("Unused", function()
		local unused, state = display.get_unused()
		if #unused == 0 then
			vim.notify(
				state == "complete" and "No unused symbols found in the analyzed scope"
					or "Unused analysis is " .. state .. "; zero references do not establish unused status",
				vim.log.levels.INFO
			)
			if state == "not analyzed" or state == "stale" then
				display.update()
			end
			return
		end
		local items = {}
		for _, item in ipairs(unused) do
			table.insert(items, {
				bufnr = vim.api.nvim_get_current_buf(),
				lnum = item.line,
				col = item.col,
				text = string.format("[%s] %s", item.kind, item.name),
			})
		end
		vim.fn.setqflist({}, " ", { title = "Verified unused symbols", items = items })
		vim.cmd("copen")
	end, "List verified unused symbols only")
	command("DumpTcb", function()
		require("angular-refs.server").dump_tcb(vim.api.nvim_get_current_buf())
	end, "Dump compiler-generated code for diagnostics, not usage counts")
	command("Toggle", function()
		config.get().enabled = not config.is_enabled()
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			display.clear(buf)
			if config.is_enabled() and eligible(buf) then
				display.schedule_update(buf)
			end
		end
		vim.notify("Angular refs: " .. (config.is_enabled() and "enabled" or "disabled"))
	end, "Toggle reference analysis")
end

return M
