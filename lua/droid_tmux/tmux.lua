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

local function starts_with(s, prefix)
  return type(s) == "string" and type(prefix) == "string" and s:sub(1, #prefix) == prefix
end

local NO_DROID_ERR = "No Droid pane found in current tmux window. Start `droid` in a tmux pane, then try again."
local STALE_DROID_ERR = "Resolved Droid pane is no longer available. Start `droid` in a tmux pane, then try again."

local function is_missing_pane_error(err)
  local e = (err or ""):lower()
  return e:find("can't find pane", 1, true) ~= nil or e:find("pane not found", 1, true) ~= nil
end

function M.new(deps)
  deps = deps or {}
  local vim_ref = deps.vim or vim
  local run = deps.run
  local getcwd = deps.getcwd or function()
    return vim_ref.fn.getcwd()
  end

  if not run then
    run = function(cmd, input)
      local res = vim_ref.system(cmd, { text = true, stdin = input }):wait()
      return res.code, res.stdout or "", res.stderr or ""
    end
  end

  local self = {}
  local last_resolution_source = "none"

  function self:in_tmux()
    local env = deps.env or vim_ref.env or {}
    return env.TMUX and env.TMUX ~= ""
  end

  function self:exec(args, input)
    if not self:in_tmux() then
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

  function self:parse_panes(out)
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

  function self:detect_droid_pane_by_cwd()
    local out, err = self:exec({ "list-panes", "-F", pane_format })
    if not out then
      return nil, err
    end
    local panes = self:parse_panes(out)

    local cwd = getcwd()
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

  function self:resolve_droid_pane()
    local by_cwd = self:detect_droid_pane_by_cwd()
    if by_cwd then
      last_resolution_source = "cwd"
      return by_cwd, nil
    end

    last_resolution_source = "none"
    return nil, NO_DROID_ERR
  end

  function self:get_last_resolution_source()
    return last_resolution_source
  end

  function self:focus_pane(pane)
    local ok, select_err = self:exec({ "select-pane", "-t", pane })
    if ok then
      return true, nil
    end
    if is_missing_pane_error(select_err) then
      return nil, STALE_DROID_ERR
    end

    local target, err = self:exec({ "display-message", "-p", "-t", pane, "#{session_name}:#{window_index}" })
    if not target then
      if is_missing_pane_error(err) then
        return nil, STALE_DROID_ERR
      end
      return nil, err or "Could not locate target pane."
    end

    ok, err = self:exec({ "select-window", "-t", target })
    if not ok then
      if is_missing_pane_error(err) then
        return nil, STALE_DROID_ERR
      end
      return nil, err or "Could not select tmux window."
    end

    ok, err = self:exec({ "select-pane", "-t", pane })
    if not ok then
      if is_missing_pane_error(err) then
        return nil, STALE_DROID_ERR
      end
      return nil, err or "Could not select tmux pane."
    end

    return true, nil
  end

  function self:focus()
    local pane, resolve_err = self:resolve_droid_pane()
    if not pane then
      return nil, resolve_err or NO_DROID_ERR
    end

    return self:focus_pane(pane)
  end

  function self:send_text(pane, text, opts)
    opts = opts or {}
    local payload = (text or ""):gsub("\r\n", "\n")
    local ok, err = self:exec({ "load-buffer", "-" }, payload)
    if not ok then
      return nil, err
    end

    ok, err = self:exec({ "paste-buffer", "-p", "-d", "-t", pane })
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
      ok, err = self:exec({ "send-keys", "-t", pane, opts.submit_key })
      if not ok then
        if is_missing_pane_error(err) then
          return nil, STALE_DROID_ERR
        end
        return nil, err
      end
    end

    return true, nil
  end

  return self
end

return M
