local M = {}
local clients = require("angular-refs.clients")
local locations = require("angular-refs.locations")

-- callback(symbols, error, syntax). Symbols have byte-based name ranges.
function M.get_symbols(bufnr, callback, requests)
	requests = requests or require("angular-refs.requests").new()
	local client = clients.get_typescript(bufnr)
	local uri = vim.uri_from_bufnr(bufnr)
	local syntax = require("angular-refs.syntax").inspect(bufnr)
	requests:request(client, "textDocument/documentSymbol", { textDocument = { uri = uri } }, function(err, result)
		if err or result == nil then
			callback({}, err or { message = "No symbol response" }, syntax)
			return
		end
		local SK, symbols, groups = vim.lsp.protocol.SymbolKind, {}, {}
		local function walk(items, owner)
			for _, item in ipairs(items) do
				local full =
					locations.normalize(item.location or { uri = uri, range = item.range }, client.offset_encoding)
				if full then
					local container = item.kind == SK.Class or item.kind == SK.Interface or item.kind == SK.Module
					local parent = owner or item.containerName
					local member = item.kind == SK.Method or item.kind == SK.Property or item.kind == SK.Field
					local top = item.kind == SK.Function
						or item.kind == SK.Constant
						or item.kind == SK.Variable
						or item.kind == SK.Enum
					if not container and (member or (not parent and top)) and not item.name:match("^_") then
						local name = item.name:gsub("^%(get%)%s+", ""):gsub("^%(set%)%s+", "")
						local selected = item.selectionRange
							and locations.normalize({ uri = uri, range = item.selectionRange }, client.offset_encoding)
						local evidence
						for _, declaration in ipairs(syntax.available and syntax.declarations or {}) do
							local loc = { uri = uri, range = declaration.range }
							if declaration.name == name and locations.contains(full, loc) then
								selected, evidence = loc, declaration
								break
							end
						end
						selected = selected or full
						local r = selected.range
						local line = locations.line(uri, r.start.line)
						local precise = r.start.line == r["end"].line
							and line
							and line:sub(r.start.character + 1, r["end"].character) == name
						if not owner and evidence and evidence.owner then
							parent = uri .. ":" .. table.concat(evidence.owner.range, ":")
						end
						local group_key = (parent or uri)
							.. ":"
							.. name
							.. (evidence and evidence.static and ":static" or ":instance")
						if item.location and not (evidence and evidence.owner) then
							group_key = locations.key(selected) -- Flat, unresolved owners must not be merged by name.
						end
						local symbol = groups[group_key]
						if not symbol then
							symbol = {
								id = locations.key(selected),
								name = name,
								owner = parent,
								kind = SK[item.kind],
								location = selected,
								range = full.range,
								declarations = {},
								definition_aliases = {},
								line = r.start.line,
								col = r.start.character,
								precise = precise == true,
								lifecycle = false,
								implicit = false,
							}
							groups[group_key] = symbol
							table.insert(symbols, symbol)
						end
						table.insert(symbol.declarations, selected)
						if evidence and evidence.definition_range then
							table.insert(symbol.definition_aliases, { uri = uri, range = evidence.definition_range })
						end
						symbol.lifecycle = symbol.lifecycle or (evidence and evidence.lifecycle) or false
						symbol.implicit = symbol.implicit or (evidence and evidence.implicit) or false
					end
					if container and item.children then
						walk(item.children, locations.key(full))
					end
				else
					syntax.discovery_incomplete = true
				end
			end
		end
		walk(result)
		callback(symbols, nil, syntax)
	end, bufnr)
end

return M
