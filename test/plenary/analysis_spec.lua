local analysis = require("angular-refs.analysis")
local lsp = require("angular-refs.lsp")
local config = require("angular-refs.config")

describe("reference ownership and uncertainty", function()
	local buf, original_clients, original_symbols, symbols, ts_refs, ng_refs, defs, requests, result
	local function loc(row, col)
		return {
			uri = vim.uri_from_bufnr(buf),
			range = {
				start = { line = row, character = col },
				["end"] = { line = row, character = col + 4 },
			},
		}
	end
	local function run()
		analysis.run(buf, requests, function(report)
			result = report
		end)
		assert.is_not_nil(result)
		return result.results[1]
	end
	before_each(function()
		buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. ".ts")
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "save save save save", "save save save save" })
		config.setup({ exclude = { respect_gitignore = false } })
		original_clients, original_symbols = vim.lsp.get_clients, lsp.get_symbols
		symbols = {
			{
				id = "A.save",
				name = "save",
				location = loc(0, 0),
				declarations = { loc(0, 0) },
				line = 0,
				col = 0,
				precise = true,
				kind = "Method",
			},
		}
		lsp.get_symbols = function(_, cb)
			cb(symbols, nil, { available = true })
		end
		ts_refs, ng_refs, defs, result = {}, {}, {}, nil
		local function client(name)
			return {
				name = name,
				id = name,
				offset_encoding = "utf-8",
				request = function(self, method, params, cb)
					if method == "textDocument/references" then
						cb(nil, self.name == "typescript-tools" and ts_refs or ng_refs)
					elseif method == "textDocument/definition" then
						local key = self.name .. ":" .. params.position.line .. ":" .. params.position.character
						cb(nil, defs[key] or {})
					else
						error(method)
					end
					return true, 1
				end,
			}
		end
		local ts, angular = client("typescript-tools"), client("angularls")
		vim.lsp.get_clients = function(opts)
			if opts.name == ts.name then
				return { ts }
			end
			if opts.name == angular.name then
				return { angular }
			end
			return {}
		end
		requests = require("angular-refs.requests").new(4)
	end)
	after_each(function()
		requests:cancel()
		vim.lsp.get_clients, lsp.get_symbols = original_clients, original_symbols
		vim.api.nvim_buf_delete(buf, { force = true })
		config.setup()
	end)
	it("deduplicates providers and keeps legitimate same-line calls", function()
		ts_refs, ng_refs = { loc(0, 0), loc(0, 5) }, { loc(0, 0), loc(0, 5), loc(0, 5) }
		defs["angularls:0:5"] = { loc(0, 0) }
		local entry = run()
		assert.equals(1, entry.count)
		assert.equals(5, entry.locations[1].range.start.character)
	end)
	it("rejects sibling implementation calls from a broad reference family", function()
		ng_refs = { loc(1, 0), loc(1, 5) }
		defs["angularls:1:0"], defs["angularls:1:5"] = { loc(0, 0) }, { loc(0, 10) }
		assert.equals(1, run().count)
	end)
	it("uses TS definitions when Angular returns no definition for a TS call", function()
		ng_refs = { loc(1, 0) }
		defs["typescript-tools:1:0"] = { loc(0, 0) }
		assert.equals(1, run().count)
	end)
	it("does not count ambiguous definitions as confirmed implementation usages", function()
		ng_refs = { loc(1, 0) }
		defs["angularls:1:0"] = { loc(0, 0), loc(0, 10) }
		local entry = run()
		assert.equals(0, entry.count)
		assert.is_false(entry.unused)
		assert.is_true(vim.tbl_contains(entry.reasons, "Some reference ownership could not be resolved"))
	end)
	it("does not turn successful empty responses into an unsupported unused claim", function()
		local entry = run()
		assert.equals("incomplete", entry.state)
		assert.is_false(entry.unused)
	end)
	it("hides only lifecycle symbols identified by syntax evidence", function()
		symbols[1].lifecycle = true
		local entry = run()
		assert.is_true(entry.hidden)
		assert.is_false(entry.unused)
	end)
	it("preserves TS calls when comprehensive_mode was configured", function()
		config.get().comprehensive_mode = true
		ts_refs = { loc(1, 0) }
		defs["typescript-tools:1:0"] = { loc(0, 0) }
		assert.equals(1, run().count)
	end)
end)
