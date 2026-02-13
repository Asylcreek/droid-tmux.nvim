local M = {}

local pane_format = "#{pane_id}\t#{session_name}:#{window_index}.#{pane_index}\t"
  .. "#{pane_current_command}\t#{pane_title}\t#{pane_current_path}"

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

function M.new(deps)
  deps = deps or {}
  local vim_ref = deps.vim or vim
  local run = deps.run
  local notify = deps.notify or (vim_ref and vim_ref.notify) or function() end
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
    return panes
  end

  function self:get_saved_pane()
    local out = self:exec({ "show-options", "-gqv", "@droid_pane" })
    if not out or out == "" then
      return nil
    end
    return out
  end

  function self:save_pane(pane_id)
    self:exec({ "set", "-g", "@droid_pane", pane_id })
  end

  function self:list_panes_all()
    local out, err = self:exec({ "list-panes", "-a", "-F", pane_format })
    if not out then
      return nil, err
    end
    return self:parse_panes(out), nil
  end

  function self:list_panes_current_window()
    local out, err = self:exec({ "list-panes", "-F", pane_format })
    if not out then
      return nil, err
    end
    return self:parse_panes(out), nil
  end

  function self:pane_exists_in_current_window(pane_id)
    local panes = self:list_panes_current_window()
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

  function self:detect_droid_pane_in_current_window()
    local out, err = self:exec({
      "list-panes",
      "-F",
      "#{pane_id}\t#{pane_current_command}\t#{pane_title}",
    })
    if not out then
      return nil, err
    end

    local title_match = nil
    for _, line in ipairs(split_lines(out)) do
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

  function self:detect_droid_pane_by_cwd()
    local panes, err = self:list_panes_current_window()
    if not panes then
      return nil, err
    end

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
    local saved = self:get_saved_pane()
    if saved and self:pane_exists_in_current_window(saved) then
      last_resolution_source = "saved"
      return saved
    end

    local by_cwd = self:detect_droid_pane_by_cwd()
    if by_cwd then
      self:save_pane(by_cwd)
      last_resolution_source = "cwd"
      return by_cwd
    end

    local detected = self:detect_droid_pane_in_current_window()
    if detected then
      self:save_pane(detected)
      last_resolution_source = "detect"
      return detected
    end

    last_resolution_source = "none"
    notify("Could not resolve Droid pane in current tmux window.", vim_ref.log.levels.ERROR)
    return nil
  end

  function self:get_last_resolution_source()
    return last_resolution_source
  end

  function self:focus()
    local pane = self:resolve_droid_pane()
    if not pane then
      return
    end

    local ok = self:exec({ "select-pane", "-t", pane })
    if ok then
      return
    end

    local target, err = self:exec({ "display-message", "-p", "-t", pane, "#{session_name}:#{window_index}" })
    if not target then
      notify(err or "Could not locate target pane.", vim_ref.log.levels.ERROR)
      return
    end

    self:exec({ "select-window", "-t", target })
    self:exec({ "select-pane", "-t", pane })
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
      return nil, err
    end

    if opts.submit_delay_ms and opts.submit_delay_ms > 0 and vim_ref.wait then
      vim_ref.wait(opts.submit_delay_ms)
    end

    if opts.submit_key and opts.submit_key ~= "" then
      ok, err = self:exec({ "send-keys", "-t", pane, opts.submit_key })
      if not ok then
        return nil, err
      end
    end

    return true, nil
  end

  return self
end

return M
