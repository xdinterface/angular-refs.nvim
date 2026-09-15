# Real language-server gate

These are test-only Node scripts. They are not a runtime dependency of the plugin.

From the repository root, using Node compatible with the selected Angular version:

```sh
export AR_TS_PARSER=/path/to/typescript.so
fixture_dir=$(node test/live/prepare.mjs 22)
npm install --prefix "$fixture_dir" --ignore-scripts --no-audit --no-fund
node test/live/matrix.mjs "$fixture_dir"
```

Repeat preparation with `21` to test the previous Angular line. Preparation creates
a new temporary directory; no installed project dependencies are changed.
Direct dependency versions are pinned in `prepare.mjs`. npm writes a lockfile in
each generated fixture, which should be retained with CI artifacts for reproduction.

The default runner checks `ts_ls` and `vtsls`. Additional environment variables:

- `AR_NVIM_BINARIES`: comma-separated Neovim binaries (default `nvim`).
- `AR_TS_TOOLS`: path to a `typescript-tools.nvim` checkout; enables that provider too.
- `AR_TS_PARSER`: path to a compiled TypeScript Tree-sitter grammar; enables framework and arrow-function assertions.
- `PLENARY_PATH`: path to a Plenary checkout for unit tests and typescript-tools.
- `AR_DEBUG_SYMBOL`: print raw reference/definition responses for one symbol.

The full gate requires `AR_TS_PARSER`: arrow initializer ownership cannot always be
verified through standard definition ranges alone. A separate unit test verifies
safe degradation when the parser is absent.

The runner copies the checked-in fixture inputs into the prepared directories,
then runs the actual plugin discovery and analysis pipeline with real servers.
Expected source occurrences are hand-selected in `run.lua`, not recorded snapshots.
It exits nonzero on missing symbols, incorrect counts/locations or timeouts.

Covered cases include inline/external templates, parent aliases, signals/models,
two-way binding deduplication, control flow, shadowed locals, literal strings,
interface-family ownership, same-line calls, overloads, accessor pairs, private and
protected methods, arrow properties, hooks, host listeners, pipes and value accessors.

The older fixture under `test/fixtures/angular-test-app` is historical material;
its former parser-based tests were not live language-server tests.
