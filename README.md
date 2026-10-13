# angular-refs.nvim

Usage counts for Angular projects in Neovim. Every function, property and variable in a
component, service or other TypeScript file shows how often it is used, including usages
in templates that a TypeScript language server cannot see. Code that nothing uses is
labelled `unused`, so it is easy to spot.

```typescript
export class UserListComponent implements OnInit {
  @Input() users: User[] = [];     | 3 usages
  @Output() selected = new EventEmitter<User>();     | 1 usage

  ngOnInit() {}     | lifecycle
  @HostListener('window:resize')
  onResize() {}     | host listener
  formatName(user: User) {}     | tests only
  oldHelper() {}     | unused
}
```

## How it works

The counts come from the Angular language server. For a symbol in a `.ts` file it reports
usages in TypeScript and in every template that touches the symbol: the component's own
template, inline templates, parent components that bind an input or listen to an output,
control flow blocks such as `@if`, `@for` and `@defer`, `@let`, pipes and host metadata.

The plugin adds three things the language server does not do on its own.

1. Lifecycle hooks and other interface members are counted per class. TypeScript treats
   every `ngOnInit` in the project as a usage of every other one. The plugin checks each
   usage with go-to-definition and keeps only those that belong to the class you are
   looking at, so `super.ngOnInit()` in a subclass counts and another component's
   `ngOnInit` does not.
2. Parent bindings of `@Input({ transform })` inputs are found. The language server
   misses them, so the plugin reads the opening tag of the elements it reports and
   matches the binding name exactly (`[x]`, `x="..."`, `x`, `bind-x`, `[(x)]` and
   aliases).
3. Only usages in your own source code are counted. Dependencies, build output and
   declaration files are ignored (see [Scope](#scope)).

Labels are only drawn when every request for a buffer succeeded. While the project is
loading, or when a server returns an error, the previous labels stay in place. The plugin
does not scan your project or start processes of its own.

## Labels

| Label | Meaning | Highlight group |
|---|---|---|
| `3 usages`, `1 usage` | Used in production code. The number includes usages in tests. | `AngularRefsCount` |
| `lifecycle` | Angular lifecycle hook that only Angular calls. | `AngularRefsFramework` |
| `host listener`, `host binding` | `@HostListener` or `@HostBinding` member that nothing else uses. | `AngularRefsFramework` |
| `implements` | Required by an interface or base class and only used through it. | `AngularRefsFramework` |
| `tests only` | Only test files use it. | `AngularRefsTestsOnly` |
| `unused` | Nothing uses it. | `AngularRefsUnused` |

Class and interface members get a label, as do top-level functions, constants, variables
and enums. All highlight groups link to `Comment`. To make unused code stand out:

```lua
vim.api.nvim_set_hl(0, "AngularRefsUnused", { link = "DiagnosticWarn" })
```

## Requirements

- Neovim 0.10 or later.
- The Angular language server (`angularls`) attached to `typescript` buffers. This is
  the nvim-lspconfig default. Attaching it to `htmlangular` buffers as well means
  unsaved template changes are counted too.
- A TypeScript language server: `typescript-tools`, `ts_ls`, `vtsls`,
  `typescript-language-server` or `tsserver`.
- Angular 20 or later. On Angular 20, set `"typeCheckHostBindings": true` in
  `angularCompilerOptions` so that usages in `host: {}` metadata are reported. Angular 21
  does this by default.

Without the Angular language server the plugin shows nothing, because counts from
TypeScript alone would call template-only code unused.

## Installation

### lazy.nvim and LazyVim

```lua
{
  "xdinterface/angular-refs.nvim",
  ft = "typescript",
  opts = {},
}
```

In LazyVim, save this as `lua/plugins/angular-refs.lua`. The `lang.angular` extra already
sets up both language servers the plugin needs.

### vim.pack (Neovim 0.12)

```lua
vim.pack.add({ "https://github.com/xdinterface/angular-refs.nvim" })
require("angular-refs").setup()
```

### Nix

Until the plugin is in nixpkgs, add it as a flake input and build it with
`buildVimPlugin`:

```nix
# flake.nix
inputs.angular-refs-nvim = {
  url = "github:xdinterface/angular-refs.nvim";
  flake = false;
};

# your Neovim plugin list
(pkgs.vimUtils.buildVimPlugin {
  pname = "angular-refs.nvim";
  version = "unstable";
  src = inputs.angular-refs-nvim;
})
```

Then call `require("angular-refs").setup()` in your configuration.

### Other plugin managers

Any plugin manager that adds the repository to `runtimepath` works. Call
`require("angular-refs").setup()` once the plugin is loaded.

## Configuration

`setup()` takes the options below. These are the defaults:

```lua
require("angular-refs").setup({
  enabled = true,
  display = {
    position = "eol",           -- "eol" or "above"
    separator = "    | ",       -- same spacing as diagnostic virtual text
    align = false,              -- line up the labels of neighbouring lines
    format = "%d usages",
    format_singular = "%d usage",
    labels = {
      unused = "unused",
      tests_only = "tests only",
      lifecycle = "lifecycle",
      host_listener = "host listener",
      host_binding = "host binding",
      implements = "implements",
    },
  },
  trigger = { debounce_ms = 500 },
  scope = {
    exclude = {},               -- extra Lua patterns for files to ignore
    test_patterns = { "%.spec%.ts$", "%.test%.ts$", "%.cy%.ts$", "/e2e/" },
    respect_gitignore = false,
  },
  symbols = {
    ignore = { "^_" },          -- symbol names that get no label
    test_buffers = false,       -- also label symbols in test files
  },
  clients = {
    angular = { "angularls", "angular" },
    typescript = { "typescript-tools", "ts_ls", "vtsls", "typescript-language-server", "tsserver" },
  },
  debug = false,
})
```

Nested tables are merged with the defaults. Lists replace the default list. Every option
is described in `:help angular-refs-config`.

## Scope

A usage counts only when the file it is in

- lies inside the project root reported by the Angular language server,
- has no `node_modules` or `.angular` directory in its path,
- is not a `.d.ts` declaration file,
- is not inside `dist/`, `out-tsc/` or `coverage/` at the project root,
- does not match a pattern in `scope.exclude`, for example `{ "/generated/" }`.

`scope.respect_gitignore = true` also ignores files that git ignores. It is off by default
because the rules above already cover dependencies and build output, and because it is
the only option that makes the plugin run a program (`git check-ignore`).

Usages in files matching `scope.test_patterns` are counted, but a symbol that only tests
use is labelled `tests only`.

## Commands

| Command | Description |
|---|---|
| `:AngularRefsRefresh` | Count the usages in the current buffer again. |
| `:AngularRefsToggle` | Hide or show all labels. |
| `:AngularRefsUnused` | List the `unused` and `tests only` symbols of the buffer in the quickfix list. |
| `:checkhealth angular-refs` | Show the attached servers, project root, Angular version and setup hints. |

Labels refresh on their own after edits in `.ts` and `.html` files, when you enter a
buffer whose labels are out of date, and when the language servers finish loading the
project. The first labels appear once the Angular language server has loaded the project,
which takes a few seconds in a large project.

## Development

```sh
make test-unit                 # unit tests, no language servers needed
make lsp-deps ANGULAR=20       # install the fixture's Angular packages and language servers
make test-lsp                  # integration tests against the real language servers
```

`make lsp-deps` installs with `--ignore-scripts` into gitignored directories.

## License

MIT
