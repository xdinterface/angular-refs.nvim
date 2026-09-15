local config = require("angular-refs.config")
local display = require("angular-refs.display")
local analysis = require("angular-refs.analysis")

describe("refresh lifecycle", function()
	local buf, original_run, original_start, original_stop, callbacks, timer_callbacks
	before_each(function()
		config.setup({ exclude = { respect_gitignore = false } })
		buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. ".ts")
		original_run, original_start, original_stop = analysis.run, vim.fn.timer_start, vim.fn.timer_stop
		callbacks, timer_callbacks = {}, {}
		analysis.run = function(_, group, callback)
			table.insert(callbacks, { group = group, done = callback })
		end
		vim.fn.timer_start = function(_, callback)
			table.insert(timer_callbacks, callback)
			return #timer_callbacks
		end
		vim.fn.timer_stop = function() end
	end)
	after_each(function()
		display.clear(buf)
		analysis.run, vim.fn.timer_start, vim.fn.timer_stop = original_run, original_start, original_stop
		vim.api.nvim_buf_delete(buf, { force = true })
		config.setup()
	end)
	it("cancels and ignores late results after clear", function()
		display.update(buf)
		display.clear(buf)
		assert.is_true(callbacks[1].group.cancelled)
		callbacks[1].done({ results = {}, state = "complete" })
		assert.is_nil(display.get_report(buf))
	end)
	it("queues a refresh requested during an active run", function()
		display.update(buf)
		display.update(buf)
		assert.equals(1, #callbacks)
		callbacks[1].done({ results = {}, state = "complete" })
		timer_callbacks[2]()
		vim.wait(100, function()
			return #callbacks == 2
		end)
		assert.equals(2, #callbacks)
	end)
	it("does not publish results for an older buffer revision", function()
		display.update(buf)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "changed" })
		callbacks[1].done({ results = {}, state = "complete" })
		assert.not_equals("complete", display.get_report(buf).state)
	end)
	it("times out even before symbol discovery responds", function()
		display.update(buf)
		timer_callbacks[1]()
		vim.wait(100, function()
			return callbacks[1].group.cancelled
		end)
		assert.equals("incomplete", display.get_report(buf).state)
		assert.same({}, display.get_unused(buf))
	end)
	it("does not start work when disabled", function()
		config.get().enabled = false
		display.update(buf)
		assert.equals(0, #callbacks)
	end)
	it("ignores a queued timeout after a successful response", function()
		display.update(buf)
		timer_callbacks[1]()
		callbacks[1].done({ results = {}, state = "complete" })
		vim.wait(30, function()
			return false
		end)
		assert.equals("complete", display.get_report(buf).state)
	end)
	it("reuses fresh unchanged results for automatic triggers", function()
		display.update(buf)
		callbacks[1].done({ results = {}, state = "complete" })
		display.schedule_update(buf)
		assert.equals(1, #timer_callbacks)
	end)
	it("does not restart from a scheduled debounce callback after clear", function()
		display.schedule_update(buf)
		timer_callbacks[1]()
		display.clear(buf)
		vim.wait(30, function()
			return false
		end)
		assert.equals(0, #callbacks)
	end)
	it("distinguishes unanalysed buffers from no unused symbols", function()
		local _, state = display.get_unused(buf)
		assert.equals("not analyzed", state)
	end)
	it("renders both declarations on one line with names", function()
		local report = {
			results = {
				{ symbol = { name = "a", line = 0, col = 0 }, count = 2, state = "incomplete" },
				{ symbol = { name = "b", line = 0, col = 5 }, count = 0, state = "incomplete" },
			},
		}
		display.render_results(buf, report)
		local marks =
			vim.api.nvim_buf_get_extmarks(buf, vim.api.nvim_create_namespace("angular-refs"), 0, -1, { details = true })
		assert.equals(1, #marks)
		assert.equals(" | a: 2 usages (incomplete)", marks[1][4].virt_text[1][1])
		assert.equals(" | b: unknown", marks[1][4].virt_text[2][1])
	end)
end)
