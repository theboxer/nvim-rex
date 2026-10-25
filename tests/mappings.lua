-- Run: nvim --headless -u NONE -i NONE -l tests/mappings.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.env.REX_SESSION, vim.env.REX_BLOCK = "session:test", "block:test"
local plugin = require("rex-splits")
local function mapped(key, mode)
  return vim.fn.maparg(key, mode or "n", false, true)
end
local function absent(key)
  assert(next(mapped(key, "n")) == nil and next(mapped(key, "t")) == nil, "unexpected mapping: " .. key)
end
local function entry_enabled()
  for _, mode in ipairs({ "n", "x", "i", "t" }) do
    assert(next(mapped("<C-M-S-Left>", mode)), "private entry mapping must survive")
  end
end

plugin.setup()
assert(mapped("<C-h>").callback)
plugin.setup({ mappings = { left = "<M-h>", right = "<M-l>" } })
for _, letter in ipairs({ "h", "j", "k", "l" }) do absent("<C-" .. letter .. ">") end
assert(mapped("<M-h>").callback)
assert(mapped("<M-l>", "t").rhs:find("navigate('right')", 1, true))
absent("<M-j>") -- Tables replace defaults; omitted directions stay unbound.
entry_enabled()
plugin.setup({ mappings = false })
absent("<M-h>")
absent("<M-l>")
entry_enabled()
vim.cmd("vsplit")
vim.cmd("wincmd l")
local right = vim.api.nvim_get_current_win()
plugin.navigate("left")
assert(vim.api.nvim_get_current_win() ~= right, "manual navigation must work without mappings")

plugin.setup()
local user_mapping = function() end
vim.keymap.set("n", "<C-h>", user_mapping)
plugin.setup({ mappings = false })
assert(mapped("<C-h>").callback == user_mapping, "setup must preserve user replacements")
vim.keymap.del("n", "<C-h>")
-- Buffer-local mappings must not hide global bindings from cleanup.
vim.keymap.set("n", "<M-h>", user_mapping, { buffer = true })
plugin.setup({ mappings = { left = "<M-h>" } })
plugin.setup({ mappings = false })
vim.keymap.del("n", "<M-h>", { buffer = true })
absent("<M-h>")

for _, mappings in ipairs({ "alt+h", { bogus = "<M-h>" }, { left = "" },
  { left = false }, { left = "<M-h>", right = "<M-h>" }, { left = "<C-M-S-Left>" } }) do
  assert(not pcall(plugin.setup, { mappings = mappings }), "invalid Neovim mappings accepted")
end
vim.env.REX_SESSION = nil
plugin.setup({ mappings = { left = "<M-h>" } })
absent("<M-h>")

local bindings, actions, calls = {}, {}, 0
local process = { foreground = { name = "nvim" } }
_G.rex = {
  bind = function(key, handler) bindings[key] = handler end,
  unbind = function(key, handler)
    if bindings[key] == handler then bindings[key] = nil end
  end,
  action = function(action) actions[action.name] = action.run end,
  log = function() end,
  block = { call = function() return process end },
  session = {
    view = function() return { active_window_id = "window:test", windows = {
      { window_id = "window:test", focused_block_id = "block:test" },
    } } end,
    focus_direction = function(args)
      assert(args.direction == "left")
      calls = calls + 1
      return { moved = false }
    end,
  },
}
local ctx = { session_id = "session:test", block_id = "block:test" }
local companion = dofile("rex/rex-splits.lua")
companion.setup()
assert(type(bindings["ctrl+h"]) == "function")
companion.setup({ mappings = { left = "alt+h" } })
assert(bindings["alt+h"] and not bindings["ctrl+h"] and not bindings["ctrl+j"])
assert(bindings["alt+h"](ctx) == false, "Neovim must receive the original key")
process = nil
assert(bindings["alt+h"](ctx) == false, "unknown processes must receive the key")
assert(calls == 0)
process = { foreground = { name = "zsh" } }
assert(bindings["alt+h"](ctx) == true, "Rex navigation must consume the key")
assert(calls == 1)
companion.setup({ mappings = false })
assert(next(bindings) == nil)
assert(actions.rex_splits_focus, "edge action must remain available")
assert(companion.navigate(ctx, "left") == true, "manual Rex navigation must work")
companion.setup()
bindings["ctrl+h"] = user_mapping
companion.setup({ mappings = false })
assert(bindings["ctrl+h"] == user_mapping, "setup must preserve user Rex bindings")
for _, mappings in ipairs({ "alt+h", { bogus = "alt+h" }, { left = "" },
  { left = false }, { left = "alt+h", right = "alt+h" }, { left = "ctrl+b>h" } }) do
  assert(not pcall(companion.setup, { mappings = mappings }), "invalid Rex mappings accepted")
end
print("PASS: custom/default/disabled mappings, reconfiguration, manual navigation, validation, and passthrough")
