-- Hold Super for a second and a half: the hotkey overlay opens; letting go closes it.
-- Loaded from frame/shell.lua. Quickshell draws the overlay (qs ipc call hotkeys …).
--
-- It stays closed when Super is used for something else in the meantime: another key
-- (Super+Space, Super+1, …) or a window drag with Super and the mouse.

local HOLD_MS = 1500
local TICK_MS = 100
-- Super_L and Super_R: XKB keycodes (evdev KEY_LEFTMETA/RIGHTMETA + 8) and the raw
-- evdev codes, whichever Hyprland hands over
local SUPER = { [133] = true, [134] = true, [125] = true, [126] = true }
-- A cursor that moved this far means Super is dragging or resizing a window; a hand that
-- rests on the mouse moves less than that
local DRAG_PX = 160

local held, used, shown, elapsed, start = false, false, false, 0, nil

local function overlay(action)
    hl.exec_cmd("qs ipc call hotkeys " .. action)
end

local function cursorMoved()
    local now = hl.get_cursor_pos()
    if not start or not now then
        return false
    end
    return math.abs(now.x - start.x) > DRAG_PX or math.abs(now.y - start.y) > DRAG_PX
end

-- Counting ticks instead of one long timeout: re-enabling a timer then never has to
-- restart it, and a tick is short enough to feel exact
local tick = hl.timer(function()
    if not held or used or shown then
        return
    end
    elapsed = elapsed + TICK_MS
    if cursorMoved() then
        used = true
    elseif elapsed >= HOLD_MS then
        shown = true
        overlay("open")
    end
end, { timeout = TICK_MS, type = "repeat" })
tick:set_enabled(false)

-- state: 0 released, 1 pressed, 2 repeated
hl.on("input.keyboard.key", function(keycode, _, state)
    if SUPER[keycode] then
        if state == 1 and not held then
            held, used, elapsed, start = true, false, 0, hl.get_cursor_pos()
            tick:set_enabled(true)
        elseif state == 0 then
            held = false
            tick:set_enabled(false)
            if shown then
                shown = false
                overlay("close")
            end
        end
    elseif state == 1 and held then
        used = true
    end
end)
