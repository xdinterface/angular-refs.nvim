local M = {}

local config = require("angular-refs.config")

-- Neovim 0.11 changed client methods to the method-call form and str_byteindex's signature
local HAS_NVIM_0_11 = vim.fn.has("nvim-0.11") == 1

local LOADING_START = "angular/projectLoadingStart"
local LOADING_FINISH = "angular/projectLoadingFinish"

---@type table<integer, "loading"|"ready">
local project_states = {}

---@type fun(client_id: integer)|nil
local on_ready_callback

---@type function|nil
local start_handler

---@type function|nil
local finish_handler

---@param bufnr integer
---@param names string[]
---@return table|nil
local function find_client(bufnr, names)
  for _, name in ipairs(names) do
    local found = vim.lsp.get_clients({ bufnr = bufnr, name = name })
    if #found > 0 then
      return found[1]
    end
  end
  return nil
end

---@param bufnr integer
---@return table|nil
function M.angular(bufnr)
  return find_client(bufnr, config.get().clients.angular)
end

---@param bufnr integer
---@return table|nil
function M.typescript(bufnr)
  return find_client(bufnr, config.get().clients.typescript)
end

---Project root the language server is serving
---@param client table
---@return string|nil
function M.root(client)
  local root = client.root_dir
  if not root and client.workspace_folders and client.workspace_folders[1] then
    root = client.workspace_folders[1].name
  end
  if not root then
    return nil
  end
  return (root:gsub("/+$", ""))
end

---Send an LSP request
---Neovim 0.11+ expects method-call syntax; the dot form is deprecated and removed in 0.13
---@return boolean ok, integer|nil request_id
function M.request(client, method, params, handler, bufnr)
  if HAS_NVIM_0_11 then
    return client:request(method, params, handler, bufnr)
  end
  return client.request(method, params, handler, bufnr)
end

---Send an LSP notification
---@param client table
---@param method string
---@param params table
---@return boolean
function M.notify(client, method, params)
  if HAS_NVIM_0_11 then
    return client:notify(method, params)
  end
  return client.notify(method, params)
end

---Whether a file is open in a buffer the client is attached to
---@param client table
---@param path string
---@return boolean
function M.has_document(client, path)
  for bufnr in pairs(client.attached_buffers or {}) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_get_name(bufnr) == path then
      return true
    end
  end
  return false
end

---Convert an LSP character offset on a line to a 0-based byte column
---@param line string
---@param character integer
---@param encoding string|nil "utf-8"|"utf-16"|"utf-32", defaults to "utf-16"
---@return integer
function M.byte_col(line, character, encoding)
  encoding = encoding or "utf-16"
  if encoding == "utf-8" then
    return math.min(character, #line)
  end
  local ok, col
  if HAS_NVIM_0_11 then
    ok, col = pcall(vim.str_byteindex, line, encoding, character, false)
  else
    ok, col = pcall(vim.str_byteindex, line, character, encoding == "utf-16")
  end
  return ok and col or #line
end

---@param client table
---@param request_id integer
local function cancel_request(client, request_id)
  if HAS_NVIM_0_11 then
    client:cancel_request(request_id)
  else
    client.cancel_request(request_id)
  end
end

---@param client table
---@return "loading"|"ready"|"unknown"
function M.project_state(client)
  return project_states[client.id] or "unknown"
end

---Track angularls project loading through its custom notifications.
---Chains onto global handlers so other plugins listening to them keep working.
---@param on_ready fun(client_id: integer)
function M.install_handlers(on_ready)
  on_ready_callback = on_ready

  if not start_handler or vim.lsp.handlers[LOADING_START] ~= start_handler then
    local previous_start = vim.lsp.handlers[LOADING_START]
    start_handler = function(err, result, ctx, cfg)
      project_states[ctx.client_id] = "loading"
      if previous_start then
        return previous_start(err, result, ctx, cfg)
      end
    end
    vim.lsp.handlers[LOADING_START] = start_handler
  end

  if not finish_handler or vim.lsp.handlers[LOADING_FINISH] ~= finish_handler then
    local previous_finish = vim.lsp.handlers[LOADING_FINISH]
    finish_handler = function(err, result, ctx, cfg)
      project_states[ctx.client_id] = "ready"
      if on_ready_callback then
        on_ready_callback(ctx.client_id)
      end
      if previous_finish then
        return previous_finish(err, result, ctx, cfg)
      end
    end
    vim.lsp.handlers[LOADING_FINISH] = finish_handler
  end
end

---@class AngularRefsBatch
---@field limit integer
---@field queue table[]
---@field head integer Index of the next queued job
---@field in_flight table<table, {client: table, id: integer}>
---@field in_flight_count integer
---@field cancelled boolean
local Batch = {}
Batch.__index = Batch

---Limit concurrent requests so a refresh never floods the language servers
---@param limit integer
---@return AngularRefsBatch
function M.new_batch(limit)
  return setmetatable({ limit = limit, queue = {}, head = 1, in_flight = {}, in_flight_count = 0, cancelled = false }, Batch)
end

function Batch:_pump()
  while not self.cancelled and self.in_flight_count < self.limit and self.head <= #self.queue do
    local job = self.queue[self.head]
    self.queue[self.head] = false
    self.head = self.head + 1
    local token = {}
    self.in_flight[token] = { client = job.client }
    self.in_flight_count = self.in_flight_count + 1
    local ok, request_id = M.request(job.client, job.method, job.params, function(err, result)
      if self.cancelled or not self.in_flight[token] then
        return
      end
      self.in_flight[token] = nil
      self.in_flight_count = self.in_flight_count - 1
      job.callback(err, result)
      self:_pump()
    end, job.bufnr)

    if not ok then
      self.in_flight[token] = nil
      self.in_flight_count = self.in_flight_count - 1
      job.callback({ message = "request could not be sent: " .. job.method }, nil)
    elseif self.in_flight[token] then
      self.in_flight[token].id = request_id
    end
  end
end

---@param client table
---@param method string
---@param params table
---@param bufnr integer
---@param callback fun(err: table|nil, result: any)
function Batch:request(client, method, params, bufnr, callback)
  if self.cancelled then
    return
  end
  table.insert(self.queue, { client = client, method = method, params = params, bufnr = bufnr, callback = callback })
  self:_pump()
end

function Batch:cancel()
  self.cancelled = true
  self.queue, self.head = {}, 1
  for _, entry in pairs(self.in_flight) do
    if entry.id then
      cancel_request(entry.client, entry.id)
    end
  end
  self.in_flight, self.in_flight_count = {}, 0
end

return M
