-- Infinite canvas: instead of tiling into workspaces, every window floats on one endless
-- plane per workspace and the screen is a camera you move over it. Loaded from
-- frame/shell.lua when ~/.local/state/frameshell/layout says "canvas"
-- (`frame layout canvas`, or the question in `frame install`).
--
-- Hyprland has no camera, so moving the view moves every window of the workspace the
-- other way; the normal window animation makes that glide. A window's place on the
-- canvas is its place on screen plus the camera. The camera of each workspace is kept in
-- ~/.local/state/frameshell/canvas, so a config reload does not lose your spot.
-- The bar draws a minimap from $XDG_RUNTIME_DIR/frame-canvas.json, written here.
--
-- Floating windows may sit anywhere outside the screen (misc.float_force_onscreen = 0,
-- the default). With several monitors, a window half off one screen shows on the
-- neighbouring one; each monitor keeps its own canvas (its workspace).

local HOME = os.getenv("HOME") or ""
local STATE = (os.getenv("XDG_STATE_HOME") or (HOME .. "/.local/state")) .. "/frameshell/canvas"
local SNAPSHOT = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/frame-canvas.json"

-- Super+Ctrl+arrows moves the view by this share of the screen
local PAN_SHARE = 0.5
-- Super+Ctrl+wheel moves it by this many pixels per notch
local WHEEL_PX = 160
-- Super+Shift+arrows moves the focused window by this much
local NUDGE_PX = 80
-- Space between windows placed or tidied automatically
local GAP = 24
-- New windows: share of the screen
local NEW_W, NEW_H = 0.55, 0.65

local cams = {}
-- Windows that floated on their own (dialogs, pickers) keep their size and place
local native_float = {}
local snapshot

-- ── Helpers ──────────────────────────────────────────────────

local function run(dispatcher)
    local ok, err = pcall(hl.dispatch, dispatcher)
    if not ok then
        print("frame canvas: " .. tostring(err))
    end
end

local function sel(w)
    return "address:" .. w.address
end

local function active_ws()
    local ws = hl.get_active_workspace()
    if ws and not ws.special then
        return ws
    end
end

local function cam_of(ws)
    local id = tostring(ws.id)
    cams[id] = cams[id] or { x = 0, y = 0 }
    return cams[id]
end

-- The monitor in layout coordinates (Hyprland reports its size in pixels)
local function view_of(ws)
    local m = ws and ws.monitor
    if not m then
        return nil
    end
    local s = (m.scale and m.scale > 0) and m.scale or 1
    return { x = m.x, y = m.y, w = m.width / s, h = m.height / s }
end

local function canvas_windows(ws)
    local out = {}
    for _, w in ipairs(hl.get_workspace_windows(ws) or {}) do
        if w.mapped and not w.hidden and not w.pinned and w.floating then
            table.insert(out, w)
        end
    end
    return out
end

local function box(w)
    return { x = w.at.x, y = w.at.y, w = w.size.x, h = w.size.y }
end

local function overlaps(a, b)
    return a.x < b.x + b.w + GAP and b.x < a.x + a.w + GAP and a.y < b.y + b.h + GAP and b.y < a.y + a.h + GAP
end

local function fully_visible(b, v)
    return b.x >= v.x and b.y >= v.y and b.x + b.w <= v.x + v.w and b.y + b.h <= v.y + v.h
end

local function load_cams()
    local f = io.open(STATE, "r")
    if not f then
        return
    end
    for line in f:lines() do
        local id, x, y = line:match("^(%S+)%s+(-?%d+)%s+(-?%d+)$")
        if id then
            cams[id] = { x = tonumber(x), y = tonumber(y) }
        end
    end
    f:close()
end

local function save_cams()
    local f = io.open(STATE, "w")
    if not f then
        return
    end
    for id, c in pairs(cams) do
        f:write(string.format("%s %d %d\n", id, math.floor(c.x), math.floor(c.y)))
    end
    f:close()
end

-- ── Moving the view ──────────────────────────────────────────

-- Moves the camera by dx, dy: every window of the workspace goes the other way
local function pan(dx, dy)
    local ws = active_ws()
    if not ws or ws.has_fullscreen then
        return
    end
    dx, dy = math.floor(dx + 0.5), math.floor(dy + 0.5)
    if dx == 0 and dy == 0 then
        return
    end
    for _, w in ipairs(canvas_windows(ws)) do
        run(hl.dsp.window.move({ x = -dx, y = -dy, relative = true, window = sel(w) }))
    end
    local c = cam_of(ws)
    c.x, c.y = c.x + dx, c.y + dy
    save_cams()
    snapshot()
end

-- Puts canvas point x, y in the middle of the screen
local function look_at(x, y)
    local ws = active_ws()
    local v = view_of(ws)
    if not v then
        return
    end
    local c = cam_of(ws)
    pan(x - (c.x + v.w / 2), y - (c.y + v.h / 2))
end

local function center_on(w)
    local v = view_of(w.workspace)
    if v then
        pan(w.at.x + w.size.x / 2 - (v.x + v.w / 2), w.at.y + w.size.y / 2 - (v.y + v.h / 2))
    end
