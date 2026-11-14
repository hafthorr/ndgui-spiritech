-- Provider packages (notum.ndgui-*) under the mock host: each stock callback contract.
-- Run: lua tests/test_providers.lua
local here = ((arg[0] or ""):gsub("\\", "/"):match("^(.*)/tests/[^/]+$") or ".")
package.path = here .. "/tests/?.lua;" .. package.path
local Mock = require("mock_host")
local addons = here .. "/.."
local core = here .. "/../../Packages/Core"
local W, Hh = 2000, 1334
local fail = 0
local function check(cond, msg) print((cond and "PASS " or "FAIL ") .. msg); if not cond then fail = fail + 1 end end
local function load_pkg(folder)
  local H = Mock.new(addons, core, { width = W, height = Hh })
  local ok, err = pcall(H.load_package, folder)
  check(ok, folder .. " loads" .. (ok and "" or (": " .. tostring(err))))
  return ok and H or nil
end
local function role(H, r) return H and H.manifest:find('<Provides role="' .. r .. '"', 1, true) ~= nil end

-- Status bars: one VM per kind.
local placed = {}
for _, case in ipairs({
  { "health", { current = 129, maximum = 129, fraction = 1 }, "129 / 129" },
  { "nano", { current = 90, maximum = 90, fraction = 1 }, "90 / 90" },
  { "experience", { current = 1396, maximum = 4500, fraction = 1396 / 4500 }, "XP  1,396 / 4,500" },
  { "alien", { current = nil, maximum = 1000, fraction = 0 }, "AXP  -- / 1,000" },
}) do
  local H = load_pkg("ndgui-status-bars")
  if H then
    check(role(H, "prk.status-bars"), "status bars declare prk.status-bars")
    H.env.status_bar_initialize(case[1])
    H.env.status_bar_apply(case[2], false)
    local cap = H.find(H.root, "status_caption")
    check(cap and cap.text == case[3], case[1] .. " caption = " .. tostring(cap and cap.text))
    if case[1] == "health" or case[1] == "nano" then
      local shade = H.find(H.root, "status_caption_shadow")
      check(shade and shade.text == case[3], case[1] .. " caption has a drop shadow")
      local mv = H.moves[#H.moves]
      local o = mv.options
      local edit = H.find(H.root, "status_edit")
      check(edit and edit.visible == false, case[1] .. " edit strip hidden until double-click")
      check(o.enabled(10, 10) == true, case[1] .. " drags while unlocked")
      local function click() o.enabled(10, 10); o.finished(true, 10, 10); H.now = H.now + 150 end
      click(); click()
      edit = H.find(H.root, "status_edit")
      check(edit.visible == true, case[1] .. " double-click shows the Lock / Flat strip")
      local bar = H.find(H.root, "status_bar")
      check(bar.tooltip and bar.tooltip:find("Double%-click"), case[1] .. " tooltip explains the double-click")
      H.find(H.root, "status_lock").on_click()
      local home_x, home_y = H.root.x, H.root.y
      H.root.x, H.root.y = 300, 400
      o.enabled(10, 10)
      H.root.x, H.root.y = 520, 610  -- core.move drags it...
      o.changed(520, 610)          -- ...and the lock snaps it back
      o.finished(true, 230, 220)
      check(H.root.x == 300 and H.root.y == 400 and H.state[mv.view].NdguiLocked == "true" and H.find(H.root, "status_lock").selected == true,
        case[1] .. " Lock: drag snaps back, saved, button lit (" .. H.root.x .. "," .. H.root.y .. ")")
      H.now = H.now + 1000
      H.find(H.root, "status_flat").on_click()
      local flat_bar = H.find(H.root, "status_bar")
      local cap = H.find(H.root, "status_caption")
      check(H.state[mv.view].NdguiFlat == "true" and flat_bar.w == nil or flat_bar ~= bar, case[1] .. " Flat rebuilds the bar")
      check(H.find(flat_bar, "status_caption") == cap and cap.text == case[3], case[1] .. " flat: number sits inside the bar (" .. tostring(cap.text) .. ")")
      check(H.root.w == 160, case[1] .. " flat bar is 160 wide (" .. tostring(H.root.w) .. ")")
      H.env.status_bar_apply({ current = 1, maximum = 2, fraction = 0.5 }, false)
      local fill = H.find(H.root, "status_fill")
      check(fill.w == 80 and fill.h == 18, case[1] .. " flat fill grows sideways (" .. tostring(fill.w) .. "x" .. tostring(fill.h) .. ")")
      check(H.find(H.root, "status_edit").visible == true and H.find(H.root, "status_flat").selected == true, case[1] .. " strip stays open, Flat lit")
      click(); click()
      check(H.find(H.root, "status_edit").visible == false, case[1] .. " double-click again hides the strip")
      H.find(H.root, "status_flat").on_click()  -- back to vertical for the fill checks below
      H.env.status_bar_apply(case[2], false)
      check(H.state[mv.view].NdguiFlat == "false" and H.find(H.root, "status_caption_plate") ~= nil, case[1] .. " Flat off restores the vertical bar")
      H.root.x, H.root.y = home_x, home_y
      -- saved settings only become readable at the native "restore" phase, not at load
      H.state[mv.view].NdguiFlat = "true"
      check(H.state_handlers[mv.view] ~= nil, case[1] .. " listens for the restore phase")
      H.state_handlers[mv.view]("restore")
      check(H.find(H.root, "status_caption").parent == nil and H.find(H.find(H.root, "status_bar"), "status_caption") ~= nil,
        case[1] .. " restore applies the saved Flat setting")
      check((H.placements[#H.placements].restored or 0) >= 1, case[1] .. " restore still restores the position")
      H.state[mv.view].NdguiFlat = "false"
      H.state_handlers[mv.view]("restore")
    end
    local fill = H.find(H.root, "status_fill")
    local vertical = case[1] == "health" or case[1] == "nano"
    local length = vertical and fill.h or fill.w
    local full = vertical and 140 or H.root.w
    if case[2].fraction > 0 then
      check(fill.visible ~= false and length == math.floor(full * case[2].fraction + 0.5),
        case[1] .. " fill " .. tostring(length) .. " of " .. tostring(full))
    else
      check(fill.visible == false, case[1] .. " empty fill hidden")
    end
    check(fill.image and fill.image:match("^library://notum%.ndgui%-lib/bars/"), case[1] .. " uses ndGUI art")
    local r = H.root
    if case[1] == "health" or case[1] == "nano" then
      check(r.x >= 0 and r.x + r.w <= W and r.y + r.h <= Hh - 30, case[1] .. " above the strip at " .. r.x .. "," .. r.y)
    else
      check(r.y >= Hh - 30 and r.y + r.h <= Hh and r.x >= 440 and r.x + r.w <= W - 470,
        case[1] .. " docked in the strip between the icon clusters at " .. r.x .. "," .. r.y .. " w=" .. r.w)
    end
    placed[case[1]] = H.root
    if case[1] == "experience" then
      H.env.status_bar_apply(case[2], true)
      check(cap.text == "SK  1,396 / 4,500", "shadowknowledge relabels XP as SK")
    end
  end
end
if placed.health and placed.nano then
  check(placed.health.x + placed.health.w < W / 2 and placed.nano.x > W / 2, "HP left of centre, NP right of centre")
end
if placed.experience and placed.alien then
  check(placed.experience.x + placed.experience.w <= placed.alien.x, "XP and AXP do not overlap")
end

-- Compass.
local C = load_pkg("ndgui-compass")
if C then
  check(role(C, "prk.compass"), "compass declares prk.compass")
  C.env.compass_place(W)
  check(math.abs((C.root.x + C.root.w / 2) - W / 2) <= 1 and C.root.y == 4, "compass centred on the top edge")
  C.env.compass_apply({ has_heading = true, heading = 1.0, has_waypoint = true, has_position = true,
    waypoint_playfield = 1, playfield = 1, x = 0, z = 0, waypoint_x = 10, waypoint_z = 10 })
  check((C.calls["compass.sprite"] or 0) == 4 and C.calls["compass.finish"] == 1, "compass draws band twice, waypoint and caret")
  check(C.find(C.root, "compass_distance").text == "14 m", "compass shows the waypoint distance: " .. tostring(C.find(C.root, "compass_distance").text))
  check(C.root.w == 320, "compass is 320 wide with the ndGUI art")
  check(C.find(C.root, "ndgui_compass_frame").visible == false, "no plate or frame with the ndGUI art")
end
-- without the ndGUI skin installed: the old framed stock compass
local C2 = Mock.new(addons, core, { width = W, height = Hh })
C2.env.ui.compass.graphic_width = function(g) return g:find("NDGUI", 1, true) and 0 or 256 end
if pcall(C2.load_package, "ndgui-compass") then
  C2.env.compass_apply({ has_heading = true, heading = 1.0 })
  check(C2.root.w == 137 and C2.find(C2.root, "ndgui_compass_frame").visible == true
    and C2.find(C2.root, "compass_band").w == 129, "skin missing: framed stock compass")
end

-- Target panels: fixed-size unit frames fed by the native slot plus game.character facts.
local rects = {}
for _, hostile in ipairs({ false, true }) do
  local T = load_pkg("ndgui-target-panels")
  if T then
    local tag = hostile and "hostile" or "friendly"
    check(role(T, "prk.target-panels"), "target panels declare prk.target-panels")
    local frame1, frame2 = T.root.kids[1], T.root.kids[2]
    local function v(frame, name) return T.find(frame, name) end
    check(#T.subs == 3, tag .. " subscribes to target, fight and self (" .. #T.subs .. ")")
    -- subs in order: target, fight, self
    T.subs[3]({ reset = true }, { name = "Ninnai", is_self = true, is_npc = false, x = 0, y = 0, z = 0, profession = 10, level = 42,
      health = 900, max_health = 1000, nano = 300, max_nano = 600, side = 2 })
    T.subs[1]({ reset = true }, { name = "Surf Lizard", is_npc = true, level = 12, health = 400, max_health = 1000, x = 30, y = 0, z = 40 })
    T.env.target_panel_place(W, hostile)
    local slot = { name = "Surf Lizard", has_bar = true, length = 0.5, fraction = 0.4, bar_color = 0xd24b4b,
      in_reach = true, header = "Lizard", name_color = 0xffffff }
    T.env.target_panel_apply(slot, { name = "" }, W)
    local w = T.root.w
    check(w == 300, tag .. " frame is a fixed 300 wide at size M (" .. tostring(w) .. ")")
    check(v(frame1, "name").text == "Surf Lizard", tag .. " shows target name")
    check(v(frame2, "frame").visible == false, tag .. " empty lower slot hides")
    local inner = v(frame1, "hp").w
    check(v(frame1, "hp_fill").w == math.floor(inner * 0.4 + 0.5) and v(frame1, "hp_fill").tint == "#d24b4b", tag .. " fill 40% in con colour")
    check(v(frame1, "hp_text").text == "400 / 1,000 (40%)", tag .. " exact HP inside the bar: " .. tostring(v(frame1, "hp_text").text))
    check(v(frame1, "portrait_level").text == "12" and v(frame1, "portrait_icon").visible == false, tag .. " NPC portrait shows level")
    check(v(frame1, "distance").text == "50 m" and v(frame1, "reach").fill == "#6fd46f", tag .. " distance 50 m, reach lit")
    check(v(frame1, "info").text == "NPC" and v(frame1, "np").visible == false, tag .. " NPC info, no nano bar")
    check(v(frame1, "accent").fill == "#d24b4b", tag .. " accent stripe in con colour")
    -- damage: ghost holds the old 40%, then drains; under 25% the fill pulses
    local updates = #T.updates
    T.subs[1]({}, { name = "Surf Lizard", is_npc = true, level = 12, health = 200, max_health = 1000, x = 30, y = 0, z = 40 })
    T.env.target_panel_apply({ name = "Surf Lizard", has_bar = true, fraction = 0.2, bar_color = 0xd24b4b, in_reach = false, name_color = 0xffffff }, { name = "" }, W)
    check(v(frame1, "hp_ghost").visible ~= false and v(frame1, "hp_ghost").w == math.floor(inner * 0.4 + 0.5), tag .. " ghost marks the lost 20%")
    check(#T.updates > updates, tag .. " animation starts")
    local tick = T.updates[#T.updates]
    local t0 = T.now
    tick(t0 + 100); check(v(frame1, "hp_ghost").w == math.floor(inner * 0.4 + 0.5), tag .. " ghost holds briefly")
    tick(t0 + 550)
    local mid = v(frame1, "hp_ghost").w
    check(mid < math.floor(inner * 0.4 + 0.5) and mid > math.floor(inner * 0.2 + 0.5), tag .. " ghost drains (" .. tostring(mid) .. ")")
    tick(t0 + 1200)
    check(v(frame1, "hp_ghost").visible == false, tag .. " ghost gone once drained")
    check(v(frame1, "hp_fill").opacity ~= nil and v(frame1, "reach").fill == "#33424f", tag .. " low HP pulses; reach dims")
    -- a player (you) in the lower slot: profession portrait, level, nano, side
    T.env.target_panel_apply(slot, { name = "Ninnai", has_bar = true, fraction = 0.9, bar_color = 0xe0d040, name_color = 0xffffff }, W)
    check(v(frame2, "portrait_icon").image == "gfx://GFX_GUI_ICON_PROFESSION_LARGE_10" and v(frame2, "level").text == "Lv 42",
      tag .. " player portrait = profession icon, Lv 42")
    check(v(frame2, "np").visible == true and v(frame2, "np_fill").w == math.floor(inner * 0.5 + 0.5), tag .. " nano bar at 50%")
    check(v(frame2, "info").text == "Doctor · Omni" and v(frame2, "distance").text == "", tag .. " info: Doctor · Omni, no distance to self")
    -- contrast: black HP text on a bright (yellow) bar, white on red
    check(v(frame2, "hp_text").color == "#000000" and v(frame2, "hp_shadow").color == "#FFFFFF", tag .. " black HP text on yellow")
    check(v(frame1, "hp_text").color == "#FFFFFF", tag .. " white HP text on red")
    -- a name wider than its box scrolls
    T.env.ui.text_width = function(view) return #(view.text or "") * 9 end
    local long = "Deathless Legionnaire of the Northern Reach"
    T.env.target_panel_apply({ name = long, has_bar = true, fraction = 0.9, bar_color = 0x40d020, name_color = 0xffffff }, { name = "" }, W)
    local shown = v(frame1, "name").text
    check(#shown < #long and long:sub(1, #shown) == shown and #shown * 9 <= v(frame1, "name").w,
      tag .. " long name is cut to its box: " .. shown)
    check(v(frame1, "hp_text").color == "#000000", tag .. " black HP text on green")
    local tk = T.updates[#T.updates]
    tk(T.now + 1600)
    check(v(frame1, "name").text == long:sub(2, #shown + 1), tag .. " name scrolls after a pause: " .. v(frame1, "name").text)
    tk(T.now + 60000); tk(T.now + 61600); tk(T.now + 63300)
    T.env.target_panel_apply({ name = "Surf Lizard", has_bar = true, fraction = 0.9, bar_color = 0x40d020, name_color = 0xffffff }, { name = "" }, W)
    check(v(frame1, "name").text == "Surf Lizard", tag .. " short name shows whole again")
    T.env.ui.text_width = nil
    rects[tag] = { x = T.root.x, w = T.root.w }
    -- saved Size comes back at the restore phase
    local view = T.moves[#T.moves].view
    T.state[view] = T.state[view] or {}
    T.state[view].NdguiSize = "S"
    T.state_handlers[view]("restore")
    check(T.root.w == 250, tag .. " restore applies saved Size S (" .. tostring(T.root.w) .. ")")
    T.state[view].NdguiSize = "M"
    T.state_handlers[view]("restore")
    -- options: double-click -> Size cycles M -> L, Compact hides portrait and info
    local mv = T.moves[#T.moves].options
    mv.enabled(5, 5); mv.finished(true, 5, 5); T.now = T.now + 100; mv.enabled(5, 5); mv.finished(true, 5, 5); T.now = T.now + 1000
    check(T.find(T.root, "target_edit").visible == true, tag .. " double-click opens Lock / Size / Compact")
    T.find(T.root, "target_size").on_click()
    check(T.root.w == 363 and T.find(T.root, "target_size").text == "Size L", tag .. " Size L = 363 wide (" .. tostring(T.root.w) .. ")")
    T.find(T.root, "target_compact").on_click()
    check(v(frame1, "portrait").visible == false and v(frame1, "row_info").visible == false and v(frame1, "level").text == "Lv 12",
      tag .. " compact: name + bar (+ level)")
  end
end
if rects.friendly and rects.hostile then
  local f, h = rects.friendly, rects.hostile
  check(f.x + f.w <= W / 2 - 160 and h.x >= W / 2 + 160, "panels clear the 320px compass")
  check(f.x >= 0 and h.x + h.w <= W, "panels stay on screen")
end

-- Team window: one unit frame per member, click-to-target kept, floating numbers from game.combat.
do
  local H = Mock.new(addons, core, { width = W, height = Hh, loose = true })
  local team_cb, binds = nil, {}
  local game = H.env.game
  game.team = setmetatable({ subscribe = function(cb) team_cb = cb end, prepare_leave = function() return 1 end,
    prepare_invite = function() return 2 end, prepare_kick = function() return 3 end, prepare_leader = function() return 4 end },
    { __index = function() return function() end end })
  game.targeting = { subscribe = function() end, prepare_select = function(ref) return "select:" .. ref end }
  local unsubscribed = 0
  game.character.unsubscribe = function() unsubscribed = unsubscribed + 1 end
  H.env.ui.actions = setmetatable({ bind = function(v, action) binds[v] = action end }, { __index = function() return function() end end })
  local ok, err = pcall(H.load_package, "ndgui-team")
  check(ok, "ndgui-team loads" .. (ok and "" or (": " .. tostring(err))))
  if ok then
    check(role(H, "prk.team"), "team declares prk.team")
    check(type(team_cb) == "function", "team subscribes to the roster")
    local function member(ref, name, prof, hp, max, leader, present, is_self)
      return { own_team = true, leader = leader, character = { reference = ref, id = #ref, name = name, is_self = is_self,
        present = present, is_npc = false, profession = prof, level = 50, health = hp, max_health = max, nano = 100, max_nano = 200, side = 1 } }
    end
    team_cb({ data = { in_team = true, can_invite = true, side = 1, context = 1, members = {
      member("me", "Ninnai", 10, 900, 1000, true, true, true), member("r2", "Bob", 1, 250, 1000, false, true),
      member("r33", "Gone", 4, 0, 800, false, false) } } })
    local host = H.find(H.root, "team_rows")
    local rows = host.kids
    local function u(i, name) return H.find(rows[i], name) end
    check(rows[1].visible == true and rows[3].visible == true and rows[4].visible == false, "three members shown, empty rows hidden")
    check(u(1, "name").text == "Ninnai" and u(1, "name").color == "#11EEAA" and u(1, "accent").fill == "#11EEAA", "leader: green name and stripe")
    check(u(2, "hp_text").text == "250 / 1,000 (25%)" and u(2, "portrait_icon").image == "gfx://GFX_GUI_ICON_PROFESSION_LARGE_1",
      "member: exact HP and profession portrait")
    check(u(2, "info").text == "Soldier · Clan" and u(2, "np").visible == true, "member: info row and nano bar")
    check(u(3, "name").color == "#888888" and u(3, "body").opacity == 0.55, "absent member greyed")
    check(binds[rows[2]] == "select:r2" and binds[u(2, "hp_text")] == "select:r2", "left-click on any part targets the member")
    -- distance: the member's own Character subscription plus self
    local subs = #H.subs
    check(subs >= 3, "member positions + self subscribed (" .. subs .. ")")
    -- subscribed in order: self (at load), then Bob and Gone (roster)
    H.subs[1]({}, { name = "Ninnai", is_self = true, x = 0, y = 0, z = 0 })
    H.subs[2]({}, { name = "Bob", x = 3, y = 0, z = 4 })
    check(u(2, "distance").text == "5.0 m", "member distance " .. tostring(u(2, "distance").text))
    -- combat numbers float over the member that took them
    H.combat({ { kind = "damage", amount = 120, target = 0, target_name = "Bob", source = 0, source_name = "Mob", critical = false },
      { kind = "healing", amount = 40, target = 0, target_name = "Ninnai", target_is_self = true } })
    check(u(2, "float_1").visible == true and u(2, "float_1_text").text == "-120", "damage floats over Bob")
    check(u(1, "float_1_text").text == "+40", "healing floats over you")
    -- Compact: name, level and health bar only
    local tall = u(2, "accent").h
    H.find(H.root, "compact_toggle").on_click()
    check(H.find(H.root, "compact_toggle").selected == true and u(2, "portrait").visible == false and u(2, "row_info").visible == false
      and u(2, "np").visible == false and u(2, "hp_text").text == "250 / 1,000 (25%)" and u(2, "level").text == "Lv 50", "Compact: name, level, HP bar")
    check(u(2, "accent").h < tall, "Compact rows are shorter (" .. tostring(u(2, "accent").h) .. " < " .. tostring(tall) .. ")")
    H.find(H.root, "compact_toggle").on_click()
    check(u(2, "portrait").visible == true and u(2, "row_info").visible == true, "Compact off: full frames again")
    -- a member leaves: their subscription is dropped
    team_cb({ data = { in_team = true, can_invite = true, side = 1, context = 2, members = {
      member("me", "Ninnai", 10, 900, 1000, true, true, true) } } })
    check(rows[2].visible == false and unsubscribed >= 1, "leaving member hidden and unwatched")
  end
end

-- Unit frame combat matching: names first, ids once they prove to agree; floats rise and fade.
do
  local T = load_pkg("ndgui-target-panels")
  if T then
    T.subs[1]({}, { id = 77, name = "Scalecoil", is_npc = true, level = 2, health = 173, max_health = 190 })
    T.env.target_panel_place(W, true)
    T.env.target_panel_apply({ name = "Scalecoil", has_bar = true, fraction = 0.91, bar_color = 0xd24b4b, in_reach = true, name_color = 0xffffff }, { name = "" }, W)
    local f1 = T.root.kids[1]
    check(#T.combat_subs == 1, "target panels watch game.combat once")
    T.combat({ { kind = "damage", amount = 17, critical = true, target = 77, target_name = "Scalecoil", source_is_self = true, source_name = "Ninnai" } })
    check(T.find(f1, "float_1_text").text == "-17!" and T.find(f1, "float_1_text").font == math.floor(15 * 1.2), "crit floats big: -17!")
    -- same name, different id: ignored now that ids proved to agree
    T.combat({ { kind = "damage", amount = 5, target = 78, target_name = "Scalecoil" } })
    check(T.find(f1, "float_2").visible ~= true, "another mob with the same name does not float here")
    -- target attacks you -> "» You"
    T.combat({ { kind = "attack_started", source = 77, source_name = "Scalecoil", target_is_self = true, target_name = "Ninnai" } })
    check(T.find(f1, "tot").visible == true and T.find(f1, "tot").text == "» You" and T.find(f1, "tot").color == "#ffa040", "target-of-target: » You")
    local tick = T.updates[#T.updates]
    tick(T.now + 500)
    local b = T.find(f1, "float_1").borders
    check(b and b[2] < 4 + math.floor(18 * 1.2) + 2, "float rises")
    tick(T.now + 1200)
    check(T.find(f1, "float_1").visible == false, "float gone after its life")
    tick(T.now + 9000)
    check(T.find(f1, "tot").visible == false, "» You fades after 8 s without attacks")
  end
end

-- Damage meter: standalone window (Control Center > Actions > Addons) over game.combat.
do
  local H = Mock.new(addons, core, { width = W, height = Hh, loose = true })
  local registered, roster
  H.env.ui.register_view = function(v, id) registered = id end
  H.env.game.team = { subscribe = function(cb) roster = cb end }
  local ok, err = pcall(H.load_package, "ndgui-meter")
  check(ok, "ndgui-meter loads" .. (ok and "" or (": " .. tostring(err))))
  if ok then
    local function f(name) return H.find(H.root, name) end
    check(H.manifest:find('<View id="meter"', 1, true) ~= nil and registered == "meter", "meter is a registered addon window")
    check(#H.combat_subs == 1, "meter watches game.combat")
    local function ev(t, kind, amount, src, tgt, extra)
      local e = { elapsed = t, kind = kind, amount = amount, source = src.id or 0, source_name = src.name or "", target = tgt.id or 0,
        target_name = tgt.name or "", origin = "weapon", ability = 0, damage_type = 0, critical = false }
      for k, val in pairs(src) do if k ~= "id" and k ~= "name" then e["source_" .. k] = val end end
      for k, val in pairs(tgt) do if k ~= "id" and k ~= "name" then e["target_" .. k] = val end end
      for k, val in pairs(extra or {}) do e[k] = val end
      return e
    end
    local me, bob, pet, mob = { id = 1, name = "Ninnai", is_self = true }, { id = 2, name = "Bob", is_player = true },
      { id = 3, name = "Fido", is_my_pet = true }, { id = 9, name = "Snake" }
    H.combat({ ev(0, "damage", 300, me, mob, { critical = true }), ev(1, "damage", 100, bob, mob), ev(2, "damage", 200, pet, mob),
      ev(3, "damage", 50, mob, me), ev(4, "healing", 80, bob, me), ev(5, "miss", 0, me, mob),
      ev(9, "damage", 350, me, mob, { origin = "special", ability = 777 }),
      ev(9, "damage", 1, me, { id = 11, name = "Gnat" }, { origin = "special", ability = 150 }), ev(9, "damage", 1, me, { id = 11, name = "Gnat" }, { damage_type = 90 }) })
    local rows = f("meter_rows").kids
    local function r(i, name) return H.find(rows[i], name) end
    local function click_row(i) H.find(rows[i], "row_hit").on_click() end
    -- default: Me with pets folded into you (800 = 600 + pet 200)
    check(f("meter_filter").text == "Me" and r(1, "row_name").text == "1. You" and rows[2].visible == false, "default: Me, pets count as you")
    check(r(1, "row_value").text == "852  94.7/s  100%", "you: amount, per second, share: " .. tostring(r(1, "row_value").text))
    check(f("meter_summary").text:find("Snake", 1, true) and f("meter_summary").text:find("0:09", 1, true), "fight named after the enemy, 9 s: " .. f("meter_summary").text)
    check(f("meter_stats").text:find("crit 20%", 1, true) and f("meter_stats").text:find("miss 17%", 1, true) and f("meter_stats").text:find("max 350", 1, true),
      "stat strip: crit, miss, max: " .. f("meter_stats").text)
    local graph_cols = f("meter_columns").kids
    check(graph_cols[1].visible == true and graph_cols[10].visible == true and graph_cols[11].visible == false, "graph: one column per second")
    -- click you: abilities incl. the pet's
    click_row(1)
    check(f("meter_detail").visible == true and r(1, "row_name").text == "Special 777" and r(2, "row_name").text == "Weapon" and r(3, "row_name").text == "Fido: Weapon"
      and r(4, "row_name").text:find("Fling Shot", 1, true) and (r(5, "row_name").text == "Weapon · Projectile" or r(4, "row_name").text == "Weapon · Projectile"),
      "drill-down: your abilities and the pet's")
    f("meter_back").on_click()
    check(f("meter_detail").visible == false, "back to the list")
    -- pets split
    f("meter_pets").on_click()
    check(r(1, "row_name").text == "1. You" and r(2, "row_name").text == "2. Fido (pet)" and r(1, "row_fill").tint == "#4fb3e8" and r(2, "row_fill").tint == "#5fb8a8",
      "pets split: you blue, pet teal")
    -- Team (Bob, a Doctor) / Raid / All
    roster({ data = { members = { { own_team = true, character = { name = "Ninnai" } }, { own_team = true, character = { name = "Bob", profession = 10 } },
      { own_team = false, character = { name = "Carl" } } } } })
    H.combat({ ev(9, "damage", 50, { id = 4, name = "Carl", is_player = true }, mob), ev(9, "damage", 20, { id = 5, name = "Dave", is_player = true }, mob) })
    f("meter_filter").on_click()
    check(f("meter_filter").text == "Team" and r(3, "row_name").text == "3. Bob" and r(3, "row_fill").tint == "#58b08c" and rows[4].visible == false, "Team adds Bob in Doctor colours")
    f("meter_filter").on_click(); f("meter_filter").on_click()
    check(f("meter_filter").text == "All" and r(5, "row_name").text == "5. Dave", "All adds strangers")
    -- Targets: Snake took everything; click for who hit it
    f("meter_targets").on_click()
    check(r(1, "row_name").text == "1. Snake" and r(1, "row_value").text:find("^1,020") ~= nil and r(2, "row_name").text == "2. Gnat" and rows[3].visible == false, "targets: Snake took 1,020")
    click_row(1)
    check(r(1, "row_name").text == "1. You" and r(4, "row_name").text == "4. Carl", "who hit Snake")
    f("meter_back").on_click()
    -- Healing / Taken
    f("meter_healing").on_click()
    check(r(1, "row_name").text == "1. Bob", "healing: Bob")
    f("meter_taken").on_click()
    check(r(1, "row_name").text == "1. You" and r(1, "row_value").text:find("^50") ~= nil, "taken: you took 50")
    -- death: the hits before it are replayed
    H.combat({ ev(10, "damage", 70, mob, me, { origin = "special", ability = 777, critical = true }), ev(11, "death", 0, mob, me, { origin = "death" }) })
    f("meter_deaths").on_click()
    check(r(1, "row_name").text == "You  0:11" and r(1, "row_value").text == "by Snake  70", "deaths: you, by Snake: " .. tostring(r(1, "row_value").text))
    click_row(1)
    check(r(1, "row_name").text == "-8.0s  Snake" and r(2, "row_name").text == "-1.0s  Snake" and r(2, "row_value").text == "Special 777  70!", "death recap replays the hits")
    f("meter_back").on_click()
    -- a pause starts fight 2; < goes back to fight 1; Overall keeps both
    f("meter_damage").on_click()
    H.combat({ ev(40, "damage", 40, bob, { id = 10, name = "Rat" }) })
    check(f("meter_summary").text:find("Rat", 1, true) and f("meter_fight").text:find("2/2", 1, true), "new fight after a pause: " .. f("meter_fight").text)
    f("meter_prev").on_click()
    check(f("meter_summary").text:find("Snake", 1, true) and f("meter_fight").text == "Fight 1/2", "< shows the earlier fight")
    f("meter_overall").on_click()
    check(f("meter_fight").text == "All fights" and f("meter_peak").text:find("one bar per fight", 1, true) ~= nil
      and f("meter_columns").kids[2].visible == true and f("meter_columns").kids[3].visible == false, "overall graph: one bar per fight")
    f("meter_reset").on_click()
    check(rows[1].visible == false and f("meter_summary").text == "No combat yet", "reset clears")
    H.combat({ ev(100, "damage", 50, me, mob), ev(101, "damage", 5000, me, { id = 0, name = "" }) })
    check(f("meter_overall").on_click() == nil and f("meter_summary").text:find("^Snake") ~= nil, "unnamed enemies never name the fight: " .. f("meter_summary").text)
  end
end

-- Nameplates: drawn on the native canvas; stock tags kept, framed bar in consider colours, corner ticks.
do
  local H = Mock.new(addons, core, { width = W, height = Hh })
  local draws, size = {}, nil
  H.env.ui.nameplates = {
    measure = function(text, sz, field) if field == "width" then return #text * sz * 0.5 elseif field == "ascent" then return sz * 0.8 else return sz * 0.2 end end,
    layout = function(w, h) size = { w, h } end,
    project = function() return 1 end, font_limit = function() return 200 end,
    place = function() return true end,
    graphic = function() return 0 end, image = function() draws[#draws + 1] = { "image" } end,
    backdrop = function(x, y, w, h, c) draws[#draws + 1] = { "backdrop", x, y, w, h, c } end,
    rectangle = function(x, y, w, h, c) assert(w >= 0 and h >= 0, "negative rectangle"); draws[#draws + 1] = { "rect", x, y, w, h, c } end,
    text = function(t, x, b, sz, c, o) draws[#draws + 1] = { "text", t, x, b, sz, c, o } end,
  }
  local ok, err = pcall(H.load_package, "ndgui-nameplates")
  check(ok, "ndgui-nameplates loads" .. (ok and "" or (": " .. tostring(err))))
  if ok then
    check(role(H, "prk.nameplates"), "nameplates declare prk.nameplates")
    local plate = { name = "Bob", organization = "Neutral Zone", health = 0.5, has_bar = true, bar_rgb = 0xff0000,
      has_name_color = false, name_rgba = 0, brackets = "selected", has_character = true, npc = false, green_name = false,
      blue_name = false, pvp_flagged = true, roleplay_tag = false, has_consider = true, consider = 0.5 }
    H.env.nameplate_draw(plate, { world = false, backing = true, distance = 10, cos_half_fov = 0.8, near = 0.1, mirror_y = false })
    local texts, rects, backdrops = {}, {}, 0
    for _, d in ipairs(draws) do
      if d[1] == "text" then texts[#texts + 1] = d elseif d[1] == "rect" then rects[#rects + 1] = d elseif d[1] == "backdrop" then backdrops = backdrops + 1 end
    end
    check(texts[1][2] == "** Bob **" and texts[2][2] == "Neutral Zone", "PvP tag and organization drawn")
    check(backdrops == 1, "one backing panel")
    local amber = 0
    for _, r in ipairs(rects) do if r[6] == 0xE0C040FF then amber = amber + 1 end end
    check(amber == 1, "even-level bar is amber")
    local blue = 0
    for _, r in ipairs(rects) do if r[6] == 0x4FB3E8FF then blue = blue + 1 end end
    check(blue == 8, "selected: four blue corner ticks (" .. blue .. " rects)")
    for _, r in ipairs(rects) do
      if r[2] < 0 or r[3] < 0 or r[2] + r[4] > size[1] + 0.01 or r[3] + r[5] > size[2] + 0.01 then
        check(false, "rectangle inside the measured plate"); break
      end
    end
    check(texts[2][4] > 16 + 5, "organization sits under the bar")
  end
end

-- Hotbar.
local B = load_pkg("ndgui-hotbar")
if B then
  check(role(B, "prk.hotbar"), "hotbar declares prk.hotbar")
  check(B.manifest:find('<InteractionScript src="interaction.lua"', 1, true) ~= nil, "hotbar keeps its interaction script")
  local entries = {}
  for i = 1, 10 do entries[i] = { token = i, icon = 0, content = "", tooltip = "", badge = "", faded = false, graphic = "", caption = "", corner = "", countdown = "" } end
  B.env.hotbar_apply({ activate = 1, previous = 2, next = 3, spinner = 4, vertical = false, active = true, row = 3 }, entries)
  check(B.find(B.root, "shortcut_bar_row").text == "3", "hotbar shows its row number")
  local slot_views = 0
  local function count(v) if v.tag == "ItemSlotView" and v.name == "shortcut_slot" then slot_views = slot_views + 1 end for _, k in ipairs(v.kids) do count(k) end end
  count(B.root)
  check(slot_views == 10, "hotbar has 10 native slots inside ndGUI cells (" .. slot_views .. ")")
  check((B.calls.icon or 0) >= 10 and (B.calls.action or 0) >= 10, "slots receive icon and use action")
  check(B.root.w == 398 and B.root.h == 44, "horizontal hotbar is the 398x44 framed plate (" .. tostring(B.root.w) .. "x" .. tostring(B.root.h) .. ")")
  local teal = 0
  local function tiles(v) if v.tag == "ItemSlotView" and v.name == "shortcut_slot" and v.slot_gfx ~= "" then teal = teal + 1 end for _, k in ipairs(v.kids) do tiles(k) end end
  tiles(B.root)
  check(teal == 0, "hotbar slots disable the native teal tile (slot_gfx=\"\")")
  local labels = {}
  local function keyl(v) if v.name == "shortcut_key" then labels[#labels + 1] = v.text end for _, k in ipairs(v.kids) do keyl(k) end end
  keyl(B.root)
  check(#labels == 10 and labels[1] == "1" and labels[10] == "0", "active hotbar labels slots 1-0")
  B.env.hotbar_apply({ activate = 1, previous = 2, next = 3, spinner = 4, vertical = false, active = false, row = 2 }, entries)
  labels = {}
  keyl(B.root)
  check(labels[1] == "", "inactive hotbar hides key labels")
end

-- Control Center: slim bottom strip, stock contract.
local CC = Mock.new(addons, core, { width = W, height = Hh, grant_destinations = true })
local ok_cc, err_cc = pcall(CC.load_package, "ndgui-control-center")
check(ok_cc, "control center loads" .. (ok_cc and "" or (": " .. tostring(err_cc))))
if ok_cc then
  check(role(CC, "prk.control-center"), "control center declares prk.control-center")
  local actions = { select_self = 1, toggle_attack = 2, friendly_previous = 3, friendly_next = 4, hostile_previous = 5, hostile_next = 6 }
  CC.env.control_center_configure(actions, { { key = "sit", reference = 9 } }, { { key = "example.meter/meter", label = "Meter" } })
  CC.env.control_center_apply({ used_ncu = 0, max_ncu = 8, credits = 27691802, aggdef_advanced = false, aggdef = 25, fighting = false, has_pets = false, perks_available = false }, {})
  CC.env.control_center_refresh()
  check(CC.find(CC.root, "ncu").text == "NCU 0/8", "NCU readout")
  check(CC.find(CC.root, "credits").text == "CRED 27,691,802", "credits grouped")
  check(math.abs(CC.find(CC.root, "aggdef").progress - 0.625) < 1e-9, "AGG/DEF slider at +25")
  local strip = CC.find(CC.root, "ndgui_strip")
  check(strip.w == W and strip.h == 30, "strip spans the viewport, 30px tall")
  check((CC.calls["menu.submenu"] or 0) > 0 and (CC.calls["menu.destination"] or 0) > 0, "menus populated")
end

-- Dragged pieces keep their spot: once moved, defaults stop re-placing them.
local M2 = Mock.new(addons, core, { width = W, height = Hh })
M2.load_package("ndgui-compass")
M2.placements[1].moved = true
M2.root.x, M2.root.y = 77, 500
M2.env.compass_place(W)
check(M2.root.x == 77 and M2.root.y == 500, "moved compass is not snapped back")
check(M2.placements[1].field == "NdguiFrame", "providers save poses under NdguiFrame")

-- Every package XML must be strictly well-formed (the client parser rejects stray tokens).
local function strict_xml(path)
  local f = io.open(path, "rb"); if not f then return true end
  local src = f:read("a"); f:close()
  local stack = {}
  for tag in src:gmatch("<([^>]*)>") do
    if not tag:match("^[?!]") then
      local closing, name = tag:match("^(/?)([%w_]+)")
      if not name then return false, "bad tag <" .. tag .. ">" end
      if closing == "/" then
        if stack[#stack] ~= name then return false, "mismatched </" .. name .. ">" end
        stack[#stack] = nil
      else
        local rest = tag:sub(#name + 1)
        local selfclose = rest:match("/%s*$") ~= nil
        rest = rest:gsub("/%s*$", "")
        rest = rest:gsub('%s+[%w_:%-]+="[^"]*"', "")
        if rest:match("%S") then return false, "stray token in <" .. name .. ">: " .. rest end
        if not selfclose then stack[#stack + 1] = name end
      end
    end
  end
  if #stack > 0 then return false, "unclosed <" .. stack[#stack] .. ">" end
  return true
end
local p = io.popen('ls -d "' .. addons .. '"/ndgui*/*.xml')
local xml_ok, xml_count = true, 0
for path in p:lines() do
  xml_count = xml_count + 1
  local ok, why = strict_xml(path)
  if not ok then xml_ok = false; print("  " .. path .. ": " .. why) end
end
p:close()
check(xml_ok and xml_count > 10, "all " .. xml_count .. " package XML files are well-formed")

-- Every library:// image referenced by any package exists on disk.
local missing = {}
local p2 = io.popen('ls -d "' .. addons .. '"/ndgui*/*.xml')
for path in p2:lines() do
  local src = io.open(path, "rb"):read("a")
  for rel in src:gmatch('library://notum%.ndgui%-lib/([^"]+)') do
    if not io.open(addons .. "/ndgui-lib/assets/" .. rel, "rb") then missing[#missing + 1] = rel end
  end
end
p2:close()
check(#missing == 0, "all library images exist" .. (#missing > 0 and (": " .. table.concat(missing, ", ")) or ""))

-- The ndGUI window frame keeps every widget name core.window and ChatFrame look up.
local frame_src = io.open(addons .. "/ndgui-lib/window.xml", "rb"):read("a")
local names_ok = true
for _, n in ipairs({ "window_titlebar", "window_icon", "window_title_tab", "window_title", "window_pin",
  "window_close", "window_content", "window_outer", "window_inner", "window_tabs" }) do
  if not frame_src:find('name="' .. n .. '"', 1, true) then names_ok = false; print("  missing " .. n) end
end
check(names_ok, "window frame template keeps the stock widget names")

-- Library tokens must match the overlay's dovvetech theme.
local theme = dofile(here .. "/theme.lua").get("darktech")
local libsrc = assert(io.open(addons .. "/ndgui-lib/lua/dovvetech.lua")):read("a")
local lib = load(libsrc, "=lib", "t", { math = math })()
local same = true
for k, v in pairs(lib.color) do if theme.color[k] ~= v then same = false; print("  mismatch " .. k) end end
check(same, "library colors match theme.lua darktech")

-- fork_hud.py packages: each loads under the mock host and declares its role.
for _, case in ipairs({
  { "ndgui-ncu", "prk.ncu" }, { "ndgui-target-ncu", "prk.target-ncu" }, { "ndgui-faction", "prk.faction" },
  { "ndgui-chat", "prk.chat" }, { "ndgui-chat-config", "prk.chat-config" }, { "ndgui-raid-bar", "prk.raid-bars" },
  { "ndgui-timer-bars", "prk.timer-bars" }, { "ndgui-team-invite", "prk.team-invite" },
  { "ndgui-sneak-indicator", "prk.sneak-indicator" }, { "ndgui-logout-progress", "prk.logout-progress" },
}) do
  local H = Mock.new(addons, core, { width = W, height = Hh, loose = true })
  local ok, err = pcall(H.load_package, case[1])
  check(ok, case[1] .. " loads (loose host)" .. (ok and "" or (": " .. tostring(err))))
  if ok then check(role(H, case[2]), case[1] .. " declares " .. case[2]) end
end
-- Hideable columns: every table window loads with the ndgui-lib table, and toggling works.
for _, case in ipairs({ "ndgui-nano-programs", "ndgui-inventory", "ndgui-friends", "ndgui-trade",
  "ndgui-actions", "ndgui-market" }) do
  local H = Mock.new(addons, core, { width = W, height = Hh, loose = true })
  local ok, err = pcall(H.load_package, case)
  check(ok, case .. " loads with the ndgui-lib table" .. (ok and "" or (": " .. tostring(err))))
end
do
  local H = Mock.new(addons, core, { width = W, height = Hh, loose = true })
  local ok, err = pcall(H.load_package, "ndgui-ncu")
  if ok then
    local env = H.env
    local prefs = {}
    env.ui.preference = { read = function(k) return prefs[k] or "" end, write = function(k, v) prefs[k] = v end,
      read_array_encoded = function() return "" end, write_array_encoded = function() end }
    local Table
    ok, err = pcall(function() Table = env.ui.require("notum.ndgui-lib/table") end)
    check(ok and Table and Table.create, "notum.ndgui-lib/table resolves" .. (ok and "" or (": " .. tostring(err))))
    if ok then
      local host = env.ui.load("library://notum.ndgui-lib/rollup.xml")
      local cols = { { id = "name", title = "Name", width = 100, value = function(e) return e end, text = function(e) return e end },
        { id = "cost", title = "Cost", width = 50, value = function(e) return e end, text = function(e) return "c" .. e end } }
      local t
      ok, err = pcall(function() t = Table.create({ host = host, columns = cols, binding = function(e) return 1 end, preference = "t" }) end)
      check(ok, "lib table creates" .. (ok and "" or (": " .. tostring(err))))
      if ok then
        t:show({ "a", "b" })
        t:toggle_column(2)
        check(prefs["t.col_hidden"] == ",cost," and t.headers[2].root.visible == false and t.rows[1].cells[2].root.visible == false,
          "hiding a column hides header + cells and saves it (" .. tostring(prefs["t.col_hidden"]) .. ")")
        t:toggle_column(1)
        check(t:column_shown(1), "the last visible column cannot be hidden")
        t:toggle_column(2)
        check(prefs["t.col_hidden"] == "" and t.rows[2].cells[2].root.visible == true, "showing it again restores it")
        local t2 = Table.create({ host = host, columns = cols, binding = function(e) return 1 end, preference = "t" })
        prefs["t.col_hidden"] = ",cost,"
        t2 = Table.create({ host = host, columns = cols, binding = function(e) return 1 end, preference = "t" })
        check(not t2:column_shown(2), "hidden columns are remembered")
        prefs["t.col_hidden"] = ""
        local t3 = Table.create({ host = host, columns = cols, binding = function(e) return 1 end, preference = "t" })
        t3:show({ "a", "b" })
        t3:move_column("cost", -1)
        check(t3.columns[1].id == "cost" and prefs["t.col_order"] == ",cost,name," and #t3.headers == 2,
          "moving a column re-orders and saves it (" .. tostring(prefs["t.col_order"]) .. ")")
        check(t3.rows[1] and t3.rows[1].cells[1].text == "ca" and t3.rows[1].cells[2].text == "a", "rows rebuilt in the new column order")
        check(t3.widths[1] == 50 and t3.widths[2] == 100,
          "widths follow their column when moved (" .. tostring(t3.widths[1]) .. "," .. tostring(t3.widths[2]) .. ")")
        t3:move_column("cost", 1)
        check(t3.widths[1] == 100 and t3.widths[2] == 50, "widths still right after moving back")
        t3:move_column("cost", -1)
        local t4 = Table.create({ host = host, columns = cols, binding = function(e) return 1 end, preference = "t" })
        check(t4.columns[1].id == "cost" and cols[1].id == "name", "column order is remembered (package columns untouched)")
        t4:reset_order()
        check(t4.columns[1].id == "name" and prefs["t.col_order"] == "", "reset restores package order")
      end
    end
  end
end

-- Local Map: hand-made provider runs the native callbacks end to end in the loose host.
do
  local drawn = {}
  local map_surface = { attach = function() end, pan = function() end, zoom = function() end,
    read = function(f) return ({ width = 400, height = 400, screen_width = 2000, screen_height = 1334 })[f] or 0 end,
    markers_begin = function() for i = #drawn, 1, -1 do drawn[i] = nil end end, markers_end = function() end,
    sprite = function(g) drawn[#drawn + 1] = g end, fan = function() drawn[#drawn + 1] = "fan" end }
  local H = Mock.new(addons, core, { width = W, height = Hh, loose = true, map_surface = map_surface })
  local ok, err = pcall(H.load_package, "ndgui-playfield-map")
  check(ok, "ndgui-playfield-map loads (loose host)" .. (ok and "" or (": " .. tostring(err))))
  if ok then
    check(role(H, "prk.playfield-map"), "local map declares prk.playfield-map")
    local env = H.env
    local calls = { pcall(env.playfield_map_configure, true, "Areas", "b", "w") }
    check(calls[1], "playfield_map_configure runs" .. (calls[1] and "" or (": " .. tostring(calls[2]))))
    calls = { pcall(env.playfield_map_visibility, true) }
    check(calls[1], "playfield_map_visibility runs" .. (calls[1] and "" or (": " .. tostring(calls[2]))))
    local facts = { changed = true, accessible = true, land_control = false, has_areas = false, has_character = true, x = 100, y = 120, width = 800, height = 800 }
    calls = { pcall(env.playfield_map_update, facts) }
    check(calls[1], "playfield_map_update runs" .. (calls[1] and "" or (": " .. tostring(calls[2]))))
    -- zoning: the new map arrives before your position, then the position follows
    local zoned = { pcall(env.playfield_map_update, { changed = true, accessible = true, land_control = false, has_areas = false,
      has_character = false, x = 0, y = 0, width = 600, height = 600 }) }
    local placed = zoned[1] and { pcall(env.playfield_map_update, { changed = false, accessible = true, land_control = false, has_areas = false,
      has_character = true, x = 300, y = 200, width = 600, height = 600 }) } or zoned
    check(zoned[1] and placed[1], "zoning: map first, position later runs" .. (placed[1] and "" or (": " .. tostring(placed[2]))))
    calls = { pcall(env.playfield_map_markers, {
      { kind = "player", x = 100, y = 120, facing = 1, radius = 0, half_angle = 0 },
      { kind = "monster", x = 130, y = 140, facing = 0, radius = 0, half_angle = 0 },
      { kind = "wedge", x = 130, y = 140, facing = 0, radius = 20, half_angle = .5 },
      { kind = "shop", x = 90, y = 90, facing = 0, radius = 0, half_angle = 0 } }) }
    check(calls[1], "playfield_map_markers runs" .. (calls[1] and "" or (": " .. tostring(calls[2]))))
    check(drawn[#drawn] == "GFX_GUI_NDGUI_MAP_PLAYER", "player arrow draws last (on top)")
    local has = {}
    for _, g in ipairs(drawn) do has[g] = true end
    check(has.GFX_GUI_NDGUI_MAP_MONSTER and has.GFX_GUI_NDGUI_MAP_SHOP and has.fan, "monster, shop and vision cone draw")
    check(env.MapOverlay.counts.monster == 1 and env.MapOverlay.counts.shop == 1, "legend counts markers")
    env.MapOverlay.shown.monster = false
    env.MapOverlay.compose()
    has = {}
    for _, g in ipairs(drawn) do has[g] = true end
    check(not has.GFX_GUI_NDGUI_MAP_MONSTER and has.GFX_GUI_NDGUI_MAP_SHOP, "monster filter hides monsters only")
    calls = { pcall(env.playfield_map_wheel, 1, 500, 500) }
    check(calls[1], "playfield_map_wheel runs" .. (calls[1] and "" or (": " .. tostring(calls[2]))))
    calls = { pcall(env.playfield_map_context, 500, 500) }
    check(calls[1], "playfield_map_context runs" .. (calls[1] and "" or (": " .. tostring(calls[2]))))
    -- calibration: walk 50 m on X and Z; map content x = 2*X + 10, y = -2*Z + 900
    local before = H.calls["menu.action"] or 0
    local function step(X, Z)
      for _, cb in ipairs(H.subs) do cb({}, { x = X, z = Z, playfield = 655 }, {}, {}) end
      env.playfield_map_update({ changed = false, accessible = true, land_control = false, has_areas = false,
        has_character = true, x = 2 * X + 10, y = -2 * Z + 900, width = 800, height = 800 })
    end
    calls = { pcall(function() step(100, 300); step(150, 250) end) }
    check(calls[1], "calibration walk runs" .. (calls[1] and "" or (": " .. tostring(calls[2]))))
    calls = { pcall(env.playfield_map_context, 500, 500) }
    check(calls[1] and (H.calls["menu.action"] or 0) == before, "context menu offers no (parked) waypoint actions")
    -- client rejects our sprites: the map falls back to stock markers instead of failing
    local real_sprite = map_surface.sprite
    map_surface.sprite = function(g) if g:find("NDGUI", 1, true) then error("A map sprite requires an installed GUI graphic identifier.") end drawn[#drawn + 1] = g end
    for k in pairs(env.MapSpriteRejected) do env.MapSpriteRejected[k] = nil end
    local survived = pcall(env.MapOverlay.compose)
    local stock = false
    for _, g in ipairs(drawn) do if g == "GFX_GUI_MAP_ARROW" then stock = true end end
    check(survived and stock, "rejected sprites fall back to stock markers")
    map_surface.sprite = real_sprite
    -- every sprite the map draws is generated by skin.py
    local skin = io.open(here .. "/tools/skin.py", "rb"):read("a")
    local src = io.open(addons .. "/ndgui-playfield-map/markers.lua", "rb"):read("a")
    local missing_sprite = {}
    for g in src:gmatch('"GFX_GUI_NDGUI_MAP_([A-Z_]+)"') do
      if not skin:find('"' .. g .. '": %(') then missing_sprite[#missing_sprite + 1] = g end
    end
    check(#missing_sprite == 0, "map sprites exist in skin.py" .. (#missing_sprite > 0 and (": " .. table.concat(missing_sprite, ",")) or ""))
  end
end

-- Planet Map: hand-made provider, DarkTech beacons, route, mission distance after walking.
do
  local drawn = {}
  local map_surface = { attach = function() end, pan = function() end, zoom = function() end,
    read = function(f) return ({ width = 400, height = 400, screen_width = 2000, screen_height = 1334 })[f] or 0 end,
    markers_begin = function() for i = #drawn, 1, -1 do drawn[i] = nil end end, markers_end = function() end,
    sprite = function(g) drawn[#drawn + 1] = g end, fan = function() end }
  local H = Mock.new(addons, core, { width = W, height = Hh, loose = true, map_surface = map_surface })
  local ok, err = pcall(H.load_package, "ndgui-planet-map")
  check(ok, "ndgui-planet-map loads (loose host)" .. (ok and "" or (": " .. tostring(err))))
  if ok then
    check(role(H, "prk.planet-map"), "planet map declares prk.planet-map")
    local env = H.env
    local P = { character = 1, character_x = 100, character_y = 100, quest = 1, quest_x = 300, quest_y = 100, held_quest = 1 }
    env.game.planet_map = { point = function(f) return P[f] or 0 end, record = function() end, choose = function() end }
    local texts = {}
    local old_text = env.ui.text
    env.ui.text = function(v, t) if v and v.name then texts[v.name] = t end return old_text(v, t) end
    local calls = { pcall(env.planet_map_choices, { { index = 1, name = "Rubi-Ka", chosen = true }, { index = 2, name = "Shadowlands", chosen = false } }) }
    check(calls[1], "planet_map_choices runs" .. (calls[1] and "" or (": " .. tostring(calls[2]))))
    calls = { pcall(env.planet_map_visibility, true) }
    check(calls[1], "planet_map_visibility runs" .. (calls[1] and "" or (": " .. tostring(calls[2]))))
    calls = { pcall(env.planet_map_update, 1, 3) }
    check(calls[1], "planet_map_update runs" .. (calls[1] and "" or (": " .. tostring(calls[2]))))
    check(drawn[#drawn] == "GFX_GUI_NDGUI_MAP_YOU", "planet 'you' beacon draws on top")
    local has = {}
    for _, g in ipairs(drawn) do has[g] = true end
    check(has.GFX_GUI_NDGUI_MAP_MARKED and has.GFX_GUI_NDGUI_MAP_ROUTE and has.GFX_GUI_NDGUI_MAP_RING, "mission beacon, route and halo draw")
    check((texts.ndplanet_name or ""):find("Rubi-Ka", 1, true) and (texts.ndplanet_name or ""):find("1/3", 1, true), "status shows map name and zoom (" .. tostring(texts.ndplanet_name) .. ")")
    check((texts.ndplanet_mission or ""):find("E", 1, true), "mission bearing east before calibration (" .. tostring(texts.ndplanet_mission) .. ")")
    -- walk 100 m east: 10 content units -> 0.1 units/m; mission is 200 units away -> 2.0 km
    for _, cb in ipairs(H.subs) do cb({}, { x = 0, z = 0, playfield = 1 }, {}, {}) end
    env.planet_map_update(1, 3)
    P.character_x, P.quest_x = 110, 310
    for _, cb in ipairs(H.subs) do cb({}, { x = 100, z = 0, playfield = 1 }, {}, {}) end
    env.planet_map_update(1, 3)
    check((texts.ndplanet_mission or ""):find("2.0 km", 1, true), "mission distance after walking (" .. tostring(texts.ndplanet_mission) .. ")")
    calls = { pcall(env.planet_map_context, 10, 10, 0) }
    check(calls[1], "planet_map_context runs" .. (calls[1] and "" or (": " .. tostring(calls[2]))))
    env.ui.text = old_text
    local skin = io.open(here .. "/tools/skin.py", "rb"):read("a")
    local src = io.open(addons .. "/ndgui-planet-map/main.lua", "rb"):read("a")
    local missing = {}
    for g in src:gmatch('"GFX_GUI_NDGUI_MAP_([A-Z_]+)"') do
      if not skin:find('"' .. g .. '": %(') then missing[#missing + 1] = g end
    end
    check(#missing == 0, "planet sprites exist in skin.py" .. (#missing > 0 and (": " .. table.concat(missing, ",")) or ""))
  end
end

-- Missions: collapsible header, list + detail pane, binding kept on rows and the detail icon.
do
  local H = Mock.new(addons, core, { width = W, height = Hh, loose = true })
  local ok, err = pcall(H.load_package, "ndgui-mission-hub")
  check(ok, "hub loads as Missions" .. (ok and "" or (": " .. tostring(err))))
  if ok then
    check(role(H, "prk.missions"), "hub declares prk.missions")
    local env = H.env
    local a = { token = 11, icon = 5, name = "Kill the Raider", timed = true, minutes = 90, selected = false }
    local b = { token = 12, icon = 6, name = "Find the Data Disk", timed = true, minutes = 120, selected = true }
    ok, err = pcall(env.missions_apply, { a, b })
    check(ok, "missions_apply runs" .. (ok and "" or (": " .. tostring(err))))
    local title = H.find(H.root, "window_title")
    check(title.text == "Missions (2)", "title counts missions: " .. tostring(title.text))
    local fold = H.find(H.root, "window_fold")
    check(fold.visible == true, "fold button shows in the title bar")
    local dt = H.find(H.root, "detail_title")
    check(dt.text == "Find the Data Disk", "detail shows the mission on the map first: " .. tostring(dt.text))
    check(H.find(H.root, "detail_status").text == "On your map", "detail status on map")
    check(H.find(H.root, "detail_time_text").text == "2:00 left", "detail time left")
    -- time drains from where it started
    b.minutes = 60
    env.missions_apply({ a, b })
    local fill = H.find(H.root, "detail_time_fill")
    check(fill.w and fill.w > 0 and fill.w < 120, "time bar drains: " .. tostring(fill.w))
    check(fill.tint == "#4FB3E8", "plenty of time is blue")
    b.minutes = 5
    env.missions_apply({ a, b })
    check(fill.tint == "#E0503C", "last minutes are red")
    -- left-click a row chooses the detail
    local clicked = false
    local function walk(v)
      if clicked then return end
      if v.on_click and v ~= fold then
        v.on_click()
        if dt.text == "Kill the Raider" then clicked = true; return end
      end
      for _, k in ipairs(v.kids or {}) do walk(k) end
    end
    walk(H.root)
    check(clicked, "clicking a row shows that mission")
    check(H.find(H.root, "detail_status").text == "Not on your map", "chosen mission not on map")
    -- fold
    fold.on_click()
    check(H.find(H.root, "missions_body").visible == false and fold.selected == true, "fold folds the window to its title bar")
    check(title.text == "Missions (2) - 1:30", "folded title shows time left: " .. tostring(title.text))
    fold.on_click()
    check(H.find(H.root, "missions_body").visible == true and title.text == "Missions (2)", "fold unfolds the window")
    -- no missions
    env.missions_apply({})
    check(H.find(H.root, "missions_empty").visible == true and title.text == "Missions", "empty state")
  end
end

-- Brief zone guess: last "in <Place>", with the joined spelling when the text has both.
do
  local Hz = Mock.new(addons, core, { width = W, height = Hh, loose = true })
  local ok, Bz = pcall(function() Hz.load_package("ndgui-mission-hub"); return Hz.env.ui.require("notum.ndgui-lib/briefs") end)
  if ok and Bz then
    check(Bz.zone("hurry to the Rome house at RomeBlue in Rome Blue, you will find") == "RomeBlue", "zone prefers the joined spelling")
    check(Bz.zone("the target is in RomeBlue, in a place called the Rome house.") == "RomeBlue", "zone skips 'in a place'")
    check(Bz.zone("Nothing to see here.") == nil, "no zone")
  else
    check(false, "briefs module loads: " .. tostring(Bz))
  end
end

-- Buff Watch: your buffs / debuffs, what you put on the target, the team grid and the alert banner.
do
  local H = Mock.new(addons, core, { width = W, height = Hh, loose = true })
  local registered, effects_subs, char_subs, roster, binds = {}, {}, {}, nil, {}
  local clock = 1000000
  H.env.ui.time = function() return clock end
  H.env.ui.register_view = function(v, id) registered[id] = v end
  H.env.game.effects = { subscribe = function(subject, cb) effects_subs[subject] = cb; return 1 end }
  H.env.game.character = { subscribe = function(subject, stats, cb) char_subs[subject] = cb; return 1 end }
  H.env.game.team = { subscribe = function(cb) roster = cb; return 1 end }
  H.env.game.targeting = { prepare_select = function(ref) return "select:" .. ref end }
  H.env.ui.actions = { bind = function(v, action) binds[#binds + 1] = { v, action } end }
  local ok, err = pcall(H.load_package, "ndgui-watch")
  check(ok, "ndgui-watch loads" .. (ok and "" or (": " .. tostring(err))))
  if ok then
    local function f(name) return H.find(H.root, name) end
    check(registered.buffs ~= nil and registered.team_buffs ~= nil, "Buff Watch and Team Buffs are addon windows")
    check(effects_subs.self and effects_subs.target and effects_subs.team and char_subs.self and char_subs.target and roster,
      "watches self / target / team effects, self and target, the roster")
    local function fx(ref, name, remaining, duration, extra)
      local e = { reference = ref, name = name, icon = ref, remaining = remaining, duration = duration, hostile = false,
        hidden = false, permanent = false, description = "", kind = "Friendly" }
      for k, v in pairs(extra or {}) do e[k] = v end
      return e
    end
    char_subs.self(nil, { id = 42, health = 1000, max_health = 1000, nano = 500, max_nano = 500 })
    effects_subs.self({ reset = true, sampled_at_ms = clock, data = { { subject = "me", known = true, effects = {
      fx(1, "Cyclic Coat of Barbs", 1200, 1200), fx(2, "Minor Wilderness Protection", 40, 2700),
      fx(3, "Hidden Thing", 10, 10, { hidden = true }) } } } })
    local names = {}
    -- visible text views named `name`, skipping hidden subtrees
    local function texts(name)
      local out = {}
      local function walk(v) if v.visible == false then return end
        if v.name == name then out[#out + 1] = v.text end
        for _, k in ipairs(v.kids or {}) do walk(k) end end
      walk(H.root)
      return out
    end
    local function walk() names = texts("buff_name") end
    walk()
    check(names[1] == "Minor Wilderness Protection" and names[2] == "Cyclic Coat of Barbs" and #names == 2,
      "your buffs, soonest to end first, hidden ones left out: " .. table.concat(names, ", "))
    -- a debuff lands: it goes first and raises the banner
    effects_subs.self({ reset = false, sampled_at_ms = clock, data = { { subject = "me", known = true, effects = {
      fx(1, "Cyclic Coat of Barbs", 1200, 1200), fx(2, "Minor Wilderness Protection", 40, 2700),
      fx(9, "Snake Venom", 30, 30, { hostile = true }) } } } })
    walk()
    check(names[1] == "Snake Venom", "debuffs on you come first: " .. tostring(names[1]))
    H.tick()
    check(f("alert").visible == true and f("alert_text").text == "DEBUFF  Snake Venom", "debuff raises the banner: " .. tostring(f("alert_text").text))
    -- timers count down between samples; an expiring long buff alerts after the debuff alert passes
    clock = clock + 30000
    H.tick()
    check(f("alert_text").text == "Minor Wilderness Protection ends in 10s", "expiring buff alert: " .. tostring(f("alert_text").text))
    -- low health beats everything
    char_subs.self(nil, { id = 42, health = 200, max_health = 1000, nano = 500, max_nano = 500 })
    clock = clock + 300
    H.tick()
    check(f("alert_text").text == "LOW HEALTH  20%", "low health alert: " .. tostring(f("alert_text").text))
    -- target: only what you cast
    char_subs.target(nil, { id = 7, name = "Snake" })
    effects_subs.target({ sampled_at_ms = clock, data = { { subject = "snake", known = true, effects = {
      fx(20, "Your DoT", 18, 30, { hostile = true, caster = 42 }), fx(21, "Someone Else's DoT", 18, 30, { hostile = true, caster = 5 }) } } } })
    check(f("target_head").text == "ON SNAKE", "target section names the target")
    local found_mine, found_other = false, false
    for _, t in ipairs(texts("buff_name")) do
      if t == "Your DoT" then found_mine = true elseif t == "Someone Else's DoT" then found_other = true end
    end
    check(found_mine and not found_other, "target shows only effects you cast")
    -- team grid
    roster({ data = { in_team = true, members = {
      { own_team = true, character = { reference = "r1", name = "Ninnai", is_self = true } },
      { own_team = true, character = { reference = "r2", name = "Bob" } } } } })
    effects_subs.team({ sampled_at_ms = clock, data = {
      { subject = "r1", known = true, effects = { fx(1, "Cyclic Coat of Barbs", 900, 1200), fx(5, "Essence of Behemoth", 3000, 3600) } },
      { subject = "r2", known = true, effects = { fx(5, "Essence of Behemoth", 3000, 3600) } } } })
    local member_names = texts("member_name")
    check(member_names[1] == "Ninnai" and member_names[2] == "Bob  -1", "team grid rows, missing count: " .. table.concat(member_names, " | "))
    local targeted = 0
    for _, b in ipairs(binds) do if b[2] == "select:r2" then targeted = targeted + 1 end end
    check(targeted == 1, "clicking a member targets them")
    -- the menu turns the banner off
    check(f("alert").visible == true, "banner on before")
  end
end

-- Mission hub: one package provides Info, Missions and Mission Terminal; Info keeps the briefing
-- of a mission page in ui.storage and the other two windows (other VMs) show it.
do
  local store = {}
  local function hub()
    local H = Mock.new(addons, core, { width = W, height = Hh, loose = true })
    H.env.ui.storage = { read = function(k) return store[k] or "" end, write = function(k, v) store[k] = v end }
    local surfaces = 0
    local info = H.env.game and H.env.game.info
    if type(info) == "table" then info.surface = function() surfaces = surfaces + 1 end end
    local ok, err = pcall(H.load_package, "ndgui-mission-hub")
    check(ok, "ndgui-mission-hub loads" .. (ok and "" or (": " .. tostring(err))))
    check(type(info) ~= "table" or surfaces == 1, "hub declares the Info page surface once, at load: " .. surfaces)
    H.surfaces = function() return surfaces end
    return ok and H or nil
  end
  local page = {
    { text = "Mission Assignment MXIL: The Rome house", tone = "title", indent = 0 },
    { text = "Description:", tone = "heading", indent = 0 },
    { text = "A gang has holed up in RomeBlue, in a place called the Rome house. Clear them out.", tone = "detail", indent = 0, document = true },
    { text = "Realtime left: 3 minutes.", tone = "detail", indent = 0 },
    { text = "Reward:", tone = "heading", indent = 0 },
    { text = "Cash: 1986 credits", tone = "detail", indent = 0 },
    { text = "Experience: (Up to) 365 XP.", tone = "detail", indent = 0 },
    { text = "Item reward:", tone = "heading", indent = 0 },
    { text = "Nano Crystal (Fling Shot)", tone = "detail", indent = 1, item = true, icon = 4242 },
  }
  for _, line in ipairs(page) do line.rgb = -1 end
  local I = hub()
  if I then
    for _, r in ipairs({ "prk.info", "prk.missions", "prk.mission-terminal" }) do
      check(role(I, r), "mission hub declares " .. r)
    end
    check(I.root ~= nil and I.find(I.root, "hub_blank") ~= nil, "hub mounts an empty frame at load")
    local ok, err = pcall(I.env.info_show, 1, page, {}, false)
    check(ok, "hub info_show runs" .. (ok and "" or (": " .. tostring(err))))
    check(I.find(I.root, "info_lines") ~= nil and I.find(I.root, "window_title").text == "Info", "hub fills the frame with Info on info_show")
    check(I.surfaces() <= 1, "Info does not declare its surface twice")
    check(I.find(I.root, "hub_blank") == nil or I.find(I.root, "hub_blank").visible == false, "placeholder removed")
    check((store["brief:Mission Assignment MXIL: The Rome house"] or "") ~= "", "Info keeps the mission briefing")
    check(store.brief_seq == "1", "brief revision bumps: " .. tostring(store.brief_seq))
    I.env.info_show(2, { { text = "Fling Shot", tone = "title", indent = 0, rgb = -1 }, { text = "Quality level: 10", tone = "detail", indent = 0, rgb = -1 } }, {}, false)
    check(store.brief_seq == "1", "non-mission pages are not kept")
    I.env.missions_apply({})
    check(I.root and I.find(I.root, "info_lines") ~= nil, "a VM keeps the first role it was given")
  end
  local M = hub()
  if M then
    local m = { token = 7, icon = 5, name = "The Rome house", timed = true, minutes = 50, selected = true }
    local ok, err = pcall(M.env.missions_apply, { m })
    check(ok, "hub missions_apply runs" .. (ok and "" or (": " .. tostring(err))))
    check(M.find(M.root, "detail_brief").visible == true, "Missions shows the kept briefing (loose title match)")
    check(M.find(M.root, "detail_pay").text == "1,986 credits  ·  365 XP", "brief pay: " .. tostring(M.find(M.root, "detail_pay").text))
    check(M.find(M.root, "detail_where").text == "Where: RomeBlue", "brief zone: " .. tostring(M.find(M.root, "detail_where").text))
    check(M.find(M.root, "detail_reward_name").text == "Nano Crystal (Fling Shot)", "brief item reward")
    check(M.find(M.root, "detail_text").text:match("^A gang has holed up") ~= nil, "brief text")
    M.env.missions_apply({ { token = 8, icon = 5, name = "Unknown Job", timed = false, selected = true } })
    check(M.find(M.root, "detail_brief").visible == false and M.find(M.root, "detail_hint").text:match("Look at mission once") ~= nil,
      "no brief: hint to look once")
  end
  local T = hub()
  if T then
    store.watch = "fling"
    local ok, err = pcall(T.env.mission_terminal_configure, "Request", "Accept", (function() local l = {} for i = 1, 7 do l[i] = { minimum = "Lo", maximum = "Hi", progress = 0.5 } end return l end)())
    check(ok, "hub terminal configure runs" .. (ok and "" or (": " .. tostring(err))))
    local state = { request = 1, accept = 2, cancel = 3, selected = false }
    local reward = { pinned_mode = false, has_pin = false, icon = 0, name = "", ql = 0, cost = 0 }
    ok, err = pcall(T.env.mission_terminal_apply, state, {
      { reference = 1, icon = 3, description = "The Rome house", selected = false },
      { reference = 2, icon = 3, description = "Find the Data Disk", selected = false },
    }, reward)
    check(ok, "hub terminal apply runs" .. (ok and "" or (": " .. tostring(err))))
    local briefs, badges = {}, {}
    local function walk(v)
      if v.name == "offer_brief" and v.visible ~= false then briefs[#briefs + 1] = v.text end
      if v.name == "offer_reward" and v.visible ~= false and (v.text or "") ~= "" then briefs.reward = v.text end
      if v.name == "offer_badge" and v.visible == true then badges[#badges + 1] = v.text end
      for _, k in ipairs(v.kids or {}) do walk(k) end
    end
    walk(T.root)
    check(#briefs == 1 and briefs[1]:match("1,986 credits") and (briefs.reward or ""):match("^Reward: Nano Crystal"), "terminal row shows a looked-at offer's pay and reward: " .. tostring(briefs[1]) .. " / " .. tostring(briefs.reward))
    check(#badges == 1 and badges[1]:match("fling"), "watch words match the kept briefing's reward: " .. table.concat(badges, "|"))
  end
end

-- Mission Terminal: offer rows, watch list matches, roll counter, presets, chosen-reward cost.
do
  local H = Mock.new(addons, core, { width = W, height = Hh, loose = true })
  local store = {}
  H.env.ui.storage = { read = function(k) return store[k] or "" end, write = function(k, v) store[k] = v end }
  local ok, err = pcall(H.load_package, "ndgui-mission-hub")
  check(ok, "hub loads as Mission Terminal" .. (ok and "" or (": " .. tostring(err))))
  if ok then
    check(role(H, "prk.mission-terminal"), "terminal declares prk.mission-terminal")
    local env = H.env
    local labels = {}
    for i = 1, 7 do labels[i] = { minimum = "Lo" .. i, maximum = "Hi" .. i, progress = 0.5 } end
    env.mission_terminal_configure("Request", "Accept", labels)
    local staged = {}
    env.game.mission_terminal = setmetatable({ slider = function(i, v) staged[i] = v; return true end }, { __index = function() return function() return false end end })
    local reward = { pinned_mode = false, has_pin = false, icon = 0, name = "", ql = 0, cost = 0 }
    local state = { request = 1, accept = 2, cancel = 3, selected = false }
    local offers = {
      { reference = 11, icon = 5, description = "Assassinate a target in Rome Blue. Reward: Ofab armor", selected = false },
      { reference = 12, icon = 6, description = "Find an item in Newland City", selected = false },
    }
    -- watch for "rome blue"
    local input = H.find(H.root, "watch")
    check(input ~= nil, "watch input exists")
    local changed
    for _, v in ipairs({ input }) do changed = v.on_text_changed end
    store.watch = "rome blue, ofab"
    ok, err = pcall(function()
      -- the text callback is registered via ui.on_text_changed (loose host: no-op), so re-load reads storage
    end)
    local H2 = Mock.new(addons, core, { width = W, height = Hh, loose = true })
    H2.env.ui.storage = { read = function(k) return store[k] or "" end, write = function(k, v) store[k] = v end }
    ok, err = pcall(H2.load_package, "ndgui-mission-hub")
    check(ok, "terminal reloads with a watch list" .. (ok and "" or (": " .. tostring(err))))
    env = H2.env
    env.mission_terminal_configure("Request", "Accept", labels)
    env.mission_terminal_apply(state, offers, reward)
    local badges = {}
    local function walk(v) if v.name == "offer_badge" then badges[#badges + 1] = v end; for _, k in ipairs(v.kids or {}) do walk(k) end end
    walk(H2.root)
    check(#badges == 6, "six offer rows")
    check(badges[1].visible == true and badges[1].text:find("rome blue", 1, true) and badges[1].text:find("ofab", 1, true),
      "matching offer gets a badge: " .. tostring(badges[1].text))
    check(badges[2].visible == false, "other offer has no badge")
    check(H2.find(H2.root, "status").text:find("Roll 1", 1, true) and H2.find(H2.root, "status").text:find("1 match", 1, true),
      "status counts the roll and the match: " .. tostring(H2.find(H2.root, "status").text))
    check(H2.find(H2.root, "window_title").text:find("MATCH", 1, true) ~= nil, "title shouts MATCH")
    check(H2.find(H2.root, "log").text:find("Rome Blue", 1, true) ~= nil, "match is logged for the session")
    -- same offers again (e.g. selection change) is not a new roll
    offers[1].selected = true
    env.mission_terminal_apply(state, offers, reward)
    check(H2.find(H2.root, "status").text:find("Roll 1", 1, true) ~= nil, "re-apply is not a roll")
    -- new offers in chosen-reward mode cost credits
    local pinned = { pinned_mode = true, has_pin = true, icon = 9, name = "Ofab Shark Mk 1", ql = 200, cost = 12500 }
    env.mission_terminal_apply(state, { { reference = 21, icon = 5, description = "Repair a machine", selected = false } }, pinned)
    check(H2.find(H2.root, "status").text:find("Roll 2", 1, true) and H2.find(H2.root, "status").text:find("12,500 credits spent", 1, true),
      "chosen-reward rolls add up: " .. tostring(H2.find(H2.root, "status").text))
    check(H2.find(H2.root, "reward_cost").text == "Each roll costs 12,500 credits", "cost per roll")
    check(store.recent_rewards == "Ofab Shark Mk 1\t200", "chosen reward remembered")
  end
end

local rollup = io.open(addons .. "/ndgui-lib/rollup.xml", "rb"):read("a")
local rnames = true
for _, n in ipairs({ "rollup_body", "rollup_icon", "rollup_close", "rollup_collapse", "rollup_expand", "rollup_header", "rollup_title" }) do
  if not rollup:find('name="' .. n .. '"', 1, true) then rnames = false; print("  missing " .. n) end
end
check(rnames, "ndGUI rollup frame keeps the core.rollup widget names")

print(fail == 0 and "ALL PASS" or ("FAILURES " .. fail)); os.exit(fail == 0 and 0 or 1)
