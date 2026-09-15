local clients = require('angular-refs.clients')
local config = require('angular-refs.config')
local lsp = require('angular-refs.lsp')

describe('angular-refs LSP integration', function()
  local original_get_clients, bufnr

  before_each(function()
    original_get_clients = vim.lsp.get_clients
    config.setup({ exclude = { respect_gitignore = false } })
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. '.ts')
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'class Example {', '  save() {}', '  run() { this.save(); }', '}' })
  end)

  after_each(function()
    vim.lsp.get_clients = original_get_clients
    vim.api.nvim_buf_delete(bufnr, { force = true })
    config.setup()
  end)

  it('uses the same preferred TS client for symbols and references', function()
    local methods = {}
    local SK = vim.lsp.protocol.SymbolKind
    local function range(line, col)
      return { start = { line = line, character = col }, ['end'] = { line = line, character = col + 4 } }
    end
    local preferred = { request = function(method, params, callback, buffer)
      assert.equals(bufnr, buffer)
      table.insert(methods, method)
      if method == 'textDocument/documentSymbol' then
        callback(nil, {{ name = 'Example', kind = SK.Class, range = range(0, 0), children = {
          { name = 'save', kind = SK.Method, range = range(1, 2) },
          { name = '_hidden', kind = SK.Method, range = range(1, 2) },
          { name = 'constructor', kind = SK.Constructor, range = range(1, 2) },
        } }})
      else
        assert.is_false(params.context.includeDeclaration)
        assert.same({ line = 1, character = 2 }, params.position)
        callback(nil, {{ uri = vim.uri_from_bufnr(bufnr), range = range(2, 15) }})
      end
      return true, #methods
    end }
    vim.lsp.get_clients = function(opts)
      assert.equals(bufnr, opts.bufnr)
      if opts.name == 'typescript-tools' then return { preferred } end
      error('Should prefer typescript-tools over another TS client')
    end
    lsp.get_symbols(bufnr, function(symbols)
      assert.equals(1, #symbols)
      assert.equals('save', symbols[1].name)
      lsp.get_references(bufnr, symbols[1].line, symbols[1].col, function(refs)
        assert.equals(1, #refs)
        assert.equals(3, refs[1].line)
      end)
    end)
    assert.same({ 'textDocument/documentSymbol', 'textDocument/references' }, methods)
  end)

  it('keeps Angular attachment checks local and makes global fallback explicit', function()
    local angular = { name = 'angular' }
    vim.lsp.get_clients = function(opts)
      if not opts.bufnr and opts.name == 'angular' then return { angular } end
      return {}
    end
    assert.is_nil(clients.get_angular(bufnr))
    assert.equals(angular, clients.get_angular(bufnr, true))
    assert.is_true(clients.is_angular(angular))
    assert.is_false(clients.is_angular(nil))
    assert.is_nil(clients.get_typescript(bufnr))
  end)

  it('preserves local-only reference filtering for lifecycle calls', function()
    local client = { request = function(_, _, callback)
      local range = { start = { line = 2, character = 15 }, ['end'] = { line = 2, character = 19 } }
      callback(nil, {
        { uri = vim.uri_from_bufnr(bufnr), range = range },
        { uri = vim.uri_from_fname('/tmp/another-component.ts'), range = range },
      })
      return true, 1
    end }
    vim.lsp.get_clients = function(opts)
      return opts.name == 'ts_ls' and { client } or {}
    end
    lsp.get_references(bufnr, 1, 2, function(refs)
      assert.equals(1, #refs)
      assert.equals(vim.api.nvim_buf_get_name(bufnr), refs[1].file)
    end, true)
  end)

  it('completes symbol and reference requests when no TS client is attached', function()
    vim.lsp.get_clients = function() return {} end
    local completed = 0
    local function check(result)
      completed = completed + 1
      assert.same({}, result)
    end
    lsp.get_symbols(bufnr, check)
    lsp.get_references(bufnr, 1, 2, check)
    assert.equals(2, completed)
  end)
end)
