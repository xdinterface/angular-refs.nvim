local config = require('angular-refs.config')
local display = require('angular-refs.display')
local lsp = require('angular-refs.lsp')
local server = require('angular-refs.server')

describe('angular-refs refresh orchestration', function()
  local bufnr, originals, callbacks, template_calls, template_callback, rendered

  local function replace(module, key, value)
    table.insert(originals, { module, key, module[key] })
    module[key] = value
  end

  before_each(function()
    originals, callbacks, rendered = {}, {}, {}
    template_calls, template_callback = 0, nil
    config.setup({ exclude = { respect_gitignore = false } })
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.tempname() .. '.ts')
    replace(vim, 'defer_fn', function() end)
    replace(lsp, 'get_symbols', function(_, callback)
      callback({
        { name = 'save', line = 0, col = 2, kind = 'Method' },
        { name = 'title', line = 1, col = 2, kind = 'Property' },
        { name = 'ngOnInit', line = 2, col = 2, kind = 'Method' },
      })
    end)
    replace(server, 'get_all_template_symbols', function(_, callback)
      template_calls = template_calls + 1
      template_callback = callback
    end)
    replace(server, 'get_decorator_refs', function(_, name)
      return name == 'save' and 1 or 0
    end)
    replace(lsp, 'get_references', function(_, line, _, callback, local_only)
      callbacks[line] = { callback = callback, local_only = local_only }
    end)
    replace(display, 'render_results', function(_, results)
      table.insert(rendered, results)
    end)
  end)

  after_each(function()
    display.clear(bufnr)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    for i = #originals, 1, -1 do
      local entry = originals[i]
      entry[1][entry[2]] = entry[3]
    end
    config.setup()
  end)

  it('shares template analysis and renders once after out-of-order TS responses', function()
    display.update(bufnr)
    assert.equals(1, template_calls)
    assert.equals(0, #rendered)
    template_callback({ save = 2, title = 3, ngOnInit = 99 })
    assert.is_false(callbacks[0].local_only)
    assert.is_false(callbacks[1].local_only)
    assert.is_true(callbacks[2].local_only)
    callbacks[1].callback({ {}, {} })
    callbacks[2].callback({ {} })
    assert.equals(0, #rendered)
    callbacks[0].callback({ {} })
    assert.equals(1, #rendered)
    assert.equals(1, rendered[1][0].ts_count)
    assert.equals(3, rendered[1][0].template_count)
    assert.equals(2, rendered[1][1].ts_count)
    assert.equals(3, rendered[1][1].template_count)
    assert.equals(1, rendered[1][2].ts_count)
    assert.equals(0, rendered[1][2].template_count)
  end)

  it('skips template analysis for buffers containing only lifecycle hooks', function()
    replace(lsp, 'get_symbols', function(_, callback)
      callback({ { name = 'ngOnInit', line = 0, col = 2, kind = 'Method' } })
    end)
    display.update(bufnr)
    assert.equals(0, template_calls)
    assert.is_true(callbacks[0].local_only)
    callbacks[0].callback({})
    assert.equals(1, #rendered)
    assert.equals(0, rendered[1][0].template_count)
  end)

  it('completes with empty template results and permits the next refresh', function()
    display.update(bufnr)
    template_callback({})
    for _, entry in pairs(callbacks) do entry.callback({}) end
    assert.equals(1, #rendered)
    display.update(bufnr)
    assert.equals(2, template_calls)
  end)

  it('preserves the separate comprehensive counting path', function()
    config.get().comprehensive_mode = true
    replace(server, 'get_comprehensive_counts', function(_, callback)
      callback({ save = 4, title = 5 })
    end)
    display.update(bufnr)
    assert.equals(0, template_calls)
    assert.same({}, callbacks)
    assert.equals(1, #rendered)
    assert.equals(4, rendered[1][0].template_count)
    assert.equals(5, rendered[1][1].template_count)
    assert.equals(0, rendered[1][2].template_count)
  end)
end)
