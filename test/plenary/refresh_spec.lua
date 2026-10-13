local config = require('angular-refs.config')

local ns = vim.api.nvim_create_namespace('angular-refs')

local stub = {}

local function install_stubs()
  stub.ng = { id = 1, name = 'angularls' }
  stub.ts = { id = 2, name = 'ts_ls' }
  stub.project_state = 'ready'
  stub.attached = true
  stub.batches = {}
  stub.fetches = {}
  stub.collects = {}
  stub.resets = 0
  stub.invalidated = {}

  package.loaded['angular-refs.clients'] = {
    angular = function()
      return stub.attached and stub.ng or nil
    end,
    typescript = function()
      return stub.attached and stub.ts or nil
    end,
    root = function()
      return '/w/app'
    end,
    project_state = function()
      return stub.project_state
    end,
    new_batch = function()
      local batch = { cancelled = false }
      function batch:cancel()
        self.cancelled = true
      end
      table.insert(stub.batches, batch)
      return batch
    end,
  }
  package.loaded['angular-refs.symbols'] = {
    fetch = function(bufnr, _, callback)
      table.insert(stub.fetches, { bufnr = bufnr, callback = callback })
    end,
  }
  package.loaded['angular-refs.references'] = {
    collect = function(ctx, list, callback)
      table.insert(stub.collects, { ctx = ctx, symbols = list, callback = callback })
    end,
    reset_cache = function()
      stub.resets = stub.resets + 1
    end,
    invalidate_file = function(path)
      table.insert(stub.invalidated, path)
    end,
  }
  package.loaded['angular-refs.refresh'] = nil
  return require('angular-refs.refresh')
end

local function symbol(name, line)
  return { name = name, line = line, col = 0, kind = 'Method', decorators = { host_listener = false, host_binding = false } }
end

