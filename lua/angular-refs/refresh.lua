local M = {}

local config = require("angular-refs.config")
local clients = require("angular-refs.clients")
local scope = require("angular-refs.scope")
local symbols = require("angular-refs.symbols")
local references = require("angular-refs.references")
local display = require("angular-refs.display")

local MAX_IN_FLIGHT = 16
local REFRESH_TIMEOUT_MS = 15000
local FIRST_RETRY_MS = 1000
local MAX_RETRY_MS = 30000

---@class AngularRefsBufferState
---@field token table|nil Identifies the refresh in flight
---@field batch AngularRefsBatch|nil
---@field stamp {changedtick: integer, generation: integer}|nil Inputs of the rendered labels
---@field running {changedtick: integer, generation: integer}|nil Inputs of the refresh in flight
---@field retry_ms integer|nil
---@field retry_timer uv.uv_timer_t|nil
---@field debounce_timer uv.uv_timer_t|nil

---@type table<integer, AngularRefsBufferState>
local states = {}

-- Bumped whenever any project file may have changed; stale stamps trigger refreshes
local generation = 0

local is_enabled = true

---@type uv.uv_timer_t|nil
local visible_timer

---@param timer uv.uv_timer_t|nil
local function stop_timer(timer)
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
  end
end

---@param delay_ms integer
---@param fn function
---@return uv.uv_timer_t
local function start_timer(delay_ms, fn)
  local timer = vim.uv.new_timer()
  timer:start(delay_ms, 0, vim.schedule_wrap(function()
    stop_timer(timer)
    fn()
  end))
  return timer
end

---@param message string
local function debug_log(message)
  if config.get().debug then
    vim.notify("angular-refs: " .. message, vim.log.levels.DEBUG)
  end
end

---@param bufnr integer
---@return AngularRefsBufferState
local function state_of(bufnr)
  states[bufnr] = states[bufnr] or {}
  return states[bufnr]
end

