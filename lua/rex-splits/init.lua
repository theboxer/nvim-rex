local M = {}
local directions = { h = "left", j = "down", k = "up", l = "right" }
local options = { wrap = true, timeout = 1000 }
local pending = false
local installed_mappings = {}

local function navigation_mappings(value)
  if value == false then return {} end
  if value == nil or value == true then
    return { left = "<C-h>", down = "<C-j>", up = "<C-k>", right = "<C-l>" }
  end
  assert(type(value) == "table", "rex-splits: mappings must be a boolean or a direction-to-key table")
  local seen = {}
  for direction, key in pairs(value) do
    assert(vim.tbl_contains(vim.tbl_values(directions), direction), "rex-splits: invalid mapping direction: " .. tostring(direction))
    assert(type(key) == "string" and key ~= "", "rex-splits: mapping keys must be non-empty strings")
    local encoded = vim.api.nvim_replace_termcodes(key, true, true, true)
    for _, name in pairs(directions) do
      local entry = "<C-M-S-" .. name:sub(1, 1):upper() .. name:sub(2) .. ">"
      assert(encoded ~= vim.api.nvim_replace_termcodes(entry, true, true, true),
        "rex-splits: mapping key is reserved for entry: " .. key)
    end
    assert(not seen[encoded], "rex-splits: duplicate mapping key: " .. key)
    seen[encoded] = true
  end
  return value
end

local function clear_mappings()
  for _, mapping in ipairs(installed_mappings) do
    -- Preserve any mapping the user replaced after setup.
    for _, current in ipairs(vim.api.nvim_get_keymap(mapping.mode)) do
      if current.lhs == mapping.lhs and current.callback == mapping.callback and current.rhs == mapping.rhs then
        vim.keymap.del(mapping.mode, current.lhs)
        break
      end
    end
  end
  installed_mappings = {}
end

local function rex_binary()
  if options.rex_bin then
    return options.rex_bin
  end
  local path = vim.fn.exepath("rex")
  if path ~= "" then
    return path
  end
  -- Rex's macOS app may be installed without its CLI on PATH.
  for _, app in ipairs({ "Rex Beta", "Rex" }) do
    path = "/Applications/" .. app .. ".app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex"
    if vim.fn.executable(path) == 1 then
      return path
    end
  end
end

function M.in_rex()
  return vim.env.REX_SESSION ~= nil and vim.env.REX_SESSION ~= ""
    and vim.env.REX_BLOCK ~= nil and vim.env.REX_BLOCK ~= ""
end

-- Called only by the Rex entry key. Never hand this back to Rex: choosing the
-- first window inside the destination pane is part of the original movement.
function M.enter(direction)
  local opposite = { left = "l", right = "h", up = "j", down = "k" }
  local letter = assert(opposite[direction], "rex-splits: invalid entry direction")
  for _ = 1, #vim.api.nvim_tabpage_list_wins(0) do
    local before = vim.api.nvim_get_current_win()
    vim.cmd("wincmd " .. letter)
    if vim.api.nvim_get_current_win() == before then break end
  end
end

function M.navigate(direction)
  local letter = directions[direction] and direction or nil
  for candidate, name in pairs(directions) do
    if direction == name then letter = candidate end
  end
  assert(letter, "rex-splits: invalid direction: " .. tostring(direction))

  local before = vim.api.nvim_get_current_win()
  vim.cmd("wincmd " .. letter)
  if vim.api.nvim_get_current_win() ~= before then
    return
  end
  if not M.in_rex() or pending then
    return
  end
  local binary = rex_binary()
  if not binary then
    vim.notify("rex-splits: Rex CLI not found; set rex_bin in setup()", vim.log.levels.ERROR)
    return
  end

  -- Call the edge action directly; it must not pass the key back to Neovim.
  -- Never invoke a shell.
  local argv = {
    binary, "--autostart=false", "--timeout", tostring(options.timeout) .. "ms",
    "do", "-s", vim.env.REX_SESSION, "-b", vim.env.REX_BLOCK,
    "rex_splits_focus", "direction=" .. directions[letter], "wrap=" .. tostring(options.wrap),
  }
  pending = true
  local ok, err = pcall(vim.system, argv, { text = true, timeout = options.timeout + 250 }, function(result)
    vim.schedule(function()
      pending = false
      if result.code ~= 0 then
        local detail = vim.trim(result.stderr or "")
        if detail == "" then detail = "Rex exited with status " .. result.code end
        vim.notify("rex-splits: " .. detail, vim.log.levels.ERROR)
      end
    end)
  end)
  if not ok then
    pending = false
    vim.notify("rex-splits: " .. tostring(err), vim.log.levels.ERROR)
  end
end

function M.setup(opts)
  local configured = vim.tbl_extend("force", { wrap = true, timeout = 1000 }, opts or {})
  assert(type(configured.timeout) == "number" and configured.timeout > 0, "rex-splits: timeout must be positive")
  assert(type(configured.wrap) == "boolean", "rex-splits: wrap must be boolean")
  local mappings = navigation_mappings(configured.mappings)
  options = configured
  clear_mappings()
  if not M.in_rex() then return end
  -- Keep the private transport mappings even when users supply their own
  -- navigation keys with mappings=false. They never invoke the CLI.
  for _, direction in pairs(directions) do
    local target = direction
    local arrow = direction:sub(1, 1):upper() .. direction:sub(2)
    local key = "<C-M-S-" .. arrow .. ">"
    vim.keymap.set({ "n", "x", "i" }, key, function()
      M.enter(target)
    end, { desc = "Enter Neovim from Rex (" .. direction .. ")" })
    vim.keymap.set("t", key,
      "<C-\\><C-n><Cmd>lua require('rex-splits').enter('" .. direction .. "')<CR>",
      { desc = "Enter Neovim from Rex (" .. direction .. ")" })
  end
  for direction, key in pairs(mappings) do
    local target = direction
    vim.keymap.set("n", key, function()
      M.navigate(target)
    end, { desc = "Navigate " .. direction .. " (Neovim/Rex)" })
    vim.keymap.set("t", key,
      "<C-\\><C-n><Cmd>lua require('rex-splits').navigate('" .. direction .. "')<CR>",
      { desc = "Navigate " .. direction .. " (Neovim/Rex)" })
    for _, mode in ipairs({ "n", "t" }) do
      local encoded = vim.api.nvim_replace_termcodes(key, true, true, true)
      for _, mapping in ipairs(vim.api.nvim_get_keymap(mode)) do
        if vim.api.nvim_replace_termcodes(mapping.lhs, true, true, true) == encoded then
          mapping.mode = mode
          installed_mappings[#installed_mappings + 1] = mapping
          break
        end
      end
    end
  end
end

return M
