-- ndGUI Local Map: marketplace-safe markers (stock atlas ids + primitives only).
-- Facing / recognition sprites use stock GFX_GUI_MAP_*; rings, trail, route and
-- reticle use DarkTech-colored fan/line primitives.
local surface = game.map_surface

local SPRITE = {
	marked = "GFX_GUI_MAP_BIG_ARROW",
	selected = "GFX_GUI_MAP_ARROW_SELECTED",
	monster = "GFX_GUI_MAPSQUARE_MONSTER",
	team = "GFX_GUI_MAPSQUARE_TEAMMEMBER",
	clan = "GFX_GUI_MAPSQUARE_CLAN",
	omni = "GFX_GUI_MAPSQUARE_OMNI",
	neutral = "GFX_GUI_MAPSQUARE_NEUTRAL",
	door = "GFX_GUI_MAPFLAG_CYAN",
	shop = "GFX_GUI_MAPSQUARE_SHOP",
	mission = "GFX_GUI_MAPSQUARE_MISSION",
	player = "GFX_GUI_MAP_ARROW",
}
local FACING = { selected = true, player = true }

local C = {
	trail = "#6CB6FF",
	trail_new = "#C5E2FF",
	ring = "#6CB6FF",
	route = "#E8C05A",
	reticle = "#6CB6FF",
}

local rejected = {}
MapSpriteRejected = rejected

local function sprite(graphic, x, y, facing)
	if rejected[graphic] then
		return
	end
	if not pcall(surface.sprite, graphic, x, y, facing or 0, 1) then
		rejected[graphic] = true
	end
end

local function dot(x, y, radius, color)
	surface.fan(x, y, radius, 0, math.pi * 2, color)
end

local function reticle(x, y)
	local c, r = C.reticle, 4
	surface.line(x - r, y, x + r, y, 1, c)
	surface.line(x, y - r, x, y + r, 1, c)
	surface.line(x - 2, y - 2, x + 2, y - 2, 1, c)
	surface.line(x + 2, y - 2, x + 2, y + 2, 1, c)
	surface.line(x + 2, y + 2, x - 2, y + 2, 1, c)
	surface.line(x - 2, y + 2, x - 2, y - 2, 1, c)
end

MAP_FILTERS = {
	{ key = "monster", label = "Monsters", kinds = { monster = true } },
	{ key = "players", label = "Other players", kinds = { clan = true, omni = true, neutral = true } },
	{ key = "team", label = "Team", kinds = { team = true } },
	{ key = "shop", label = "Shops", kinds = { shop = true } },
	{ key = "mission", label = "Missions", kinds = { mission = true } },
	{ key = "door", label = "Doors", kinds = { door = true } },
	{ key = "wedge", label = "Vision cones", kinds = { wedge = true } },
}
local GROUP = {}
for _, filter in ipairs(MAP_FILTERS) do
	for kind in pairs(filter.kinds) do
		GROUP[kind] = filter.key
	end
end

MapOverlay = {
	shown = {},
	readings = {},
	counts = {},
	trail = {},
	rings = nil,
	reticle = nil,
	dot_step = 6,
	waypoint = nil,
}
for _, filter in ipairs(MAP_FILTERS) do
	MapOverlay.shown[filter.key] = true
end

local function ring(cx, cy, radius, step)
	if radius <= 0 then
		return
	end
	local count = math.max(24, math.min(160, math.floor(2 * math.pi * radius / math.max(1, step))))
	for i = 0, count - 1 do
		local a = 2 * math.pi * i / count
		dot(cx + radius * math.cos(a), cy + radius * math.sin(a), 1, C.ring)
	end
end

function MapOverlay.compose()
	local self = MapOverlay
	surface.markers_begin()
	local trail = self.trail
	for i = 1, #trail do
		local color = i > #trail - 8 and C.trail_new or C.trail
		dot(trail[i][1], trail[i][2], i > #trail - 8 and 1.5 or 1, color)
	end
	local rings = self.rings
	if rings then
		for _, metres in ipairs(rings.metres) do
			ring(rings.x, rings.y, metres * rings.scale, self.dot_step)
		end
	end
	local counts = {}
	for _, filter in ipairs(MAP_FILTERS) do
		counts[filter.key] = 0
	end
	local player, waypoint
	for _, marker in ipairs(self.readings) do
		if marker.kind == "player" then
			player = marker
		elseif marker.kind == "marked" then
			waypoint = marker
		end
	end
	self.waypoint = waypoint and { waypoint.x, waypoint.y } or nil
	if player and waypoint then
		local dx, dy = waypoint.x - player.x, waypoint.y - player.y
		local length = math.sqrt(dx * dx + dy * dy)
		local step = math.max(1, self.dot_step * 1.5)
		local count = math.min(200, math.floor(length / step))
		for i = 1, count - 1 do
			dot(player.x + dx * i / count, player.y + dy * i / count, 1, C.route)
		end
	end
	for _, marker in ipairs(self.readings) do
		local group = GROUP[marker.kind]
		if group then
			counts[group] = counts[group] + 1
		end
		if marker.kind == "player" or marker.kind == "marked" then
			-- drawn last, on top
		elseif not group or self.shown[group] then
			if marker.kind == "wedge" then
				local direction = marker.facing - math.pi / 2
				surface.fan(marker.x, marker.y, marker.radius,
					direction - marker.half_angle, direction + marker.half_angle, "#383D8FD4")
			else
				local graphic = SPRITE[marker.kind]
				sprite(graphic or SPRITE.neutral, marker.x, marker.y, FACING[marker.kind] and marker.facing or 0)
			end
		end
	end
	if self.reticle then
		reticle(self.reticle[1], self.reticle[2])
	end
	if waypoint then
		sprite(SPRITE.marked, waypoint.x, waypoint.y, 0)
	end
	if player then
		sprite(SPRITE.player, player.x, player.y, player.facing)
	end
	surface.markers_end()
	self.counts = counts
end

function map_markers_apply(readings)
	MapOverlay.readings = readings or {}
	MapOverlay.compose()
end
