local M = {}

local config = require("angular-refs.config")

local function is_spec_file(filename)
  return filename:match("%.spec%.ts$") or filename:match("%.test%.ts$")
end

---@param bufnr number
---@return boolean
local function has_angular_lsp(bufnr)
  local server = require("angular-refs.server")
  for _, name in ipairs(server.ANGULAR_CLIENT_NAMES) do
    local clients = vim.lsp.get_clients({ bufnr = bufnr, name = name })
    if #clients > 0 then
      return true
    end
  end
  return false
end

---@param opts AngularRefsConfig|nil
function M.setup(opts)
  config.setup(opts)

  local group = vim.api.nvim_create_augroup("AngularRefs", { clear = true })
  local cfg = config.get()

  if cfg.trigger.on_open then
    vim.api.nvim_create_autocmd("BufEnter", {
      group = group,
      pattern = "*.ts",
      callback = function(args)
        if not config.is_enabled() then return end
        if not has_angular_lsp(args.buf) then return end
        local filename = vim.api.nvim_buf_get_name(args.buf)
        if is_spec_file(filename) then return end
        require("angular-refs.display").schedule_update(args.buf)
      end,
    })
  end

  if cfg.trigger.on_save then
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = group,
      pattern = { "*.ts", "*.html" },
      callback = function(args)
        if not config.is_enabled() then return end
        if not has_angular_lsp(args.buf) then return end

        local filename = vim.api.nvim_buf_get_name(args.buf)

        if filename:match("%.html$") then
          local server = require("angular-refs.server")
          server.invalidate(filename)
          server.invalidate_parent_cache(filename)
          for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(buf) and has_angular_lsp(buf) then
              local bufname = vim.api.nvim_buf_get_name(buf)
              if bufname:match("%.ts$") and not is_spec_file(bufname) then
                require("angular-refs.display").schedule_update(buf)
              end
            end
          end
        else
          if not is_spec_file(filename) then
            require("angular-refs.server").invalidate(args.buf)
            require("angular-refs.display").schedule_update(args.buf)
          end
        end
      end,
    })
  end

  vim.api.nvim_create_autocmd({ "CursorHold", "InsertLeave" }, {
    group = group,
    pattern = "*.ts",
    callback = function(args)
      if not config.is_enabled() then return end
      if not has_angular_lsp(args.buf) then return end
      local filename = vim.api.nvim_buf_get_name(args.buf)
      if is_spec_file(filename) then return end
      require("angular-refs.display").schedule_update(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(args)
      if not config.is_enabled() then return end
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and vim.tbl_contains(require("angular-refs.server").ANGULAR_CLIENT_NAMES, client.name) then
        local bufname = vim.api.nvim_buf_get_name(args.buf)
        if bufname:match("%.ts$") and not is_spec_file(bufname) then
          require("angular-refs.display").schedule_update(args.buf)
        end
      end
    end,
  })

  vim.api.nvim_create_user_command("AngularRefsRefresh", function()
    local buf = vim.api.nvim_get_current_buf()
    require("angular-refs.display").update(buf)
  end, { desc = "Refresh Angular reference counts" })

  vim.api.nvim_create_user_command("AngularRefsStatus", function()
    local buf = vim.api.nvim_get_current_buf()
    if has_angular_lsp(buf) then
      vim.notify("Angular refs: Angular LSP attached to this buffer", vim.log.levels.INFO)
    else
      vim.notify("Angular refs: Angular LSP not attached to this buffer", vim.log.levels.WARN)
    end
  end, { desc = "Show Angular refs status" })

  vim.api.nvim_create_user_command("AngularRefsDumpTcb", function()
    local buf = vim.api.nvim_get_current_buf()
    require("angular-refs.server").dump_tcb(buf)
  end, { desc = "Dump raw TCB content for debugging" })

  vim.api.nvim_create_user_command("AngularRefsUnused", function()
    local buf = vim.api.nvim_get_current_buf()
    local filename = vim.api.nvim_buf_get_name(buf)
    local unused = require("angular-refs.display").get_unused(buf)

    if #unused == 0 then
      vim.notify("No unused symbols found", vim.log.levels.INFO)
      return
    end

    local qf_items = {}
    for _, item in ipairs(unused) do
      table.insert(qf_items, {
        filename = filename,
        lnum = item.line,
        text = string.format("[%s] %s", item.kind, item.name),
      })
    end

    vim.fn.setqflist(qf_items)
    vim.cmd("copen")
  end, { desc = "List all unused symbols in quickfix" })

  vim.api.nvim_create_user_command("AngularRefsToggle", function()
    local c = config.get()
    c.enabled = not c.enabled
    if c.enabled then
      vim.notify("Angular refs: enabled", vim.log.levels.INFO)
    else
      local display = require("angular-refs.display")
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) then
          display.clear(buf)
        end
      end
      vim.notify("Angular refs: disabled", vim.log.levels.INFO)
    end
  end, { desc = "Toggle Angular reference counts on/off" })
end

return M
