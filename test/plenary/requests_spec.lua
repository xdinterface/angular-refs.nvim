local requests = require("angular-refs.requests")

describe("bounded request groups", function()
	it("limits in-flight requests and drains queued work", function()
		local callbacks, count = {}, 0
		local client = {
			request = function(_, _, _, cb)
				count = count + 1
				callbacks[count] = cb
				return true, count
			end,
		}
		local group = requests.new(2)
		for _ = 1, 5 do
			group:request(client, "test", {}, function() end)
		end
		assert.equals(2, count)
		callbacks[1](nil, {})
		assert.equals(3, count)
		callbacks[2](nil, {})
		callbacks[3](nil, {})
		assert.equals(5, count)
		group:cancel()
	end)
	it("cancels requests and suppresses late callbacks and queued work", function()
		local callback, cancelled, delivered = nil, nil, false
		local client = {
			request = function(_, _, _, cb)
				callback = cb
				return true, 42
			end,
			cancel_request = function(_, id)
				cancelled = id
			end,
		}
		local group = requests.new(1)
		group:request(client, "test", {}, function()
			delivered = true
		end)
		group:request(client, "test", {}, function()
			delivered = true
		end)
		group:cancel()
		callback(nil, {})
		assert.equals(42, cancelled)
		assert.is_false(delivered)
	end)
	it("delivers transport rejection as an error", function()
		local called = false
		requests.new():request(
			{
				request = function()
					return false
				end,
			},
			"test",
			{},
			function(err)
				called = true
				assert.is_not_nil(err)
			end
		)
		assert.is_true(called)
	end)
end)
