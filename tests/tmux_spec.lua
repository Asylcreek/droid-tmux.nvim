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

local function test_resolve_prefers_picked_pane()
  local stubs = {
    ["tmux show-options -wqv @droid_pane"] = {
      code = 0,
      out = "%9\n",
    },
    ["tmux list-panes -F #{pane_id}\t#{pane_current_command}\t#{pane_title}\t#{pane_current_path}"] = {
      code = 0,
      out = "%9\tzsh\tshell\t/repo\n",
    },
  }

  local client = tmux_mod.new({
    vim = fake_vim(),
    env = { TMUX = "1" },
    run = make_runner(stubs),
  })

  local pane = client:resolve_droid_pane()
  assert(pane == "%9", "expected picked pane to win")
  assert(client:get_last_resolution_source() == "picked", "expected picked source")
end

local function test_resolve_reports_when_no_picked_pane_found()
  local stubs = {
    ["tmux show-options -wqv @droid_pane"] = {
      code = 0,
      out = "\n",
    },
  }

  local client = tmux_mod.new({
    vim = fake_vim(),
    env = { TMUX = "1" },
    run = make_runner(stubs),
  })

  local pane, err = client:resolve_droid_pane()
  assert(pane == nil, "expected unresolved pane")
  assert(
    err == "No Droid pane picked for this tmux window. Run `:DroidPickPane` to select one.",
    "expected no-picked-pane error"
  )
  assert(client:get_last_resolution_source() == "none", "expected resolution source none")
end

local function test_resolve_reports_when_picked_pane_is_stale()
  local stubs = {
    ["tmux show-options -wqv @droid_pane"] = {
      code = 0,
      out = "%9\n",
    },
    ["tmux list-panes -F #{pane_id}\t#{pane_current_command}\t#{pane_title}\t#{pane_current_path}"] = {
      code = 0,
      out = "%2\tzsh\tshell\t/repo\n",
    },
    ["tmux set-option -wu @droid_pane"] = {
      code = 0,
      out = "",
    },
  }

  local client = tmux_mod.new({
    vim = fake_vim(),
    env = { TMUX = "1" },
    run = make_runner(stubs),
  })

  local pane, err = client:resolve_droid_pane()
  assert(pane == nil, "expected unresolved pane")
  assert(
    err == "Picked Droid pane is no longer available in this tmux window. Run `:DroidPickPane` again.",
    "expected stale picked pane error"
  )
  assert(client:get_last_resolution_source() == "none", "expected resolution source none")
end

local function test_resolve_reports_when_show_options_fails()
  local stubs = {
    ["tmux show-options -wqv @droid_pane"] = {
      code = 1,
      err = "tmux failed",
    },
  }

  local client = tmux_mod.new({
    vim = fake_vim(),
    env = { TMUX = "1" },
    run = make_runner(stubs),
  })

  local pane, err = client:resolve_droid_pane()
  assert(pane == nil, "expected unresolved pane")
  assert(err == "tmux failed", "expected tmux error to surface")
  assert(client:get_last_resolution_source() == "none", "expected resolution source none")
end

local function test_focus_reports_stale_droid_pane_when_closed()
  local stubs = {
    ["tmux show-options -wqv @droid_pane"] = {
      code = 0,
      out = "%3\n",
    },
    ["tmux list-panes -F #{pane_id}\t#{pane_current_command}\t#{pane_title}\t#{pane_current_path}"] = {
      code = 0,
      out = "%3\tzsh\tshell\t/repo\n",
    },
    ["tmux select-pane -t %3"] = { code = 1, err = "can't find pane: %3" },
  }

  local client = tmux_mod.new({
    vim = fake_vim(),
    env = { TMUX = "1" },
    run = make_runner(stubs),
  })

  local ok, err = client:focus()
  assert(ok == nil, "expected focus to fail")
  assert(
    err == "Picked Droid pane is no longer available in this tmux window. Run `:DroidPickPane` again.",
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
    err == "Picked Droid pane is no longer available in this tmux window. Run `:DroidPickPane` again.",
    "expected stale pane send error"
  )
end

return {
  test_parse_panes = test_parse_panes,
  test_resolve_prefers_picked_pane = test_resolve_prefers_picked_pane,
  test_resolve_reports_when_no_picked_pane_found = test_resolve_reports_when_no_picked_pane_found,
  test_resolve_reports_when_picked_pane_is_stale = test_resolve_reports_when_picked_pane_is_stale,
  test_resolve_reports_when_show_options_fails = test_resolve_reports_when_show_options_fails,
  test_focus_reports_stale_droid_pane_when_closed = test_focus_reports_stale_droid_pane_when_closed,
  test_send_text_reports_stale_droid_pane_when_closed = test_send_text_reports_stale_droid_pane_when_closed,
}
