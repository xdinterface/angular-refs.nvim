local M = {}
local config = require("angular-refs.config")
local ns = vim.api.nvim_create_namespace("angular-refs")
local runs, reports, timers = {}, {}, {}
local revision = 0

local function stop(timer)
	if timer then
		vim.fn.timer_stop(timer)
	end
end

local function valid(buf)
	return vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf)
end

function M.render_results(buf, report)
	if not valid(buf) or not config.is_enabled() then
		return
	end
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	local cfg, lines = config.get().display, {}
	for _, result in ipairs(report.results) do
		if not result.hidden then
			local text
			if result.unused then
				text = cfg.format_zero
			elseif result.count == 0 and result.state ~= "complete" then
				text = cfg.format_unknown
			elseif result.state ~= "complete" then
				text = string.format(cfg.format_incomplete, result.count)
			else
				text = string.format(result.count == 1 and cfg.format_singular or cfg.format, result.count)
			end
			local row = result.symbol.line
			lines[row] = lines[row] or {}
			table.insert(lines[row], { result = result, text = text })
		end
	end
	for row, entries in pairs(lines) do
		if row < vim.api.nvim_buf_line_count(buf) then
			table.sort(entries, function(a, b)
				return a.result.symbol.col < b.result.symbol.col
			end)
			local chunks = {}
			for _, entry in ipairs(entries) do
				table.insert(chunks, {
					cfg.separator .. (#entries > 1 and entry.result.symbol.name .. ": " or "") .. entry.text,
					entry.result.unused and cfg.zero_refs_highlight or cfg.highlight,
				})
			end
			local opts = { hl_mode = "combine" }
			if cfg.position == "above" then
				opts.virt_lines, opts.virt_lines_above = { chunks }, true
			else
				opts.virt_text, opts.virt_text_pos = chunks, "eol"
			end
			vim.api.nvim_buf_set_extmark(buf, ns, row, 0, opts)
		end
	end
end

function M.update(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	if not config.is_enabled() or not valid(buf) then
		return
	end
	local path = vim.api.nvim_buf_get_name(buf)
	if path == "" or require("angular-refs.filter").should_exclude(path) then
		return
	end
	stop(timers[buf])
	timers[buf] = nil
	if runs[buf] then
		runs[buf].dirty = true
		return
	end
	local clients = require("angular-refs.clients")
	local run = {
		tick = vim.api.nvim_buf_get_changedtick(buf),
		revision = revision,
		ts = clients.get_typescript(buf),
		angular = clients.get_angular(buf),
		requests = require("angular-refs.requests").new(config.get().analysis.max_concurrent_requests),
	}
	runs[buf] = run
	reports[buf] = { state = "loading", results = {}, reasons = {}, scope = path }
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	local function finish(report)
		if runs[buf] ~= run then
			return
		end
		stop(run.timer)
		run.requests:cancel()
		runs[buf] = nil
		if not valid(buf) or not config.is_enabled() then
			return
		end
		local stale = run.tick ~= vim.api.nvim_buf_get_changedtick(buf)
			or run.revision ~= revision
			or run.ts ~= clients.get_typescript(buf)
			or run.angular ~= clients.get_angular(buf)
		if not stale then
			report.tick, report.revision = run.tick, run.revision
			report.finished_at = vim.uv.hrtime()
			reports[buf] = report
			M.render_results(buf, report)
		end
		if stale or run.dirty then
			M.schedule_update(buf, true)
		end
	end
	run.timer = vim.fn.timer_start(config.get().analysis.timeout_ms, function()
		vim.schedule(function()
			if runs[buf] ~= run then
				return
			end
			local partial = run.partial or { results = {} }
			partial.state, partial.reasons = "incomplete", { "Analysis timed out" }
			for _, result in ipairs(partial.results) do
				result.count, result.state, result.unused = #result.locations, "incomplete", false
				table.insert(result.reasons, "Analysis timed out")
			end
			finish(partial)
		end)
	end)
	local filter = require("angular-refs.filter")
	filter.prepare({ path }, function(filter_error)
		if runs[buf] ~= run then
			return
		end
		if filter.should_exclude(path) then
			finish({ state = "excluded", results = {}, reasons = { "Document excluded from analysis" } })
			return
		end
		run.partial = require("angular-refs.analysis").run(buf, run.requests, function(report)
			if filter_error then
				report.state = "incomplete"
				report.reasons = report.reasons or {}
				table.insert(report.reasons, filter_error)
			end
			finish(report)
		end)
	end)
end

function M.schedule_update(buf, force)
	if not valid(buf) or not config.is_enabled() then
		return
	end
	local cached = reports[buf]
	if
		not force
		and cached
		and cached.finished_at
		and cached.revision == revision
		and cached.tick == vim.api.nvim_buf_get_changedtick(buf)
		and (vim.uv.hrtime() - cached.finished_at) / 1e6 < config.get().analysis.timeout_ms
	then
		return
	end
	stop(timers[buf])
	if runs[buf] then
		runs[buf].dirty = true
		return
	end
	local timer
	timer = vim.fn.timer_start(config.get().trigger.debounce_ms, function()
		vim.schedule(function()
			if timers[buf] ~= timer then
				return
			end
			timers[buf] = nil
			if valid(buf) then
				M.update(buf)
			end
		end)
	end)
	timers[buf] = timer
end

function M.clear(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	stop(timers[buf])
	timers[buf] = nil
	local run = runs[buf]
	runs[buf], reports[buf] = nil, nil
	if run then
		stop(run.timer)
		run.requests:cancel()
	end
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	end
end

-- Conservatively invalidate all observed documents: cross-project imports can
-- connect different client roots. No filesystem scan or name-based owner cache.
function M.invalidate()
	revision = revision + 1
	local buffers = {}
	for buf in pairs(reports) do
		table.insert(buffers, buf)
	end
	for _, buf in ipairs(buffers) do
		M.clear(buf)
		if valid(buf) then
			M.schedule_update(buf)
		end
	end
end

function M.get_report(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	local report = reports[buf]
	if report and report.tick and valid(buf) and report.tick ~= vim.api.nvim_buf_get_changedtick(buf) then
		return { state = "stale", results = {}, reasons = { "Buffer changed since analysis" } }
	end
	return report
end

function M.get_unused(buf)
	local report = M.get_report(buf)
	local unused = {}
	for _, result in ipairs(report and report.results or {}) do
		if result.unused then
			table.insert(unused, {
				name = result.symbol.name,
				line = result.symbol.line + 1,
				col = result.symbol.col + 1,
				kind = result.symbol.kind,
			})
		end
	end
	table.sort(unused, function(a, b)
		return a.line == b.line and a.col < b.col or a.line < b.line
	end)
	return unused, report and report.state or "not analyzed"
end

return M
