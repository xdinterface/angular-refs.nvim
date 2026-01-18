# angular-refs.nvim

Display Angular template reference counts alongside TypeScript references in Neovim.

## Features

- Shows combined reference counts from TypeScript and Angular templates as virtual text
- Uses Angular Language Service's TCB (Type-Check Block) for accurate template analysis
- Highlights symbols with zero references to identify unused code
- Configurable display format and position

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
- Angular Language Server (`angularls`)
- A TypeScript LSP (ts_ls, typescript-tools, or vtsls)

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
  display = {
    position = "eol",                  -- "eol" or "above"
    separator = " ",                   -- Separator before text (e.g., " - ", " · ")
    format = "%d usages",              -- Format for 2+ references
    format_singular = "%d usage",      -- Format for 1 reference
    format_zero = "unused",            -- Format for zero references
    highlight = "Comment",             -- Highlight group for normal usages
    zero_refs_highlight = "Comment",         -- Highlight for zero usages
  },
  trigger = {
    on_open = true,     -- Update on BufEnter
    on_save = true,     -- Update on BufWritePost
    debounce_ms = 500,  -- Debounce time
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
| `:AngularRefsUnused` | List all unused symbols in quickfix |
| `:AngularRefsStatus` | Show Angular LSP status |
| `:AngularRefsDumpTcb` | Dump raw TCB content (for debugging) |

## How It Works

1. Uses LSP `textDocument/documentSymbol` to find all symbols in TypeScript files
2. Queries your TypeScript LSP for standard `textDocument/references`
3. Queries Angular Language Server using `angular/getTcb` to analyze template references
4. Displays combined counts as virtual text

## What's Tracked

**Included:**
- Class methods and properties (including lifecycle hooks)
- Exported functions (utility files)
- Exported constants
- Enums

**Excluded:**
- Constructors
- Private members (prefixed with `_`)
- Local variables inside methods
- Interfaces (type-only, no runtime impact)

**Note:** Lifecycle hooks (`ngOnInit`, etc.) may show high reference counts due to TypeScript LSP counting all interface implementations as references. This is a [known LSP limitation](https://github.com/microsoft/TypeScript/issues/61484).

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

## License

MIT
