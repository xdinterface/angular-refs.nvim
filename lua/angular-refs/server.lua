local M = {}

local TS_CLIENT_NAMES = { "typescript-tools", "ts_ls", "vtsls", "typescript-language-server", "tsserver" }
local ANGULAR_CLIENT_NAMES = { "angularls", "angular" }

---Find an LSP client by trying a list of names
---@param bufnr number|nil Buffer to check (nil for any buffer)
---@param names string[] List of client names to try
---@param check_all_buffers boolean|nil If true, also check clients attached to any buffer
---@return table|nil
local function find_client_by_names(bufnr, names, check_all_buffers)
  for _, name in ipairs(names) do
    if bufnr then
      local clients = vim.lsp.get_clients({ bufnr = bufnr, name = name })
      if #clients > 0 then
        return clients[1]
      end
    end
  end
  if check_all_buffers then
    for _, name in ipairs(names) do
      local clients = vim.lsp.get_clients({ name = name })
      if #clients > 0 then
        return clients[1]
      end
    end
  end
  return nil
end

---Helper to create a symbol adder function for template parsing
---@param symbols table<string, number> Table to add symbols to
---@return fun(name: string)
local function create_symbol_adder(symbols)
  return function(name)
    if name and name ~= "" and not name:match("^%$") then
      symbols[name] = (symbols[name] or 0) + 1
    end
  end
end

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

---@type table<number, table<string, number>>
local refs_cache = {}

---@type table<string, {counts: table<string, number>, timestamp: number}>
local parent_usage_cache = {}
local PARENT_CACHE_TTL_MS = 30000 -- 30 seconds

---@class TemplateRef
---@field file string Full file path
---@field line number 1-indexed line number
---@field column number 1-indexed column number
---@field context string Line content for preview

---Get the TypeScript LSP client
---@param bufnr number Buffer to check
---@return table|nil
local function get_ts_client(bufnr)
  return find_client_by_names(bufnr, TS_CLIENT_NAMES, false)
end

---Get the Angular LSP client (check all buffers since it might only be attached to HTML)
---@param bufnr number|nil Optional buffer to check first
---@return table|nil
local function get_angular_client(bufnr)
  return find_client_by_names(bufnr, ANGULAR_CLIENT_NAMES, true)
end

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
  local input_by_alias = {}
  local input_by_name = {}
  for _, input in ipairs(inputs) do
    input_by_name[input.name] = input
    if input.alias then
      input_by_alias[input.alias] = input
    end
  end

  local output_by_alias = {}
  local output_by_name = {}
  for _, output in ipairs(outputs) do
    output_by_name[output.name] = output
    if output.alias then
      output_by_alias[output.alias] = output
    end
  end

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
  local file = io.open(component_path, "r")
  if not file then
    return nil
  end
  local content = file:read("*all")
  file:close()

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

---Parse TCB TypeScript content to extract referenced symbols
---@param tcb_content string|nil
---@return table<string, number> symbol_name to count mapping
function M.parse_tcb_symbols(tcb_content)
  if not tcb_content or tcb_content == "" then
    return {}
  end

  local symbols = {}

  -- Angular TCB generates code with patterns like:
  -- ((this).propertyName)   - most common in modern Angular
  -- (this).propertyName     - also common
  -- this.propertyName       - less common
  -- ((_ctx).propertyName)   - older Angular versions

  -- Match ((this).xxx) patterns - most common in modern Angular
  for symbol in tcb_content:gmatch("%(%(this%)%)%.([a-zA-Z_][a-zA-Z0-9_]*)") do
    symbols[symbol] = (symbols[symbol] or 0) + 1
  end

  -- Match (this).xxx patterns
  for symbol in tcb_content:gmatch("%(this%)%.([a-zA-Z_][a-zA-Z0-9_]*)") do
    symbols[symbol] = (symbols[symbol] or 0) + 1
  end

  -- Match this.xxx patterns (without parentheses)
  for symbol in tcb_content:gmatch("[^%w_]this%.([a-zA-Z_][a-zA-Z0-9_]*)") do
    symbols[symbol] = (symbols[symbol] or 0) + 1
  end

  -- Match this.xxx at start of string (the [^%w_] pattern above misses these)
  local start_symbol = tcb_content:match("^this%.([a-zA-Z_][a-zA-Z0-9_]*)")
  if start_symbol then
    symbols[start_symbol] = (symbols[start_symbol] or 0) + 1
  end

  -- Legacy: Match ((_ctx).xxx) patterns - older Angular versions
  for symbol in tcb_content:gmatch("%(%(_ctx%)%)%.([a-zA-Z_][a-zA-Z0-9_]*)") do
    symbols[symbol] = (symbols[symbol] or 0) + 1
  end

  -- Legacy: Match _ctx.xxx patterns
  for symbol in tcb_content:gmatch("_ctx%.([a-zA-Z_][a-zA-Z0-9_]*)") do
    symbols[symbol] = (symbols[symbol] or 0) + 1
  end

  return symbols
