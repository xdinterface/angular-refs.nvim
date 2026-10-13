local angular_refs = require('angular-refs')

local function autocmd_events()
  local events = {}
  for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ group = 'AngularRefs' })) do
    events[autocmd.event] = true
  end
  return events
end

describe('angular-refs setup', function()
  it('registers commands', function()
    angular_refs.setup()
    local commands = vim.api.nvim_get_commands({})
    assert.is_not_nil(commands.AngularRefsRefresh)
    assert.is_not_nil(commands.AngularRefsToggle)
    assert.is_not_nil(commands.AngularRefsUnused)
    assert.is_nil(commands.AngularRefsStatus)
    assert.is_nil(commands.AngularRefsDumpTcb)
  end)

  it('registers refresh autocmds without CursorHold', function()
    angular_refs.setup()
    local events = autocmd_events()
    for _, event in ipairs({ 'BufEnter', 'LspAttach', 'TextChanged', 'TextChangedI', 'BufWritePost', 'FileChangedShellPost', 'BufWipeout', 'ColorScheme' }) do
      assert.is_true(events[event] == true, 'missing ' .. event)
    end
    assert.is_nil(events.CursorHold)
  end)

  it('invalidates only the edited file while typing and everything on save', function()
    angular_refs.setup()
    local refresh = require('angular-refs.refresh')
    local original = refresh.bump_generation
    local calls = {}
    refresh.bump_generation = function(path)
      table.insert(calls, path or 'all')
    end
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, '/w/app/src/edited.component.ts')
    vim.api.nvim_exec_autocmds('TextChanged', { buffer = buf })
    vim.api.nvim_exec_autocmds('TextChangedI', { buffer = buf })
    vim.api.nvim_exec_autocmds('BufWritePost', { buffer = buf })
    refresh.bump_generation = original
    vim.api.nvim_buf_delete(buf, { force = true })
    assert.same({ '/w/app/src/edited.component.ts', '/w/app/src/edited.component.ts', 'all' }, calls)
  end)

  it('defines highlight groups', function()
    angular_refs.setup()
    assert.equals('Comment', vim.api.nvim_get_hl(0, { name = 'AngularRefsCount' }).link)
  end)

  it('starts disabled when enabled = false and the toggle enables it', function()
    angular_refs.setup({ enabled = false })
    assert.is_false(require('angular-refs.refresh').enabled())
    vim.cmd('AngularRefsToggle')
    assert.is_true(require('angular-refs.refresh').enabled())
  end)

  it('opens an empty quickfix message when nothing is unused', function()
    angular_refs.setup()
    local messages = {}
    local original = vim.notify
    vim.notify = function(msg)
      table.insert(messages, msg)
    end
    vim.cmd('AngularRefsUnused')
    vim.notify = original
    assert.truthy(messages[1]:find('No unused', 1, true))
  end)
end)

describe('angular-refs health', function()
  it('reports missing clients and deprecated options without erroring', function()
    local original = vim.notify
    vim.notify = function() end
    angular_refs.setup({ comprehensive_mode = true })
    vim.notify = original
    vim.cmd('checkhealth angular-refs')
    local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
    assert.truthy(text:find('comprehensive_mode', 1, true))
    assert.truthy(text:find('No Angular language server', 1, true))
    assert.is_nil(text:find('ERROR: Failed to run', 1, true))
  end)
end)
