local helpers = require('test.lsp.helpers')

-- These tests go through the plugin's own autocommands, as typing in the editor does:
-- an edit only invalidates what involves the edited file, and refreshes are scheduled
-- for every visible buffer.
describe('angular-refs after edits, with real language servers', function()
  if not helpers.installed() then
    pending('language servers not installed: run `make lsp-deps`')
    return
  end

  before_each(function()
    vim.o.hidden = true
    require('angular-refs').setup({ trigger = { debounce_ms = 50 } })
  end)

  after_each(function()
    vim.cmd('silent! only')
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.bo[bufnr].modified then
        vim.api.nvim_buf_call(bufnr, function()
          vim.cmd('silent edit!')
        end)
      end
    end
  end)

  it('counts a usage typed into another TypeScript file before it is saved', function()
    local service = helpers.open('services/data.service.ts')
    helpers.refresh(service)
    assert.equals('unused', helpers.labels(service)['DataService.getItemById'])

    vim.cmd('split')
    local user = helpers.open('components/ts-patterns/ts-patterns.component.ts')
    local at = helpers.line_of(user, 'publicMethod(): string {') + 1
    helpers.edit(user, at, at, { '    this.dataService.getItemById(1);' })
    helpers.wait_fresh(service)
    assert.equals('1 usage', helpers.labels(service)['DataService.getItemById'])

    helpers.edit(user, at, at + 1, {})
    helpers.wait_fresh(service)
    assert.equals('unused', helpers.labels(service)['DataService.getItemById'])
  end)

  it('turns a member unused when its only usage is removed, and back when restored', function()
    local catalog = helpers.open('catalog/catalog.component.ts')
    helpers.refresh(catalog)
    assert.equals('1 usage', helpers.labels(catalog)['CatalogComponent.tsOnlyMethod'])

    local at = helpers.line_of(catalog, 'callsTsOnly(): void { this.tsOnlyMethod(); }')
    local original = vim.api.nvim_buf_get_lines(catalog, at, at + 1, false)
    helpers.edit(catalog, at, at + 1, { '  callsTsOnly(): void {}' })
    helpers.wait_fresh(catalog)
    assert.equals('unused', helpers.labels(catalog)['CatalogComponent.tsOnlyMethod'])

    helpers.edit(catalog, at, at + 1, original)
    helpers.wait_fresh(catalog)
    assert.equals('1 usage', helpers.labels(catalog)['CatalogComponent.tsOnlyMethod'])
  end)

  it('keeps every label on its own line after lines are inserted above', function()
    local catalog = helpers.open('catalog/catalog.component.ts')
    helpers.refresh(catalog)
    local before = helpers.labels(catalog)

    helpers.edit(catalog, 0, 0, { '// inserted', '// above' })
    helpers.wait_fresh(catalog)
    assert.same(before, helpers.labels(catalog))
  end)
end)
