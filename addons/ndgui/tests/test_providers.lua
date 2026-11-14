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
  { "experience", { current = 1396, maximum = 4500, fraction = 1396 / 4500 }, "XP  1396 / 4500" },
  { "alien", { current = nil, maximum = 1000, fraction = 0 }, "AXP  -- / 1000" },
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
      check(cap.text == "SK  1396 / 4500", "shadowknowledge relabels XP as SK")
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
  check((C.calls["compass.sprite"] or 0) == 3 and C.calls["compass.finish"] == 1, "compass draws band twice plus waypoint")
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
    check(v(frame1, "hp_text").text == "400 / 1,000   40%", tag .. " exact HP inside the bar: " .. tostring(v(frame1, "hp_text").text))
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
    rects[tag] = { x = T.root.x, w = T.root.w }
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
  check(f.x + f.w <= W / 2 - 68 and h.x >= W / 2 + 68, "panels clear the 137px compass")
  check(f.x >= 0 and h.x + h.w <= W, "panels stay on screen")
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
for _, case in ipairs({ "ndgui-nano-programs", "ndgui-inventory", "ndgui-friends", "ndgui-missions", "ndgui-trade",
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

local rollup = io.open(addons .. "/ndgui-lib/rollup.xml", "rb"):read("a")
local rnames = true
for _, n in ipairs({ "rollup_body", "rollup_icon", "rollup_close", "rollup_collapse", "rollup_expand", "rollup_header", "rollup_title" }) do
  if not rollup:find('name="' .. n .. '"', 1, true) then rnames = false; print("  missing " .. n) end
end
check(rnames, "ndGUI rollup frame keeps the core.rollup widget names")

print(fail == 0 and "ALL PASS" or ("FAILURES " .. fail)); os.exit(fail == 0 and 0 or 1)