end

---Parse HTML template to find references inside control flow blocks (@for, @if, @switch, @defer)
---This supplements TCB parsing since Angular TCB doesn't include content inside these blocks
---@param template_content string
---@return table<string, number> symbol_name to count mapping
function M.parse_template_control_flow(template_content)
  if not template_content or template_content == "" then
    return {}
  end

  local symbols = {}
  local add_symbol = create_symbol_adder(symbols)

  -- Pattern to match control flow blocks: @for, @if, @else if, @switch, @case, @defer, @let
  -- We need to find content inside these blocks and extract bindings

  -- Match event bindings: (eventName)="handler($event, args)" or (eventName)="property = value"
  for handler in template_content:gmatch("%([%w%.]+%)%s*=%s*\"([^\"]+)\"") do
    -- Extract method calls: methodName(...)
    for method in handler:gmatch("([a-zA-Z_][a-zA-Z0-9_]*)%s*%(") do
      add_symbol(method)
    end
    -- Extract property assignments: property = value (the property being assigned)
    local prop = handler:match("^([a-zA-Z_][a-zA-Z0-9_]*)%s*=")
    if prop then
      add_symbol(prop)
    end
  end

  -- Match property bindings: [property]="expression"
  for expr in template_content:gmatch("%[[%w%.%-]+%]%s*=%s*\"([^\"]+)\"") do
    -- Extract property/method references from the expression
    for ref in expr:gmatch("([a-zA-Z_][a-zA-Z0-9_]*)") do
      -- Skip common keywords and loop variables
      if not ref:match("^(true|false|null|undefined|let|const|var|if|else|for|of|in|track|as)$") then
        add_symbol(ref)
      end
    end
  end

  -- Match interpolations: {{ expression }}
  for expr in template_content:gmatch("{{%s*([^}]+)%s*}}") do
    -- Extract first identifier (the property/method being accessed)
    for ref in expr:gmatch("([a-zA-Z_][a-zA-Z0-9_]*)") do
      if not ref:match("^(true|false|null|undefined)$") then
        add_symbol(ref)
      end
      break -- Only get the first identifier (the root property)
    end
  end

  -- Match two-way bindings: [(ngModel)]="property" or [(model)]="property"
  for prop in template_content:gmatch("%[%([%w]+%)%]%s*=%s*\"([a-zA-Z_][a-zA-Z0-9_]*)\"") do
    add_symbol(prop)
  end

  -- Match @for track expressions: @for (item of items; track trackFn(item))
  for track_expr in template_content:gmatch("@for[^{]*track%s+([^;%)}{]+)") do
    for ref in track_expr:gmatch("([a-zA-Z_][a-zA-Z0-9_]*)") do
      if not ref:match("^(item|index|first|last|even|odd|count)$") then
        add_symbol(ref)
      end
    end
  end

  -- Match @for collection: @for (item of collection; ...)
  for collection in template_content:gmatch("@for%s*%([^%)]+%s+of%s+([a-zA-Z_][a-zA-Z0-9_]*)") do
    add_symbol(collection)
  end

  -- Match @if/@else if conditions
  for condition in template_content:gmatch("@if%s*%(([^%)]+)%)") do
    for ref in condition:gmatch("([a-zA-Z_][a-zA-Z0-9_]*)") do
      if not ref:match("^(true|false|null|undefined|and|or|not)$") then
        add_symbol(ref)
      end
    end
  end
  for condition in template_content:gmatch("@else%s+if%s*%(([^%)]+)%)") do
    for ref in condition:gmatch("([a-zA-Z_][a-zA-Z0-9_]*)") do
      if not ref:match("^(true|false|null|undefined|and|or|not)$") then
        add_symbol(ref)
      end
    end
  end

  -- Match @switch expression
  for expr in template_content:gmatch("@switch%s*%(([^%)]+)%)") do
    for ref in expr:gmatch("([a-zA-Z_][a-zA-Z0-9_]*)") do
      add_symbol(ref)
    end
  end

  -- Match @case expressions: @case (StatusEnum.Active)
  for expr in template_content:gmatch("@case%s*%(([^%)]+)%)") do
    for ref in expr:gmatch("([a-zA-Z_][a-zA-Z0-9_]*)") do
      if not ref:match("^(true|false|null|undefined)$") then
        add_symbol(ref)
      end
    end
  end

  -- Match @let declarations: @let varName = expression
  for expr in template_content:gmatch("@let%s+[a-zA-Z_][a-zA-Z0-9_]*%s*=%s*([^;}{]+)") do
    for ref in expr:gmatch("([a-zA-Z_][a-zA-Z0-9_]*)") do
      if not ref:match("^(true|false|null|undefined)$") then
        add_symbol(ref)
      end
    end
  end

  -- Match @defer blocks: @defer (when isReady) { ... }
  for expr in template_content:gmatch("@defer%s*%(([^%)]+)%)") do
    local when_expr = expr:match("when%s+([^;%)]+)")
    if when_expr then
      for ref in when_expr:gmatch("([a-zA-Z_][a-zA-Z0-9_]*)") do
        if not ref:match("^(true|false|null|undefined)$") then
          add_symbol(ref)
        end
      end
    end
  end

  -- Legacy: Match *ngIf="condition" or *ngIf="condition; else elseBlock"
  for expr in template_content:gmatch('%*ngIf%s*=%s*"([^"]+)"') do
    -- Extract the condition part (before any ; else/then)
    local condition = expr:match("^([^;]+)")
    if condition then
      for ref in condition:gmatch("([a-zA-Z_][a-zA-Z0-9_]*)") do
        if not ref:match("^(true|false|null|undefined|let|as)$") then
          add_symbol(ref)
        end
      end
    end
  end

  -- Legacy: Match *ngFor="let item of collection; trackBy: trackFn"
  for expr in template_content:gmatch('%*ngFor%s*=%s*"([^"]+)"') do
    -- Extract collection: "let item of collection"
    local collection = expr:match("of%s+([a-zA-Z_][a-zA-Z0-9_]*)")
    if collection then
      add_symbol(collection)
    end
    -- Extract trackBy function if present
    local track_fn = expr:match("trackBy%s*:%s*([a-zA-Z_][a-zA-Z0-9_]*)")
    if track_fn then
      add_symbol(track_fn)
    end
  end

  -- Legacy: Match [ngSwitch]="expression"
  for expr in template_content:gmatch('%[ngSwitch%]%s*=%s*"([^"]+)"') do
    for ref in expr:gmatch("([a-zA-Z_][a-zA-Z0-9_]*)") do
      add_symbol(ref)
    end
  end

  -- Match ternary expressions in interpolations: {{ condition ? trueVal : falseVal }}
  for expr in template_content:gmatch("{{([^}]+)}}") do
    if expr:match("%?") then
      for ref in expr:gmatch("([a-zA-Z_][a-zA-Z0-9_]*)") do
        if not ref:match("^(true|false|null|undefined)$") then
          add_symbol(ref)
        end
      end
    end
  end

  -- Match pipe expressions: {{ value | pipeName }}
  for value in template_content:gmatch("{{%s*([a-zA-Z_][a-zA-Z0-9_]*)%s*|") do
    add_symbol(value)
  end

  -- Match async pipe: {{ observable$ | async }}
  for obs in template_content:gmatch("{{%s*([a-zA-Z_$][a-zA-Z0-9_$]*)%s*|%s*async") do
    add_symbol(obs)
  end

  -- Match custom pipe names: {{ value | myCustomPipe | sortPipe }}
  local builtin_pipes = {
    async = true, date = true, uppercase = true, lowercase = true,
    titlecase = true, currency = true, number = true, percent = true,
    json = true, slice = true, keyvalue = true,
  }
  for pipe_name in template_content:gmatch("|%s*([a-zA-Z_][a-zA-Z0-9_]*)") do
    if not builtin_pipes[pipe_name] then
      add_symbol(pipe_name)
    end
  end

  return symbols
