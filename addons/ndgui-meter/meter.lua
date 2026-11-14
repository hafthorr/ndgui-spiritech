-- Damage meter model: pure bookkeeping over game.combat observations (no UI).
--
-- Credits damage and healing to their source and damage taken to its target, for you, your pets and
-- known players (mobs would flood the lists). Every credit also lands in per-ability stats (hits,
-- crits, biggest hit, misses), per-second buckets (graph, best 5 s burst) and, for damage, the enemy
-- that took it (Targets). The last hits each tracked actor took are kept so a death can be replayed.
--
-- Segments: fights (one ends after IDLE seconds without combat; the last HISTORY are kept) and
-- "all" since reset. Durations count only the seconds spent fighting.
ui.define("ndgui.meter", function()
	local Meter = {}
	Meter.__index = Meter
	local IDLE, HISTORY, RECAP = 6, 10, 10
	local MAX_ACTORS, MAX_TARGETS, MAX_ABILITIES, MAX_DEATHS, MAX_SECONDS = 128, 64, 40, 20, 900
	Meter.IDLE, Meter.HISTORY, Meter.RECAP = IDLE, HISTORY, RECAP

	-- ---- names for damage types and special attacks ----
	-- Classic AO stat ids first; the client's own lookup (when this package may use it) adds to them.
	local damage_types = {
		[90] = "Projectile", [91] = "Melee", [92] = "Energy", [93] = "Chemical", [94] = "Radiation",
		[95] = "Cold", [96] = "Poison", [97] = "Fire",
	}
	local specials = {
		[121] = "Bow Special", [142] = "Brawl", [143] = "Riposte", [144] = "Dimach", [146] = "Sneak Attack",
		[147] = "Fast Attack", [148] = "Burst", [150] = "Fling Shot", [151] = "Aimed Shot", [167] = "Full Auto",
	}
	local function stat_id(name)
		if not (ui.combat and ui.combat.stat) then
			return 0
		end
		local ok, id = pcall(ui.combat.stat, name)
		return ok and tonumber(id) or 0
	end
	for stat, label in pairs({
		projectileac = "Projectile", meleeac = "Melee", energyac = "Energy", chemicalac = "Chemical",
		radiationac = "Radiation", coldac = "Cold", poisonac = "Poison", fireac = "Fire", nanoac = "Nano",
		falldamage = "Fall",
	}) do
		local id = stat_id(stat)
		if id ~= 0 then damage_types[id] = label end
	end
	for stat, label in pairs({
		flingshot = "Fling Shot", burst = "Burst", fullauto = "Full Auto", aimedshot = "Aimed Shot",
		fastattack = "Fast Attack", brawl = "Brawl", dimach = "Dimach", sneakattack = "Sneak Attack",
		backstab = "Backstab", riposte = "Riposte",
	}) do
		local id = stat_id(stat)
		if id ~= 0 then specials[id] = label end
	end

	-- What dealt or healed it: weapon (with damage type), a named special, a nano, a shield...
	function Meter.ability(e)
		local origin, id = e.origin, tonumber(e.ability) or 0
		if origin == "special" then
			return specials[id] or (id ~= 0 and ("Special " .. id) or "Special")
		elseif origin == "health_report" then
			return id ~= 0 and ("Nano " .. id) or (e.kind == "healing" and "Heal" or "Nano")
		elseif origin == "shield" then
			return "Damage shield"
		elseif origin == "reflect" then
			return "Reflect"
		elseif origin == "weapon" then
			local kind = damage_types[tonumber(e.damage_type) or 0]
			return kind and ("Weapon · " .. kind) or "Weapon"
		end
		return e.kind == "healing" and "Heal" or "Other"
	end

	-- ---- construction --------------------------------------------------------------------
	local function stats()
		return { hits = 0, crits = 0, max = 0, misses = 0, burst = 0, abilities = {}, count = 0 }
	end

	local function segment(t, timed)
		return {
			start = t, last = t, active = 0, actors = {}, count = 0, targets = {}, tcount = 0, deaths = {},
			total = { damage = 0, healing = 0, taken = 0 }, buckets = timed and {} or nil, seconds = 0,
		}
	end

	function Meter.create()
		local self = setmetatable({}, Meter)
		self:reset()
		return self
	end

	function Meter:reset()
		self.fights, self.all = {}, nil
		self.recent = {} -- actor key -> last hits taken (for death recaps)
		self.incomplete, self.full = false, false
		self.last_t, self.last_wall = nil, nil
	end

	function Meter:fight()
		return self.fights[#self.fights]
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
		return { key = key, name = name, raw = raw, self = is_self == true, pet = pet == true }
	end
	Meter._who = who

	local function actor_in(self, seg, who_)
		local actor = seg.actors[who_.key]
		if not actor then
			if seg.count >= MAX_ACTORS then
				self.full = true
				return nil
			end
			actor = { key = who_.key, name = who_.name, raw = who_.raw, self = who_.self, pet = who_.pet,
				damage = 0, healing = 0, taken = 0, stats = { damage = stats(), healing = stats(), taken = stats() } }
			seg.actors[who_.key] = actor
			seg.count = seg.count + 1
		end
		actor.name = who_.name
		return actor
	end

	local function bump_ability(st, label, amount, crit)
		local ability = st.abilities[label]
		if not ability then
			if st.count >= MAX_ABILITIES then
				label = "Other"
				ability = st.abilities[label]
			end
			if not ability then
				ability = { label = label, amount = 0, hits = 0, crits = 0, max = 0 }
				st.abilities[label] = ability
				st.count = st.count + 1
			end
		end
		ability.amount = ability.amount + amount
		ability.hits = ability.hits + 1
		if crit then ability.crits = ability.crits + 1 end
		if amount > ability.max then ability.max = amount end
	end

	-- one credited amount on one actor in one segment
	local function record(seg, actor, kind, amount, label, crit, t)
		actor[kind] = actor[kind] + amount
		seg.total[kind] = seg.total[kind] + amount
		local st = actor.stats[kind]
		st.hits = st.hits + 1
		if crit then st.crits = st.crits + 1 end
		if amount > st.max then st.max = amount end
		bump_ability(st, label, amount, crit)
		if seg.buckets then
			local second = math.floor(t - seg.start)
			if second >= 0 and second < MAX_SECONDS then
				local bucket = seg.buckets[second]
				if not bucket then
					bucket = {}
					seg.buckets[second] = bucket
				end
				local cell = bucket[actor.key]
				if not cell then
					cell = { damage = 0, healing = 0, taken = 0 }
					bucket[actor.key] = cell
				end
				cell[kind] = cell[kind] + amount
				if second + 1 > seg.seconds then seg.seconds = second + 1 end
				-- best 5 s burst ending now
				local sum = 0
				for s = second - 4, second do
					local b = seg.buckets[s]
					local c = b and b[actor.key]
					if c then sum = sum + c[kind] end
				end
				if sum / 5 > st.burst then st.burst = sum / 5 end
			end
		end
	end

	-- the fight and overall segments for an event at time t (opening a new fight after a pause)
	local function segments_for(self, t)
		local fight = self:fight()
		if not fight or t - fight.last > IDLE or t < fight.last then
			fight = segment(t, true)
			self.fights[#self.fights + 1] = fight
			if #self.fights > HISTORY then
				table.remove(self.fights, 1)
			end
		end
		if not self.all or t < self.all.last then
			self.all = segment(t, false)
		end
		for _, seg in ipairs({ fight, self.all }) do
			local gap = t - seg.last
			if gap > 0 and gap <= IDLE then
				seg.active = seg.active + gap
			end
			if t > seg.last then
				seg.last = t
			end
		end
		self.last_t, self.last_wall = t, ui.time()
		return fight, self.all
	end

	local function remember_hit(self, target, e, label, amount, t)
		local list = self.recent[target.key]
		if not list then
			list = {}
			self.recent[target.key] = list
		end
		list[#list + 1] = { t = t, source = e.source_is_self and "You" or (e.source_name ~= "" and e.source_name or "Unknown"),
			label = label, amount = amount, crit = e.critical == true }
		if #list > RECAP then
			table.remove(list, 1)
		end
	end

	local function credit_target(seg, e, source_key, amount)
		local id = tonumber(e.target) or 0
		local name = e.target_name ~= "" and e.target_name or "Unknown"
		local key = id ~= 0 and ("#" .. id) or ("n:" .. name)
		local target = seg.targets[key]
		if not target then
			if seg.tcount >= MAX_TARGETS then
				return
			end
			target = { key = key, name = name, total = 0, by = {} }
			seg.targets[key] = target
			seg.tcount = seg.tcount + 1
		end
		target.total = target.total + amount
		target.by[source_key] = (target.by[source_key] or 0) + amount
	end

	local function death(self, e, t)
		local died = who(e, "target")
		if not died then
			return
		end
		local hits = {}
		for i, hit in ipairs(self.recent[died.key] or {}) do
			hits[i] = hit
		end
		self.recent[died.key] = nil
		local entry = { key = died.key, name = died.name, raw = died.raw, self = died.self, pet = died.pet, t = t,
			hits = hits, killer = hits[#hits] and hits[#hits].source or (e.source_name ~= "" and e.source_name or nil) }
		local fight, all = segments_for(self, t)
		for _, seg in ipairs({ fight, all }) do
			entry.at = t - seg.start
			seg.deaths[#seg.deaths + 1] = setmetatable({ at = t - seg.start }, { __index = entry })
			if #seg.deaths > MAX_DEATHS then
				table.remove(seg.deaths, 1)
			end
		end
	end

	function Meter:apply(batch, events)
		if batch and batch.reset then
			self:reset()
		end
		if batch and (tonumber(batch.missed) or 0) > 0 then
			self.incomplete = true
		end
		for _, e in ipairs(events or {}) do
			local kind, amount = e.kind, tonumber(e.amount) or 0
			local t = tonumber(e.elapsed) or 0
			if kind == "death" then
				death(self, e, t)
			elseif kind == "miss" then
				local source, target = who(e, "source"), who(e, "target")
				if source or target then
					local fight, all = segments_for(self, t)
					for _, seg in ipairs({ fight, all }) do
						local a = source and actor_in(self, seg, source)
						if a then a.stats.damage.misses = a.stats.damage.misses + 1 end
						a = target and actor_in(self, seg, target)
						if a then a.stats.taken.misses = a.stats.taken.misses + 1 end
					end
				end
			elseif amount > 0 and (kind == "damage" or kind == "healing") then
				local source = who(e, "source")
				local target = kind == "damage" and who(e, "target") or nil
				if source or target then
					local label = Meter.ability(e)
					local crit = e.critical == true
					local fight, all = segments_for(self, t)
					for _, seg in ipairs({ fight, all }) do
						if source then
							local a = actor_in(self, seg, source)
							if a then
								record(seg, a, kind, amount, label, crit, t)
								if kind == "damage" then credit_target(seg, e, source.key, amount) end
							end
						end
						if target then
							local a = actor_in(self, seg, target)
							if a then
								local from = e.source_is_self and "You" or (e.source_name ~= "" and e.source_name or "Unknown")
								record(seg, a, "taken", amount, from .. " · " .. label, crit, t)
							end
						end
					end
					-- overall bursts are the best any fight reached
					for _, side in ipairs({ { source, kind }, { target, "taken" } }) do
						local who_, k = side[1], side[2]
						local fa = who_ and fight.actors[who_.key]
						local aa = who_ and all.actors[who_.key]
						if fa and aa and fa.stats[k].burst > aa.stats[k].burst then
							aa.stats[k].burst = fa.stats[k].burst
						end
					end
					if target then
						remember_hit(self, target, e, label, amount, t)
					end
				end
			end
		end
	end

	-- ---- views ---------------------------------------------------------------------------
	-- Actors of a segment as shown: pets folded into "You" when merge is on.
	local function shown_actors(seg, merge)
		if not merge then
			return seg.actors
		end
		local out, me = {}, nil
		local function into_me(actor)
			if not me then
				me = { key = "self", name = "You", raw = "", self = true, pet = false, damage = 0, healing = 0, taken = 0,
					stats = { damage = stats(), healing = stats(), taken = stats() } }
				out.self = me
			end
			for _, kind in ipairs({ "damage", "healing", "taken" }) do
				me[kind] = me[kind] + actor[kind]
				local from, to = actor.stats[kind], me.stats[kind]
				to.hits, to.crits, to.misses = to.hits + from.hits, to.crits + from.crits, to.misses + from.misses
				to.max, to.burst = math.max(to.max, from.max), math.max(to.burst, from.burst)
				for label, ability in pairs(from.abilities) do
					local name = actor.pet and (actor.raw .. ": " .. label) or label
					local copy = to.abilities[name]
					if not copy then
						copy = { label = name, amount = 0, hits = 0, crits = 0, max = 0 }
						to.abilities[name] = copy
					end
					copy.amount, copy.hits, copy.crits = copy.amount + ability.amount, copy.hits + ability.hits, copy.crits + ability.crits
					copy.max = math.max(copy.max, ability.max)
				end
			end
		end
		for key, actor in pairs(seg.actors) do
			if actor.self or actor.pet then
				into_me(actor)
			else
				out[key] = actor
			end
		end
		return out
	end

	local function sorted(list, field)
		table.sort(list, function(a, b)
			if a[field] ~= b[field] then
				return a[field] > b[field]
			end
			return (a.key or a.label or "") < (b.key or b.label or "")
		end)
		return list
	end

	-- Sources for one kind that pass keep(actor), biggest first, and their total.
	function Meter.leaders(seg, kind, keep, merge)
		local list, total = {}, 0
		if not seg then
			return list, 0
		end
		for _, actor in pairs(shown_actors(seg, merge)) do
			if actor[kind] > 0 and (not keep or keep(actor)) then
				list[#list + 1] = actor
				total = total + actor[kind]
			end
		end
		return sorted(list, kind), total
	end

	-- One actor as shown (merged "You" when merging).
	function Meter.actor(seg, key, merge)
		return seg and shown_actors(seg, merge)[key] or nil
	end

	-- Enemies (anyone damaged) by damage from kept sources, biggest first.
	function Meter.targets(seg, keep, merge)
		local list, total = {}, 0
		if not seg then
			return list, 0
		end
		for _, target in pairs(seg.targets) do
			local amount = 0
			for source_key, value in pairs(target.by) do
				local actor = seg.actors[source_key]
				if actor and (not keep or keep(merge and actor.pet and { self = true } or actor)) then
					amount = amount + value
				end
			end
			if amount > 0 then
				list[#list + 1] = { key = target.key, name = target.name, amount = amount, by = target.by }
				total = total + amount
			end
		end
		return sorted(list, "amount"), total
	end

	-- Who hit one target, biggest first (keys resolved to shown names).
	function Meter.sources_of(seg, target, keep, merge)
		local list, total, mine = {}, 0, nil
		for source_key, value in pairs(target.by) do
			local actor = seg.actors[source_key]
			if actor and (not keep or keep(actor)) then
				if merge and (actor.self or actor.pet) then
					if not mine then
						mine = { key = "self", name = "You", self = true, amount = 0 }
						list[#list + 1] = mine
					end
					mine.amount = mine.amount + value
				else
					list[#list + 1] = { key = source_key, name = actor.name, self = actor.self, pet = actor.pet, raw = actor.raw, amount = value }
				end
				total = total + value
			end
		end
		return sorted(list, "amount"), total
	end

	-- An actor's abilities for one kind, biggest first.
	function Meter.abilities(actor, kind)
		local list = {}
		for _, ability in pairs(actor.stats[kind].abilities) do
			list[#list + 1] = ability
		end
		return sorted(list, "amount")
	end

	-- Deaths of kept actors in a segment, newest first.
	function Meter.deaths(seg, keep)
		local list = {}
		for i = #(seg and seg.deaths or {}), 1, -1 do
			local d = seg.deaths[i]
			if not keep or keep(d) then
				list[#list + 1] = d
			end
		end
		return list
	end

	-- Per-second amounts of one kind from kept actors (fights only), oldest first.
	function Meter.series(seg, kind, keep)
		local out = {}
		if not (seg and seg.buckets) then
			return out
		end
		for second = 0, seg.seconds - 1 do
			local sum = 0
			for key, cell in pairs(seg.buckets[second] or {}) do
				local actor = seg.actors[key]
				if actor and (not keep or keep(actor)) then
					sum = sum + cell[kind]
				end
			end
			out[#out + 1] = sum
		end
		return out
	end

	-- Overall: one value per kept fight (its rate of one kind), oldest first.
	function Meter:per_fight(kind, keep, merge)
		local out = {}
		for _, fight in ipairs(self.fights) do
			local _, total = Meter.leaders(fight, kind, keep, merge)
			out[#out + 1] = total / self:seconds(fight)
		end
		return out
	end

	-- A fight is named after the named enemy that took the most damage.
	function Meter.name(seg)
		local best
		for _, target in pairs(seg and seg.targets or {}) do
			if target.name ~= "Unknown" and (not best or target.total > best.total) then
				best = target
			end
		end
		return best and best.name or "Fight"
	end

	-- Seconds of fighting so far: a live fight keeps counting until the pause that ends it.
	function Meter:seconds(seg)
		if not seg then
			return 1
		end
		local active = seg.active
		if self.last_t and self.last_wall and (seg == self:fight() or seg == self.all) then
			local now = self.last_t + (ui.time() - self.last_wall) / 1000
			local idle = now - seg.last
			if idle > 0 and idle <= IDLE then
				active = active + idle
			end
		end
		return math.max(1, active)
	end

	-- Whether the newest fight is still going (no IDLE pause yet).
	function Meter:live()
		return self.last_wall ~= nil and (ui.time() - self.last_wall) / 1000 <= IDLE
	end

	return Meter
end)
