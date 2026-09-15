local lsp = require("angular-refs.lsp")
local clients = require("angular-refs.clients")
local syntax = require("angular-refs.syntax")
local locations = require("angular-refs.locations")

describe("source-based symbol discovery", function()
	local buf, original_clients, original_syntax, response
	local function range(col, finish)
		return { start = { line = 0, character = col }, ["end"] = { line = 0, character = finish } }
	end
	before_each(function()
		buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. ".ts")
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "class A { save() {} } class B { save() {} }" })
		original_clients, original_syntax = vim.lsp.get_clients, syntax.inspect
		syntax.inspect = function()
			return { available = false }
		end
		local client = {
			name = "typescript-tools",
			offset_encoding = "utf-8",
			request = function(self, method, _, cb)
				assert.equals("typescript-tools", self.name)
				assert.equals("textDocument/documentSymbol", method)
				cb(nil, response)
				return true, 1
			end,
		}
		vim.lsp.get_clients = function(opts)
			return opts.name == "typescript-tools" and { client } or {}
		end
		response = {
			{
				name = "A",
				kind = 5,
				range = range(0, 20),
				children = {
					{ name = "save", kind = 6, range = range(10, 19), selectionRange = range(10, 14) },
				},
			},
			{
				name = "B",
				kind = 5,
				range = range(22, 43),
				children = {
					{ name = "save", kind = 6, range = range(32, 41), selectionRange = range(32, 36) },
				},
			},
		}
	end)
	after_each(function()
		vim.lsp.get_clients, syntax.inspect = original_clients, original_syntax
		vim.api.nvim_buf_delete(buf, { force = true })
	end)
	it("keeps same-line members of different owners separate and uses selectionRange", function()
		lsp.get_symbols(buf, function(symbols, err)
			assert.is_nil(err)
			assert.equals(2, #symbols)
			assert.is_true(symbols[1].precise)
			assert.is_true(symbols[2].precise)
			assert.not_equals(symbols[1].id, symbols[2].id)
			assert.equals(32, symbols[2].col)
		end)
	end)
	it("does not silently query an imprecise declaration range", function()
		response[1].children[1].selectionRange = nil
		lsp.get_symbols(buf, function(symbols)
			assert.is_false(symbols[1].precise)
		end)
	end)
	it("distinguishes unavailable discovery from a successful empty response", function()
		vim.lsp.get_clients = function()
			return {}
		end
		lsp.get_symbols(buf, function(symbols, err)
			assert.same({}, symbols)
			assert.is_not_nil(err)
		end)
	end)
	it("keeps attachment checks local", function()
		vim.lsp.get_clients = function(opts)
			return not opts.bufnr and { { name = "angular" } } or {}
		end
		assert.is_nil(clients.get_angular(buf))
	end)
	it("converts UTF-16 positions through bytes without losing Unicode offsets", function()
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "😀save" })
		local uri = vim.uri_from_bufnr(buf)
		assert.same(
			{ line = 0, character = 4 },
			locations.position(uri, { line = 0, character = 2 }, "utf-16", "utf-8")
		)
		assert.same(
			{ line = 0, character = 2 },
			locations.position(uri, { line = 0, character = 4 }, "utf-8", "utf-16")
		)
	end)
end)
