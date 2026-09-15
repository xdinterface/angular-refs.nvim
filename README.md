# angular-refs.nvim

Display Angular template reference counts alongside TypeScript references in Neovim.

## Features

- Shows combined reference counts from TypeScript and Angular templates as virtual text
- Uses Angular Language Service's TCB (Type-Check Block) for accurate template analysis
- Highlights symbols with zero references to identify unused code
- Configurable display format and position
- Optional comprehensive mode for parent component usage tracking

> **Note:** This plugin only activates for Angular projects (detected via Angular LSP attachment).
> Non-Angular TypeScript files are unaffected.

## Example

```typescript
export class MyComponent {
  userName: string;          // 3 usages

  getData() {                // 5 usages
    // ...
  }

  unusedMethod() {           // unused
    // ...
  }
}
```

## Requirements

- Neovim 0.9+
- Angular Language Server (`angularls` or `angular`)
- A TypeScript LSP (see [Supported LSP Clients](#supported-lsp-clients))

## Installation

### lazy.nvim

```lua
{
  "xdinterface/angular-refs.nvim",
  ft = { "typescript" },
  opts = {},
}
```

### packer.nvim

```lua
use {
  "xdinterface/angular-refs.nvim",
  ft = { "typescript" },
  config = function()
    require("angular-refs").setup()
  end,
}
```

### vim-plug

```vim
Plug 'xdinterface/angular-refs.nvim'
```

Then in your config:
```lua
require("angular-refs").setup()
```

### Nix Flakes

```nix
{
  inputs.angular-refs-nvim.url = "github:xdinterface/angular-refs.nvim";
}
```

Add to your Neovim plugins:
```nix
inputs.angular-refs-nvim.packages.${system}.default
```

## Configuration

```lua
require("angular-refs").setup({
  enabled = true,
  comprehensive_mode = false,  -- Enable parent component usage tracking (slower but more complete)
  display = {
    position = "eol",                  -- "eol" or "above"
    separator = " | ",                 -- Separator before text (e.g., " | ", " - ", " · ")
    format = "%d usages",              -- Format for 2+ references
    format_singular = "%d usage",      -- Format for 1 reference
    format_zero = "unused",            -- Format for zero references
    highlight = "Comment",             -- Highlight group for normal usages
    zero_refs_highlight = "Comment",   -- Highlight for zero usages
  },
  trigger = {
    on_open = true,     -- Update on BufEnter
    on_save = true,     -- Update on BufWritePost
    debounce_ms = 500,  -- Debounce time
  },
  exclude = {
    patterns = {                -- Lua patterns to exclude from counts
      "node_modules",
      "/dist/",
      "%.angular",
      "/build/",
      "/coverage/",
      "/__pycache__/",
    },
    respect_gitignore = true,   -- Also exclude gitignored files
  },
  debug = false,
})
```

## Navigation

This plugin is **informational only** - it displays usage counts but doesn't override navigation.

- Use your standard LSP keybindings (e.g., `gr` or `grr`) to navigate to references
- Template references are included in the count but aren't directly navigable (Angular's TCB doesn't provide exact positions)

## Commands

| Command | Description |
|---------|-------------|
| `:AngularRefsRefresh` | Manually refresh reference counts |
| `:AngularRefsToggle` | Toggle reference counts on/off |
| `:AngularRefsUnused` | List all unused symbols in quickfix |
| `:AngularRefsStatus` | Show Angular LSP status |
| `:AngularRefsDumpTcb` | Dump raw TCB content (for debugging) |

## How It Works

1. Uses LSP `textDocument/documentSymbol` to find all symbols in TypeScript files
2. Queries your TypeScript LSP for standard `textDocument/references`
3. Queries Angular Language Server using `angular/getTcb` to analyze template references
4. Parses Angular templates for additional references in control flow blocks
5. Displays combined counts as virtual text

When `comprehensive_mode` is enabled, the plugin also:
- Searches parent component templates for usages of inputs/outputs
- Tracks component selector usage across the project
- Detects two-way binding (`[(prop)]`) and correctly counts both input and output

Template caches are automatically invalidated when HTML files are saved.

## What's Tracked

### Signal-based APIs (Angular 16+)

- `signal()` - Basic signals
- `input()` / `input.required()` - Signal inputs
- `output()` - Signal outputs
- `model()` - Two-way binding model (generates input + `Change` output)
- `computed()` - Computed signals
- `linkedSignal()` - Linked signals (Angular 19+)
- `resource()` / `rxResource()` - Async resources (Angular 19+)
- `viewChild()` / `viewChildren()` - View queries
- `contentChild()` / `contentChildren()` - Content queries

### Decorator-based APIs

- `@Input()` / `@Output()` with alias support
- `@ViewChild()` / `@ViewChildren()`
- `@ContentChild()` / `@ContentChildren()`
- `@HostBinding()` / `@HostListener()`
- `host: {}` block in `@Component`

### Other

- Class methods and properties
- Getters and setters
- Exported functions and constants

### Excluded

- Constructors
- Private members (prefixed with `_` or using `private` keyword)
- Local variables inside methods
- Interfaces (type-only, no runtime impact)

**Note:** Lifecycle hooks (`ngOnInit`, etc.) use local-only reference counting due to a [known LSP limitation](https://github.com/microsoft/TypeScript/issues/61484) where TypeScript counts all interface implementations project-wide. Only references within the same file are counted.

## Filtering

By default, references from these locations are excluded from counts:
- `node_modules/`
- `dist/`, `build/`, `.angular/`
- `coverage/`, `__pycache__/`
- Any files matching your `.gitignore`

### Custom Exclusions

```lua
require("angular-refs").setup({
  exclude = {
    patterns = { "node_modules", "vendor/", "my%-folder" },  -- Lua patterns
    respect_gitignore = true,  -- Default: true
  },
})
```

To show all references (including gitignored files):

```lua
require("angular-refs").setup({
  exclude = {
    respect_gitignore = false,
  },
})
```

## Template Syntax Support

### Modern Control Flow (Angular 17+)

- `@if` / `@else if` / `@else` - Conditional blocks
- `@for` - For loops with `track` expressions
- `@switch` / `@case` / `@default` - Switch statements
- `@let` - Local template variables
- `@defer` - Deferred loading blocks

### Legacy Directives

- `*ngIf` - Structural if directive
- `*ngFor` - Structural for directive with `trackBy` support
- `[ngSwitch]` / `*ngSwitchCase` - Switch directive

### Bindings

- Interpolations: `{{ property }}`
- Property bindings: `[property]="expression"`
- Event bindings: `(event)="handler()"`
- Two-way bindings: `[(ngModel)]="property"`
- Pipe expressions: `{{ value | pipeName }}`
- Async pipe: `{{ observable$ | async }}`

## Supported LSP Clients

### Angular

- `angularls` (mason, lspconfig)
- `angular` (alternative name)

### TypeScript

- `typescript-tools` (recommended)
- `ts_ls` (nvim-lspconfig)
- `vtsls`
- `typescript-language-server`
- `tsserver`

## Troubleshooting

### References not showing

1. Check TypeScript LSP is attached: `:LspInfo`
2. Check Angular LSP is attached: `:AngularRefsStatus`
3. Enable debug mode: `require("angular-refs").setup({ debug = true })`

### Template references show 0

The `angular/getTcb` request requires Angular LSP to be initialized:
- Ensure your project has a valid `angular.json`
- Angular LSP may need a moment to index on first open
- Try `:AngularRefsDumpTcb` to verify TCB content is returned

### Parent usages not counted

Enable comprehensive mode in your config:
```lua
require("angular-refs").setup({
  comprehensive_mode = true,
})
```

Note: This mode performs project-wide searches and may be slower on large codebases.

## Development

The implementation is organized by responsibility:

- `clients.lua`: shared LSP client selection and Angular attachment checks.
- `lsp.lua`: document symbols and TypeScript reference requests.
- `parser.lua`: TCB, template, component metadata, and host-expression text parsing.
- `server.lua`: file access, caches, parent-template searches, and Angular analysis orchestration.
- `display.lua`: refresh scheduling, result aggregation, and virtual text.
- `init.lua`: configuration wiring, commands, and editor events.

Default-mode refreshes analyze the template once and share its counts across symbols.
Lifecycle hooks retain same-file TypeScript counting and skip template counts.
Comprehensive mode retains its separate template/parent counting behavior.

Run the tests with Neovim and an installed `plenary.nvim`:

```sh
nvim --headless -u test/minimal_init.lua -i NONE -c "lua require('plenary.test_harness').test_directory('test/plenary/', {minimal_init = 'test/minimal_init.lua', sequential = true})"
```

The suite covers parsers, fixture searches, and refresh/LSP coordination using mocked
clients. It does not establish reference-count accuracy against running language servers.

## License

MIT
