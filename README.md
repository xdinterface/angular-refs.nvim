# angular-refs.nvim

Source-based TypeScript and Angular template usage counts for Neovim.

The plugin combines references from your existing TypeScript and Angular language
servers, deduplicates source locations, and checks which declaration each reference
belongs to. It does not count occurrences in compiler-generated template code.

## Requirements

- Neovim 0.11 or 0.12.
- Angular 21 or 22, with a matching Angular language server (`angularls` or `angular`).
- A TypeScript provider: `typescript-tools`, `ts_ls` / `typescript-language-server`,
  or `vtsls`. The legacy client name `tsserver` is also recognized.
- Recommended: an installed **TypeScript Tree-sitter parser**. It supplies declaration,
  arrow-function and framework-hook evidence. The plugin does not install parsers.

There is no Node helper to install for this plugin. Your language servers retain
their usual Node/TypeScript requirements. See [Angular version compatibility](https://angular.dev/reference/versions).

## Installation

For lazy.nvim:

```lua
{
  'xdinterface/angular-refs.nvim',
  ft = 'typescript',
  opts = {},
}
```

With another package manager, load the plugin and call:

```lua
require('angular-refs').setup()
```

Automatic display is restricted to TypeScript buffers attached to Angular LSP.
Spec/test files are not annotated, but references from tests still count.

## What the counts mean

A usage is a **source occurrence**, not the number of times a function runs.
Callbacks count once per source reference; a two-way binding counts once per
referenced symbol, not once for each generated read/write check.

Counts belong to the specific member implementation. A call to `service.save()`
does not count toward a component's unrelated `save()`. References returned for
an entire interface/override family are checked against their definitions.
Unresolved dispatch is not credited as a confirmed implementation usage.

Both external and inline templates use Angular's source mappings. Aliased
inputs, signal inputs, parent bindings, control-flow expressions and host
expressions are handled through the language server, not HTML regular expressions.
Overloads and getter/setter pairs are grouped by their owning member. Different
members on one line are displayed separately with their names.

### Incomplete results and unused detection

| Display | Meaning |
| --- | --- |
| `3 usages (incomplete)` | Three confirmed source occurrences; additional usages cannot be ruled out. |
| `unknown` | No confirmed references, but insufficient evidence to claim the symbol is unused. |
| `unused` | Reserved for a complete, eligible zero-reference analysis. |

**Current limitation:** standard reference APIs do not establish whole-workspace
project coverage. This version therefore marks results incomplete and does **not**
emit `unused` for ordinary zero-reference results. A successful empty LSP response
is not a dead-code proof. No option silently opts out of this safety rule.

Dynamic property access, external consumers, unsupported syntax, missing servers
and ambiguous ownership can all leave gaps. Tree-sitter helps classify declarations
and framework entry points; it does not provide a whole-program reachability proof.
Cross-file inheritance and custom framework registration remain conservative gaps.

Recognized Angular lifecycle hooks have no numeric label and never enter unused
results. Recognition uses Angular imports/decorators and resolvable same-file
inheritance, not method names alone. Without sufficient syntax evidence, the plugin
withholds that classification. Explicit references remain available through normal
LSP navigation.

Host listeners, inputs/outputs, signal factories, queries, pipe transforms and
recognized value-accessor callbacks carry framework-use evidence. The plugin does
not invent numeric usages for framework invocation or population.

## Configuration

```lua
require('angular-refs').setup({
  enabled = true,
  analysis = {
    timeout_ms = 10000,          -- Whole refresh, including symbol discovery
    max_concurrent_requests = 4, -- Per provider within a refresh
  },
  display = {
    position = 'eol',           -- 'eol' or 'above'
    separator = ' | ',
    format = '%d usages',
    format_singular = '%d usage',
    format_zero = 'unused',
    format_unknown = 'unknown',
    format_incomplete = '%d usages (incomplete)',
    highlight = 'Comment',
    zero_refs_highlight = 'Comment',
  },
  trigger = {
    on_open = true,
    on_save = true,
    debounce_ms = 500,
  },
  exclude = {
    respect_gitignore = true,
    patterns = { 'node_modules', '/dist/', '%.angular', '/build/', '/coverage/', '/__pycache__/' },
  },
})
```

`comprehensive_mode` is accepted as a deprecated no-op for compatibility. Both
TypeScript and parent-template references now go through the same pipeline.
The `debug` option remains accepted for compatibility; detailed result reasons
are available through status and the analysis report.

## Commands

| Command | Purpose |
| --- | --- |
| `:AngularRefsRefresh` | Invalidate existing analysis and request fresh results. |
| `:AngularRefsStatus` | Show provider initialization, reported versions, scope and incomplete reasons. |
| `:AngularRefsUnused` | List verified unused symbols only; explain when analysis is incomplete. |
| `:AngularRefsToggle` | Enable/disable analysis, cancelling pending work when disabled. |
| `:AngularRefsDumpTcb` | Show raw compiler output at the cursor for diagnostics only. |

For inspection from Lua, `require('angular-refs.display').get_report(bufnr)` returns
the current report, including each symbol's confirmed locations and uncertainty
reasons. Stored locations use UTF-8 byte columns; requests are converted to each
server's negotiated encoding. This report is an internal diagnostic interface,
not a stable extension API.

## Refresh behavior and limitations

Each refresh owns a cancellable request group and a document/workspace revision.
Late responses cannot restore labels after disabling, invalidation or buffer
removal. Refreshes requested while busy are queued. Timeouts retain confirmed
partial results, marked incomplete.

Automatic triggers reuse unchanged results for up to the configured timeout
interval; explicit refresh and invalidation bypass that short-lived cache.

Edits and saves in TypeScript/HTML invalidate observed buffers, including callers
and test files. HTML does not need its own LSP attachment. Relevant configuration
and Git-ignore saves also invalidate results. Loaded unsaved text takes precedence
over disk when interpreting locations. Git exclusions are checked asynchronously
in batches using the file's repository root.

Invalidation currently covers all observed buffers conservatively rather than
maintaining a dependency graph. External changes are picked up on Neovim's
file-change events, focus regain or manual refresh; there is no recursive
filesystem watcher. Language servers remain responsible for indexing source files.

## Development and validation

`make test` runs the focused Plenary tests. Set `PLENARY_PATH` if Plenary is not
already installed at a supported runtime path. Set `AR_TS_PARSER` to a compiled
TypeScript grammar to include parser-backed unit tests.

Real-server fixtures and a matrix runner live in [test/live](test/live/README.md).
They test exact source locations as well as counts. The old regex-count tests and
unused expected-count JSON were removed with the old counting backend; the older
Angular fixture source remains as historical material.

Local validation covered Angular **21.2.23 / TypeScript 5.9.3** and Angular
**22.1.6 / TypeScript 6.0.3**, with Neovim **0.11.5 and 0.12.4**, across
`typescript-tools.nvim`, `typescript-language-server` and `vtsls`.
The support target is the latest stable patch of the two supported release lines;
the versions above identify the actual local test runs, not untested patches.

## Nix rollout

Commit and publish the verified plugin revision, update the plugin input in your
Nix configuration, then rebuild and restart Neovim. Remove a temporary
`client.request` substitution patch only after the input points to this updated
source. Runtime requests use the colon-method API; no `/nix/store` files need editing.
