# Research: Notum Dovvetech and the Spiritech UI surface

> Background notes from the first (v0.1) design pass. The packages have moved on since (see the top-level README); kept for the research and design rationale.

Reference point for behavior is ndGUI 4.3.4.x as published by Honorbound, continuing the line Misat0 built from Kitao’s Dovvetech GUI. The public feature list used here is the one on [rubi-ka.net/ndgui](https://rubi-ka.net/ndgui) (core 4.3.4.7, themes 4.3.4.5) and the Funcom thread “Notum Dovvetech GUI 4.34”, which records a later package, 4.3.4.8 (2019-03-08). This note does not copy texture packs, XML skins, or the classic `ndGUI_Config_Tool.cmd` installer.

Spiritech’s public description is the Project Rubi-Ka post “Introducing Spiritech” (project-rk.com, 2026-11-11). A 2021 Project Rubi-Ka plugin post about Lua character stats is a different, older client. It is not the Spiritech API and is not used as a binding source.

## Defining visual traits

ndGUI’s reputation comes from a clear visual style and a space-efficient layout, plus adjusted text colors so chat, info panels, and tooltips stay readable on a smaller chrome. The UI gives screen space back to the world instead of framing it with thick stock Anarchy Online panels.

The seven classic themes are:

- dovvetech
- dovvetech dark
- dovvetech edge
- darktech
- darktech mini
- darktech mini HUD
- darktech glass

Two families carry the set. Dovvetech is the lighter steel-blue branch. Public comments from the maintainer put an orange compass marker on the Dovve variants because it stays visible on blue chrome. DarkTech is the near-black branch. The same comments put a blue compass marker on Dark because it matches that palette, and they describe regular DarkTech as normal-height bars with a more pronounced window frame. DarkTech Mini keeps that dark palette but shortens HP, nano, and the other bars; the short bars are what make Mini “mini”. DarkTech mini HUD and DarkTech glass are further variants on the dark family (glass reads as a translucent frame over the same density idea). Edge and dovvetech dark are contrast and rim variants of the Dovve family. None of those roles are sampled from the theme zips. They are the public distinctions this package is allowed to follow.

Frames of that era are square, tight, and texture-backed. Window headers are a single thin strip. Bars are flat tracks with a bright fill. The menubar is a super slim menubar: one control row, not a stack of toolbars.

## Defining functional traits

The slim menubar supports top/bottom and left/right positioning, a floating menu, fading, and main-menu auto-hide. Fading in the classic client is the Control Center low/high fade pair. Auto-hide collapses the main menu (Char, Info, Misc) until the bar is needed. SoftMenu adds extra menubar buttons whose actions the player picks. Quick Options opens directly onto Lock Wear, Lock Shortcutbar, Lock RaidBar, Inspect, Auto-AFK, Social, and Show All Names.

The compact raid window and smaller raid bars are optional layouts for group play, with a reset path when a size switch went wrong. Static shortcutbar hotkey numbering keeps each slot’s number put when bars are moved or hidden. Horizontal and vertical shortcutbar togglers flip a bar’s axis.

Classic extras around that core, present in the public list but not required to recognize the UI, include extended menus (PvP, leet pet duel, pet control, visual-detail and performance shortcuts, assist-macro creation), the Control Center builder, the theme customizer (notum|morph), the number-bar aligner, nano-icon border toggles, info-window font size, and the three text schemes (Notum, Classic Notum, Game Default).

## High-value recreations

These are the traits a long-time ndGUI user would miss first, and they are the v1 bar:

- Space-efficient layout and adjusted text colors, expressed as theme tokens rather than a texture swap.
- A theme switch that changes color, frame, and density together. v1 ships four tokens sets that cover the two families, the mini density, and one modern variant: Classic Dovvetech, DarkTech, DarkTech Mini, and Adaptive.
- The slim menubar: one row, top/bottom and left/right anchors, floating, fading, and main-menu auto-hide.
- SoftMenu buttons bound only from a catalog of shipped windows.
- Quick Options for the seven toggles above, stored in the same config as everything else.
- Health, nano, and XP bars, a compass, a target frame, and shortcut bars as separate elements.
- Static hotkey labels and a horizontal/vertical axis toggle.
- Inventory, chat, a compact raid/group window with a smaller row than the standard preset, and an options window.
- Opacity, layout presets, UI scale, and an enable flag per element.

## Deferred classic extras

Not in v1, on purpose:

- The other classic themes: dovvetech dark, dovvetech edge, darktech mini HUD, and darktech glass. They fit the same token tables later.
- The theme customizer and the Control Center builder.
- Agg/Def bar, creds bar, NCU bar, mail notifier, perk-actions button, mouse pointers, and nano-icon border toggles.
- Extended menus: PvP, leet pet duel, pet control, visual-detail/performance shortcuts, and assist-macro creation.
- Full historic SoftMenu targets (Pets, Knowledge, Skills, Perks, Research, Mechs, Rollup) beyond the shipped-window catalog.
- The classic three-way text-color switch, info-window font size as its own installer toggle, and per-character versus global XML customization. v1 keeps one adjusted text color per theme and one config document.

## Spiritech custom UI API

The 2026-11-11 Spiritech post says the client is a new 64-bit engine for Windows, Linux, and Mac, with a Lua community UI API and no DLL injections, a fully scalable UI, and cloud sync for client settings. The binding surface used by this package is the client export in Lua API docs (shipped with the client in `client/docs/lua-api`), not that marketing post and not the 2021 plugin API.

Documented facts this package follows:

- Packages live in `UI/Addons` or the per-user `ui-packages` directory (`~/.local/share/ProjectRubiKa/ui-packages` on Linux). `package.xml` names windows and `main.lua`. A package is either a native UI role or standalone windows, not both.
- Coordinates are logical pixels. `ui.pixel_scale_x` and `ui.pixel_scale_y` are the framebuffer scale of those coordinates. `ui.parent_width` and `ui.parent_height` report the viewport for an unattached view. `ui.font_size` is a logical size from 1 to 256. `ui.opacity` is 0 through 1. `ui.progress` clamps a fraction to 0 through 1.
- `game.character.subscribe` delivers `bars.health`, `bars.nano`, and `bars.xp` as `CharacterBar` values (`current`, `maximum`, and a bounded `fraction`). That API is available to standalone addons.
- Native hotbar state (`HotbarState.vertical`, row labels with ten shown as zero) belongs to the built-in Hotbar package. A standalone addon does not receive `hotbar_apply`.
- `core.storage` / `ui.storage` is a per-package text store on this machine, shared by every character, capped at 4096 UTF-8 bytes per value. It is not account cloud sync.

Anything the export does not specify stays marked as an assumption in [design.md](design.md). The pure core never calls a live client. A missing probe is reported unavailable and load still returns.