---Answer the newest fetch and collect with the given counts
local function answer(list, results)
  stub.fetches[#stub.fetches].callback(list)
  stub.collects[#stub.collects].callback(results)
end

local function marks(buf)
  return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
end

describe('angular-refs.refresh', function()
  local refresh, buf

  before_each(function()
    config.setup()
    refresh = install_stubs()
    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, '/w/app/src/comp' .. buf .. '.ts')
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'class A {', '  a() {}', '  b() {}', '}' })
  end)

  after_each(function()
    refresh.detach(buf)
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    for _, name in ipairs({ 'clients', 'symbols', 'references', 'refresh' }) do
      package.loaded['angular-refs.' .. name] = nil
    end
  end)

  it('does nothing without both language clients', function()
    stub.attached = false
    refresh.run(buf)
    assert.equals(0, #stub.fetches)
    assert.equals(0, #marks(buf))
  end)

  it('waits while angularls is loading the project and retries', function()
    stub.project_state = 'loading'
    refresh.run(buf)
    assert.equals(0, #stub.fetches)
    stub.project_state = 'ready'
    vim.wait(2500, function()
      return #stub.fetches > 0
    end, 20)
    assert.equals(1, #stub.fetches)
  end)

  it('renders results and stamps the buffer as fresh', function()
    refresh.run(buf)
    answer({ symbol('a', 1), symbol('b', 2) }, {
      { prod = 2, test = 0, related = false },
      { prod = 0, test = 0, related = false },
    })
    assert.equals(2, #marks(buf))
    assert.is_true(refresh.is_fresh(buf))
    assert.equals('/w/app', stub.collects[1].ctx.root)
    assert.equals(vim.uri_from_bufnr(buf), stub.collects[1].ctx.uri)
  end)

  it('is stale after an edit or a generation bump', function()
    refresh.run(buf)
    answer({ symbol('a', 1) }, { { prod = 1, test = 0, related = false } })
    vim.api.nvim_buf_set_lines(buf, 3, 3, false, { '' })
    assert.is_false(refresh.is_fresh(buf))

    refresh.run(buf)
    answer({ symbol('a', 1) }, { { prod = 1, test = 0, related = false } })
    assert.is_true(refresh.is_fresh(buf))
    refresh.bump_generation()
    assert.is_false(refresh.is_fresh(buf))
  end)

  it('invalidates one file after an edit and everything without a file', function()
    refresh.run(buf)
    answer({ symbol('a', 1) }, { { prod = 1, test = 0, related = false } })
    refresh.bump_generation('/w/app/src/other.ts')
    assert.is_false(refresh.is_fresh(buf))
    assert.same({ '/w/app/src/other.ts' }, stub.invalidated)
    assert.equals(0, stub.resets)
    refresh.bump_generation()
    assert.equals(1, stub.resets)
  end)

  it('keeps previous labels when a refresh fails and retries', function()
    refresh.run(buf)
    answer({ symbol('a', 1) }, { { prod = 1, test = 0, related = false } })
    refresh.bump_generation()
    refresh.run(buf)
    answer({ symbol('a', 1) }, nil)
    assert.equals(1, #marks(buf))
    assert.is_false(refresh.is_fresh(buf))
    vim.wait(2500, function()
      return #stub.fetches == 3
    end, 20)
    assert.equals(3, #stub.fetches)
  end)

  it('checks whether its own file is gitignored in the background before counting', function()
    config.setup({ scope = { respect_gitignore = true } })
    refresh.run(buf)
    assert.equals(0, #stub.fetches)
    vim.wait(5000, function()
      return #stub.fetches == 1
    end, 20)
    assert.equals(1, #stub.fetches)
  end)

  it('does not render results for text that changed while counting, and counts again', function()
    refresh.run(buf)
    stub.fetches[1].callback({ symbol('a', 1) })
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, { '// inserted above the symbol' })
    stub.collects[1].callback({ { prod = 1, test = 0, related = false } })
    assert.equals(0, #marks(buf))
    assert.is_false(refresh.is_fresh(buf))
    vim.wait(2000, function()
      return #stub.fetches == 2
    end, 20)
    assert.equals(2, #stub.fetches)
  end)

  it('keeps previous labels when symbols cannot be fetched', function()
    refresh.run(buf)
    answer({ symbol('a', 1) }, { { prod = 1, test = 0, related = false } })
    refresh.bump_generation()
    refresh.run(buf)
    stub.fetches[2].callback(nil)
    assert.equals(1, #marks(buf))
    assert.equals(1, #stub.collects)
  end)

  it('lets a running refresh finish when triggered again without changes', function()
    refresh.run(buf)
    refresh.run(buf)
    refresh.refresh_visible()
    assert.equals(1, #stub.fetches)
    assert.is_false(stub.batches[1].cancelled)
    answer({ symbol('a', 1) }, { { prod = 1, test = 0, related = false } })
    assert.is_true(refresh.is_fresh(buf))
  end)

  it('restarts a running refresh after a project change', function()
    refresh.run(buf)
    refresh.bump_generation()
    refresh.run(buf)
    assert.equals(2, #stub.fetches)
    assert.is_true(stub.batches[1].cancelled)
  end)

  it('cancels an older refresh and ignores its results', function()
    refresh.run(buf)
    stub.fetches[1].callback({ symbol('a', 1) })
    local older_collect = stub.collects[1]
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, { '' })
    refresh.run(buf)
    assert.is_true(stub.batches[1].cancelled)
    answer({ symbol('b', 2) }, { { prod = 5, test = 0, related = false } })
    older_collect.callback({ { prod = 0, test = 0, related = false } })
    local found = marks(buf)
    assert.equals(1, #found)
    assert.equals(2, found[1][2])
  end)

  it('skips test buffers unless enabled', function()
    vim.api.nvim_buf_set_name(buf, '/w/app/src/comp.spec.ts')
    refresh.run(buf)
    assert.equals(0, #stub.fetches)
    config.setup({ symbols = { test_buffers = true } })
    refresh.run(buf)
    assert.equals(1, #stub.fetches)
  end)

  it('skips files outside the project scope', function()
    vim.api.nvim_buf_set_name(buf, '/w/app/node_modules/lib/index.ts')
    refresh.run(buf)
    assert.equals(0, #stub.fetches)
  end)

  it('survives a buffer wiped mid-refresh', function()
    refresh.run(buf)
    local fetch = stub.fetches[1]
    vim.api.nvim_buf_delete(buf, { force = true })
    assert.has_no.errors(function()
      fetch.callback({ symbol('a', 1) })
      if stub.collects[1] then
        stub.collects[1].callback({ { prod = 1, test = 0, related = false } })
      end
    end)
    refresh.detach(buf)
    assert.is_false(refresh.is_fresh(buf))
  end)

  describe('debug logging', function()
    local messages, original_notify

    before_each(function()
      messages = {}
      original_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(messages, { msg = msg, level = level })
      end
    end)

    after_each(function()
      vim.notify = original_notify
    end)

    it('reports rendered refreshes and failures when debug is on', function()
      config.setup({ debug = true })
      refresh.run(buf)
      answer({ symbol('a', 1) }, { { prod = 1, test = 0, related = false } })
      refresh.bump_generation()
      refresh.run(buf)
      answer({ symbol('a', 1) }, nil)
      assert.equals(2, #messages)
      assert.truthy(messages[1].msg:find('1 symbols', 1, true))
      assert.truthy(messages[2].msg:find('failed', 1, true))
      assert.equals(vim.log.levels.DEBUG, messages[1].level)
    end)

    it('stays silent when debug is off', function()
      refresh.run(buf)
      answer({ symbol('a', 1) }, nil)
      assert.equals(0, #messages)
    end)
  end)

  it('clears labels and stops refreshing when toggled off', function()
    refresh.run(buf)
    answer({ symbol('a', 1) }, { { prod = 1, test = 0, related = false } })
    refresh.set_enabled(false)
    assert.is_false(refresh.enabled())
    assert.equals(0, #marks(buf))
    refresh.run(buf)
    assert.equals(1, #stub.fetches)
    refresh.set_enabled(true)
  end)
end)
