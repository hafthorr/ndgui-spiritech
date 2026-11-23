-- Buff Watch model: pure functions over game.effects / game.character observations (no UI).
--
--   M.left(effect, sampled_at_ms, now)   seconds left now (native samples, counted down between them)
--   M.clock(seconds)                     "1h05" / "4:07" / "38s"
--   M.on_you(effects, sampled, now)      your buffs and debuffs, debuffs first, then soonest to end
--   M.split_you(effects, sampled, now, options)  rows (what needs attention) and icons (the rest)
--   M.expiring(effect, left, warn)       a buff inside its warning window
--   M.on_target(effects, self_id, ...)   what you put on your target (or every hostile effect if the
--                                        client reports no casters)
--   M.team_grid(members, collections)    columns = buffs seen on the team, cells = time left / missing
--   M.alerts(state, now)                 the alerts worth showing right now, most urgent first
ui.define("ndgui.watch", function()
	local M = {}

	M.EXPIRING = 15 -- seconds: a buff about to end
	M.MIN_ALERT_DURATION = 60 -- shorter buffs (team auras, heals over time, procs) never warn: no amber row, no alert
	M.LOW_HEALTH, M.LOW_NANO = 0.30, 0.20
	M.DEBUFF_ALERT_MS = 4000
	M.MAX_COLUMNS = 10
	M.WARN_CHOICES = { 30, 60, 300 } -- "warn when a buff has less than": seconds
	M.WARN_DEFAULT = 60
	M.WARN_FRACTION = 0.25 -- ...and less than this share of its duration (a 30 s buff warns at 7 s)

	function M.left(effect, sampled_at, now)
		if effect.permanent then
			return math.huge
		end
		local passed = (now and sampled_at) and math.max(0, (now - sampled_at) / 1000) or 0
		return math.max(0, (effect.remaining or 0) - passed)
	end

	function M.clock(seconds)
		if seconds == math.huge then
			return ""
		end
		seconds = math.max(0, math.ceil(seconds))
		if seconds >= 3600 then
			return string.format("%dh%02d", seconds // 3600, (seconds % 3600) // 60)
		elseif seconds >= 60 then
			return string.format("%d:%02d", seconds // 60, seconds % 60)
		end
		return seconds .. "s"
	end

	-- 0..1 left of the whole duration (1 for permanent or unknown durations)
	function M.fraction(effect, left)
		if effect.permanent or not effect.duration or effect.duration <= 0 then
			return 1
		end
		return math.max(0, math.min(1, left / effect.duration))
	end

	local function sorted(list, sampled, now)
		for _, row in ipairs(list) do
			row.left = M.left(row.effect, sampled, now)
		end
		table.sort(list, function(a, b)
			if a.hostile ~= b.hostile then
				return a.hostile
			end
			if a.left ~= b.left then
				return a.left < b.left
			end
			return (a.effect.name or "") < (b.effect.name or "")
		end)
		return list
	end

	function M.on_you(effects, sampled, now)
		local list = {}
		for _, effect in ipairs(effects or {}) do
			if not effect.hidden then
				list[#list + 1] = { effect = effect, hostile = effect.hostile == true }
			end
		end
		return sorted(list, sampled, now)
	end

	function M.expiring(effect, left, warn)
		if effect.permanent or left == math.huge then
			return false
		end
		if effect.duration and effect.duration > 0 and effect.duration < M.MIN_ALERT_DURATION then
			return false -- short auras and procs run out all the time
		end
		local limit = warn or M.WARN_DEFAULT
		if effect.duration and effect.duration > 0 then
			limit = math.min(limit, effect.duration * M.WARN_FRACTION)
		end
		return left <= limit
	end

	-- What needs attention gets a row: debuffs on you, buffs inside their warning window, buffs pinned
	-- with "Always show as a row". Everything else is an icon (soonest to end first, permanent last).
	-- options: { warn = seconds, pinned = { [name] = true }, hidden = { [name] = true }, quiet = { [name] = true }
	--            (quiet: "Don't warn about this buff": stays an icon, no alert),
	--            all_rows = bool (the old full list), max_rows = n (overflow becomes icons) }
	function M.split_you(effects, sampled, now, options)
		options = options or {}
		local pinned, hidden, quiet = options.pinned or {}, options.hidden or {}, options.quiet or {}
		local rows, icons = {}, {}
		for _, entry in ipairs(M.on_you(effects, sampled, now)) do
			local name = entry.effect.name or ""
			entry.expiring = not entry.hostile and not quiet[name] and M.expiring(entry.effect, entry.left, options.warn)
			entry.pinned = pinned[name] == true
			if entry.hostile then
				rows[#rows + 1] = entry
			elseif hidden[name] then
				-- "Hide this buff"
			elseif options.all_rows or entry.pinned or entry.expiring then
				rows[#rows + 1] = entry
			else
				icons[#icons + 1] = entry
			end
		end
		local max_rows = options.max_rows or math.huge
		if #rows > max_rows then
			while #rows > max_rows do
				icons[#icons + 1] = table.remove(rows)
			end
			table.sort(icons, function(a, b)
				if a.left ~= b.left then
					return a.left < b.left
				end
				return (a.effect.name or "") < (b.effect.name or "")
			end)
		end
		return rows, icons
	end

	function M.on_target(effects, self_id, sampled, now)
		local mine, any_caster = {}, false
		for _, effect in ipairs(effects or {}) do
			if effect.caster ~= nil then
				any_caster = true
			end
		end
		for _, effect in ipairs(effects or {}) do
			if not effect.hidden then
				local yours = self_id ~= nil and effect.caster == self_id
				if yours or (not any_caster and effect.hostile) then
					mine[#mine + 1] = { effect = effect, hostile = false }
				end
			end
		end
		return sorted(mine, sampled, now)
	end

	-- members: { { name, reference, profession, is_self } ... } in roster order
	-- collections: subject reference -> CharacterEffects ({ known, stale, effects })
	-- Columns are the friendly buffs anyone on the team has (most common first, then by name); each
	-- row says, per column, the effect a member has (or nil: missing; false: unknown).
	function M.team_grid(members, collections)
		local seen, order = {}, {}
		for _, member in ipairs(members) do
			local collection = collections[member.reference]
			if collection and collection.known then
				local mine = {}
				for _, effect in ipairs(collection.effects or {}) do
					local name = effect.name
					if name and name ~= "" and not effect.hostile and not effect.hidden and not mine[name] then
						mine[name] = true
						local column = seen[name]
						if not column then
							column = { name = name, icon = effect.icon, count = 0 }
							seen[name] = column
							order[#order + 1] = column
						end
						column.count = column.count + 1
					end
				end
			end
		end
		table.sort(order, function(a, b)
			if a.count ~= b.count then
				return a.count > b.count
			end
			return a.name < b.name
		end)
		while #order > M.MAX_COLUMNS do
			table.remove(order)
		end
		local rows = {}
		for _, member in ipairs(members) do
			local collection = collections[member.reference]
			local known = collection and collection.known
			local cells, missing = {}, 0
			for index, column in ipairs(order) do
				local found = false
				if known then
					found = nil
					for _, effect in ipairs(collection.effects or {}) do
						if effect.name == column.name and not effect.hostile then
							found = effect
							break
						end
					end
					if not found then
						missing = missing + 1
					end
				end
				cells[index] = found
			end
			rows[#rows + 1] = { member = member, cells = cells, known = known == true, missing = missing,
				stale = collection and collection.stale or false }
		end
		return { columns = order, rows = rows }
	end

	-- state: { health, max_health, nano, max_nano, effects, sampled, debuffs = { {name, at} }, quiet = { [name] = true } }
	-- Returns { { kind, text, level = "danger" | "warn" | "info", key } ... } most urgent first.
	function M.alerts(state, now)
		local list = {}
		if state.max_health and state.max_health > 0 and state.health and state.health > 0 then
			local f = state.health / state.max_health
			if f < M.LOW_HEALTH then
				list[#list + 1] = { kind = "health", level = "danger", key = "health",
					text = string.format("LOW HEALTH  %d%%", math.floor(f * 100 + 0.5)) }
			end
		end
		for _, hit in ipairs(state.debuffs or {}) do
			if now - hit.at < M.DEBUFF_ALERT_MS then
				list[#list + 1] = { kind = "debuff", level = "danger", key = "debuff:" .. hit.name,
					text = "DEBUFF  " .. hit.name }
			end
		end
		if state.max_nano and state.max_nano > 0 and state.nano then
			local f = state.nano / state.max_nano
			if f < M.LOW_NANO then
				list[#list + 1] = { kind = "nano", level = "warn", key = "nano",
					text = string.format("LOW NANO  %d%%", math.floor(f * 100 + 0.5)) }
			end
		end
		local expiring = {}
		for _, effect in ipairs(state.effects or {}) do
			if not effect.hostile and not effect.hidden and not effect.permanent
				and (effect.duration or 0) >= M.MIN_ALERT_DURATION and not (state.quiet or {})[effect.name or ""] then
				local left = M.left(effect, state.sampled, now)
				if left > 0 and left <= M.EXPIRING then
					expiring[#expiring + 1] = { effect = effect, left = left }
				end
			end
		end
		table.sort(expiring, function(a, b) return a.left < b.left end)
		for _, row in ipairs(expiring) do
			list[#list + 1] = { kind = "expiring", level = "info", key = "expiring:" .. (row.effect.name or ""),
				text = (row.effect.name or "Buff") .. " ends in " .. M.clock(row.left), icon = row.effect.icon }
		end
		return list
	end

	-- Hostile effects that appeared since the last batch (new references), for the debuff alert.
	function M.new_debuffs(previous, effects)
		local fresh, now_refs = {}, {}
		for _, effect in ipairs(effects or {}) do
			if effect.hostile and not effect.hidden then
				now_refs[effect.reference] = true
				if previous and not previous[effect.reference] then
					fresh[#fresh + 1] = effect
				end
			end
		end
		return fresh, now_refs
	end

	return M
end)
