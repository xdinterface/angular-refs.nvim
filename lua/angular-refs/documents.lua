local M = {}

local clients = require("angular-refs.clients")

local MAX_FILE_BYTES = 1024 * 1024

-- A session that never finishes (its refresh was superseded) still releases its documents
local SESSION_RELEASE_MS = 30000

---Text of a file: from its loaded buffer when there is one, otherwise read asynchronously from disk
---@param path string
---@param callback fun(text: string|nil) nil when the file is missing or larger than 1 MiB
function M.read_text(path, callback)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) == path then
      callback(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"))
      return
    end
  end

  local done = vim.schedule_wrap(callback)
  vim.uv.fs_open(path, "r", 438, function(open_err, fd)
    if open_err or not fd then
      done(nil)
      return
    end
    vim.uv.fs_fstat(fd, function(stat_err, stat)
      if stat_err or not stat or stat.size > MAX_FILE_BYTES then
        vim.uv.fs_close(fd)
        done(nil)
        return
      end
      vim.uv.fs_read(fd, stat.size, 0, function(read_err, data)
        vim.uv.fs_close(fd)
        done(not read_err and data or nil)
      end)
    end)
  end)
end

---@class AngularRefsOpenedDocument
---@field client table
---@field uri string
---@field path string
---@field users integer Sessions using the document
---@field ready boolean didOpen was sent
---@field waiters fun(ok: boolean)[]

---Documents opened on a TypeScript server, shared by all sessions
---@type table<string, AngularRefsOpenedDocument>
local opened = {}

---@param client table
---@param uri string
---@return string
local function key_of(client, uri)
  return client.id .. " " .. uri
end

---@param client table
---@param uri string
---@param on_ready fun(ok: boolean)
local function acquire(client, uri, on_ready)
  local key = key_of(client, uri)
  local document = opened[key]
  if document then
    document.users = document.users + 1
    if document.ready then
      on_ready(true)
    else
      table.insert(document.waiters, on_ready)
    end
    return
  end

  document = { client = client, uri = uri, path = vim.uri_to_fname(uri), users = 1, ready = false, waiters = { on_ready } }
  opened[key] = document
  M.read_text(document.path, function(text)
    local still_wanted = opened[key] == document
    if text and still_wanted then
      clients.notify(client, "textDocument/didOpen", {
        textDocument = { uri = uri, languageId = "typescript", version = 0, text = text },
      })
      document.ready = true
    elseif still_wanted then
      opened[key] = nil
    end
    local waiters = document.waiters
    document.waiters = {}
    for _, waiter in ipairs(waiters) do
      waiter(text ~= nil and still_wanted)
    end
  end)
end

---@param client table
---@param uri string
local function release(client, uri)
  local key = key_of(client, uri)
  local document = opened[key]
  if not document then
    return
  end
  document.users = document.users - 1
  if document.users > 0 then
    return
  end
  opened[key] = nil
  if document.ready and not clients.has_document(client, document.path) then
    clients.notify(client, "textDocument/didClose", { textDocument = { uri = uri } })
  end
end

---@class AngularRefsDocumentSession
---@field client table
---@field acquired table<string, true>
---@field release_timer uv.uv_timer_t|nil
local Session = {}
Session.__index = Session

---Documents one refresh needs open on a TypeScript server.
---Language servers only resolve definitions in documents the editor opened, so a .ts file
---without a buffer is opened until every session using it has released it.
---@param client table
---@return AngularRefsDocumentSession
function M.session(client)
  return setmetatable({ client = client, acquired = {} }, Session)
end

---Make sure the server has the document open, then call on_ready
---@param uri string
---@param on_ready fun(ok: boolean) false when the file cannot be read
function Session:ensure(uri, on_ready)
  if clients.has_document(self.client, vim.uri_to_fname(uri)) then
    on_ready(true)
    return
  end
  if not self.acquired[uri] then
    self.acquired[uri] = true
    if not self.release_timer then
      self.release_timer = vim.defer_fn(function()
        self:release_all()
      end, SESSION_RELEASE_MS)
    end
    acquire(self.client, uri, on_ready)
    return
  end
  -- Already acquired by this session: wait until it is open
  local document = opened[key_of(self.client, uri)]
  if document and not document.ready then
    table.insert(document.waiters, on_ready)
  else
    on_ready(document ~= nil)
  end
end

---Release every document this session opened
function Session:release_all()
  local timer = self.release_timer
  if timer and not timer:is_closing() then
    timer:stop()
    timer:close()
  end
  for uri in pairs(self.acquired) do
    release(self.client, uri)
  end
  self.acquired = {}
end

return M
