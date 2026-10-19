-- Apps outside Quickshell: Dolphin, Zed, Zen. Loaded from frame/shell.lua.

-- Qt apps (Dolphin) take style, fonts and the theme palette from qt6ct
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
-- Without Plasma, KDE apps find no application menu and "Open with" stays empty;
-- archlinux-xdg-menu provides arch-applications.menu
hl.env("XDG_MENU_PREFIX", "arch-")

hl.bind("SUPER + E", hl.dsp.exec_cmd("dolphin"), { description = "frame apps · Dolphin" })
hl.bind("SUPER + B", hl.dsp.exec_cmd("zen-browser"), { description = "frame apps · Zen" })
hl.bind("SUPER + SHIFT + E", hl.dsp.exec_cmd("zeditor"), { description = "frame apps · Zed" })
