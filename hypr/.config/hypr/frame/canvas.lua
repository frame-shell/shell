-- Infinite canvas: instead of tiling into workspaces, every window floats on one endless
-- plane per workspace and the screen is a camera you move over it. Loaded from
-- frame/shell.lua when ~/.local/state/frameshell/layout says "canvas"
-- (`frame layout canvas`, or the question in `frame install`).
--
-- Hyprland has no camera, so moving the view moves every window of the workspace the
-- other way; the normal window animation makes that glide. A window's place on the
-- canvas is its place in Hyprland's layout plus the camera of its workspace; with more
-- than one monitor each one has its own canvas at the monitor's position, so a window
-- can be dragged from one to the other in the overview. The camera of each workspace is
-- kept in ~/.local/state/frameshell/canvas, so a config reload does not lose your spot.
-- The bar draws a minimap and the overview (Super+wheel) its map from
-- $XDG_RUNTIME_DIR/frame-canvas.json, written here.
--
-- Floating windows may sit anywhere outside the screen (misc.float_force_onscreen = 0,
-- the default). With several monitors, a window half off one screen shows on the
-- neighbouring one.

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
    local w, h = m.width / s, m.height / s
    -- A turned screen (transform 1, 3, 5, 7) is as wide as its mode is high
    if (tonumber(m.transform) or 0) % 2 == 1 then
        w, h = h, w
    end
    return { x = m.x, y = m.y, w = w, h = h }
end

