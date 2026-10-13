local M = {}

---@param char string
---@return boolean
local function is_space(char)
  return char == " " or char == "\t" or char == "\n" or char == "\r"
end

---Attribute section of the opening tag whose `<` is at `offset` or earlier on the same line
---@param text string
---@param offset integer 1-based byte offset
---@return string|nil
function M.opening_tag(text, offset)
  local start = offset
  while start >= 1 and text:sub(start, start) ~= "<" do
    if text:sub(start, start) == "\n" then
      return nil
    end
    start = start - 1
  end
  if start < 1 then
    return nil
  end

  local pos = start + 1
  while pos <= #text and not is_space(text:sub(pos, pos)) and not text:sub(pos, pos):match("[/>]") do
    pos = pos + 1
  end

  local attributes_start = pos
  local quote
  while pos <= #text do
    local char = text:sub(pos, pos)
    if quote then
      if char == quote then
        quote = nil
      end
    elseif char == '"' or char == "'" then
      quote = char
    elseif char == ">" then
      return text:sub(attributes_start, pos - 1)
    end
    pos = pos + 1
  end
  return text:sub(attributes_start)
end

---Attribute names in an opening tag's attribute section, values skipped quote-aware
---@param tag string|nil
---@return string[]
function M.attribute_names(tag)
  local names = {}
  if not tag then
    return names
  end

  local pos = 1
  while pos <= #tag do
    local char = tag:sub(pos, pos)
    if is_space(char) or char == "/" then
      pos = pos + 1
    else
      local name_start = pos
      while pos <= #tag and not is_space(tag:sub(pos, pos)) and not tag:sub(pos, pos):match("[=/]") do
        pos = pos + 1
      end
      table.insert(names, tag:sub(name_start, pos - 1))

      local after_name = pos
      while after_name <= #tag and is_space(tag:sub(after_name, after_name)) do
        after_name = after_name + 1
      end
      if tag:sub(after_name, after_name) == "=" then
        pos = after_name + 1
        while pos <= #tag and is_space(tag:sub(pos, pos)) do
          pos = pos + 1
        end
        local quote = tag:sub(pos, pos)
        if quote == '"' or quote == "'" then
          local closing = tag:find(quote, pos + 1, true)
          pos = closing and closing + 1 or #tag + 1
        else
          while pos <= #tag and not is_space(tag:sub(pos, pos)) do
            pos = pos + 1
          end
        end
      end
    end
  end
  return names
end

---Whether an opening tag binds an input called `name`
---@param tag string|nil
---@param name string Binding name (the alias when the input has one)
---@return boolean
function M.binds_input(tag, name)
  local forms = {
    [name] = true,
    ["[" .. name .. "]"] = true,
    ["[(" .. name .. ")]"] = true,
    ["bind-" .. name] = true,
  }
  for _, attribute in ipairs(M.attribute_names(tag)) do
    if forms[attribute] then
      return true
    end
  end
  return false
end

return M
