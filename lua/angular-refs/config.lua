local M = {}

---@class AngularRefsLabels
---@field unused string
---@field tests_only string
---@field lifecycle string
---@field host_listener string
---@field host_binding string
---@field implements string

---@class AngularRefsDisplayConfig
---@field position "eol"|"above"
---@field separator string Text between the code (or the aligned column) and the label
---@field align boolean Line up the labels of neighbouring lines
---@field format string Format for 2+ usages
---@field format_singular string Format for 1 usage
---@field labels AngularRefsLabels

---@class AngularRefsScopeConfig
---@field exclude string[] Extra Lua patterns, added to the built-in scope rules
---@field test_patterns string[] Lua patterns identifying test files
---@field respect_gitignore boolean

---@class AngularRefsSymbolsConfig
---@field ignore string[] Lua patterns for symbol names that get no label
---@field test_buffers boolean Label symbols inside test files

---@class AngularRefsClientsConfig
---@field angular string[]
---@field typescript string[]

---@class AngularRefsConfig
---@field enabled boolean
---@field display AngularRefsDisplayConfig
---@field trigger {debounce_ms: integer}
---@field scope AngularRefsScopeConfig
---@field symbols AngularRefsSymbolsConfig
---@field clients AngularRefsClientsConfig
---@field debug boolean

---@type AngularRefsConfig
M.defaults = {
  enabled = true,
  display = {
    position = "eol",
    separator = "    | ",
    align = false,
    format = "%d usages",
    format_singular = "%d usage",
    labels = {
      unused = "unused",
      tests_only = "tests only",
      lifecycle = "lifecycle",
      host_listener = "host listener",
      host_binding = "host binding",
      implements = "implements",
    },
  },
  trigger = {
    debounce_ms = 500,
  },
  scope = {
    exclude = {},
    test_patterns = { "%.spec%.ts$", "%.test%.ts$", "%.cy%.ts$", "/e2e/" },
    respect_gitignore = false,
  },
  symbols = {
    ignore = { "^_" },
    test_buffers = false,
  },
  clients = {
    angular = { "angularls", "angular" },
    typescript = { "typescript-tools", "ts_ls", "vtsls", "typescript-language-server", "tsserver" },
  },
  debug = false,
}

-- v1 exclude patterns now covered by the built-in scope rules
local BUILT_IN_V1_PATTERNS = {
  ["node_modules"] = true,
  ["/dist/"] = true,
  ["%.angular"] = true,
  ["/build/"] = true,
  ["/coverage/"] = true,
  ["/__pycache__/"] = true,
}

---@type AngularRefsConfig
local options = vim.deepcopy(M.defaults)

---@type string[]
local last_warnings = {}

---Deep merge where nested tables merge but lists and scalars replace
---@param base table
---@param override table
---@return table
local function merge(base, override)
  local result = vim.deepcopy(base)
  for key, value in pairs(override) do
    local is_mergeable = type(value) == "table" and type(result[key]) == "table" and not vim.islist(value)
    if is_mergeable then
      result[key] = merge(result[key], value)
    else
      result[key] = vim.deepcopy(value)
    end
  end
  return result
end

---Move v1 option keys to their v2 location and describe each change
---@param opts table
---@return table opts, string[] warnings
local function migrate(opts)
  opts = vim.deepcopy(opts)
  local warnings = {}

  if opts.comprehensive_mode ~= nil then
    table.insert(warnings, "`comprehensive_mode` was removed: counts are now always exact; option ignored")
    opts.comprehensive_mode = nil
  end

  if type(opts.exclude) == "table" then
    opts.scope = opts.scope or {}
    if opts.exclude.patterns then
      opts.scope.exclude = vim.tbl_filter(function(pattern)
        return not BUILT_IN_V1_PATTERNS[pattern]
      end, opts.exclude.patterns)
      table.insert(warnings, "`exclude.patterns` moved to `scope.exclude` (built-in folders are now always excluded)")
    end
    if opts.exclude.respect_gitignore ~= nil then
      opts.scope.respect_gitignore = opts.exclude.respect_gitignore
      table.insert(warnings, "`exclude.respect_gitignore` moved to `scope.respect_gitignore`")
    end
    opts.exclude = nil
  end

  local display = opts.display
  if type(display) == "table" then
    if display.format_zero ~= nil then
      display.labels = display.labels or {}
      display.labels.unused = display.format_zero
      display.format_zero = nil
      table.insert(warnings, "`display.format_zero` moved to `display.labels.unused`")
    end
    if display.highlight ~= nil or display.zero_refs_highlight ~= nil then
      display.highlight = nil
      display.zero_refs_highlight = nil
      table.insert(warnings, "`display.highlight` options were removed: link the AngularRefs* highlight groups instead")
    end
  end

  local trigger = opts.trigger
  if type(trigger) == "table" and (trigger.on_open ~= nil or trigger.on_save ~= nil) then
    trigger.on_open = nil
    trigger.on_save = nil
    table.insert(warnings, "`trigger.on_open`/`trigger.on_save` were removed: refreshes are automatic; options ignored")
  end

  return opts, warnings
end

---@param opts AngularRefsConfig|table|nil
function M.setup(opts)
  local migrated, warnings = migrate(opts or {})
  options = merge(M.defaults, migrated)
  last_warnings = warnings
  for _, warning in ipairs(warnings) do
    vim.notify("angular-refs: " .. warning, vim.log.levels.WARN)
  end
end

---@return AngularRefsConfig
function M.get()
  return options
end

---Deprecation warnings produced by the last setup call
---@return string[]
function M.warnings()
  return last_warnings
end

return M
