-- ndgui-intel (chat + floating combat text + zone notice in one package) and the ndgui-lib bus.
-- Several mock VMs share one storage table, like the client's VMs share the package's ui.storage.
-- Run: lua tests/test_intel.lua
local here = ((arg[0] or ""):gsub("\\", "/"):match("^(.*)/tests/[^/]+$") or ".")
package.path = here .. "/tests/?.lua;" .. package.path
local Mock = require("mock_host")
local addons = here .. "/.."
local core = here .. "/../../Packages/Core"
local fail = 0
local function check(cond, msg) print((cond and "PASS " or "FAIL ") .. msg); if not cond then fail = fail + 1 end end

local storage = {}
local NOW = 1700000000000

-- one VM of the package, with the host calls ndgui-intel uses on top of the mock
local function vm(settings)
  local H = Mock.new(addons, core, { width = 1920, height = 1080, settings = settings or { ["text-size"] = 16, ["merge-hits"] = true, ["big-hits"] = true } })
  local ui = H.ui
  H.now = NOW
  ui.time = function() return H.now end
  ui.storage.read = function(k) assert(type(k) == "string" and #k >= 1 and #k <= 128, "storage key " .. tostring(k)); return storage[k] end
  ui.storage.write = function(k, v)
    assert(type(k) == "string" and #k <= 128, "storage key")
    assert(type(v) == "string" and #v <= 4096, "storage value too long (" .. #tostring(v) .. ") for " .. k)
    storage[k] = v ~= "" and v or nil
  end
  ui.width = function() return 1920 end
  ui.height = function() return 1080 end
  ui.desired_width = function(v) return #(v.text or "") * 7 end
  ui.desired_height = function() return 16 end
  ui.click_through = function(v, b) assert(v); v.click_through = b end
  -- like the client: colours are #RRGGBB / #AARRGGBB (at most 9 bytes)
  local function colour(c) assert(type(c) == "string" and #c <= 9, "color exceeds its UTF-8 byte limit: " .. tostring(c)) end
  ui.fill_color = function(v, c) assert(v); colour(c); v.fill = c end
  ui.text_color = function(v, c) assert(v); colour(c); v.color = c end
  ui.graphic_tint = function(v, c) assert(v); colour(c); v.tint = c end
  ui.opacity = function(v, o) assert(v and o >= 0 and o <= 1, "opacity"); v.opacity = o end
  H.pointers = {}
  ui.on_pointer = function(v, cb) assert(v and type(cb) == "function"); H.pointers[v] = cb end
  ui.capture_pointer = function(v) assert(v) end
  H.lines = {}
  ui.chat = {
    style = function(line) assert(line) end, font_family = function(line) assert(line) end,
    text = function(line, text) assert(line); line.out = (line.out or "") .. text end,
    part = function(line, part) assert(line); line.out = (line.out or "") .. "<" .. part .. ">" end,
    channel = function(line, caption) line.out = (line.out or "") .. caption end,
    commit = function(line) H.lines[#H.lines + 1] = line.out end,
    borders = function() end, invalidate = function() end,
  }
  H.released = {}
  ui.floaters = { release = function(token) H.released[#H.released + 1] = token end }
  ui.settings.declare(io.open(addons .. "/ndgui-intel/package.xml"):read("a"))
  H.load_package("ndgui-intel")
  return H
end

local function visible(v) return v and v.visible ~= false end
local function find(H, name) return H.find(H.root, name) end
local function msg(fields)
  local m = { kind = "system", sender = "", channel = "", body = "", sent = false, time = "", time_ms = NOW, color = "",
    structured = false, font_size = 13, font_family = "" }
  for k, v in pairs(fields) do m[k] = v end
  m.line = {}
  return m
end

-- ---- pure modules ------------------------------------------------------------------------
do
  local H = vm()
  local ui = H.ui
  local Bus = ui.require("notum.ndgui-lib/bus")
  local r = Bus.reader()
  Bus.publish("alert", { k = "tell", text = "hi" .. string.char(31) .. "there" })
  Bus.publish("loot", { item = "Ring" })
  local got = {}
  r.poll(function(topic, f) got[#got + 1] = topic .. "=" .. (f.text or f.item) end)
  check(#got == 2 and got[1] == "alert=hi there" and got[2] == "loot=Ring", "bus delivers in order, separators cleaned: " .. table.concat(got, ","))
  got = {}
  r.poll(function(topic) got[#got + 1] = topic end)
  check(#got == 0, "bus reader does not repeat events")
  for i = 1, Bus.RING + 10 do Bus.publish("x", { n = i }) end
  local n = 0
  r.poll(function() n = n + 1 end)
  check(n == Bus.RING, "a reader that fell behind gets the last RING events (" .. n .. ")")
  check(Bus.lease("hud", "a", 1000, 3000) and not Bus.lease("hud", "b", 2000, 3000), "lease: second owner refused while fresh")
  check(Bus.lease("hud", "b", 5000, 3000), "lease: taken over when stale")
  Bus.release("hud", "b")
  check(Bus.lease("hud", "c", 5001, 3000), "lease: free after release")
  check(#Bus.hash("x") == 16 and Bus.hash("abc") ~= Bus.hash("abd"), "hash is 16 hex and differs")

  local Sniff = ui.require("intel.sniff")
  local s = Sniff.new()
  local ctx = { self_name = "Bobtheagent", words = { "omni-med" }, now = NOW }
  local function one(m) local out = s.read(msg(m), ctx); return out[1] end
  local e = one({ kind = "tell", structured = true, sender = "Alice", body = "u there?" })
  check(e and e[1] == "alert" and e[2].k == "tell" and e[2].who == "Alice", "tell -> alert")
  check(one({ kind = "tell", structured = true, sent = true, sender = "Alice", body = "yes" }) == nil, "your own tell is no alert")
  e = one({ kind = "channel", structured = true, channel = "OOC", sender = "Carl", body = "anyone seen bobtheagent?" })
  check(e and e[2].k == "name", "your name in a channel -> alert")
  check(one({ kind = "channel", structured = true, sender = "Carl", body = "bobtheagentx" }) == nil, "only the whole word counts")
  e = one({ kind = "vicinity", structured = true, sender = "Dan", body = "WTS Omni-Med suit" })
  check(e and e[2].k == "word" and e[2].w == "omni-med", "watch word (any case, with a dash) -> alert")
  e = one({ body = "You received Ring of Divine Teardrops." })
  check(e and e[1] == "loot" and e[2].item == "Ring of Divine Teardrops", "loot line -> item")
  check(one({ body = "You received 1,500 credits." }) == nil, "credits are not loot")
  check(one({ body = "You received 3200 xp." }) == nil, "xp is not loot")
  e = one({ body = "Raid locks:", time_ms = NOW })
  check(e and e[1] == "locks" and e[2].text == "Raid locks:", "raid locks header")
  ctx.now = NOW + 300
  e = one({ body = "Albtraum: 2 days 3 hours", time_ms = NOW + 300 })
  check(e and e[1] == "locks" and e[2].text == "Raid locks:\nAlbtraum: 2 days 3 hours", "raid lock line joins the list")
  ctx.now = NOW + 9000
  check(one({ body = "Something else", time_ms = NOW + 9000 }) == nil, "lines long after the header are not locks")
  e = one({ kind = "local", body = "Unknown command: /ndgui watch Omni-Med" })
  check(e and e[1] == "cmd" and e[2].c == "watch" and e[2].a == "omni-med", "command inside a local notice")
  e = one({ kind = "tell", structured = true, sent = true, sender = "Bobtheagent", body = "ndgui alts" })
  check(e and e[1] == "cmd" and e[2].c == "alts", "command in a tell to yourself")
  check(one({ kind = "vicinity", structured = true, sender = "Eve", body = "ndgui alts" }) == nil, "someone else's 'ndgui' line is no command")

  local L = ui.require("intel.ledger")
  local r2 = L.rates(0)
  r2.sample(0, { xp = 1000, xp_max = 5000, level = 10, cash = 100 })
  r2.sample(60000, { xp = 4000, xp_max = 5000, level = 10, cash = 600 })
  r2.sample(120000, { xp = 500, xp_max = 6000, level = 11, cash = 400 })
  check(r2.xp.gained == 3000 + 1000 + 500, "XP across a level-up: " .. r2.xp.gained)
  check(math.abs(r2.xp_rate(120000) - 4500 * 30) < 1, "XP per hour")
  check(r2.cash.income == 500 and r2.cash.spent == 200 and r2.cash_rate(120000) == 300 * 30, "credits in / out per hour")
  check(r2.eta(120000) ~= nil and r2.eta(120000) > 0, "time to level")
  check(L.short(1234567) == "1.23M" and L.short(45200) == "45k" and L.short(999) == "999", "short numbers")
  local locks = L.locks("Raid locks:\nAlbtraum: 2d\nIPS: 5h")
  check(#locks == 2 and locks[2] == "IPS: 5h", "locks list")
  check(#L.locks("No raid locks.") == 0 and #L.locks("Raid locks: Pande (3h)") == 1, "no locks / inline lock")
  check(L.index_add(L.index_add("", "a"), "a") == "a" and L.index_remove("a,b", "a") == "b", "alt index add/remove")

  local F = ui.require("intel.fct")
  check(F.number("Critical! 1,234") == 1234 and F.number("Miss") == nil, "fct number")
  check(F.format(2340) == "2,340" and F.format(23400) == "23.4k", "fct format")
end

-- ---- three VMs: chat, floating combat text, zone notice ---------------------------------------
storage = {}
local chat, fct, zone = vm(), vm(), vm()
-- like the client: the chat role gets no character information
chat.env.game.character.subscribe = function() error("Character information is unavailable for this package.") end
-- the client calls chat callbacks right after mount
chat.env.chat_visual(false)
chat.env.chat_state(true, true)
chat.env.chat_output("", "")
check(find(chat, "chat_content").opacity == 1 and find(chat, "chat_content").click_through == false, "chat VM shows its chat content")
check(find(fct, "chat_content").opacity == 0 and find(fct, "chat_content").click_through == true, "other VMs keep it invisible and click-through")

-- the FCT VM gets combat text; nobody hosts the HUD before ELECT_AFTER_MS
fct.env.floating_text_spawn({ { token = 1, text = "1200", rgb = 0xFF0000, random = 0.5 } }, 1.0)
check(visible(find(fct, "strip")), "a VM that knows it is not chat hosts the HUD from its first callback")
fct.now = NOW + 3500
fct.env.floating_text_tick({ { token = 1, visible = true, x = 500, y = 400, distance = 10 } }, 1.1)
check(visible(find(fct, "strip")), "FCT VM hosts the HUD after the election")
check(not visible(find(fct, "chat_content")), "FCT VM hides the chat content")
zone.now = NOW + 3600
zone.env.zone_notice_apply({ arrived = true, lines = { "Omni-1 Trade", "Omni-1" }, countdown = "", opens_to_attack = false,
  countdown_ms = 0, now_ms = NOW + 3600, width = 1920, height = 1080 })
check(find(zone, "strip") == nil, "zone VM sees the lease and stays out")

-- the HUD VM learns about you
for _, cb in ipairs(fct.subs) do
  cb({ reset = true }, { name = "Bobtheagent", key = "rk1:bob", level = 50, profession = 5, organization = "Spirits" },
    { { id = 61, value = 100000 }, { id = 169, value = 3 } },
    { { key = "xp", current = 1000, maximum = 50000 }, { key = "alien", current = 10, maximum = 1000 } })
end

-- merge: a second hit near the first within MERGE_S adds up
fct.env.floating_text_spawn({ { token = 2, text = "800", rgb = 0xFF0000, random = 0.5 } }, 1.2)
fct.env.floating_text_tick({ { token = 1, visible = true, x = 500, y = 400, distance = 10 }, { token = 2, visible = true, x = 510, y = 405, distance = 10 } }, 1.3)
local merged = false
for _, kid in ipairs(fct.root.kids) do if kid.text == "2,000 x2" then merged = true end end
check(merged, "quick hits on one spot merge: 2,000 x2")
check(#fct.released == 1 and fct.released[1] == 2, "the merged-away event's anchor is released")
fct.env.floating_text_tick({ { token = 1, visible = true, x = 500, y = 400, distance = 10 } }, 9.0)
check(#fct.released == 2, "expired text releases its anchor")

-- chat -> bus -> HUD
chat.env.chat_present({
  msg({ kind = "tell", structured = true, sender = "Alice", body = "u there?" }),
  msg({ body = "You received Ancient Novictum Ring.", time_ms = NOW + 1 }),
  msg({ kind = "local", body = "Unknown command: /ndgui alts", time_ms = NOW + 2 }),
  msg({ body = "Raid locks:", time_ms = NOW + 3 }),
  msg({ body = "Pandemonium: 1 day 2 hours", time_ms = NOW + 4 }),
})
check(chat.lines[1]:find("^> ") ~= nil, "the tell line gets a marker in chat: " .. tostring(chat.lines[1]))
chat.env.chat_present({ msg({ kind = "channel", structured = true, channel = "OOC", sender = "Carl", body = "where is Bobtheagent", time_ms = NOW + 5 }) })
check(chat.lines[#chat.lines]:find("^> ") ~= nil, "your name (from the HUD over the bus) marks a line")
check(#chat.lines == 6, "every chat line still shows")
fct.now = NOW + 6000
fct.env.floating_text_tick({}, 10.0)
check(visible(find(fct, "alert")) and find(fct, "alert_text").text:find("Pandemonium") == nil, "an alert banner shows")
local alts_open = false
for _, kid in ipairs(fct.root.kids) do if kid.name == "frame" and visible(kid) then
  if fct.find(kid, "frame_title").text == "Alts" then alts_open = true end end end
check(alts_open, "'ndgui alts' opened the Alts window")
local Bus = fct.ui.require("notum.ndgui-lib/bus")
local index = Bus.get("alts")
check(index ~= "", "your character is in the alt index")
local record = fct.ui.require("intel.ledger").parse(Bus.get("alt:" .. index))
check(record.n == "Bobtheagent" and record.l == 50 and record.cr == 100000, "alt record: name, level, credits")
check(record.z == "Omni-1 Trade", "alt record: zone from the zone notice VM (" .. tostring(record.z) .. ")")
check(record.lk and record.lk:find("Pandemonium", 1, true) ~= nil, "alt record: raid locks from chat")
local row_name
for _, kid in ipairs(fct.root.kids) do
  local n = fct.find(kid, "alt_name")
  if n and n.text ~= "" then row_name = n.text end
end
check(row_name == "Bobtheagent", "Alts window lists you")
check(fct.find(fct.root, "strip_log").text == "Log 1" or fct.find(fct.root, "strip_log").text == "Log 2", "Log button counts unread alerts: " .. tostring(fct.find(fct.root, "strip_log").text))

-- the HUD VM dies (lease not renewed): the zone VM takes over
zone.now = NOW + 20000
zone.env.zone_notice_apply({ arrived = false, lines = {}, countdown = "", opens_to_attack = false, countdown_ms = 0, now_ms = NOW + 20000, width = 1920, height = 1080 })
check(visible(find(zone, "strip")), "another non-chat VM takes the HUD over when the lease goes stale")

-- dragging the strip saves its position
local grip = find(zone, "strip_grip")
local drag = zone.pointers[grip]
drag("start", 100, 100); drag("move", 160, 130); drag("end", 160, 130)
check(Bus.get("pos:strip") == "68,38", "strip position saved after a drag: " .. Bus.get("pos:strip"))

-- watch words from commands reach the chat VM
zone.modules = nil
chat.env.chat_present({ msg({ kind = "local", body = "Unknown command: /ndgui watch ql300", time_ms = NOW + 50 }) })
zone.now = NOW + 21000
zone.env.zone_notice_apply({ arrived = false, lines = {}, countdown = "", opens_to_attack = false, countdown_ms = 0, now_ms = NOW + 21000, width = 1920, height = 1080 })
check(Bus.get("words") == "ql300", "ndgui watch saves the word: " .. Bus.get("words"))
chat.env.chat_present({ msg({ kind = "vicinity", structured = true, sender = "Zed", body = "selling QL300 stuff", time_ms = NOW + 60 }) })
check(chat.lines[#chat.lines]:find("^> ") ~= nil, "a watch word marks the chat line")

-- zone names: the notice line that is a name, not a sentence
do
  local Z = vm().ui.require("intel.zone")
  check(Z.zone_name({ "Suppression field at 75%. Wildlife may attack you.", "Omni-1 Trade" }) == "Omni-1 Trade", "zone name skips the gas sentence")
  check(Z.zone_name({ "Suppression field at 75%. Wildlife may attack you." }) == nil, "no name when there is only a notice")
  check(Z.zone_name({ "Suppression field at 75%. Wildlife may attack you.", "Entering 'Newland City'." }) == "Newland City", "zone name from Entering '...' (as the client sends it)")
end

-- ---- alt items (ndgui-inventory's "which character has it") ----------------------------------
do
  storage = {}
  local H = vm()
  local A = H.ui.require("notum.ndgui-lib/alt_items")
  local function slot(name, ql, count) return { occupied = true, name = name, quality = ql, count = count } end
  A.me("alice", "Alice")
  A.record("Bank", { slot("Ring of Divine Teardrops", 200, 1), slot("Health Kit", 100, 5), slot("Health Kit", 100, 3), { occupied = false } })
  A.record("Corpse of a Leet", { slot("Leet Ring", 1, 1) })
  local big = {}
  for i = 1, 400 do big[i] = slot(string.format("Implant number %03d with a long descriptive name", i), i, 1) end
  A.record("Inventory", big)
  A.me("bob", "Bob")
  A.record("Inventory", { slot("Ring of Essence", 150, 1) })
  local found = A.find("ring", "Inventory")
  check(#found == 1 and found[1].name == "Alice" and found[1].title == "Bank" and found[1].item.ql == 200,
    "search finds the other character's bank, not this window (" .. #found .. ")")
  check(#A.find("leet", "Inventory") == 0, "loot / corpse windows are not saved")
  local kits = A.find("health kit", "x")
  check(#kits == 1 and kits[1].item.count == 8, "same item + QL merge their counts")
  local implants = A.find("implant number", "Inventory")
  check(#implants == 400, "a big container is split over several storage values (" .. #implants .. ")")
  A.me("alice", "Alice")
  A.record("Inventory", { slot("Implant number 001 with a long descriptive name", 1, 1) })
  check(#A.find("implant number", "x") == 1, "re-saving a container drops its old chunks")
  check(#A.find("ri", "x") == 0, "fewer than three letters search nothing")
end

-- ---- Target Debuffs rotation learning (ndgui-watch/watch.lua) ---------------------------------
do
  local defs = {}
  local env = setmetatable({ ui = { define = function(name, fn) defs[name] = fn end } }, { __index = _G })
  assert(loadfile(addons .. "/ndgui-watch/watch.lua", "t", env))()
  local W = defs["ndgui.watch"]()
  local seen, rotation, off = {}, {}, {}
  local dot = { name = "Poison Dart", caster = 7, hostile = true }
  check(#W.learn(seen, { dot }, 7, 100, true, rotation, off) == 0, "one enemy is not a rotation yet")
  check(#W.learn(seen, { dot }, 7, 100, true, rotation, off) == 0, "the same enemy again does not count twice")
  local joined = W.learn(seen, { dot, { name = "Someone's DoT", caster = 9, hostile = true } }, 7, 101, true, rotation, off)
  check(#joined == 1 and rotation["Poison Dart"], "your effect on a second enemy joins the rotation")
  check(#W.learn({}, { { name = "Heal", caster = 7, hostile = false } }, 7, 5, false, {}, {}) == 0
    and #W.learn({}, { { name = "Heal", caster = 7, hostile = false } }, 7, 6, false, {}, {}) == 0, "buffs on friends are not learned")
  local rot2, off2 = {}, { ["Poison Dart"] = true }
  W.learn({}, { dot }, 7, 1, true, rot2, off2); W.learn({}, { dot }, 7, 2, true, rot2, off2)
  check(not rot2["Poison Dart"], "an effect you stopped tracking is not learned again")
  local missing = W.missing({ { effect = { name = "Poison Dart" } } }, { ["Poison Dart"] = true, ["Slow"] = true })
  check(#missing == 1 and missing[1] == "Slow", "missing = rotation minus what is on the target")
end

print(fail == 0 and "ALL PASS" or ("FAILURES " .. fail)); os.exit(fail == 0 and 0 or 1)
