local config = require('angular-refs.config')

describe('angular-refs.config', function()
  before_each(function()
    config.options = vim.deepcopy(config.defaults)
  end)

  describe('defaults', function()
    it('should have enabled set to true', function()
      assert.is_true(config.defaults.enabled)
    end)

    it('should have display.position set to eol', function()
      assert.equals('eol', config.defaults.display.position)
    end)

    it('should have display.separator set to " | "', function()
      assert.equals(' | ', config.defaults.display.separator)
    end)

    it('should have trigger.on_open set to true', function()
      assert.is_true(config.defaults.trigger.on_open)
    end)

    it('should have trigger.on_save set to true', function()
      assert.is_true(config.defaults.trigger.on_save)
    end)

    it('should have trigger.debounce_ms set to 500', function()
      assert.equals(500, config.defaults.trigger.debounce_ms)
    end)

    it('should have debug set to false', function()
      assert.is_false(config.defaults.debug)
    end)
  end)

  describe('setup', function()
    it('should merge user options with defaults', function()
      config.setup({ debug = true })
      assert.is_true(config.options.debug)
      assert.is_true(config.options.enabled)
    end)

    it('should override nested options', function()
      config.setup({
        display = {
          position = 'above',
        },
      })
      assert.equals('above', config.options.display.position)
      assert.equals(' | ', config.options.display.separator)
    end)

    it('should override trigger options', function()
      config.setup({
        trigger = {
          debounce_ms = 1000,
        },
      })
      assert.equals(1000, config.options.trigger.debounce_ms)
      assert.is_true(config.options.trigger.on_open)
    end)
  end)

  describe('get', function()
    it('should return current options', function()
      local opts = config.get()
      assert.is_table(opts)
      assert.is_true(opts.enabled)
    end)
  end)

  describe('is_enabled', function()
    it('should return true when enabled', function()
      config.options.enabled = true
      assert.is_true(config.is_enabled())
    end)

    it('should return false when disabled', function()
      config.options.enabled = false
      assert.is_false(config.is_enabled())
    end)
  end)
end)