-- Every monitor with its visible workspace, the view in layout coordinates and its camera
local function views()
    local out = {}
    for _, m in ipairs(hl.get_monitors() or {}) do
        local ws = m.active_workspace
        if ws and not ws.special then
            local v = view_of(ws)
            if v then
                v.ws, v.monitor, v.cam = ws, m, cam_of(ws)
                out[#out + 1] = v
            end
        end
    end
    return out
end

-- The view of the named monitor; without a name the one whose canvas has global point
-- gx, gy, otherwise the nearest one. Canvases overlap as soon as two cameras differ by
-- less than a screen, so callers that know the monitor (overview, minimap) name it.
local function view_at(gx, gy, name)
    if name and name ~= "" then
        for _, v in ipairs(views()) do
            if v.monitor.name == name then
                return v
            end
        end
    end
    local best, best_d
    for _, v in ipairs(views()) do
        local x1, y1 = v.x + v.cam.x, v.y + v.cam.y
        local dx = math.max(x1 - gx, 0, gx - (x1 + v.w))
        local dy = math.max(y1 - gy, 0, gy - (y1 + v.h))
        local d = dx * dx + dy * dy
        if not best_d or d < best_d then
            best, best_d = v, d
        end
    end
    return best
end

-- The view whose screen shows layout point lx, ly (where a window is right now)
local function view_on_screen(lx, ly)
    for _, v in ipairs(views()) do
        if lx >= v.x and lx < v.x + v.w and ly >= v.y and ly < v.y + v.h then
            return v
        end
    end
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

-- A window on any monitor's visible workspace, by address
local function find_window(address)
    for _, v in ipairs(views()) do
        for _, w in ipairs(canvas_windows(v.ws)) do
            if w.address == address then
                return w, v
            end
        end
    end
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

-- A fullscreen window pins the view; the overview and the minimap end it first
local function is_fullscreen(w)
    local f = w.fullscreen
    return f == true or (type(f) == "number" and f > 0)
end

-- Ends fullscreen on that workspace only, never on the focused window of another one
local function leave_fullscreen(ws)
    if not (ws and ws.has_fullscreen) then
        return
    end
    for _, w in ipairs(hl.get_workspace_windows(ws) or {}) do
        if is_fullscreen(w) then
            run(hl.dsp.window.fullscreen({ window = sel(w) }))
        end
    end
end

-- Moves the camera of ws (default: the focused one) by dx, dy: every window of the
-- workspace goes the other way
local function pan(dx, dy, ws)
    ws = ws or active_ws()
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

local function ws_of_monitor(name)
    for _, v in ipairs(views()) do
        if v.monitor.name == name then
            return v.ws
        end
    end
    return active_ws()
end

-- Dragging empty canvas (quickshell/canvas/CanvasDesk.qml) sends many small steps: the
-- windows and the camera move at once, the state file and the maps follow on drag_done
local function drag_by(name, dx, dy)
    local ws = ws_of_monitor(name)
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
end

local function drag_done()
    save_cams()
    snapshot()
end

-- The same for the monitor with that name (minimap in the bar of another screen)
local function pan_on(name, dx, dy)
    for _, v in ipairs(views()) do
        if v.monitor.name == name then
            pan(dx, dy, v.ws)
            return
        end
    end
    pan(dx, dy)
end

-- Puts global canvas point x, y in the middle of the screen whose canvas it is on
local function look_at(x, y, name)
    local v = view_at(x, y, name)
    if not v then
        return
    end
    leave_fullscreen(v.ws)
    pan(x - (v.x + v.cam.x + v.w / 2), y - (v.y + v.cam.y + v.h / 2), v.ws)
end

local function center_on(w)
    local ws = w.workspace
    local v = view_of(ws)
    if v then
        pan(w.at.x + w.size.x / 2 - (v.x + v.w / 2), w.at.y + w.size.y / 2 - (v.y + v.h / 2), ws)
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

-- Picked in the overview: focus the window (on whichever monitor) and bring it to the middle
local function pick(address)
    local w = find_window(address)
    if not w then
        return
    end
    leave_fullscreen(w.workspace)
    run(hl.dsp.focus({ window = sel(w) }))
    center_on(w)
end

-- Dragged in the overview: puts the window's top left corner at global canvas point x, y.
-- A point on another monitor's canvas moves the window to that monitor first.
local function move_to(address, x, y, name)
    local w, own = find_window(address)
    if not w then
        return
    end
    local target = view_at(x + w.size.x / 2, y + w.size.y / 2, name) or own
    if target.ws.id ~= own.ws.id then
        run(hl.dsp.window.move({ workspace = tostring(target.ws.id), follow = false, window = sel(w) }))
    end
    run(hl.dsp.window.move({ x = math.floor(x - target.cam.x), y = math.floor(y - target.cam.y), window = sel(w) }))
    snapshot()
end

-- F in the overview: fullscreen on the screen the window is (mostly) on. A window hanging
-- over another monitor's canvas moves there first, so it fills the screen it sits on.
local function fullscreen_on(address)
    local w, own = find_window(address)
    if not w then
        return
    end
    -- Where the window is on the screens right now decides, not the (overlapping) canvases
    local target = view_on_screen(w.at.x + w.size.x / 2, w.at.y + w.size.y / 2) or own
    if target.ws.id ~= own.ws.id then
        run(hl.dsp.window.move({ workspace = tostring(target.ws.id), follow = false, window = sel(w) }))
        w = find_window(address) or w
    end
    leave_fullscreen(target.ws)
    run(hl.dsp.focus({ window = sel(w) }))
    -- Leaving fullscreen later should show the window, not empty canvas
    if not fully_visible(box(w), target) then
        center_on(w)
    end
    run(hl.dsp.window.fullscreen({ window = sel(w) }))
    snapshot()
end

-- Dragged by its corner in the overview: the window's new size in pixels
local function resize_to(address, width, height)
    local w = find_window(address)
    if not w then
        return
    end
    run(hl.dsp.window.resize({ x = math.max(100, math.floor(width)), y = math.max(80, math.floor(height)), relative = false, window = sel(w) }))
    snapshot()
end

-- Q in the overview: asks the window to close (like the title bar's x, not a kill)
local function close_window(address)
    local w = find_window(address)
    if w then
        run(hl.dsp.window.close({ window = sel(w) }))
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
    -- Every canvas back to its start first, so the windows that keep floating (dialogs)
    -- are on screen again and not where some camera left them
    for _, ws in ipairs(hl.get_workspaces() or {}) do
        local c = cams[tostring(ws.id)]
        if c and (c.x ~= 0 or c.y ~= 0) and not ws.special then
            for _, w in ipairs(canvas_windows(ws)) do
                run(hl.dsp.window.move({ x = c.x, y = c.y, relative = true, window = sel(w) }))
            end
        end
    end
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

-- ── Map data for the bar and the overview ────────────────────

local function jstr(s)
    return '"' .. (tostring(s):gsub('[%c"\\]', function(ch)
        return string.format("\\u%04x", ch:byte())
    end)) .. '"'
end

local last_snapshot = ""

-- { monitors: [{ name, focused, workspace, x, y, w, h, camera: { x, y } }],
--   windows: [{ address, monitor, x, y, w, h, active, class, title }] }
-- Everything in global canvas coordinates: layout position plus the camera of the
-- window's workspace, so each monitor's canvas lies where the monitor is. Only written
-- when something changed.
snapshot = function()
    local active = hl.get_active_window()
    local mons, wins = {}, {}
    for _, v in ipairs(views()) do
        mons[#mons + 1] = string.format('{"name":%s,"focused":%s,"workspace":%s,"x":%d,"y":%d,"w":%d,"h":%d,"camera":{"x":%d,"y":%d}}',
            jstr(v.monitor.name), v.monitor.focused and "true" or "false", jstr(v.ws.id),
            math.floor(v.x), math.floor(v.y), math.floor(v.w), math.floor(v.h), math.floor(v.cam.x), math.floor(v.cam.y))
        for _, w in ipairs(canvas_windows(v.ws)) do
            wins[#wins + 1] = string.format('{"address":%s,"monitor":%s,"x":%d,"y":%d,"w":%d,"h":%d,"active":%s,"class":%s,"title":%s}',
                jstr(w.address or ""), jstr(v.monitor.name),
                math.floor(w.at.x + v.cam.x), math.floor(w.at.y + v.cam.y), math.floor(w.size.x), math.floor(w.size.y),
                (active and active.address == w.address) and "true" or "false", jstr(w.class or ""), jstr(w.title or ""))
        end
    end
    if #mons == 0 then
        return
    end
    local text = string.format('{"monitors":[%s],"windows":[%s]}\n', table.concat(mons, ","), table.concat(wins, ","))
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

-- A handler that fails must not put Hyprland's error bar on the screen: the window
-- handed to an event can already be half gone (window.destroy), and a window that
-- disappears while the list is read raises too. Errors go to the log instead.
local function on(event, fn)
    hl.on(event, function(...)
        local ok, err = pcall(fn, ...)
        if not ok then
            print("frame canvas: " .. event .. ": " .. tostring(err))
        end
    end)
end

on("window.open_early", function(w)
    if w.floating then
        native_float[w.address] = true
    end
end)

on("window.open", function(w)
    place_new(w)
    snapshot()
end)

-- The window is being torn down here; its fields may already be gone, and the window
-- list still has it for a moment, so the snapshot waits for the next timer tick
on("window.destroy", function(w)
    local ok, address = pcall(function()
        return w.address
    end)
    if ok and address then
        native_float[address] = nil
    end
end)

on("window.close", snapshot)
on("window.active", snapshot)
on("window.move_to_workspace", snapshot)
on("workspace.active", snapshot)
on("config.reloaded", float_all)

-- Mouse drags do not send an event; a cheap look twice a second keeps the maps right
-- (and catches the window that just closed)
hl.timer(function()
    pcall(snapshot)
end, { timeout = 500, type = "repeat" })

-- The distro config (CachyOS) uses Super+wheel and Super+Ctrl+arrows and the wheel for
-- workspaces and Super+Shift+arrows to move windows; a key bound twice runs both, so
-- those binds are dropped first (hl.unbind: one bind per call, modifiers spelled like
-- the other bind, see shell.lua)
local function bind(keys, fn, text)
    for _, spelling in ipairs({ keys, (keys:gsub("CTRL", "CONTROL")) }) do
        for _ = 1, 4 do
            pcall(hl.unbind, spelling)
        end
    end
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
bind("SUPER + CTRL + F", hl.dsp.window.fullscreen(), "fullscreen on / off")
bind("SUPER + CTRL + C", function()
    local w = hl.get_active_window()
    if w and w.floating then
        center_on(w)
    end
end, "center the window")
bind("SUPER + CTRL + H", home, "back to the start")
bind("SUPER + CTRL + G", tidy, "tidy into a grid")

-- Super+wheel: zoom out into the overview (quickshell/canvas/CanvasOverview.qml), zoom
-- back in on the window under the cursor. The overview takes plain wheel, drag and clicks itself.
bind("SUPER + mouse_down", hl.dsp.exec_cmd("qs ipc call overview zoomOut"), "zoom out · overview")
bind("SUPER + mouse_up", hl.dsp.exec_cmd("qs ipc call overview zoomIn"), "zoom in")

-- While the overview is open, Super + mouse must not drag or resize the windows behind
-- it (Hyprland's mouse binds work through the overlay). The binds are the distro's
-- (CachyOS: config/binds.lua) and come back the same way when the overview closes.
local DRAG_BINDS = {
    { "SUPER + mouse:272", hl.dsp.window.drag() },
    { "SUPER + mouse:273", hl.dsp.window.resize() },
}
local function overview(open)
    if open then
        -- Zooming out in the middle of Super+drag: the window must not keep following
        -- the cursor behind the overlay, so the drag (or resize) is released here
        run(hl.dsp.exec_raw("mouse", "0movewindow"))
        run(hl.dsp.exec_raw("mouse", "0resizewindow"))
    end
    for _, b in ipairs(DRAG_BINDS) do
        for _ = 1, 4 do
            pcall(hl.unbind, b[1])
        end
    end
    if not open then
        for _, b in ipairs(DRAG_BINDS) do
            hl.bind(b[1], b[2], b[3])
        end
    end
end

-- For the bar (minimap), the overview and frame: hyprctl eval 'frame_canvas.look_at(0, 0)'
frame_canvas = {
    overview = overview,
    pan = pan,
    pan_on = pan_on,
    drag_by = drag_by,
    drag_done = drag_done,
    look_at = look_at,
    select = pick,
    move_to = move_to,
    fullscreen = fullscreen_on,
    resize_to = resize_to,
    close_window = close_window,
    home = home,
    tidy = tidy,
    release = release,
}
