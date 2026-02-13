local context_mod = require("droid_tmux.context")

local function make_vim()
  return {
    diagnostic = {
      severity = {
        ERROR = 1,
        WARN = 2,
        INFO = 3,
        HINT = 4,
      },
      get = function(buf)
        if buf == 0 then
          return {
            { severity = 1, lnum = 0, col = 1, message = "bad thing", source = "lua_ls", code = "E1" },
          }
        end
        return {}
      end,
    },
    fn = {
      expand = function()
        return "/repo/file.lua"
      end,
      getqflist = function()
        return { items = {} }
      end,
    },
    fs = {
      dirname = function(path)
        return path:match("(.+)/[^/]+$") or ""
      end,
    },
    api = {
      nvim_buf_get_name = function()
        return "/repo/file.lua"
      end,
      nvim_list_bufs = function()
        return { 1 }
      end,
      nvim_buf_is_loaded = function()
        return true
      end,
    },
  }
end

local function test_format_diagnostics_truncates()
  local client = context_mod.new({
    vim = make_vim(),
    run = function()
      return 0, "", ""
    end,
  })

  local out = client:format_diagnostics({
    { severity = 1, lnum = 0, col = 0, message = "m1" },
    { severity = 2, lnum = 1, col = 0, message = "m2" },
  }, 1)

  assert(out:find("%[ERROR%] 1:1 m1", 1, false), "expected first diagnostic line")
  assert(out:find("%.%.%. truncated %.%.%.", 1, false), "expected truncation marker")
end

local function test_expand_template_file_and_unknown()
  local client = context_mod.new({
    vim = make_vim(),
    run = function(cmd)
      if cmd[1] == "git" and cmd[2] == "diff" then
        return 0, "diff --git a/file b/file\n", ""
      end
      return 1, "", "unexpected command"
    end,
  })

  local out = client:expand_template("File={file};Unknown={missing};Diff={diff}")
  assert(out:find("File=/repo/file.lua", 1, true), "expected file variable")
  assert(out:find("Unknown=", 1, true), "expected empty missing variable")
  assert(out:find("Diff=diff --git", 1, true), "expected diff variable")
end

return {
  test_format_diagnostics_truncates = test_format_diagnostics_truncates,
  test_expand_template_file_and_unknown = test_expand_template_file_and_unknown,
}
