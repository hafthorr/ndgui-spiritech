-- ndGUI overhead nameplates (prk.nameplates): clean and quiet.
-- Name with a thin outline; a framed health bar in soft consider colours (green -> amber -> red);
-- organization in muted steel under it; thin corner ticks for selected (blue) / attacking (red)
-- instead of the stock bracket art; one dark panel behind the text when backing is enabled.
-- The client reports one bracket state per plate, so a selected mob that is also attacking only says
-- "attacking": the selected target is worked out here from game.character("target") and gets both
-- (the plate grows by a few pixels: red ticks stay where they always sit, blue ones go outside them).
-- Name tags (GM, PvP ** **, roleplay = =, blue/green names) and the distance scaling / screen-edge
-- anchoring are the stock rules unchanged.
ui.root(ui.load("root.xml"))

local canvas = ui.nameplates
local style = {
	font = 13,
	organization_font = 11,
	outline = 2,
	name_baseline = 12,
	bar_width = 72,
	bar_top = 16,
	bar_height = 5,
	frame = 1, -- dark border around the bar
	organization_gap = 3,
	padding = 6, -- left/right room inside the plate (brackets sit in it)
	tick = 6, -- corner tick arm length
	tick_width = 2,
	backing_radius = 2,
	anchored_height = 32,
	pixels_per_world_unit = 128,
	full_size_distance = 15,
	font_limit_margin = 1,
	name_color = 0xF2F6FAFF,
	staff_color = 0x3CFF3CFF,
	blue_npc_color = 0x6AAEFFFF,
	organization_color = 0x9FB3C4FF,
	track_color = 0x1A2229E6,
	frame_color = 0x000000C8,
	shine_color = 0xFFFFFF30,
	unknown_consider_color = 0x8A949CFF,
	backing_color = 0x0A0F14A6,
	selected_color = 0x4FB3E8FF,
	attacking_color = 0xE0503CFF,
}
-- consider ramp: easy -> even -> deadly
local RAMP = { { 0.0, 0x5F, 0xC2, 0x5F }, { 0.5, 0xE0, 0xC0, 0x40 }, { 1.0, 0xD8, 0x48, 0x3C } }

local layout = {}

-- current selected target: name and health fraction, to recognise its plate
local selected = { name = nil, health = nil }
local HEALTH_SLACK = 0.06 -- plate and target health arrive at slightly different times

local function on_target(_, character)
	if character and character.name and not character.is_self then
		selected.name = character.name
		local maximum = character.max_health
		selected.health = (maximum and maximum > 0 and character.health) and character.health / maximum or nil
	else
		selected.name, selected.health = nil, nil
	end
end
if game and game.character and game.character.subscribe then
	pcall(game.character.subscribe, "target", "", on_target)
end

local function is_selected(plate)
	if plate.brackets == "selected" then
		return true
	end
	if not selected.name or plate.name ~= selected.name then
		return false
	end
	-- same-named mobs: the one whose health matches (when both are known)
	if selected.health and plate.has_bar then
		return math.abs(plate.health - selected.health) <= HEALTH_SLACK
	end
	return true
end

local function caption(plate)
	local name = plate.name
	local color = plate.has_name_color and plate.name_rgba or style.name_color
	if not plate.has_character then
		return name, color
	end
	if not plate.npc then
		if plate.green_name then
			color = style.staff_color
			if name ~= "" then name = "GM " .. name end
		end
		if name ~= "" then
			if plate.pvp_flagged then
				name = "** " .. name .. " **"
			elseif plate.roleplay_tag then
				name = "= " .. name .. " ="
			end
		end
	elseif plate.blue_name then
		color = style.blue_npc_color
	end
	return name, color
end

local function measure(plate)
	local margin = (plate.brackets == "attacking" and is_selected(plate)) and style.tick_width + 1 or 0
	local name, color = caption(plate)
	local widest = canvas.measure(name, style.font, "width")
	local bottom = style.name_baseline - canvas.measure(name, style.font, "descent") + style.outline / 2
	if plate.has_bar then
		widest = math.max(widest, style.bar_width)
		bottom = math.max(bottom, style.bar_top + style.bar_height + style.frame)
	end
	local organization_baseline = 0
	if plate.organization ~= "" then
		widest = math.max(widest, canvas.measure(plate.organization, style.organization_font, "width"))
		local above = plate.has_bar and (style.bar_top + style.bar_height + style.frame) or bottom
		organization_baseline = math.ceil(above + style.organization_gap
			+ canvas.measure(plate.organization, style.organization_font, "ascent"))
		bottom = organization_baseline - canvas.measure(plate.organization, style.organization_font, "descent")
			+ style.outline / 2
	end
	local width = math.ceil(widest + style.padding * 2) + margin * 2
	local height = math.ceil(bottom + 1) + margin * 2
	canvas.layout(width, height)
	layout.name, layout.color = name, color
	layout.width, layout.height = width, height
	layout.margin = margin -- everything inside is drawn this far in
	layout.center = width / 2
	layout.organization_baseline = organization_baseline + margin
	return layout