end

local DIRS = { left = { -1, 0 }, right = { 1, 0 }, up = { 0, -1 }, down = { 0, 1 } }

local function pan_dir(name, share)
    local v = view_of(active_ws())
    if v then
        local d = DIRS[name]
        pan(d[1] * v.w * share, d[2] * v.h * share)
    end
end

-- Focuses the nearest window in that direction and brings it into view;
-- with nothing there the view just moves on
local function focus_dir(name)
    local ws = active_ws()
    local v = view_of(ws)
    if not v then
        return
    end
    local d = DIRS[name]
    local cur = hl.get_active_window()
    local own = cur and cur.floating and cur.workspace and cur.workspace.id == ws.id
    local cx = own and cur.at.x + cur.size.x / 2 or v.x + v.w / 2
    local cy = own and cur.at.y + cur.size.y / 2 or v.y + v.h / 2

    local best, best_score
    for _, w in ipairs(canvas_windows(ws)) do
        if not (own and w.address == cur.address) then
            local dx, dy = w.at.x + w.size.x / 2 - cx, w.at.y + w.size.y / 2 - cy
            local along = dx * d[1] + dy * d[2]
            local across = math.abs(dx * d[2]) + math.abs(dy * d[1])
            if along > 1 then
                local score = along + 2 * across
                if not best_score or score < best_score then
                    best, best_score = w, score
                end
            end
        end
    end
    if not best then
        pan_dir(name, PAN_SHARE)
        return
    end
    run(hl.dsp.focus({ window = sel(best) }))
    if not fully_visible(box(best), v) then
        center_on(best)
    end
end

local function nudge(name)
    local d = DIRS[name]
    run(hl.dsp.window.move({ x = d[1] * NUDGE_PX, y = d[2] * NUDGE_PX, relative = true }))
end

-- Back to where the canvas started
local function home()
    local ws = active_ws()
    if ws then
        local c = cam_of(ws)
        pan(-c.x, -c.y)
    end
end

