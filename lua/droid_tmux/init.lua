local M = {}

local context_mod = require("droid_tmux.context")
local tmux_mod = require("droid_tmux.tmux")

local defaults = {
  submit_key = "Enter",
  submit_delay_ms = 120,
  keymaps = {
    ask = "<leader>aa",
    focus = "<leader>af",
    visual = "<leader>av",
    line = "<leader>al",
    prompt = "<leader>ap",
    diff = "<leader>ad",
    diagnostics = "<leader>ax",
    diagnostics_all = "<leader>aX",
    quickfix = "<leader>aq",
  },
}

local config = vim.deepcopy(defaults)
local tmux_client = tmux_mod.new({ vim = vim })
local context_client = context_mod.new({ vim = vim })
local last_send = {
  ok = nil,
  err = nil,
  pane = nil,
  size = 0,
}

local function build_single_line_message(message)
  local msg = message and vim.trim(message) or ""
  return msg:gsub("%s+", " ")
end

local function map_key(mode, lhs, rhs, opts)
  if lhs == nil or lhs == false or lhs == "" then
    return
  end
  vim.keymap.set(mode, lhs, rhs, opts)
end

local function create_user_command(name, fn, opts)
  if vim.fn.exists(":" .. name) == 2 then
    pcall(vim.api.nvim_del_user_command, name)
  end
  vim.api.nvim_create_user_command(name, fn, opts)
end