end

-- Stock placement: grow with distance up to the font limit, keep the plate on screen at the top edge.
local function top_overflow(offset, half_height, depth, up_y)
	if up_y == 0 then
		return 0
	end
	local top = canvas.project(offset, "y") + up_y * half_height
	local edge = up_y > 0 and 1 or -1
	return math.max(0, (top / depth - edge) / (up_y / depth))
end

local function place(layout, frame)
	local world_scale = 1 / style.pixels_per_world_unit
	local offset = 0
	if frame.world then
		world_scale = math.max(1, frame.distance / style.full_size_distance) / style.pixels_per_world_unit
		local top_direction = frame.mirror_y and -1 or 1
		offset = top_direction * (style.anchored_height - layout.height) / 2 * world_scale
		local depth = canvas.project(offset, "w")
		if depth <= frame.near then
			return false
		end
		local pixels_per_unit = canvas.project(offset, "pixels_per_unit")
		local maximum_scale = (canvas.font_limit() - style.font_limit_margin) / (style.font * pixels_per_unit)
		world_scale = math.min(world_scale, maximum_scale)
		offset = top_direction * (style.anchored_height - layout.height) / 2 * world_scale
		local up_y = canvas.project(offset, "up_y")
		local half_height = layout.height / 2 * world_scale
		local overflow = top_overflow(offset, half_height, depth, up_y)
		if overflow > 0 then
			local top_edge_depth = canvas.project(offset, "distance") * frame.cos_half_fov
			if depth < top_edge_depth then
				local shrink = depth / top_edge_depth
				world_scale = world_scale * shrink
				half_height = half_height * shrink
				overflow = top_overflow(offset, half_height, depth, up_y)
			end
			offset = offset - overflow
		end
	end
	return canvas.place(offset, world_scale)
end

local function rgba(r, g, b, a)
	return math.floor(r) * 0x1000000 + math.floor(g) * 0x10000 + math.floor(b) * 0x100 + (a or 255)
end

local function health_color(plate)
	if not plate.has_consider then
		return plate.bar_rgb * 256 + 255
	end
	local consider = math.min(plate.consider, 1)
	if consider < 0 then
		return style.unknown_consider_color
	end
	for i = 1, #RAMP - 1 do
		local a, b = RAMP[i], RAMP[i + 1]
		if consider <= b[1] then
			local t = (consider - a[1]) / (b[1] - a[1])
			return rgba(a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, a[4] + (b[4] - a[4]) * t)
		end
	end
	local last = RAMP[#RAMP]
	return rgba(last[2], last[3], last[4])
end

-- Four L-shaped corner ticks around the plate (inset pixels in from its edge).
local function ticks(width, height, color, inset)
	local t, w, i = style.tick, style.tick_width, inset or 0
	for _, corner in ipairs({ { i, i, 1, 1 }, { width - i, i, -1, 1 }, { i, height - i, 1, -1 }, { width - i, height - i, -1, -1 } }) do
		local x, y, sx, sy = corner[1], corner[2], corner[3], corner[4]
		local hx = sx > 0 and x or x - t
		local vy = sy > 0 and y or y - t
		canvas.rectangle(hx, sy > 0 and y or y - w, t, w, color)
		canvas.rectangle(sx > 0 and x or x - w, vy, w, t, color)
	end
end

function nameplate_measure(plate)
	measure(plate)
end

function nameplate_draw(plate, frame)
	local l = measure(plate)
	if not place(l, frame) then
		return
	end
	if frame.backing then
		canvas.backdrop(l.margin, l.margin, l.width - l.margin * 2, l.height - l.margin * 2, style.backing_color,
			style.backing_radius)
	end
	local m = l.margin
	if plate.brackets == "attacking" then
		ticks(l.width, l.height, style.attacking_color, m)
	end
	if is_selected(plate) then
		ticks(l.width, l.height, style.selected_color) -- around the red ones when both
	end
	canvas.text(l.name, l.center, style.name_baseline + m, style.font, l.color, style.outline)
	if plate.has_bar then
		local left = math.floor(l.center - style.bar_width / 2)
		local fraction = math.max(0, math.min(1, plate.health))
		local filled = math.floor(style.bar_width * fraction + 0.5)
		local f = style.frame
		local top = style.bar_top + m
		canvas.rectangle(left - f, top - f, style.bar_width + f * 2, style.bar_height + f * 2, style.frame_color)
		canvas.rectangle(left, top, style.bar_width, style.bar_height, style.track_color)
		if filled > 0 then
			canvas.rectangle(left, top, filled, style.bar_height, health_color(plate))
			canvas.rectangle(left, top, filled, 1, style.shine_color)
		end
	end
	if plate.organization ~= "" then
		canvas.text(plate.organization, l.center, l.organization_baseline, style.organization_font,
			style.organization_color, style.outline)
	end
end
