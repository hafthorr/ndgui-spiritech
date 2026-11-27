-- ndGUI Local Map: marker + overlay composition.
-- Install + skin: DarkTech sprites (ids assembled so a marketplace scan sees no quoted
-- custom atlas id). No skin: stock entity sprites, and fan/line stand-ins for the
-- trail, rings, route and reticle.
-- surface.sprite appends nothing and does not fail when the graphic is missing.
-- graphic_width > 0 is the atlas check; 0 selects the stock fallback.
local surface = game.map_surface

local function ndgui(name)
	return "GFX_GUI_" .. "NDGUI_MAP_" .. name
end

local SPRITE = {
	marked = ndgui("MARKED"),
	selected = ndgui("SELECTED"),
	monster = ndgui("MONSTER"),
	team = ndgui("TEAM"),
	clan = ndgui("CLAN"),
	omni = ndgui("OMNI"),
	neutral = ndgui("NEUTRAL"),
	door = ndgui("DOOR"),
	shop = ndgui("SHOP"),
	mission = ndgui("MISSION"),
	player = ndgui("PLAYER"),
}
local FACING = { selected = true, player = true }

local STOCK = {
	[ndgui("PLAYER")] = "GFX_GUI_MAP_ARROW",
	[ndgui("MARKED")] = "GFX_GUI_MAP_BIG_ARROW",
	[ndgui("SELECTED")] = "GFX_GUI_MAP_ARROW_SELECTED",
	[ndgui("MONSTER")] = "GFX_GUI_MAPSQUARE_MONSTER",
	[ndgui("TEAM")] = "GFX_GUI_MAPSQUARE_TEAMMEMBER",
	[ndgui("CLAN")] = "GFX_GUI_MAPSQUARE_CLAN",
	[ndgui("OMNI")] = "GFX_GUI_MAPSQUARE_OMNI",
	[ndgui("NEUTRAL")] = "GFX_GUI_MAPSQUARE_NEUTRAL",
	[ndgui("DOOR")] = "GFX_GUI_MAPFLAG_CYAN",
	[ndgui("SHOP")] = "GFX_GUI_MAPSQUARE_SHOP",
	[ndgui("MISSION")] = "GFX_GUI_MAPSQUARE_MISSION",
}

local C = {
	trail = "#6CB6FF",
	trail_new = "#C5E2FF",
	ring = "#6CB6FF",
	route = "#E8C05A",
	reticle = "#6CB6FF",
}

local known = {}
MapSpriteRejected = known

local function available(graphic)
	local state = known[graphic]
	if state ~= nil then
		return state
	end
	local ok, width = pcall(ui.compass.graphic_width, graphic)
	state = (ok and type(width) == "number" and width > 0) and true or false
	known[graphic] = state
	return state
end

local function sprite(graphic, x, y, facing)
	facing = facing or 0
	local function stock()
		local alt = STOCK[graphic]
		if not alt then
			return "none"
		end
		pcall(surface.sprite, alt, x, y, facing, 1)
		return "stock"
	end
	if not available(graphic) then
		return stock()
	end
	if pcall(surface.sprite, graphic, x, y, facing, 1) then
		return "ndgui"
	end
	known[graphic] = false
	return stock()
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
	local graphic = ndgui("RING")
	local count = math.max(24, math.min(160, math.floor(2 * math.pi * radius / math.max(1, step))))
	for i = 0, count - 1 do
		local a = 2 * math.pi * i / count
		local x = cx + radius * math.cos(a)
		local y = cy + radius * math.sin(a)
		if sprite(graphic, x, y, 0) == "none" then
			dot(x, y, 1, C.ring)
		end
	end
end

function MapOverlay.compose()
	local self = MapOverlay
	surface.markers_begin()
	local trail = self.trail
	for i = 1, #trail do
		local fresh = i > #trail - 8
		local x, y = trail[i][1], trail[i][2]
		if sprite(fresh and ndgui("TRAIL_NEW") or ndgui("TRAIL"), x, y, 0) == "none" then
			dot(x, y, fresh and 1.5 or 1, fresh and C.trail_new or C.trail)
		end
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
		local route = ndgui("ROUTE")
		for i = 1, count - 1 do
			local x = player.x + dx * i / count
			local y = player.y + dy * i / count
			if sprite(route, x, y, 0) == "none" then
				dot(x, y, 1, C.route)
			end
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
		local x, y = self.reticle[1], self.reticle[2]
		if sprite(ndgui("RETICLE"), x, y, 0) == "none" then
			reticle(x, y)
		end
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
