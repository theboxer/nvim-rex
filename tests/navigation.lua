-- Run from the plugin root with nvim --headless -u NONE -i NONE -l tests/navigation.lua.
local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
vim.env.REX_SESSION, vim.env.REX_BLOCK = "session:test", "block:editor"
local actions, bindings, forwarded, requests = {}, {}, {}, {}
local custom = arg[1] == "alt"
local modifier, notation = custom and "alt" or "ctrl", custom and "M" or "C"
local rex_mappings, nvim_mappings = {}, {}
for letter, direction in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
  rex_mappings[direction] = modifier .. "+" .. letter
  nvim_mappings[direction] = "<" .. notation .. "-" .. letter .. ">"
end
local focused, active = "block:editor", "window:test"
local process = { foreground = { name = "nvim" }, child = { name = "zsh" } }
local focus_calls, fail_focus, cli_callback = 0, false, nil
local hold_cli, fail_cli = false, false
local notifications = {}
vim.notify = function(message) notifications[#notifications + 1] = message end
local function eq(actual, expected, message)
  assert(vim.deep_equal(actual, expected), (message or "values differ")
    .. "\nexpected " .. vim.inspect(expected) .. "\nactual " .. vim.inspect(actual))
end
local ctx = { session_id = "session:test", block_id = "block:editor", client_id = "client:test" }
_G.rex = {
  action = function(action) actions[action.name] = action.run end,
  bind = function(key, handler) bindings[key] = handler end,
  unbind = function(key, handler)
    if bindings[key] == handler then bindings[key] = nil end
  end,
  log = function() end,
  block = { call = function(creator, method, args)
    eq(creator, "com.superlogical.terminal")
    if method == "write" then
      local arrows = {
        ["\27[1;8D"] = "Left", ["\27[1;8C"] = "Right",
        ["\27[1;8A"] = "Up", ["\27[1;8B"] = "Down",
      }
      local key = "<C-M-S-" .. assert(arrows[args.data]) .. ">"
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(key, true, false, true), "xt", false)
      return {}
    end
    eq(method, "process")
    eq(args, { session_id = ctx.session_id, block_id = ctx.block_id })
    return process, process == nil and "unavailable" or nil
  end },
  session = {
    view = function()
      return { active_window_id = active, windows = {
        { window_id = "window:test", focused_block_id = focused },
        { window_id = "window:other", focused_block_id = "block:other" },
      } }
    end,
    focus_direction = function(args)
      if fail_focus then return nil, "focus failed" end
      eq(args.session_id, ctx.session_id)
      focus_calls = focus_calls + 1
      requests[#requests + 1] = args
      return { moved = true }
    end,
  },
}
local companion = dofile(root .. "/rex/rex-splits.lua")
companion.setup({ mappings = custom and rex_mappings or nil })
local cli_calls = 0
vim.system = function(argv, opts, callback)
  cli_calls = cli_calls + 1
  eq(vim.list_slice(argv, 2, 10), {
    "--autostart=false", "--timeout", "1000ms", "do", "-s", ctx.session_id, "-b", ctx.block_id, "rex_splits_focus",
  })
  eq(opts.timeout, 1250)
  local direction = assert(argv[11]:match("^direction=(%a+)$"))
  local wrap = argv[12] == "wrap=true"
  cli_callback = function()
    local ok, err = pcall(actions.rex_splits_focus, ctx, { direction = direction, wrap = wrap })
    callback({ code = (ok and not fail_cli) and 0 or 1, stderr = ok and (fail_cli and "CLI unavailable" or "") or tostring(err) })
  end
  if not hold_cli then cli_callback() end
  return {}
end
local plugin = require("rex-splits")
plugin.setup({ rex_bin = "/test/rex", mappings = custom and nvim_mappings or nil })
local function flush() vim.wait(10, function() return false end) end
local function press(letter)
  local key = modifier .. "+" .. letter
  local handled = bindings[key](ctx, { keybinding = key })
  assert(type(handled) == "boolean", "Rex handler must return handled status")
  if not handled then
    forwarded[#forwarded + 1] = key
    -- Model Rex passthrough: deliver the pressed key unchanged.
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<" .. notation .. "-" .. letter .. ">", true, false, true), "xt", false)
  end
  flush()
end

-- Actual Neovim windows and mapped keys, with only Rex I/O simulated.
for _, case in ipairs({ { "l", "vsplit", "h" }, { "h", "vsplit", "l" },
    { "j", "split", "k" }, { "k", "split", "j" } }) do
  vim.cmd("only!")
  vim.cmd(case[2])
  vim.cmd("wincmd " .. case[3])
  local start, count = vim.api.nvim_get_current_win(), focus_calls
  press(case[1])
  assert(vim.api.nvim_get_current_win() ~= start, "key must move inside Neovim first")
  eq(focus_calls, count, "internal move must not leave Neovim")
  press(case[1])
  eq(focus_calls, count + 1, "edge must hand off to Rex exactly once")
  eq(requests[#requests].wrap, true)
end

vim.cmd("only!")
-- Return to editor, shell, and back; no persistent active-editor flag.
process = { foreground = { name = "zsh" }, child = { name = "nvim" } }
local count, sent = focus_calls, #forwarded
press("h")
eq(focus_calls, count + 1, "suspended Neovim must not steal shell navigation")
eq(#forwarded, sent)
process = { child = { name = "/opt/homebrew/bin/nvim" } }
press("h")
eq(#forwarded, sent + 1, "directly launched Neovim must receive key")

-- An edge request arriving after a focus change must not move another pane.
process = { foreground = { name = "nvim" } }
count = focus_calls
focused = "block:other"
press("l")
eq(focus_calls, count)
focused, active = ctx.block_id, "window:other"
press("l")
eq(focus_calls, count)
active = "window:test"

-- Ignore auto-repeat while the edge handoff is in flight, then recover.
hold_cli = true
local calls = cli_calls
press("l")
press("l")
eq(cli_calls, calls + 1)
cli_callback()
flush()
hold_cli = false
press("l")
eq(cli_calls, calls + 2)

fail_focus = true
press("l")
assert(notifications[#notifications]:find("focus failed", 1, true))
fail_focus, fail_cli = false, true
press("l")
assert(notifications[#notifications]:find("CLI unavailable", 1, true))
fail_cli = false
count = focus_calls
press("l")
eq(focus_calls, count + 1, "failed command must release pending lock")

plugin.setup({ wrap = false, mappings = custom and nvim_mappings or nil })
press("l")
eq(requests[#requests].wrap, false)
local ok = pcall(plugin.navigate, "bogus")
eq(ok, false)
ok = pcall(actions.rex_splits_focus, ctx, { direction = "bogus" })
eq(ok, false)
vim.env.REX_SESSION = nil
calls = cli_calls
plugin.navigate("h")
eq(cli_calls, calls, "outside Rex, no CLI should run")

-- The public installation spec only enables the plugin inside Rex.
vim.env.REX_SESSION, vim.env.HERDR_ENV = ctx.session_id, "1"
local spec = dofile(root .. "/examples/lazy.lua")
eq(spec[1][1], "theboxer/nvim-rex")
eq(spec[1].main, "rex-splits")
eq(spec[1].cond(), true)
vim.env.REX_SESSION = nil
spec = dofile(root .. "/examples/lazy.lua")
eq(spec[1].cond(), false)
eq(#spec, 1)
print("PASS (" .. modifier .. "): four-direction window/edge navigation, process routing, stale focus, repeat, errors, wrap, and Rex scoping")
