local classify = require('angular-refs.classify')
local config = require('angular-refs.config')

local function symbol(name, decorators)
  return {
    name = name,
    decorators = vim.tbl_extend('force', {
      host_listener = false,
      host_binding = false,
      input_transform = false,
    }, decorators or {}),
  }
end

local function counts(prod, test, related)
  return { prod = prod, test = test or 0, related = related or false }
end

describe('angular-refs.classify', function()
  before_each(function()
    config.setup()
  end)

  it('shows the total count when production usages exist', function()
    assert.same({ 'count', '3 usages', 'AngularRefsCount' }, { classify.label(symbol('a'), counts(1, 2)) })
    assert.same({ 'count', '1 usage', 'AngularRefsCount' }, { classify.label(symbol('a'), counts(1)) })
  end)

  it('prefers a count over every framework label', function()
    local state = classify.label(symbol('ngOnInit', { host_listener = true }), counts(2, 0, true))
    assert.equals('count', state)
  end)

  it('labels unused lifecycle hooks', function()
    assert.same(
      { 'lifecycle', 'lifecycle', 'AngularRefsFramework' },
      { classify.label(symbol('ngOnInit'), counts(0, 3, true)) }
    )
    for name in pairs(classify.LIFECYCLE) do
      assert.equals('lifecycle', classify.label(symbol(name), counts(0)))
    end
  end)

  it('labels host listeners and host bindings', function()
    assert.same(
      { 'host_listener', 'host listener', 'AngularRefsFramework' },
      { classify.label(symbol('onResize', { host_listener = true }), counts(0, 0, true)) }
    )
    assert.same(
      { 'host_binding', 'host binding', 'AngularRefsFramework' },
      { classify.label(symbol('active', { host_binding = true }), counts(0)) }
    )
  end)

  it('labels interface and base-class members that only have related usages', function()
    assert.same(
      { 'implements', 'implements', 'AngularRefsFramework' },
      { classify.label(symbol('greet'), counts(0, 2, true)) }
    )
  end)

  it('labels members used only from tests', function()
    assert.same(
      { 'tests_only', 'tests only', 'AngularRefsTestsOnly' },
      { classify.label(symbol('helper'), counts(0, 2)) }
    )
  end)

  it('labels members with no usages as unused', function()
    assert.same({ 'unused', 'unused', 'AngularRefsUnused' }, { classify.label(symbol('dead'), counts(0)) })
  end)

  it('uses configured label texts and formats', function()
    config.setup({
      display = { format = '%d refs', format_singular = '%d ref', labels = { unused = 'dead', tests_only = 'test' } },
    })
    assert.equals('dead', select(2, classify.label(symbol('x'), counts(0))))
    assert.equals('test', select(2, classify.label(symbol('x'), counts(0, 1))))
    assert.equals('2 refs', select(2, classify.label(symbol('x'), counts(2))))
    assert.equals('1 ref', select(2, classify.label(symbol('x'), counts(1))))
  end)
end)
