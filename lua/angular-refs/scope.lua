local M = {}

local config = require("angular-refs.config")

-- Angular's build and test output folders, only excluded directly under the project root
local ROOT_OUTPUT_DIRS = { "dist/", "out-tsc/", "coverage/" }

-- Dependency and tooling folders, excluded at any depth
local EXCLUDED_SEGMENTS = { "/node_modules/", "/.angular/" }

---@type table<string, boolean>
local gitignore_cache = {}

---@param path string
---@return boolean
local function is_gitignored(path)
  if gitignore_cache[path] == nil then
    local result = vim.system({ "git", "-C", vim.fs.dirname(path), "check-ignore", "-q", path }):wait()
    gitignore_cache[path] = result.code == 0
  end
  return gitignore_cache[path]
end

---@type table<string, string|false>
local realpath_cache = {}

---@param path string
---@return string|nil
local function realpath(path)
  if realpath_cache[path] == nil then
    realpath_cache[path] = vim.uv.fs_realpath(path) or false
  end
  return realpath_cache[path] or nil
end

---Path relative to root; tolerates a symlinked root or symlinked path (e.g. /tmp -> /private/tmp)
---@param path string
---@param root string
---@return string|nil
local function relative_to(path, root)
  if vim.startswith(path, root .. "/") then
    return path:sub(#root + 2)
  end
  local real_root = realpath(root)
  if real_root and vim.startswith(path, real_root .. "/") then
    return path:sub(#real_root + 2)
  end
  local real_dir = realpath(vim.fs.dirname(path))
  local real_path = real_dir and (real_dir .. "/" .. vim.fs.basename(path))
  local target = real_root or root
  if real_path and vim.startswith(real_path, target .. "/") then
    return real_path:sub(#target + 2)
  end
  return nil
end

---Whether a reference location belongs to the project's own source code
---@param path string Absolute file path
---@param root string|nil Project root without trailing slash
---@return boolean
function M.in_scope(path, root)
  local relative = root and relative_to(path, root)
  if not relative then
    return false
  end
  for _, dir in ipairs(ROOT_OUTPUT_DIRS) do
    if vim.startswith(relative, dir) then
      return false
    end
  end

  local rooted = "/" .. relative
  for _, segment in ipairs(EXCLUDED_SEGMENTS) do
    if rooted:find(segment, 1, true) then
      return false
    end
  end

  if vim.endswith(path, ".d.ts") then
    return false
  end

  local cfg = config.get().scope
  for _, pattern in ipairs(cfg.exclude) do
    if path:match(pattern) then
      return false
    end
  end

  return not (cfg.respect_gitignore and is_gitignored(path))
end

---@param path string
---@return boolean
function M.is_test(path)
  for _, pattern in ipairs(config.get().scope.test_patterns) do
    if path:match(pattern) then
      return true
    end
  end
  return false
end

---Resolve gitignore status for many files with one git process, so in_scope hits the cache
---@param paths string[]
function M.prefetch_gitignore(paths)
  if not config.get().scope.respect_gitignore then
    return
  end

  local unknown, seen = {}, {}
  for _, path in ipairs(paths) do
    if gitignore_cache[path] == nil and not seen[path] then
      seen[path] = true
      table.insert(unknown, path)
    end
  end
  if #unknown == 0 then
    return
  end

  local result = vim.system({ "git", "-C", vim.fs.dirname(unknown[1]), "check-ignore", "--stdin", "-z" }, {
    stdin = table.concat(unknown, "\0") .. "\0",
  }):wait()

  -- Exit 128: git aborted the whole batch (e.g. a path outside the repository).
  -- Leave the paths uncached so is_gitignored resolves them one by one.
  if result.code ~= 0 and result.code ~= 1 then
    return
  end

  local ignored = {}
  for path in (result.stdout or ""):gmatch("[^%z]+") do
    ignored[path] = true
  end
  for _, path in ipairs(unknown) do
    gitignore_cache[path] = ignored[path] == true
  end
end

function M.clear_cache()
  gitignore_cache = {}
  realpath_cache = {}
end

return M
