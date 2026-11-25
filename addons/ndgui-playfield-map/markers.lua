-- ndGUI Local Map: marker + overlay composition (DarkTech sprites from tools/skin.py).
-- Everything is drawn in projected content coordinates on the native map surface.
local surface = game.map_surface

local SPRITE = {
	marked = "GFX_GUI_NDGUI_MAP_MARKED",
	selected = "GFX_GUI_NDGUI_MAP_SELECTED",
	monster = "GFX_GUI_NDGUI_MAP_MONSTER",
	team = "GFX_GUI_NDGUI_MAP_TEAM",
	clan = "GFX_GUI_NDGUI_MAP_CLAN",
	omni = "GFX_GUI_NDGUI_MAP_OMNI",
	neutral = "GFX_GUI_NDGUI_MAP_NEUTRAL",
	door = "GFX_GUI_NDGUI_MAP_DOOR",
	shop = "GFX_GUI_NDGUI_MAP_SHOP",
	mission = "GFX_GUI_NDGUI_MAP_MISSION",
	player = "GFX_GUI_NDGUI_MAP_PLAYER",
}
local FACING = { selected = true, player = true }

-- If the client rejects one of our sprites (skin not installed, renamed upstream...), draw
-- the stock marker instead and never take the map down.
local FALLBACK = {
	GFX_GUI_NDGUI_MAP_PLAYER = "GFX_GUI_MAP_ARROW", GFX_GUI_NDGUI_MAP_MARKED = "GFX_GUI_MAP_BIG_ARROW",
	GFX_GUI_NDGUI_MAP_SELECTED = "GFX_GUI_MAP_ARROW_SELECTED", GFX_GUI_NDGUI_MAP_MONSTER = "GFX_GUI_MAPSQUARE_MONSTER",
	GFX_GUI_NDGUI_MAP_TEAM = "GFX_GUI_MAPSQUARE_TEAMMEMBER", GFX_GUI_NDGUI_MAP_CLAN = "GFX_GUI_MAPSQUARE_CLAN",
	GFX_GUI_NDGUI_MAP_OMNI = "GFX_GUI_MAPSQUARE_OMNI", GFX_GUI_NDGUI_MAP_NEUTRAL = "GFX_GUI_MAPSQUARE_NEUTRAL",
	GFX_GUI_NDGUI_MAP_DOOR = "GFX_GUI_MAPFLAG_CYAN", GFX_GUI_NDGUI_MAP_SHOP = "GFX_GUI_MAPSQUARE_SHOP",
	GFX_GUI_NDGUI_MAP_MISSION = "GFX_GUI_MAPSQUARE_MISSION", GFX_GUI_NDGUI_MAP_TRAIL = "GFX_GUI_MAPSQUARE_NEUTRAL",
	GFX_GUI_NDGUI_MAP_TRAIL_NEW = "GFX_GUI_MAPSQUARE_TEAMMEMBER", GFX_GUI_NDGUI_MAP_RING = "GFX_GUI_MAPSQUARE_NEUTRAL",
	GFX_GUI_NDGUI_MAP_ROUTE = "GFX_GUI_MAPSQUARE_SHOP",
}
local rejected = {}
MapSpriteRejected = rejected

local function sprite(graphic, x, y, facing)
	if rejected[graphic] then
		graphic = FALLBACK[graphic]
		if not graphic then
			return
		end
		pcall(surface.sprite, graphic, x, y, facing, 1)
		return
	end
	if not pcall(surface.sprite, graphic, x, y, facing, 1) then
		rejected[graphic] = true
		if FALLBACK[graphic] then
			pcall(surface.sprite, FALLBACK[graphic], x, y, facing, 1)
		end
	end
end

-- Filter groups shown in the "Show" menu, in menu order. Player/waypoint/selection always draw.
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
	shown = {},          -- filter key -> bool
	readings = {},       -- last native marker list
	counts = {},         -- filter key -> visible count
	trail = {},          -- { {x, y}, ... } content coordinates, oldest first
	rings = nil,         -- { x, y, radius_per_metre, metres = {...} } or nil
	reticle = nil,       -- { x, y } content coordinates or nil
	dot_step = 6,        -- content units between ring dots (set from zoom)
	waypoint = nil,      -- { x, y } content coordinates of the native waypoint, or nil
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
		sprite("GFX_GUI_NDGUI_MAP_RING", cx + radius * math.cos(a), cy + radius * math.sin(a), 0)
	end
end

function MapOverlay.compose()
	local self = MapOverlay
	surface.markers_begin()
	-- Underlay first: trail, then range rings.
	local trail = self.trail
	for i = 1, #trail do
		sprite(i > #trail - 8 and "GFX_GUI_NDGUI_MAP_TRAIL_NEW" or "GFX_GUI_NDGUI_MAP_TRAIL", trail[i][1], trail[i][2], 0)
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
	-- The native waypoint is the "marked" subject: route line from me to it underneath.
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
			sprite("GFX_GUI_NDGUI_MAP_ROUTE", player.x + dx * i / count, player.y + dy * i / count, 0)
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
				-- Unknown native kinds still show (as a neutral dot) instead of vanishing.
				sprite(graphic or SPRITE.neutral, marker.x, marker.y, FACING[marker.kind] and marker.facing or 0)
			end
		end
	end
	if self.reticle then
		sprite("GFX_GUI_NDGUI_MAP_RETICLE", self.reticle[1], self.reticle[2], 0)
	end
	-- Waypoint, then the player arrow, always on top of everything.
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