end

---@class ComponentInput
---@field name string Internal property name
---@field alias string|nil External binding name (if aliased)
---@field required boolean Whether input is required
---@field kind string "decorator" | "signal"

---@class ComponentOutput
---@field name string Internal property name
---@field alias string|nil External event name (if aliased)
---@field kind string "decorator" | "signal"

---@class ComponentMetadata
---@field selector string|nil Component selector (e.g., "app-child")
---@field inputs ComponentInput[] List of input properties
---@field outputs ComponentOutput[] List of output properties
---@field host_bindings table<string, number> Host binding references

---Extract component metadata (selector, inputs, outputs) from component content
---@param component_content string
---@return ComponentMetadata
function M.get_component_metadata(component_content)
  if not component_content or component_content == "" then
    return { selector = nil, inputs = {}, outputs = {}, host_bindings = {} }
  end

  local metadata = {
    selector = nil,
    inputs = {},
    outputs = {},
    host_bindings = M.parse_host_bindings(component_content),
  }

  -- Extract selector from @Component decorator
  metadata.selector = component_content:match("selector%s*:%s*['\"]([^'\"]+)['\"]")

  -- Parse @Input() decorators: @Input() name, @Input('alias') name, @Input({ alias: 'x' }) name
  for line in component_content:gmatch("[^\n]+") do
    -- @Input() propName or @Input('alias') propName
    local input_simple_alias, input_simple_name = line:match("@Input%s*%(%s*['\"]([^'\"]+)['\"]%s*%)%s*([a-zA-Z_][a-zA-Z0-9_]*)")
    if input_simple_alias and input_simple_name then
      table.insert(metadata.inputs, {
        name = input_simple_name,
        alias = input_simple_alias,
        required = false,
        kind = "decorator",
      })
    else
      -- @Input() propName (no alias)
      local input_name = line:match("@Input%s*%(%s*%)%s*([a-zA-Z_][a-zA-Z0-9_]*)")
      if input_name then
        table.insert(metadata.inputs, {
          name = input_name,
          alias = nil,
          required = false,
          kind = "decorator",
        })
      else
        -- @Input({ required: true, alias: 'x' }) propName
        local input_opts, input_opts_name = line:match("@Input%s*%((%b{})%)%s*([a-zA-Z_][a-zA-Z0-9_]*)")
        if input_opts and input_opts_name then
          local alias = input_opts:match("alias%s*:%s*['\"]([^'\"]+)['\"]")
          local required = input_opts:match("required%s*:%s*true") ~= nil
          table.insert(metadata.inputs, {
            name = input_opts_name,
            alias = alias,
            required = required,
            kind = "decorator",
          })
        end
      end
    end

    -- @Output() eventName or @Output('alias') eventName
    local output_simple_alias, output_simple_name = line:match("@Output%s*%(%s*['\"]([^'\"]+)['\"]%s*%)%s*([a-zA-Z_][a-zA-Z0-9_]*)")
    if output_simple_alias and output_simple_name then
      table.insert(metadata.outputs, {
        name = output_simple_name,
        alias = output_simple_alias,
        kind = "decorator",
      })
    else
      local output_name = line:match("@Output%s*%(%s*%)%s*([a-zA-Z_][a-zA-Z0-9_]*)")
      if output_name then
        table.insert(metadata.outputs, {
          name = output_name,
          alias = nil,
          kind = "decorator",
        })
      end
    end

    -- Signal inputs: name = input<Type>() or name = input({ alias: 'x' }) or name = input.required<Type>()
    local signal_input_name = line:match("([a-zA-Z_][a-zA-Z0-9_]*)%s*=%s*input%s*[<%(.]")
    if signal_input_name then
      local alias = line:match("input%s*%(%s*{[^}]*alias%s*:%s*['\"]([^'\"]+)['\"]")
      local required = line:match("input%.required") ~= nil
      table.insert(metadata.inputs, {
        name = signal_input_name,
        alias = alias,
        required = required,
        kind = "signal",
      })
    end

    -- Signal outputs: name = output<Type>()
    local signal_output_name = line:match("([a-zA-Z_][a-zA-Z0-9_]*)%s*=%s*output%s*[<%(]")
    if signal_output_name then
      local alias = line:match("output%s*%(%s*{[^}]*alias%s*:%s*['\"]([^'\"]+)['\"]")
      table.insert(metadata.outputs, {
        name = signal_output_name,
        alias = alias,
        kind = "signal",
      })
    end

    -- Signal model (two-way binding): name = model<Type>()
    local model_name = line:match("([a-zA-Z_][a-zA-Z0-9_]*)%s*=%s*model%s*[<%(]")
    if model_name then
      local alias = line:match("model%s*%(%s*{[^}]*alias%s*:%s*['\"]([^'\"]+)['\"]")
      -- model is both input and output
      table.insert(metadata.inputs, {
        name = model_name,
        alias = alias,
        required = false,
        kind = "signal",
      })
      table.insert(metadata.outputs, {
        name = model_name .. "Change",
        alias = alias and (alias .. "Change") or nil,
        kind = "signal",
      })
    end
  end

  return metadata
