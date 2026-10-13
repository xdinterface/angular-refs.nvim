local M = {}

local repo = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h:h')
M.app = repo .. '/test/fixtures/angular-test-app'
M.servers = repo .. '/test/.servers/node_modules'

local TIMEOUT_MS = 180000

---@return boolean
function M.installed()
  return vim.uv.fs_stat(M.servers .. '/@angular/language-server/index.js') ~= nil
    and vim.uv.fs_stat(M.app .. '/node_modules/@angular/core/package.json') ~= nil
end

local function start_servers(bufnr)
  vim.lsp.start({
    name = 'ts_ls',
    cmd = { M.servers .. '/.bin/typescript-language-server', '--stdio' },
    root_dir = M.app,
    init_options = { tsserver = { path = M.app .. '/node_modules/typescript/lib' } },
  }, { bufnr = bufnr })
  vim.lsp.start({
    name = 'angularls',
    cmd = {
      'node',
      M.servers .. '/@angular/language-server/index.js',
      '--stdio',
      '--tsProbeLocations',
      M.app .. '/node_modules',
      '--ngProbeLocations',
      M.servers,
    },
    root_dir = M.app,
    filetypes = { 'typescript', 'htmlangular' },
  }, { bufnr = bufnr })
end

---Open a fixture file (relative to src/app) with both servers attached
---@param relative string
---@return integer bufnr
function M.open(relative)
  vim.cmd('edit ' .. vim.fn.fnameescape(M.app .. '/src/app/' .. relative))
  local bufnr = vim.api.nvim_get_current_buf()
  start_servers(bufnr)
  local clients = require('angular-refs.clients')
  assert(
    vim.wait(TIMEOUT_MS, function()
      local ng, ts = clients.angular(bufnr), clients.typescript(bufnr)
      return ng ~= nil and ts ~= nil and ng.initialized and ts.initialized and clients.project_state(ng) ~= 'loading'
    end, 50),
    'language servers did not start for ' .. relative
  )
  return bufnr
end

---Refresh a buffer through the plugin and wait for labels
---@param bufnr integer
function M.refresh(bufnr)
  local refresh = require('angular-refs.refresh')
  refresh.bump_generation()
  refresh.run(bufnr)
  assert(
    vim.wait(TIMEOUT_MS, function()
      return refresh.is_fresh(bufnr)
    end, 50),
    'labels never rendered for ' .. vim.api.nvim_buf_get_name(bufnr)
  )
end

---@param bufnr integer
---@return AngularRefsSymbol[]
local function fetch_symbols(bufnr)
  local clients = require('angular-refs.clients')
  local list
  require('angular-refs.symbols').fetch(bufnr, clients.typescript(bufnr), function(result)
    list = result or {}
  end)
  assert(vim.wait(TIMEOUT_MS, function()
    return list ~= nil
  end, 20))
  return list
end

---@param symbol AngularRefsSymbol
---@return string
local function symbol_id(symbol)
  return symbol.container and (symbol.container .. '.' .. symbol.name) or symbol.name
end

---Rendered label text per symbol id ("Class.member" or top-level name)
---@param bufnr integer
---@return table<string, string>
function M.labels(bufnr)
  local ns = vim.api.nvim_create_namespace('angular-refs')
  local separator = vim.trim(require('angular-refs.config').get().display.separator)
  local by_line = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })) do
    local text = vim.trim(mark[4].virt_text[1][1])
    by_line[mark[2]] = vim.trim(text:sub(#separator + 1))
  end
  local labels = {}
  for _, symbol in ipairs(fetch_symbols(bufnr)) do
    labels[symbol_id(symbol)] = by_line[symbol.line]
  end
  return labels
end

---Raw usage counts per symbol name, straight from references.collect
---@param bufnr integer
---@return table<string, AngularRefsCounts>
function M.counts(bufnr)
  local clients = require('angular-refs.clients')
  local ng, ts = clients.angular(bufnr), clients.typescript(bufnr)
  local list = fetch_symbols(bufnr)
  local results
  require('angular-refs.references').collect({
    bufnr = bufnr,
    uri = vim.uri_from_bufnr(bufnr),
    path = vim.api.nvim_buf_get_name(bufnr),
    root = clients.root(ng),
    ng = ng,
    ts = ts,
    batch = clients.new_batch(16),
  }, list, function(r)
    results = r or false
  end)
  assert(vim.wait(TIMEOUT_MS, function()
    return results ~= nil
  end, 20))
  assert(results, 'references.collect failed')
  local counts = {}
  for index, symbol in ipairs(list) do
    counts[symbol.name] = counts[symbol.name] or results[index]
  end
  return counts
end

return M
