local function new_fake_tmux(opts)
  local cfg = opts or {}
  local calls = {}
  local client = {
    calls = calls,
  }

  function client:focus()
    if cfg.focus_ok == false then
      return nil, cfg.focus_err or "focus failed"
    end
    return true, nil
  end

  function client:resolve_droid_pane()
    if cfg.resolve_ok == false then
      return nil, cfg.resolve_err or "resolve failed"
    end
    return "%1"
  end

  function client:get_last_resolution_source()
    return "cwd"
  end

  function client:send_text(pane, text, opts)
    if cfg.send_ok == false then
      return nil, cfg.send_err or "send failed"
    end
    table.insert(calls, {
      pane = pane,
      text = text,
      opts = opts,
    })
    return true, nil
  end

  return client
end

local function new_fake_context()
  local client = {}

  function client:get_current_diff()
    return "diff --git a/a.lua b/a.lua\n+print('x')\n", nil
  end

  function client:format_diagnostics()
    return "- [ERROR] 1:1 boom"
  end

  function client:get_context_value(name)
    if name == "diagnostics_all" then
      return "File: /tmp/a.lua\n\n- [ERROR] 1:1 boom"
    end
    return ""
  end

  function client:format_quickfix_items()
    return ""
  end

  function client:expand_template(tpl)
    return "expanded:" .. tpl
  end

  return client
end

local function fresh_plugin(fake_tmux, fake_context)
  package.loaded["droid_tmux"] = nil
  local plugin = require("droid_tmux")
  plugin.setup({
    _clients = {
      tmux = fake_tmux,
      context = fake_context,
    },
  })
  return plugin
end

