-- Loads the shipped ndgui modules and drives ndgui.load.
-- No reimplementation of theme tables, clamp math, or layout.

local function dirname(path)
  return path:match("^(.*)/[^/]+$") or "."
end

local root = dirname(dirname(arg[0] or ""))
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local ndgui = require("ndgui")
local theme = require("ndgui.theme")
local config = require("ndgui.config")
local layout = require("ndgui.layout")
local host = require("ndgui.host")
local menubar = require("ndgui.menubar")
local hud = require("ndgui.hud")
local windows = require("ndgui.windows")

local passed = 0

local function check(cond, msg)
  if not cond then
    print("FAIL: " .. msg)
    os.exit(1)
  end
  passed = passed + 1
  print("PASS: " .. msg)
end

local function near(a, b, eps)
  return math.abs(a - b) <= (eps or 1e-9)
end

local function has_button(model, id)
  for i = 1, #model.buttons do
    if model.buttons[i].id == id then return true end
  end
  return false
end

local function bar_labels(model, id)
  for i = 1, #model.bars do
    if model.bars[i].id == id then
      local labels = {}
      for s = 1, #model.bars[i].slots do
        labels[s] = model.bars[i].slots[s].hotkey
      end
      return table.concat(labels, ",")
    end
  end
  return nil
end

local function slots(n)
  local list = {}
  for i = 1, n do list[i] = { item = "s" .. i } end
  return list
end

