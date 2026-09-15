local M = {}

function M.line(uri, row)
	local ok, path = pcall(vim.uri_to_fname, uri)
	if not ok then
		return nil
	end
	local buf = vim.fn.bufnr(path)
	if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
		return vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
	end
	local read, lines = pcall(vim.fn.readfile, path, "", row + 1)
	return read and lines[row + 1] or nil
end

function M.position(uri, position, from, to)
	from, to = from or "utf-16", to or "utf-16"
	if from == to then
		return vim.deepcopy(position)
	end
	local line = M.line(uri, position.line)
	if not line then
		return nil
	end
	local ok, byte = pcall(vim.str_byteindex, line, from, position.character, false)
	if not ok then
		return nil
	end
	local converted, col = pcall(vim.str_utfindex, line, to, byte, false)
	if not converted then
		return nil
	end
	return { line = position.line, character = col }
end

-- All stored ranges use byte columns; wire positions are converted at the edge.
function M.normalize(location, encoding)
	local uri = location.uri or location.targetUri
	local range = location.targetSelectionRange or location.range or location.targetRange
	if not uri or not range or not range.start or not range["end"] then
		return nil
	end
	local ok, path = pcall(vim.uri_to_fname, uri)
	if not ok then
		return nil
	end
	uri = vim.uri_from_fname(vim.fs.normalize(path))
	local start = M.position(uri, range.start, encoding, "utf-8")
	local finish = M.position(uri, range["end"], encoding, "utf-8")
	if not start or not finish then
		return nil
	end
	return { uri = uri, range = { start = start, ["end"] = finish } }
end

function M.key(location)
	local r = location.range
	return table.concat({ location.uri, r.start.line, r.start.character, r["end"].line, r["end"].character }, ":")
end

local function before(a, b)
	return a.line < b.line or (a.line == b.line and a.character < b.character)
end

function M.contains(outer, inner)
	return outer.uri == inner.uri
		and not before(inner.range.start, outer.range.start)
		and not before(outer.range["end"], inner.range["end"])
end

return M