local function test_send_line_uses_common_send_pipeline()
  local tmux = new_fake_tmux()
  local context = new_fake_context()
  local plugin = fresh_plugin(tmux, context)

  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(buf, "/tmp/send_line.lua")
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "first", "second", "third" })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  plugin.send_line("please review")

  assert(#tmux.calls == 1, "expected one send call")
  local sent = tmux.calls[1]
  assert(sent.pane == "%1", "expected resolved pane")
  assert(sent.text:find("please review", 1, true), "expected prefix")
  assert(sent.text:find("File: /tmp/send_line.lua", 1, true), "expected file path")
  assert(sent.text:find("Line: 2", 1, true), "expected line number")
  assert(sent.text:find("second", 1, true), "expected selected line content")
end

local function test_send_lines_uses_common_send_pipeline()
  local tmux = new_fake_tmux()
  local context = new_fake_context()
  local plugin = fresh_plugin(tmux, context)

  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(buf, "/tmp/send_lines.lua")
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "a", "b", "c", "d" })

  plugin.send_lines(2, 3, "inspect")

  assert(#tmux.calls == 1, "expected one send call")
  local sent = tmux.calls[1]
  assert(sent.text:find("inspect", 1, true), "expected prefix")
  assert(sent.text:find("Lines: 2-3", 1, true), "expected range metadata")
  assert(sent.text:find("b\nc", 1, true), "expected selected lines")
end

local function test_send_diff_uses_common_send_pipeline()
  local tmux = new_fake_tmux()
  local context = new_fake_context()
  local plugin = fresh_plugin(tmux, context)

  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(buf, "/tmp/diff_target.lua")
  vim.api.nvim_set_current_buf(buf)

  plugin.send_diff("")

  assert(#tmux.calls == 1, "expected one send call")
  local sent = tmux.calls[1]
  assert(sent.text:find("Review this diff", 1, true), "expected default diff header")
  assert(sent.text:find("File: /tmp/diff_target.lua", 1, true), "expected diff file metadata")
  assert(sent.text:find("```diff", 1, true), "expected diff fence")
end

local function test_prompt_expansion_uses_common_send_pipeline()
  local tmux = new_fake_tmux()
  local context = new_fake_context()
  local plugin = fresh_plugin(tmux, context)

  plugin.prompt("Review {file}")

  assert(#tmux.calls == 1, "expected one send call")
  local sent = tmux.calls[1]
  assert(sent.text == "expanded:Review {file}", "expected expanded prompt payload")
end

local function test_send_diagnostics_all_uses_common_send_pipeline()
  local tmux = new_fake_tmux()
  local context = new_fake_context()
  local plugin = fresh_plugin(tmux, context)

  plugin.send_diagnostics_all("")

  assert(#tmux.calls == 1, "expected one send call")
  local sent = tmux.calls[1]
  assert(sent.text:find("Explain and help fix workspace diagnostics", 1, true), "expected default prefix")
  assert(sent.text:find("File: /tmp/a.lua", 1, true), "expected diagnostics payload")
end

local function test_droid_status_command_registered()
  local tmux = new_fake_tmux()
  local context = new_fake_context()
  fresh_plugin(tmux, context)
  assert(vim.fn.exists(":DroidStatus") == 2, "expected :DroidStatus command")
end

local function test_droid_status_reports_pane_source()
  local tmux = new_fake_tmux()
  local context = new_fake_context()
  local plugin = fresh_plugin(tmux, context)
  local original_notify = vim.notify
  local message = nil

  vim.notify = function(msg)
    message = msg
  end

  local ok, err = pcall(function()
    plugin.status()
  end)
  vim.notify = original_notify

  assert(ok, "expected status call to succeed: " .. tostring(err))
  assert(type(message) == "string", "expected status message")
  assert(message:find("pane_source: cwd", 1, true), "expected pane source in status output")
end

local function test_focus_notifies_when_no_droid_pane()
  local tmux = new_fake_tmux({
    focus_ok = false,
    focus_err = "No Droid pane found in current tmux window. Start `droid` in a tmux pane, then try again.",
  })
  local context = new_fake_context()
  local plugin = fresh_plugin(tmux, context)
  local original_notify = vim.notify
  local message = nil

  vim.notify = function(msg)
    message = msg
  end

  local ok, err = pcall(function()
    plugin.focus()
  end)
  vim.notify = original_notify

  assert(ok, "expected focus call to succeed: " .. tostring(err))
  assert(type(message) == "string", "expected focus notification")
  assert(message:find("No Droid pane found in current tmux window", 1, true), "expected no-droid focus message")
end

local function test_send_line_notifies_when_no_droid_pane()
  local tmux = new_fake_tmux({
    resolve_ok = false,
    resolve_err = "No Droid pane found in current tmux window. Start `droid` in a tmux pane, then try again.",
  })
  local context = new_fake_context()
  local plugin = fresh_plugin(tmux, context)
  local original_notify = vim.notify
  local message = nil

  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(buf, "/tmp/no_droid.lua")
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })

  vim.notify = function(msg)
    message = msg
  end

  local ok, err = pcall(function()
    plugin.send_line("")
  end)
  vim.notify = original_notify

  assert(ok, "expected send_line call to succeed: " .. tostring(err))
  assert(type(message) == "string", "expected send notification")
  assert(message:find("No Droid pane found in current tmux window", 1, true), "expected no-droid send message")
  assert(#tmux.calls == 0, "expected no send_text call when pane unresolved")
end

return {
  test_send_line_uses_common_send_pipeline = test_send_line_uses_common_send_pipeline,
  test_send_lines_uses_common_send_pipeline = test_send_lines_uses_common_send_pipeline,
  test_send_diff_uses_common_send_pipeline = test_send_diff_uses_common_send_pipeline,
  test_prompt_expansion_uses_common_send_pipeline = test_prompt_expansion_uses_common_send_pipeline,
  test_send_diagnostics_all_uses_common_send_pipeline = test_send_diagnostics_all_uses_common_send_pipeline,
  test_droid_status_command_registered = test_droid_status_command_registered,
  test_droid_status_reports_pane_source = test_droid_status_reports_pane_source,
  test_focus_notifies_when_no_droid_pane = test_focus_notifies_when_no_droid_pane,
  test_send_line_notifies_when_no_droid_pane = test_send_line_notifies_when_no_droid_pane,
}
