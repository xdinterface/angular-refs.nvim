local display = require('angular-refs.display')
local config = require('angular-refs.config')

local ns = vim.api.nvim_create_namespace('angular-refs')

local function symbol(name, line, decorators)
  return {
    name = name,
    line = line,
    col = 2,
    kind = 'Method',
    decorators = vim.tbl_extend('force', { host_listener = false, host_binding = false }, decorators or {}),
  }
end

local function entry(name, line, prod, test, related)
  return { symbol = symbol(name, line), counts = { prod = prod, test = test or 0, related = related or false } }
end

local function marks(buf)
  local out = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    table.insert(out, { line = mark[2], details = mark[4] })
  end
  return out
end

describe('angular-refs.display', function()
  local buf

  before_each(function()
    config.setup()
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'a', 'b', 'c', 'd' })
  end)

  after_each(function()
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  describe('setup_highlights', function()
    it('links every group to Comment by default', function()
      display.setup_highlights()
      for _, group in ipairs({ 'AngularRefsCount', 'AngularRefsUnused', 'AngularRefsTestsOnly', 'AngularRefsFramework' }) do
        assert.equals('Comment', vim.api.nvim_get_hl(0, { name = group }).link)
      end
    end)

    it('keeps a highlight the user already defined', function()
      vim.api.nvim_set_hl(0, 'AngularRefsUnused', { fg = '#ff0000' })
      display.setup_highlights()
      local hl = vim.api.nvim_get_hl(0, { name = 'AngularRefsUnused' })
      assert.is_nil(hl.link)
      assert.equals(0xff0000, hl.fg)
      vim.api.nvim_set_hl(0, 'AngularRefsUnused', {})
    end)
  end)

  describe('render', function()
    it('renders end-of-line labels with separator and highlight group', function()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'a', 'bbbbb', 'c', 'd' })
      display.render(buf, { entry('used', 1, 2), entry('dead', 2, 0) })
      local found = marks(buf)
      assert.equals(2, #found)
      assert.same({ { '    | 2 usages', 'AngularRefsCount' } }, found[1].details.virt_text)
      assert.equals('eol', found[1].details.virt_text_pos)
      assert.same({ { '    | unused', 'AngularRefsUnused' } }, found[2].details.virt_text)
    end)

    it('renders labels above the line, indented like the line', function()
      config.setup({ display = { position = 'above' } })
      vim.api.nvim_buf_set_lines(buf, 1, 2, false, { '    b' })
      display.render(buf, { entry('used', 1, 1) })
      local details = marks(buf)[1].details
      assert.is_nil(details.virt_text)
      assert.same({ { { '    1 usage', 'AngularRefsCount' } } }, details.virt_lines)
      assert.is_true(details.virt_lines_above)
    end)

    it('renders two symbols on one line', function()
      display.render(buf, { entry('a', 3, 1), entry('b', 3, 0) })
      local found = marks(buf)
      assert.equals(2, #found)
      assert.equals(3, found[1].line)
      assert.equals(3, found[2].line)
    end)

    it('replaces previous labels on re-render', function()
      display.render(buf, { entry('a', 0, 1), entry('b', 1, 1) })
      display.render(buf, { entry('a', 0, 3) })
      local found = marks(buf)
      assert.equals(1, #found)
      assert.same({ { '    | 3 usages', 'AngularRefsCount' } }, found[1].details.virt_text)
    end)

    describe('alignment', function()
      before_each(function()
        config.setup({ display = { align = true } })
      end)

      local function label_texts()
        local by_line = {}
        for _, mark in ipairs(marks(buf)) do
          by_line[mark.line] = mark.details.virt_text[1][1]
        end
        return by_line
      end

      it('aligns a block to its longest line, across comments and blank lines', function()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
          '  a = 1',
          '  bbbbb = 2',
          '  /* note */',
          '',
          '  c(): void {',
          '    body',
          '  }',
          '  d = 4',
        })
        display.render(buf, { entry('a', 0, 1), entry('b', 1, 1), entry('c', 4, 1), entry('d', 7, 1) })
        local texts = label_texts()
        assert.equals(string.rep(' ', 6) .. '    | 1 usage', texts[0])
        assert.equals(string.rep(' ', 2) .. '    | 1 usage', texts[1])
        assert.equals('    | 1 usage', texts[4])
        assert.equals('    | 1 usage', texts[7])
      end)

      it('keeps JSDoc lines inside a block', function()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '  a = 1', '  /**', '   * doc', '   */', '  bbb = 2' })
        display.render(buf, { entry('a', 0, 1), entry('b', 4, 1) })
        assert.equals(string.rep(' ', 2) .. '    | 1 usage', label_texts()[0])
      end)

      it('starts a new block at a different indent', function()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'const a = 1', '  bbbbbbbbbbbb = 2' })
        display.render(buf, { entry('a', 0, 1), entry('b', 1, 1) })
        assert.equals('    | 1 usage', label_texts()[0])
      end)

      it('measures tabs with the buffer tabstop', function()
        vim.bo[buf].tabstop = 4
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '\ta', '\tbbb' })
        display.render(buf, { entry('a', 0, 1), entry('b', 1, 1) })
        assert.equals(string.rep(' ', 2) .. '    | 1 usage', label_texts()[0])
      end)

      it('pads only the first of two labels on one line', function()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'a', 'bbb' })
        display.render(buf, { entry('a', 0, 1), entry('b', 0, 0), entry('c', 1, 1) })
        local on_first_line = {}
        for _, mark in ipairs(marks(buf)) do
          if mark.line == 0 then
            table.insert(on_first_line, mark.details.virt_text[1][1])
          end
        end
        table.sort(on_first_line)
        assert.same({ string.rep(' ', 2) .. '    | 1 usage', '    | unused' }, on_first_line)
      end)

      it('does not pad when alignment is off', function()
        config.setup({ display = { align = false } })
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'a', 'bbbbb' })
        display.render(buf, { entry('a', 0, 1), entry('b', 1, 1) })
        assert.equals('    | 1 usage', label_texts()[0])
      end)
    end)

    it('skips symbols beyond the end of the buffer', function()
      display.render(buf, { entry('gone', 99, 1), entry('here', 0, 1) })
      assert.equals(1, #marks(buf))
    end)
  end)

  describe('unused', function()
    it('lists unused and tests-only symbols sorted by line, 1-indexed', function()
      display.render(buf, {
        entry('tests', 3, 0, 2),
        entry('used', 0, 1),
        entry('dead', 1, 0),
        entry('iface', 2, 0, 0, true),
      })
      assert.same({
        { name = 'dead', line = 2, kind = 'Method', tests_only = false },
        { name = 'tests', line = 4, kind = 'Method', tests_only = true },
      }, display.unused(buf))
    end)

    it('returns an empty list for a buffer without results', function()
      assert.same({}, display.unused(buf))
    end)
  end)

  describe('clear', function()
    it('removes labels and stored results', function()
      display.render(buf, { entry('dead', 0, 0) })
      display.clear(buf)
      assert.equals(0, #marks(buf))
      assert.same({}, display.unused(buf))
    end)

    it('clears every buffer with clear_all', function()
      local other = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(other, 0, -1, false, { 'x' })
      display.render(buf, { entry('a', 0, 1) })
      display.render(other, { entry('b', 0, 1) })
      display.clear_all()
      assert.equals(0, #marks(buf))
      assert.equals(0, #marks(other))
      vim.api.nvim_buf_delete(other, { force = true })
    end)
  end)
end)