end

---Extract component metadata from a buffer
---@param bufnr number
---@return ComponentMetadata
function M.get_component_metadata_for_buffer(bufnr)
  local component_path = vim.api.nvim_buf_get_name(bufnr)
  local file = io.open(component_path, "r")
  if not file then
    return { selector = nil, inputs = {}, outputs = {}, host_bindings = {} }
  end

  local content = file:read("*all")
  file:close()

  return M.get_component_metadata(content)
end

---Parse @Component decorator host bindings
---@param component_content string
---@return table<string, number> symbol_name to count mapping
function M.parse_host_bindings(component_content)
  if not component_content or component_content == "" then
    return {}
  end

  local symbols = {}
  local add_symbol = create_symbol_adder(symbols)

  -- Find host: { ... } block in @Component decorator
  local host_block = component_content:match("host%s*:%s*{([^}]+)}")
  if not host_block then
    return symbols
  end

  -- Match property bindings: '[class.active]': 'isActive' or '[attr.id]': 'componentId'
  for expr in host_block:gmatch("%'%[.-%]%'%s*:%s*%'([^%']+)%'") do
    for ref in expr:gmatch("([a-zA-Z_][a-zA-Z0-9_]*)") do
      add_symbol(ref)
    end
  end

  -- Match event bindings: '(click)': 'onClick($event)' or '(window:resize)': 'onResize($event)'
  for handler in host_block:gmatch("%'%(.-%)%'%s*:%s*%'([^%']+)%'") do
    local method = handler:match("([a-zA-Z_][a-zA-Z0-9_]*)%s*%(")
    if method then
      add_symbol(method)
    end
  end

  return symbols
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
      local file = io.open(template_path, "r")
      if file then
        local template_content = file:read("*all")
        file:close()

        local html_symbols = M.parse_template_control_flow(template_content)
        for name, count in pairs(html_symbols) do
          all_symbols[name] = (all_symbols[name] or 0) + count
        end
      end
    end

    -- Add host binding symbols from component
    local comp_file = io.open(component_path, "r")
    if comp_file then
      local comp_content = comp_file:read("*all")
      comp_file:close()

      local host_symbols = M.parse_host_bindings(comp_content)
      for name, count in pairs(host_symbols) do
        all_symbols[name] = (all_symbols[name] or 0) + count
      end
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
  local client = get_angular_client(bufnr)
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

