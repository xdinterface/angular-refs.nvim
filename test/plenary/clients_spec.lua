local fake = require('test.fake_client')
local clients = require('angular-refs.clients')
local config = require('angular-refs.config')

---Fake LSP client that records requests and lets the test answer them
local function fake_client(opts)
  opts = opts or {}
  local client = {
    id = opts.id or 1,
    name = opts.name or 'angularls',
    root_dir = opts.root_dir,
    workspace_folders = opts.workspace_folders,
    pending = {},
    cancelled = {},
    next_id = 0,
  }
  function client:request(method, params, handler, bufnr)
    assert(self == client and type(method) == 'string', 'client called in the wrong form for this Neovim version')
    self.next_id = self.next_id + 1
    self.pending[self.next_id] = { method = method, params = params, handler = handler, bufnr = bufnr }
    return true, self.next_id
  end
  function client:cancel_request(id)
    table.insert(self.cancelled, id)
    self.pending[id] = nil
  end
  function client:respond(id, err, result)
    local request = self.pending[id]
    self.pending[id] = nil
    request.handler(err, result, { client_id = self.id, method = request.method })
  end
  function client:in_flight()
    return vim.tbl_count(self.pending)
  end
  return fake.like_running_neovim(client)
end

describe('angular-refs.clients', function()
  local original_get_clients

  before_each(function()
    config.setup()
    original_get_clients = vim.lsp.get_clients
  end)

  after_each(function()
    vim.lsp.get_clients = original_get_clients
  end)

  describe('lookup', function()
    it('finds the angular client by configured name for the buffer', function()
      local ng = fake_client({ name = 'angular' })
      vim.lsp.get_clients = function(filter)
        assert.equals(7, filter.bufnr)
        return filter.name == 'angular' and { ng } or {}
      end
      assert.equals(ng, clients.angular(7))
    end)

    it('finds the typescript client in configured priority order', function()
      local vtsls = fake_client({ name = 'vtsls' })
      local ts_ls = fake_client({ name = 'ts_ls' })
      vim.lsp.get_clients = function(filter)
        if filter.name == 'vtsls' then
          return { vtsls }
        elseif filter.name == 'ts_ls' then
          return { ts_ls }
        end
        return {}
      end
      assert.equals(ts_ls, clients.typescript(1))
    end)

    it('respects custom client names', function()
      config.setup({ clients = { angular = { 'my-ng' } } })
      local ng = fake_client({ name = 'my-ng' })
      vim.lsp.get_clients = function(filter)
        return filter.name == 'my-ng' and { ng } or {}
      end
      assert.equals(ng, clients.angular(1))
    end)

    it('returns nil when no client is attached', function()
      vim.lsp.get_clients = function()
        return {}
      end
      assert.is_nil(clients.angular(1))
      assert.is_nil(clients.typescript(1))
    end)
  end)

  describe('root', function()
    it('strips a trailing slash from root_dir', function()
      assert.equals('/w/app', clients.root(fake_client({ root_dir = '/w/app/' })))
    end)

    it('falls back to the first workspace folder', function()
      local client = fake_client({ workspace_folders = { { name = '/w/app', uri = 'file:///w/app' } } })
      assert.equals('/w/app', clients.root(client))
    end)

    it('returns nil without root information', function()
      assert.is_nil(clients.root(fake_client()))
    end)
  end)

  describe('request', function()
    it('calls the client in the form the running Neovim version expects', function()
      local client = fake_client()
      local ok, id = clients.request(client, 'textDocument/references', {}, function() end, 1)
      assert.is_true(ok)
      assert.equals(1, id)
      assert.equals('textDocument/references', client.pending[1].method)
    end)
  end)

  describe('byte_col', function()
    it('converts UTF-16 characters after multibyte text to byte columns', function()
      local line = '<p>äö</p><app-x>'
      assert.equals(line:find('<app-x', 1, true) - 1, clients.byte_col(line, 9, 'utf-16'))
    end)

    it('treats utf-8 offsets as bytes and clamps past the end', function()
      assert.equals(2, clients.byte_col('abc', 2, 'utf-8'))
      assert.equals(3, clients.byte_col('abc', 99, 'utf-16'))
    end)
  end)

  describe('project readiness', function()
    local saved_start, saved_finish

    before_each(function()
      saved_start = vim.lsp.handlers['angular/projectLoadingStart']
      saved_finish = vim.lsp.handlers['angular/projectLoadingFinish']
    end)

    after_each(function()
      vim.lsp.handlers['angular/projectLoadingStart'] = saved_start
      vim.lsp.handlers['angular/projectLoadingFinish'] = saved_finish
    end)

    it('tracks loading state per client and calls the ready callback', function()
      local ready_ids = {}
      clients.install_handlers(function(client_id)
        table.insert(ready_ids, client_id)
      end)
      local client = fake_client({ id = 42 })
      assert.equals('unknown', clients.project_state(client))
      vim.lsp.handlers['angular/projectLoadingStart'](nil, nil, { client_id = 42 })
      assert.equals('loading', clients.project_state(client))
      vim.lsp.handlers['angular/projectLoadingFinish'](nil, nil, { client_id = 42 })
      assert.equals('ready', clients.project_state(client))
      assert.same({ 42 }, ready_ids)
    end)

    it('keeps calling a previously registered global handler', function()
      local previous_called = false
      vim.lsp.handlers['angular/projectLoadingFinish'] = function()
        previous_called = true
      end
      clients.install_handlers(function() end)
      vim.lsp.handlers['angular/projectLoadingFinish'](nil, nil, { client_id = 1 })
      assert.is_true(previous_called)
    end)

    it('does not wrap its own handler twice on repeated setup', function()
      local calls = 0
      clients.install_handlers(function()
        calls = calls + 1
      end)
      clients.install_handlers(function()
        calls = calls + 1
      end)
      vim.lsp.handlers['angular/projectLoadingFinish'](nil, nil, { client_id = 3 })
      assert.equals(1, calls)
    end)
  end)

  describe('batch', function()
    it('never exceeds the in-flight limit and drains the queue', function()
      local client = fake_client()
      local batch = clients.new_batch(2)
      local results = {}
      for i = 1, 5 do
        batch:request(client, 'm', { i = i }, 1, function(_, result)
          table.insert(results, result)
        end)
      end
      assert.equals(2, client:in_flight())
      while client:in_flight() > 0 do
        local id = next(client.pending)
        client:respond(id, nil, client.pending[id].params.i)
        assert.is_true(client:in_flight() <= 2)
      end
      table.sort(results)
      assert.same({ 1, 2, 3, 4, 5 }, results)
    end)

    it('cancels in-flight requests, drops queued ones and suppresses callbacks', function()
      local client = fake_client()
      local batch = clients.new_batch(1)
      local called = false
      batch:request(client, 'a', {}, 1, function()
        called = true
      end)
      batch:request(client, 'b', {}, 1, function()
        called = true
      end)
      local in_flight_id = next(client.pending)
      local handler = client.pending[in_flight_id].handler
      batch:cancel()
      assert.same({ in_flight_id }, client.cancelled)
      handler(nil, {}, {})
      assert.is_false(called)
      assert.equals(0, client:in_flight())
    end)

    it('reports a request that could not be sent as an error', function()
      local client = fake_client()
      function client:request()
        return false, nil
      end
      local batch = clients.new_batch(4)
      local received_err
      batch:request(client, 'a', {}, 1, function(err)
        received_err = err
      end)
      assert.is_not_nil(received_err)
    end)
  end)
end)
