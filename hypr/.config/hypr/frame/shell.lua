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

local function shell(target, action)
    return hl.dsp.exec_cmd("qs ipc call " .. target .. " " .. action)
end

hl.bind("SUPER + SPACE", shell("launcher", "toggle"), { description = "frame shell · launcher" })
hl.bind("SUPER + C", shell("controlcenter", "toggle"), { description = "frame shell · control center" })
hl.bind("SUPER + W", shell("wallpapers", "toggle"), { description = "frame shell · wallpapers" })
hl.bind("SUPER + L", shell("lock", "lock"), { description = "frame shell · lock" })

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
