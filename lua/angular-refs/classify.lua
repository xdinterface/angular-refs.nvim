local M = {}

local config = require("angular-refs.config")

M.LIFECYCLE = {
  ngOnChanges = true,
  ngOnInit = true,
  ngDoCheck = true,
  ngAfterContentInit = true,
  ngAfterContentChecked = true,
  ngAfterViewInit = true,
  ngAfterViewChecked = true,
  ngOnDestroy = true,
}

---@class AngularRefsCounts
---@field prod integer Usages outside test files
---@field test integer Usages inside test files
---@field related boolean Linked to an interface or base-class member

---@alias AngularRefsState "count"|"lifecycle"|"host_listener"|"host_binding"|"implements"|"tests_only"|"unused"

---Decide the label for a symbol; the first matching rule wins
---@param symbol AngularRefsSymbol
---@param counts AngularRefsCounts
---@return AngularRefsState state, string text, string highlight
function M.label(symbol, counts)
  local display = config.get().display
  local labels = display.labels

  if counts.prod > 0 then
    local total = counts.prod + counts.test
    local format = total == 1 and display.format_singular or display.format
    return "count", string.format(format, total), "AngularRefsCount"
  end
  if M.LIFECYCLE[symbol.name] then
    return "lifecycle", labels.lifecycle, "AngularRefsFramework"
  end
  if symbol.decorators.host_listener then
    return "host_listener", labels.host_listener, "AngularRefsFramework"
  end
  if symbol.decorators.host_binding then
    return "host_binding", labels.host_binding, "AngularRefsFramework"
  end
  if counts.related then
    return "implements", labels.implements, "AngularRefsFramework"
  end
  if counts.test > 0 then
    return "tests_only", labels.tests_only, "AngularRefsTestsOnly"
  end
  return "unused", labels.unused, "AngularRefsUnused"
end

return M
