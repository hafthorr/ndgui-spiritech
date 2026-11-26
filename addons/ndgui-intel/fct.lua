-- Floating combat text (prk.floating-combat-text), ndGUI style.
--
-- The client hands each overhead event as text + colour + an anchor token whose screen position
-- comes with every tick. On top of the stock rise-and-fade:
--   merge    numbers of one colour landing near the same spot within MERGE_S add up into one
--            text that grows: "2,340 x5" (Options > Combat > Floating combat text > Merge quick hits)
--   pop      a hit close to your biggest of the session (or a critical) starts large, in gold,
--            and settles (Pop big hits)
--   shadow   every text has a dark copy under it, so it reads on snow and on sky
-- Pure helpers (F.number, F.format, F.merge_target) are tested offline.
ui.define("intel.fct", function()
	local F = {}

	local LIFETIME = 2.6
	local RISE = 70
	local SPREAD = 26
	local MIN_SIZE = 7
	local FULL_DISTANCE = 10
	local MERGE_S = 0.6 -- a later hit within this time of an earlier one...
	local MERGE_PX = 56 -- ...whose anchor is this close merges into it
	local POP_S = 0.18
	local POP_SCALE = 1.7
	local BIG_SHARE = 0.8 -- of the session's biggest number
	local GOLD = "#FFD24A"
	local SHADOW = "#000000"
	F.MERGE_S, F.MERGE_PX = MERGE_S, MERGE_PX

	-- the first number in a text: "Hit 1,234 points" -> 1234; nil without one
	function F.number(text)
		local digits = (text or ""):match("(%d[%d,]*)")
		if not digits then
			return nil
		end
		return tonumber((digits:gsub(",", "")))
	end

	function F.format(value)
		if value >= 1000000 then
			return string.format("%.2fM", value / 1000000)
		elseif value >= 100000 then
			return string.format("%.0fk", value / 1000)
		elseif value >= 10000 then
			return string.format("%.1fk", value / 1000)
		end
		local text = tostring(math.floor(value))
		local left, rest = text:match("^(%d)(%d%d%d)$")
		return left and (left .. "," .. rest) or text
	end

	-- the active event a new one at (x, y) merges into, or nil
	function F.merge_target(active, fresh, x, y, now)
		for index = #active, 1, -1 do
			local event = active[index]
			if event ~= fresh and event.placed and event.value and fresh.value and event.rgb == fresh.rgb
				and now - event.last_hit <= MERGE_S
				and math.abs(event.anchor_x - x) <= MERGE_PX and math.abs(event.anchor_y - y) <= MERGE_PX then
				return event
			end
		end
	end

	local root
	local active = {}
	local best = 0

	local function setting(kind, key, default)
		local ok, value = pcall(function() return ui.settings[kind](key) end)
		if ok and value ~= nil then
			return value
		end
		return default
	end

	local function hex(rgb)
		return string.format("#%06X", rgb or 0xFFFFFF)
	end

	local function make_text(value, color)
		local view = ui.load("fct_text.xml")
		ui.text(view, value)
		ui.text_color(view, color)
		ui.add(root, view)
		return view
	end

	local function retire(index)
		local event = active[index]
		pcall(ui.destroy, event.view)
		pcall(ui.destroy, event.shadow)
		pcall(ui.floaters.release, event.token)
		table.remove(active, index)
	end

	local function label(event)
		if event.hits > 1 then
			return F.format(event.value) .. " x" .. event.hits
		end
		return event.text
	end

	function F.mount(layer)
		root = layer
	end

	function F.spawn(events, now)
		local size = math.floor(setting("number", "text-size", 16) + 0.5)
		local pop = setting("toggle", "big-hits", true)
		for _, event in ipairs(events) do
			local value = F.number(event.text)
			local critical = (event.text or ""):lower():find("crit", 1, true) ~= nil
			local big = pop and value and (critical or (best > 0 and value >= best * BIG_SHARE))
			if value and value > best then
				best = value
			end
			local color = big and GOLD or hex(event.rgb)
			active[#active + 1] = {
				token = event.token, text = event.text or "", rgb = event.rgb, value = value, hits = 1,
				born = now, last_hit = now, size = size, big = big,
				offset = ((event.random or 0.5) * 2 - 1) * SPREAD,
				shadow = make_text(event.text or "", SHADOW), view = make_text(event.text or "", color),
			}
		end
	end

	function F.tick(readings, now)
		local anchors = {}
		for _, reading in ipairs(readings) do
			anchors[reading.token] = reading
		end
		local merge = setting("toggle", "merge-hits", true)
		for index = #active, 1, -1 do
			local event = active[index]
			local anchor = anchors[event.token]
			if not event.placed and anchor and anchor.visible then
				local into = merge and F.merge_target(active, event, anchor.x, anchor.y, now)
				if into then
					into.value = into.value + event.value
					into.hits = into.hits + 1
					into.last_hit = now
					into.born = math.max(into.born, now - LIFETIME * 0.35) -- keep it on screen while hits keep coming
					into.big = into.big or event.big
					local text = label(into)
					ui.text(into.view, text)
					ui.text(into.shadow, text)
					if event.big then
						ui.text_color(into.view, GOLD)
					end
					retire(index)
					goto continue
				end
				event.placed, event.anchor_x, event.anchor_y = true, anchor.x, anchor.y
			end
			do
				local age = math.max(0, (now - event.born) / LIFETIME)
				if age >= 1 then
					retire(index)
				elseif anchor then
					ui.visible(event.view, anchor.visible)
					ui.visible(event.shadow, anchor.visible)
					if anchor.visible then
						event.anchor_x, event.anchor_y = anchor.x, anchor.y
						local nearness = FULL_DISTANCE / math.max(FULL_DISTANCE, anchor.distance or FULL_DISTANCE)
						local scale = nearness
						local since_hit = now - event.last_hit
						if event.big and since_hit < POP_S then
							scale = scale * (POP_SCALE - (POP_SCALE - 1.25) * (since_hit / POP_S))
						elseif event.big then
							scale = scale * 1.25
						end
						local font = math.max(MIN_SIZE, math.min(96, math.floor(event.size * scale + 0.5)))
						ui.font_size(event.view, font)
						ui.font_size(event.shadow, font)
						local k = font / event.size
						local eased = 1 - (1 - age) * (1 - age) -- fast up, then settling
						local x = anchor.x + event.offset * k - ui.desired_width(event.view) / 2
						local y = anchor.y - ui.desired_height(event.view) - RISE * k * eased
						x = math.max(-16384, math.min(16384, math.floor(x)))
						y = math.max(-16384, math.min(16384, math.floor(y)))
						ui.place(event.shadow, x + 1, y + 1)
						ui.place(event.view, x, y)
					end
					local opacity = age <= 0.6 and 1 or math.max(0, (1 - age) / 0.4)
					ui.opacity(event.view, opacity)
					ui.opacity(event.shadow, opacity * 0.8)
				end
			end
			::continue::
		end
	end

	return F
end)
