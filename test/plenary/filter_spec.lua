local filter = require("angular-refs.filter")
local config = require("angular-refs.config")

describe("asynchronous exclusions", function()
	local original_system, original_root, calls
	before_each(function()
		config.setup()
		filter.clear_cache()
		original_system, original_root = vim.system, vim.fs.root
		calls = {}
		vim.fs.root = function(path)
			return path:match("^/tmp/repo%-a") and "/tmp/repo-a" or "/tmp/repo-b"
		end
		vim.system = function(command, opts, cb)
			table.insert(calls, { command = command, opts = opts, cb = cb })
		end
	end)
	after_each(function()
		vim.system, vim.fs.root = original_system, original_root
		filter.clear_cache()
		config.setup()
	end)
	it("batches by repository root and does not invoke Git on the hot path", function()
		local finished = false
		filter.prepare({ "/tmp/repo-a/a.ts", "/tmp/repo-a/b.ts", "/tmp/repo-b/a.ts" }, function()
			finished = true
		end)
		assert.equals(2, #calls)
		for _, call in ipairs(calls) do
			local root = call.command[3]
			call.cb({ code = 0, stdout = root .. "/a.ts\0" })
		end
		vim.wait(100, function()
			return finished
		end)
		assert.is_true(finished)
		assert.is_true(filter.should_exclude("/tmp/repo-a/a.ts"))
		assert.is_false(filter.should_exclude("/tmp/repo-a/b.ts"))
		assert.equals(2, #calls)
	end)
	it("reports a failed Git check instead of caching it as success", function()
		local message
		filter.prepare({ "/tmp/repo-a/a.ts" }, function(err)
			message = err
		end)
		calls[1].cb({ code = 128 })
		vim.wait(100, function()
			return message ~= nil
		end)
		assert.equals("Git exclusion check failed", message)
	end)
end)
