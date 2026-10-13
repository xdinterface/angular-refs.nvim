local repo = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':h:h:h')
dofile(repo .. '/test/minimal_init.lua')
package.path = repo .. '/?.lua;' .. package.path
