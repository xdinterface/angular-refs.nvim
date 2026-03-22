local server = require('angular-refs.server')
local helpers = require('test.helpers')

describe('angular-refs.server', function()
  describe('is_lifecycle_method', function()
    it('should identify ngOnInit as lifecycle method', function()
      assert.is_true(server.is_lifecycle_method('ngOnInit'))
    end)

    it('should identify ngOnDestroy as lifecycle method', function()
      assert.is_true(server.is_lifecycle_method('ngOnDestroy'))
    end)

    it('should identify ngOnChanges as lifecycle method', function()
      assert.is_true(server.is_lifecycle_method('ngOnChanges'))
    end)

    it('should identify ngDoCheck as lifecycle method', function()
      assert.is_true(server.is_lifecycle_method('ngDoCheck'))
    end)

    it('should identify ngAfterContentInit as lifecycle method', function()
      assert.is_true(server.is_lifecycle_method('ngAfterContentInit'))
    end)

    it('should identify ngAfterContentChecked as lifecycle method', function()
      assert.is_true(server.is_lifecycle_method('ngAfterContentChecked'))
    end)

    it('should identify ngAfterViewInit as lifecycle method', function()
      assert.is_true(server.is_lifecycle_method('ngAfterViewInit'))
    end)

    it('should identify ngAfterViewChecked as lifecycle method', function()
      assert.is_true(server.is_lifecycle_method('ngAfterViewChecked'))
    end)

    it('should NOT identify regular methods as lifecycle methods', function()
      assert.is_false(server.is_lifecycle_method('handleClick'))
      assert.is_false(server.is_lifecycle_method('saveData'))
      assert.is_false(server.is_lifecycle_method('processItems'))
      assert.is_false(server.is_lifecycle_method('init'))
      assert.is_false(server.is_lifecycle_method('destroy'))
    end)
  end)

  describe('parse_tcb_symbols', function()
    it('should parse ((this)).property pattern', function()
      local tcb = [[
        var _t1 = null! as MyComponent;
        ((this)).myProperty;
        ((this)).anotherProperty;
      ]]
      local symbols = server.parse_tcb_symbols(tcb)
      assert.equals(1, symbols['myProperty'] or 0)
      assert.equals(1, symbols['anotherProperty'] or 0)
    end)

    it('should parse (this).property pattern', function()
      local tcb = [[
        (this).simpleProperty;
        (this).methodCall();
      ]]
      local symbols = server.parse_tcb_symbols(tcb)
      assert.equals(1, symbols['simpleProperty'] or 0)
      assert.equals(1, symbols['methodCall'] or 0)
    end)

    it('should parse this.property pattern', function()
      local tcb = [[
        this.directProperty;
        this.directMethod();
      ]]
      local symbols = server.parse_tcb_symbols(tcb)
      assert.equals(1, symbols['directProperty'] or 0)
      assert.equals(1, symbols['directMethod'] or 0)
    end)

    it('should parse ((_ctx)).property pattern (legacy)', function()
      local tcb = [[
        ((_ctx)).legacyProperty;
        ((_ctx)).legacyMethod();
      ]]
      local symbols = server.parse_tcb_symbols(tcb)
      assert.equals(1, symbols['legacyProperty'] or 0)
      assert.equals(1, symbols['legacyMethod'] or 0)
    end)

    it('should parse _ctx.property pattern (legacy)', function()
      local tcb = [[
        _ctx.oldProperty;
        _ctx.oldMethod();
      ]]
      local symbols = server.parse_tcb_symbols(tcb)
      assert.equals(1, symbols['oldProperty'] or 0)
      assert.equals(1, symbols['oldMethod'] or 0)
    end)

    it('should count multiple occurrences of the same symbol', function()
      local tcb = [[
        ((this)).count;
        ((this)).count;
        ((this)).count;
      ]]
      local symbols = server.parse_tcb_symbols(tcb)
      assert.equals(3, symbols['count'] or 0)
    end)

    it('should handle mixed patterns', function()
      local tcb = [[
        ((this)).prop1;
        (this).prop2;
        this.prop3;
        ((_ctx)).prop4;
        _ctx.prop5;
      ]]
      local symbols = server.parse_tcb_symbols(tcb)
      assert.equals(1, symbols['prop1'] or 0)
      assert.equals(1, symbols['prop2'] or 0)
      assert.equals(1, symbols['prop3'] or 0)
      assert.equals(1, symbols['prop4'] or 0)
      assert.equals(1, symbols['prop5'] or 0)
    end)

    it('should parse this.property at start of line', function()
      local tcb = 'this.startOfLine;\n((this)).otherProp;'
      local symbols = server.parse_tcb_symbols(tcb)
      assert.equals(1, symbols['startOfLine'] or 0)
      assert.equals(1, symbols['otherProp'] or 0)
    end)

    it('should parse this.property at start of each line', function()
      local tcb = 'this.first;\nthis.second;\nthis.third;'
      local symbols = server.parse_tcb_symbols(tcb)
      assert.equals(1, symbols['first'] or 0)
      assert.equals(1, symbols['second'] or 0)
      assert.equals(1, symbols['third'] or 0)
    end)

    it('should handle method calls with parentheses', function()
      local tcb = [[
        ((this)).getData();
        ((this)).processItem(item);
        ((this)).calculate(a, b, c);
      ]]
      local symbols = server.parse_tcb_symbols(tcb)
      assert.equals(1, symbols['getData'] or 0)
      assert.equals(1, symbols['processItem'] or 0)
      assert.equals(1, symbols['calculate'] or 0)
    end)

    it('should handle property access chains', function()
      local tcb = [[
        ((this)).nested.deep.value;
        ((this)).config.option;
      ]]
      local symbols = server.parse_tcb_symbols(tcb)
      assert.equals(1, symbols['nested'] or 0)
      assert.equals(1, symbols['config'] or 0)
    end)

    it('should return empty table for empty input', function()
      local symbols = server.parse_tcb_symbols('')
      assert.same({}, symbols)
    end)

    it('should return empty table for nil input', function()
      local symbols = server.parse_tcb_symbols(nil)
      assert.same({}, symbols)
    end)

    it('should ignore non-matching patterns', function()
      local tcb = [[
        var x = 5;
        const name = "test";
        function doSomething() {}
      ]]
      local symbols = server.parse_tcb_symbols(tcb)
      assert.same({}, symbols)
    end)
  end)

  describe('find_template_file', function()
    it('should return nil for non-component files', function()
      local result = server.find_template_file('/path/to/service.ts')
      assert.is_nil(result)
    end)
  end)

  describe('find_project_root', function()
    it('should return nil for non-existent path', function()
      local result = server.find_project_root('/non/existent/path')
      assert.is_nil(result)
    end)
  end)

  describe('find_selector_usages', function()
    it('should return empty for nil selector', function()
      local result = server.find_selector_usages(nil, {}, {}, '/some/path')
      assert.same({}, result)
    end)

    it('should return empty for nil project root', function()
      local result = server.find_selector_usages('app-test', {}, {}, nil)
      assert.same({}, result)
    end)

    it('should return empty for empty inputs and outputs', function()
      local result = server.find_selector_usages('app-test', {}, {}, '/some/path')
      assert.same({}, result)
    end)

    it('should return empty when no HTML files match selector', function()
      local result = server.find_selector_usages('app-nonexistent', {
        { name = 'testInput', alias = nil, kind = 'decorator' }
      }, {}, '/tmp/nonexistent')
      assert.same({}, result)
    end)
  end)

  describe('get_declarations_in_buffer', function()
    it('should find property declarations', function()
      local content = [[
export class TestComponent {
  myProperty = 'value';
  anotherProp: string;
}
]]
      local buf = helpers.create_buffer_with_content(content)
      local decls = server.get_declarations_in_buffer(buf)
      vim.api.nvim_buf_delete(buf, { force = true })

      local names = {}
      for _, d in ipairs(decls) do
        names[d.name] = true
      end

      assert.is_true(names['myProperty'] or false)
      assert.is_true(names['anotherProp'] or false)
    end)

    it('should find method declarations', function()
      local content = [[
export class TestComponent {
  myMethod() {}
  async asyncMethod() {}
}
]]
      local buf = helpers.create_buffer_with_content(content)
      local decls = server.get_declarations_in_buffer(buf)
      vim.api.nvim_buf_delete(buf, { force = true })

      local names = {}
      for _, d in ipairs(decls) do
        names[d.name] = true
      end

      assert.is_true(names['myMethod'] or false)
      assert.is_true(names['asyncMethod'] or false)
    end)

    it('should find getter and setter declarations', function()
      local content = [[
export class TestComponent {
  get computedValue() { return ''; }
  set computedValue(v: string) {}
}
]]
      local buf = helpers.create_buffer_with_content(content)
      local decls = server.get_declarations_in_buffer(buf)
      vim.api.nvim_buf_delete(buf, { force = true })

      local names = {}
      for _, d in ipairs(decls) do
        names[d.name] = true
      end

      assert.is_true(names['computedValue'] or false)
    end)

    it('should find signal declarations', function()
      local content = [[
export class TestComponent {
  count = signal(0);
  simpleInput = input<string>();
  requiredInput = input.required<string>();
  clicked = output<void>();
  twoWay = model(0);
}
]]
      local buf = helpers.create_buffer_with_content(content)
      local decls = server.get_declarations_in_buffer(buf)
      vim.api.nvim_buf_delete(buf, { force = true })

      local names = {}
      for _, d in ipairs(decls) do
        names[d.name] = true
      end

      assert.is_true(names['count'] or false)
      assert.is_true(names['simpleInput'] or false)
      assert.is_true(names['requiredInput'] or false)
      assert.is_true(names['clicked'] or false)
      assert.is_true(names['twoWay'] or false)
    end)

    it('should find Angular 19+ signal declarations', function()
      local content = [[
export class TestComponent {
  count = signal(0);
  doubled = linkedSignal(() => this.count() * 2);
  userData = resource({
    request: () => ({ id: this.userId() }),
    loader: ({ request }) => fetch('/api/users/' + request.id)
  });
  rxData = rxResource({
    request: () => this.searchTerm(),
    loader: ({ request }) => this.http.get('/api/search?q=' + request)
  });
}
]]
      local buf = helpers.create_buffer_with_content(content)
      local decls = server.get_declarations_in_buffer(buf)
      vim.api.nvim_buf_delete(buf, { force = true })

      local names = {}
      for _, d in ipairs(decls) do
        names[d.name] = true
      end

      assert.is_true(names['count'] or false)
      assert.is_true(names['doubled'] or false)
      assert.is_true(names['userData'] or false)
      assert.is_true(names['rxData'] or false)
    end)

    it('should exclude private members', function()
      local content = [[
export class TestComponent {
  publicProp = 'public';
  private privateProp = 'private';
  #ecmaPrivate = 'ecma';
}
]]
      local buf = helpers.create_buffer_with_content(content)
      local decls = server.get_declarations_in_buffer(buf)
      vim.api.nvim_buf_delete(buf, { force = true })

      local names = {}
      for _, d in ipairs(decls) do
        names[d.name] = true
      end

      assert.is_true(names['publicProp'] or false)
      assert.is_falsy(names['privateProp'])
      assert.is_falsy(names['ecmaPrivate'])
    end)

    it('should return empty for non-class content', function()
      local content = [[
const x = 5;
function helper() {}
]]
      local buf = helpers.create_buffer_with_content(content)
      local decls = server.get_declarations_in_buffer(buf)
      vim.api.nvim_buf_delete(buf, { force = true })

      assert.equals(0, #decls)
    end)

    it('should exclude lifecycle methods from declarations', function()
      local content = [[
export class TestComponent {
  publicProp = 'value';
  ngOnInit() {}
  ngOnDestroy() {}
  ngAfterViewInit() {}
  handleClick() {}
}
]]
      local buf = helpers.create_buffer_with_content(content)
      local decls = server.get_declarations_in_buffer(buf)
      vim.api.nvim_buf_delete(buf, { force = true })

      local names = {}
      for _, d in ipairs(decls) do
        names[d.name] = true
      end

      assert.is_true(names['publicProp'] or false)
      assert.is_true(names['handleClick'] or false)
      assert.is_falsy(names['ngOnInit'])
      assert.is_falsy(names['ngOnDestroy'])
      assert.is_falsy(names['ngAfterViewInit'])
    end)

    it('should exclude all Angular lifecycle methods', function()
      local content = [[
export class TestComponent {
  ngOnInit() {}
  ngOnDestroy() {}
  ngOnChanges() {}
  ngDoCheck() {}
  ngAfterContentInit() {}
  ngAfterContentChecked() {}
  ngAfterViewInit() {}
  ngAfterViewChecked() {}
  regularMethod() {}
}
]]
      local buf = helpers.create_buffer_with_content(content)
      local decls = server.get_declarations_in_buffer(buf)
      vim.api.nvim_buf_delete(buf, { force = true })

      local names = {}
      for _, d in ipairs(decls) do
        names[d.name] = true
      end

      assert.is_true(names['regularMethod'] or false)
      assert.is_falsy(names['ngOnInit'])
      assert.is_falsy(names['ngOnDestroy'])
      assert.is_falsy(names['ngOnChanges'])
      assert.is_falsy(names['ngDoCheck'])
      assert.is_falsy(names['ngAfterContentInit'])
      assert.is_falsy(names['ngAfterContentChecked'])
      assert.is_falsy(names['ngAfterViewInit'])
      assert.is_falsy(names['ngAfterViewChecked'])
    end)

    it('should include line and column information', function()
      local content = [[
export class TestComponent {
  myProperty = 'value';
}
]]
      local buf = helpers.create_buffer_with_content(content)
      local decls = server.get_declarations_in_buffer(buf)
      vim.api.nvim_buf_delete(buf, { force = true })

      assert.equals(1, #decls)
      assert.equals('myProperty', decls[1].name)
      assert.equals(1, decls[1].line) -- 0-indexed, line 2 = index 1
      assert.is_true(decls[1].col >= 0)
    end)

    it('should find generic method declarations', function()
      local content = [[
export class TestComponent {
  getData<T>(): T { return {} as T; }
  fetchItems<T, U>(a: T): U { return {} as U; }
}
]]
      local buf = helpers.create_buffer_with_content(content)
      local decls = server.get_declarations_in_buffer(buf)
      vim.api.nvim_buf_delete(buf, { force = true })

      local names = {}
      for _, d in ipairs(decls) do
        names[d.name] = true
      end

      assert.is_true(names['getData'] or false)
      assert.is_true(names['fetchItems'] or false)
    end)

    it('should find constructor parameter properties', function()
      local content = [[
export class TestComponent {
  constructor(public svc: Service, private priv: Other, readonly ro: Third) {}
}
]]
      local buf = helpers.create_buffer_with_content(content)
      local decls = server.get_declarations_in_buffer(buf)
      vim.api.nvim_buf_delete(buf, { force = true })

      local names = {}
      for _, d in ipairs(decls) do
        names[d.name] = true
      end

      assert.is_true(names['svc'] or false)
      assert.is_true(names['ro'] or false)
      assert.is_falsy(names['priv'])
    end)

    it('should find protected constructor parameter properties', function()
      local content = [[
export class TestComponent {
  constructor(protected router: Router) {}
}
]]
      local buf = helpers.create_buffer_with_content(content)
      local decls = server.get_declarations_in_buffer(buf)
      vim.api.nvim_buf_delete(buf, { force = true })

      local names = {}
      for _, d in ipairs(decls) do
        names[d.name] = true
      end

      assert.is_true(names['router'] or false)
    end)

    it('should exclude underscore-prefixed private members', function()
      local content = [[
export class TestComponent {
  publicProp = 'public';
  _privateProp = 'private';
  _anotherPrivate: string;
}
]]
      local buf = helpers.create_buffer_with_content(content)
      local decls = server.get_declarations_in_buffer(buf)
      vim.api.nvim_buf_delete(buf, { force = true })

      local names = {}
      for _, d in ipairs(decls) do
        names[d.name] = true
      end

      assert.is_true(names['publicProp'] or false)
      assert.is_falsy(names['_privateProp'])
      assert.is_falsy(names['_anotherPrivate'])
    end)
  end)

  describe('get_component_metadata', function()
    it('should extract component selector', function()
      local content = [[
@Component({
  selector: 'app-test',
  template: ''
})
export class TestComponent {}
]]
      local metadata = server.get_component_metadata(content)
      assert.equals('app-test', metadata.selector)
    end)

    it('should extract simple @Input properties', function()
      local content = [[
@Component({ selector: 'app-test', template: '' })
export class TestComponent {
  @Input() name: string;
  @Input() value: number;
}
]]
      local metadata = server.get_component_metadata(content)
      assert.equals(2, #metadata.inputs)

      local names = {}
      for _, input in ipairs(metadata.inputs) do
        names[input.name] = input
      end

      assert.is_not_nil(names['name'])
      assert.is_nil(names['name'].alias)
      assert.is_not_nil(names['value'])
    end)

    it('should extract aliased @Input properties', function()
      local content = [[
@Component({ selector: 'app-test', template: '' })
export class TestComponent {
  @Input('externalName') internalName: string;
}
]]
      local metadata = server.get_component_metadata(content)
      assert.equals(1, #metadata.inputs)
      assert.equals('internalName', metadata.inputs[1].name)
      assert.equals('externalName', metadata.inputs[1].alias)
    end)

    it('should extract @Input with options object', function()
      local content = [[
@Component({ selector: 'app-test', template: '' })
export class TestComponent {
  @Input({ required: true, alias: 'external' }) internal: string;
}
]]
      local metadata = server.get_component_metadata(content)
      assert.equals(1, #metadata.inputs)
      assert.equals('internal', metadata.inputs[1].name)
      assert.equals('external', metadata.inputs[1].alias)
      assert.is_true(metadata.inputs[1].required)
    end)

    it('should extract simple @Output properties', function()
      local content = [[
@Component({ selector: 'app-test', template: '' })
export class TestComponent {
  @Output() clicked = new EventEmitter<void>();
}
]]
      local metadata = server.get_component_metadata(content)
      assert.equals(1, #metadata.outputs)
      assert.equals('clicked', metadata.outputs[1].name)
      assert.is_nil(metadata.outputs[1].alias)
    end)

    it('should extract aliased @Output properties', function()
      local content = [[
@Component({ selector: 'app-test', template: '' })
export class TestComponent {
  @Output('externalEvent') internalEvent = new EventEmitter<void>();
}
]]
      local metadata = server.get_component_metadata(content)
      assert.equals(1, #metadata.outputs)
      assert.equals('internalEvent', metadata.outputs[1].name)
      assert.equals('externalEvent', metadata.outputs[1].alias)
    end)

    it('should extract signal inputs', function()
      local content = [[
@Component({ selector: 'app-test', template: '' })
export class TestComponent {
  name = input<string>();
  requiredName = input.required<string>();
}
]]
      local metadata = server.get_component_metadata(content)
      assert.equals(2, #metadata.inputs)

      local inputs = {}
      for _, input in ipairs(metadata.inputs) do
        inputs[input.name] = input
      end

      assert.is_not_nil(inputs['name'])
      assert.equals('signal', inputs['name'].kind)
      assert.is_not_nil(inputs['requiredName'])
      assert.is_true(inputs['requiredName'].required)
    end)

    it('should extract signal outputs', function()
      local content = [[
@Component({ selector: 'app-test', template: '' })
export class TestComponent {
  clicked = output<void>();
}
]]
      local metadata = server.get_component_metadata(content)
      assert.equals(1, #metadata.outputs)
      assert.equals('clicked', metadata.outputs[1].name)
      assert.equals('signal', metadata.outputs[1].kind)
    end)

    it('should extract model (two-way binding) as input and output', function()
      local content = [[
@Component({ selector: 'app-test', template: '' })
export class TestComponent {
  count = model<number>(0);
}
]]
      local metadata = server.get_component_metadata(content)
      assert.equals(1, #metadata.inputs)
      assert.equals('count', metadata.inputs[1].name)
      assert.equals(1, #metadata.outputs)
      assert.equals('countChange', metadata.outputs[1].name)
    end)

    it('should return empty metadata for non-component files', function()
      local content = [[
export class MyService {
  getData() {}
}
]]
      local metadata = server.get_component_metadata(content)
      assert.is_nil(metadata.selector)
      assert.equals(0, #metadata.inputs)
      assert.equals(0, #metadata.outputs)
    end)
  end)

  describe('parse_host_bindings', function()
    it('should parse property bindings in host', function()
      local content = [[
@Component({
  host: {
    '[class.active]': 'isActive',
    '[attr.data-id]': 'componentId'
  }
})
]]
      local symbols = server.parse_host_bindings(content)
      assert.equals(1, symbols['isActive'] or 0)
      assert.equals(1, symbols['componentId'] or 0)
    end)

    it('should parse event bindings in host', function()
      local content = [[
@Component({
  host: {
    '(click)': 'onClick($event)',
    '(window:resize)': 'onResize($event)'
  }
})
]]
      local symbols = server.parse_host_bindings(content)
      assert.equals(1, symbols['onClick'] or 0)
      assert.equals(1, symbols['onResize'] or 0)
    end)

    it('should return empty for no host block', function()
      local content = [[
@Component({
  selector: 'app-test'
})
]]
      local symbols = server.parse_host_bindings(content)
      assert.same({}, symbols)
    end)
  end)

  describe('parse_template_control_flow', function()
    it('should parse event bindings', function()
      local content = [[
<button (click)="handleClick()">Click</button>
<div (contextmenu)="onContextMenu($event)">Right click</div>
]]
      local symbols = server.parse_template_control_flow(content)
      assert.equals(1, symbols['handleClick'] or 0)
      assert.equals(1, symbols['onContextMenu'] or 0)
    end)

    it('should parse @for collection', function()
      local content = [[
@for (item of items; track item.id) {
  <div>{{ item.name }}</div>
}
]]
      local symbols = server.parse_template_control_flow(content)
      assert.equals(1, symbols['items'] or 0)
    end)

    it('should parse @if conditions', function()
      local content = [[
@if (showContent) {
  <div>Visible</div>
}
]]
      local symbols = server.parse_template_control_flow(content)
      assert.equals(1, symbols['showContent'] or 0)
    end)

    it('should parse interpolations', function()
      local content = [[
<p>{{ message }}</p>
<span>{{ count }}</span>
]]
      local symbols = server.parse_template_control_flow(content)
      assert.equals(1, symbols['message'] or 0)
      assert.equals(1, symbols['count'] or 0)
    end)

    it('should return empty for nil input', function()
      local symbols = server.parse_template_control_flow(nil)
      assert.same({}, symbols)
    end)

    it('should parse *ngIf legacy directive', function()
      local content = [[
<div *ngIf="showContent">Visible</div>
<span *ngIf="isLoading">Loading...</span>
]]
      local symbols = server.parse_template_control_flow(content)
      assert.equals(1, symbols['showContent'] or 0)
      assert.equals(1, symbols['isLoading'] or 0)
    end)

    it('should parse *ngIf with else block', function()
      local content = [[
<div *ngIf="hasData; else noDataTemplate">Has data</div>
]]
      local symbols = server.parse_template_control_flow(content)
      assert.equals(1, symbols['hasData'] or 0)
    end)

    it('should parse *ngFor legacy directive', function()
      local content = [[
<li *ngFor="let item of items">{{ item.name }}</li>
]]
      local symbols = server.parse_template_control_flow(content)
      assert.equals(1, symbols['items'] or 0)
    end)

    it('should parse *ngFor with trackBy', function()
      local content = [[
<li *ngFor="let item of items; trackBy: trackById">{{ item.name }}</li>
]]
      local symbols = server.parse_template_control_flow(content)
      assert.equals(1, symbols['items'] or 0)
      assert.equals(1, symbols['trackById'] or 0)
    end)

    it('should parse [ngSwitch] directive', function()
      local content = [[
<div [ngSwitch]="status">
  <span *ngSwitchCase="'active'">Active</span>
</div>
]]
      local symbols = server.parse_template_control_flow(content)
      assert.is_true((symbols['status'] or 0) >= 1)
    end)

    it('should parse ternary expressions in interpolations', function()
      local content = [[
<p>{{ isActive ? activeLabel : inactiveLabel }}</p>
]]
      local symbols = server.parse_template_control_flow(content)
      assert.is_true((symbols['isActive'] or 0) >= 1)
      assert.is_true((symbols['activeLabel'] or 0) >= 1)
      assert.is_true((symbols['inactiveLabel'] or 0) >= 1)
    end)

    it('should parse pipe expressions', function()
      local content = [[
<p>{{ dateValue | date:'short' }}</p>
<span>{{ textValue | uppercase }}</span>
]]
      local symbols = server.parse_template_control_flow(content)
      assert.is_true((symbols['dateValue'] or 0) >= 1)
      assert.is_true((symbols['textValue'] or 0) >= 1)
    end)

    it('should parse async pipe with observables', function()
      local content = [[
<div>{{ data$ | async }}</div>
<span>{{ asyncData$ | async }}</span>
]]
      local symbols = server.parse_template_control_flow(content)
      assert.equals(1, symbols['data$'] or 0)
      assert.equals(1, symbols['asyncData$'] or 0)
    end)

    it('should handle method with arguments in template', function()
      local content = '<button (click)="save(item, index, $event)">Save</button>'
      local symbols = server.parse_template_control_flow(content)
      assert.equals(1, symbols['save'] or 0)
    end)

    it('should handle signal() calls in template', function()
      local content = '{{ count() }}'
      local symbols = server.parse_template_control_flow(content)
      assert.equals(1, symbols['count'] or 0)
    end)

    it('should handle multiple refs to same symbol', function()
      local content = [[
        <div>{{ items.length }}</div>
        <ul>
          @for (item of items; track item) {
            <li>{{ item }}</li>
          }
        </ul>
        <span *ngIf="items.length > 0">Has items</span>
      ]]
      local symbols = server.parse_template_control_flow(content)
      assert.is_true((symbols['items'] or 0) >= 2)
    end)

    it('should handle complex event handler expressions', function()
      local content = '<input (input)="name = $event.target.value" />'
      local symbols = server.parse_template_control_flow(content)
      assert.equals(1, symbols['name'] or 0)
    end)

    it('should handle property binding expressions', function()
      local content = '<div [class.active]="isActive" [style.color]="textColor"></div>'
      local symbols = server.parse_template_control_flow(content)
      assert.equals(1, symbols['isActive'] or 0)
      assert.equals(1, symbols['textColor'] or 0)
    end)

    it('should handle two-way binding', function()
      local content = '<input [(ngModel)]="username" />'
      local symbols = server.parse_template_control_flow(content)
      assert.equals(1, symbols['username'] or 0)
    end)

    it('should handle @switch expression', function()
      local content = [[
        @switch (status) {
          @case ('active') { <span>Active</span> }
          @case ('inactive') { <span>Inactive</span> }
        }
      ]]
      local symbols = server.parse_template_control_flow(content)
      assert.equals(1, symbols['status'] or 0)
    end)

    it('should handle @let declarations', function()
      local content = '@let total = count * price'
      local symbols = server.parse_template_control_flow(content)
      assert.equals(1, symbols['count'] or 0)
      assert.equals(1, symbols['price'] or 0)
    end)

    it('should parse custom pipe names', function()
      local content = '<p>{{ value | myCustomPipe | sortPipe }}</p>'
      local symbols = server.parse_template_control_flow(content)
      assert.equals(1, symbols['myCustomPipe'] or 0)
      assert.equals(1, symbols['sortPipe'] or 0)
    end)

    it('should not parse built-in pipe names', function()
      local content = '<p>{{ value | date | uppercase | async }}</p>'
      local symbols = server.parse_template_control_flow(content)
      assert.equals(0, symbols['date'] or 0)
      assert.equals(0, symbols['uppercase'] or 0)
      assert.equals(0, symbols['async'] or 0)
    end)

    it('should parse @defer with when condition', function()
      local content = '@defer (when isReady) { <div></div> }'
      local symbols = server.parse_template_control_flow(content)
      assert.equals(1, symbols['isReady'] or 0)
    end)

    it('should parse @defer with complex when condition', function()
      local content = '@defer (when dataLoaded && userAuthenticated) { <div></div> }'
      local symbols = server.parse_template_control_flow(content)
      assert.equals(1, symbols['dataLoaded'] or 0)
      assert.equals(1, symbols['userAuthenticated'] or 0)
    end)

    it('should parse @case expressions', function()
      local content = '@switch (s) { @case (StatusEnum.Active) { } }'
      local symbols = server.parse_template_control_flow(content)
      assert.equals(1, symbols['StatusEnum'] or 0)
    end)

    it('should parse @case with multiple values', function()
      local content = [[@switch (status) {
        @case (Status.Active) { }
        @case (Status.Pending) { }
      }]]
      local symbols = server.parse_template_control_flow(content)
      assert.is_true((symbols['Status'] or 0) >= 2)
    end)

    it('should parse method arguments in interpolations', function()
      local content = '{{ formatDate(startDate, endDate, locale) }}'
      local symbols = server.parse_template_control_flow(content)
      assert.equals(1, symbols['formatDate'] or 0)
      assert.equals(1, symbols['startDate'] or 0)
      assert.equals(1, symbols['endDate'] or 0)
      assert.equals(1, symbols['locale'] or 0)
    end)

    it('should parse object literal values in ngClass', function()
      local content = '<div [ngClass]="{active: isActive, disabled: isDisabled}"></div>'
      local symbols = server.parse_template_control_flow(content)
      assert.is_true((symbols['isActive'] or 0) >= 1)
      assert.is_true((symbols['isDisabled'] or 0) >= 1)
    end)

    it('should parse class binding expressions', function()
      local content = '<div [class.active]="isSelected" [class.hidden]="!isVisible"></div>'
      local symbols = server.parse_template_control_flow(content)
      assert.equals(1, symbols['isSelected'] or 0)
      assert.equals(1, symbols['isVisible'] or 0)
    end)

    it('should parse style binding expressions', function()
      local content = '<div [style.backgroundColor]="bgColor" [style.width.px]="itemWidth"></div>'
      local symbols = server.parse_template_control_flow(content)
      assert.equals(1, symbols['bgColor'] or 0)
      assert.equals(1, symbols['itemWidth'] or 0)
    end)

    it('should parse attr binding expressions', function()
      local content = '<input [attr.data-id]="itemId" [attr.aria-label]="labelText">'
      local symbols = server.parse_template_control_flow(content)
      assert.equals(1, symbols['itemId'] or 0)
      assert.equals(1, symbols['labelText'] or 0)
    end)

    it('should parse pipe arguments', function()
      local content = '{{ items | slice:startIdx:endIdx }}'
      local symbols = server.parse_template_control_flow(content)
      assert.is_true((symbols['items'] or 0) >= 1)
      assert.is_true((symbols['startIdx'] or 0) >= 1)
      assert.is_true((symbols['endIdx'] or 0) >= 1)
    end)

    it('should parse ternary in event handlers', function()
      local content = '<button (click)="isOpen ? close() : open()"></button>'
      local symbols = server.parse_template_control_flow(content)
      assert.is_true((symbols['isOpen'] or 0) >= 1)
      assert.is_true((symbols['close'] or 0) >= 1)
      assert.is_true((symbols['open'] or 0) >= 1)
    end)

    it('should parse nullish coalescing operator', function()
      local content = '{{ userName ?? defaultName }}'
      local symbols = server.parse_template_control_flow(content)
      assert.is_true((symbols['userName'] or 0) >= 1)
      assert.is_true((symbols['defaultName'] or 0) >= 1)
    end)

    it('should parse logical operators in bindings', function()
      local content = '<button [disabled]="isLoading || hasError || isEmpty"></button>'
      local symbols = server.parse_template_control_flow(content)
      assert.is_true((symbols['isLoading'] or 0) >= 1)
      assert.is_true((symbols['hasError'] or 0) >= 1)
      assert.is_true((symbols['isEmpty'] or 0) >= 1)
    end)

    it('should parse single-quoted object literals', function()
      local content = [[<div [ngClass]='{"active": isActive}'></div>]]
      local symbols = server.parse_template_control_flow(content)
      assert.is_true((symbols['isActive'] or 0) >= 1)
    end)

    it('should parse simple method call with multiple arguments', function()
      local content = '{{ formatDate(startDate, endDate) }}'
      local symbols = server.parse_template_control_flow(content)
      assert.is_true((symbols['formatDate'] or 0) >= 1)
      assert.is_true((symbols['startDate'] or 0) >= 1)
      assert.is_true((symbols['endDate'] or 0) >= 1)
    end)

    it('should parse @for with method call collection', function()
      local content = '@for (item of getItems(); track item.id) {\n  <div>{{ item.name }}</div>\n}'
      local symbols = server.parse_template_control_flow(content)
      assert.is_true((symbols['getItems'] or 0) >= 1)
    end)

    it('should only extract root identifier from @case with property access', function()
      local content = '@switch (status) {\n  @case (StatusEnum.Active) {\n    <span>Active</span>\n  }\n}'
      local symbols = server.parse_template_control_flow(content)
      assert.is_true((symbols['StatusEnum'] or 0) >= 1)
      assert.is_nil(symbols['Active'])
    end)

    it('should parse @case with simple identifier', function()
      local content = '@switch (mode) {\n  @case (ViewMode) {\n    <span>View</span>\n  }\n}'
      local symbols = server.parse_template_control_flow(content)
      assert.is_true((symbols['ViewMode'] or 0) >= 1)
    end)

    it('should parse optional chaining in interpolations', function()
      local content = '{{ foo?.bar }}'
      local symbols = server.parse_template_control_flow(content)
      assert.is_true((symbols['foo'] or 0) >= 1)
    end)

    it('should parse @let with method call expression', function()
      local content = '@let result = computeValue(inputData);'
      local symbols = server.parse_template_control_flow(content)
      assert.is_true((symbols['computeValue'] or 0) >= 1)
      assert.is_true((symbols['inputData'] or 0) >= 1)
    end)

    it('should parse two-way binding with simple property', function()
      local content = '<input [(ngModel)]="username">'
      local symbols = server.parse_template_control_flow(content)
      assert.is_true((symbols['username'] or 0) >= 1)
    end)
  end)

  describe('get_decorator_refs', function()
    it('should count @HostListener decorated method', function()
      local content = [[
export class TestComponent {
  @HostListener('click')
  handleClick() {}
}
]]
      local buf = helpers.create_buffer_with_content(content)
      local refs = server.get_decorator_refs(buf, 'handleClick')
      vim.api.nvim_buf_delete(buf, { force = true })
      assert.equals(1, refs)
    end)

    it('should count @HostListener with event details', function()
      local content = [[
export class TestComponent {
  @HostListener('document:keydown', ['$event'])
  onKeydown(event: KeyboardEvent) {}
}
]]
      local buf = helpers.create_buffer_with_content(content)
      local refs = server.get_decorator_refs(buf, 'onKeydown')
      vim.api.nvim_buf_delete(buf, { force = true })
      assert.equals(1, refs)
    end)

    it('should count @HostBinding property', function()
      local content = [[
export class TestComponent {
  @HostBinding('class.active')
  isActive = false;
}
]]
      local buf = helpers.create_buffer_with_content(content)
      local refs = server.get_decorator_refs(buf, 'isActive')
      vim.api.nvim_buf_delete(buf, { force = true })
      assert.equals(1, refs)
    end)

    it('should count @HostBinding getter', function()
      local content = [[
export class TestComponent {
  @HostBinding('attr.data-id')
  get dataId() { return this.id; }
}
]]
      local buf = helpers.create_buffer_with_content(content)
      local refs = server.get_decorator_refs(buf, 'dataId')
      vim.api.nvim_buf_delete(buf, { force = true })
      assert.equals(1, refs)
    end)

    it('should return 0 for non-decorated methods', function()
      local content = [[
export class TestComponent {
  regularMethod() {}
  anotherMethod() {}
}
]]
      local buf = helpers.create_buffer_with_content(content)
      local refs = server.get_decorator_refs(buf, 'regularMethod')
      vim.api.nvim_buf_delete(buf, { force = true })
      assert.equals(0, refs)
    end)

    it('should handle multiple decorators on different methods', function()
      local content = [[
export class TestComponent {
  @HostListener('click')
  onClick() {}

  @HostListener('keydown')
  onKeydown() {}

  @HostBinding('class.active')
  isActive = false;
}
]]
      local buf = helpers.create_buffer_with_content(content)
      local onClick = server.get_decorator_refs(buf, 'onClick')
      local onKeydown = server.get_decorator_refs(buf, 'onKeydown')
      local isActive = server.get_decorator_refs(buf, 'isActive')
      vim.api.nvim_buf_delete(buf, { force = true })
      assert.equals(1, onClick)
      assert.equals(1, onKeydown)
      assert.equals(1, isActive)
    end)
  end)
end)
