local M = {}

local pane_format = "#{pane_id}\t#{pane_current_command}\t#{pane_title}\t#{pane_current_path}"

local function trim(s)
  if type(s) ~= "string" then
    return ""
  end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function split_lines(text)
  local lines = {}
  for line in (text or ""):gmatch("([^\n]+)") do
    table.insert(lines, line)
  end
  return lines
end

local NO_DROID_ERR = "No Droid pane picked for this tmux window. Run `:DroidPickPane` to select one."
local STALE_DROID_ERR = "Picked Droid pane is no longer available in this tmux window. Run `:DroidPickPane` again."
local PICKED_PANE_OPTION = "@droid_pane"

local function is_missing_pane_error(err)
  local e = (err or ""):lower()
  return e:find("can't find pane", 1, true) ~= nil or e:find("pane not found", 1, true) ~= nil
end

function M.new(deps)
  deps = deps or {}
  local vim_ref = deps.vim or vim
  local run = deps.run

  if not run then
    run = function(cmd, input)
      local res = vim_ref.system(cmd, { text = true, stdin = input }):wait()
      return res.code, res.stdout or "", res.stderr or ""
    end
  end

  local client = {}
  local last_resolution_source = "none"

  function client.in_tmux(_)
    local env = deps.env or vim_ref.env or {}
    return env.TMUX and env.TMUX ~= ""
  end

  function client.exec(_, args, input)
    if not client:in_tmux() then
      return nil, "Not running inside tmux."
    end
    local cmd = { "tmux" }
    for _, arg in ipairs(args or {}) do
      table.insert(cmd, arg)
    end
    local code, out, err = run(cmd, input)
    if code ~= 0 then
      return nil, (err ~= "" and err or out)
    end
    return trim(out), nil
  end

  function client.parse_panes(_, out)
    local panes = {}
    for _, line in ipairs(split_lines(out)) do
      local pane_id, cmd, title, path = line:match("^(%%[%d]+)\t([^\t]*)\t([^\t]*)\t(.*)$")
      if pane_id then
        table.insert(panes, {
          pane_id = pane_id,
          cmd = cmd,
          title = title,
          path = path,
        })
      end
    end
    return panes
  end

  function client.list_panes(_)
    local out, err = client:exec({ "list-panes", "-F", pane_format })
    if not out then
      return nil, err
    end
    return client:parse_panes(out), nil
  end

  function client.get_picked_pane(_)
    local pane, err = client:exec({ "show-options", "-wqv", PICKED_PANE_OPTION })
    if not pane then
      return nil, err
    end
    pane = trim(pane)
    if pane == "" then
      return nil, nil
    end
    if pane:match("^%%[%d]+$") then
      return pane, nil
    end
    return nil, nil
  end

  function client.set_picked_pane(_, pane)
    local target = trim(pane or "")
    if target == "" then
      local current, current_err = client:exec({ "display-message", "-p", "#{pane_id}" })
      if not current then
        return nil, current_err or "Could not resolve current tmux pane."
      end
      target = trim(current)
    end
    if not target:match("^%%[%d]+$") then
      return nil, "Pane id must look like `%1`."
    end
    local ok, err = client:exec({ "set-option", "-wq", PICKED_PANE_OPTION, target })
    if not ok then
      return nil, err or "Could not persist picked pane."
    end
    return target, nil
  end

  function client.clear_picked_pane(_)
    local ok, err = client:exec({ "set-option", "-wu", PICKED_PANE_OPTION })
    if not ok then
      return nil, err or "Could not clear picked pane."
    end
    return true, nil
  end

  function client.pane_exists(_, pane)
    local panes, err = client:list_panes()
    if not panes then
      return nil, err
    end
    for _, item in ipairs(panes) do
      if item.pane_id == pane then
        return true, nil
      end
    end
    return false, nil
  end

  function client.resolve_droid_pane(_)
    local picked, picked_err = client:get_picked_pane()
    if not picked and picked_err then
      last_resolution_source = "none"
      return nil, picked_err
    end
    if picked then
      local exists, exists_err = client:pane_exists(picked)
      if exists_err then
        last_resolution_source = "none"
        return nil, exists_err
      end
      if exists then
        last_resolution_source = "picked"
        return picked, nil
      end
      client:clear_picked_pane()
      last_resolution_source = "none"
      return nil, STALE_DROID_ERR
    end

    last_resolution_source = "none"
    return nil, NO_DROID_ERR
  end

  function client.get_last_resolution_source(_)
    return last_resolution_source
  end

  function client.focus_pane(_, pane)
    local ok, select_err = client:exec({ "select-pane", "-t", pane })
    if ok then
      return true, nil
    end
    if is_missing_pane_error(select_err) then
      return nil, STALE_DROID_ERR
    end

    local target, err = client:exec({ "display-message", "-p", "-t", pane, "#{session_name}:#{window_index}" })
    if not target then
      if is_missing_pane_error(err) then
        return nil, STALE_DROID_ERR
      end
      return nil, err or "Could not locate target pane."
    end

    ok, err = client:exec({ "select-window", "-t", target })
    if not ok then
      if is_missing_pane_error(err) then
        return nil, STALE_DROID_ERR
      end
      return nil, err or "Could not select tmux window."
    end

    ok, err = client:exec({ "select-pane", "-t", pane })
    if not ok then
      if is_missing_pane_error(err) then
        return nil, STALE_DROID_ERR
      end
      return nil, err or "Could not select tmux pane."
    end

    return true, nil
  end

  function client.focus(_)
    local pane, resolve_err = client:resolve_droid_pane()
    if not pane then
      return nil, resolve_err or NO_DROID_ERR
    end

    return client:focus_pane(pane)
  end

  function client.send_text(_, pane, text, opts)
    opts = opts or {}
    local payload = (text or ""):gsub("\r\n", "\n")
    local ok, err = client:exec({ "load-buffer", "-" }, payload)
    if not ok then
      return nil, err
    end

    ok, err = client:exec({ "paste-buffer", "-p", "-d", "-t", pane })
    if not ok then
      if is_missing_pane_error(err) then
        return nil, STALE_DROID_ERR
      end
      return nil, err
    end

    if opts.submit_delay_ms and opts.submit_delay_ms > 0 and vim_ref.wait then
      vim_ref.wait(opts.submit_delay_ms)
    end

    if opts.submit_key and opts.submit_key ~= "" then
      ok, err = client:exec({ "send-keys", "-t", pane, opts.submit_key })
      if not ok then
        if is_missing_pane_error(err) then
          return nil, STALE_DROID_ERR
        end
        return nil, err
      end
    end

    return true, nil
  end

  return client
end

return M
