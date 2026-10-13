local M = {}

local health = vim.health

---@param path string
---@return string|nil
local function read(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local text = file:read("*a")
  file:close()
  return text
end

---@param root string
local function check_angular_version(root)
  local manifest = read(root .. "/node_modules/@angular/core/package.json")
  local ok, decoded = pcall(vim.json.decode, manifest or "")
  local version = ok and type(decoded) == "table" and decoded.version or nil
  if not version then
    health.warn("Could not read @angular/core version from " .. root .. "/node_modules")
    return
  end

  local major = tonumber(version:match("^(%d+)"))
  if major and major < 20 then
    health.warn("Angular " .. version .. ": counts are verified on Angular 20 and later")
  else
    health.ok("Angular " .. version)
  end

  if major == 20 then
    local tsconfig = read(root .. "/tsconfig.json") or ""
    if not tsconfig:match('"typeCheckHostBindings"%s*:%s*true') then
      health.warn(
        "Angular 20 only counts usages in `host: {}` metadata with type checking enabled",
        { 'Add `"typeCheckHostBindings": true` to `angularCompilerOptions` in tsconfig.json' }
      )
    end
  end
end

function M.check()
  local config = require("angular-refs.config")
  local clients = require("angular-refs.clients")
  local refresh = require("angular-refs.refresh")

  health.start("angular-refs")

  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim " .. tostring(vim.version()))
  else
    health.error("Neovim 0.10 or later is required")
  end

  for _, warning in ipairs(config.warnings()) do
    health.warn("Deprecated option: " .. warning)
  end

  if not refresh.enabled() then
    health.info("Labels are disabled (`:AngularRefsToggle` to enable)")
  end

  if config.get().scope.respect_gitignore then
    health.info("`scope.respect_gitignore` is on: the plugin runs `git check-ignore` in your project")
  end

  local bufnr = vim.fn.bufnr("#") ~= -1 and vim.fn.bufnr("#") or vim.api.nvim_get_current_buf()
  local ng, ts = clients.angular(bufnr), clients.typescript(bufnr)

  if ng then
    health.ok("Angular language server attached: " .. ng.name)
  else
    health.warn("No Angular language server attached to the current buffer", {
      "Labels only appear when angularls is attached to TypeScript buffers",
      "Configured names: " .. table.concat(config.get().clients.angular, ", "),
    })
  end

  if ts then
    health.ok("TypeScript language server attached: " .. ts.name)
  else
    health.warn("No TypeScript language server attached to the current buffer", {
      "Configured names: " .. table.concat(config.get().clients.typescript, ", "),
    })
  end

  if not ng then
    return
  end

  local root = clients.root(ng)
  if root then
    health.ok("Project root: " .. root)
    check_angular_version(root)
  else
    health.warn("angularls reports no project root; usages cannot be scoped to your project")
  end

  local filetypes = ng.config and ng.config.filetypes or {}
  if not vim.tbl_contains(filetypes, "htmlangular") and not vim.tbl_contains(filetypes, "html") then
    health.warn("angularls is not attached to template buffers", {
      "Unsaved template edits are counted only after saving",
      'Add "htmlangular" to the angularls filetypes',
    })
  end

  health.info("Project state: " .. clients.project_state(ng))
end

return M
