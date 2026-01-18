local M = {}

---@class AngularRefsDisplayConfig
---@field position "eol"|"above" Virtual text position
---@field separator string Separator before usage text (e.g., " ", " - ", " · ")
---@field format string Format string for plural usages (2+)
---@field format_singular string Format string for singular usage (1)
---@field format_zero string Format string for zero usages
---@field highlight string Highlight group for normal usages
---@field zero_refs_highlight string Highlight group for zero usages

---@class AngularRefsTriggerConfig
---@field on_open boolean Update on BufEnter
---@field on_save boolean Update on BufWritePost
---@field debounce_ms number Debounce time in milliseconds

---@class AngularRefsConfig
---@field enabled boolean Enable the plugin
---@field display AngularRefsDisplayConfig Display configuration
---@field trigger AngularRefsTriggerConfig Trigger configuration
---@field debug boolean Enable debug logging

---@type AngularRefsConfig
M.defaults = {
  enabled = true,
  display = {
    position = "eol",
    separator = " ",
    format = "%d usages",
    format_singular = "%d usage",
    format_zero = "unused",
    highlight = "Comment",
    zero_refs_highlight = "Comment",
  },
  trigger = {
    on_open = true,
    on_save = true,
    debounce_ms = 500,
  },
  debug = false,
}

---@type AngularRefsConfig
M.current = vim.deepcopy(M.defaults)

---@param opts AngularRefsConfig|nil
function M.setup(opts)
  M.current = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

---@return AngularRefsConfig
function M.get()
  return M.current
end

return M
