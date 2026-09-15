local M = {}

---@type table<string, boolean>
local gitignore_cache = {}

---Check if a file matches any exclusion pattern
---@param filepath string
---@return boolean
function M.should_exclude(filepath)
	local cfg = require("angular-refs.config").get()

	-- Check custom patterns first (fast)
	for _, pattern in ipairs(cfg.exclude.patterns) do
		if filepath:match(pattern) then
			return true
		end
	end

	-- Check gitignore if enabled
	if cfg.exclude.respect_gitignore then
		return M.is_gitignored(filepath)
	end

	return false
end

---Check if a file is gitignored (cached)
---@param filepath string
---@return boolean
function M.is_gitignored(filepath)
	if gitignore_cache[filepath] ~= nil then
		return gitignore_cache[filepath]
	end

	-- The hot path is cache-only. Call prepare() before filtering a result batch.
	return false
end

---Populate gitignore results asynchronously, batched by the actual Git root.
function M.prepare(paths, callback)
	if not require("angular-refs.config").get().exclude.respect_gitignore then
		callback()
		return
	end
	local groups = {}
	for _, path in ipairs(paths) do
		if gitignore_cache[path] == nil then
			local root = vim.fs.root(vim.fs.dirname(path), ".git")
			if root then
				groups[root] = groups[root] or {}
				groups[root][path] = true
			else
				gitignore_cache[path] = false
			end
		end
	end
	local pending, failed = vim.tbl_count(groups), false
	if pending == 0 then
		callback()
		return
	end
	local cache = gitignore_cache
	for root, files in pairs(groups) do
		local paths_in_root = vim.tbl_keys(files)
		vim.system(
			{ "git", "-C", root, "check-ignore", "-z", "--stdin" },
			{ stdin = table.concat(paths_in_root, "\0") .. "\0" },
			function(result)
				vim.schedule(function()
					if result.code == 0 or result.code == 1 then
						for _, path in ipairs(paths_in_root) do
							cache[path] = false
						end
						for path in (result.stdout or ""):gmatch("[^%z]+") do
							cache[path] = true
						end
					else
						failed = true
					end
					pending = pending - 1
					if pending == 0 then
						callback(failed and "Git exclusion check failed" or nil)
					end
				end)
			end
		)
	end
end

---Clear the gitignore cache
function M.clear_cache()
	gitignore_cache = {}
end

return M
