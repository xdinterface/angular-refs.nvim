local M = {}

local config = require("angular-refs.config")

---@param bufnr integer
---@param client_id integer
---@return boolean
local function is_plugin_client(bufnr, client_id)
  local clients = require("angular-refs.clients")
  for _, client in ipairs({ clients.angular(bufnr), clients.typescript(bufnr) }) do
    if client and client.id == client_id then
      return true
    end
  end
  return false
end

---@param bufnr integer
local function show_unused(bufnr)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local unused = require("angular-refs.display").unused(bufnr)
  if #unused == 0 then
    vim.notify("angular-refs: No unused symbols found", vim.log.levels.INFO)
    return
  end

  local items = {}
  for _, item in ipairs(unused) do
    local marker = item.tests_only and " [tests only]" or ""
    table.insert(items, {
      filename = filename,
      lnum = item.line,
      text = string.format("[%s] %s%s", item.kind, item.name, marker),
    })
  end
  vim.fn.setqflist(items)
  vim.cmd("copen")
end

---@param opts AngularRefsConfig|table|nil
function M.setup(opts)
  config.setup(opts)

  local display = require("angular-refs.display")
  local refresh = require("angular-refs.refresh")
  local clients = require("angular-refs.clients")

  display.setup_highlights()
  clients.install_handlers(function()
    refresh.refresh_visible()
  end)
  refresh.set_enabled(config.get().enabled)

  local group = vim.api.nvim_create_augroup("AngularRefs", { clear = true })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = display.setup_highlights,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    pattern = "*.ts",
    callback = function(args)
      if not refresh.is_fresh(args.buf) then
        refresh.schedule(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(args)
      if is_plugin_client(args.buf, args.data.client_id) then
        refresh.schedule(args.buf)
      end
    end,
  })

  -- Any edit or save can change counts shown in other buffers, e.g. a template using a member
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost" }, {
    group = group,
    pattern = { "*.ts", "*.html" },
    callback = function()
      refresh.bump_generation()
      refresh.schedule_visible()
    end,
  })

  vim.api.nvim_create_autocmd("FileChangedShellPost", {
    group = group,
    callback = function()
      refresh.bump_generation()
      refresh.schedule_visible()
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(args)
      refresh.detach(args.buf)
    end,
  })

  vim.api.nvim_create_user_command("AngularRefsRefresh", function()
    refresh.bump_generation()
    refresh.run(vim.api.nvim_get_current_buf())
  end, { desc = "Refresh Angular usage counts" })

  vim.api.nvim_create_user_command("AngularRefsToggle", function()
    refresh.set_enabled(not refresh.enabled())
  end, { desc = "Toggle Angular usage counts" })

  vim.api.nvim_create_user_command("AngularRefsUnused", function()
    show_unused(vim.api.nvim_get_current_buf())
  end, { desc = "List unused and tests-only symbols in quickfix" })
end

M.config = config.get

return M
