-- Dovvetech prk.target-panels provider. One VM per panel (friendly / hostile).
-- Panels sit on the top edge either side of the centred compass, capped in width.
local D = ui.require("notum.ndgui-lib/dovvetech")
local root = ui.load("panel.xml")
ui.root(root)
local placement = D.movable(root)

local minimum_bar_width = 64
local maximum_bar_width = 300
local compass_clearance = D.COMPASS_CLEARANCE
local upper = {
	slot = ui.find(root, "target_upper"),
	bar = ui.find(root, "target_upper_bar"),
	name = ui.find(root, "target_upper_name"),
	pct = ui.find(root, "target_upper_pct"),
	fill = ui.find(root, "target_upper_fill"),
}
local lower = {
	slot = ui.find(root, "target_lower"),
	bar = ui.find(root, "target_lower_bar"),
	name = ui.find(root, "target_lower_name"),
	pct = ui.find(root, "target_lower_pct"),
	fill = ui.find(root, "target_lower_fill"),
}

local function panel_width(viewport_width)
	-- Room between the screen edge and the centred compass on each half.
	local room = viewport_width * 0.5 - compass_clearance - D.MARGIN
	return math.floor(math.max(minimum_bar_width, math.min(maximum_bar_width, room)))
end

local function apply_slot(views, slot, maximum)
	local visible = slot.name ~= ""
	ui.visible(views.slot, visible)
	ui.visible(views.bar, visible and slot.has_bar)
	if not visible then
		return
	end

	-- Inner width of the plate (7px padding each side); native length scales the bar.
	local inner = maximum - 14
	local width = math.floor(minimum_bar_width + (inner - minimum_bar_width) * slot.length)
	local fraction = math.max(0, math.min(1, slot.fraction or 0))
	local filled = math.floor(width * fraction + 0.5)
	ui.size(views.bar, width, 10)
	ui.visible(views.fill, filled > 0)
	if filled > 0 then
		ui.size(views.fill, filled, 10)
	end
	ui.graphic_tint(views.fill, string.format("#%06x", slot.bar_color))
	ui.visible(views.pct, slot.has_bar)
	ui.text(views.pct, tostring(math.floor(fraction * 100 + 0.5)) .. "%")
	-- Out of reach dims the readout instead of the stock bar highlight.
	ui.text_color(views.pct, slot.in_reach and D.color.text or D.color.text_dim)
	ui.text(views.name, slot.name)
	ui.tooltip(views.slot, slot.header)
	ui.text_color(views.name, string.format("#%06x", slot.name_color))
end

ui.visible(upper.slot, false)
ui.visible(lower.slot, false)

function target_panel_place(viewport_width, hostile)
	local width = panel_width(viewport_width)
	local centre = viewport_width * 0.5
	local x = hostile and (centre + compass_clearance) or (centre - compass_clearance - width)
	ui.size(root, width, -1)
	D.place_default(placement, root, math.floor(math.max(0, x)), D.TOP_Y)
end

function target_panel_apply(upper_slot, lower_slot, viewport_width)
	local maximum = panel_width(viewport_width)
	ui.size(root, maximum, -1)
	apply_slot(upper, upper_slot, maximum)
	apply_slot(lower, lower_slot, maximum)
end
