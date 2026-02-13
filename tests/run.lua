local test_modules = {
  "tests.tmux_spec",
  "tests.context_spec",
  "tests.send_spec",
}

local function run_case(mod_name, case_name, fn)
  local ok, err = pcall(fn)
  if ok then
    print("PASS " .. mod_name .. "::" .. case_name)
    return true
  end
  io.stderr:write("FAIL " .. mod_name .. "::" .. case_name .. "\n" .. tostring(err) .. "\n")
  return false
end

local function run()
  local total = 0
  local failed = 0

  for _, mod_name in ipairs(test_modules) do
    local mod = require(mod_name)
    for case_name, fn in pairs(mod) do
      if type(fn) == "function" then
        total = total + 1
        if not run_case(mod_name, case_name, fn) then
          failed = failed + 1
        end
      end
    end
  end

  print(string.format("Ran %d tests, %d failed", total, failed))
  if failed > 0 then
    error("test failures: " .. failed)
  end
end

return {
  run = run,
}
