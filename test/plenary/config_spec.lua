local config = require('angular-refs.config')

local function capture_notifications(fn)
  local messages = {}
  local original = vim.notify
  vim.notify = function(msg, level)
    table.insert(messages, { msg = msg, level = level })
  end
  local ok, err = pcall(fn)
  vim.notify = original
  assert(ok, err)
  return messages
end

describe('angular-refs.config', function()
  before_each(function()
    config.setup()
  end)

  describe('defaults', function()
    it('matches the documented display defaults', function()
      local display = config.get().display
      assert.equals('eol', display.position)
      assert.equals('    | ', display.separator)
      assert.is_false(display.align)
      assert.equals('%d usages', display.format)
      assert.equals('%d usage', display.format_singular)
      assert.same({
        unused = 'unused',
        tests_only = 'tests only',
        lifecycle = 'lifecycle',
        host_listener = 'host listener',
        host_binding = 'host binding',
        implements = 'implements',
      }, display.labels)
    end)

    it('matches the documented scope defaults', function()
      local scope = config.get().scope
      assert.same({}, scope.exclude)
      assert.same({ '%.spec%.ts$', '%.test%.ts$', '%.cy%.ts$', '/e2e/' }, scope.test_patterns)
      assert.is_false(scope.respect_gitignore)
    end)

    it('matches the documented symbol, trigger and client defaults', function()
      local cfg = config.get()
      assert.is_true(cfg.enabled)
      assert.is_false(cfg.debug)
      assert.equals(500, cfg.trigger.debounce_ms)
      assert.same({ '^_' }, cfg.symbols.ignore)
      assert.is_false(cfg.symbols.test_buffers)
      assert.same({ 'angularls', 'angular' }, cfg.clients.angular)
      assert.same(
        { 'typescript-tools', 'ts_ls', 'vtsls', 'typescript-language-server', 'tsserver' },
        cfg.clients.typescript
      )
    end)
  end)

  describe('setup', function()
    it('overrides scalars and keeps sibling defaults', function()
      config.setup({ display = { separator = ' - ' } })
      assert.equals(' - ', config.get().display.separator)
      assert.equals('eol', config.get().display.position)
    end)

    it('replaces lists instead of merging them by index', function()
      config.setup({ scope = { test_patterns = { 'x' } } })
      assert.same({ 'x' }, config.get().scope.test_patterns)
    end)

    it('keeps label defaults when only one label is overridden', function()
      config.setup({ display = { labels = { unused = 'dead' } } })
      assert.equals('dead', config.get().display.labels.unused)
      assert.equals('tests only', config.get().display.labels.tests_only)
    end)

    it('does not mutate the defaults table', function()
      config.setup({ scope = { exclude = { '/generated/' } } })
      assert.same({}, config.defaults.scope.exclude)
    end)
  end)

  describe('deprecations', function()
    it('warns about comprehensive_mode and ignores it', function()
      local messages = capture_notifications(function()
        config.setup({ comprehensive_mode = true })
      end)
      assert.is_nil(config.get().comprehensive_mode)
      assert.equals(1, #messages)
      assert.equals(vim.log.levels.WARN, messages[1].level)
      assert.truthy(messages[1].msg:find('comprehensive_mode', 1, true))
    end)

    it('moves exclude.patterns to scope.exclude without built-in entries', function()
      capture_notifications(function()
        config.setup({ exclude = { patterns = { 'node_modules', '/dist/', '%.angular', 'vendor/' } } })
      end)
      assert.same({ 'vendor/' }, config.get().scope.exclude)
      assert.is_nil(config.get().exclude)
    end)

    it('moves exclude.respect_gitignore to scope.respect_gitignore', function()
      capture_notifications(function()
        config.setup({ exclude = { respect_gitignore = true } })
      end)
      assert.is_true(config.get().scope.respect_gitignore)
    end)

    it('moves display.format_zero to display.labels.unused', function()
      capture_notifications(function()
        config.setup({ display = { format_zero = 'dead' } })
      end)
      assert.equals('dead', config.get().display.labels.unused)
      assert.is_nil(config.get().display.format_zero)
    end)

    it('warns about removed highlight and trigger keys', function()
      local messages = capture_notifications(function()
        config.setup({ display = { highlight = 'Error' }, trigger = { on_open = false } })
      end)
      assert.equals(2, #messages)
      assert.is_nil(config.get().display.highlight)
      assert.is_nil(config.get().trigger.on_open)
    end)

    it('records warnings for health checks', function()
      capture_notifications(function()
        config.setup({ comprehensive_mode = false })
      end)
      assert.equals(1, #config.warnings())
    end)

    it('does not warn for a current config', function()
      local messages = capture_notifications(function()
        config.setup({ debug = true })
      end)
      assert.equals(0, #messages)
      assert.equals(0, #config.warnings())
    end)
  end)
end)
