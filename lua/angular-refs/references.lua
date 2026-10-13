local M = {}

local clients = require("angular-refs.clients")
local scope = require("angular-refs.scope")
local tags = require("angular-refs.tags")

local MAX_TEMPLATE_BYTES = 1024 * 1024

---@class AngularRefsContext
---@field bufnr integer
---@field uri string URI of the buffer being labelled
---@field path string File path of the buffer being labelled
---@field root string Project root
---@field ng table Angular language client
---@field ts table TypeScript language client
---@field batch AngularRefsBatch

---@type table<string, table[]>
local definition_cache = {}

---Forget cached definition results (call when any project file changed)
function M.reset_cache()
  definition_cache = {}
end

---@param location table
---@return string
local function location_key(location)
  local start = location.range.start
  return location.uri .. ":" .. start.line .. ":" .. start.character
end

---@alias AngularRefsTarget {uri: string, line: integer, character: integer}

---@param result table|table[]|nil Location | Location[] | LocationLink[]
---@return AngularRefsTarget[]
local function normalize_definitions(result)
  if not result then
    return {}
  end
  local list = (result.uri or result.targetUri) and { result } or result
  local targets = {}
  for _, item in ipairs(list) do
    local range = item.targetSelectionRange or item.range
    if range then
      table.insert(targets, { uri = item.uri or item.targetUri, line = range.start.line, character = range.start.character })
    end
  end
  return targets
end

---@param uri string
---@param position {line: integer, character: integer}
---@return table
local function position_params(uri, position)
  return { textDocument = { uri = uri }, position = position }
end

---Text of a file: from its loaded buffer when there is one, otherwise read asynchronously from disk
---@param path string
---@param callback fun(text: string|nil)
local function read_text(path, callback)
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
      if stat_err or not stat or stat.size > MAX_TEMPLATE_BYTES then
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