-- Themes: color, frame, and density tokens differ, and windows read them.
local ids = theme.ids()
check(#ids == 4, "four v1 themes")
local seen_color, seen_frame, seen_density = {}, {}, {}
for i = 1, #ids do
  local t = theme.get(ids[i])
  check(t ~= nil, "theme " .. ids[i] .. " loads")
  local color_key = t.color.panel .. "|" .. t.color.text .. "|" .. t.color.accent .. "|" .. t.color.border
  local frame_key = t.frame.style .. "|" .. tostring(t.frame.border_px) .. "|" .. tostring(t.frame.radius_px)
  local density_key = t.density.id .. "|" .. tostring(t.density.bar_px) .. "|" .. tostring(t.density.menu_row_px) .. "|" .. tostring(t.density.font_px)
  check(not seen_color[color_key], "color tokens distinct for " .. ids[i])
  check(not seen_frame[frame_key], "frame tokens distinct for " .. ids[i])
  check(not seen_density[density_key], "density tokens distinct for " .. ids[i])
  seen_color[color_key] = true
  seen_frame[frame_key] = true
  seen_density[density_key] = true
  check(t.density.raid_row_compact_px < t.density.raid_row_px, "compact raid base is smaller in " .. ids[i])
end

local dove = ndgui.load({ config = { theme = "dovvetech" } })
local adapt = ndgui.load({ config = { theme = "adaptive" } })
check(dove.theme.color.text ~= adapt.theme.color.text, "theme switch changes text token")
check(dove.theme.frame.style ~= adapt.theme.frame.style, "theme switch changes frame style")
check(dove.theme.density.id ~= adapt.theme.density.id, "theme switch changes density")
check(dove.windows.chat.chrome.text == dove.theme.color.text, "chat reads theme text")
check(dove.windows.inventory.chrome.style == dove.theme.frame.style, "inventory reads theme frame")
check(dove.windows.raid.chrome.border_px == dove.theme.frame.border_px, "raid reads theme border")
check(dove.windows.options.chrome.text == dove.windows.chat.chrome.text, "options shares the active text token")
check(adapt.windows.chat.chrome.text == adapt.theme.color.text, "adaptive chat reads its own text")
check(adapt.windows.chat.chrome.text ~= dove.windows.chat.chrome.text, "windows follow the active theme")

-- Config round-trip.
local cfg = config.default()
cfg.theme = "darktech"
cfg.opacity = 0.55
cfg.ui_scale = 1.5
cfg.layout_preset = "efficient"
cfg.menubar.anchor = "left"
cfg.menubar.floating = true
cfg.menubar.fading = false
cfg.menubar.auto_hide = true
cfg.raid.preset = "compact"
cfg.shortcutbar.orientation = "vertical"
for i = 1, #config.ELEMENT_IDS do
  local id = config.ELEMENT_IDS[i]
  config.set_element(cfg, id, id == "chat" or id == "health" or id == "menubar")
end
for i = 1, #config.QUICK_OPTION_IDS do
  config.set_quick_option(cfg, config.QUICK_OPTION_IDS[i], i % 2 == 0)
end
check(menubar.assign(cfg, 1, "pets") == false, "SoftMenu rejects a target outside the catalog")
check(menubar.assign(cfg, 1, "inventory") == true, "SoftMenu accepts a catalog action")
check(menubar.assign(cfg, 2, "options") == true, "SoftMenu accepts a second catalog action")
local encoded = config.encode(cfg)
local again = config.decode(encoded)
check(again ~= nil, "config decode succeeds")
check(again.theme == "darktech", "config round-trips theme")
check(again.opacity == cfg.opacity, "config round-trips opacity")
check(again.ui_scale == 1.5, "config round-trips user ui scale")
check(again.menubar.anchor == "left", "config round-trips menubar anchor")
check(again.menubar.floating == true, "config round-trips floating")
check(again.menubar.fading == false, "config round-trips fading")
check(again.menubar.auto_hide == true, "config round-trips auto-hide")
check(again.layout_preset == "efficient", "config round-trips layout preset")
check(again.raid.preset == "compact", "config round-trips raid preset")
check(again.shortcutbar.orientation == "vertical", "config round-trips shortcut orientation")
check(again.elements.chat == true and again.elements.compass == false, "config round-trips enable flags")
check(again.elements.inventory == false and again.elements.health == true, "config round-trips each element flag")
check(again.menubar.enabled == again.elements.menubar, "menubar enable flag matches the element")
for i = 1, #config.QUICK_OPTION_IDS do
  local id = config.QUICK_OPTION_IDS[i]
  check(again.quick_options[id] == (i % 2 == 0), "Quick Options persist " .. id)
end
check(again.softmenu[1].action == "inventory" and again.softmenu[2].action == "options", "SoftMenu slots persist")
check(config.encode(again) == encoded, "config encode is stable")
check(config.storage_ok(encoded), "config fits the 4096-byte storage value")
check(config.storage_ok(config.encode(config.default())), "default config fits storage")

local dropped = config.normalize({
  softmenu = { { slot = 1, action = "pets" }, { slot = 2, action = "chat" } },
})
check(#dropped.softmenu == 1 and dropped.softmenu[1].action == "chat", "unknown SoftMenu actions are not kept")

-- Layout scale, including 1080p through 5K and client pixel scale.
local at1 = layout.place("classic", 1)
local at2 = layout.place("classic", 2)
check(#at1 > 1 and #at1 == #at2, "preset places more than one rectangle")
for i = 1, #at1 do
  check(at2[i].id == at1[i].id, "scaled rect keeps id " .. at1[i].id)
  check(at2[i].x == at1[i].x * 2, "x scales by 2 for " .. at1[i].id)
  check(at2[i].y == at1[i].y * 2, "y scales by 2 for " .. at1[i].id)
  check(at2[i].w == at1[i].w * 2, "w scales by 2 for " .. at1[i].id)
  check(at2[i].h == at1[i].h * 2, "h scales by 2 for " .. at1[i].id)
end
local at15 = layout.place("classic", 1.5)
for i = 1, #at1 do
  check(math.abs(at15[i].w - at1[i].w * 1.5) <= 0.5, "fractional scale stays within a pixel for " .. at1[i].id)
end
local eff1 = layout.place("efficient", 1)
local eff3 = layout.place("efficient", 3)
check(eff3[1].w == eff1[1].w * 3, "a second preset scales by the same rule")

local p1080 = layout.resolution({ w = 1920, h = 1080 }, 1, 1)
local p4k = layout.resolution({ w = 3840, h = 2160 }, 1, 1)
local p5k = layout.resolution({ w = 5120, h = 2880 }, 1, 1)
local client4k = layout.resolution({ w = 1920, h = 1080 }, 2, 1)
local client5k = layout.resolution({ w = 1920, h = 1080 }, 5120 / 1920, 1)
check(p1080.scale == 1, "1080p logical viewport stays at factor 1")
check(p4k.scale == 2, "4K logical viewport scales by 2")
check(near(p5k.scale, 5120 / 1920), "5K logical viewport scales by 5120/1920")
check(client4k.scale == 1 and client4k.pixel_scale == 2, "client pixel scale does not multiply a 1080p logical viewport")
check(layout.physical_px(22, client4k) == layout.physical_px(22, p4k), "4K client-scale and 4K logical agree in framebuffer pixels")
check(math.abs(layout.physical_px(22, client5k) - layout.physical_px(22, p5k)) <= 1, "5K client-scale and 5K logical agree within a pixel")
check(layout.resolution({ w = 1280, h = 720 }, 1, 1).factor == 1, "below 1080p does not shrink chrome")
check(near(layout.resolution({ w = 7680, h = 4320 }, 1, 1).factor, 5120 / 1920), "above 5K clamps to the 5K factor")
check(layout.resolution({ w = 3840, h = 2160 }, 1, 1.5).scale == 3, "user ui scale multiplies the viewport factor")
check(layout.font_px(15, 100) == 256, "font size clamps to the client maximum of 256")

local placed1080 = layout.place("classic", p1080.scale)
local placed4k = layout.place("classic", p4k.scale)
check(placed4k[1].w == placed1080[1].w * 2, "4K logical preset rectangles are twice 1080p")

-- Missing host binding does not abort. Real probe names are reported.
local bare = ndgui.load({ host = {}, config = config.default() })
check(bare.ok == true, "missing host bindings do not abort load")
check(#bare.unavailable == #host.PROBES, "every unbound probe is reported")
local saw_place = false
for i = 1, #bare.unavailable do
  if bare.unavailable[i] == "ui.place" then saw_place = true end
end
check(saw_place, "ui.place is reported unavailable")
local called, reason = bare.host.call("game.character.subscribe")
check(called == false and reason == "unavailable", "unbound host call returns unavailable")

local threw = ndgui.load({
  config = config.default(),
  input = { screen = { w = 1920, h = 1080 }, pixel_scale = 1 },
  host = {
    ["ui.parent_width"] = function() error("no view") end,
    ["ui.pixel_scale_x"] = function() return 2 end,
  },
})
check(threw.ok == true, "a throwing host call does not abort load")
check(threw.display.viewport_w == 1920, "failed viewport read keeps the fallback")
check(threw.display.pixel_scale == 2, "a successful pixel-scale read is kept")
check(threw.display.scale == 1, "pixel scale 2 on a 1080p logical view does not double layout")

local logical4k = ndgui.load({
  config = config.default(),
  input = { screen = { w = 1920, h = 1080 }, pixel_scale = 1 },
  host = {
    ["ui.parent_width"] = function() return 3840 end,
    ["ui.parent_height"] = function() return 2160 end,
    ["ui.pixel_scale_x"] = function() return 1 end,
    ["ui.pixel_scale_y"] = function() return 1 end,
  },
})
check(logical4k.ok == true, "4K host viewport loads")
check(logical4k.display.scale == 2, "4K host viewport resolves layout scale 2")
check(logical4k.menubar.rows == 1, "4K menubar is still one row")
check(logical4k.menubar.thickness == theme.get("dovvetech").density.menu_row_px * 2, "4K menubar thickness is one scaled row")

local bad_theme = ndgui.load({ config = { theme = "darktech_glass" } })
check(bad_theme.ok == true and bad_theme.theme.id == "dovvetech", "unknown theme falls back without aborting")
check(#bad_theme.warnings > 0, "unknown theme records a warning")

local bad_text = ndgui.load({ config = "this is not lua" })
check(bad_text.ok == true, "corrupt config text does not abort load")

-- Menubar: one row, anchors, float, fade, auto-hide.
local screen = { w = 1920, h = 1080 }
local dove_theme = theme.get("dovvetech")
local function menu(anchor, extra)
  local c = config.default()
  c.menubar.anchor = anchor
  c.menubar.floating = extra.floating and true or false
  c.menubar.fading = extra.fading and true or false
  c.menubar.auto_hide = extra.auto_hide and true or false
  return menubar.build(c, dove_theme, {
    scale = extra.scale or 1,
    screen = extra.screen or screen,
    hovered = extra.hovered and true or false,
  })
end

local top = menu("top", {})
local bottom = menu("bottom", {})
local left = menu("left", {})
local right = menu("right", {})
check(top.rows == 1 and bottom.rows == 1 and left.rows == 1 and right.rows == 1, "menubar thickness is one row")
check(top.thickness == dove_theme.density.menu_row_px, "docked thickness equals one menu row")
check(top.thickness == bottom.thickness and left.thickness == top.thickness, "every anchor uses the same one-row thickness")
check(top.axis == "horizontal" and bottom.axis == "horizontal", "top and bottom are horizontal")
check(left.axis == "vertical" and right.axis == "vertical", "left and right are vertical")
check(top.rect.h == top.thickness and bottom.rect.h == bottom.thickness, "horizontal short side is one row")
check(left.rect.w == left.thickness and right.rect.w == right.thickness, "vertical short side is one row")
check(top.rect.y == 0, "top anchor sits on the top edge")
check(bottom.rect.y + bottom.rect.h == screen.h, "bottom anchor sits on the bottom edge")
check(left.rect.x == 0, "left anchor sits on the left edge")
check(right.rect.x + right.rect.w == screen.w, "right anchor sits on the right edge")
check(top.anchor ~= bottom.anchor and left.anchor ~= right.anchor, "anchor state changes the menubar model")

local top_float = menu("top", { floating = true })
local bottom_float = menu("bottom", { floating = true })
local left_float = menu("left", { floating = true })
local right_float = menu("right", { floating = true })
check(top_float.floating and top_float.rect.y > top.rect.y, "floating moves the top bar off the edge")
check(bottom_float.rect.y < bottom.rect.y, "floating moves the bottom bar off the edge")
check(left_float.rect.x > 0, "floating moves the left bar off the edge")
check(right_float.rect.x + right_float.rect.w < screen.w, "floating moves the right bar off the edge")

local fade_off = menu("top", { fading = false, hovered = false })
local fade_idle = menu("top", { fading = true, hovered = false })
local fade_hot = menu("top", { fading = true, hovered = true })
check(fade_off.fade_opacity == 1, "fading off keeps full opacity")
check(fade_idle.fading and fade_idle.fade_opacity < 1, "fading idle lowers opacity")
check(fade_hot.fade_opacity == 1, "fading restores opacity while hovered")

local shown = menu("top", { auto_hide = false, hovered = false })
local hidden_menu = menu("top", { auto_hide = true, hovered = false })
local revealed = menu("top", { auto_hide = true, hovered = true })
check(shown.main_menu_visible and has_button(shown, "char"), "auto-hide off keeps the main menu")
check(hidden_menu.auto_hide and not hidden_menu.main_menu_visible and not has_button(hidden_menu, "char"), "auto-hide hides the main menu")
check(has_button(hidden_menu, "quick_options"), "auto-hide keeps Quick Options on the row")
check(revealed.main_menu_visible and has_button(revealed, "info"), "hover shows the main menu again")

local wide = menu("right", { screen = { w = 3840, h = 2160 }, scale = 2 })
check(wide.rows == 1, "4K menubar is one row")
check(wide.rect.w == wide.thickness, "4K vertical bar short side is the scaled row")
check(wide.rect.x + wide.rect.w == 3840, "4K right anchor uses the logical viewport edge")
check(wide.thickness == top.thickness * 2, "layout scale 2 doubles one row, it does not add a row")

local mini = menubar.build(config.default(), theme.get("darktech_mini"), { scale = 1, screen = screen })
check(mini.thickness == theme.get("darktech_mini").density.menu_row_px, "menubar thickness follows the theme row")
check(mini.thickness ~= top.thickness, "theme switch changes menubar thickness without a second menubar")

-- SoftMenu catalog opens shipped windows.
local cat = menubar.catalog()
local opens = {}
for i = 1, #cat do opens[cat[i].opens] = true end
check(opens.inventory and opens.chat and opens.raid and opens.options, "SoftMenu catalog opens the shipped windows")
local assigned = config.default()
menubar.assign(assigned, 1, "raid")
menubar.assign(assigned, 2, "chat")
local built = menubar.build(assigned, dove_theme, { scale = 1, screen = screen })
check(built.softmenu_actions[1] == "raid" and built.softmenu_actions[2] == "chat", "SoftMenu buttons use catalog action ids")

-- HUD fractions, hotkeys, axis, raid rows, enable flags.
check(hud.fraction(150, 100) == 1, "health fraction clamps above max")
check(hud.fraction(-5, 200) == 0, "nano fraction clamps below zero")
check(near(hud.fraction(50, 200), 0.25), "xp fraction is current/max")
check(hud.fraction(10, 0) == 0, "a zero max clamps to zero")
check(hud.fraction(10, nil) == 0, "a missing max clamps to zero")
check(hud.bar_fraction({ fraction = 1.4 }) == 1, "a native fraction above one clamps")
check(near(hud.bar_fraction({ fraction = 0.25 }), 0.25), "a native fraction is used when current is absent")

local snap = {
  health = { current = 150, max = 100 },
  nano = { current = -5, max = 200 },
  xp = { current = 50, max = 200 },
  shortcuts = {
    { id = "main", slots = slots(4) },
    { id = "alt", slots = slots(4) },
    { id = "extra", slots = slots(4) },
  },
}
local loaded_bars = ndgui.load({ config = config.default(), snapshot = snap })
check(loaded_bars.hud.health == 1, "load reports clamped health")
check(loaded_bars.hud.nano == 0, "load reports clamped nano")
check(near(loaded_bars.hud.xp, 0.25), "load reports clamped xp")

local hot_cfg = config.default()
hot_cfg.shortcutbar.order = { "main", "alt", "extra" }
hot_cfg.shortcutbar.hidden = {}
hot_cfg.shortcutbar.orientation = "horizontal"
local before = hud.shortcuts(hot_cfg, snap, dove_theme, 1)
hot_cfg.shortcutbar.order = { "extra", "main" }
hot_cfg.shortcutbar.hidden = { alt = true }
local after = hud.shortcuts(hot_cfg, snap, dove_theme, 1)
check(bar_labels(before, "main") == bar_labels(after, "main"), "hotkey labels stay fixed when bars are reordered")
check(bar_labels(before, "extra") == bar_labels(after, "extra"), "hotkey labels stay fixed when a bar is hidden")
check(bar_labels(after, "alt") == nil, "a hidden shortcut bar is absent")
check(after.bars[1].id == "extra" and after.bars[2].id == "main", "visible bars follow the new order")
check(bar_labels(before, "main") == "1,2,3,4", "slot labels are the static 1-based numbers")
check(hud.hotkey_label(10) == "0", "slot 10 keeps the static 0 label")

local horiz = hud.shortcuts(hot_cfg, snap, dove_theme, 1)
hot_cfg.shortcutbar.orientation = "vertical"
local vert = hud.shortcuts(hot_cfg, snap, dove_theme, 1)
check(horiz.axis == "horizontal" and vert.axis == "vertical", "horizontal/vertical toggle swaps the shortcut axis")
check(horiz.bars[1].rect.w > horiz.bars[1].rect.h, "horizontal bar is wider than it is tall")
check(vert.bars[1].rect.h > vert.bars[1].rect.w, "vertical bar is taller than it is wide")

for i = 1, #ids do
  local t = theme.get(ids[i])
  local compact = windows.raid_row_px("compact", t, 1)
  local standard = windows.raid_row_px("standard", t, 1)
  check(compact < standard, "compact raid row is smaller for " .. ids[i])
  local compact4 = windows.raid_row_px("compact", t, 2)
  local standard4 = windows.raid_row_px("standard", t, 2)
  check(compact4 < standard4, "compact raid row stays smaller at 4K scale for " .. ids[i])
end

local raid_std = config.default()
raid_std.raid.preset = "standard"
local raid_cmp = config.default()
raid_cmp.raid.preset = "compact"
local std_session = ndgui.load({ config = raid_std })
local cmp_session = ndgui.load({ config = raid_cmp })
check(cmp_session.windows.raid.row_px < std_session.windows.raid.row_px, "compact raid/group preset uses a smaller row")

for i = 1, #config.ELEMENT_IDS do
  local id = config.ELEMENT_IDS[i]
  local off = config.default()
  config.set_element(off, id, false)
  local hidden = ndgui.load({ config = off, snapshot = snap })
  check(hidden.elements[id] == nil, id .. " is absent when disabled")
  local on = config.default()
  config.set_element(on, id, true)
  local shown_el = ndgui.load({ config = on, snapshot = snap })
  check(shown_el.elements[id] ~= nil, id .. " is present when enabled")
end

-- Fixture through the same entry the consumer uses.
local fixture = dofile(root .. "/fixtures/session.lua")
local first = ndgui.load({
  config = fixture.config,
  snapshot = fixture.snapshot,
  input = fixture.input,
  host = fixture.host,
})
local second = ndgui.load({
  config = fixture.config,
  snapshot = fixture.snapshot,
  input = fixture.input,
  host = fixture.host,
})
local text_a = ndgui.format_observable(first)
local text_b = ndgui.format_observable(second)
check(text_a == text_b, "two loads of the fixture print the same observable")
check(first.theme.id == "dovvetech", "fixture theme is a v1 theme")
check(first.theme.frame.style ~= "" and first.theme.color.text ~= "", "fixture frame and text tokens are set")
check(first.menubar.anchor == "top" and first.menubar.floating and first.menubar.fading and first.menubar.auto_hide, "fixture menubar flags match")
check(first.menubar.softmenu_actions[1] == "chat" and first.menubar.softmenu_actions[2] == "options", "fixture SoftMenu actions match")
check(first.hud.health == 1 and first.hud.nano == 0 and near(first.hud.xp, 0.25), "fixture fractions match the clamped snapshot")
check(first.hud.hotkey_text == "main:1,2,3,4,5,6,7,8,9,0;alt:1,2,3,4,5,6,7,8,9,0", "fixture hotkey labels match")
check(first.hud.shortcut_axis == "horizontal", "fixture shortcut axis matches")
check(first.elements.compass == nil and first.elements.inventory == nil, "disabled fixture elements are absent")
check(first.elements.chat ~= nil and first.elements.target ~= nil, "enabled fixture elements are present")
check(first.display.viewport_w == 3840 and first.display.viewport_h == 2160, "fixture viewport is 4K")
check(first.display.scale == 2 and first.display.pixel_scale == 1, "fixture 4K logical scale is 2")
local unavailable = {}
for i = 1, #first.unavailable do unavailable[first.unavailable[i]] = true end
check(unavailable["ui.place"] and unavailable["ui.storage.write"] and unavailable["game.character.subscribe"], "unbound fixture host calls are listed")
check(not unavailable["ui.parent_width"] and not unavailable["ui.opacity"], "bound fixture host calls are not listed")
check(string.find(text_a, "elements=", 1, true) ~= nil, "observable lists elements")
check(string.find(text_a, "compass", 1, true) == nil, "observable omits the disabled compass")

-- Client entry: dofile the real main.lua against a host that already
-- has a non-default config document.
local function run_main(store, counts)
  local previous_ui = _G.ui
  local previous_game = _G.game
  _G.ui = {
    storage = {
      read = function(key)
        counts.read = counts.read + 1
        counts.order[#counts.order + 1] = "read"
        if key ~= "config" then return "" end
        return store.config or ""
      end,
      write = function(key, value)
        counts.write = counts.write + 1
        counts.order[#counts.order + 1] = "write"
        store[key] = value
      end,
    },
  }
  _G.game = nil
  dofile(root .. "/main.lua")
  _G.ui = previous_ui
  _G.game = previous_game
end

local saved = config.default()
saved.theme = "darktech"
saved.opacity = 0.4
saved.ui_scale = 1.5
saved.menubar.anchor = "bottom"
local store = { config = config.encode(saved) }
local counts = { read = 0, write = 0, order = {} }
run_main(store, counts)
local kept = config.decode(store.config)
check(counts.read >= 1, "main.lua reads storage key config")
check(counts.order[1] == "read", "main.lua reads config before it writes")
check(counts.write == 1, "main.lua writes the normalized config once")
check(kept.theme == "darktech", "stored theme survives main.lua")
check(kept.opacity == 0.4, "stored opacity survives main.lua")
check(kept.ui_scale == 1.5, "stored ui_scale survives main.lua")
check(kept.menubar.anchor == "bottom", "stored anchor survives main.lua")
check(kept.theme ~= config.default().theme or saved.theme == "dovvetech", "main.lua did not replace the stored theme with the default")

local empty_store = {}
local empty_counts = { read = 0, write = 0, order = {} }
run_main(empty_store, empty_counts)
local seeded = config.decode(empty_store.config)
check(empty_counts.read >= 1 and empty_counts.write == 1, "an empty config key is read and then seeded")
check(seeded.theme == "dovvetech" and seeded.menubar.anchor == "top", "an empty config key seeds defaults")

local thrown_original = config.encode(saved)
local thrown_store = { config = thrown_original }
local thrown_counts = { read = 0, write = 0 }
local previous_ui = _G.ui
local previous_game = _G.game
_G.ui = {
  storage = {
    read = function()
      thrown_counts.read = thrown_counts.read + 1
      error("storage down")
    end,
    write = function(key, value)
      thrown_counts.write = thrown_counts.write + 1
      thrown_store[key] = value
    end,
  },
}
_G.game = nil
dofile(root .. "/main.lua")
_G.ui = previous_ui
_G.game = previous_game
check(thrown_counts.read >= 1, "main.lua still calls storage read when it throws")
check(thrown_counts.write == 0, "a throwing storage read does not write")
check(thrown_store.config == thrown_original, "a throwing storage read leaves the previous config bytes unchanged")

print("ALL PASS " .. tostring(passed))
