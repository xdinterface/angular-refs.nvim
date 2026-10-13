local fake = require('test.fake_client')
local symbols = require('angular-refs.symbols')
local config = require('angular-refs.config')

local SK = vim.lsp.protocol.SymbolKind

local function range(start_line, start_char, end_line, end_char)
  return {
    start = { line = start_line, character = start_char },
    ['end'] = { line = end_line or start_line, character = end_char or start_char + 1 },
  }
end

---DocumentSymbol whose range starts at `start` and whose name is found in `lines`
local function node(lines, name, kind, start_line, start_char, children, name_line)
  name_line = name_line or start_line
  local name_char = lines[name_line + 1]:find(name, 1, true) - 1
  return {
    name = name,
    kind = kind,
    range = range(start_line, start_char, name_line, name_char + #name),
    selectionRange = range(name_line, name_char, name_line, name_char + #name),
    children = children,
  }
end

local function by_name(list)
  local map = {}
  for _, symbol in ipairs(list) do
    map[symbol.name] = symbol
  end
  return map
end

describe('angular-refs.symbols', function()
  before_each(function()
    config.setup()
  end)

  describe('extract', function()
    it('keeps top-level functions, constants, variables and enums only', function()
      local lines = { 'export function fn() {}', 'export const C = 1;', 'export enum E {}', 'let v = 1;', 'class K {}' }
      local result = {
        node(lines, 'fn', SK.Function, 0, 0),
        node(lines, 'C', SK.Constant, 1, 0),
        node(lines, 'E', SK.Enum, 2, 0),
        node(lines, 'v', SK.Variable, 3, 0),
        node(lines, 'K', SK.Class, 4, 0, {}),
      }
      local names = vim.tbl_keys(by_name(symbols.extract(result, lines)))
      table.sort(names)
      assert.same({ 'C', 'E', 'fn', 'v' }, names)
    end)

    it('keeps class and interface members but not constructors', function()
      local lines = {
        'export class Comp {',
        '  constructor() {}',
        '  prop = 1;',
        '  method() {}',
        '}',
        'interface Shape {',
        '  area: number;',
        '}',
      }
      local result = {
        node(lines, 'Comp', SK.Class, 0, 0, {
          node(lines, 'constructor', SK.Constructor, 1, 2),
          node(lines, 'prop', SK.Property, 2, 2),
          node(lines, 'method', SK.Method, 3, 2),
        }),
        node(lines, 'Shape', SK.Interface, 5, 0, { node(lines, 'area', SK.Field, 6, 2) }),
      }
      local found = by_name(symbols.extract(result, lines))
      assert.is_nil(found.constructor)
      assert.equals('Comp', found.prop.container)
      assert.same({ line = 0, character = 13 }, found.prop.container_pos)
      assert.equals('Method', found.method.kind)
      assert.equals('Shape', found.area.container)
    end)

    it('positions symbols at the name, not at the decorator', function()
      local lines = { 'export class Comp {', '  @Output() legacyOut = new EventEmitter();', '}' }
      local result = { node(lines, 'Comp', SK.Class, 0, 0, { node(lines, 'legacyOut', SK.Property, 1, 2) }) }
      local found = by_name(symbols.extract(result, lines))
      assert.equals(1, found.legacyOut.line)
      assert.equals(12, found.legacyOut.col)
      assert.same({ line = 1, character = 2 }, found.legacyOut.decl_start)
    end)

    it('skips names matching symbols.ignore', function()
      local lines = { 'export class Comp {', '  _secret = 1;', '  shown = 2;', '}' }
      local result = {
        node(lines, 'Comp', SK.Class, 0, 0, {
          node(lines, '_secret', SK.Property, 1, 2),
          node(lines, 'shown', SK.Property, 2, 2),
        }),
      }
      local found = by_name(symbols.extract(result, lines))
      assert.is_nil(found._secret)
      assert.is_not_nil(found.shown)
    end)

    it('detects host decorators on the same and the previous line', function()
      local lines = {
        'export class Comp {',
        "  @HostListener('window:resize', ['$event'])",
        '  onResize() {}',
        "  @HostBinding('class.active') active = true;",
        '  plain() {}',
        '}',
      }
      local result = {
        node(lines, 'Comp', SK.Class, 0, 0, {
          node(lines, 'onResize', SK.Method, 1, 2, nil, 2),
          node(lines, 'active', SK.Property, 3, 2),
          node(lines, 'plain', SK.Method, 4, 2),
        }),
      }
      local found = by_name(symbols.extract(result, lines))
      assert.is_true(found.onResize.decorators.host_listener)
      assert.equals(2, found.onResize.line)
      assert.is_true(found.active.decorators.host_binding)
      assert.is_false(found.plain.decorators.host_listener)
      assert.is_false(found.plain.decorators.host_binding)
    end)

    it('detects decorator inputs with transform and their alias', function()
      local lines = {
        'export class Comp {',
        '  @Input({ transform: booleanAttribute }) disabled = false;',
        "  @Input({ alias: 'ext', transform: numberAttribute }) size = 0;",
        "  @Input('named') plainAlias = '';",
        '}',
      }
      local result = {
        node(lines, 'Comp', SK.Class, 0, 0, {
          node(lines, 'disabled', SK.Property, 1, 2),
          node(lines, 'size', SK.Property, 2, 2),
          node(lines, 'plainAlias', SK.Property, 3, 2),
        }),
      }
      local found = by_name(symbols.extract(result, lines))
      assert.is_true(found.disabled.decorators.input_transform)
      assert.is_nil(found.disabled.decorators.input_alias)
      assert.is_true(found.size.decorators.input_transform)
      assert.equals('ext', found.size.decorators.input_alias)
      assert.is_false(found.plainAlias.decorators.input_transform)
      assert.equals('named', found.plainAlias.decorators.input_alias)
    end)

    it('detects heritage clauses on classes', function()
      local lines = {
        'export class A implements OnInit {',
        '  a() {}',
        '}',
        'export class B',
        '  extends A {',
        '  b() {}',
        '}',
        'export class C {',
        '  c() {}',
        '}',
      }
      local result = {
        node(lines, 'A', SK.Class, 0, 0, { node(lines, 'a', SK.Method, 1, 2) }),
        node(lines, 'B', SK.Class, 3, 0, { node(lines, 'b', SK.Method, 5, 2) }),
        node(lines, 'C', SK.Class, 7, 0, { node(lines, 'c', SK.Method, 8, 2) }),
      }
      local found = by_name(symbols.extract(result, lines))
      assert.is_true(found.a.container_related)
      assert.is_true(found.b.container_related)
      assert.is_false(found.c.container_related)
    end)

    it('treats interface members as related (implementations share their references)', function()
      local lines = { 'export interface Greeter {', '  greet(): string;', '}' }
      local result = { node(lines, 'Greeter', SK.Interface, 0, 0, { node(lines, 'greet', SK.Method, 1, 2) }) }
      assert.is_true(symbols.extract(result, lines)[1].container_related)
    end)

    it('returns an empty list for an empty result', function()
      assert.same({}, symbols.extract({}, {}))
    end)
  end)

  describe('fetch', function()
    local function fake_ts(err, result)
      local client = { offset_encoding = 'utf-16' }
      function client:request(method, _, handler)
        assert.equals('textDocument/documentSymbol', method)
        handler(err, result)
        return true, 1
      end
      return fake.like_running_neovim(client)
    end

    it('returns extracted symbols from the client response', function()
      local buf = vim.api.nvim_create_buf(false, true)
      local lines = { 'export function fn() {}' }
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      local received
      symbols.fetch(buf, fake_ts(nil, { node(lines, 'fn', SK.Function, 0, 0) }), function(list)
        received = list
      end)
      assert.equals('fn', received[1].name)
    end)

    it('returns nil on error or missing result', function()
      local buf = vim.api.nvim_create_buf(false, true)
      local received = 'unset'
      symbols.fetch(buf, fake_ts({ message = 'boom' }, nil), function(list)
        received = list
      end)
      assert.is_nil(received)
      received = 'unset'
      symbols.fetch(buf, fake_ts(nil, nil), function(list)
        received = list
      end)
      assert.is_nil(received)
    end)
  end)
end)
