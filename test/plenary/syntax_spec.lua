local syntax = require("angular-refs.syntax")

describe("optional syntax evidence", function()
	it("degrades safely when the parser is unavailable", function()
		local original = vim.treesitter.get_parser
		vim.treesitter.get_parser = function()
			error("not installed")
		end
		local result = syntax.inspect(0)
		vim.treesitter.get_parser = original
		assert.is_false(result.available)
	end)
	-- The live matrix additionally tests these classifications with a real parser.
	if vim.env.AR_TS_PARSER then
		before_each(function()
			vim.treesitter.language.add("typescript", { path = vim.env.AR_TS_PARSER })
		end)
		it("recognizes aliases, inheritance, sibling method decorators and signal factories", function()
			local buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
				"import { Component as C, HostListener, input } from '@angular/core';",
				'@C({template: ""}) class Base { ngOnInit() {} }',
				"class Derived extends Base { ngOnDestroy() {} }",
				"class Plain { ngOnInit() {} }",
				'@C({template: ""}) class Other {',
				"  field = input.required<string>();",
				'  @HostListener("click") onClick() {}',
				"}",
			})
			local result = syntax.inspect(buf)
			vim.api.nvim_buf_delete(buf, { force = true })
			assert.is_true(result.available)
			local declarations = result.declarations
			assert.is_true(declarations[1].lifecycle)
			assert.is_true(declarations[2].lifecycle)
			assert.is_false(declarations[3].lifecycle)
			assert.is_true(declarations[4].implicit)
			assert.is_true(declarations[5].implicit)
		end)
		it("records arrow initializer definitions and computed access without counting them", function()
			local buf = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(
				buf,
				0,
				-1,
				false,
				{ "class A { arrow = () => {}; call(key: string) { this[key](); } }" }
			)
			local result = syntax.inspect(buf)
			vim.api.nvim_buf_delete(buf, { force = true })
			assert.is_true(result.dynamic)
			assert.is_not_nil(result.declarations[1].definition_range)
		end)
	end
end)
