-- Numbers behind the Intel HUD, without host calls (tested offline):
--   Ledger.rates(now)        XP / alien XP / credits gained this session, per hour, time to level
--   Ledger.record / parse    one character's line in the alt list (ui.storage, every character)
--   Ledger.profession(id), Ledger.ago(ms), Ledger.short(n)
ui.define("intel.ledger", function()
	local Bus = ui.require("notum.ndgui-lib/bus")
	local L = {}

	L.WINDOW_MS = 10 * 60 * 1000 -- the "recent" rate looks this far back
	L.MIN_MS = 60 * 1000 -- no per-hour figure before a minute of data

	local PROFESSIONS = {
		[1] = "Soldier", [2] = "Martial Artist", [3] = "Engineer", [4] = "Fixer", [5] = "Agent",
		[6] = "Adventurer", [7] = "Trader", [8] = "Bureaucrat", [9] = "Enforcer", [10] = "Doctor",
		[11] = "Nano-Technician", [12] = "Meta-Physicist", [14] = "Keeper", [15] = "Shade",
	}

	function L.profession(id)
		return PROFESSIONS[id or 0] or ""
	end

	function L.short(value)
		value = tonumber(value) or 0
		local sign = value < 0 and "-" or ""
		value = math.abs(value)
		if value >= 1000000000 then
			return sign .. string.format("%.2fB", value / 1000000000)
		elseif value >= 1000000 then
			return sign .. string.format("%.2fM", value / 1000000)
		elseif value >= 10000 then
			return sign .. string.format("%.0fk", value / 1000)
		elseif value >= 1000 then
			return sign .. string.format("%.1fk", value / 1000)
		end
		return sign .. tostring(math.floor(value))
	end

	function L.clock(seconds)
		seconds = math.max(0, math.floor(seconds or 0))
		local h, m = seconds // 3600, (seconds % 3600) // 60
		if h > 0 then
			return string.format("%d:%02d", h, m)
		end
		return string.format("%d:%02d", m, seconds % 60)
	end

	function L.ago(ms)
		local s = math.max(0, math.floor((ms or 0) / 1000))
		if s < 90 then
			return "now"
		elseif s < 3600 then
			return (s // 60) .. "m ago"
		elseif s < 48 * 3600 then
			return (s // 3600) .. "h ago"
		end
		return (s // 86400) .. "d ago"
	end

	-- ---- rates ---------------------------------------------------------------------------
	-- one counter: feed (now, current, maximum, level); level-ups add what was left of the old level
	local function counter()
		local c = { gained = 0, samples = {} }
		function c.feed(now, current, maximum, level)
			if current == nil then
				return
			end
			if c.current ~= nil then
				if level and c.level and level > c.level then
					c.gained = c.gained + math.max(0, (c.maximum or c.current) - c.current) + current
				elseif current > c.current and (level == nil or level == c.level) then
					c.gained = c.gained + (current - c.current)
				end
			end
			c.current, c.maximum, c.level = current, maximum, level or c.level
			local last = c.samples[#c.samples]
			if not last or now - last.t >= 15000 then
				c.samples[#c.samples + 1] = { t = now, g = c.gained }
				while #c.samples > 2 and now - c.samples[2].t > L.WINDOW_MS do
					table.remove(c.samples, 1)
				end
			end
		end
		function c.reset()
			c.gained, c.samples = 0, {}
		end
		return c
	end

	function L.rates(now)
		local r = { started = now, xp = counter(), axp = counter(), cash = { income = 0, spent = 0 } }
		function r.sample(at, facts)
			r.xp.feed(at, facts.xp, facts.xp_max, facts.level)
			r.axp.feed(at, facts.axp, facts.axp_max, facts.alevel)
			if facts.cash ~= nil then
				if r.cash.last ~= nil then
					local delta = facts.cash - r.cash.last
					if delta > 0 then
						r.cash.income = r.cash.income + delta
					elseif delta < 0 then
						r.cash.spent = r.cash.spent - delta
					end
				end
				r.cash.last = facts.cash
			end
		end
		function r.reset(at)
			r.started = at
			r.xp.reset()
			r.axp.reset()
			r.cash.income, r.cash.spent = 0, 0
		end
		local function per_hour(amount, at)
			local ms = at - r.started
			if ms < L.MIN_MS then
				return nil
			end
			return amount * 3600000 / ms
		end
		function r.xp_rate(at) return per_hour(r.xp.gained, at) end
		function r.axp_rate(at) return per_hour(r.axp.gained, at) end
		function r.cash_rate(at) return per_hour(r.cash.income - r.cash.spent, at) end
		-- the last WINDOW_MS only (what you are doing right now)
		function r.recent_xp_rate(at)
			local first = r.xp.samples[1]
			if not first or at - first.t < L.MIN_MS then
				return nil
			end
			return (r.xp.gained - first.g) * 3600000 / (at - first.t)
		end
		-- seconds to the next level at the recent (else session) rate
		function r.eta(at)
			local rate = r.recent_xp_rate(at) or r.xp_rate(at)
			local c = r.xp
			if not rate or rate <= 0 or not c.maximum or not c.current or c.maximum <= c.current then
				return nil
			end
			return (c.maximum - c.current) / rate * 3600
		end
		return r
	end

	-- ---- alt records ------------------------------------------------------------------------
	L.INDEX = "alts"

	function L.id(character)
		local key = character and (character.key or (character.name and "name:" .. character.name))
		return key and Bus.hash(key) or nil
	end

	function L.record(fields)
		return Bus.encode(fields)
	end

	function L.parse(text)
		local r = Bus.decode(text)
		r.l, r.p, r.cr, r.xp, r.s, r.lkt = tonumber(r.l), tonumber(r.p), tonumber(r.cr), tonumber(r.xp), tonumber(r.s), tonumber(r.lkt)
		return r
	end

	function L.index_add(index, id)
		for item in (index or ""):gmatch("[^,]+") do
			if item == id then
				return index
			end
		end
		return (index == nil or index == "") and id or (index .. "," .. id)
	end

	function L.index_remove(index, id)
		local keep = {}
		for item in (index or ""):gmatch("[^,]+") do
			if item ~= id then
				keep[#keep + 1] = item
			end
		end
		return table.concat(keep, ",")
	end

	-- "Raid locks:\nAlbtraum: 2d 3h\n..." -> entries after the header, and how many
	function L.locks(text)
		local entries = {}
		for line in (text or ""):gmatch("[^\n]+") do
			local rest = line:match("^Raid locks:%s*(.-)%s*$")
			if rest and rest ~= "" then
				entries[#entries + 1] = rest
			elseif not rest and line ~= "No raid locks." then
				entries[#entries + 1] = line
			end
		end
		return entries
	end

	return L
end)
