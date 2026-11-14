-- Damage meter model: pure bookkeeping over game.combat observations (no UI).
-- Credits damage and healing to their source, and damage taken to its target, but only for you,
-- your pets and known players (mobs would flood the list). Two segments: the current fight (ends
-- after IDLE seconds without a credited event) and overall since reset; both time only the seconds
-- spent fighting, so a break between pulls does not dilute the rate.
ui.define("ndgui.meter", function()
	local Meter = {}
	Meter.__index = Meter
	local IDLE = 6
	local MAX_ACTORS = 128
	Meter.IDLE = IDLE

	local function segment(t)
		return { start = t, last = t, active = 0, actors = {}, count = 0, total = { damage = 0, healing = 0, taken = 0 } }
	end

	function Meter.create()
		local self = setmetatable({}, Meter)
		self:reset()
		return self
	end

	function Meter:reset()
		self.fight, self.all = nil, nil
		self.incomplete, self.full = false, false
	end

	-- key, display name and flags for one side of an observation, or nil when it is not ours to count
	local function who(e, side)
		local is_self, pet, player = e[side .. "_is_self"], e[side .. "_is_my_pet"], e[side .. "_is_player"]
		if not (is_self or pet or player) then
			return nil
		end
		local raw = e[side .. "_name"] or ""
		local name = is_self and "You" or raw ~= "" and (raw .. (pet and " (pet)" or "")) or "Unknown"
		local id = tonumber(e[side]) or 0
		local key = is_self and "self" or id ~= 0 and ("#" .. id) or ("n:" .. raw)
		return key, name, is_self == true, pet == true, raw
	end

	local function credit(self, seg, key, name, is_self, pet, raw, kind, amount)
		local actor = seg.actors[key]
		if not actor then
			if seg.count >= MAX_ACTORS then
				self.full = true
				return
			end
			actor = { key = key, name = name, raw = raw, self = is_self, pet = pet, damage = 0, healing = 0, taken = 0 }
			seg.actors[key] = actor
			seg.count = seg.count + 1
		end
		actor.name = name
		actor[kind] = actor[kind] + amount
		seg.total[kind] = seg.total[kind] + amount
	end

	function Meter:apply(batch, events)
		if batch and batch.reset then
			self:reset()
		end
		if batch and (tonumber(batch.missed) or 0) > 0 then
			self.incomplete = true
		end
		for _, e in ipairs(events or {}) do
			local amount = tonumber(e.amount) or 0
			if amount > 0 and (e.kind == "damage" or e.kind == "healing") then
				local credits = {}
				local key, name, is_self, pet, raw = who(e, "source")
				if key then
					credits[#credits + 1] = { key, name, is_self, pet, raw, e.kind }
				end
				if e.kind == "damage" then
					key, name, is_self, pet, raw = who(e, "target")
					if key then
						credits[#credits + 1] = { key, name, is_self, pet, raw, "taken" }
					end
				end
				if #credits > 0 then
					local t = tonumber(e.elapsed) or 0
					if not self.fight or t - self.fight.last > IDLE or t < self.fight.last then
						self.fight = segment(t)
					end
					if not self.all or t < self.all.last then
						self.all = segment(t)
					end
					for _, seg in ipairs({ self.fight, self.all }) do
						local gap = t - seg.last
						if gap > 0 and gap <= IDLE then
							seg.active = seg.active + gap
						end
						if t > seg.last then
							seg.last = t
						end
						for _, c in ipairs(credits) do
							credit(self, seg, c[1], c[2], c[3], c[4], c[5], c[6], amount)
						end
					end
				end
			end
		end
	end

	-- The segment for a scope ("fight" / "all"), its sources for one kind (biggest first) that pass
	-- keep(actor) when given, and their total.
	function Meter:leaders(scope, kind, keep)
		local seg = self[scope]
		local list, total = {}, 0
		if not seg then
			return list, nil, 0
		end
		for _, actor in pairs(seg.actors) do
			if actor[kind] > 0 and (not keep or keep(actor)) then
				list[#list + 1] = actor
				total = total + actor[kind]
			end
		end
		table.sort(list, function(a, b)
			if a[kind] ~= b[kind] then
				return a[kind] > b[kind]
			end
			return a.key < b.key
		end)
		return list, seg, total
	end

	-- Seconds the segment spent fighting (never below 1, so one hit is not infinite DPS).
	function Meter.seconds(seg)
		return math.max(1, seg and seg.active or 0)
	end

	return Meter
end)
