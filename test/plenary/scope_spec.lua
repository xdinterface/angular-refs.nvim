local scope = require('angular-refs.scope')
local config = require('angular-refs.config')

describe('angular-refs.scope', function()
  local root = '/w/app'

  before_each(function()
    config.setup()
    scope.clear_cache()
  end)

  describe('in_scope', function()
    it('accepts project source files', function()
      assert.is_true(scope.in_scope('/w/app/src/a.ts', root))
      assert.is_true(scope.in_scope('/w/app/src/app/a.component.html', root))
    end)

    it('rejects files outside the root', function()
      assert.is_false(scope.in_scope('/w/other/a.ts', root))
      assert.is_false(scope.in_scope('/w/app-two/a.ts', root))
      assert.is_false(scope.in_scope('/nix/store/x/lib.dom.d.ts', root))
    end)

    it('rejects node_modules and .angular at any depth', function()
      assert.is_false(scope.in_scope('/w/app/node_modules/x/a.ts', root))
      assert.is_false(scope.in_scope('/w/app/libs/x/node_modules/y.ts', root))
      assert.is_false(scope.in_scope('/w/app/node_modules/.pnpm/x/a.ts', root))
      assert.is_false(scope.in_scope('/w/app/.angular/cache/a.ts', root))
    end)

    it('rejects declaration files', function()
      assert.is_false(scope.in_scope('/w/app/src/types.d.ts', root))
    end)

    it('rejects root-level build and test output only', function()
      assert.is_false(scope.in_scope('/w/app/dist/a.ts', root))
      assert.is_false(scope.in_scope('/w/app/out-tsc/a.ts', root))
      assert.is_false(scope.in_scope('/w/app/coverage/a.ts', root))
      assert.is_true(scope.in_scope('/w/app/src/app/dist/a.ts', root))
      assert.is_true(scope.in_scope('/w/app/src/app/build/a.ts', root))
    end)

    it('applies user exclude patterns', function()
      config.setup({ scope = { exclude = { '/generated/' } } })
      assert.is_false(scope.in_scope('/w/app/src/generated/a.ts', root))
      assert.is_true(scope.in_scope('/w/app/src/app/a.ts', root))
    end)

    it('handles a root with pattern characters as plain text', function()
      local odd_root = '/home/u/my-app.v2'
      assert.is_true(scope.in_scope('/home/u/my-app.v2/src/a.ts', odd_root))
      assert.is_false(scope.in_scope('/home/u/my-appXv2/src/a.ts', odd_root))
    end)

    it('accepts real paths when the root is a symlink, and the reverse', function()
      local real = vim.fn.resolve(vim.fn.tempname())
      local link = real .. '-link'
      vim.fn.mkdir(real .. '/src', 'p')
      vim.uv.fs_symlink(real, link)
      assert.is_true(scope.in_scope(real .. '/src/a.ts', link))
      assert.is_true(scope.in_scope(link .. '/src/a.ts', real))
      assert.is_false(scope.in_scope(real .. '/node_modules/a.ts', link))
      vim.fn.delete(link)
      vim.fn.delete(real, 'rf')
    end)

    it('rejects everything when the root is unknown', function()
      assert.is_false(scope.in_scope('/w/app/src/a.ts', nil))
    end)
  end)

  describe('is_test', function()
    it('recognises default test file patterns', function()
      assert.is_true(scope.is_test('/w/app/src/a.component.spec.ts'))
      assert.is_true(scope.is_test('/w/app/src/a.test.ts'))
      assert.is_true(scope.is_test('/w/app/src/a.cy.ts'))
      assert.is_true(scope.is_test('/w/app/e2e/login.ts'))
    end)

    it('does not treat look-alike names as tests', function()
      assert.is_false(scope.is_test('/w/app/src/spec.ts.html'))
      assert.is_false(scope.is_test('/w/app/src/inspector.ts'))
    end)

    it('uses configured test patterns', function()
      config.setup({ scope = { test_patterns = { '/testing/' } } })
      assert.is_true(scope.is_test('/w/app/src/testing/helper.ts'))
      assert.is_false(scope.is_test('/w/app/src/a.spec.ts'))
    end)
  end)

  describe('gitignore', function()
    local original_system, original_fn_system
    local spawned

    before_each(function()
      spawned = 0
      original_system = vim.system
      original_fn_system = vim.fn.system
      vim.system = function(...)
        spawned = spawned + 1
        return original_system(...)
      end
      vim.fn.system = function(...)
        spawned = spawned + 1
        return original_fn_system(...)
      end
    end)

    after_each(function()
      vim.system = original_system
      vim.fn.system = original_fn_system
    end)

    it('never starts a process when disabled', function()
      scope.prefetch_gitignore({ '/w/app/src/a.ts', '/w/app/src/b.ts' })
      scope.in_scope('/w/app/src/a.ts', root)
      assert.equals(0, spawned)
    end)

    it('excludes gitignored files when enabled', function()
      local repo = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h:h')
      config.setup({ scope = { respect_gitignore = true } })
      local ignored = repo .. '/foo.log'
      local tracked = repo .. '/README.md'
      scope.prefetch_gitignore({ ignored, tracked })
      assert.equals(1, spawned)
      assert.is_false(scope.in_scope(ignored, repo))
      assert.is_true(scope.in_scope(tracked, repo))
      assert.equals(1, spawned)
    end)
  end)
end)
