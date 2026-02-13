local M = {}

local function trim(s)
  if type(s) ~= "string" then
    return ""
  end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
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

  local self = {}

  function self:get_current_diff(path)
    local current_path = path or vim_ref.fn.expand("%:p")
    local code, out, err = run({ "git", "diff", "--", current_path })
    if code ~= 0 then
      return nil, (err ~= "" and err or out)
    end
    if trim(out) == "" then
      return nil, ""
    end
    return out, nil
  end

  function self:is_git_ignored(path)
    if path == "" then
      return false
    end

    local dir = vim_ref.fs.dirname(path)
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

  function self:format_diagnostics(diags, limit)
    if #diags == 0 then
      return ""
    end

    local severity_map = {
      [vim_ref.diagnostic.severity.ERROR] = "ERROR",
      [vim_ref.diagnostic.severity.WARN] = "WARN",
      [vim_ref.diagnostic.severity.INFO] = "INFO",
      [vim_ref.diagnostic.severity.HINT] = "HINT",
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

  function self:format_quickfix_items(limit)
    local qf = vim_ref.fn.getqflist({ items = 1 })
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
        filename = vim_ref.api.nvim_buf_get_name(item.bufnr)
      end
      filename = filename or "[no-file]"
      local lnum = item.lnum or 0
      local col = item.col or 0
      local text = (item.text or ""):gsub("\n", " ")
      table.insert(lines, string.format("- %s:%d:%d %s", filename, lnum, col, text))
    end

    return table.concat(lines, "\n")
  end

  function self:get_context_value(name)
    if name == "file" then
      return vim_ref.fn.expand("%:p")
    end
    if name == "diagnostics" then
      return self:format_diagnostics(vim_ref.diagnostic.get(0), 80)
    end
    if name == "diagnostics_all" then
      local parts = {}
      for _, buf in ipairs(vim_ref.api.nvim_list_bufs()) do
        if vim_ref.api.nvim_buf_is_loaded(buf) then
          local path = vim_ref.api.nvim_buf_get_name(buf)
          if not self:is_git_ignored(path) then
            local d = vim_ref.diagnostic.get(buf)
            if #d > 0 then
              table.insert(parts, "File: " .. path)
              table.insert(parts, self:format_diagnostics(d, 80))
            end
          end
        end
      end
      return table.concat(parts, "\n\n")
    end
    if name == "quickfix" then
      return self:format_quickfix_items(100)
    end
    if name == "diff" then
      local diff = self:get_current_diff()
      return diff or ""
    end
    return ""
  end

  function self:expand_template(tpl)
    return (tpl:gsub("{([%w_]+)}", function(key)
      return self:get_context_value(key)
    end))
  end

  return self
end

return M