---Get template references for a symbol (TCB-based, legacy)
---@param bufnr number
---@param symbol_name string
---@param callback fun(refs: TemplateRef[])
function M.get_template_refs(bufnr, symbol_name, callback)
  M.get_all_template_symbols(bufnr, function(symbols)
    local count = symbols[symbol_name] or 0

    if count > 0 then
      local refs = {}
      local filename = vim.api.nvim_buf_get_name(bufnr)

      for _ = 1, count do
        table.insert(refs, {
          file = filename,
          line = 0,
          column = 0,
          context = "(template reference)",
        })
      end

      callback(refs)
    else
      callback({})
    end
  end)
end

-- ============================================================================
-- LSP References-based approach (recommended)
-- Uses textDocument/references for accurate reference counting
-- ============================================================================

---Get LSP references for a position in a buffer
---@param bufnr number Buffer number
---@param line number 0-indexed line number
---@param col number 0-indexed column number
---@param callback fun(refs: table[]|nil, err: any)
function M.get_references_at_position(bufnr, line, col, callback)
  local cfg = require("angular-refs.config").get()
  local client = get_ts_client(bufnr)

  if not client then
    if cfg.debug then
      vim.notify("angular-refs: TypeScript LSP client not found", vim.log.levels.DEBUG)
    end
    callback(nil, "No TypeScript LSP client")
    return
  end

  local params = {
    textDocument = { uri = vim.uri_from_bufnr(bufnr) },
    position = { line = line, character = col },
    context = { includeDeclaration = false },
  }

  client.request("textDocument/references", params, function(err, result)
    if err then
      if cfg.debug then
        vim.notify("angular-refs: references error: " .. vim.inspect(err), vim.log.levels.DEBUG)
      end
      callback(nil, err)
      return
    end

    callback(result or {}, nil)
  end, bufnr)
