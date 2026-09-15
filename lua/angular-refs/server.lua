local M = {}

local clients = require("angular-refs.clients")
local parser = require("angular-refs.parser")

-- Preserve the existing parser entry points for callers and fixture tests.
M.parse_tcb_symbols = parser.parse_tcb_symbols
M.parse_template_control_flow = parser.parse_template_control_flow
M.get_component_metadata = parser.get_component_metadata
M.parse_host_bindings = parser.parse_host_bindings

-- Angular lifecycle methods that should be excluded from reference counting
local LIFECYCLE_METHODS = {
  "ngOnInit",
  "ngOnDestroy",
  "ngOnChanges",
  "ngDoCheck",
  "ngAfterContentInit",
  "ngAfterContentChecked",
  "ngAfterViewInit",
  "ngAfterViewChecked",
}

---Check if a method name is an Angular lifecycle method
---@param name string
---@return boolean
function M.is_lifecycle_method(name)
  return vim.tbl_contains(LIFECYCLE_METHODS, name)
end

---Get decorator reference count for a symbol (@HostListener, @HostBinding)
---@param bufnr number Buffer number
---@param symbol_name string Name of the symbol to check
---@return number Number of decorator references
function M.get_decorator_refs(bufnr, symbol_name)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local count = 0

  for i, line in ipairs(lines) do
    -- Check for @HostListener decorator
    if line:match("@HostListener%s*%(") then
      local next_line = lines[i + 1] or ""
      -- Check if the next line (or same line for single-line) defines the symbol
      if next_line:match(symbol_name .. "%s*%(") or next_line:match(symbol_name .. "%s*=") then
        count = count + 1
      end
      -- Also check same line for compact decorators: @HostListener('click') onClick() {}
      if line:match(symbol_name .. "%s*%(") then
        count = count + 1
      end
    end

    -- Check for @HostBinding decorator
    if line:match("@HostBinding%s*%(") then
      local next_line = lines[i + 1] or ""
      -- Check if next line defines the symbol (property or getter)
      if next_line:match(symbol_name .. "%s*[=:;]") or next_line:match("get%s+" .. symbol_name) then
        count = count + 1
      end
      if line:match(symbol_name .. "%s*[=:;]") or line:match("get%s+" .. symbol_name) then
        count = count + 1
      end
    end
  end

  return count
end

---@type table<number, table<string, number>>
local tcb_cache = {}

---@type table<string, {counts: table<string, number>, timestamp: number}>
local parent_usage_cache = {}
local PARENT_CACHE_TTL_MS = 30000 -- 30 seconds

