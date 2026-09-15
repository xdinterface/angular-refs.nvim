local M = {}
local clients = require("angular-refs.clients")
local locations = require("angular-refs.locations")

local function reason(result, message)
	if not vim.tbl_contains(result.reasons, message) then
		table.insert(result.reasons, message)
	end
end

function M.run(bufnr, requests, callback)
	local ts, angular = clients.get_typescript(bufnr), clients.get_angular(bufnr)
	local report = {
		results = {},
		reasons = {},
		providers = {
			typescript = ts and ts.name or "unavailable",
			angular = angular and angular.name or "unavailable",
		},
		scope = (ts and ts.config and ts.config.root_dir) or vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr)),
	}
	require("angular-refs.lsp").get_symbols(bufnr, function(symbols, err, syntax)
		if err then
			report.state = "incomplete"
			report.reasons = { err.message or tostring(err) }
			callback(report)
			return
		end
		local remaining = #symbols
		if remaining == 0 then
			report.state = syntax.discovery_incomplete and "incomplete" or "complete"
			if syntax.discovery_incomplete then
				report.reasons = { "Some symbol locations could not be resolved" }
			end
			callback(report)
			return
		end
		local definitions = {}
		local definition_aliases = {}
		for _, symbol in ipairs(symbols) do
			for _, alias in ipairs(symbol.definition_aliases or {}) do
				definition_aliases[locations.key(alias)] = symbol.location
			end
		end
		local function resolve(client, candidate, done)
			if not client then
				done({}, { message = "Definition provider unavailable" })
				return
			end
			local key = tostring(client.id or client.name) .. ":" .. locations.key(candidate)
			if definitions[key] then
				if definitions[key].waiting then
					table.insert(definitions[key].waiting, done)
				else
					done(definitions[key].value, definitions[key].error)
				end
				return
			end
			definitions[key] = { waiting = { done } }
			local position = locations.position(candidate.uri, candidate.range.start, "utf-8", client.offset_encoding)
			local function finish(error, response)
				local normalized = {}
				if response and (response.uri or response.targetUri) then
					response = { response }
				end
				for _, value in ipairs(response or {}) do
					local loc = locations.normalize(value, client.offset_encoding)
					if loc then
						loc = definition_aliases[locations.key(loc)] or loc
					end
					if loc then
						table.insert(normalized, loc)
					else
						error = { message = "Unconvertible definition position" }
					end
				end
				local waiting = definitions[key].waiting
				definitions[key] = { value = normalized, error = error }
				for _, fn in ipairs(waiting) do
					fn(normalized, error)
				end
			end
			if not position then
				finish({ message = "Source unavailable for position conversion" })
				return
			end
			requests:request(client, "textDocument/definition", {
				textDocument = { uri = candidate.uri },
				position = position,
			}, finish, bufnr)
		end
		for _, symbol in ipairs(symbols) do
			local result =
				{ symbol = symbol, locations = {}, reasons = {}, state = "incomplete", implicit = symbol.implicit }
			table.insert(report.results, result)
			-- Standard references do not expose a whole-workspace coverage guarantee.
			-- Keep this explicit until a provider can supply positive coverage evidence.
			reason(result, "Workspace-wide project coverage is not established by the attached reference APIs")
			if not syntax.available then
				reason(result, "TypeScript syntax safety checks unavailable")
			end
			if syntax.discovery_incomplete then
				reason(result, "Some symbol locations could not be resolved")
			end
			if syntax.dynamic then
				reason(result, "Computed access requires additional ownership analysis")
			end
			if symbol.implicit then
				reason(result, "Angular-managed member")
			end
			local function complete()
				result.count = #result.locations
				result.state = #result.reasons == 0 and "complete" or "incomplete"
				result.unused = result.state == "complete"
					and result.count == 0
					and not result.implicit
					and not symbol.lifecycle
				remaining = remaining - 1
				if remaining == 0 then
					report.state = "complete"
					for _, entry in ipairs(report.results) do
						if entry.state ~= "complete" then
							report.state = "incomplete"
						end
					end
					callback(report)
				end
			end
			if symbol.lifecycle then
				result.hidden = true
				complete()
			elseif not symbol.precise then
				reason(result, "Declaration name position could not be verified")
				complete()
			else
				local candidates, pending = {}, 2
				local function verify()
					local list = vim.tbl_values(candidates)
					local left = #list
					if left == 0 then
						complete()
						return
					end
					local function finish_candidate()
						left = left - 1
						if left == 0 then
							complete()
						end
					end
					for _, candidate in ipairs(list) do
						local declaration = false
						for _, other in ipairs(symbols) do
							for _, location in ipairs(other.declarations) do
								if locations.contains(location, candidate) then
									declaration = true
								end
							end
						end
						if declaration then
							finish_candidate()
						else
							-- Angular candidates can originate in inline templates in .ts files.
							local preferred = candidate.angular and angular or ts
							local examine
							examine = function(defs, error, fallback)
								if (#defs == 0 or error) and fallback then
									resolve(fallback, candidate, function(ds, e)
										examine(ds, e)
									end)
									return
								end
								local matches, foreign = false, false
								for _, def in ipairs(defs) do
									local own = false
									for _, location in ipairs(symbol.declarations) do
										if locations.contains(def, location) or locations.contains(location, def) then
											own = true
										end
									end
									matches, foreign = matches or own, foreign or not own
								end
								if error or #defs == 0 or (matches and foreign) then
									reason(result, "Some reference ownership could not be resolved")
								elseif matches then
									local self_definition = false
									for _, def in ipairs(defs) do
										if locations.contains(def, candidate) then
											self_definition = true
										end
									end
									if not self_definition then
										table.insert(result.locations, candidate)
									end
								end
								finish_candidate()
							end
							resolve(preferred, candidate, function(ds, e)
								examine(ds, e, preferred == angular and ts or nil)
							end)
						end
					end
				end
				for _, provider in ipairs({
					{ client = ts, name = "TypeScript" },
					{ client = angular, name = "Angular" },
				}) do
					local client = provider.client
					local position = client
						and locations.position(
							symbol.location.uri,
							symbol.location.range.start,
							"utf-8",
							client.offset_encoding
						)
					local function received(error, refs)
						if error or refs == nil then
							reason(result, provider.name .. " reference search unavailable or incomplete")
						else
							for _, raw in ipairs(refs) do
								local loc = locations.normalize(raw, client.offset_encoding)
								if not loc then
									reason(result, "A reference location could not be normalized")
								else
									local key = locations.key(loc)
									candidates[key] = candidates[key] or loc
									candidates[key].angular = candidates[key].angular or client == angular
								end
							end
						end
						pending = pending - 1
						if pending == 0 then
							local paths = {}
							for _, loc in pairs(candidates) do
								table.insert(paths, vim.uri_to_fname(loc.uri))
							end
							local filter = require("angular-refs.filter")
							filter.prepare(paths, function(filter_error)
								if requests.cancelled then
									return
								end
								if filter_error then
									reason(result, filter_error)
								end
								for key, loc in pairs(candidates) do
									if filter.should_exclude(vim.uri_to_fname(loc.uri)) then
										candidates[key] = nil
									end
								end
								verify()
							end)
						end
					end
					if not position then
						received({ message = "Provider or source position unavailable" })
					else
						requests:request(client, "textDocument/references", {
							textDocument = { uri = symbol.location.uri },
							position = position,
							context = { includeDeclaration = false },
						}, received, bufnr)
					end
				end
			end
		end
	end, requests)
	return report
end

return M
