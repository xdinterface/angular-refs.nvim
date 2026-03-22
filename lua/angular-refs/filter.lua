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

  -- Use git check-ignore (respects all .gitignore files in the tree)
  vim.fn.system({ "git", "check-ignore", "-q", filepath })
  local ignored = vim.v.shell_error == 0
  gitignore_cache[filepath] = ignored
  return ignored
end

---Clear the gitignore cache
function M.clear_cache()
  gitignore_cache = {}
end

return M