---Find the project root by looking for angular.json, package.json, or .git
---@param start_path string|nil Starting path (defaults to current buffer's directory)
---@return string|nil project_root
function M.find_project_root(start_path)
  start_path = start_path or vim.fn.expand("%:p:h")

  local markers = { "angular.json", "nx.json", "package.json", ".git" }

  local current = start_path
  local max_depth = 20 -- Max directory levels to traverse upward looking for project root

  for _ = 1, max_depth do
    for _, marker in ipairs(markers) do
      local marker_path = current .. "/" .. marker
      if vim.fn.filereadable(marker_path) == 1 or vim.fn.isdirectory(marker_path) == 1 then
        return current
      end
    end

    local parent = vim.fn.fnamemodify(current, ":h")
    if parent == current then
      break
    end
    current = parent
  end

  return nil
end

---Search for all HTML files in a directory tree
---@param root_path string Project root path
---@return string[] html_files List of HTML file paths
local function find_html_files(root_path)
  local filter = require("angular-refs.filter")
  local files = {}

  local glob_pattern = root_path .. "/**/*.html"
  local matches = vim.fn.glob(glob_pattern, false, true)

  for _, path in ipairs(matches) do
    if not filter.should_exclude(path) then
      table.insert(files, path)
    end
  end

  return files
end

---Read file content
---@param path string
---@return string|nil
local function read_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local content = file:read("*all")
  file:close()
  return content
end

---Add source counts to a result owned by the caller, without mutating caches.
local function merge_counts(target, source)
  for name, count in pairs(source) do
    target[name] = (target[name] or 0) + count
  end
end

local function index_bindings(bindings)
  local by_alias, by_name = {}, {}
  for _, binding in ipairs(bindings) do
    by_name[binding.name] = binding
    if binding.alias then
      by_alias[binding.alias] = binding
    end
  end
  return by_alias, by_name
end

---Extract bindings from tag content and update usage counts
---@param tag_content string The tag attributes content
---@param input_by_alias table<string, ComponentInput>
---@param input_by_name table<string, ComponentInput>
---@param output_by_alias table<string, ComponentOutput>
---@param output_by_name table<string, ComponentOutput>
---@param usage_counts table<string, number> Table to update with counts
local function extract_bindings_from_tag(tag_content, input_by_alias, input_by_name, output_by_alias, output_by_name, usage_counts)
  for binding_name in tag_content:gmatch("%[([a-zA-Z_][a-zA-Z0-9_]*)%]%s*=") do
    local input = input_by_alias[binding_name] or input_by_name[binding_name]
    if input then
      usage_counts[input.name] = (usage_counts[input.name] or 0) + 1
    end
  end

  for binding_name in tag_content:gmatch("%(([a-zA-Z_][a-zA-Z0-9_]*)%)%s*=") do
    local output = output_by_alias[binding_name] or output_by_name[binding_name]
    if output then
      usage_counts[output.name] = (usage_counts[output.name] or 0) + 1
    end
  end

  for binding_name in tag_content:gmatch("%[%(([a-zA-Z_][a-zA-Z0-9_]*)%)%]%s*=") do
    local input = input_by_alias[binding_name] or input_by_name[binding_name]
    if input then
      usage_counts[input.name] = (usage_counts[input.name] or 0) + 1
    end
    local change_name = binding_name .. "Change"
    local output = output_by_alias[change_name] or output_by_name[change_name]
    if output then
      usage_counts[output.name] = (usage_counts[output.name] or 0) + 1
    end
  end
end

---@class ParentUsage
---@field file string Path to parent template
---@field binding string The binding name used (may be alias)
---@field property string The internal property name
---@field kind string "input" | "output" | "two-way"

---Find usages of a component selector in parent templates
---Returns binding information for inputs/outputs
---@param selector string Component selector (e.g., "app-child")
---@param inputs ComponentInput[] Component inputs
---@param outputs ComponentOutput[] Component outputs
---@param project_root string Project root path
---@return table<string, number> property_name -> usage_count
function M.find_selector_usages(selector, inputs, outputs, project_root)
  if not selector or not project_root then
    return {}
  end

  -- Check cache first
  local cache_key = selector .. ":" .. project_root
  local cached = parent_usage_cache[cache_key]
  if cached then
    local now = vim.uv.now()
    if now - cached.timestamp < PARENT_CACHE_TTL_MS then
      return cached.counts
    end
  end

  local cfg = require("angular-refs.config").get()
  local usage_counts = {}

  -- Build lookup maps for faster matching
  local input_by_alias, input_by_name = index_bindings(inputs)
  local output_by_alias, output_by_name = index_bindings(outputs)

  local html_files = find_html_files(project_root)

  if cfg.debug then
    vim.notify(
      "angular-refs: Searching " .. #html_files .. " HTML files for selector: " .. selector,
      vim.log.levels.DEBUG
    )
  end

  for _, file_path in ipairs(html_files) do
    local content = read_file(file_path)
    if content then
      -- Find all opening tags for this selector and extract bindings from each
      -- This ensures we only count bindings that are on the component element itself
      -- Pattern matches: <selector ...> or <selector/> capturing the attributes
      local escaped_selector = vim.pesc(selector)

      -- Match opening tags: <selector attr="val"> or <selector attr="val" />
      -- We need to handle multi-line tags, so we use [^>]* to capture all attributes
      for tag_content in content:gmatch("<" .. escaped_selector .. "(%s[^>]*)>") do
        if cfg.debug then
          vim.notify("angular-refs: Found selector in " .. file_path, vim.log.levels.DEBUG)
        end
        extract_bindings_from_tag(tag_content, input_by_alias, input_by_name, output_by_alias, output_by_name, usage_counts)
      end

      for tag_content in content:gmatch("<" .. escaped_selector .. "(%s[^/]*)/>") do
        if cfg.debug then
          vim.notify("angular-refs: Found self-closing selector in " .. file_path, vim.log.levels.DEBUG)
        end
        extract_bindings_from_tag(tag_content, input_by_alias, input_by_name, output_by_alias, output_by_name, usage_counts)
      end

      -- Handle tags with no attributes: <selector></selector>
      if content:match("<" .. escaped_selector .. ">") then
        if cfg.debug then
          vim.notify("angular-refs: Found selector (no attrs) in " .. file_path, vim.log.levels.DEBUG)
        end
      end
    end
  end

  parent_usage_cache[cache_key] = {
    counts = usage_counts,
    timestamp = vim.uv.now(),
  }

  return usage_counts
end

---Find the template file path for a component
---@param component_path string Path to the .ts component file
---@return string|nil template_path
function M.find_template_file(component_path)
  -- Read component file content
  local content = read_file(component_path)
  if not content then
    return nil
  end

  -- Look for templateUrl: './xxx.html' or templateUrl: "xxx.html"
  local template_url = content:match("templateUrl%s*:%s*['\"]([^'\"]+)['\"]")
  if template_url then
    -- Resolve relative path
    local component_dir = vim.fn.fnamemodify(component_path, ":h")
    return vim.fn.simplify(component_dir .. "/" .. template_url)
  end

  -- Try convention: component.ts -> component.html
  local html_path = component_path:gsub("%.ts$", ".html")
  if vim.fn.filereadable(html_path) == 1 then
    return html_path
  end

  return nil
end

---Extract component metadata from a buffer
---@param bufnr number
---@return ComponentMetadata
function M.get_component_metadata_for_buffer(bufnr)
  local component_path = vim.api.nvim_buf_get_name(bufnr)
  return M.get_component_metadata(read_file(component_path))
end

---Get all template symbols by combining TCB + HTML parsing + host bindings
---@param bufnr number
---@param callback fun(symbols: table<string, number>)
function M.get_all_template_symbols(bufnr, callback)
  local component_path = vim.api.nvim_buf_get_name(bufnr)
  local template_path = M.find_template_file(component_path)

  -- Start with TCB symbols
  M.get_tcb_symbols(bufnr, function(tcb_symbols)
    local all_symbols = vim.deepcopy(tcb_symbols)

    -- Add HTML template parsing for control flow blocks
    if template_path then
      local template_content = read_file(template_path)
      if template_content then
        local html_symbols = M.parse_template_control_flow(template_content)
        merge_counts(all_symbols, html_symbols)
      end
    end

    -- Add host binding symbols from component
    local comp_content = read_file(component_path)
    if comp_content then
      local host_symbols = M.parse_host_bindings(comp_content)
      merge_counts(all_symbols, host_symbols)
    end

    callback(all_symbols)
  end)
end

---Call angular/getTcb LSP request on the template file and parse response
---@param bufnr number The component TS buffer
---@param callback fun(symbols: table<string, number>)
function M.get_tcb_symbols(bufnr, callback)
  -- Check cache first
  if tcb_cache[bufnr] then
    callback(tcb_cache[bufnr])
    return
  end

  local cfg = require("angular-refs.config").get()
  local component_path = vim.api.nvim_buf_get_name(bufnr)

  -- Find the template file for this component
  local template_path = M.find_template_file(component_path)
  if not template_path then
    if cfg.debug then
      vim.notify("angular-refs: No template file found for " .. component_path, vim.log.levels.DEBUG)
    end
    callback({})
    return
  end

  if cfg.debug then
    vim.notify("angular-refs: Found template: " .. template_path, vim.log.levels.DEBUG)
  end

  -- Get Angular client (might be attached to template buffer)
  local client = clients.get_angular(bufnr, true)
  if not client then
    if cfg.debug then
      vim.notify("angular-refs: Angular LSP client not found", vim.log.levels.DEBUG)
    end
    callback({})
    return
  end

  -- Call getTcb on the template file
  local template_uri = vim.uri_from_fname(template_path)
  local params = {
    textDocument = { uri = template_uri },
    position = { line = 0, character = 0 },
  }

  if cfg.debug then
    vim.notify("angular-refs: Calling getTcb on " .. template_uri, vim.log.levels.DEBUG)
  end

  client.request("angular/getTcb", params, function(err, result)
    if err then
      if cfg.debug then
        vim.notify("angular-refs: getTcb error: " .. vim.inspect(err), vim.log.levels.DEBUG)
      end
      callback({})
      return
    end

    if not result or not result.content then
      if cfg.debug then
        vim.notify("angular-refs: getTcb returned no content for " .. template_path, vim.log.levels.DEBUG)
      end
      callback({})
      return
    end

    if cfg.debug then
      vim.notify("angular-refs: TCB content length: " .. #result.content, vim.log.levels.DEBUG)
    end

    -- Parse TCB content to extract symbol references
    local symbols = M.parse_tcb_symbols(result.content)

    -- Cache the result
    tcb_cache[bufnr] = symbols

    if cfg.debug then
      vim.notify("angular-refs: TCB symbols found: " .. vim.inspect(symbols), vim.log.levels.DEBUG)
    end

    callback(symbols)
  end, bufnr)
end

---Get all class member declarations from a TypeScript component buffer
---Parses the buffer to find properties and methods that should have ref counts displayed
---@param bufnr number Buffer number
---@return table[] declarations List of {name: string, line: number, col: number, kind: string}
function M.get_declarations_in_buffer(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local declarations = {}

  local in_class = false
  local class_brace_depth = 0

  for line_idx, line in ipairs(lines) do
    local line_0idx = line_idx - 1

    -- Track class boundaries
    if line:match("^%s*export%s+class%s+") or line:match("^%s*class%s+") then
      in_class = true
      class_brace_depth = 0
    end

    if in_class then
      for _ in line:gmatch("{") do
        class_brace_depth = class_brace_depth + 1
      end
      for _ in line:gmatch("}") do
        class_brace_depth = class_brace_depth - 1
        if class_brace_depth <= 0 then
          in_class = false
        end
      end
    end

    if in_class and class_brace_depth > 0 then
      -- Skip private members (private keyword, # prefix, or _ prefix convention)
      if line:match("^%s*private%s+") or line:match("^%s*#") or line:match("^%s*_[a-zA-Z]") then
        goto continue
      end

      -- Parse constructor parameter properties (public/readonly/protected params become class properties)
      local constructor_params = line:match("^%s*constructor%s*%((.*)%)")
      if constructor_params then
        for _, param_name in constructor_params:gmatch("(public%s+)([a-zA-Z_][a-zA-Z0-9_]*)") do
          local col = line:find(param_name) - 1
          table.insert(declarations, {
            name = param_name,
            line = line_0idx,
            col = col,
            kind = "parameter-property",
          })
        end
        for _, param_name in constructor_params:gmatch("(readonly%s+)([a-zA-Z_][a-zA-Z0-9_]*)") do
          local col = line:find(param_name) - 1
          table.insert(declarations, {
            name = param_name,
            line = line_0idx,
            col = col,
            kind = "parameter-property",
          })
        end
        for _, param_name in constructor_params:gmatch("(protected%s+)([a-zA-Z_][a-zA-Z0-9_]*)") do
          local col = line:find(param_name) - 1
          table.insert(declarations, {
            name = param_name,
            line = line_0idx,
            col = col,
            kind = "parameter-property",
          })
        end
        goto continue
      end

      -- Match property declarations: name = value, name: type, name?: type, name!: type
      local prop_match = line:match("^%s*([a-zA-Z_][a-zA-Z0-9_]*)%s*[=:?!]")
      if prop_match and not line:match("^%s*" .. prop_match .. "%s*%(") then
        -- Not a method call
        local col = line:find(prop_match) - 1
        table.insert(declarations, {
          name = prop_match,
          line = line_0idx,
          col = col,
          kind = "property",
        })
        goto continue
      end

      -- Match method declarations: name(...) or async name(...) or get name() or set name(...)
      -- Also handle generic methods: getData<T>()
      local method_match = line:match("^%s*async%s+([a-zA-Z_][a-zA-Z0-9_]*)%s*[<%(]")
        or line:match("^%s*([a-zA-Z_][a-zA-Z0-9_]*)%s*[<%(]")
        or line:match("^%s*get%s+([a-zA-Z_][a-zA-Z0-9_]*)%s*%(")
        or line:match("^%s*set%s+([a-zA-Z_][a-zA-Z0-9_]*)%s*%(")

      if method_match then
        -- Skip Angular lifecycle methods
        if M.is_lifecycle_method(method_match) then
          goto continue
        end

        local col = line:find(method_match) - 1
        table.insert(declarations, {
          name = method_match,
          line = line_0idx,
          col = col,
          kind = "method",
        })
        goto continue
      end

      -- Match decorator-based declarations: @Input(), @Output(), @ViewChild(), etc.
      local decorator_match = line:match("@Input.-([a-zA-Z_][a-zA-Z0-9_]*)%s*[=:;]")
        or line:match("@Output.-([a-zA-Z_][a-zA-Z0-9_]*)%s*[=:;]")
        or line:match("@ViewChild.-([a-zA-Z_][a-zA-Z0-9_]*)%s*[=:;!]")
        or line:match("@ViewChildren.-([a-zA-Z_][a-zA-Z0-9_]*)%s*[=:;!]")
        or line:match("@ContentChild.-([a-zA-Z_][a-zA-Z0-9_]*)%s*[=:;!]")
        or line:match("@ContentChildren.-([a-zA-Z_][a-zA-Z0-9_]*)%s*[=:;!]")

      if decorator_match then
        local col = line:find(decorator_match) - 1
        table.insert(declarations, {
          name = decorator_match,
          line = line_0idx,
          col = col,
          kind = "decorated",
        })
      end
    end

    ::continue::
  end

  return declarations
end

---Get all references by combining multiple sources:
---1. Own template refs (TCB + HTML parsing + host bindings)
---2. Parent component usages (project-wide search for inputs/outputs)
---
---This is the comprehensive method that mirrors WebStorm's approach.
---@param bufnr number Buffer number
---@param callback fun(symbol_counts: table<string, number>)
function M.get_all_references(bufnr, callback)
  local cfg = require("angular-refs.config").get()
  local component_path = vim.api.nvim_buf_get_name(bufnr)

  if cfg.debug then
    vim.notify("angular-refs: Getting all references for " .. component_path, vim.log.levels.DEBUG)
  end

  -- Get component metadata (selector, inputs, outputs)
  local metadata = M.get_component_metadata_for_buffer(bufnr)

  -- Start with own template references
  M.get_all_template_symbols(bufnr, function(own_refs)
    local all_refs = vim.deepcopy(own_refs)

    -- Add parent component usages for inputs/outputs
    if metadata.selector and (#metadata.inputs > 0 or #metadata.outputs > 0) then
      local project_root = M.find_project_root(vim.fn.fnamemodify(component_path, ":h"))

      if project_root then
        local parent_refs = M.find_selector_usages(metadata.selector, metadata.inputs, metadata.outputs, project_root)

        if cfg.debug then
          vim.notify("angular-refs: Parent refs found: " .. vim.inspect(parent_refs), vim.log.levels.DEBUG)
        end

        -- Merge parent refs
        merge_counts(all_refs, parent_refs)
      elseif cfg.debug then
        vim.notify("angular-refs: No project root found for parent search", vim.log.levels.DEBUG)
      end
    end

    -- Filter out lifecycle methods (they should already be filtered in get_declarations_in_buffer,
    -- but double-check here for safety)
    local filtered_refs = {}
    for name, count in pairs(all_refs) do
      if not M.is_lifecycle_method(name) then
        filtered_refs[name] = count
      end
    end

    if cfg.debug then
      local list = {}
      for name, count in pairs(filtered_refs) do
        table.insert(list, string.format("  %s: %d", name, count))
      end
      table.sort(list)
      vim.notify("angular-refs: All references:\n" .. table.concat(list, "\n"), vim.log.levels.DEBUG)
    end

    callback(filtered_refs)
  end)
end

---Get comprehensive reference counts using all available sources
---This combines TCB parsing, template HTML parsing, host bindings, and parent usages
---@param bufnr number Buffer number
---@param callback fun(symbol_counts: table<string, number>)
function M.get_comprehensive_counts(bufnr, callback)
  local cfg = require("angular-refs.config").get()

  if cfg.debug then
    vim.notify("angular-refs: Using comprehensive reference counting (WebStorm-style)", vim.log.levels.DEBUG)
  end

  -- Get declarations to know which symbols to display
  local declarations = M.get_declarations_in_buffer(bufnr)
  local decl_names = {}
  for _, decl in ipairs(declarations) do
    decl_names[decl.name] = true
  end

  -- Get all references
  M.get_all_references(bufnr, function(all_refs)
    -- Only return counts for symbols that are actually declared in the component
    local filtered = {}
    for name, count in pairs(all_refs) do
      if decl_names[name] then
        filtered[name] = count
      end
    end

    callback(filtered)
  end)
end

---Invalidate cache for a buffer
---@param bufnr number|string Buffer number or file path
function M.invalidate(bufnr)
  if type(bufnr) == "string" then
    -- File path passed, find buffer
    for buf, _ in pairs(tcb_cache) do
      if vim.api.nvim_buf_is_valid(buf) then
        local name = vim.api.nvim_buf_get_name(buf)
        if name == bufnr or name:match(vim.pesc(bufnr)) then
          tcb_cache[buf] = nil
        end
      end
    end
  else
    tcb_cache[bufnr] = nil
  end
end

---Invalidate parent usage cache (call when HTML files change)
function M.invalidate_parent_cache()
  parent_usage_cache = {}
end

---Dump raw TCB content for debugging
---@param bufnr number
function M.dump_tcb(bufnr)
  local component_path = vim.api.nvim_buf_get_name(bufnr)
  local template_path = M.find_template_file(component_path)

  if not template_path then
    vim.notify("angular-refs: No template file found for " .. component_path, vim.log.levels.ERROR)
    return
  end

  vim.notify("angular-refs: Template: " .. template_path, vim.log.levels.INFO)

  local client = clients.get_angular(bufnr, true)
  if not client then
    vim.notify("angular-refs: Angular LSP client not found", vim.log.levels.ERROR)
    return
  end

  vim.notify("angular-refs: Using client: " .. client.name, vim.log.levels.INFO)

  local template_uri = vim.uri_from_fname(template_path)
  client.request("angular/getTcb", {
    textDocument = { uri = template_uri },
    position = { line = 0, character = 0 },
  }, function(err, result)
    if err then
      vim.notify("angular-refs: getTcb error: " .. vim.inspect(err), vim.log.levels.ERROR)
      return
    end

    if not result or not result.content then
      vim.notify("angular-refs: getTcb returned no content", vim.log.levels.WARN)
      return
    end

    vim.notify("angular-refs: TCB content length: " .. #result.content, vim.log.levels.INFO)

    -- Show in a scratch buffer
    local lines = vim.split(result.content, "\n")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = "typescript"
    vim.api.nvim_buf_set_name(buf, "TCB Debug Output")

    vim.cmd("vsplit")
    vim.api.nvim_win_set_buf(0, buf)

    -- Also show parsed symbols
    local symbols = M.parse_tcb_symbols(result.content)
    local symbol_list = {}
    for name, count in pairs(symbols) do
      table.insert(symbol_list, string.format("  %s: %d", name, count))
    end
    table.sort(symbol_list)

    if #symbol_list > 0 then
      vim.notify("angular-refs: Parsed symbols:\n" .. table.concat(symbol_list, "\n"), vim.log.levels.INFO)
    else
      vim.notify("angular-refs: No symbols parsed from TCB content", vim.log.levels.WARN)
    end
  end, bufnr)
end

M.TS_CLIENT_NAMES = clients.TS_CLIENT_NAMES
M.ANGULAR_CLIENT_NAMES = clients.ANGULAR_CLIENT_NAMES

return M
