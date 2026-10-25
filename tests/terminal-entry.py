"""Exercise the Rex entry bytes through a real Neovim TUI, not feedkeys/RPC.

Run: python3 tests/terminal-entry.py [path/to/nvim]
Only creates a temporary editor and files; no Rex server is contacted.
"""
import json
import os
from pathlib import Path
import select
import shutil
import subprocess
import sys
import tempfile
import time


plugin = Path(__file__).resolve().parents[1]
nvim = sys.argv[1] if len(sys.argv) > 1 else shutil.which("nvim")
assert nvim, "nvim is required"
with tempfile.TemporaryDirectory(prefix="rex-splits-entry-") as directory:
    temporary = Path(directory)
    state_file = temporary / "state.json"
    init_file = temporary / "init.lua"
    init_file.write_text(r'''
vim.opt.rtp:prepend(vim.env.REX_SPLITS_TEST_PLUGIN)
require("rex-splits").setup()
vim.o.swapfile = false
vim.o.ttimeoutlen = 100
vim.cmd("vsplit")
vim.cmd("wincmd h")
vim.cmd("split")
vim.cmd("wincmd l")
vim.cmd("split")
vim.cmd("wincmd j")
local function record()
  local windows = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    windows[tostring(win)] = vim.api.nvim_win_get_position(win)
  end
  vim.fn.writefile({ vim.json.encode({
    current = tostring(vim.api.nvim_get_current_win()), windows = windows,
    mode = vim.api.nvim_get_mode().mode,
    lines = vim.api.nvim_buf_get_lines(0, 0, -1, false),
  }) }, vim.env.REX_SPLITS_TEST_STATE)
end
vim.api.nvim_create_autocmd({ "WinEnter", "ModeChanged", "TextChanged", "TextChangedI" }, {
  callback = function() vim.schedule(record) end,
})
vim.schedule(record)
''')
    env = dict(os.environ, TERM="xterm-256color", REX_SESSION="session:test", REX_BLOCK="block:test",
               REX_SPLITS_TEST_PLUGIN=str(plugin), REX_SPLITS_TEST_STATE=str(state_file),
               NVIM_LOG_FILE=str(temporary / "nvim.log"))
    master, slave = os.openpty()
    editor = subprocess.Popen([nvim, "-u", str(init_file), "-i", "NONE", "-n"],
                              stdin=slave, stdout=slave, stderr=slave, env=env, start_new_session=True)
    os.close(slave)
    output = bytearray()

    def wait_for(predicate, description):
        deadline = time.monotonic() + 4
        state = None
        while time.monotonic() < deadline:
            if select.select([master], [], [], 0.02)[0]:
                try:
                    output.extend(os.read(master, 65536))
                except OSError:
                    break
            if state_file.exists():
                try:
                    state = json.loads(state_file.read_text())
                except json.JSONDecodeError:
                    continue
                if predicate(state):
                    return state
            if editor.poll() is not None:
                break
        raise AssertionError(f"{description}; last state: {state}; TUI tail: {bytes(output[-500:])!r}")

    try:
        state = wait_for(lambda s: len(s["windows"]) == 4, "editor ready")
        positions = list(state["windows"].values())
        left, right = min(p[1] for p in positions), max(p[1] for p in positions)
        top, bottom = min(p[0] for p in positions), max(p[0] for p in positions)
        for sequence, axis, expected, name in [
            (b"\x1b[1;8C", 1, left, "rightward entry selects left edge"),
            (b"\x1b[1;8B", 0, top, "downward entry selects top edge"),
            (b"\x1b[1;8D", 1, right, "leftward entry selects right edge"),
            (b"\x1b[1;8A", 0, bottom, "upward entry selects bottom edge"),
        ]:
            os.write(master, sequence)
            wait_for(lambda s: s["windows"][s["current"]][axis] == expected, name)
        os.write(master, b"i")
        wait_for(lambda s: s["mode"] == "i", "enter insert mode")
        os.write(master, b"\x1b[1;8C")
        state = wait_for(lambda s: s["windows"][s["current"]][1] == left,
                         "entry signal also works when destination is in insert mode")
        assert state["lines"] == [""], "entry signal must not insert text"
        print("PASS: real Neovim TUI decodes all four entry signals, including insert mode")
    finally:
        editor.terminate()
        try:
            editor.wait(timeout=2)
        except subprocess.TimeoutExpired:
            editor.kill()
            editor.wait()
        os.close(master)