---@param text string
---@param position {line: integer, character: integer}
---@param encoding string|nil
---@return integer|nil offset 1-based byte offset into text
local function byte_offset(text, position, encoding)
  local offset, line = 1, 0
  while line < position.line do
    local newline = text:find("\n", offset, true)
    if not newline then
      return nil
    end
    offset = newline + 1
    line = line + 1
  end
  local line_end = text:find("\n", offset, true) or (#text + 1)
  return offset + clients.byte_col(text:sub(offset, line_end - 1), position.character, encoding)
end

---Documents opened on a TypeScript server for definition requests, shared by concurrent collects
---@type table<string, {client: table, uri: string, path: string, users: integer, ready: boolean, waiters: fun(ok: boolean)[]}>
local opened_documents = {}

---Language servers only resolve definitions in documents the editor opened, so a .ts file
---without a buffer is opened on the TypeScript server until its last user releases it
---@param client table
---@param uri string
---@param on_ready fun(ok: boolean)
local function acquire_document(client, uri, on_ready)
  local key = client.id .. " " .. uri
  local document = opened_documents[key]
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
  opened_documents[key] = document
  read_text(document.path, function(text)
    local still_wanted = opened_documents[key] == document
    if text and still_wanted then
      clients.notify(client, "textDocument/didOpen", {
        textDocument = { uri = uri, languageId = "typescript", version = 0, text = text },
      })
      document.ready = true
    elseif still_wanted then
      opened_documents[key] = nil
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
local function release_document(client, uri)
  local key = client.id .. " " .. uri
  local document = opened_documents[key]
  if not document then
    return
  end
  document.users = document.users - 1
  if document.users > 0 then
    return
  end
  opened_documents[key] = nil
  if document.ready and not clients.has_document(client, document.path) then
    clients.notify(client, "textDocument/didClose", { textDocument = { uri = uri } })
  end
end

---@param a {line: integer, character: integer}
---@param b {line: integer, character: integer}
---@return boolean
local function position_before(a, b)
  return a.line < b.line or (a.line == b.line and a.character < b.character)
end

---The name itself, or Angular wiring inside the member's own decorators
---(Angular 22 reports `@HostBinding('class.x')` as a reference of the member it decorates)
---@param symbol AngularRefsSymbol
---@param location table
---@param uri string
---@return boolean
local function on_own_declaration(symbol, location, uri)
  if location.uri ~= uri then
    return false
  end
  local start = location.range.start
  local name = { line = symbol.line, character = symbol.col }
  if start.line == name.line and start.character == name.character then
    return true
  end
  local decl_start = symbol.decl_start or name
  return not position_before(start, decl_start) and position_before(start, name)
end

---@alias AngularRefsElement {uri: string, line: integer, last_line: integer, tag: string}

---Opening tags of the template elements among a class's reference locations
---@param candidates table[] In-scope reference locations of the class
---@param encoding string|nil Offset encoding of the locations
---@param on_elements fun(elements: AngularRefsElement[]|nil) nil when a file cannot be read
local function read_elements(candidates, encoding, on_elements)
  local pending, elements, failed = #candidates, {}, false
  if pending == 0 then
    on_elements(elements)
    return
  end
  for _, location in ipairs(candidates) do
    read_text(vim.uri_to_fname(location.uri), function(text)
      if failed then
        return
      end
      if not text then
        failed = true
        on_elements(nil)
        return
      end
      local offset = byte_offset(text, location.range.start, encoding)
      local is_element = offset and (text:sub(offset, offset) == "<" or text:sub(offset - 1, offset - 1) == "<")
      local tag = is_element and tags.opening_tag(text, offset)
      if tag then
        local _, newlines = tag:gsub("\n", "")
        table.insert(elements, {
          uri = location.uri,
          line = location.range.start.line,
          last_line = location.range.start.line + newlines,
          tag = tag,
        })
      end
      pending = pending - 1
      if pending == 0 then
        on_elements(elements)
      end
    end)
  end
end

---Collect exact usage counts for every symbol of one buffer
---@param ctx AngularRefsContext
---@param symbols AngularRefsSymbol[]
---@param callback fun(results: AngularRefsCounts[]|nil) nil when any request failed
function M.collect(ctx, symbols, callback)
  local results = {}
  local remaining = #symbols
  local finished = false

  -- Documents this collect acquired on the TypeScript server, released when it ends
  ---@type table<string, true>
  local acquired = {}
  local release_timer

  local function release_documents()
    if release_timer and not release_timer:is_closing() then
      release_timer:stop()
      release_timer:close()
    end
    for uri in pairs(acquired) do
      release_document(ctx.ts, uri)
    end
    acquired = {}
  end

  local function finish_with(value)
    if not finished then
      finished = true
      release_documents()
      callback(value)
    end
  end

  local function fail()
    finish_with(nil)
  end

  local function complete(index, counts)
    if finished then
      return
    end
    results[index] = counts
    remaining = remaining - 1
    if remaining == 0 then
      finish_with(results)
    end
  end

  if remaining == 0 then
    finish_with(results)
    return
  end

  ---@param callback_fn fun(err: table|nil, result: any)
  local function request(client, method, uri, position, callback_fn)
    local params = position_params(uri, position)
    if method == "textDocument/references" then
      -- Required by the LSP spec; angularls reports the declaration anyway, see on_own_declaration
      params.context = { includeDeclaration = false }
    end
    ctx.batch:request(client, method, params, ctx.bufnr, callback_fn)
  end

  ---@param uri string
  ---@param on_ready fun(ok: boolean)
  local function ensure_document(uri, on_ready)
    if clients.has_document(ctx.ts, vim.uri_to_fname(uri)) then
      on_ready(true)
      return
    end
    if not acquired[uri] then
      acquired[uri] = true
      if not release_timer then
        -- A superseded collect never finishes; still release the documents it acquired
        release_timer = vim.defer_fn(release_documents, 30000)
      end
      acquire_document(ctx.ts, uri, on_ready)
      return
    end
    -- Already acquired by this collect: wait until it is open
    local document = opened_documents[ctx.ts.id .. " " .. uri]
    if document and not document.ready then
      table.insert(document.waiters, on_ready)
    else
      on_ready(document ~= nil)
    end
  end

  ---@param location table
  ---@param on_targets fun(targets: AngularRefsTarget[]|nil)
  local function definitions(location, on_targets)
    local cache_key = location_key(location)
    if definition_cache[cache_key] then
      on_targets(definition_cache[cache_key])
      return
    end

    local function store(targets)
      definition_cache[cache_key] = targets
      on_targets(targets)
    end

    local function ask_angular()
      request(ctx.ng, "textDocument/definition", location.uri, location.range.start, function(err, result)
        if err then
          on_targets(nil)
        else
          store(normalize_definitions(result))
        end
      end)
    end

    if not vim.uri_to_fname(location.uri):match("%.ts$") then
      ask_angular()
      return
    end
    ensure_document(location.uri, function(ok)
      if not ok then
        on_targets(nil)
        return
      end
      -- Inline templates live in .ts files, where tsserver finds no definition
      request(ctx.ts, "textDocument/definition", location.uri, location.range.start, function(err, result)
        if err then
          on_targets(nil)
          return
        end
        local targets = normalize_definitions(result)
        if #targets > 0 then
          store(targets)
        else
          ask_angular()
        end
      end)
    end)
  end

  ---Keep only locations whose definition is this symbol's declaration
  ---@param symbol AngularRefsSymbol
  ---@param locations table[]
  ---@param on_kept fun(kept: table[]|nil, dropped: boolean)
  local function filter_by_definition(symbol, locations, on_kept)
    local pending = #locations
    if pending == 0 then
      on_kept({}, false)
      return
    end
    local keep = {}
    local dropped, failed = false, false
    for index, location in ipairs(locations) do
      definitions(location, function(targets)
        if failed then
          return
        end
        if not targets then
          failed = true
          on_kept(nil, false)
          return
        end
        local matches = false
        for _, target in ipairs(targets) do
          if target.uri == ctx.uri and target.line == symbol.line and target.character == symbol.col then
            matches = true
          end
        end
        keep[index] = matches or nil
        dropped = dropped or not matches
        pending = pending - 1
        if pending == 0 then
          local kept = {}
          for i, item in ipairs(locations) do
            if keep[i] then
              table.insert(kept, item)
            end
          end
          on_kept(kept, dropped)
        end
      end)
    end
  end

  ---@type table<string, {tags: {uri: string, line: integer, last_line: integer, tag: string}[]|nil, waiters: function[]}>
  local element_cache = {}

  ---Opening tags of template elements using the symbol's class, via angularls class references
  ---@param symbol AngularRefsSymbol
  ---@param on_elements fun(elements: {uri: string, line: integer, last_line: integer, tag: string}[]|nil)
  local function class_elements(symbol, on_elements)
    local entry = element_cache[symbol.container]
    if entry then
      if entry.waiters then
        table.insert(entry.waiters, on_elements)
      else
        on_elements(entry.tags)
      end
      return
    end
    entry = { waiters = { on_elements } }
    element_cache[symbol.container] = entry

    local function resolve(elements)
      entry.tags = elements
      local waiters = entry.waiters
      entry.waiters = nil
      for _, waiter in ipairs(waiters) do
        waiter(elements)
      end
    end

    request(ctx.ng, "textDocument/references", ctx.uri, symbol.container_pos, function(err, result)
      if err or not result then
        resolve(nil)
        return
      end
      local paths = vim.tbl_map(function(location)
        return vim.uri_to_fname(location.uri)
      end, result)
      scope.prefetch_gitignore(paths, function()
        local candidates = vim.tbl_filter(function(location)
          return scope.in_scope(vim.uri_to_fname(location.uri), ctx.root)
        end, result)
        read_elements(candidates, ctx.ng.offset_encoding, resolve)
      end)
    end)
  end

  ---Parent bindings angularls misses for decorator inputs with `transform`
  ---@param symbol AngularRefsSymbol
  ---@param kept table[]
  ---@param on_extra fun(extra: table[]|nil)
  local function transform_input_bindings(symbol, kept, on_extra)
    if not (symbol.decorators.input_transform and symbol.container_pos) then
      on_extra({})
      return
    end
    class_elements(symbol, function(elements)
      if not elements then
        on_extra(nil)
        return
      end
      local binding = symbol.decorators.input_alias or symbol.name
      local extra = {}
      for _, element in ipairs(elements) do
        local already_reported = false
        for _, location in ipairs(kept) do
          local line = location.range.start.line
          if location.uri == element.uri and line >= element.line and line <= element.last_line then
            already_reported = true
          end
        end
        if not already_reported and tags.binds_input(element.tag, binding) then
          table.insert(extra, { uri = element.uri, range = { start = { line = element.line, character = 0 } } })
        end
      end
      on_extra(extra)
    end)
  end

  ---@param index integer
  ---@param symbol AngularRefsSymbol
  ---@param locations table[]
  local function process(index, symbol, locations, paths)
    local in_scope, out_of_scope = {}, 0
    for i, location in ipairs(locations) do
      if not on_own_declaration(symbol, location, ctx.uri) then
        if scope.in_scope(paths[i], ctx.root) then
          table.insert(in_scope, location)
        else
          out_of_scope = out_of_scope + 1
        end
      end
    end

    local used_in_ts, used_in_other_ts_file = false, false
    for _, location in ipairs(in_scope) do
      local path = vim.uri_to_fname(location.uri)
      if path:match("%.ts$") then
        used_in_ts = true
        used_in_other_ts_file = used_in_other_ts_file or path ~= ctx.path
      end
    end

    local function finish(kept, related)
      transform_input_bindings(symbol, kept, function(extra)
        if not extra then
          fail()
          return
        end
        local counts = { prod = 0, test = 0, related = related }
        for _, location in ipairs(vim.list_extend(vim.list_extend({}, kept), extra)) do
          if scope.is_test(vim.uri_to_fname(location.uri)) then
            counts.test = counts.test + 1
          else
            counts.prod = counts.prod + 1
          end
        end
        complete(index, counts)
      end)
    end

    -- TypeScript returns references of related members (interface, base and sibling classes)
    -- as if they were this member's; only class and interface members can be related
    local needs_filter = symbol.container ~= nil
      and (out_of_scope > 0 or used_in_other_ts_file or (symbol.container_related and used_in_ts))
    if not needs_filter then
      finish(in_scope, false)
      return
    end
    filter_by_definition(symbol, in_scope, function(kept, dropped)
      if not kept then
        fail()
        return
      end
      finish(kept, out_of_scope > 0 or dropped)
    end)
  end

  for index, symbol in ipairs(symbols) do
    local position = { line = symbol.line, character = symbol.col }
    request(ctx.ng, "textDocument/references", ctx.uri, position, function(err, result)
      if finished then
        return
      end
      if err or not result then
        fail()
        return
      end
      local paths = {}
      for _, location in ipairs(result) do
        table.insert(paths, vim.uri_to_fname(location.uri))
      end
      scope.prefetch_gitignore(paths, function()
        if not finished then
          process(index, symbol, result, paths)
        end
      end)
    end)
  end
end

return M
