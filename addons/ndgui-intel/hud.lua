-- Intel HUD: runs in ONE of this package's non-chat VMs (floating combat text or zone notice, both
-- full-screen layers), whichever holds the bus lease "hud" (main.lua). It reads what the chat VM and
-- the zone VM put on the bus and shows:
--   strip    XP / alien XP / credits per hour this session, time to level, session clock,
--            Alts / Log / reset buttons. Drag by the grip.
--   alert    a banner for a tell, your name, a watch word, saved raid locks, command answers
--   Alts     every character you have logged in with this ndGUI: level, XP, credits (total too),
--            last zone, when, raid locks (from the Raid window's Raid Locks button)
--   Log      this session's alerts and loot, newest first
-- Commands (typed so only you see them; see README): ndgui alts | log | hud | reset |
--   watch <word> | unwatch <word> | words | help
-- Positions and open windows are kept in this package's storage (every character).
ui.define("intel.hud", function()
	local Bus = ui.require("notum.ndgui-lib/bus")
	local Button = ui.require("notum.ndgui-lib/button")
	local Ledger = ui.require("intel.ledger")
	local H = {}

	local ALERT_MS, ALERT_FADE_MS = 7000, 1000
	local LOG_KEEP, LOG_ROWS, ALT_ROWS = 60, 20, 16
	local ALTS_W, LOG_W = 712, 560
	local STRIP_W, STRIP_H, ALERT_W, ALERT_H = 574, 26, 420, 30
	local KIND = {
		tell = { "TELL", "#4FB3E8" }, name = { "NAME", "#E0C040" }, word = { "WATCH", "#E08A3C" },
		loot = { "LOOT", "#9CD69C" }, locks = { "LOCKS", "#E08A3C" }, ndgui = { "NDGUI", "#6CB6FF" },
	}
	local nl = string.char(10)

	local layer
	local built, active = false, false
	local strip, alert, alts, logw
	local pos = {}
	local rates
	local me = { cash = nil }
	local zone = { name = "", sub = "" }
	local reader
	local seen, seen_order = {}, {}
	local log = {}
	local unread = 0
	local alert_state = { until_ms = 0 }
	local last_record, last_record_text = 0, ""
	local confirm_forget = {}

	local function now_ms()
		local ok, value = pcall(ui.time)
		return ok and type(value) == "number" and value or 0
	end

	local function screen()
		local ok_w, w = pcall(ui.width, layer)
		local ok_h, h = pcall(ui.height, layer)
		w = ok_w and type(w) == "number" and w > 200 and w or 1920
		h = ok_h and type(h) == "number" and h > 200 and h or 1080
		return w, h
	end

	-- ---- placement ----------------------------------------------------------------------------
	local function clamp(x, y, w, h)
		local sw, sh = screen()
		return math.floor(math.max(0, math.min(x, sw - math.min(w, sw)))), math.floor(math.max(0, math.min(y, sh - math.min(h, sh))))
	end

	local function put(key, view, x, y, w, h)
		x, y = clamp(x, y, w, h)
		pos[key] = { x = x, y = y, w = w, h = h }
		ui.place(view, x, y)
	end

	local function place(key, view, w, h, default)
		local x, y = Bus.get("pos:" .. key):match("^(-?%d+),(-?%d+)$")
		if x then
			x, y = tonumber(x), tonumber(y)
		else
			x, y = default(screen())
		end
		put(key, view, x, y, w, h)
	end

	local function draggable(key, view, handle)
		local drag
		ui.on_pointer(handle, function(phase, x, y)
			if phase == "start" then
				ui.capture_pointer(handle)
				local p = pos[key] or { x = 0, y = 0, w = 100, h = 30 }
				drag = { ox = p.x, oy = p.y, px = x, py = y }
			elseif drag and (phase == "move" or phase == "end") then
				local p = pos[key]
				put(key, view, drag.ox + x - drag.px, drag.oy + y - drag.py, p.w, p.h)
			end
			if drag and (phase == "end" or phase == "cancel") then
				drag = nil
				local p = pos[key]
				Bus.set("pos:" .. key, p.x .. "," .. p.y)
			end
		end)
	end

	-- ---- log + alert ------------------------------------------------------------------------
	-- os is not in the addon sandbox. Indexing it before pcall throws and fails the whole role.
	local function clock_of(ms)
		local secs = math.floor((ms or 0) / 1000)
		local ok, text = pcall(function()
			return os.date("%H:%M", secs)
		end)
		if ok and type(text) == "string" then
			return text
		end
		local tod = secs % 86400
		return string.format("%02d:%02d", math.floor(tod / 3600), math.floor(tod % 3600 / 60))
	end

	local function setting_on(key, default)
		local ok, value = pcall(function()
			return ui.settings.toggle(key)
		end)
		if ok and type(value) == "boolean" then
			return value
		end
		return default
	end

	local function strip_on()
		return active and setting_on("show-strip", true) and Bus.get("hud_hidden") ~= "1"
	end

	-- The Log and Alts windows remember that they were opened. Hiding the strip closes
	-- them too, so a login with the strip hidden does not bring the Log back.
	local function hide_panels()
		if alts and alts.open then
			alts.set_open(false)
		end
		if logw and logw.open then
			logw.set_open(false)
		end
		if alert then
			alert_state.until_ms = 0
			ui.visible(alert.root, false)
		end
	end

	local function apply_strip()
		if not strip_on() then
			hide_panels()
		end
		if strip then
			ui.visible(strip.root, strip_on())
		end
	end

	local render_log, render_strip

	local function show_alert(kind, text)
		if not built or not setting_on("show-alerts", true) then
			return
		end
		local look = KIND[kind] or KIND.ndgui
		ui.text(alert.kind, look[1])
		ui.text_color(alert.kind, look[2])
		ui.fill_color(alert.edge, look[2])
		ui.text(alert.text, text)
		ui.tooltip(alert.hit, text .. nl .. "Click: open the Log")
		alert_state.until_ms = now_ms() + ALERT_MS
		ui.opacity(alert.root, 1)
		ui.visible(alert.root, active)
	end

	local function add_log(kind, text, at)
		table.insert(log, 1, { kind = kind, text = text, at = at or now_ms() })
		while #log > LOG_KEEP do
			table.remove(log)
		end
		if kind ~= "loot" and not (logw and logw.open) then
			unread = unread + 1
		end
		render_log()
		render_strip(now_ms(), true)
	end

	local function first_time(id)
		if not id or id == "" then
			return true
		end
		if seen[id] then
			return false
		end
		seen[id] = true
		seen_order[#seen_order + 1] = id
		if #seen_order > 300 then
			seen[table.remove(seen_order, 1)] = nil
		end
		return true
	end

	-- ---- windows ------------------------------------------------------------------------------
	local function frame(key, title, width)
		local view = ui.load("hud_window.xml")
		local w = { key = key, root = view, width = width, height = 120, open = false,
			title = ui.find(view, "frame_title"), content = ui.find(view, "frame_content"),
			bar = ui.find(view, "frame_titlebar"), close = ui.find(view, "frame_close") }
		ui.text(w.title, title)
		ui.add(layer, view)
		ui.visible(view, false)
		draggable(key, view, w.bar)
		function w.resize(height)
			w.height = height
			ui.size(view, w.width, height)
			ui.size(w.title, w.width - 46, 24) -- a weight-only TextView gets no width here
			local p = pos[key]
			if p then
				put(key, view, p.x, p.y, w.width, height)
			end
		end
		function w.set_open(open)
			w.open = open
			ui.visible(view, open and active)
			Bus.set("open:" .. key, open and "1" or "0")
		end
		ui.on_click(w.close, function()
			w.set_open(false)
		end)
		return w
	end

	local function line(host)
		local view = ui.load("text_line.xml")
		ui.add(host, view)
		return view
	end

	-- Alts -------------------------------------------------------------------------------------
	local function alt_ids()
		local ids = {}
		for id in Bus.get(Ledger.INDEX):gmatch("[^,]+") do
			ids[#ids + 1] = id
		end
		return ids
	end

	local function render_alts()
		if not alts or not alts.open then
			return
		end
		local now = now_ms()
		local list, total = {}, 0
		for _, id in ipairs(alt_ids()) do
			local text = Bus.get("alt:" .. id)
			if text ~= "" then
				local record = Ledger.parse(text)
				record.id = id
				list[#list + 1] = record
				total = total + (record.cr or 0)
			end
		end
		table.sort(list, function(a, b)
			if a.id == me.id then return true end
			if b.id == me.id then return false end
			return (a.s or 0) > (b.s or 0)
		end)
		for index, row in ipairs(alts.rows) do
			local record = list[index]
			ui.visible(row.root, record ~= nil)
			row.id = record and record.id
			if record then
				local here = record.id == me.id
				ui.fill_color(row.back, here and "#C0183048" or (index % 2 == 0 and "#600A1016" or "#900A1016"))
				ui.image(row.prof, (record.p or 0) > 0 and ("gfx://GFX_GUI_ICON_PROFESSION_" .. record.p) or "")
				ui.text(row.name, record.n or "?")
				ui.tooltip(row.name, (record.n or "?") .. "  " .. Ledger.profession(record.p) .. ((record.o or "") ~= "" and (nl .. record.o) or ""))
				ui.text(row.level, record.l and tostring(record.l) or "")
				ui.text(row.xp, record.xp and string.format("%d%%", math.floor(record.xp / 10)) or "")
				ui.text(row.cash, record.cr and Ledger.short(record.cr) or "")
				local zone_text = (record.z or ""):find("%", 1, true) and "" or (record.z or "") -- gas notices saved by early builds
				ui.text(row.zone, zone_text)
				ui.tooltip(row.zone, zone_text)
				ui.text(row.seen, here and "online" or Ledger.ago(now - (record.s or 0)))
				ui.text_color(row.seen, here and "#6CE07A" or "#7F9BB0")
				local entries = Ledger.locks(record.lk)
				if not record.lkt then
					ui.text(row.locks, "not checked")
					ui.text_color(row.locks, "#5A6A78")
					ui.tooltip(row.locks, "On this character: Raid window > Raid Locks")
				else
					ui.text(row.locks, #entries == 0 and "none" or (#entries == 1 and entries[1] or (#entries .. " locks: " .. entries[1])))
					ui.text_color(row.locks, #entries == 0 and "#7F9BB0" or "#E08A3C")
					ui.tooltip(row.locks, (#entries == 0 and "No raid locks." or table.concat(entries, nl))
						.. nl .. "Checked " .. Ledger.ago(now - record.lkt))
				end
				ui.text(row.forget, confirm_forget[record.id] and "?" or "x")
				ui.text_color(row.forget, confirm_forget[record.id] and "#E0503C" or "#5A6A78")
			end
		end
		local shown = math.min(#list, #alts.rows)
		ui.text(alts.total, string.format("%d character%s  -  %s credits in all", #list, #list == 1 and "" or "s", Ledger.short(total)))
		ui.text(alts.hint, "Raid locks: press Raid Locks in the Raid window once on each character.")
		alts.resize(24 + 4 + 20 + shown * 21 + 2 * 18 + 16)
	end

	local function build_alts()
		alts = frame("alts", "Alts", ALTS_W)
		ui.add(alts.content, ui.load("alts_head.xml"))
		alts.rows = {}
		for index = 1, ALT_ROWS do
			local view = ui.load("alts_row.xml")
			ui.add(alts.content, view)
			local row = { root = view }
			for _, name in ipairs({ "back", "prof", "name", "level", "xp", "cash", "zone", "seen", "locks", "forget" }) do
				row[name] = ui.find(view, "alt_" .. name)
			end
			ui.on_click(row.forget, function()
				local id = row.id
				if not id then
					return
				end
				if confirm_forget[id] then
					confirm_forget[id] = nil
					Bus.set("alt:" .. id, "")
					Bus.set(Ledger.INDEX, Ledger.index_remove(Bus.get(Ledger.INDEX), id))
				else
					confirm_forget[id] = true
				end
				render_alts()
			end)
			alts.rows[index] = row
		end
		alts.total = line(alts.content)
		ui.text_color(alts.total, "#C5D7E6")
		alts.hint = line(alts.content)
		place("alts", alts.root, ALTS_W, 300, function(sw, sh) return (sw - ALTS_W) / 2, sh * 0.2 end)
		alts.resize(200)
	end

	-- Log --------------------------------------------------------------------------------------
	function render_log()
		if not logw or not logw.open then
			return
		end
		unread = 0
		local alerts_n, loot_n = 0, 0
		for _, entry in ipairs(log) do
			if entry.kind == "loot" then loot_n = loot_n + 1 else alerts_n = alerts_n + 1 end
		end
		for index, row in ipairs(logw.rows) do
			local entry = log[index]
			ui.visible(row.root, entry ~= nil)
			if entry then
				local look = KIND[entry.kind] or KIND.ndgui
				ui.text(row.time, clock_of(entry.at))
				ui.text(row.kind, look[1])
				ui.text_color(row.kind, look[2])
				ui.text(row.text, entry.text)
				ui.tooltip(row.text, entry.text)
			end
		end
		local words = Bus.get("words")
		ui.text(logw.summary, string.format("%d alerts, %d loot this session.  Watch words: %s", alerts_n, loot_n,
			words ~= "" and words or "none (ndgui watch <word>)"))
		logw.resize(24 + 4 + 18 + math.max(1, math.min(#log, LOG_ROWS)) * 18 + 16)
	end

	local function build_log()
		logw = frame("log", "Intel Log", LOG_W)
		logw.summary = line(logw.content)
		logw.rows = {}
		for index = 1, LOG_ROWS do
			local view = ui.load("log_row.xml")
			ui.add(logw.content, view)
			logw.rows[index] = { root = view, time = ui.find(view, "log_time"), kind = ui.find(view, "log_kind"), text = ui.find(view, "log_text") }
			ui.size(logw.rows[index].text, LOG_W - 110, 18)
			ui.visible(view, false)
		end
		place("log", logw.root, LOG_W, 200, function(sw, sh) return sw - LOG_W - 40, sh * 0.35 end)
		logw.resize(120)
	end

	local function toggle(w)
		w.set_open(not w.open)
		if w == alts then render_alts() else render_log() end
		render_strip(now_ms(), true)
	end

	-- ---- strip ----------------------------------------------------------------------------------
	local next_strip = 0
	function render_strip(now, force)
		if not built or (not force and now < next_strip) then
			return
		end
		next_strip = now + 1000
		local xp_rate, eta = rates.xp_rate(now), rates.eta(now)
		local recent = rates.recent_xp_rate(now)
		local xp_text = "XP " .. (xp_rate and (Ledger.short(xp_rate) .. "/h") or "--/h")
		if eta then
			xp_text = xp_text .. "  lvl " .. (eta >= 3600 and string.format("%.1fh", eta / 3600) or string.format("%dm", math.ceil(eta / 60)))
		end
		ui.text(strip.xp, xp_text)
		ui.tooltip(strip.xp, "XP this session: " .. Ledger.short(rates.xp.gained)
			.. nl .. "Last 10 min: " .. (recent and (Ledger.short(recent) .. "/h") or "--")
			.. nl .. "Next level: " .. (eta and Ledger.clock(eta) or "--"))
		local axp_rate = rates.axp.gained > 0 and rates.axp_rate(now)
		ui.text(strip.axp, axp_rate and ("AXP " .. Ledger.short(axp_rate) .. "/h") or "")
		ui.tooltip(strip.axp, "Alien XP this session: " .. Ledger.short(rates.axp.gained))
		local cash_rate = rates.cash_rate(now)
		ui.text(strip.cash, cash_rate and ("Cr " .. (cash_rate >= 0 and "+" or "") .. Ledger.short(cash_rate) .. "/h") or "Cr --/h")
		ui.tooltip(strip.cash, "Credits in: " .. Ledger.short(rates.cash.income) .. nl .. "Credits out: " .. Ledger.short(rates.cash.spent)
			.. nl .. "On you: " .. (me.cash and Ledger.short(me.cash) or "--"))
		ui.text(strip.time, Ledger.clock((now - rates.started) / 1000))
		ui.tooltip(strip.time, "Session time (the 0 button starts over)")
		ui.text(strip.log, unread > 0 and ("Log " .. unread) or "Log")
	end

	local function build_strip()
		local view = ui.load("hud_strip.xml")
		pcall(Button.skin_tree, view)
		strip = { root = view }
		for _, name in ipairs({ "grip", "xp", "axp", "cash", "time", "alts", "log", "reset", "close" }) do
			strip[name] = ui.find(view, "strip_" .. name)
		end
		ui.add(layer, view)
		draggable("strip", view, strip.grip)
		place("strip", view, STRIP_W, STRIP_H, function() return 8, 8 end)
		ui.on_click(strip.alts, function() toggle(alts) end)
		ui.on_click(strip.log, function() toggle(logw) end)
		ui.on_click(strip.reset, function()
			rates.reset(now_ms())
			show_alert("ndgui", "Session counters start over.")
			render_strip(now_ms(), true)
		end)
		ui.on_click(strip.close, function()
			Bus.set("hud_hidden", "1")
			apply_strip()
		end)
		pcall(function()
			ui.settings.on_change(function()
				if not built then
					return
				end
				apply_strip()
				if not setting_on("show-alerts", true) then
					alert_state.until_ms = 0
					ui.visible(alert.root, false)
				end
			end)
		end)
	end

	local function build_alert()
		local view = ui.load("hud_alert.xml")
		alert = { root = view, back = ui.find(view, "alert_back"), edge = ui.find(view, "alert_edge"),
			kind = ui.find(view, "alert_kind"), text = ui.find(view, "alert_text"), hit = ui.find(view, "alert_hit") }
		ui.add(layer, view)
		ui.visible(view, false)
		ui.size(alert.text, ALERT_W - 70, ALERT_H)
		place("alert", view, ALERT_W, ALERT_H, function(sw) return (sw - ALERT_W) / 2, 212 end)
		ui.on_click(alert.hit, function()
			alert_state.until_ms = 0
			ui.visible(alert.root, false)
			if not logw.open then
				toggle(logw)
			end
		end)
	end

	-- ---- your character's record ------------------------------------------------------------
	local function save_record(now, force)
		if not me.id or not me.name then
			return
		end
		local old = Ledger.parse(Bus.get("alt:" .. me.id))
		if old.z and old.z:find("%", 1, true) then
			old.z = nil -- 0.4 dev builds saved a gas notice as the zone
		end
		local fields = {
			n = me.name, l = me.level or old.l, p = me.profession or old.p, o = me.org or old.o,
			cr = me.cash or old.cr, xp = me.xp_permille or old.xp,
			z = zone.name ~= "" and zone.name or old.z, s = math.floor(now / 60000) * 60000,
			lk = me.locks or old.lk, lkt = me.locks_at or old.lkt,
		}
		local text = Ledger.record(fields)
		if text ~= last_record_text and (force or now - last_record >= 15000) then
			last_record, last_record_text = now, text
			Bus.set("alt:" .. me.id, text)
			Bus.set(Ledger.INDEX, Ledger.index_add(Bus.get(Ledger.INDEX), me.id))
			render_alts()
		end
	end

	local function stat_value(stats, id)
		for key, stat in pairs(stats or {}) do
			if type(stat) == "table" and (stat.id or key) == id then
				return stat.value
			end
		end
	end

	local function bar(bars, key)
		if type(bars) ~= "table" then
			return nil
		end
		if bars[key] then
			return bars[key]
		end
		for _, item in pairs(bars) do
			if type(item) == "table" and item.key == key then
				return item
			end
		end
	end

	local function on_self(_, character, stats, bars)
		if not character then
			return
		end
		local id = Ledger.id(character)
		if id ~= me.id then
			me = { id = id }
			rates = Ledger.rates(now_ms())
		end
		me.name, me.level, me.profession, me.org = character.name, character.level, character.profession, character.organization
		if me.name then
			Bus.set("self_name", me.name) -- for the chat VM (no game.character there)
		end
		me.cash = stat_value(stats, 61) or me.cash
		local xp, axp = bar(bars, "xp"), bar(bars, "alien")
		if xp and xp.maximum and xp.maximum > 0 and xp.current then
			me.xp_permille = math.floor(xp.current / xp.maximum * 1000)
		end
		local now = now_ms()
		rates.sample(now, {
			xp = xp and xp.current, xp_max = xp and xp.maximum, level = character.level,
			axp = axp and axp.current, axp_max = axp and axp.maximum, alevel = stat_value(stats, 169),
			cash = me.cash,
		})
		save_record(now, false)
	end

	-- ---- bus ----------------------------------------------------------------------------------
	local COMMANDS = "ndgui alts | log | hud | reset | watch <word> | unwatch <word> | words"

	local function command(c, a)
		local words = Bus.get("words")
		if c == "alts" then
			toggle(alts)
		elseif c == "log" then
			toggle(logw)
		elseif c == "hud" then
			if not setting_on("show-strip", true) then
				show_alert("ndgui", "Intel strip is off in Options, Interface, Intel.")
			else
				local hidden = Bus.get("hud_hidden") ~= "1"
				Bus.set("hud_hidden", hidden and "1" or "0")
				apply_strip()
				show_alert("ndgui", hidden and "Intel strip hidden (ndgui hud brings it back)." or "Intel strip shown.")
			end
		elseif c == "reset" then
			rates.reset(now_ms())
			show_alert("ndgui", "Session counters start over.")
		elseif c == "watch" and a ~= "" then
			local list = {}
			for word in words:gmatch("[^,]+") do
				if word ~= a then list[#list + 1] = word end
			end
			list[#list + 1] = a
			Bus.set("words", table.concat(list, ","))
			show_alert("ndgui", "Watching chat for: " .. table.concat(list, ", "))
		elseif c == "unwatch" and a ~= "" then
			local list = {}
			for word in words:gmatch("[^,]+") do
				if word ~= a then list[#list + 1] = word end
			end
			Bus.set("words", table.concat(list, ","))
			show_alert("ndgui", #list > 0 and ("Watching chat for: " .. table.concat(list, ", ")) or "No watch words left.")
		elseif c == "words" then
			show_alert("ndgui", words ~= "" and ("Watching chat for: " .. words:gsub(",", ", ")) or "No watch words (ndgui watch <word>).")
		else
			show_alert("ndgui", COMMANDS)
		end
		render_log()
		render_strip(now_ms(), true)
	end

	local function on_event(topic, f)
		if not first_time(f.id) then
			return
		end
		if topic == "alert" then
			local text = (f.who ~= "" and (f.who .. ": ") or "") .. (f.text or "")
			if f.k == "word" then
				text = "[" .. (f.w or "") .. "] " .. text
			elseif f.k == "name" and (f.ch or "") ~= "" then
				text = "[" .. f.ch .. "] " .. text
			end
			add_log(f.k, text)
			show_alert(f.k, text)
		elseif topic == "loot" then
			add_log("loot", f.item or "")
		elseif topic == "locks" then
			me.locks, me.locks_at = f.text, now_ms()
			save_record(now_ms(), true)
			local entries = Ledger.locks(f.text)
			show_alert("locks", (me.name or "This character") .. ": " .. (#entries == 0 and "no raid locks" or (#entries .. " raid lock(s) saved")))
		elseif topic == "zone" then
			if (f.name or "") ~= "" then
				zone.name, zone.sub = f.name, f.sub or ""
				save_record(now_ms(), true)
			end
		elseif topic == "cmd" then
			-- Replay is how a command typed before this VM took the HUD still arrives.
			-- The bus keeps old sessions, so a command with no time, or older than a minute, is ignored.
			local at = tonumber(f.t)
			if at and math.abs(now_ms() - at) <= 60000 then
				command(f.c or "", f.a or "")
			end
		end
	end

	-- ---- lifecycle ----------------------------------------------------------------------------
	function H.build(root)
		if built then
			return
		end
		layer = root
		rates = Ledger.rates(now_ms())
		-- Commands typed while the HUD was being elected. Older alerts and loot stay
		-- on the bus for this install, and replaying them showed the banner on every login.
		reader = Bus.reader({ replay = 8, replay_topic = "cmd" })
		build_strip()
		build_alert()
		build_alts()
		build_log()
		built = true
		Bus.set("diag:hud_error", "")
		game.character.subscribe("self", "61,169", on_self)
	end

	function H.set_active(value)
		if not built then
			return
		end
		active = value
		if not value then
			ui.visible(strip.root, false)
			ui.visible(alts.root, false)
			ui.visible(logw.root, false)
			ui.visible(alert.root, false)
			return
		end
		alts.open = Bus.get("open:alts") == "1"
		logw.open = Bus.get("open:log") == "1"
		apply_strip()
		ui.visible(alts.root, alts.open)
		ui.visible(logw.root, logw.open)
		render_alts()
		render_log()
		render_strip(now_ms(), true)
	end

	function H.tick(now)
		if not built or not active then
			return
		end
		reader.poll(on_event)
		if alert_state.until_ms > 0 then
			local left = alert_state.until_ms - now
			if left <= 0 then
				alert_state.until_ms = 0
				ui.visible(alert.root, false)
			elseif left < ALERT_FADE_MS then
				ui.opacity(alert.root, left / ALERT_FADE_MS)
			end
		end
		render_strip(now, false)
		save_record(now, false)
	end

	H.command = command -- tests
	return H
end)
