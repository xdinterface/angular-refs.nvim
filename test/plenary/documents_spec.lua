local fake = require('test.fake_client')
local documents = require('angular-refs.documents')

---Fake TypeScript client that records didOpen/didClose notifications
local function ts_client()
  local client = { id = 7, name = 'ts_ls', attached_buffers = {}, notifications = {} }
  function client:notify(method, params)
    table.insert(self.notifications, method)
    self.last_text = params.textDocument.text or self.last_text
    return true
  end
  return fake.like_running_neovim(client)
end

---@return boolean|nil ok
local function ensure(session, uri)
  local result
  session:ensure(uri, function(ok)
    result = ok
  end)
  vim.wait(2000, function()
    return result ~= nil
  end, 5)
  return result
end

---@return string|nil text, boolean answered_immediately
local function read(path)
  local done, text = false, nil
  documents.read_text(path, function(result)
    done, text = true, result
  end)
  local immediate = done
  vim.wait(2000, function()
    return done
  end, 5)
  return text, immediate
end

describe('angular-refs.documents', function()
  local dir, path, uri

  before_each(function()
    dir = vim.fn.tempname()
    vim.fn.mkdir(dir, 'p')
    path = dir .. '/a.ts'
    uri = vim.uri_from_fname(path)
    vim.fn.writefile({ 'export const a = 1;' }, path)
  end)

  after_each(function()
    vim.fn.delete(dir, 'rf')
  end)

  describe('read_text', function()
    it('reads a file from disk without blocking', function()
      local text, immediate = read(path)
      assert.equals('export const a = 1;\n', text)
      assert.is_false(immediate)
    end)

    it('prefers the unsaved text of a loaded buffer', function()
      local buf = vim.fn.bufadd(path)
      vim.fn.bufload(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'export const b = 2;' })
      local text, immediate = read(path)
      vim.api.nvim_buf_delete(buf, { force = true })
      assert.equals('export const b = 2;', text)
      assert.is_true(immediate)
    end)

    it('refuses files larger than 1 MiB', function()
      local big = dir .. '/big.html'
      vim.fn.writefile({ string.rep('x', 1024 * 1024 + 1) }, big)
      assert.is_nil(read(big))
    end)

    it('returns nil for a missing file', function()
      assert.is_nil(read(dir .. '/missing.ts'))
    end)
  end)

  describe('session', function()
    it('opens a file on the server once and closes it after the last session releases it', function()
      local client = ts_client()
      local one, two = documents.session(client), documents.session(client)
      assert.is_true(ensure(one, uri))
      assert.is_true(ensure(two, uri))
      assert.same({ 'textDocument/didOpen' }, client.notifications)
      assert.equals('export const a = 1;\n', client.last_text)
      one:release_all()
      assert.same({ 'textDocument/didOpen' }, client.notifications)
      two:release_all()
      assert.same({ 'textDocument/didOpen', 'textDocument/didClose' }, client.notifications)
    end)

    it('lets several requests of one session wait for the same opening', function()
      local client = ts_client()
      local session = documents.session(client)
      local answers = {}
      for _ = 1, 3 do
        session:ensure(uri, function(ok)
          table.insert(answers, ok)
        end)
      end
      vim.wait(2000, function()
        return #answers == 3
      end, 5)
      assert.same({ true, true, true }, answers)
      assert.same({ 'textDocument/didOpen' }, client.notifications)
      session:release_all()
      assert.same({ 'textDocument/didOpen', 'textDocument/didClose' }, client.notifications)
    end)

    it('leaves files alone that the editor has open', function()
      local client = ts_client()
      local buf = vim.fn.bufadd(path)
      vim.fn.bufload(buf)
      client.attached_buffers[buf] = true
      local session = documents.session(client)
      assert.is_true(ensure(session, uri))
      session:release_all()
      vim.api.nvim_buf_delete(buf, { force = true })
      assert.same({}, client.notifications)
    end)

    it('does not close a file the editor opened in the meantime', function()
      local client = ts_client()
      local session = documents.session(client)
      assert.is_true(ensure(session, uri))
      local buf = vim.fn.bufadd(path)
      vim.fn.bufload(buf)
      client.attached_buffers[buf] = true
      session:release_all()
      vim.api.nvim_buf_delete(buf, { force = true })
      assert.same({ 'textDocument/didOpen' }, client.notifications)
    end)

    it('reports a file it cannot read', function()
      local client = ts_client()
      local session = documents.session(client)
      assert.is_false(ensure(session, vim.uri_from_fname(dir .. '/missing.ts')))
      session:release_all()
      assert.same({}, client.notifications)
    end)
  end)
end)
