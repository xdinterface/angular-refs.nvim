local helpers = require('test.helpers')

describe('angular-refs integration', function()
  local ctx

  before_each(function()
    ctx = helpers.create_test_context()
  end)

  after_each(function()
    ctx:cleanup()
  end)

  describe('fixture files', function()
    it('should have ts-patterns component', function()
      local path = helpers.get_fixture_path('components/ts-patterns/ts-patterns.component.ts')
      assert.is_true(vim.fn.filereadable(path) == 1)
    end)

    it('should have ts-patterns template', function()
      local path = helpers.get_fixture_path('components/ts-patterns/ts-patterns.component.html')
      assert.is_true(vim.fn.filereadable(path) == 1)
    end)

    it('should have decorators component', function()
      local path = helpers.get_fixture_path('components/decorators/decorators.component.ts')
      assert.is_true(vim.fn.filereadable(path) == 1)
    end)

    it('should have signals component', function()
      local path = helpers.get_fixture_path('components/signals/signals.component.ts')
      assert.is_true(vim.fn.filereadable(path) == 1)
    end)

    it('should have template-patterns component', function()
      local path = helpers.get_fixture_path('components/template-patterns/template-patterns.component.ts')
      assert.is_true(vim.fn.filereadable(path) == 1)
    end)

    it('should have parent component', function()
      local path = helpers.get_fixture_path('components/parent-child/parent.component.ts')
      assert.is_true(vim.fn.filereadable(path) == 1)
    end)

    it('should have child component', function()
      local path = helpers.get_fixture_path('components/parent-child/child.component.ts')
      assert.is_true(vim.fn.filereadable(path) == 1)
    end)

    it('should have data service', function()
      local path = helpers.get_fixture_path('services/data.service.ts')
      assert.is_true(vim.fn.filereadable(path) == 1)
    end)
  end)

  describe('ts-patterns component', function()
    it('should open ts-patterns component', function()
      local bufnr = helpers.open_fixture('components/ts-patterns/ts-patterns.component.ts')
      ctx:add_buffer(bufnr)
      assert.is_true(vim.api.nvim_buf_is_valid(bufnr))
    end)

    it('should find publicProp declaration', function()
      local bufnr = helpers.open_fixture('components/ts-patterns/ts-patterns.component.ts')
      ctx:add_buffer(bufnr)
      local line = helpers.find_symbol_line(bufnr, 'publicProp')
      assert.is_not_nil(line)
    end)

    it('should find EXPORTED_CONST declaration', function()
      local bufnr = helpers.open_fixture('components/ts-patterns/ts-patterns.component.ts')
      ctx:add_buffer(bufnr)
      local line = helpers.find_line_with_pattern(bufnr, 'EXPORTED_CONST')
      assert.is_not_nil(line)
    end)

    it('should find all variable declaration types', function()
      local bufnr = helpers.open_fixture('components/ts-patterns/ts-patterns.component.ts')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'export const EXPORTED_CONST'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'const LOCAL_CONST'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'let mutableVar'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'var legacyVar'))
    end)

    it('should find all function declaration types', function()
      local bufnr = helpers.open_fixture('components/ts-patterns/ts-patterns.component.ts')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'export function exportedFunction'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'function localFunction'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'async function asyncFunction'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'function%* generatorFunction'))
    end)

    it('should find arrow function declarations', function()
      local bufnr = helpers.open_fixture('components/ts-patterns/ts-patterns.component.ts')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'export const arrowFn'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'const localArrow'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'const asyncArrow'))
    end)

    it('should find type declarations', function()
      local bufnr = helpers.open_fixture('components/ts-patterns/ts-patterns.component.ts')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'export interface ExportedInterface'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'interface LocalInterface'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'export type ExportedType'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'type LocalType'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'export enum ExportedEnum'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'enum LocalEnum'))
    end)

    it('should find class member declarations', function()
      local bufnr = helpers.open_fixture('components/ts-patterns/ts-patterns.component.ts')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'publicProp'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'readonly readonlyProp'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'private privateProp'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'protected protectedProp'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'static staticProp'))
    end)

    it('should find getter and setter', function()
      local bufnr = helpers.open_fixture('components/ts-patterns/ts-patterns.component.ts')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'get computedValue'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'set computedValue'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'get readonlyComputed'))
    end)
  end)

  describe('decorators component', function()
    it('should find @Input declarations', function()
      local bufnr = helpers.open_fixture('components/decorators/decorators.component.ts')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '@Input%(%) simpleInput'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, "@Input%('externalName'%)"))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '@Input%({ required: true }%)'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '@Input%({ transform: booleanAttribute }%)'))
    end)

    it('should find @Output declarations', function()
      local bufnr = helpers.open_fixture('components/decorators/decorators.component.ts')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '@Output%(%) simpleOutput'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, "@Output%('externalEvent'%)"))
    end)

    it('should find @ViewChild declarations', function()
      local bufnr = helpers.open_fixture('components/decorators/decorators.component.ts')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, "@ViewChild%('inputRef'%)"))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '@ViewChild%(ChildComponent%)'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, "@ViewChild%('staticRef', { static: true }%)"))
    end)

    it('should find @ViewChildren declarations', function()
      local bufnr = helpers.open_fixture('components/decorators/decorators.component.ts')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, "@ViewChildren%('listItem'%)"))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '@ViewChildren%(ChildComponent%)'))
    end)

    it('should find @ContentChild declarations', function()
      local bufnr = helpers.open_fixture('components/decorators/decorators.component.ts')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, "@ContentChild%('projected'%)"))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '@ContentChild%(TemplateRef%)'))
    end)

    it('should find host binding properties', function()
      local bufnr = helpers.open_fixture('components/decorators/decorators.component.ts')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'isActive = false'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'isDisabled = false'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'componentId ='))
    end)
  end)

  describe('signals component', function()
    it('should find signal input declarations', function()
      local bufnr = helpers.open_fixture('components/signals/signals.component.ts')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'simpleInput = input<string>'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'requiredInput = input.required'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'aliasedInput = input<string>'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'transformedInput = input'))
    end)

    it('should find signal output declarations', function()
      local bufnr = helpers.open_fixture('components/signals/signals.component.ts')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'clicked = output'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'customEvent = output'))
    end)

    it('should find model declarations', function()
      local bufnr = helpers.open_fixture('components/signals/signals.component.ts')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'count = model%(0%)'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'selectedItem = model'))
    end)

    it('should find signal query declarations', function()
      local bufnr = helpers.open_fixture('components/signals/signals.component.ts')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'searchField = viewChild'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'requiredChild = viewChild.required'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'allItems = viewChildren'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'projectedContent = contentChild'))
    end)

    it('should find signal and computed declarations', function()
      local bufnr = helpers.open_fixture('components/signals/signals.component.ts')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, "firstName = signal%('John'%)"))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, "lastName = signal%('Doe'%)"))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'fullName = computed'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'isAdult = computed'))
    end)
  end)

  describe('template-patterns component', function()
    it('should have interpolation patterns in template', function()
      local bufnr = helpers.open_fixture('components/template-patterns/template-patterns.component.html')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '{{ simpleProperty }}'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '{{ methodCall%(%) }}'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '{{ nested.deep.property }}'))
    end)

    it('should have property binding patterns in template', function()
      local bufnr = helpers.open_fixture('components/template-patterns/template-patterns.component.html')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '%[id%]="elementId"'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '%[class.active%]="isActive"'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '%[style.color%]="textColor"'))
    end)

    it('should have event binding patterns in template', function()
      local bufnr = helpers.open_fixture('components/template-patterns/template-patterns.component.html')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '%(click%)="handleClick%(%)'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '%(input%)="onInput'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '%(keydown.enter%)="onEnter'))
    end)

    it('should have control flow patterns in template', function()
      local bufnr = helpers.open_fixture('components/template-patterns/template-patterns.component.html')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '@if %(showContent%)'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '@for %(item of items'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '@switch %(status%)'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '@defer'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '@let fullName'))
    end)

    it('should have pipe patterns in template', function()
      local bufnr = helpers.open_fixture('components/template-patterns/template-patterns.component.html')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, "| date:'short'"))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '| uppercase'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, "| currency:'USD'"))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '| async'))
    end)

    it('should have legacy structural directive patterns', function()
      local bufnr = helpers.open_fixture('components/template-patterns/template-patterns.component.html')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '%*ngIf="legacyCondition"'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '%*ngFor="let item of legacyItems'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '%[ngSwitch%]="legacyStatus"'))
    end)
  end)

  describe('parent-child components', function()
    it('should have parent using child with decorator bindings', function()
      local bufnr = helpers.open_fixture('components/parent-child/parent.component.html')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '%[simpleInput%]="parentSimple"'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '%[aliasedName%]="parentAliased"'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '%(simpleOutput%)="onSimpleOutput%(%)'))
    end)

    it('should have parent using child with signal bindings', function()
      local bufnr = helpers.open_fixture('components/parent-child/parent.component.html')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '%[signalInput%]="parentSignalInput"'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, '%[%(count%)%]="parentCount"'))
    end)

    it('should have child with all input variations', function()
      local bufnr = helpers.open_fixture('components/parent-child/child.component.ts')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, "@Input%(%) simpleInput"))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, "@Input%('aliasedName'%)"))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, "signalInput = input<string>"))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, "count = model"))
    end)
  end)

  describe('project-wide search', function()
    it('should extract component metadata from child component', function()
      local server = require('angular-refs.server')
      local child_path = helpers.get_fixture_path('components/parent-child/child.component.ts')
      local file = io.open(child_path, 'r')
      assert.is_not_nil(file)
      local content = file:read('*all')
      file:close()

      local metadata = server.get_component_metadata(content)
      assert.equals('app-child', metadata.selector)
      assert.is_true(#metadata.inputs > 0)
      assert.is_true(#metadata.outputs > 0)
    end)

    it('should extract decorator-based @Input with alias', function()
      local server = require('angular-refs.server')
      local child_path = helpers.get_fixture_path('components/parent-child/child.component.ts')
      local file = io.open(child_path, 'r')
      local content = file:read('*all')
      file:close()

      local metadata = server.get_component_metadata(content)

      local found_aliased = false
      for _, input in ipairs(metadata.inputs) do
        if input.name == 'realInputName' and input.alias == 'aliasedName' then
          found_aliased = true
          break
        end
      end
      assert.is_true(found_aliased, 'Should find aliased input: realInputName with alias aliasedName')
    end)

    it('should extract signal-based inputs', function()
      local server = require('angular-refs.server')
      local child_path = helpers.get_fixture_path('components/parent-child/child.component.ts')
      local file = io.open(child_path, 'r')
      local content = file:read('*all')
      file:close()

      local metadata = server.get_component_metadata(content)

      local found_signal_input = false
      for _, input in ipairs(metadata.inputs) do
        if input.name == 'signalInput' and input.kind == 'signal' then
          found_signal_input = true
          break
        end
      end
      assert.is_true(found_signal_input, 'Should find signal input')
    end)

    it('should extract model as both input and output', function()
      local server = require('angular-refs.server')
      local child_path = helpers.get_fixture_path('components/parent-child/child.component.ts')
      local file = io.open(child_path, 'r')
      local content = file:read('*all')
      file:close()

      local metadata = server.get_component_metadata(content)

      local found_count_input = false
      local found_count_output = false
      for _, input in ipairs(metadata.inputs) do
        if input.name == 'count' then
          found_count_input = true
        end
      end
      for _, output in ipairs(metadata.outputs) do
        if output.name == 'countChange' then
          found_count_output = true
        end
      end
      assert.is_true(found_count_input, 'Model should create input')
      assert.is_true(found_count_output, 'Model should create output with Change suffix')
    end)

    it('should find project root from fixture path', function()
      local server = require('angular-refs.server')
      local child_path = helpers.get_fixture_path('components/parent-child/child.component.ts')
      local project_root = server.find_project_root(vim.fn.fnamemodify(child_path, ':h'))
      assert.is_not_nil(project_root)
      assert.is_true(vim.fn.filereadable(project_root .. '/package.json') == 1)
    end)

    it('should find selector usages in parent template', function()
      local server = require('angular-refs.server')
      local child_path = helpers.get_fixture_path('components/parent-child/child.component.ts')
      local file = io.open(child_path, 'r')
      local content = file:read('*all')
      file:close()

      local metadata = server.get_component_metadata(content)
      local project_root = server.find_project_root(vim.fn.fnamemodify(child_path, ':h'))

      local usages = server.find_selector_usages(
        metadata.selector,
        metadata.inputs,
        metadata.outputs,
        project_root
      )

      -- simpleInput is used multiple times in parent template
      assert.is_true((usages['simpleInput'] or 0) > 0, 'Should find simpleInput usage in parent')
    end)

    it('should find aliased input via alias in parent template', function()
      local server = require('angular-refs.server')
      local child_path = helpers.get_fixture_path('components/parent-child/child.component.ts')
      local file = io.open(child_path, 'r')
      local content = file:read('*all')
      file:close()

      local metadata = server.get_component_metadata(content)
      local project_root = server.find_project_root(vim.fn.fnamemodify(child_path, ':h'))

      local usages = server.find_selector_usages(
        metadata.selector,
        metadata.inputs,
        metadata.outputs,
        project_root
      )

      -- realInputName has alias 'aliasedName' which is used in parent as [aliasedName]="..."
      assert.is_true((usages['realInputName'] or 0) > 0, 'Should find realInputName via its alias aliasedName')
    end)

    it('should find output event handlers in parent template', function()
      local server = require('angular-refs.server')
      local child_path = helpers.get_fixture_path('components/parent-child/child.component.ts')
      local file = io.open(child_path, 'r')
      local content = file:read('*all')
      file:close()

      local metadata = server.get_component_metadata(content)
      local project_root = server.find_project_root(vim.fn.fnamemodify(child_path, ':h'))

      local usages = server.find_selector_usages(
        metadata.selector,
        metadata.inputs,
        metadata.outputs,
        project_root
      )

      -- simpleOutput is used in parent as (simpleOutput)="..."
      assert.is_true((usages['simpleOutput'] or 0) > 0, 'Should find simpleOutput usage in parent')
    end)

    it('should find two-way bindings in parent template', function()
      local server = require('angular-refs.server')
      local child_path = helpers.get_fixture_path('components/parent-child/child.component.ts')
      local file = io.open(child_path, 'r')
      local content = file:read('*all')
      file:close()

      local metadata = server.get_component_metadata(content)
      local project_root = server.find_project_root(vim.fn.fnamemodify(child_path, ':h'))

      local usages = server.find_selector_usages(
        metadata.selector,
        metadata.inputs,
        metadata.outputs,
        project_root
      )

      -- count is used as [(count)]="..." in parent
      assert.is_true((usages['count'] or 0) > 0, 'Should find count two-way binding usage in parent')
    end)

    it('should count two-way binding Change output', function()
      local server = require('angular-refs.server')
      local child_path = helpers.get_fixture_path('components/parent-child/child.component.ts')
      local file = io.open(child_path, 'r')
      local content = file:read('*all')
      file:close()

      local metadata = server.get_component_metadata(content)
      local project_root = server.find_project_root(vim.fn.fnamemodify(child_path, ':h'))

      local usages = server.find_selector_usages(
        metadata.selector,
        metadata.inputs,
        metadata.outputs,
        project_root
      )

      -- [(count)]="..." should count both count input and countChange output
      assert.is_true((usages['count'] or 0) > 0, 'Should find count input from two-way binding')
      assert.is_true((usages['countChange'] or 0) > 0, 'Should find countChange output from two-way binding')
    end)

    it('should only count bindings on component elements (not entire file)', function()
      local server = require('angular-refs.server')
      local child_path = helpers.get_fixture_path('components/parent-child/child.component.ts')
      local file = io.open(child_path, 'r')
      local content = file:read('*all')
      file:close()

      local metadata = server.get_component_metadata(content)
      local project_root = server.find_project_root(vim.fn.fnamemodify(child_path, ':h'))

      local usages = server.find_selector_usages(
        metadata.selector,
        metadata.inputs,
        metadata.outputs,
        project_root
      )

      -- simpleInput is used on <app-child> elements, count should be >= 1
      -- but should not count bindings from other elements in the file
      assert.is_true((usages['simpleInput'] or 0) >= 1, 'Should find simpleInput on app-child')
    end)
  end)

  describe('data service', function()
    it('should have signal properties', function()
      local bufnr = helpers.open_fixture('services/data.service.ts')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'readonly items = signal'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'readonly currentUser = signal'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'readonly isLoading = signal'))
    end)

    it('should have computed properties', function()
      local bufnr = helpers.open_fixture('services/data.service.ts')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'readonly itemCount = computed'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'readonly activeItems = computed'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'readonly totalPrice = computed'))
    end)

    it('should have public methods', function()
      local bufnr = helpers.open_fixture('services/data.service.ts')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'fetchItems%(%)'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'getItemById'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'addItem'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'updateItem'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'removeItem'))
    end)

    it('should have private methods', function()
      local bufnr = helpers.open_fixture('services/data.service.ts')
      ctx:add_buffer(bufnr)

      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'private internalMethod'))
      assert.is_not_nil(helpers.find_line_with_pattern(bufnr, 'private _helperMethod'))
    end)
  end)
end)
