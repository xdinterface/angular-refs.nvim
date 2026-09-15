-- A bounded, cancellable request group. One group belongs to one refresh.
local M = {}

function M.new(limit)
	local group = { queue = {}, running = {}, counts = {}, cancelled = false }
	local pump

	function group:cancel()
		self.cancelled = true
		self.queue = {}
		for task in pairs(self.running) do
			if task.id and task.client.cancel_request then
				pcall(task.client.cancel_request, task.client, task.id)
			end
		end
		self.running = {}
	end

	pump = function()
		if group.cancelled or group.pumping then
			return
		end
		group.pumping = true
		local i = 1
		while i <= #group.queue do
			local task = group.queue[i]
			local client = task.client
			if (group.counts[client] or 0) >= (limit or 4) then
				i = i + 1
			else
				table.remove(group.queue, i)
				group.counts[client] = (group.counts[client] or 0) + 1
				group.running[task] = true
				local finished = false
				local function done(err, result)
					if finished then
						return
					end
					finished = true
					group.running[task] = nil
					group.counts[client] = group.counts[client] - 1
					if not group.cancelled then
						task.callback(err, result)
						pump()
					end
				end
				local ok, accepted, id = pcall(client.request, client, task.method, task.params, done, task.bufnr)
				task.id = id
				if not ok and finished then
					error(accepted)
				end
				if not ok or accepted == false then
					done({ message = ok and "Request rejected" or tostring(accepted) })
				end
			end
		end
		group.pumping = false
	end

	function group:request(client, method, params, callback, bufnr)
		if self.cancelled then
			return
		end
		if not client then
			callback({ message = "Language server unavailable" })
			return
		end
		table.insert(
			self.queue,
			{ client = client, method = method, params = params, callback = callback, bufnr = bufnr }
		)
		pump()
	end

	return group
end

return M
