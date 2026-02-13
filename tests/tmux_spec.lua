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

  local panes = client:parse_panes("%1\ts:1.0\tdroid\tDroid Agent\t/repo\n%2\ts:1.1\tzsh\tshell\t/repo/sub\n")
  assert(#panes == 2, "expected parsed panes")
  assert(panes[1].pane_id == "%1", "expected first pane id")
  assert(panes[2].cmd == "zsh", "expected second pane command")
end

local function test_resolve_prefers_saved_pane()
  local stubs = {
    ["tmux show-options -gqv @droid_pane"] = { code = 0, out = "%3\n" },
    ["tmux list-panes -F #{pane_id}\t#{session_name}:#{window_index}.#{pane_index}\t#{pane_current_command}\t#{pane_title}\t#{pane_current_path}"] = {
      code = 0,
      out = "%3\ts:1.0\tdroid\tDroid\t/repo\n%4\ts:1.1\tzsh\tshell\t/repo\n",
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
  assert(pane == "%3", "expected saved pane to win")
end

local function test_resolve_falls_back_to_cwd_match_and_saves()
  local set_calls = 0
  local stubs = {
    ["tmux show-options -gqv @droid_pane"] = { code = 0, out = "%9\n" },
    ["tmux list-panes -F #{pane_id}\t#{session_name}:#{window_index}.#{pane_index}\t#{pane_current_command}\t#{pane_title}\t#{pane_current_path}"] = {
      code = 0,
      out = "%2\ts:1.0\tdroid\tDroid\t/repo\n%7\ts:1.1\tdroid\tDroid\t/other\n",
    },
    ["tmux set -g @droid_pane %2"] = {
      code = 0,
      out = "",
      err = "",
      on_call = function()
        set_calls = set_calls + 1
      end,
    },
  }

  local run = function(cmd)
    local key = table.concat(cmd, " ")
    local value = stubs[key]
    if not value then
      return 1, "", "missing stub: " .. key
    end
    if value.on_call then
      value.on_call()
    end
    return value.code, value.out or "", value.err or ""
  end

  local client = tmux_mod.new({
    vim = fake_vim(),
    env = { TMUX = "1" },
    run = run,
    getcwd = function()
      return "/repo"
    end,
  })

  local pane = client:resolve_droid_pane()
  assert(pane == "%2", "expected cwd droid pane")
  assert(set_calls == 1, "expected pane save when discovered")
end

return {
  test_parse_panes = test_parse_panes,
  test_resolve_prefers_saved_pane = test_resolve_prefers_saved_pane,
  test_resolve_falls_back_to_cwd_match_and_saves = test_resolve_falls_back_to_cwd_match_and_saves,
}
