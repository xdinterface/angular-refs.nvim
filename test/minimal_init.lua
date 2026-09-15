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
