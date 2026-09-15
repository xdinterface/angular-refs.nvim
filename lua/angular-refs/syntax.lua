-- Optional syntax evidence. Failure to parse is uncertainty, never evidence of zero uses.
local M = {}
local hooks = {
	ngOnInit = true,
	ngOnDestroy = true,
	ngOnChanges = true,
	ngDoCheck = true,
	ngAfterContentInit = true,
	ngAfterContentChecked = true,
	ngAfterViewInit = true,
	ngAfterViewChecked = true,
}

function M.inspect(bufnr)
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr, "typescript")
	if not ok or not parser then
		return { available = false }
	end
	local parsed, trees = pcall(parser.parse, parser)
	if not parsed or not trees[1] then
		return { available = false }
	end
	local root = trees[1]:root()
	local result = { available = not root:has_error(), classes = {}, declarations = {}, dynamic = false }
	local imports = {}
	local text = function(node)
		return vim.treesitter.get_node_text(node, bufnr)
	end
	-- Resolve local aliases of Angular imports. Namespace imports are handled too.
	for node in root:iter_children() do
		if node:type() == "import_statement" then
			local source = node:field("source")[1]
			local module = source and text(source):match("^['\"](@angular/[%w_-]+)['\"]$")
			if module == "@angular/core" or module == "@angular/forms" then
				local function visit_import(n)
					if n:type() == "import_specifier" then
						local name, alias = n:field("name")[1], n:field("alias")[1]
						if name then
							imports[text(alias or name)] = (module == "@angular/forms" and "forms:" or "") .. text(name)
						end
					elseif n:type() == "namespace_import" then
						local name = n:named_child(0)
						if name then
							imports[text(name)] = module == "@angular/forms" and "forms:*" or "*"
						end
					end
					for child in n:iter_children() do
						visit_import(child)
					end
				end
				visit_import(node)
			end
		end
	end
	local function angular_name(name)
		local namespace, member = name:match("^([%w_$]+)%.([%w_$]+)$")
		return imports[name]
			or (namespace and imports[namespace] == "*" and member)
			or (namespace and imports[namespace] == "forms:*" and "forms:" .. member)
			or nil
	end
	local function decorators(node)
		local found = {}
		local function record(child)
			if child:type() == "decorator" then
				local call = child:named_child(0)
				local fn = call and (call:field("function")[1] or call)
				local name = fn and angular_name(text(fn))
				if name then
					found[name] = true
				end
			end
		end
		for child in node:iter_children() do
			record(child)
		end
		-- Method decorators are siblings in the TypeScript grammar; field
		-- decorators are children. Never borrow decorators across another member.
		local previous = node:prev_named_sibling()
		while previous and previous:type() == "decorator" do
			record(previous)
			previous = previous:prev_named_sibling()
		end
		return found
	end
	local function visit(node, owner)
		local kind = node:type()
		if kind == "class_declaration" or kind == "abstract_class_declaration" then
			local ds = decorators(node)
			-- Some grammar versions place decorators on the export statement.
			if node:parent() and node:parent():type() == "export_statement" then
				ds = vim.tbl_extend("force", decorators(node:parent()), ds)
			end
			owner = {
				angular = ds.Component or ds.Directive or ds.Injectable or ds.Pipe,
				pipe = ds.Pipe,
				range = { node:range() },
				name = text(node:field("name")[1]),
			}
			local function heritage(n)
				if n:type() == "type_identifier" or n:type() == "nested_type_identifier" then
					if angular_name(text(n)) == "forms:ControlValueAccessor" then
						owner.cva = true
					end
				end
				if n:type() == "extends_clause" then
					local base = n:field("value")[1] or n:named_child(0)
					if base then
						owner.base = text(base)
					end
				end
				for child in n:iter_children() do
					heritage(child)
				end
			end
			for child in node:iter_children() do
				if child:type() == "class_heritage" then
					heritage(child)
				end
			end
			table.insert(result.classes, owner)
		end
		if kind == "subscript_expression" then
			result.dynamic = true
		end
		local name = node:field("name")[1]
		if
			name
			and (
				kind == "method_definition"
				or kind == "method_signature"
				or kind == "public_field_definition"
				or kind == "property_signature"
				or kind == "function_declaration"
				or kind == "variable_declarator"
			)
		then
			local row, col, erow, ecol = name:range()
			local ds = decorators(node)
			local value = node:field("value")[1]
			local factory
			local static = false
			for child in node:iter_children() do
				if child:type() == "static" then
					static = true
				end
			end
			if value and value:type() == "call_expression" then
				local fn = value:field("function")[1]
				if fn then
					factory = angular_name(text(fn):gsub("%.required$", ""))
				end
			end
			local definition_range
			if value and (value:type() == "arrow_function" or value:type() == "function_expression") then
				local sr, sc, er, ec = value:range()
				definition_range = { start = { line = sr, character = sc }, ["end"] = { line = er, character = ec } }
			end
			table.insert(result.declarations, {
				name = text(name),
				owner = owner,
				static = static,
				definition_range = definition_range,
				range = { start = { line = row, character = col }, ["end"] = { line = erow, character = ecol } },
				lifecycle = owner and owner.angular and hooks[text(name)] or false,
				implicit = ds.HostListener
					or ds.HostBinding
					or ds.Input
					or ds.Output
					or ds.ViewChild
					or ds.ViewChildren
					or ds.ContentChild
					or ds.ContentChildren
					or factory == "input"
					or factory == "output"
					or factory == "model"
					or factory == "viewChild"
					or factory == "viewChildren"
					or factory == "contentChild"
					or factory == "contentChildren"
					or (owner and owner.cva and vim.tbl_contains(
						{ "writeValue", "registerOnChange", "registerOnTouched", "setDisabledState" },
						text(name)
					))
					or (owner and owner.pipe and text(name) == "transform")
					or false,
			})
		end
		for child in node:iter_children() do
			visit(child, owner)
		end
	end
	visit(root)
	-- Propagate Angular context through resolvable same-file inheritance. Imported
	-- or ambiguous bases remain unknown, rather than classified by method name.
	for _ = 1, #result.classes do
		for _, class in ipairs(result.classes) do
			if class.base and not class.angular then
				local matches = {}
				for _, base in ipairs(result.classes) do
					if base.name == class.base then
						table.insert(matches, base)
					end
				end
				if #matches == 1 then
					class.angular = matches[1].angular
				end
			end
		end
	end
	for _, declaration in ipairs(result.declarations) do
		declaration.lifecycle = declaration.owner and declaration.owner.angular and hooks[declaration.name] or false
	end
	return result
end

return M
