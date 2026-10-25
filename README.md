# nvim-rex

Navigate Neovim windows and [Rex](https://www.superlogical.com/rex/docs) panes
with `Ctrl+h/j/k/l`. At a Neovim window edge, navigation continues in Rex.
Entering Neovim selects the opposite window edge. Wrapping is enabled by default.

Requires **Neovim 0.10+**, the Rex CLI, and Rex's Lua configuration API.
Install both components below.
Tested with Rex `0.0.1792787366-g623b2d` (API 7).

## 1. Install in Neovim

Choose one package manager. Run setup after your default window mappings.
Mappings activate only inside Rex, when
`REX_SESSION` and `REX_BLOCK` are set.

### lazy.nvim / LazyVim

Add this spec to `lazy.setup()`, or save it as `lua/plugins/nvim-rex.lua` in
LazyVim. See also [examples/lazy.lua](examples/lazy.lua).

```lua
return {
  {
    "theboxer/nvim-rex",
    main = "rex-splits",
    event = "VeryLazy",
    cond = function()
      return vim.env.REX_SESSION ~= nil and vim.env.REX_SESSION ~= ""
        and vim.env.REX_BLOCK ~= nil and vim.env.REX_BLOCK ~= ""
    end,
    opts = {},
    keys = {
      { "<C-h>", function() require("rex-splits").navigate("h") end, desc = "Navigate left (Neovim/Rex)" },
      { "<C-j>", function() require("rex-splits").navigate("j") end, desc = "Navigate down (Neovim/Rex)" },
      { "<C-k>", function() require("rex-splits").navigate("k") end, desc = "Navigate up (Neovim/Rex)" },
      { "<C-l>", function() require("rex-splits").navigate("l") end, desc = "Navigate right (Neovim/Rex)" },
    },
  },
}
```

`main` selects the `rex-splits` module; `opts = {}` calls setup with defaults.
`keys` prevents LazyVim from overriding the mappings. Run `:Lazy sync` and
restart Neovim.

### vim-plug

Inside your existing `plug#begin()` / `plug#end()` block:

```vim
Plug 'theboxer/nvim-rex'
```

After `plug#end()` and your other keymaps:

```vim
lua require('rex-splits').setup()
```

Run `:PlugInstall` and restart Neovim.

### packer.nvim

```lua
use {
  "theboxer/nvim-rex",
  config = function()
    require("rex-splits").setup()
  end,
}
```

Run `:PackerSync` and restart Neovim.

### mini.deps

```lua
MiniDeps.add({ source = "theboxer/nvim-rex" })
require("rex-splits").setup()
```

### vim.pack (Neovim 0.12+)

```lua
vim.pack.add({ "https://github.com/theboxer/nvim-rex" })
require("rex-splits").setup()
```

## 2. Configure Rex

Load the companion from the **same checkout** as the Neovim plugin.
After the plugin loads, find its path in Neovim:

```vim
:lua print(vim.api.nvim_get_runtime_file("rex/rex-splits.lua", false)[1])
```

Add that path to Rex's `~/.config/rex/init.lua`, replacing existing direct
`Ctrl+h/j/k/l` pane-focus bindings:

```lua
dofile("/absolute/path/to/nvim-rex/rex/rex-splits.lua").setup()
```

For lazy.nvim this is normally
`~/.local/share/nvim/lazy/nvim-rex/rex/rex-splits.lua`. Use an absolute path:
Lua's `dofile` does not expand `~`.

```sh
rex config check
rex config reload
```

Restart Neovim. Reload Rex and restart Neovim after plugin updates.
If the Rex CLI is not on `PATH`, use its full path; on macOS Beta:
`/Applications/Rex Beta.app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex`.

## Configuration

Both components accept `setup()` without arguments. Neovim options:

| Option | Default | Description |
| --- | --- | --- |
| `wrap` | `true` | Wrap at outer edges. |
| `timeout` | `1000` | Rex CLI timeout in milliseconds. |
| `mappings` | `true` | Default Ctrl bindings; a table sets custom keys, `false` disables bindings. |
| `rex_bin` | auto-detected | Rex CLI path; searches `PATH`, then macOS app bundles. |

Rex accepts `wrap` and `mappings`, both defaulting to `true`. Neovim installs
navigation mappings in normal and terminal modes. To disable wrapping, use
`setup({ wrap = false })` on both sides.

### Custom mappings

Set matching shortcuts on both sides. Rex passes the original key to Neovim
when it is focused; Neovim handles its windows and calls Rex at an edge.

To replace `Ctrl+h/j/k/l` with `Alt+h/j/k/l`, update the existing setup calls:

**Neovim** (`init.lua` or your plugin configuration):

```lua
require("rex-splits").setup({
  mappings = {
    left = "<M-h>", down = "<M-j>", up = "<M-k>", right = "<M-l>",
  },
})
```

For lazy.nvim / LazyVim, set `opts.mappings` and update `keys` to match.
[examples/lazy-custom.lua](examples/lazy-custom.lua) provides the complete spec
with both generated from one mapping table.

**Rex** (`~/.config/rex/init.lua`):

```lua
dofile("/absolute/path/to/nvim-rex/rex/rex-splits.lua").setup({
  mappings = {
    left = "alt+h", down = "alt+j", up = "alt+k", right = "alt+l",
  },
})
```

A table replaces the default bindings; omitted directions stay unbound. Rex
mappings must be single shortcuts, without key sequences or modes.
Remove old `rex.bind(..., "rex_splits_left")` bindings (and the other directions);
the directional actions have been replaced by these function bindings.

Run `rex config check`, `rex config reload`, and restart Neovim.

For manual bindings, set `mappings = false`. In Neovim, call
`require("rex-splits").navigate("left")`. In Rex, return
`companion.navigate(ctx, "left")` from a `rex.bind` function, where `companion`
is the table returned by `dofile`. Both accept `h/j/k/l` or `left/down/up/right`.

## Behavior and conflicts

The entry protocol reserves `Ctrl+Alt+Shift+Left/Right/Up/Down` in Neovim,
including when `mappings = false`. Terminal navigation exits terminal-input
mode. All ordinary splits participate, including sidebars; floats follow
`wincmd`. Detection requires a foreground process named `nvim` or `nvim.exe`.
Plain SSH/nested tmux, resizing, and automatic unzoom are not implemented.

Disable other navigation plugins inside Rex.
Rex shortcuts configured in its app UI take priority over `init.lua`; remove
conflicting UI bindings. Check `rex keymap` and `:verbose nmap <C-l>` for
key conflicts.

## Local development and tests

With lazy.nvim, replace `"theboxer/nvim-rex"` in the spec with
`dir = "/absolute/path/to/nvim-rex"`. Point Rex's `dofile` at that checkout too.

From the repository root:

```sh
nvim --headless -u NONE -i NONE -l tests/navigation.lua
nvim --headless -u NONE -i NONE -l tests/navigation.lua alt
nvim --headless -u NONE -i NONE -l tests/wrap.lua
nvim --headless -u NONE -i NONE -l tests/wrap.lua alt
nvim --headless -u NONE -i NONE -l tests/mappings.lua
python3 tests/terminal-entry.py
nvim --headless -u NONE -i NONE -l tests/lazy.lua
nvim --headless -u NONE -i NONE -l tests/lazy.lua alt
```

Navigation/wrap tests simulate Rex I/O; the terminal test uses a real Neovim
PTY. The LazyVim test needs locally installed lazy.nvim, LazyVim, and snacks.nvim; set
`REX_SPLITS_LAZY_ROOT` to their parent directory if it differs from
`stdpath("data") .. "/lazy"`. For a live check, cycle both directions through
two Neovim splits and two adjacent Rex shell panes.

References: [Rex Lua API](https://www.superlogical.com/rex/docs/reference/lua),
[lazy.nvim](https://lazy.folke.io/spec),
[vim-plug](https://github.com/junegunn/vim-plug),
[packer.nvim](https://github.com/wbthomason/packer.nvim),
[mini.deps](https://nvim-mini.org/mini.nvim/doc/mini-deps.html),
[vim.pack](https://neovim.io/doc/user/pack.html).
