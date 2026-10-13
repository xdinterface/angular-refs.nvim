local helpers = require('test.lsp.helpers')

local EXPECTED_PATH = vim.fn.fnamemodify(helpers.app, ':h') .. '/expected-refs.json'

describe('expected-refs.json', function()
  if not helpers.installed() then
    it('needs language servers (run `make lsp-deps`)', function()
      pending('language servers not installed')
    end)
    return
  end

  require('angular-refs').setup()
  local expected = vim.json.decode(table.concat(vim.fn.readfile(EXPECTED_PATH), '\n'))

  for file, symbols in pairs(expected) do
    it('matches the documented usage counts in ' .. file, function()
      local path = vim.fs.find(file, { path = helpers.app .. '/src', type = 'file' })[1]
      assert(path, 'fixture not found: ' .. file)
      local bufnr = helpers.open(path:sub(#helpers.app + #'/src/app/' + 1))
      local counts = helpers.counts(bufnr)

      local wrong = {}
      for name, spec in pairs(symbols) do
        if type(spec) == 'table' and spec.expected ~= nil then
          local actual = counts[name] and (counts[name].prod + counts[name].test)
          if actual ~= spec.expected then
            table.insert(wrong, string.format('%s: expected %d, got %s', name, spec.expected, tostring(actual)))
          end
        end
      end
      table.sort(wrong)
      assert(#wrong == 0, file .. '\n  ' .. table.concat(wrong, '\n  '))
    end)
  end
end)
