local helpers = require('test.lsp.helpers')

local function usages(n)
  return n == 1 and '1 usage' or (n .. ' usages')
end

local function ones(names)
  local map = {}
  for _, name in ipairs(names) do
    map[name] = usages(1)
  end
  return map
end

-- Every member is used exactly once through one Angular pattern unless listed otherwise
local CATALOG = vim.tbl_extend('error', ones({
  'interp', 'interpMethod', 'chainObj', 'safeNav', 'nonNull', 'ternaryCond', 'ternaryA', 'ternaryB',
  'nullishProp', 'formatFn', 'methodArg', 'thisPrefixed', 'anyCast', 'optionalFn', 'tplLiteral',
  'getterProp', 'setterProp', 'enumHolder', 'propBind', 'bindPrefix', 'attrBind', 'classBind',
  'styleBind', 'ngClassObj', 'arrayLiteralItem', 'eventWithArg', 'onPrefixHandler', 'keyedEvent',
  'assignTarget', 'multiStmtA', 'multiStmtB', 'onModelChange', 'twoWayModel', 'ifCond', 'ifAs',
  'elseIfCond', 'forItems', 'forItems2', 'trackFn', 'forInner', 'emptyMsg', 'switchVal', 'caseVal',
  'deferWhen', 'deferBody', 'deferPlaceholder', 'letSource', 'ngIfCond', 'ngTemplateIf', 'ngForItems',
  'ngForTrack', 'ngSwitchVal', 'ngSwitchCaseVal', 'templateOutletCtx', 'pipeInput', 'pipeArg',
  'asyncObs$', 'computedVal', 'animState', 'animDone', 'icuCount', 'childInputValue', 'onChildOut',
  'modelSync', 'directiveColor', 'hostMetaProp', 'hostMetaHandler', 'callsTsOnly', 'tsOnlyMethod',
}), {
  getterBacking = usages(2),
  eventHandler = usages(2),
  signalVal = usages(2),
  hostBindingProp = 'host binding',
  onResize = 'host listener',
  testOnlyMethod = 'tests only',
  unusedMember = 'unused',
})

local function prefixed(prefix, map)
  local out = {}
  for name, label in pairs(map) do
    out[prefix .. '.' .. name] = label
  end
  return out
end

local function assert_labels(file, expected)
  local bufnr = helpers.open(file)
  helpers.refresh(bufnr)
  local labels = helpers.labels(bufnr)
  local wrong = {}
  for id, label in pairs(expected) do
    if labels[id] ~= label then
      table.insert(wrong, string.format('%s: expected %q, got %q', id, label, tostring(labels[id])))
    end
  end
  table.sort(wrong)
  assert(#wrong == 0, file .. '\n  ' .. table.concat(wrong, '\n  '))
end

describe('angular-refs with real language servers', function()
  if not helpers.installed() then
    it('needs language servers (run `make lsp-deps`)', function()
      pending('language servers not installed')
    end)
    return
  end

  require('angular-refs').setup()

  it('labels every template and TypeScript usage pattern exactly', function()
    assert_labels('catalog/catalog.component.ts', prefixed('CatalogComponent', CATALOG))
  end)

  it('counts parent bindings for every input and output style', function()
    assert_labels('catalog/catalog-child.component.ts', prefixed('CatalogChildComponent', {
      childIn = usages(2),
      tBool = usages(2),
      tAlias = usages(2),
      tSignal = usages(2),
      aliasedIn = usages(2),
      signalIn = usages(2),
      requiredIn = usages(2),
      inputsArrayProp = usages(1),
      childModel = usages(2),
      childOut = usages(2),
      legacyOut = usages(2),
      fire = usages(1),
      publicChildMethod = usages(1),
    }))
  end)

  it('counts directive inputs and pipe usages of only this pipe', function()
    assert_labels('catalog/catalog-highlight.directive.ts', { ['CatalogHighlightDirective.appCatHighlight'] = usages(1) })
    assert_labels('catalog/catalog.pipe.ts', { ['CatalogPipe.transform'] = usages(1) })
  end)

  it('scopes lifecycle hooks to their own class', function()
    assert_labels('catalog/lifecycle.ts', {
      ['LifeA.ngOnInit'] = usages(3),
      ['LifeB.ngOnInit'] = 'lifecycle',
      ['LifeC.ngOnInit'] = usages(1),
      bootLifeA = 'unused',
    })
  end)

  it('labels interface implementations only called through the interface', function()
    assert_labels('catalog/greeter.ts', {
      ['CatalogGreeter.greet'] = 'implements',
      ['Greeter.greet'] = usages(1),
      useGreeter = 'unused',
    })
  end)

  it('counts every parent binding form of decorator inputs with transform', function()
    assert_labels('transform-inputs/transform-child.component.ts', prefixed('TransformChildComponent', {
      disabled = usages(8),
      sizeValue = usages(3),
      neverBound = usages(1),
      unusedFlag = 'unused',
    }))
    assert_labels('transform-inputs/transform-parent.component.ts', prefixed('TransformParentComponent', {
      flag = usages(7),
      count = usages(1),
      items = usages(1),
      noop = usages(1),
    }))
  end)

  it('counts attribute-directive inputs with transform', function()
    assert_labels('transform-inputs/transform-flag.directive.ts', { ['TransformFlagDirective.appFlag'] = usages(2) })
  end)

  it('counts unsaved edits in an htmlangular template buffer', function()
    local component = helpers.open('catalog/catalog.component.ts')
    helpers.refresh(component)
    assert.equals(usages(1), helpers.labels(component)['CatalogComponent.interp'])

    local template = helpers.open('catalog/catalog.component.html')
    vim.bo[template].filetype = 'htmlangular'
    vim.api.nvim_buf_set_lines(template, -1, -1, false, { '<p>{{ interp }}</p>' })
    vim.wait(1000)
    helpers.refresh(component)
    assert.equals(usages(2), helpers.labels(component)['CatalogComponent.interp'])

    vim.api.nvim_buf_set_lines(template, -2, -1, false, {})
    vim.wait(1000)
    helpers.refresh(component)
    assert.equals(usages(1), helpers.labels(component)['CatalogComponent.interp'])
  end)
end)
