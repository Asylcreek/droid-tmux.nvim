local M = {}

local defaults = {
  submit_key = "C-m",
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
local pane_format = "#{pane_id}\t#{session_name}:#{window_index}.#{pane_index}\t"
  .. "#{pane_current_command}\t#{pane_title}\t#{pane_current_path}"

local function run(cmd, input)
  local res = vim.system(cmd, { text = true, stdin = input }):wait()
  return res.code, res.stdout or "", res.stderr or ""
end

local function in_tmux()
  return vim.env.TMUX and vim.env.TMUX ~= ""
end

local function tmux(args, input)
  if not in_tmux() then
    return nil, "Not running inside tmux."
  end
  local cmd = { "tmux" }
  vim.list_extend(cmd, args)
  local code, out, err = run(cmd, input)
  if code ~= 0 then
    return nil, (err ~= "" and err or out)
  end
  return vim.trim(out), nil
end

local function starts_with(s, prefix)
  return type(s) == "string" and type(prefix) == "string" and s:sub(1, #prefix) == prefix
end

local function build_single_line_message(message)
  local msg = message and vim.trim(message) or ""
  return msg:gsub("%s+", " ")
end

local function get_saved_pane()
  local out = tmux({ "show-options", "-gqv", "@droid_pane" })
  if not out or out == "" then
    return nil
  end
  return out
end

local function save_pane(pane_id)
  tmux({ "set", "-g", "@droid_pane", pane_id })
end

local function list_panes_all()
  local out, err = tmux({
    "list-panes",
    "-a",
    "-F",
    pane_format,
  })
  if not out then
    return nil, err
  end

  local panes = {}
  for _, line in ipairs(vim.split(out, "\n", { trimempty = true })) do
    local pane_id, target, cmd, title, path = line:match("^(%%[%d]+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
    if pane_id then
      table.insert(panes, {
        pane_id = pane_id,
        target = target,
        cmd = cmd,
        title = title,
        path = path,
        label = string.format("%s  [%s]  cmd=%s  title=%s", pane_id, target, cmd, title),
      })
    end
  end
  return panes, nil
end

local function list_panes_current_window()
  local out, err = tmux({
    "list-panes",
    "-F",
    pane_format,
  })
  if not out then
    return nil, err
  end

  local panes = {}
  for _, line in ipairs(vim.split(out, "\n", { trimempty = true })) do
    local pane_id, target, cmd, title, path = line:match("^(%%[%d]+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
    if pane_id then
      table.insert(panes, {
        pane_id = pane_id,
        target = target,
        cmd = cmd,
        title = title,
        path = path,
        label = string.format("%s  [%s]  cmd=%s  title=%s", pane_id, target, cmd, title),
      })
    end
  end
  return panes, nil
end

local function pane_exists_in_current_window(pane_id)
  local panes = list_panes_current_window()
  if not panes then
    return false
  end
  for _, pane in ipairs(panes) do
    if pane.pane_id == pane_id then
      return true
    end
  end
  return false
end

local function detect_droid_pane_in_current_window()
  local out, err = tmux({
    "list-panes",
    "-F",
    "#{pane_id}\t#{pane_current_command}\t#{pane_title}",
  })
  if not out then
    return nil, err
  end

  local lines = vim.split(out, "\n", { trimempty = true })
  local title_match = nil

  for _, line in ipairs(lines) do
    local pane_id, cmd, title = line:match("^(%%[%d]+)\t([^\t]*)\t(.*)$")
    if pane_id then
      if cmd == "droid" then
        return pane_id, nil
      end
      local t = (title or ""):lower()
      if t:find("droid", 1, true) then
        title_match = title_match or pane_id
      end
    end
  end

  if title_match then
    return title_match, nil
  end

  return nil, "No Droid pane found in current tmux window."
end

local function detect_droid_pane_by_cwd()
  local panes, err = list_panes_current_window()
  if not panes then
    return nil, err
  end

  local cwd = vim.fn.getcwd()
  local best = nil
  local best_score = -1

  for _, pane in ipairs(panes) do
    local cmd = (pane.cmd or ""):lower()
    local title = (pane.title or ""):lower()
    local path = pane.path or ""
    local is_droid = cmd == "droid" or title:find("droid", 1, true) ~= nil

    if is_droid then
      local score = 100
      if path == cwd then
        score = score + 60
      elseif starts_with(cwd, path) then
        score = score + 40
      elseif starts_with(path, cwd) then
        score = score + 30
      end
      if score > best_score then
        best = pane
        best_score = score
      end
    end
  end

  if best then
    return best.pane_id, nil
  end
  return nil, "No Droid pane found by cwd."
end

local function resolve_droid_pane()
  local saved = get_saved_pane()
  if saved and pane_exists_in_current_window(saved) then
    return saved
  end

  local by_cwd = detect_droid_pane_by_cwd()
  if by_cwd then
    save_pane(by_cwd)
    return by_cwd
  end

  local detected = detect_droid_pane_in_current_window()
  if detected then
    save_pane(detected)
    return detected
  end

  vim.notify("Could not resolve Droid pane in current tmux window.", vim.log.levels.ERROR)
  return nil
end

local function get_current_diff()
  local path = vim.fn.expand("%:p")
  local code, out, err = run({ "git", "diff", "--", path })
  if code ~= 0 then
    return nil, (err ~= "" and err or out)
  end
  if vim.trim(out) == "" then
    return nil, ""
  end
  return out, nil
end

local function is_git_ignored(path)
  if path == "" then
    return false
  end

  local dir = vim.fs.dirname(path)
  if not dir or dir == "" then
    return false
  end

  local code = run({ "git", "-C", dir, "check-ignore", "-q", "--", path })
  if code == 0 then
    return true
  end
  if code == 1 then
    return false
  end
  return false
end

local function format_diagnostics(diags, limit)
  if #diags == 0 then
    return ""
  end

  local severity_map = {
    [vim.diagnostic.severity.ERROR] = "ERROR",
    [vim.diagnostic.severity.WARN] = "WARN",
    [vim.diagnostic.severity.INFO] = "INFO",
    [vim.diagnostic.severity.HINT] = "HINT",
  }

  local lines = {}
  for i, d in ipairs(diags) do
    if i > limit then
      table.insert(lines, "... truncated ...")
      break
    end
    local sev = severity_map[d.severity] or "UNKNOWN"
    local lnum = (d.lnum or 0) + 1
    local col = (d.col or 0) + 1
    local source = d.source and (" source=" .. d.source) or ""
    local code = d.code and (" code=" .. tostring(d.code)) or ""
    local msg = (d.message or ""):gsub("\n", " ")
    table.insert(lines, string.format("- [%s] %d:%d %s%s%s", sev, lnum, col, msg, source, code))
  end
  return table.concat(lines, "\n")
end

local function format_quickfix_items(limit)
  local qf = vim.fn.getqflist({ items = 1 })
  local items = qf.items or {}
  if #items == 0 then
    return ""
  end

  local lines = {}
  for i, item in ipairs(items) do
    if i > limit then
      table.insert(lines, "... truncated ...")
      break
    end
    local filename = item.filename
    if (not filename or filename == "") and item.bufnr and item.bufnr > 0 then
      filename = vim.api.nvim_buf_get_name(item.bufnr)
    end
    filename = filename or "[no-file]"
    local lnum = item.lnum or 0
    local col = item.col or 0
    local text = (item.text or ""):gsub("\n", " ")
    table.insert(lines, string.format("- %s:%d:%d %s", filename, lnum, col, text))
  end

  return table.concat(lines, "\n")
end

local function get_context_value(name)
  if name == "file" then
    return vim.fn.expand("%:p")
  end
  if name == "diagnostics" then
    return format_diagnostics(vim.diagnostic.get(0), 80)
  end
  if name == "diagnostics_all" then
    local parts = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(buf) then
        local path = vim.api.nvim_buf_get_name(buf)
        if is_git_ignored(path) then
          goto continue
        end
        local d = vim.diagnostic.get(buf)
        if #d > 0 then
          table.insert(parts, "File: " .. path)
          table.insert(parts, format_diagnostics(d, 80))
        end
      end
      ::continue::
    end
    return table.concat(parts, "\n\n")
  end
  if name == "quickfix" then
    return format_quickfix_items(100)
  end
  if name == "diff" then
    local diff = get_current_diff()
    return diff or ""
  end
  return ""
end

local function expand_template(tpl)
  return (tpl:gsub("{([%w_]+)}", function(key)
    return get_context_value(key)
  end))
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
  local panes, err = list_panes_all()
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
    save_pane(choice.pane_id)
    vim.notify("Set @droid_pane=" .. choice.pane_id, vim.log.levels.INFO)
  end)
end

function M.focus()
  local pane = resolve_droid_pane()
  if not pane then
    return
  end

  local ok = tmux({ "select-pane", "-t", pane })
  if ok then
    return
  end

  local target, err = tmux({ "display-message", "-p", "-t", pane, "#{session_name}:#{window_index}" })
  if not target then
    vim.notify(err or "Could not locate target pane.", vim.log.levels.ERROR)
    return
  end

  tmux({ "select-window", "-t", target })
  tmux({ "select-pane", "-t", pane })
end

function M.send(text)
  if not text or text == "" then
    vim.notify("Nothing to send.", vim.log.levels.WARN)
    return
  end

  local pane = resolve_droid_pane()
  if not pane then
    return
  end

  text = text:gsub("\r\n", "\n")
  local lines = vim.split(text, "\n", { plain = true })

  for i, line in ipairs(lines) do
    if line ~= "" then
      local ok, err = tmux({ "send-keys", "-t", pane, "-l", "--", line })
      if not ok then
        vim.notify(err or "tmux send-keys failed.", vim.log.levels.ERROR)
        return
      end
    end

    if i < #lines then
      tmux({ "send-keys", "-t", pane, "\\", "C-m" })
    end
  end

  tmux({ "send-keys", "-t", pane, config.submit_key })
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
  local out, err = get_current_diff()
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
  local body = format_diagnostics(vim.diagnostic.get(0), 80)
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
  local body = get_context_value("diagnostics_all")
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
  local body = format_quickfix_items(100)
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
    M.send(expand_template(template))
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
    M.send(expand_template(choice.template))
  end)
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

  create_user_command("DroidPickPane", function()
    M.pick_pane()
  end, {})

  create_user_command("DroidFocus", function()
    M.focus()
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
