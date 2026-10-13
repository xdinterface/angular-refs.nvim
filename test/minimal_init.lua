local plenary_path = os.getenv('PLENARY_DIR') or (vim.fn.stdpath('data') .. '/lazy/plenary.nvim')
if not vim.uv.fs_stat(plenary_path) then
  plenary_path = vim.fn.stdpath('data') .. '/site/pack/vendor/start/plenary.nvim'
end
vim.opt.rtp:prepend(plenary_path)

local plugin_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h')
vim.opt.rtp:prepend(plugin_path)

vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false

-- Shared test helpers live under test/ and are required as `test.<name>`
package.path = plugin_path .. '/?.lua;' .. package.path
