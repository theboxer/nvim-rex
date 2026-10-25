-- Three Rex panes: [ Neovim left | Neovim right ] [ shell ] [ shell ].
-- Neovim windows and key maps are real; Rex session state and transport are simulated.
local root = vim.fn.getcwd()
vim.opt.rtp:prepend(root)
vim.env.REX_SESSION, vim.env.REX_BLOCK = "session:test", "block:editor"
local actions, bindings = {}, {}
local custom = arg[1] == "alt"
local modifier, notation = custom and "alt" or "ctrl", custom and "M" or "C"
local rex_mappings, nvim_mappings = {}, {}
for letter, direction in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
  rex_mappings[direction] = modifier .. "+" .. letter
  nvim_mappings[direction] = "<" .. notation .. "-" .. letter .. ">"
end
local panes = { "block:editor", "block:middle", "block:last" }
local index = 1
local function feed(notation)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(notation, true, false, true), "xt", false)
end
local arrow_keys = {
  ["\27[1;8D"] = "<C-M-S-Left>", ["\27[1;8C"] = "<C-M-S-Right>",
  ["\27[1;8A"] = "<C-M-S-Up>", ["\27[1;8B"] = "<C-M-S-Down>",
}
local function context()
  return { session_id = "session:test", block_id = panes[index], client_id = "client:test" }
end
_G.rex = {
  action = function(action) actions[action.name] = action.run end,
  bind = function(key, action) bindings[key] = action end,
  log = function() end,
  block = { call = function(_, method, args)
    if method == "process" then
      return { foreground = { name = args.block_id == panes[1] and "nvim" or "zsh" } }
    end
    assert(method == "write", "unexpected terminal method: " .. method)
    assert(args.block_id == panes[1], "entry keys must only go to Neovim")
    feed(assert(arrow_keys[args.data], "unknown entry key"))
    return {}
  end },
  session = {
    view = function()
      return { active_window_id = "window:test", windows = {
        { window_id = "window:test", focused_block_id = panes[index] },
      } }
    end,
    focus_direction = function(args)
      local next_index = index + ((args.direction == "right" or args.direction == "down") and 1 or -1)
      if args.wrap then next_index = (next_index - 1) % #panes + 1 end
      if panes[next_index] then index = next_index end
      return {}
    end,
  },
}
dofile(root .. "/rex/rex-splits.lua").setup({ mappings = custom and rex_mappings or nil })
vim.system = function(argv, _, callback)
  local origin = { session_id = vim.env.REX_SESSION, block_id = vim.env.REX_BLOCK }
  local direction = assert(table.concat(argv, " "):match("direction=(%a+)"))
  actions.rex_splits_focus(origin, { direction = direction, wrap = true })
  callback({ code = 0, stderr = "" })
  return {}
end
require("rex-splits").setup({ rex_bin = "/test/rex", mappings = custom and nvim_mappings or nil })
local function press(letter)
  local key = modifier .. "+" .. letter
  if not bindings[key](context(), { keybinding = key }) then
    feed("<" .. notation .. "-" .. letter .. ">")
  end
  vim.wait(5, function() return false end)
end
local function expect(pane, window, message)
  assert(index == pane, message .. ": expected Rex pane " .. pane .. ", got " .. index)
  if window then
    assert(vim.api.nvim_get_current_win() == window, message .. ": wrong Neovim window")
  end
end

vim.cmd("vsplit")
vim.cmd("wincmd h")
local left = vim.api.nvim_get_current_win()
vim.cmd("wincmd l")
local right = vim.api.nvim_get_current_win()
-- Exactly the reported state: the editor remembers its rightmost window.
index = 3
press("l")
expect(1, left, "rightmost Rex pane must wrap to leftmost Neovim window")
press("h")
expect(3, nil, "leftmost Neovim window must wrap to rightmost Rex pane")
press("h")
expect(2, nil, "left into middle Rex pane")
press("h")
expect(1, right, "entering Neovim from the right must choose its rightmost window")
press("h")
expect(1, left, "next left stays inside Neovim")
press("l")
expect(1, right, "next right stays inside Neovim")
press("l")
expect(2, nil, "exit Neovim to middle Rex pane")
press("l")
expect(3, nil, "right into last Rex pane")
press("l")
expect(1, left, "complete rightward cycle")
-- No cross-pane movement with wrap disabled must preserve the current window.
actions.rex_splits_focus(context(), { direction = "left", wrap = false })
expect(1, left, "wrap=false stops at the layout edge")
-- A single Rex pane still needs to wrap between its own Neovim windows.
panes = { "block:editor" }
vim.api.nvim_set_current_win(right)
press("l")
expect(1, left, "single Rex pane wraps to first Neovim window")
press("h")
expect(1, right, "single Rex pane wraps to last Neovim window")
print("PASS (" .. modifier .. "): both directions cycle through two Neovim windows and three Rex panes")
