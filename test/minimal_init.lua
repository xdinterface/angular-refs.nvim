local plenary_path = vim.fn.stdpath('data') .. '/lazy/plenary.nvim'
if not vim.loop.fs_stat(plenary_path) then
  plenary_path = vim.fn.stdpath('data') .. '/site/pack/vendor/start/plenary.nvim'
end

if vim.loop.fs_stat(plenary_path) then
  vim.opt.rtp:prepend(plenary_path)
end

local plugin_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
vim.opt.rtp:prepend(plugin_path)

package.path = plugin_path .. '/?.lua;' .. plugin_path .. '/?/init.lua;' .. package.path

vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false

vim.g.mapleader = ' '

local function setup_lsp()
  local lspconfig_ok, lspconfig = pcall(require, 'lspconfig')
  if not lspconfig_ok then
    return
  end

  local capabilities = vim.lsp.protocol.make_client_capabilities()

  local ts_ok = pcall(function()
    lspconfig.ts_ls.setup({
      capabilities = capabilities,
      root_dir = function(fname)
        return lspconfig.util.root_pattern('tsconfig.json', 'package.json')(fname)
          or vim.fn.getcwd()
      end,
    })
  end)

  local angular_ok = pcall(function()
    lspconfig.angularls.setup({
      capabilities = capabilities,
      root_dir = function(fname)
        return lspconfig.util.root_pattern('angular.json')(fname) or vim.fn.getcwd()
      end,
    })
  end)

  return ts_ok, angular_ok
end

local M = {}

return M
