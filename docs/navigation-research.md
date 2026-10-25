# Navigation mappings: Herdr, tmux, and Rex

Research date: 2026-10-25. The recommendation below is now implemented; see
[configuration](../README.md#custom-mappings) for the supported interface.

## Findings

The common contract is: configure the same shortcut in the editor and terminal;
the terminal lets the editor handle it when the editor is focused; the editor
requests terminal navigation only at a window edge. Implementations differ in
how they deliver the key and detect the editor.

| Implementation | When Neovim is focused | Custom mappings |
| --- | --- | --- |
| herdr-splits.nvim | Replays a configured chord through Herdr's CLI. | Neovim mapping, Herdr binding, and configured forwarding chord must agree. |
| vim-tmux-navigator | Replays the bound key with `send-keys`. | Matching editor mappings and tmux keys. |
| smart-splits.nvim + tmux backend | Replays the bound key when a pane flag identifies Neovim. | Matching editor mappings and tmux keys. |
| smart-splits.nvim + Rex backend | Returns `false` from a Rex function binding, allowing native passthrough. | Matching editor mappings and Rex bindings. |
| nvim-rex before this change | Replays fixed `Ctrl+h/j/k/l`, regardless of the triggering binding. | Rex aliases work, but do not replace the forwarded Ctrl keys. |

Sources and qualifications for each row follow.

## Herdr

The installed plugin is `lmilojevicc/herdr-splits.nvim`, local revision
`94f30cf4e9ac76ddf185a3acd0977be728fa4106`. Its public source confirms that
the navigation script selects a default chord for the direction, replaces it
with a configured `nav_key_*` value when present, and calls `herdr pane send-keys`
when the foreground process is Vim/Neovim. It does not have to forward Ctrl.
[Navigation script](https://github.com/lmilojevicc/herdr-splits.nvim/blob/main/scripts/herdr-nav.sh).

Neovim `setup({ nav_keys = ... })` converts Neovim notation to Herdr notation
and publishes the forwarding configuration to a generated file. This configures
the replayed keys; users still define their Neovim mappings and Herdr trigger
bindings. The README warns that setup must run before custom keys are needed,
because the generated forwarding configuration otherwise does not exist yet.
[Configuration implementation](https://github.com/lmilojevicc/herdr-splits.nvim/blob/main/lua/herdr-splits/config.lua),
[notation and file handling](https://github.com/lmilojevicc/herdr-splits.nvim/blob/main/lua/herdr-splits/conf.lua),
[custom key documentation](https://github.com/lmilojevicc/herdr-splits.nvim#auto-unzoom-and-wrap-around).

Assessment: configurable forwarding is better than nvim-rex's fixed Ctrl keys,
but generated configuration introduces extra state, startup ordering, and a
third place where keys must agree. Rex's native passthrough can avoid that.

## vim-tmux-navigator

The README explicitly requires custom bindings in both Vim and tmux.
`tmux_navigator_no_mappings` disables the Vim defaults so users can map the
directional commands themselves.
[Custom bindings](https://github.com/christoomey/vim-tmux-navigator#custom-key-bindings).

The TPM script uses one key variable for both the tmux binding and `send-keys`.
Its `@vim_navigator_mapping_left/down/up/right` options therefore change the
trigger and replay together. Foreground process detection chooses between
replaying the key and moving a tmux pane.
[TPM implementation](https://github.com/christoomey/vim-tmux-navigator/blob/master/vim-tmux-navigator.tmux).

Assessment: matching mappings on both sides are an established configuration
model. A custom terminal key should not silently require an unrelated default
editor mapping.

## smart-splits.nvim

Current upstream is under `smart-splits-nvim`, with v3 separating multiplexer
backends into their own plugins. Core requires Neovim 0.11+, exposes directional
Lua functions and commands, and installs no mappings automatically.
[Core documentation](https://github.com/smart-splits-nvim/smart-splits.nvim#keybindings).

The tmux backend maintains `@pane-is-vim` while Neovim owns the pane. Its
documented bindings send the same key to Neovim or move the tmux pane, depending
on that flag. TPM options customize movement keys; configuration must be ready
before those keys are used. This avoids foreground process inspection per key
but adds lifecycle state and an eager-loading requirement.
[Tmux backend](https://github.com/smart-splits-nvim/backend-tmux#tmux).

There is also an existing community
[Rex backend](https://github.com/rawnly/smart-splits-backend-rex), inspected at
commit `464432c443cd2252d37df91664f9d9f4680d044d`. Its documented Rex navigation
bindings return `false` when Neovim is focused, passing the original key through.
No replay configuration is needed for navigation. Installation uses smart-splits
core, this backend, editor keymaps, and Rex function bindings.
[Rex backend setup](https://github.com/rawnly/smart-splits-backend-rex/blob/464432c443cd2252d37df91664f9d9f4680d044d/README.md).

That backend invokes `rex do -e` with an inline focus script and compares session
revisions to determine whether focus moved. Its focus implementation does not
send a destination-entry signal to select the opposite Neovim window edge.
It is therefore not an exact replacement for nvim-rex's current entry behavior.
The backend was inspected, not installed or tested live. Its README also has an
installation repository-name typo, so copying the example needs care.
[Focus implementation](https://github.com/rawnly/smart-splits-backend-rex/blob/464432c443cd2252d37df91664f9d9f4680d044d/lua/smart-splits-backend-rex/rex.lua),
[movement implementation](https://github.com/rawnly/smart-splits-backend-rex/blob/464432c443cd2252d37df91664f9d9f4680d044d/lua/smart-splits-backend-rex/move.lua).

## Recommendation for nvim-rex

Use native Rex passthrough for navigation. Rex documents that a function binding
returning `false` or nil tries older function bindings and, if none handle the
key, sends it to the terminal. This preserves the pressed key and avoids a
forwarding-key option, notation conversion, and generated configuration.
Older handlers and app-level shortcut precedence still matter.
[Rex binding semantics](https://www.superlogical.com/rex/docs/customize/keyboard-shortcuts#binding-a-lua-function).

Keep the public model small:

1. `setup()` enables the default Ctrl mappings on each side.
2. A mapping table replaces those defaults with matching shortcuts on both sides,
   using each application's native notation: `<M-h>` in Neovim, `alt+h` in Rex.
3. `mappings = false` disables automatic user-facing bindings for manual setups.
4. Keep `navigate(direction)` separate from mapping installation.

Neovim configuration:

```lua
require("rex-splits").setup({ mappings = {
  left = "<M-h>", down = "<M-j>", up = "<M-k>", right = "<M-l>",
} })
```

Rex configuration:

```lua
dofile("/absolute/path/to/nvim-rex/rex/rex-splits.lua").setup({ mappings = {
  left = "alt+h", down = "alt+j", up = "alt+k", right = "alt+l",
} })
```

Rex passes Alt through unchanged to Neovim; the plugin no longer binds Ctrl
unless explicitly requested. Custom mappings require matching physical shortcuts
on both sides.

Keep the separate `rex_splits_focus` action for editor-to-Rex edge requests.
Keep the existing private entry handoff independent of user mappings: it selects
the opposite edge when entering Neovim and must not invoke navigation again.
These responsibilities are already separated in
[the Neovim module](../lua/rex-splits/init.lua) and
[the Rex companion](../rex/rex-splits.lua).

Verified native Alt passthrough, held-key repeat, terminal mode, shell navigation,
and opposite-edge entry on an isolated Rex `0.0.1792787366-g623b2d` server.
The test suite covers default replacement, `mappings = false`, manual bindings,
and navigation/wrapping with both Ctrl and Alt. Function bindings do not expose
named palette/CLI actions; the `rex_splits_focus` action remains for edge requests.

For users already on smart-splits, the existing Rex backend is worth evaluating.
For this small standalone plugin, adopting the same passthrough contract can
improve usability without adding the smart-splits dependency or changing the
current Neovim 0.10 requirement and entry behavior.
