-- Load from Rex's init.lua: dofile("/path/to/nvim-rex/rex/rex-splits.lua").setup()
local M = {}
local directions = { h = "left", j = "down", k = "up", l = "right" }
local wrap = true
local installed_mappings = {}
local action_registered = false
local terminal = "com.superlogical.terminal"
-- Ctrl+Alt+Shift+arrows are reserved for the Neovim entry handoff. These
-- xterm key sequences work without a client or a Neovim RPC connection.
local entry_keys = {
    left = "\27[1;8D", right = "\27[1;8C",
    up = "\27[1;8A", down = "\27[1;8B",
}

local function normalize(direction)
    direction = directions[direction] or direction
    assert(entry_keys[direction], "rex-splits: invalid direction: " .. tostring(direction))
    return direction
end

local function navigation_mappings(value)
    if value == false then return {} end
    if value == nil or value == true then
        return { left = "ctrl+h", down = "ctrl+j", up = "ctrl+k", right = "ctrl+l" }
    end
    assert(type(value) == "table", "rex-splits: mappings must be a boolean or a direction-to-key table")
    local seen = {}
    for direction, key in pairs(value) do
        assert(entry_keys[direction], "rex-splits: invalid mapping direction: " .. tostring(direction))
        assert(type(key) == "string" and key ~= "", "rex-splits: mapping keys must be non-empty strings")
        assert(not key:find("[/>]"), "rex-splits: mappings require single keys, not modes or sequences")
        assert(not seen[key:lower()], "rex-splits: duplicate mapping key: " .. key)
        seen[key:lower()] = true
    end
    return value
end

local function is_nvim(process)
    local foreground = process and (process.foreground or process.child)
    local name = foreground and foreground.name or ""
    name = name:match("([^/\\]+)$") or name
    return name == "nvim" or name == "nvim.exe"
end

-- An asynchronous request from Neovim must not move focus after the user has
-- switched tabs/panes. Rex's focus_direction acts on the session's active pane.
local function focus(ctx, direction, wrap)
    assert(ctx.session_id and ctx.block_id, "rex-splits: missing session or block")
    local view, err = rex.session.view { session_id = ctx.session_id }
    assert(view, err)
    for _, window in ipairs(view.windows or {}) do
        if window.window_id == view.active_window_id then
            if window.focused_block_id ~= ctx.block_id then
                return { moved = false, reason = "focus_changed" }
            end
            local result, focus_err = rex.session.focus_direction {
                session_id = ctx.session_id, direction = direction, wrap = wrap,
            }
            assert(result, focus_err)
            -- Focus changes between Rex blocks do not choose a window inside
            -- Neovim. Enter at the opposite edge to keep one continuous cycle.
            local after, view_err = rex.session.view { session_id = ctx.session_id }
            if not after then
                rex.log("warn", "rex-splits: cannot inspect destination: " .. tostring(view_err))
                return result
            end
            if after.active_window_id ~= window.window_id then return result end
            for _, destination in ipairs(after.windows or {}) do
                if destination.window_id == window.window_id then
                    local block_id = destination.focused_block_id
                    if block_id and (block_id ~= ctx.block_id or wrap) then
                        local process = rex.block.call(terminal, "process", {
                            session_id = ctx.session_id, block_id = block_id,
                        })
                        if is_nvim(process) then
                            local written, write_err = rex.block.call(terminal, "write", {
                                session_id = ctx.session_id, block_id = block_id,
                                data = entry_keys[direction],
                            })
                            if not written then
                                rex.log("warn", "rex-splits: cannot select Neovim entry window: " .. tostring(write_err))
                            end
                        end
                    end
                    break
                end
            end
            return result
        end
    end
    return { moved = false, reason = "no_active_window" }
end

-- Return false to let Rex deliver the original key to Neovim unchanged.
-- Manual bindings can return this result from rex.bind(key, function(ctx) ... end).
function M.navigate(ctx, direction)
    direction = normalize(direction)
    local process, err = rex.block.call(terminal, "process", {
        session_id = ctx.session_id, block_id = ctx.block_id,
    })
    if not process then
        rex.log("warn", "rex-splits: cannot inspect process: " .. tostring(err))
        return false
    end
    if is_nvim(process) then return false end
    focus(ctx, direction, wrap)
    return true
end

function M.setup(opts)
    opts = opts or {}
    assert(opts.wrap == nil or type(opts.wrap) == "boolean", "rex-splits: wrap must be boolean")
    local mappings = navigation_mappings(opts.mappings)
    wrap = opts.wrap ~= false
    for key, handler in pairs(installed_mappings) do
        rex.unbind(key, handler)
    end
    installed_mappings = {}
    if not action_registered then
        rex.action {
            name = "rex_splits_focus",
            title = "Move from Neovim to a Rex pane",
            category = "Neovim",
            args = { direction = "string", wrap = "boolean?" },
            run = function(ctx, args)
                local direction = normalize(args.direction)
                local should_wrap = args.wrap
                if should_wrap == nil then should_wrap = wrap end
                return focus(ctx, direction, should_wrap)
            end,
        }
        action_registered = true
    end
    for direction, key in pairs(mappings) do
        local target = direction
        local handler = function(ctx) return M.navigate(ctx, target) end
        rex.bind(key, handler)
        installed_mappings[key] = handler
    end
end

return M