function M.pick_pane()
  local panes, err = tmux_client:list_panes_all()
  if not panes then
    vim.notify(err or "Could not list tmux panes.", vim.log.levels.ERROR)
    return
  end
  if #panes == 0 then
    vim.notify("No tmux panes found.", vim.log.levels.WARN)
    return
  end

  vim.ui.select(panes, {
    prompt = "Select Droid pane",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if not choice then
      return
    end
    tmux_client:save_pane(choice.pane_id)
    vim.notify("Set @droid_pane=" .. choice.pane_id, vim.log.levels.INFO)
  end)
end

function M.focus()
  tmux_client:focus()
end

function M.send(text)
  if not text or text == "" then
    vim.notify("Nothing to send.", vim.log.levels.WARN)
    return
  end

  local pane = tmux_client:resolve_droid_pane()
  if not pane then
    last_send = {
      ok = false,
      err = "Could not resolve Droid pane.",
      pane = nil,
      size = #text,
    }
    return
  end

  local ok, err = tmux_client:send_text(pane, text, {
    submit_key = config.submit_key,
    submit_delay_ms = config.submit_delay_ms,
  })
  if not ok then
    last_send = {
      ok = false,
      err = err or "tmux send failed.",
      pane = pane,
      size = #text,
    }
    vim.notify(err or "tmux send failed.", vim.log.levels.ERROR)
    return
  end

  last_send = {
    ok = true,
    err = nil,
    pane = pane,
    size = #text,
  }
end

function M.status()
  local pane = tmux_client:resolve_droid_pane() or "[unresolved]"
  local source = "unknown"
  if tmux_client.get_last_resolution_source then
    source = tmux_client:get_last_resolution_source() or "unknown"
  end
  local send_state
  if last_send.ok == nil then
    send_state = "none"
  elseif last_send.ok then
    send_state = "ok"
  else
    send_state = "error: " .. (last_send.err or "unknown")
  end

  local lines = {
    "droid-tmux status",
    "pane: " .. pane,
    "pane_source: " .. source,
    "submit_key: " .. tostring(config.submit_key),
    "submit_delay_ms: " .. tostring(config.submit_delay_ms),
    "last_send: " .. send_state,
    "last_send_size: " .. tostring(last_send.size or 0),
  }
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

function M.ask(message)
  local msg = build_single_line_message(message)
  if msg ~= "" then
    M.send(msg)
    return
  end

  vim.ui.input({ prompt = "Droid > " }, function(input)
    local text = build_single_line_message(input)
    if text ~= "" then
      M.send(text)
    end
  end)
end

function M.send_buffer(message)
  local path = vim.fn.expand("%:p")
  local msg = build_single_line_message(message)
  local payload = "File: " .. path
  if msg ~= "" then
    payload = msg .. " | " .. payload
  end
  M.send(payload)
end

function M.send_line(message)
  local path = vim.fn.expand("%:p")
  local line_no = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(0, line_no - 1, line_no, false)[1] or ""
  local prefix = build_single_line_message(message)
  local payload = string.format("File: %s\nLine: %d\n\n%s", path, line_no, line)
  if prefix ~= "" then
    payload = string.format("%s\n\n%s", prefix, payload)
  end
  M.send(payload)
end

function M.send_lines(line1, line2, message)
  local path = vim.fn.expand("%:p")
  local start_line = tonumber(line1) or vim.api.nvim_win_get_cursor(0)[1]
  local end_line = tonumber(line2) or start_line
  start_line = math.max(1, start_line)
  end_line = math.max(1, end_line)
  if end_line < start_line then
    start_line, end_line = end_line, start_line
  end
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  local prefix = build_single_line_message(message)
  local payload = string.format("File: %s\nLines: %d-%d\n\n%s", path, start_line, end_line, table.concat(lines, "\n"))
  if prefix ~= "" then
    payload = string.format("%s\n\n%s", prefix, payload)
  end
  M.send(payload)
end

function M.send_diff(message)
  local path = vim.fn.expand("%:p")
  local out, err = context_client:get_current_diff()
  if err then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end
  if not out or out == "" then
    vim.notify("No unstaged diff for current file.", vim.log.levels.INFO)
    return
  end

  local msg = build_single_line_message(message)
  local header = msg ~= "" and msg or "Review this diff"
  local payload = string.format("%s\n\nFile: %s\n\n```diff\n%s\n```", header, path, out)
  M.send(payload)
end

function M.send_diagnostics(message)
  local path = vim.fn.expand("%:p")
  local body = context_client:format_diagnostics(vim.diagnostic.get(0), 80)
  if body == "" then
    vim.notify("No diagnostics in current buffer.", vim.log.levels.INFO)
    return
  end

  local prefix = build_single_line_message(message)
  if prefix == "" then
    prefix = "Explain and help fix these diagnostics"
  end

  local payload = string.format("%s\n\nFile: %s\n\n%s", prefix, path, body)
  M.send(payload)
end

function M.send_diagnostics_all(message)
  local body = context_client:get_context_value("diagnostics_all")
  if body == "" then
    vim.notify("No diagnostics in loaded non-gitignored buffers.", vim.log.levels.INFO)
    return
  end

  local prefix = build_single_line_message(message)
  if prefix == "" then
    prefix = "Explain and help fix workspace diagnostics"
  end

  M.send(prefix .. "\n\n" .. body)
end

function M.send_quickfix(message)
  local body = context_client:format_quickfix_items(100)
  if body == "" then
    vim.notify("Quickfix list is empty.", vim.log.levels.INFO)
    return
  end

  local prefix = build_single_line_message(message)
  if prefix == "" then
    prefix = "Review and prioritize these quickfix items"
  end

  M.send(prefix .. "\n\n" .. body)
end

function M.prompt(template)
  if template and vim.trim(template) ~= "" then
    M.send(context_client:expand_template(template))
    return
  end

  local prompts = {
    {
      label = "Review {file}",
      template = "Review this file and suggest improvements:\n\nFile: {file}",
    },
    {
      label = "Fix {diagnostics}",
      template = "Help me fix these diagnostics:\n\nFile: {file}\n\n{diagnostics}",
    },
    {
      label = "Fix {diagnostics_all}",
      template = "Help me prioritize and fix workspace diagnostics:\n\n{diagnostics_all}",
    },
    {
      label = "Review {quickfix}",
      template = "Review these quickfix items and suggest a fix order:\n\n{quickfix}",
    },
    {
      label = "Review {diff}",
      template = "Review this diff and propose concrete changes:\n\nFile: {file}\n\n{diff}",
    },
  }

  vim.ui.select(prompts, {
    prompt = "Droid Prompt",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if not choice then
      return
    end
    M.send(context_client:expand_template(choice.template))
  end)
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  if opts and opts._clients then
    tmux_client = opts._clients.tmux or tmux_mod.new({ vim = vim })
    context_client = opts._clients.context or context_mod.new({ vim = vim })
  else
    tmux_client = tmux_mod.new({ vim = vim })
    context_client = context_mod.new({ vim = vim })
  end

  create_user_command("DroidPickPane", function()
    M.pick_pane()
  end, {})

  create_user_command("DroidFocus", function()
    M.focus()
  end, {})

  create_user_command("DroidStatus", function()
    M.status()
  end, {})

  create_user_command("DroidAsk", function(c)
    M.ask(c.args)
  end, { nargs = "*" })

  create_user_command("DroidPrompt", function(c)
    M.prompt(c.args)
  end, { nargs = "*" })

  create_user_command("DroidSendLine", function(c)
    M.send_line(c.args)
  end, { nargs = "*" })

  create_user_command("DroidSendLines", function(c)
    M.send_lines(c.line1, c.line2, c.args)
  end, { nargs = "*", range = true })

  create_user_command("DroidSendBuffer", function(c)
    M.send_buffer(c.args)
  end, { nargs = "*" })

  create_user_command("DroidSendDiff", function(c)
    M.send_diff(c.args)
  end, { nargs = "*" })

  create_user_command("DroidSendDiagnostics", function(c)
    M.send_diagnostics(c.args)
  end, { nargs = "*" })

  create_user_command("DroidSendDiagnosticsAll", function(c)
    M.send_diagnostics_all(c.args)
  end, { nargs = "*" })

  create_user_command("DroidSendQuickfix", function(c)
    M.send_quickfix(c.args)
  end, { nargs = "*" })

  local km = config.keymaps or {}

  map_key("n", km.file, function()
    M.send_buffer("")
  end, { desc = "Droid: send file" })

  map_key("v", km.visual, function()
    local s = vim.fn.line("v")
    local e = vim.fn.line(".")
    if s == 0 or e == 0 then
      local ms = vim.fn.getpos("'<")
      local me = vim.fn.getpos("'>")
      s = ms[2]
      e = me[2]
    end
    if s > e then
      s, e = e, s
    end
    vim.ui.input({ prompt = "Droid (selection) > " }, function(input)
      M.send_lines(s, e, input or "")
    end)
  end, { desc = "Droid: send selected lines (optional message)" })

  map_key("n", km.line, function()
    vim.ui.input({ prompt = "Droid (line) > " }, function(input)
      M.send_line(input or "")
    end)
  end, { desc = "Droid: send current line (optional message)" })

  map_key("n", km.prompt, function()
    M.prompt("")
  end, { desc = "Droid: prompt picker" })

  map_key("n", km.diff, function()
    M.send_diff("")
  end, { desc = "Droid: send git diff" })

  map_key("n", km.diagnostics, function()
    M.send_diagnostics("")
  end, { desc = "Droid: send diagnostics" })

  map_key("n", km.diagnostics_all, function()
    M.send_diagnostics_all("")
  end, { desc = "Droid: send workspace diagnostics" })

  map_key("n", km.quickfix, function()
    M.send_quickfix("")
  end, { desc = "Droid: send quickfix" })

  map_key("n", km.ask, function()
    M.ask("")
  end, { desc = "Droid: ask prompt" })

  map_key("n", km.focus, function()
    M.focus()
  end, { desc = "Droid: focus pane" })

  map_key("n", km.pick_pane, function()
    M.pick_pane()
  end, { desc = "Droid: pick pane" })
end

return M
