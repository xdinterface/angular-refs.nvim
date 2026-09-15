-- AR_TEST_ROOT=<prepared fixture> AR_TS_PROVIDER=ts_ls|vtsls|typescript-tools
-- nvim --headless -i NONE -u test/minimal_init.lua -l test/live/run.lua
local root = assert(vim.env.AR_TEST_ROOT, "AR_TEST_ROOT is required")
local provider = vim.env.AR_TS_PROVIDER or "ts_ls"
local function run()
	if vim.env.AR_TS_PARSER then
		vim.treesitter.language.add("typescript", { path = vim.env.AR_TS_PARSER })
	end
	require("angular-refs.config").setup({ exclude = { respect_gitignore = false }, analysis = { timeout_ms = 60000 } })
	local angular_id = assert(vim.lsp.start({
		name = "angularls",
		root_dir = root,
		cmd = {
			root .. "/node_modules/.bin/ngserver",
			"--stdio",
			"--tsProbeLocations",
			root,
			"--ngProbeLocations",
			root,
		},
	}, { attach = false }))
	local ts_id
	if provider == "typescript-tools" then
		vim.opt.rtp:prepend(assert(vim.env.AR_TS_TOOLS, "AR_TS_TOOLS is required"))
		require("typescript-tools").setup({
			root_dir = root,
			settings = { tsserver_path = root .. "/node_modules/typescript/lib/tsserver.js" },
		})
	else
		ts_id = assert(vim.lsp.start({
			name = provider,
			root_dir = root,
			cmd = {
				root .. "/node_modules/.bin/" .. (provider == "vtsls" and "vtsls" or "typescript-language-server"),
				"--stdio",
			},
			init_options = { tsserver = { path = root .. "/node_modules/typescript/lib/tsserver.js" } },
			settings = {
				typescript = { tsdk = root .. "/node_modules/typescript/lib" },
				vtsls = { autoUseWorkspaceTsdk = true },
			},
		}, { attach = false }))
	end
	local buffers = {}
	for _, name in ipairs({ "app.ts", "child.ts", "ownership.ts", "types.ts" }) do
		vim.cmd.edit(root .. "/" .. name)
		local buf = vim.api.nvim_get_current_buf()
		vim.bo[buf].filetype = "typescript"
		buffers[name] = buf
		vim.lsp.buf_attach_client(buf, angular_id)
		if ts_id then
			vim.lsp.buf_attach_client(buf, ts_id)
		end
	end
	assert(
		vim.wait(30000, function()
			for _, buf in pairs(buffers) do
				local ts = require("angular-refs.clients").get_typescript(buf)
				if not ts or not ts.initialized then
					return false
				end
			end
			return vim.lsp.get_client_by_id(angular_id).initialized
		end, 50),
		"Servers did not initialize"
	)
	local reports = {}
	for name, buf in pairs(buffers) do
		local report
		local group = require("angular-refs.requests").new(4)
		require("angular-refs.analysis").run(buf, group, function(value)
			report = value
		end)
		assert(
			vim.wait(60000, function()
				return report ~= nil
			end, 20),
			"Analysis timed out: " .. name
		)
		group:cancel()
		reports[name] = report
		for _, entry in ipairs(report.results) do
			print(
				string.format(
					"%s:%d %s=%d%s",
					name,
					entry.symbol.line + 1,
					entry.symbol.name,
					entry.count,
					entry.hidden and " hidden" or ""
				)
			)
			if entry.symbol.name == vim.env.AR_DEBUG_SYMBOL then
				local ts = require("angular-refs.clients").get_typescript(buf)
				local response = ts:request_sync("textDocument/references", {
					textDocument = { uri = entry.symbol.location.uri },
					position = entry.symbol.location.range.start,
					context = { includeDeclaration = false },
				}, 10000, buf)
				print("DEBUG REFERENCES " .. vim.inspect(response))
				for _, loc in ipairs(response and response.result or {}) do
					print("DEBUG DEFINITION " .. vim.inspect(ts:request_sync("textDocument/definition", {
						textDocument = { uri = loc.uri },
						position = loc.range.start,
					}, 10000, buf)))
				end
			end
		end
	end
	local assertions = 0
	local function check(file, name, row, expected)
		for _, entry in ipairs(reports[file].results) do
			if entry.symbol.name == name and (not row or entry.symbol.line + 1 == row) then
				assert(
					entry.count == expected,
					file
						.. ":"
						.. name
						.. " expected "
						.. expected
						.. ", got "
						.. entry.count
						.. "\n"
						.. vim.inspect(entry)
				)
				assert(not entry.unused, "No whole-workspace coverage proof is available")
				assertions = assertions + 1
				return entry
			end
		end
		error("Missing symbol: " .. file .. ":" .. name)
	end
	check("app.ts", "save", nil, 2)
	check("app.ts", "asyncData$", nil, 2)
	check("app.ts", "twoWayValue", nil, 3)
	check("app.ts", "title", nil, 4)
	check("app.ts", "getItems", nil, 1)
	check("child.ts", "realName", nil, 2)
	check("child.ts", "signalName", nil, 2)
	check("child.ts", "emitSimple", nil, 1)
	check("child.ts", "hostClick", nil, 1)
	check("ownership.ts", "save", 7, 0)
	check("ownership.ts", "save", 12, 3)
	check("types.ts", "callback", nil, 2)
	check("types.ts", "secret", nil, 1)
	check("types.ts", "guarded", nil, 1)
	check("types.ts", "create", nil, 1)
	check("types.ts", "arrow", nil, 1)
	check("types.ts", "overloaded", nil, 1)
	check("types.ts", "value", nil, 2)
	check("types.ts", "first", nil, 1)
	check("types.ts", "second", nil, 2)
	check("types.ts", "parameterProp", nil, 1)
	check("types.ts", "same", 32, 1)
	check("types.ts", "same", 33, 1)
	assert(not check("types.ts", "ngOnInit", nil, 0).hidden, "Ordinary method must not be hidden")
	-- Hand-selected source occurrences, not a snapshot of server output.
	local function exact(file, name, row, expected)
		local entry = check(file, name, row, #expected)
		local actual, wanted = {}, {}
		for _, location in ipairs(entry.locations) do
			table.insert(actual, require("angular-refs.locations").key(location))
		end
		for _, occurrence in ipairs(expected) do
			local path, line, token, occurrence_number = unpack(occurrence)
			local source = vim.fn.readfile(root .. "/" .. path)[line]
			local column, start = nil, 1
			for _ = 1, occurrence_number or 1 do
				column = assert(source:find(token, start, true), "Expected token missing in fixture")
				start = column + #token
			end
			table.insert(
				wanted,
				require("angular-refs.locations").key({
					uri = vim.uri_from_fname(root .. "/" .. path),
					range = {
						start = { line = line - 1, character = column - 1 },
						["end"] = { line = line - 1, character = column - 1 + #token },
					},
				})
			)
		end
		table.sort(actual)
		table.sort(wanted)
		assert(
			vim.deep_equal(actual, wanted),
			"Source location mismatch: "
				.. file
				.. ":"
				.. name
				.. "\nactual="
				.. vim.inspect(actual)
				.. "\nexpected="
				.. vim.inspect(wanted)
		)
	end
	exact("app.ts", "save", nil, { { "app.html", 1, "save" }, { "app.ts", 16, "save" } })
	exact("app.ts", "asyncData$", nil, { { "app.html", 4, "asyncData$" }, { "app.html", 5, "asyncData$" } })
	exact(
		"app.ts",
		"twoWayValue",
		nil,
		{ { "app.html", 2, "twoWayValue" }, { "app.html", 3, "twoWayValue" }, { "app.html", 8, "twoWayValue" } }
	)
	exact("child.ts", "realName", nil, { { "child.ts", 4, "realName" }, { "app.html", 8, "publicName" } })
	exact("child.ts", "signalName", nil, { { "child.ts", 4, "signalName" }, { "app.html", 8, "signalAlias" } })
	exact(
		"ownership.ts",
		"save",
		12,
		{ { "ownership.ts", 3, "save" }, { "ownership.ts", 9, "save" }, { "ownership.ts", 14, "save" } }
	)
	if vim.env.AR_TS_PARSER then
		assert(check("app.ts", "ngOnInit", nil, 0).hidden, "Lifecycle hook must be hidden")
		assert(check("child.ts", "ngOnDestroy", nil, 0).hidden, "Aliased Angular decorator must be recognized")
		assert(check("child.ts", "resize", nil, 0).implicit, "HostListener must be recognized")
		assert(check("types.ts", "transform", nil, 0).implicit, "Pipe entry point must be recognized")
		assert(check("types.ts", "writeValue", nil, 0).implicit, "CVA entry point must be recognized")
	end
	print("PASS: " .. assertions .. " live assertions; provider=" .. provider .. "; Neovim=" .. tostring(vim.version()))
end
local ok, err = xpcall(run, debug.traceback)
for _, client in ipairs(vim.lsp.get_clients()) do
	client:stop(true)
end
if not ok then
	io.stderr:write(err .. "\n")
	vim.cmd("cquit 1")
else
	vim.cmd("qa!")
end
