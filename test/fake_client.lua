local M = {}

local METHODS = { request = true, notify = true, cancel_request = true }

---Make a fake LSP client callable the way real clients of the running Neovim are.
---Fakes define their methods with `self`. Neovim 0.11+ clients are called the same way
---(`client:request(...)`), but Neovim 0.10 clients expose plain functions that are called
---without `self` (`client.request(...)`). Methods assigned later, e.g. by a single test,
---are adapted as well.
---@param client table
---@return table
function M.like_running_neovim(client)
  if vim.fn.has("nvim-0.11") == 1 then
    return client
  end
  local methods = {}
  for name in pairs(METHODS) do
    methods[name] = rawget(client, name)
    client[name] = nil
  end
  return setmetatable(client, {
    __index = function(_, key)
      local method = methods[key]
      if method then
        return function(...)
          return method(client, ...)
        end
      end
    end,
    __newindex = function(target, key, value)
      if METHODS[key] then
        methods[key] = value
      else
        rawset(target, key, value)
      end
    end,
  })
end

return M
