local M = {}

---@class AngularRefsDisplayConfig
---@field position "eol"|"above" Virtual text position
---@field separator string Separator before usage text (e.g., " ", " - ", " · ")
---@field format string Format string for plural usages (2+)
---@field format_singular string Format string for singular usage (1)
---@field format_zero string Format string for zero usages
---@field format_unknown string Text when zero confirmed usages cannot establish unused status
---@field format_incomplete string Format string for a confirmed lower bound
---@field highlight string Highlight group for normal usages
---@field zero_refs_highlight string Highlight group for zero usages

---@class AngularRefsTriggerConfig
---@field on_open boolean Update on BufEnter
---@field on_save boolean Update on BufWritePost
---@field debounce_ms number Debounce time in milliseconds

---@class AngularRefsExcludeConfig
---@field patterns string[] Lua patterns to exclude from reference counts
---@field respect_gitignore boolean Respect .gitignore files (default: true)

---@class AngularRefsConfig
---@field enabled boolean Enable the plugin
---@field comprehensive_mode boolean Deprecated compatibility option; no effect
---@field analysis {timeout_ms: integer, max_concurrent_requests: integer}
---@field display AngularRefsDisplayConfig Display configuration
---@field trigger AngularRefsTriggerConfig Trigger configuration
---@field exclude AngularRefsExcludeConfig Exclusion patterns for filtering references
---@field debug boolean Enable debug logging

---@type AngularRefsConfig
M.defaults = {
	enabled = true,
	comprehensive_mode = false, -- Deprecated: all refreshes use the shared pipeline.
	analysis = { timeout_ms = 10000, max_concurrent_requests = 4 },
	display = {
		position = "eol",
		separator = " | ",
		format = "%d usages",
		format_singular = "%d usage",
		format_zero = "unused",
		format_unknown = "unknown",
		format_incomplete = "%d usages (incomplete)",
		highlight = "Comment",
		zero_refs_highlight = "Comment",
	},
	trigger = {
		on_open = true,
		on_save = true,
		debounce_ms = 500,
	},
	exclude = {
		patterns = {
			"node_modules",
			"/dist/",
			"%.angular",
			"/build/",
			"/coverage/",
			"/__pycache__/",
		},
		respect_gitignore = true,
	},
	debug = false,
}

---@type AngularRefsConfig
M.options = vim.deepcopy(M.defaults)

---@param opts AngularRefsConfig|nil
function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
	for _, key in ipairs({ "timeout_ms", "max_concurrent_requests" }) do
		local value = M.options.analysis[key]
		assert(
			type(value) == "number" and value >= 1 and value % 1 == 0,
			"angular-refs: analysis." .. key .. " must be a positive integer"
		)
	end
end

---@return AngularRefsConfig
function M.get()
	return M.options
end

---@return boolean
function M.is_enabled()
	return M.options.enabled
end

return M
