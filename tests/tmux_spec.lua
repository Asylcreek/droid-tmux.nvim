local tmux_mod = require("droid_tmux.tmux")

local function fake_vim()
  return {
    log = { levels = { ERROR = 4 } },
  }
end

local function make_runner(stubs)
  return function(cmd)
    local key = table.concat(cmd, " ")
    local value = stubs[key]
    if not value then
      return 1, "", "missing stub: " .. key
    end
    return value.code, value.out or "", value.err or ""
  end
end

local function test_parse_panes()
  local client = tmux_mod.new({
    vim = fake_vim(),
    env = { TMUX = "1" },
    run = function()
      return 0, "", ""
    end,
    getcwd = function()
      return "/repo"
    end,
  })

  local panes = client:parse_panes("%1\tdroid\tDroid Agent\t/repo\n%2\tzsh\tshell\t/repo/sub\n")
  assert(#panes == 2, "expected parsed panes")
  assert(panes[1].pane_id == "%1", "expected first pane id")
  assert(panes[2].cmd == "zsh", "expected second pane command")
end

local function test_resolve_prefers_cwd_match()
  local stubs = {
    ["tmux list-panes -F #{pane_id}\t#{pane_current_command}\t#{pane_title}\t#{pane_current_path}"] = {
      code = 0,
      out = "%2\tdroid\tDroid\t/repo\n%7\tdroid\tDroid\t/other\n",
    },
  }

  local client = tmux_mod.new({
    vim = fake_vim(),
    env = { TMUX = "1" },
    run = make_runner(stubs),
    getcwd = function()
      return "/repo"
    end,
  })

  local pane = client:resolve_droid_pane()
  assert(pane == "%2", "expected cwd droid pane")
  assert(client:get_last_resolution_source() == "cwd", "expected cwd source")
end

local function test_resolve_matches_droid_without_cwd_match()
  local stubs = {
    ["tmux list-panes -F #{pane_id}\t#{pane_current_command}\t#{pane_title}\t#{pane_current_path}"] = {
      code = 0,
      out = "%2\tzsh\tshell\t/repo\n%4\tdroid\twork\t/other\n",
    },
  }

  local client = tmux_mod.new({
    vim = fake_vim(),
    env = { TMUX = "1" },
    run = make_runner(stubs),
    getcwd = function()
      return "/repo"
    end,
  })

  local pane = client:resolve_droid_pane()
  assert(pane == "%4", "expected droid pane when cwd does not match")
  assert(client:get_last_resolution_source() == "cwd", "expected cwd resolver source")
end

local function test_resolve_matches_droid_title_when_command_is_shell()
  local stubs = {
    ["tmux list-panes -F #{pane_id}\t#{pane_current_command}\t#{pane_title}\t#{pane_current_path}"] = {
      code = 0,
      out = "%19\tzsh\tzsh\t/repo\n%20\tzsh\tt•:Droid\t/repo\n%84\tzsh\tt•:Droid\t/repo\n",
    },
  }

  local client = tmux_mod.new({
    vim = fake_vim(),
    env = { TMUX = "1" },
    run = make_runner(stubs),
    getcwd = function()
      return "/repo"
    end,
  })

  local pane = client:resolve_droid_pane()
  assert(pane == "%20", "expected first Droid-titled pane when command is shell")
  assert(client:get_last_resolution_source() == "cwd", "expected cwd source via title fallback")
end

local function test_resolve_reports_when_no_droid_pane_found()
  local stubs = {
    ["tmux list-panes -F #{pane_id}\t#{pane_current_command}\t#{pane_title}\t#{pane_current_path}"] = {
      code = 0,
      out = "%2\tzsh\tshell\t/repo\n%7\tbash\teditor\t/repo\n",
    },
  }

  local client = tmux_mod.new({
    vim = fake_vim(),
    env = { TMUX = "1" },
    run = make_runner(stubs),
    getcwd = function()
      return "/repo"
    end,
  })

  local pane, err = client:resolve_droid_pane()
  assert(pane == nil, "expected unresolved pane")
  assert(
    err == "No Droid pane found in current tmux window. Start `droid` in a tmux pane, then try again.",
    "expected clear no-droid error"
  )
  assert(client:get_last_resolution_source() == "none", "expected resolution source none")
end

local function test_focus_reports_stale_droid_pane_when_closed()
  local stubs = {
    ["tmux list-panes -F #{pane_id}\t#{pane_current_command}\t#{pane_title}\t#{pane_current_path}"] = {
      code = 0,
      out = "%3\tdroid\tDroid\t/repo\n",
    },
    ["tmux select-pane -t %3"] = { code = 1, err = "can't find pane: %3" },
  }

  local client = tmux_mod.new({
    vim = fake_vim(),
    env = { TMUX = "1" },
    run = make_runner(stubs),
    getcwd = function()
      return "/repo"
    end,
  })

  local ok, err = client:focus()
  assert(ok == nil, "expected focus to fail")
  assert(
    err == "Resolved Droid pane is no longer available. Start `droid` in a tmux pane, then try again.",
    "expected stale pane focus error"
  )
end

local function test_send_text_reports_stale_droid_pane_when_closed()
  local stubs = {
    ["tmux load-buffer -"] = { code = 0, out = "" },
    ["tmux paste-buffer -p -d -t %5"] = { code = 1, err = "can't find pane: %5" },
  }

  local client = tmux_mod.new({
    vim = fake_vim(),
    env = { TMUX = "1" },
    run = make_runner(stubs),
  })

  local ok, err = client:send_text("%5", "payload", { submit_key = "Enter" })
  assert(ok == nil, "expected send failure")
  assert(
    err == "Resolved Droid pane is no longer available. Start `droid` in a tmux pane, then try again.",
    "expected stale pane send error"
  )
end

return {
  test_parse_panes = test_parse_panes,
  test_resolve_prefers_cwd_match = test_resolve_prefers_cwd_match,
  test_resolve_matches_droid_without_cwd_match = test_resolve_matches_droid_without_cwd_match,
  test_resolve_matches_droid_title_when_command_is_shell = test_resolve_matches_droid_title_when_command_is_shell,
  test_resolve_reports_when_no_droid_pane_found = test_resolve_reports_when_no_droid_pane_found,
  test_focus_reports_stale_droid_pane_when_closed = test_focus_reports_stale_droid_pane_when_closed,
  test_send_text_reports_stale_droid_pane_when_closed = test_send_text_reports_stale_droid_pane_when_closed,
}