-- Lays every window out in a grid around the middle of the screen
local function tidy()
    local ws = active_ws()
    local v = view_of(ws)
    if not v then
        return
    end
    local list = canvas_windows(ws)
    if #list == 0 then
        return
    end
    table.sort(list, function(a, b)
        return a.at.y + a.at.x * 0.001 < b.at.y + b.at.x * 0.001
    end)
    local cols = math.ceil(math.sqrt(#list))
    local rows = math.ceil(#list / cols)
    local cw, ch = 0, 0
    for _, w in ipairs(list) do
        cw, ch = math.max(cw, w.size.x), math.max(ch, w.size.y)
    end
    cw, ch = cw + GAP, ch + GAP
    local left = v.x + v.w / 2 - cols * cw / 2
    local top = v.y + v.h / 2 - rows * ch / 2
    for i, w in ipairs(list) do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        run(hl.dsp.window.move({
            x = math.floor(left + col * cw + (cw - w.size.x) / 2),
            y = math.floor(top + row * ch + (ch - w.size.y) / 2),
            window = sel(w),
        }))
    end
    snapshot()
end

-- ── New windows ──────────────────────────────────────────────

-- The middle of the screen if it is free, otherwise the nearest free spot in rings around it
local function place_new(w)
    if native_float[w.address] or not w.floating or w.pinned then
        return
    end
    local ws = w.workspace
    if not ws or ws.special then
        return
    end
    local v = view_of(ws)
    if not v then
        return
    end
    local others = {}
    for _, o in ipairs(canvas_windows(ws)) do
        if o.address ~= w.address then
            table.insert(others, box(o))
        end
    end
    local bw, bh = w.size.x, w.size.y
    local x0, y0 = v.x + (v.w - bw) / 2, v.y + (v.h - bh) / 2
    local candidates = { { x = x0, y = y0, d = 0 } }
    for ring = 1, 4 do
        for i = -ring, ring do
            for j = -ring, ring do
                if math.max(math.abs(i), math.abs(j)) == ring then
                    -- Screens are wide: right first, then left, then below and above
                    local d = i * i + j * j * 1.6 + (i < 0 and 0.1 or 0) + (j < 0 and 0.2 or 0)
                    table.insert(candidates, { x = x0 + i * (bw + GAP), y = y0 + j * (bh + GAP), d = d })
                end
            end
        end
    end
    table.sort(candidates, function(a, b)
        return a.d < b.d
    end)

    local spot
    for _, c in ipairs(candidates) do
        local free = true
        for _, o in ipairs(others) do
            if overlaps({ x = c.x, y = c.y, w = bw, h = bh }, o) then
                free = false
                break
            end
        end
        if free then
            spot = c
            break
        end
    end
    -- A crowded canvas: stack it slightly offset in the middle
    spot = spot or { x = x0 + 32 * (#others % 8), y = y0 + 32 * (#others % 8) }

    run(hl.dsp.window.move({ x = math.floor(spot.x), y = math.floor(spot.y), window = sel(w) }))
    if not fully_visible({ x = spot.x, y = spot.y, w = bw, h = bh }, v) then
        center_on(w)
    end
end

-- Windows that were tiled before (switching from the normal layout) float now
local function float_all()
    for _, w in ipairs(hl.get_windows() or {}) do
        local ws = w.workspace
        if w.mapped and not w.floating and ws and not ws.special then
            run(hl.dsp.window.float({ action = "set", window = sel(w) }))
        end
    end
    snapshot()
end

-- Before `frame layout tiling`: big windows tile again, small ones (dialogs) keep floating
local function release()
    for _, w in ipairs(hl.get_windows() or {}) do
        local v = view_of(w.workspace)
        if w.mapped and w.floating and not w.pinned and v and (w.size.x > v.w * 0.3 or w.size.y > v.h * 0.3) then
            run(hl.dsp.window.float({ action = "unset", window = sel(w) }))
        end
    end
    cams = {}
    os.remove(STATE)
    os.remove(SNAPSHOT)
end

-- ── Minimap data for the bar ─────────────────────────────────

local function jstr(s)
    return '"' .. (tostring(s):gsub('[%c"\\]', function(ch)
        return string.format("\\u%04x", ch:byte())
    end)) .. '"'
end

local last_snapshot = ""

-- { workspace, camera: { x, y }, view: { w, h }, windows: [{ x, y, w, h, active, class, title }] }
-- in canvas coordinates; only written when something changed
snapshot = function()
    local ws = active_ws()
    local v = view_of(ws)
    if not v then
        return
    end
    local c = cam_of(ws)
    local active = hl.get_active_window()
    local parts = {}
    for _, w in ipairs(canvas_windows(ws)) do
        parts[#parts + 1] = string.format('{"x":%d,"y":%d,"w":%d,"h":%d,"active":%s,"class":%s,"title":%s}',
            math.floor(w.at.x - v.x + c.x), math.floor(w.at.y - v.y + c.y), math.floor(w.size.x), math.floor(w.size.y),
            (active and active.address == w.address) and "true" or "false", jstr(w.class or ""), jstr(w.title or ""))
    end
    local text = string.format('{"workspace":%s,"camera":{"x":%d,"y":%d},"view":{"w":%d,"h":%d},"windows":[%s]}\n',
        jstr(ws.id), math.floor(c.x), math.floor(c.y), math.floor(v.w), math.floor(v.h), table.concat(parts, ","))
    if text == last_snapshot then
        return
    end
    last_snapshot = text
    local f = io.open(SNAPSHOT, "w")
    if f then
        f:write(text)
        f:close()
    end
end

-- ── Rules, events, binds ─────────────────────────────────────

load_cams()

-- Windows that would tile float instead, at a comfortable size; dialogs already float
-- and are left alone (match float = false only sees how the window started)
hl.window_rule({
    name = "frame-canvas",
    match = { float = false },
    float = true,
    size = { "monitor_w*" .. NEW_W, "monitor_h*" .. NEW_H },
    center = true,
})

hl.on("window.open_early", function(w)
    if w.floating then
        native_float[w.address] = true
    end
end)

hl.on("window.open", function(w)
    place_new(w)
    snapshot()
end)

hl.on("window.destroy", function(w)
    native_float[w.address] = nil
    snapshot()
end)

hl.on("window.close", function()
    snapshot()
end)
hl.on("window.active", function()
    snapshot()
end)
hl.on("window.move_to_workspace", function()
    snapshot()
end)
hl.on("workspace.active", function()
    snapshot()
end)
hl.on("config.reloaded", float_all)

-- Mouse drags do not send an event; a cheap look twice a second keeps the minimap right
hl.timer(snapshot, { timeout = 500, type = "repeat" })

local function bind(keys, fn, text)
    hl.bind(keys, fn, { description = "frame canvas · " .. text })
end

for _, name in ipairs({ "left", "right", "up", "down" }) do
    bind("SUPER + CTRL + " .. name, function()
        pan_dir(name, PAN_SHARE)
    end, "look " .. name)
    bind("SUPER + ALT + " .. name, function()
        focus_dir(name)
    end, "next window " .. name)
    bind("SUPER + SHIFT + " .. name, function()
        nudge(name)
    end, "move window " .. name)
end

bind("SUPER + CTRL + mouse_down", function()
    pan(0, WHEEL_PX)
end, "scroll down")
bind("SUPER + CTRL + mouse_up", function()
    pan(0, -WHEEL_PX)
end, "scroll up")
bind("SUPER + CTRL + SHIFT + mouse_down", function()
    pan(WHEEL_PX, 0)
end, "scroll right")
bind("SUPER + CTRL + SHIFT + mouse_up", function()
    pan(-WHEEL_PX, 0)
end, "scroll left")
bind("SUPER + CTRL + F", function()
    local w = hl.get_active_window()
    if w and w.floating then
        center_on(w)
    end
end, "center the window")
bind("SUPER + CTRL + H", home, "back to the start")
bind("SUPER + CTRL + G", tidy, "tidy into a grid")

-- For the bar (click on the minimap) and frame: hyprctl eval 'frame_canvas.look_at(0, 0)'
frame_canvas = {
    pan = pan,
    look_at = look_at,
    home = home,
    tidy = tidy,
    release = release,
}
