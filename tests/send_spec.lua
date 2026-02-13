local tmux_mod = require("droid_tmux.tmux")

local function fake_vim()
  return {
    log = { levels = { ERROR = 4 } },
    wait = function()
      return true
    end,
  }
end

local function test_send_text_paste_preserves_multiline_and_submit()
  local calls = {}
  local run = function(cmd, input)
    table.insert(calls, { cmd = table.concat(cmd, " "), input = input })
    return 0, "", ""
  end

  local client = tmux_mod.new({
    vim = fake_vim(),
    env = { TMUX = "1" },
    run = run,
  })

  local payload = "Review:\n\n```lua\nprint('ok')\n```\n"
  local ok = client:send_text("%1", payload, { submit_key = "Enter" })

  assert(ok == true, "expected send to succeed")
  assert(#calls == 3, "expected load-buffer, paste-buffer, submit")
  assert(calls[1].cmd == "tmux load-buffer -", "expected load-buffer first")
  assert(calls[1].input == payload, "expected exact payload")
  assert(calls[2].cmd == "tmux paste-buffer -p -d -t %1", "expected bracketed paste target")
  assert(calls[3].cmd == "tmux send-keys -t %1 Enter", "expected submit key")
end

local function test_send_text_normalizes_crlf_before_paste()
  local calls = {}
  local run = function(cmd, input)
    table.insert(calls, { cmd = table.concat(cmd, " "), input = input })
    return 0, "", ""
  end

  local client = tmux_mod.new({
    vim = fake_vim(),
    env = { TMUX = "1" },
    run = run,
  })

  local ok = client:send_text("%2", "a\r\nb\r\n", { submit_key = "Enter" })
  assert(ok == true, "expected send to succeed")
  assert(calls[1].input == "a\nb\n", "expected CRLF normalized to LF")
end

local function test_send_text_submit_delay_waits_before_submit()
  local calls = {}
  local waited = nil
  local run = function(cmd, input)
    table.insert(calls, { cmd = table.concat(cmd, " "), input = input })
    return 0, "", ""
  end

  local v = fake_vim()
  v.wait = function(ms)
    waited = ms
    return true
  end

  local client = tmux_mod.new({
    vim = v,
    env = { TMUX = "1" },
    run = run,
  })

  local ok = client:send_text("%3", "hello", { submit_key = "Enter", submit_delay_ms = 40 })
  assert(ok == true, "expected send to succeed")
  assert(waited == 40, "expected wait before submit")
  assert(calls[3].cmd == "tmux send-keys -t %3 Enter", "expected submit key")
end

return {
  test_send_text_paste_preserves_multiline_and_submit = test_send_text_paste_preserves_multiline_and_submit,
  test_send_text_normalizes_crlf_before_paste = test_send_text_normalizes_crlf_before_paste,
  test_send_text_submit_delay_waits_before_submit = test_send_text_submit_delay_waits_before_submit,
}