end

---Filter references to exclude self-references and excluded paths
---@param refs table[] LSP reference results
---@param declaration_uri string URI of the declaration file
---@param declaration_line number 0-indexed line of the declaration
---@return number Filtered reference count
local function filter_references(refs, declaration_uri, declaration_line)
  if not refs then
    return 0
  end

  local filter = require("angular-refs.filter")
  local count = 0
  for _, ref in ipairs(refs) do
    local ref_uri = ref.uri or (ref.targetUri)
    local ref_line = ref.range and ref.range.start and ref.range.start.line

    if ref_uri and ref_line then
      local is_same_location = ref_uri == declaration_uri and ref_line == declaration_line
      local ref_path = vim.uri_to_fname(ref_uri)
      local is_excluded = filter.should_exclude(ref_path)

      if not is_same_location and not is_excluded then
        count = count + 1
      end
    end
  end

  return count
end

---Count references for a single declaration using LSP
---@param bufnr number Buffer number
---@param declaration table Declaration info {name: string, line: number, col: number}
---@param callback fun(name: string, count: number)
function M.count_references_for_declaration(bufnr, declaration, callback)
  local uri = vim.uri_from_bufnr(bufnr)

  M.get_references_at_position(bufnr, declaration.line, declaration.col, function(refs, err)
    if err or not refs then
      callback(declaration.name, 0)
      return
    end

    local count = filter_references(refs, uri, declaration.line)
    callback(declaration.name, count)
  end)
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
        for visibility, param_name in constructor_params:gmatch("(public%s+)([a-zA-Z_][a-zA-Z0-9_]*)") do
          local col = line:find(param_name) - 1
          table.insert(declarations, {
            name = param_name,
            line = line_0idx,
            col = col,
            kind = "parameter-property",
          })
        end
        for visibility, param_name in constructor_params:gmatch("(readonly%s+)([a-zA-Z_][a-zA-Z0-9_]*)") do
          local col = line:find(param_name) - 1
          table.insert(declarations, {
            name = param_name,
            line = line_0idx,
            col = col,
            kind = "parameter-property",
          })
        end
        for visibility, param_name in constructor_params:gmatch("(protected%s+)([a-zA-Z_][a-zA-Z0-9_]*)") do
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

      -- Match signal declarations: name = signal(...), input(...), output(...), model(...), computed(...)
      local signal_match = line:match("^%s*([a-zA-Z_][a-zA-Z0-9_]*)%s*=%s*signal%s*%(")
        or line:match("^%s*([a-zA-Z_][a-zA-Z0-9_]*)%s*=%s*input%s*[.%(]")
        or line:match("^%s*([a-zA-Z_][a-zA-Z0-9_]*)%s*=%s*output%s*[.%(]")
        or line:match("^%s*([a-zA-Z_][a-zA-Z0-9_]*)%s*=%s*model%s*[.%(]")
        or line:match("^%s*([a-zA-Z_][a-zA-Z0-9_]*)%s*=%s*computed%s*%(")
        or line:match("^%s*([a-zA-Z_][a-zA-Z0-9_]*)%s*=%s*linkedSignal%s*%(")
        or line:match("^%s*([a-zA-Z_][a-zA-Z0-9_]*)%s*=%s*resource%s*%(")
        or line:match("^%s*([a-zA-Z_][a-zA-Z0-9_]*)%s*=%s*rxResource%s*%(")
        or line:match("^%s*([a-zA-Z_][a-zA-Z0-9_]*)%s*=%s*viewChild%s*[.%(]")
        or line:match("^%s*([a-zA-Z_][a-zA-Z0-9_]*)%s*=%s*viewChildren%s*%(")
        or line:match("^%s*([a-zA-Z_][a-zA-Z0-9_]*)%s*=%s*contentChild%s*[.%(]")
        or line:match("^%s*([a-zA-Z_][a-zA-Z0-9_]*)%s*=%s*contentChildren%s*%(")

      if signal_match then
        local col = line:find(signal_match) - 1
        table.insert(declarations, {
          name = signal_match,
          line = line_0idx,
          col = col,
          kind = "signal",
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

---Count all references for declarations in a buffer using LSP references
---This is the primary method for getting accurate reference counts
---@param bufnr number Buffer number
---@param callback fun(symbol_counts: table<string, number>)
function M.count_all_references_lsp(bufnr, callback)
  -- Check cache first
  if refs_cache[bufnr] then
    callback(refs_cache[bufnr])
    return
  end

  local cfg = require("angular-refs.config").get()
  local declarations = M.get_declarations_in_buffer(bufnr)

  if #declarations == 0 then
    if cfg.debug then
      vim.notify("angular-refs: No declarations found in buffer", vim.log.levels.DEBUG)
    end
    callback({})
    return
  end

  if cfg.debug then
    vim.notify("angular-refs: Found " .. #declarations .. " declarations", vim.log.levels.DEBUG)
  end

  local results = {}
  local pending = #declarations

  for _, decl in ipairs(declarations) do
    M.count_references_for_declaration(bufnr, decl, function(name, count)
      results[name] = count
      pending = pending - 1

      if pending == 0 then
        -- All done, cache and return
        refs_cache[bufnr] = results

        if cfg.debug then
          local list = {}
          for n, c in pairs(results) do
            table.insert(list, string.format("  %s: %d", n, c))
          end
          table.sort(list)
          vim.notify("angular-refs: LSP reference counts:\n" .. table.concat(list, "\n"), vim.log.levels.DEBUG)
        end

        callback(results)
      end
    end)
  end
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
        for name, count in pairs(parent_refs) do
          all_refs[name] = (all_refs[name] or 0) + count
        end
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
          refs_cache[buf] = nil
        end
      end
    end
    for buf, _ in pairs(refs_cache) do
      if vim.api.nvim_buf_is_valid(buf) then
        local name = vim.api.nvim_buf_get_name(buf)
        if name == bufnr or name:match(vim.pesc(bufnr)) then
          refs_cache[buf] = nil
        end
      end
    end
  else
    tcb_cache[bufnr] = nil
    refs_cache[bufnr] = nil
  end
end

---Clear entire cache
function M.clear_cache()
  tcb_cache = {}
  refs_cache = {}
  parent_usage_cache = {}
end

---Invalidate parent usage cache (call when HTML files change)
---@param html_path string|nil Optional specific HTML file path to invalidate
function M.invalidate_parent_cache(html_path)
  if html_path then
    -- Invalidate all cache entries since any HTML change might affect any component
    parent_usage_cache = {}
  else
    parent_usage_cache = {}
  end
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

  local client = get_angular_client(bufnr)
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

M.TS_CLIENT_NAMES = TS_CLIENT_NAMES
M.ANGULAR_CLIENT_NAMES = ANGULAR_CLIENT_NAMES

return M
