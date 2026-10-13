local tags = require('angular-refs.tags')

local function names_of(html, offset)
  return tags.attribute_names(tags.opening_tag(html, offset or 1))
end

describe('angular-refs.tags', function()
  describe('opening_tag', function()
    it('returns nil when there is no tag', function()
      assert.is_nil(tags.opening_tag('plain text', 1))
    end)

    it('starts from the < at the offset or earlier on the line', function()
      local html = '<p>x</p><app-x [a]="1"></app-x>'
      local at_name = html:find('app-x', 1, true)
      assert.same({ '[a]' }, names_of(html, at_name))
    end)

    it('does not jump to a tag on a previous line', function()
      local html = '<app-x [a]="1">\nplain text'
      assert.is_nil(tags.opening_tag(html, html:find('plain', 1, true)))
    end)

    it('ignores > inside double and single quoted values', function()
      assert.same({ '[disabled]', 'title' }, names_of([[<app-x [disabled]="a > b" title='c > d'>]]))
    end)

    it('handles multi-line and self-closing tags', function()
      local html = '<app-x\n  [disabled]="true"\n  (changed)="on($event)"\n/>\n<div [other]="1"></div>'
      assert.same({ '[disabled]', '(changed)' }, names_of(html))
    end)

    it('returns the rest of the text for an unterminated tag', function()
      assert.same({ '[a]', 'b' }, names_of('<app-x [a]="1" b'))
    end)
  end)

  describe('binds_input', function()
    local function binds(html, name)
      return tags.binds_input(tags.opening_tag(html, 1), name)
    end

    it('matches every Angular input binding form', function()
      assert.is_true(binds('<app-x [disabled]="x">', 'disabled'))
      assert.is_true(binds('<app-x disabled="true">', 'disabled'))
      assert.is_true(binds('<app-x disabled>', 'disabled'))
      assert.is_true(binds('<app-x disabled/>', 'disabled'))
      assert.is_true(binds('<app-x bind-disabled="x">', 'disabled'))
      assert.is_true(binds('<app-x [(disabled)]="x">', 'disabled'))
      assert.is_true(binds('<app-x disabled="{{ x }}">', 'disabled'))
    end)

    it('does not match look-alike attributes', function()
      assert.is_false(binds('<app-x [attr.disabled]="x">', 'disabled'))
      assert.is_false(binds('<app-x [class.disabled]="x">', 'disabled'))
      assert.is_false(binds('<app-x [style.disabled]="x">', 'disabled'))
      assert.is_false(binds('<app-x (disabled)="x()">', 'disabled'))
      assert.is_false(binds('<app-x [disabledX]="x">', 'disabled'))
      assert.is_false(binds('<app-x data-disabled="x">', 'disabled'))
      assert.is_false(binds('<app-x title="disabled">', 'disabled'))
    end)

    it('returns false for a nil tag', function()
      assert.is_false(tags.binds_input(nil, 'disabled'))
    end)
  end)
end)