---@param bufnr integer
---@return boolean
local function is_candidate(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return false
  end
  local path = vim.api.nvim_buf_get_name(bufnr)
  if not path:match("%.ts$") then
    return false
  end
  return config.get().symbols.test_buffers or not scope.is_test(path)
end

---@param bufnr integer
local function schedule_retry(bufnr)
  local state = state_of(bufnr)
  state.retry_ms = math.min((state.retry_ms or FIRST_RETRY_MS / 2) * 2, MAX_RETRY_MS)
  stop_timer(state.retry_timer)
  state.retry_timer = start_timer(state.retry_ms, function()
    state.retry_timer = nil
    if states[bufnr] and not M.is_fresh(bufnr) then
      M.run(bufnr)
    end
  end)
end

---@param bufnr integer
local function cancel_in_flight(bufnr)
  local state = states[bufnr]
  if state and state.batch then
    state.batch:cancel()
  end
  if state then
    state.token, state.batch, state.running = nil, nil, nil
  end
end

---Refresh one buffer now
---@param bufnr integer
function M.run(bufnr)
  if not is_enabled or not is_candidate(bufnr) then
    return
  end
  local ng, ts = clients.angular(bufnr), clients.typescript(bufnr)
  if not ng or not ts then
    return
  end
  local root = clients.root(ng)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if not scope.gitignore_resolved(path) then
    scope.prefetch_gitignore({ path }, function()
      M.run(bufnr)
    end)
    return
  end
  if not scope.in_scope(path, root) then
    return
  end
  if clients.project_state(ng) == "loading" then
    schedule_retry(bufnr)
    return
  end

  local state = state_of(bufnr)
  local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
  local started_generation = generation
  -- A refresh for the same inputs is already in flight: restarting it would make the
  -- servers answer the same requests twice (e.g. when the project finishes loading)
  if state.running and state.running.changedtick == changedtick and state.running.generation == generation then
    return
  end

  cancel_in_flight(bufnr)
  local token = {}
  local batch = clients.new_batch(MAX_IN_FLIGHT)
  state.token, state.batch = token, batch
  state.running = { changedtick = changedtick, generation = started_generation }

  local function is_current()
    return states[bufnr] == state and state.token == token and vim.api.nvim_buf_is_valid(bufnr)
  end

  local timeout_timer

  local started_at = vim.uv.hrtime()

  local function fail()
    if is_current() then
      debug_log("refresh failed for " .. path .. ", retrying")
      stop_timer(timeout_timer)
      cancel_in_flight(bufnr)
      schedule_retry(bufnr)
    end
  end

  timeout_timer = start_timer(REFRESH_TIMEOUT_MS, fail)

  symbols.fetch(bufnr, ts, function(list)
    if not is_current() then
      return
    end
    if not list then
      fail()
      return
    end
    local ctx = {
      bufnr = bufnr,
      uri = vim.uri_from_bufnr(bufnr),
      path = path,
      root = root,
      ng = ng,
      ts = ts,
      batch = batch,
    }
    references.collect(ctx, list, function(results)
      if not is_current() then
        return
      end
      if not results then
        fail()
        return
      end
      stop_timer(timeout_timer)
      if vim.api.nvim_buf_get_changedtick(bufnr) ~= changedtick then
        -- Symbol positions describe the old text: rendering would put labels on the wrong lines
        state.token, state.batch, state.running = nil, nil, nil
        M.schedule(bufnr)
        return
      end
      local entries = {}
      for index, symbol in ipairs(list) do
        table.insert(entries, { symbol = symbol, counts = results[index] })
      end
      display.render(bufnr, entries)
      state.token, state.batch, state.running, state.retry_ms = nil, nil, nil, nil
      state.stamp = { changedtick = changedtick, generation = started_generation }
      debug_log(string.format("%s: %d symbols in %.0f ms", path, #list, (vim.uv.hrtime() - started_at) / 1e6))
    end)
  end)
end

---Refresh one buffer after the configured debounce
---@param bufnr integer
function M.schedule(bufnr)
  local state = state_of(bufnr)
  stop_timer(state.debounce_timer)
  state.debounce_timer = start_timer(config.get().trigger.debounce_ms, function()
    state.debounce_timer = nil
    M.run(bufnr)
  end)
end

---Refresh every visible buffer whose labels are stale
function M.refresh_visible()
  local seen = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local bufnr = vim.api.nvim_win_get_buf(win)
    if not seen[bufnr] and not M.is_fresh(bufnr) then
      seen[bufnr] = true
      M.run(bufnr)
    end
  end
end

---Debounced refresh_visible, for edit and save events
function M.schedule_visible()
  stop_timer(visible_timer)
  visible_timer = start_timer(config.get().trigger.debounce_ms, function()
    visible_timer = nil
    M.refresh_visible()
  end)
end

---Mark every buffer stale because a project file may have changed
function M.bump_generation()
  generation = generation + 1
  references.reset_cache()
end

---@param bufnr integer
---@return boolean
function M.is_fresh(bufnr)
  local state = states[bufnr]
  return state ~= nil
    and state.stamp ~= nil
    and vim.api.nvim_buf_is_valid(bufnr)
    and state.stamp.changedtick == vim.api.nvim_buf_get_changedtick(bufnr)
    and state.stamp.generation == generation
end

---Drop all state of a buffer (on wipe)
---@param bufnr integer
function M.detach(bufnr)
  local state = states[bufnr]
  if not state then
    return
  end
  cancel_in_flight(bufnr)
  stop_timer(state.retry_timer)
  stop_timer(state.debounce_timer)
  states[bufnr] = nil
  display.clear(bufnr)
end

---@param value boolean
function M.set_enabled(value)
  is_enabled = value
  if value then
    M.refresh_visible()
    return
  end
  for bufnr in pairs(states) do
    M.detach(bufnr)
  end
  display.clear_all()
end

---@return boolean
function M.enabled()
  return is_enabled
end

return M
