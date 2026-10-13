local M = {}

local config = require("angular-refs.config")

-- Angular's build and test output folders, only excluded directly under the project root
local ROOT_OUTPUT_DIRS = { "dist/", "out-tsc/", "coverage/" }

-- Dependency and tooling folders, excluded at any depth
local EXCLUDED_SEGMENTS = { "/node_modules/", "/.angular/" }

---@type table<string, boolean>
local gitignore_cache = {}

---Callbacks waiting for a path whose git check is running
---@type table<string, fun()[]>
local gitignore_waiters = {}

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

---Whether a reference location belongs to the project's own source code.
---Gitignore status comes from prefetch_gitignore; a path it has not resolved counts as not ignored.
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

  return not (cfg.respect_gitignore and gitignore_cache[path] == true)
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

---@param path string
---@param ignored boolean
local function resolve_gitignore(path, ignored)
  gitignore_cache[path] = ignored
  local waiters = gitignore_waiters[path] or {}
  gitignore_waiters[path] = nil
  for _, waiter in ipairs(waiters) do
    waiter()
  end
end

---Run git without blocking the editor; a git that cannot start reports exit code -1
---@param cmd string[]
---@param opts table
---@param on_exit fun(result: {code: integer, stdout: string|nil})
local function run_git(cmd, opts, on_exit)
  local done = vim.schedule_wrap(on_exit)
  local ok = pcall(vim.system, cmd, opts, done)
  if not ok then
    done({ code = -1 })
  end
end

---@param path string
local function check_one(path)
  run_git({ "git", "-C", vim.fs.dirname(path), "check-ignore", "-q", path }, {}, function(result)
    resolve_gitignore(path, result.code == 0)
  end)
end

---@param paths string[]
local function check_batch(paths)
  run_git({ "git", "-C", vim.fs.dirname(paths[1]), "check-ignore", "--stdin", "-z" }, {
    stdin = table.concat(paths, "\0") .. "\0",
  }, function(result)
    if result.code == -1 then
      for _, path in ipairs(paths) do
        resolve_gitignore(path, false)
      end
      return
    end
    -- Exit 128: git aborted the whole batch (e.g. a path outside the repository)
    if result.code ~= 0 and result.code ~= 1 then
      for _, path in ipairs(paths) do
        check_one(path)
      end
      return
    end
    local ignored = {}
    for path in (result.stdout or ""):gmatch("[^%z]+") do
      ignored[path] = true
    end
    for _, path in ipairs(paths) do
      resolve_gitignore(path, ignored[path] == true)
    end
  end)
end

---Resolve the gitignore status of files in the background, then call on_done.
---Requests for files already being checked wait for that check instead of starting git again.
---@param paths string[]
---@param on_done fun()
function M.prefetch_gitignore(paths, on_done)
  if not config.get().scope.respect_gitignore then
    on_done()
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
    on_done()
    return
  end

  local remaining = #unknown
  local function one_resolved()
    remaining = remaining - 1
    if remaining == 0 then
      on_done()
    end
  end

  local to_check = {}
  for _, path in ipairs(unknown) do
    if gitignore_waiters[path] then
      table.insert(gitignore_waiters[path], one_resolved)
    else
      gitignore_waiters[path] = { one_resolved }
      table.insert(to_check, path)
    end
  end
  if #to_check > 0 then
    check_batch(to_check)
  end
end

---@param path string
---@return boolean
function M.gitignore_resolved(path)
  return not config.get().scope.respect_gitignore or gitignore_cache[path] ~= nil
end

function M.clear_cache()
  gitignore_cache = {}
  gitignore_waiters = {}
  realpath_cache = {}
end

return M
