-- Text parsers only: file access, LSP requests and caches belong in server.lua.
local M = {}

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
    -- Extract property references in ternary expressions: isOpen ? close() : open()
    if handler:match("%?") then
      for ref in handler:gmatch("([a-zA-Z_][a-zA-Z0-9_]*)") do
        if not ref:match("^(true|false|null|undefined|event)$") then
          add_symbol(ref)
        end
      end
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
    -- Also extract arguments from method calls: {{ method(arg1, arg2) }}
    for args in expr:gmatch("[a-zA-Z_][a-zA-Z0-9_]*%s*%(([^%)]+)%)") do
      for ref in args:gmatch("([a-zA-Z_][a-zA-Z0-9_]*)") do
        if not ref:match("^(true|false|null|undefined|this)$") then
          add_symbol(ref)
        end
      end
    end
  end

  -- Match two-way bindings: [(ngModel)]="property" or [(model)]="property"
  for prop in template_content:gmatch("%[%([%w]+%)%]%s*=%s*\"([a-zA-Z_][a-zA-Z0-9_]*)\"") do
    add_symbol(prop)
  end

  -- Match object literals in property bindings: [ngClass]="{active: isActive, disabled: isDisabled}"
  for obj_literal in template_content:gmatch('%[[%w%.%-]+%]%s*=%s*"{([^"]+)}"') do
    for value in obj_literal:gmatch(":%s*([a-zA-Z_][a-zA-Z0-9_]*)") do
      if not value:match("^(true|false|null|undefined)$") then
        add_symbol(value)
      end
    end
  end
  -- Also handle single-quoted object literals
  for obj_literal in template_content:gmatch("%[[%w%.%-]+%]%s*=%s*'{([^']+)}'") do
    for value in obj_literal:gmatch(":%s*([a-zA-Z_][a-zA-Z0-9_]*)") do
      if not value:match("^(true|false|null|undefined)$") then
        add_symbol(value)
      end
    end
  end

  -- Match @for track expressions: @for (item of items; track trackFn(item))
  for track_expr in template_content:gmatch("@for[^{]*track%s+([^;%)}{]+)") do
    for ref in track_expr:gmatch("([a-zA-Z_][a-zA-Z0-9_]*)") do
      if not ref:match("^(item|index|first|last|even|odd|count)$") then
        add_symbol(ref)
      end
    end
  end

  -- Match @for collection: @for (item of collection; ...) or @for (item of getItems(); ...)
  for collection in template_content:gmatch("@for%s*%([^%)]+%s+of%s+([a-zA-Z_][a-zA-Z0-9_]*)") do
    add_symbol(collection)
  end
  for method in template_content:gmatch("@for%s*%([^%)]+%s+of%s+([a-zA-Z_][a-zA-Z0-9_]*)%s*%(") do
    add_symbol(method)
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

  -- Match @case expressions: @case (StatusEnum.Active) - only extract root identifier
  for expr in template_content:gmatch("@case%s*%(([^%)]+)%)") do
    local root = expr:match("([a-zA-Z_][a-zA-Z0-9_]*)")
    if root and not root:match("^(true|false|null|undefined)$") then
      add_symbol(root)
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

  -- Match pipe arguments: {{ value | pipe:arg1:arg2 }}
  for pipe_expr in template_content:gmatch("{{[^}]*|[^}]+}}") do
    for arg in pipe_expr:gmatch(":([a-zA-Z_][a-zA-Z0-9_]*)") do
      if not arg:match("^(true|false|null|undefined)$") then
        add_symbol(arg)
      end
    end
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

return M
