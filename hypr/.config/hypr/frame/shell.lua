-- frameshell for Hyprland (Lua config, Hyprland 0.55+): autostart, shell keybinds, idle.
-- Loaded from your own hyprland.lua with require("frame/shell"); `frame install hypr`
-- adds that line. Descriptions show up in the hotkey overlay (hold Super).

-- Quickshell runs bar, launcher, lockscreen and the rest; hypridle locks after idle
-- time (see hypridle.conf); frame-wallpaper starts the wallpaper picked in the app;
-- cliphist keeps what you copy for the launcher
hl.on("hyprland.start", function()
    hl.exec_cmd("qs")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("~/.local/bin/frame-wallpaper apply")
    -- Clipboard history for the launcher (;)
    hl.exec_cmd("command -v cliphist >/dev/null && wl-paste --watch cliphist store")
    -- GoXLR faders and mutes for the shell; does nothing without GoXLR Utility
    hl.exec_cmd("command -v goxlr-daemon >/dev/null && goxlr-daemon")
end)

-- A key bound twice runs both binds, and the distro config (CachyOS: config/binds.lua)
-- has its own on some of frame's keys, so those are dropped first. hl.unbind takes one
-- bind per call and wants the modifiers spelled as the other bind wrote them (CachyOS:
-- CONTROL, not CTRL); the key itself may differ in case. apps.lua and canvas.lua do the same.
local function take(keys, dispatcher, opts)
    for _, spelling in ipairs({ keys, (keys:gsub("CTRL", "CONTROL")) }) do
        for _ = 1, 4 do
            pcall(hl.unbind, spelling)
        end
    end
    return hl.bind(keys, dispatcher, opts)
end

local function shell(target, action)
    return hl.dsp.exec_cmd("qs ipc call " .. target .. " " .. action)
end

take("SUPER + SPACE", shell("launcher", "toggle"), { description = "frame shell · launcher" })
take("SUPER + C", shell("controlcenter", "toggle"), { description = "frame shell · control center" })
take("SUPER + V", shell("launcher", "clipboard"), { description = "frame shell · clipboard history" })
take("SUPER + W", shell("wallpapers", "toggle"), { description = "frame shell · wallpapers" })
take("SUPER + L", shell("lock", "lock"), { description = "frame shell · lock" })
-- Ctrl+Alt+Q types an @ (for a keyboard without a working AltGr). The sign is typed with
-- a virtual keyboard once Ctrl and Alt are up again, otherwise the app would see Ctrl+@.
local AT_MODIFIERS = { 37, 64, 105, 108 } -- Control_L, Alt_L, Control_R, Alt_R (XKB keycodes)
local at_timer
local at_waited = 0
local function type_at()
    at_waited = at_waited + 20
    local held = false
    for _, code in ipairs(AT_MODIFIERS) do
        local ok, down = pcall(hl.is_key_down, code)
        if ok and down then
            held = true
        end
    end
    if held and at_waited < 1500 then
        return
    end
    at_timer:set_enabled(false)
    local f = io.open((os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/frame-at.log", "a")
    if f then f:write("typed after " .. at_waited .. " ms, held=" .. tostring(held) .. "\n"); f:close() end
    hl.exec_cmd("wtype @")
end
at_timer = hl.timer(type_at, { timeout = 20, type = "repeat" })
at_timer:set_enabled(false)
take("CTRL + ALT + Q", function()
    at_waited = 0
    at_timer:set_enabled(true)
end, { description = "frame shell · type @" })

-- Screenshots (the distro binds Print to grim + slurp; the shell has its own picker)
take("Print", shell("screenshot", "region"), { description = "frame shell · screenshot: region or window" })
take("SHIFT + Print", shell("screenshot", "screen"), { description = "frame shell · screenshot: whole screen" })
take("SUPER + Print", shell("screenshot", "screen"), { description = "frame shell · screenshot: whole screen" })
-- Keyboards without a Print key: the Windows shortcuts (Super+Shift+S was the distro's
-- "move window to special workspace")
take("SUPER + SHIFT + S", shell("screenshot", "region"), { description = "frame shell · screenshot: region or window" })
take("SUPER + CTRL + S", shell("screenshot", "screen"), { description = "frame shell · screenshot: whole screen" })

hl.config({
    misc = {
        -- A restarted Quickshell can take over the lock after a crash
        allow_session_lock_restore = true,
    },
})

-- Each require is its own scope in Hyprland, so an error in one file leaves the others working
require("frame/apps")
require("frame/hotkeys")

-- Layout picked in `frame install` or with `frame layout tiling|canvas`; the normal
-- tiling needs nothing, the infinite canvas lives in frame/canvas.lua
local function layout()
    local home = os.getenv("XDG_STATE_HOME") or ((os.getenv("HOME") or "") .. "/.local/state")
    local f = io.open(home .. "/frameshell/layout", "r")
    if not f then
        return "tiling"
    end
    local mode = (f:read("*l") or ""):match("^%s*(%a+)") or "tiling"
    f:close()
    return mode
end
if layout() == "canvas" then
    require("frame/canvas")
end
-- Written by `frame theme`; missing until the first run, which must not stop the rest
pcall(require, "frame/colors")
