local fake = require('test.fake_client')
local references = require('angular-refs.references')
local clients = require('angular-refs.clients')
local config = require('angular-refs.config')

local NIL_RESULT = {}

local function loc(path, line, character)
  return {
    uri = vim.uri_from_fname(path),
    range = { start = { line = line, character = character }, ['end'] = { line = line, character = character + 1 } },
  }
end

local function key(method, path, line, character)
  return method .. ' ' .. vim.uri_from_fname(path) .. ':' .. line .. ':' .. character
end

---Fake client answering from `routes` (method + position -> response); unknown positions get `{}`
local function fake_client(name, routes)
  local client = { name = name, id = name == 'angularls' and 1 or 2, offset_encoding = 'utf-16', calls = {}, params = {} }
  function client:request(method, params, handler)
    local k = method .. ' ' .. params.textDocument.uri .. ':' .. params.position.line .. ':' .. params.position.character
    table.insert(self.calls, k)
    table.insert(self.params, { method = method, params = params })
    local response = routes[k]
    if response == NIL_RESULT then
      handler(nil, nil)
    elseif type(response) == 'table' and response.err then
      handler(response.err, nil)
    else
      handler(nil, response or {})
    end
    return true, #self.calls
  end
  function client:cancel_request() end
  return fake.like_running_neovim(client)
end

local function symbol(overrides)
  return vim.tbl_deep_extend('force', {
    name = 'value',
    line = 10,
    col = 2,
    kind = 'Property',
    container = 'Comp',
    container_pos = { line = 3, character = 13 },
    container_related = false,
    decorators = { host_listener = false, host_binding = false, input_transform = false },
  }, overrides or {})
end

local root = '/w/app'
local comp = '/w/app/src/comp.ts'

local function context(ng, ts)
  return {
    bufnr = 0,
    uri = vim.uri_from_fname(comp),
    path = comp,
    root = root,
    ng = ng,
    ts = ts,
    batch = clients.new_batch(16),
  }
end

---Run collect and wait for its (possibly async) callback
local function collect(ctx, list)
  local done, results = false, nil
  references.collect(ctx, list, function(r)
    done, results = true, r
  end)
  vim.wait(2000, function()
    return done
  end, 5)
  assert.is_true(done, 'collect never called back')
  return results
end

local REFS = 'textDocument/references'
local DEF = 'textDocument/definition'

describe('angular-refs.references', function()
  local real_has_document = clients.has_document

  before_each(function()
    config.setup()
    references.reset_cache()
    -- Fake paths below do not exist on disk; treat every document as open in the editor
    clients.has_document = function()
      return true
    end
  end)

  after_each(function()
    clients.has_document = real_has_document
  end)

  it('drops the declaration and counts production usages', function()
    local ng = fake_client('angularls', {
      [key(REFS, comp, 10, 2)] = { loc(comp, 10, 2), loc('/w/app/src/comp.html', 5, 10), loc(comp, 20, 9) },
    })
    local ts = fake_client('ts_ls', {})
    local results = collect(context(ng, ts), { symbol() })
    assert.same({ prod = 2, test = 0, related = false }, results[1])
    assert.equals(0, #ts.calls)
  end)

  it('sends spec-compliant reference requests that exclude the declaration', function()
    local ng = fake_client('angularls', { [key(REFS, comp, 10, 2)] = { loc(comp, 20, 9) } })
    collect(context(ng, fake_client('ts_ls', {})), { symbol() })
    assert.equals(REFS, ng.params[1].method)
    assert.same({ includeDeclaration = false }, ng.params[1].params.context)
  end)

  it('ignores references inside the symbol own decorators', function()
    local ng = fake_client('angularls', {
      [key(REFS, comp, 10, 27)] = { loc(comp, 10, 16), loc('/w/app/src/comp.html', 1, 1) },
    })
    local results = collect(context(ng, fake_client('ts_ls', {})), {
      symbol({ col = 27, decl_start = { line = 10, character = 2 } }),
    })
    assert.same({ prod = 1, test = 0, related = false }, results[1])
  end)

  it('counts usages in test files separately', function()
    local ng = fake_client('angularls', {
      [key(REFS, comp, 10, 2)] = { loc('/w/app/src/comp.spec.ts', 4, 4) },
    })
    local ts = fake_client('ts_ls', { [key(DEF, '/w/app/src/comp.spec.ts', 4, 4)] = { loc(comp, 10, 2) } })
    local results = collect(context(ng, ts), { symbol() })
    assert.same({ prod = 0, test = 1, related = false }, results[1])
  end)

  it('marks out-of-scope usages as related and keeps only usages resolving to the symbol', function()
    local ng = fake_client('angularls', {
      [key(REFS, comp, 10, 2)] = {
        loc('/w/app/node_modules/@angular/core/index.d.ts', 700, 2),
        loc('/w/app/src/sub.ts', 3, 10),
        loc('/w/app/src/other.ts', 4, 6),
      },
    })
    local ts = fake_client('ts_ls', {
      [key(DEF, '/w/app/src/sub.ts', 3, 10)] = { loc(comp, 10, 2) },
      [key(DEF, '/w/app/src/other.ts', 4, 6)] = { loc('/w/app/src/other.ts', 1, 2) },
    })
    local results = collect(context(ng, ts), { symbol({ name = 'ngOnInit' }) })
    assert.same({ prod = 1, test = 0, related = true }, results[1])
    assert.equals(2, #ts.calls)
  end)

  it('tells apart members declared on the same line', function()
    local ng = fake_client('angularls', {
      [key(REFS, comp, 10, 2)] = { loc('/w/app/src/use.ts', 3, 10), loc('/w/app/src/other.ts', 4, 6) },
    })
    local ts = fake_client('ts_ls', {
      -- `a = 1; b = 2;` on line 10: the second usage resolves to `b` at character 9
      [key(DEF, '/w/app/src/use.ts', 3, 10)] = { loc(comp, 10, 2) },
      [key(DEF, '/w/app/src/other.ts', 4, 6)] = { loc(comp, 10, 9) },
    })
    local results = collect(context(ng, ts), { symbol() })
    assert.same({ prod = 1, test = 0, related = true }, results[1])
  end)

  it('filters members of classes with heritage when another .ts file uses them', function()
    local ng = fake_client('angularls', {
      [key(REFS, comp, 10, 2)] = { loc('/w/app/src/other.ts', 1, 1) },
    })
    local ts = fake_client('ts_ls', {
      [key(DEF, '/w/app/src/other.ts', 1, 1)] = { loc(comp, 10, 2) },
    })
    local results = collect(context(ng, ts), { symbol({ container_related = true }) })
    assert.same({ prod = 1, test = 0, related = false }, results[1])
    assert.equals(1, #ts.calls)
  end)

  it('does not filter heritage-class members used only in templates', function()
    local ng = fake_client('angularls', {
      [key(REFS, comp, 10, 2)] = { loc('/w/app/src/comp.html', 2, 4), loc('/w/app/src/comp.html', 3, 4) },
    })
    local ts = fake_client('ts_ls', {})
    local results = collect(context(ng, ts), { symbol({ container_related = true }) })
    assert.equals(2, results[1].prod)
    assert.equals(0, #ts.calls)
  end)

  it('filters heritage-class members used in their own file (interface in the same file)', function()
    local ng = fake_client('angularls', {
      [key(REFS, comp, 10, 2)] = { loc(comp, 2, 2), loc(comp, 30, 9) },
    })
    local ts = fake_client('ts_ls', {
      [key(DEF, comp, 2, 2)] = { loc(comp, 2, 2) },
      [key(DEF, comp, 30, 9)] = { loc(comp, 2, 2) },
    })
    local results = collect(context(ng, ts), { symbol({ container_related = true }) })
    assert.same({ prod = 0, test = 0, related = true }, results[1])
  end)

  it('filters members used from another .ts file even without heritage (base classes)', function()
    local ng = fake_client('angularls', {
      [key(REFS, comp, 10, 2)] = { loc('/w/app/src/child.ts', 5, 11), loc('/w/app/src/use.ts', 8, 4) },
    })
    local ts = fake_client('ts_ls', {
      [key(DEF, '/w/app/src/child.ts', 5, 11)] = { loc('/w/app/src/child.ts', 5, 11) },
      [key(DEF, '/w/app/src/use.ts', 8, 4)] = { loc(comp, 10, 2) },
    })
    local results = collect(context(ng, ts), { symbol() })
    assert.same({ prod = 1, test = 0, related = true }, results[1])
  end)

  it('never filters top-level functions', function()
    local ng = fake_client('angularls', {
      [key(REFS, comp, 10, 2)] = { loc('/w/app/src/use.ts', 8, 4), loc('/w/app/src/other.ts', 2, 4) },
    })
    local ts = fake_client('ts_ls', {})
    local fn = symbol({ kind = 'Function' })
    fn.container, fn.container_pos = nil, nil
    local results = collect(context(ng, ts), { fn })
    assert.same({ prod = 2, test = 0, related = false }, results[1])
    assert.equals(0, #ts.calls)
  end)

  it('leaves out usages in gitignored files when respect_gitignore is on', function()
    config.setup({ scope = { respect_gitignore = true } })
    local repo = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h:h')
    local file = repo .. '/src/comp.ts'
    local ng = fake_client('angularls', {
      [key(REFS, file, 10, 2)] = { loc(repo .. '/src/use.ts', 8, 4), loc(repo .. '/test/.servers/generated.ts', 2, 4) },
    })
    local fn = symbol({ kind = 'Function' })
    fn.container, fn.container_pos = nil, nil
    local ctx = context(ng, fake_client('ts_ls', {}))
    ctx.uri, ctx.path, ctx.root = vim.uri_from_fname(file), file, repo
    assert.same({ prod = 1, test = 0, related = false }, collect(ctx, { fn })[1])
  end)

  it('routes template locations to angularls and falls back to it when tsserver has nothing', function()
    local ng = fake_client('angularls', {
      [key(REFS, comp, 10, 2)] = {
        loc('/w/app/node_modules/x.d.ts', 1, 1),
        loc('/w/app/src/a.html', 2, 3),
        loc('/w/app/src/inline.ts', 7, 8),
      },
      [key(DEF, '/w/app/src/a.html', 2, 3)] = { { targetUri = vim.uri_from_fname(comp), targetSelectionRange = loc(comp, 10, 2).range, targetRange = loc(comp, 9, 0).range } },
      [key(DEF, '/w/app/src/inline.ts', 7, 8)] = loc(comp, 10, 2),
    })
    local ts = fake_client('ts_ls', {})
    local results = collect(context(ng, ts), { symbol() })
    assert.same({ prod = 2, test = 0, related = true }, results[1])
    assert.same({ key(DEF, '/w/app/src/inline.ts', 7, 8) }, ts.calls)
  end)

  describe('definitions in files not open in the editor', function()
    local tmp_root

    before_each(function()
      clients.has_document = real_has_document
      tmp_root = vim.fn.resolve(vim.fn.tempname())
      vim.fn.mkdir(tmp_root .. '/src', 'p')
    end)

    after_each(function()
      vim.fn.delete(tmp_root, 'rf')
    end)

    ---TS client that only resolves definitions for documents it was told are open
    local function strict_ts(routes)
      local client = fake_client('ts_ls', {})
      client.open_documents, client.notifications = {}, {}
      client.attached_buffers = {}
      function client:notify(method, params)
        table.insert(self.notifications, method)
        if method == 'textDocument/didOpen' then
          assert.is_truthy(params.textDocument.text:find('use()', 1, true))
          self.open_documents[params.textDocument.uri] = true
        elseif method == 'textDocument/didClose' then
          self.open_documents[params.textDocument.uri] = nil
        end
        return true
      end
      function client:request(method, params, handler)
        local k = method .. ' ' .. params.textDocument.uri .. ':' .. params.position.line .. ':' .. params.position.character
        table.insert(self.calls, k)
        handler(nil, self.open_documents[params.textDocument.uri] and routes[k] or nil)
        return true, #self.calls
      end
      return client
    end

    local function tmp_context(ng, ts)
      local ctx = context(ng, ts)
      ctx.root = tmp_root
      ctx.path = tmp_root .. '/src/comp.ts'
      ctx.uri = vim.uri_from_fname(ctx.path)
      return ctx
    end

    it('opens the document for the definition request and closes it afterwards', function()
      local child = tmp_root .. '/src/comp.ts'
      local user = tmp_root .. '/src/user.ts'
      vim.fn.writefile({ 'import { Comp } from "./comp";', 'new Comp().use();' }, user)
      local ng = fake_client('angularls', { [key(REFS, child, 10, 2)] = { loc(user, 1, 11) } })
      local ts = strict_ts({ [key(DEF, user, 1, 11)] = { loc(child, 10, 2) } })
      local results = collect(tmp_context(ng, ts), { symbol() })
      assert.same({ prod = 1, test = 0, related = false }, results[1])
      assert.same({ 'textDocument/didOpen', 'textDocument/didClose' }, ts.notifications)
      assert.same({}, ts.open_documents)
    end)

    it('shares an opened document between concurrent collects and closes it once', function()
      local child = tmp_root .. '/src/comp.ts'
      local other = tmp_root .. '/src/other.ts'
      local user = tmp_root .. '/src/user.ts'
      vim.fn.writefile({ 'import { Comp } from "./comp";', 'new Comp().use(); new Other().use();' }, user)
      local ng = fake_client('angularls', {
        [key(REFS, child, 10, 2)] = { loc(user, 1, 11) },
        [key(REFS, other, 10, 2)] = { loc(user, 1, 30) },
      })
      local ts = strict_ts({
        [key(DEF, user, 1, 11)] = { loc(child, 10, 2) },
        [key(DEF, user, 1, 30)] = { loc(other, 10, 2) },
      })
      local first, second = tmp_context(ng, ts), tmp_context(ng, ts)
      second.path, second.uri = other, vim.uri_from_fname(other)

      local results = {}
      references.collect(first, { symbol() }, function(r)
        results.first = r
      end)
      references.collect(second, { symbol() }, function(r)
        results.second = r
      end)
      vim.wait(2000, function()
        return results.first ~= nil and results.second ~= nil
      end, 5)

      assert.equals(1, results.first[1].prod)
      assert.equals(1, results.second[1].prod)
      assert.same({ 'textDocument/didOpen', 'textDocument/didClose' }, ts.notifications)
    end)

    it('does not reopen a document the editor already has open', function()
      local child = tmp_root .. '/src/comp.ts'
      local user = tmp_root .. '/src/user.ts'
      vim.fn.writefile({ 'new Comp().use();' }, user)
      local buf = vim.fn.bufadd(user)
      vim.fn.bufload(buf)
      local ng = fake_client('angularls', { [key(REFS, child, 10, 2)] = { loc(user, 0, 11) } })
      local ts = strict_ts({ [key(DEF, user, 0, 11)] = { loc(child, 10, 2) } })
      ts.attached_buffers[buf] = true
      ts.open_documents[vim.uri_from_fname(user)] = true
      local results = collect(tmp_context(ng, ts), { symbol() })
      assert.equals(1, results[1].prod)
      assert.same({}, ts.notifications)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  it('fails the whole collect on any request error', function()
    local ng = fake_client('angularls', { [key(REFS, comp, 10, 2)] = { err = { message = 'boom' } } })
    assert.is_nil(collect(context(ng, fake_client('ts_ls', {})), { symbol(), symbol({ name = 'b', line = 11 }) }))
  end)

  it('treats a nil result as a failure, never as zero usages', function()
    local ng = fake_client('angularls', { [key(REFS, comp, 10, 2)] = NIL_RESULT })
    assert.is_nil(collect(context(ng, fake_client('ts_ls', {})), { symbol() }))
  end)

  it('fails when a definition request errors', function()
    local ng = fake_client('angularls', {
      [key(REFS, comp, 10, 2)] = { loc('/w/app/node_modules/x.d.ts', 1, 1), loc('/w/app/src/b.ts', 1, 1) },
    })
    local ts = fake_client('ts_ls', { [key(DEF, '/w/app/src/b.ts', 1, 1)] = { err = { message = 'boom' } } })
    assert.is_nil(collect(context(ng, ts), { symbol() }))
  end)

  it('returns an empty list for no symbols', function()
    assert.same({}, collect(context(fake_client('angularls', {}), fake_client('ts_ls', {})), {}))
  end)

  describe('decorator transform inputs', function()
    local tmp_root

    local function input_symbol(overrides)
      return symbol(vim.tbl_deep_extend('force', {
        name = 'disabled',
        decorators = { input_transform = true },
      }, overrides or {}))
    end

    local function context_in(dir, ng)
      local ctx = context(ng, fake_client('ts_ls', {}))
      ctx.root = dir
      ctx.path = dir .. '/src/comp.ts'
      ctx.uri = vim.uri_from_fname(ctx.path)
      return ctx
    end

    local function write(path, text)
      vim.fn.mkdir(vim.fs.dirname(path), 'p')
      vim.fn.writefile(vim.split(text, '\n'), path)
    end

    before_each(function()
      tmp_root = vim.fn.resolve(vim.fn.tempname())
      vim.fn.mkdir(tmp_root .. '/src', 'p')
    end)

    after_each(function()
      vim.fn.delete(tmp_root, 'rf')
    end)

    it('adds parent bindings found in an unloaded template file', function()
      local child, parent = tmp_root .. '/src/comp.ts', tmp_root .. '/src/parent.html'
      write(parent, '<div>\n  <app-x\n    [disabled]="flag"\n  ></app-x>\n  <app-x [attr.disabled]="x"></app-x>\n</div>')
      write(tmp_root .. '/src/module.ts', "import { X } from './x';\nconst list: Array<X> = [];\n  imports: [X],")
      local ng = fake_client('angularls', {
        [key(REFS, child, 10, 2)] = { loc(child, 30, 4) },
        [key(REFS, child, 3, 13)] = { loc(parent, 1, 2), loc(parent, 4, 2), loc(tmp_root .. '/src/module.ts', 2, 10) },
      })
      local results = collect(context_in(tmp_root, ng), { input_symbol() })
      assert.same({ prod = 2, test = 0, related = false }, results[1])
    end)

    it('reads loaded buffers instead of disk and matches aliases', function()
      local child, parent = tmp_root .. '/src/comp.ts', tmp_root .. '/src/parent.html'
      write(parent, '<app-x [ext]="old">')
      local buf = vim.fn.bufadd(parent)
      vim.fn.bufload(buf)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '<app-x ext="unsaved">' })
      local ng = fake_client('angularls', {
        [key(REFS, child, 10, 2)] = {},
        [key(REFS, child, 3, 13)] = { loc(parent, 0, 0) },
      })
      local results = collect(context_in(tmp_root, ng), { input_symbol({ decorators = { input_alias = 'ext' } }) })
      assert.equals(1, results[1].prod)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('does not double count a binding angularls already reported', function()
      local child, parent = tmp_root .. '/src/comp.ts', tmp_root .. '/src/parent.html'
      write(parent, '<app-x\n  [disabled]="flag"\n/>')
      local ng = fake_client('angularls', {
        [key(REFS, child, 10, 2)] = { loc(parent, 1, 3) },
        [key(REFS, child, 3, 13)] = { loc(parent, 0, 0) },
      })
      local results = collect(context_in(tmp_root, ng), { input_symbol() })
      assert.equals(1, results[1].prod)
    end)

    it('finds the tag after multibyte text on the same line', function()
      local child, parent = tmp_root .. '/src/comp.ts', tmp_root .. '/src/parent.html'
      write(parent, '<p>äö</p><app-x [disabled]="x"></app-x>')
      local ng = fake_client('angularls', {
        [key(REFS, child, 10, 2)] = {},
        [key(REFS, child, 3, 13)] = { loc(parent, 0, 9) },
      })
      local results = collect(context_in(tmp_root, ng), { input_symbol() })
      assert.equals(1, results[1].prod)
    end)

    it('fails instead of reading a template larger than 1 MiB', function()
      local child, parent = tmp_root .. '/src/comp.ts', tmp_root .. '/src/parent.html'
      write(parent, '<app-x [disabled]="x">' .. string.rep('a', 1024 * 1024 + 10))
      local ng = fake_client('angularls', {
        [key(REFS, child, 10, 2)] = {},
        [key(REFS, child, 3, 13)] = { loc(parent, 0, 0) },
      })
      assert.is_nil(collect(context_in(tmp_root, ng), { input_symbol() }))
    end)

    it('requests class references once per class', function()
      local child, parent = tmp_root .. '/src/comp.ts', tmp_root .. '/src/parent.html'
      write(parent, '<app-x [a]="1" [b]="2">')
      local ng = fake_client('angularls', {
        [key(REFS, child, 10, 2)] = {},
        [key(REFS, child, 11, 2)] = {},
        [key(REFS, child, 3, 13)] = { loc(parent, 0, 0) },
      })
      local results = collect(context_in(tmp_root, ng), {
        input_symbol({ name = 'a' }),
        input_symbol({ name = 'b', line = 11 }),
      })
      assert.equals(1, results[1].prod)
      assert.equals(1, results[2].prod)
      local class_requests = vim.tbl_filter(function(call)
        return call == key(REFS, child, 3, 13)
      end, ng.calls)
      assert.equals(1, #class_requests)
    end)
  end)
end)
