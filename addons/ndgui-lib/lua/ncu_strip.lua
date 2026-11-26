-- Marketplace NCU strip: same as Core ncu.strip, but cells load from the package
-- (shared=false) so wells can be library:// open_*.png instead of stock atlas slots.
-- Loaded as notum.ndgui-lib/ncu_strip via <Modules root="lua" /> (file body = factory).
local Grid = ui.require("notum.ndgui-lib/slot_cells")
local Table = ui.require("core.table")
local Presentation = ui.require("ncu.presentation")
local Strip = {}
Strip.__index = Strip

function Strip.create(host, options)
	local self = setmetatable({ host = host, options = options }, Strip)
	self.cells = Grid.cells({
		stable = true,
		collection = options.collection,
		host = host,
		template = options.template,
		binding = function(entry)
			return entry.token
		end,
		icon = function(entry)
			return entry.icon
		end,
		overlay = Presentation.frame,
		progress = Presentation.elapsed,
		opacity = options.flash and Presentation.flash or nil,
		tooltip = function(entry)
			return Presentation.tooltip(entry, true)
		end,
	})
	if options.collection and not ui.in_combat() then
		ui.collection_collapse(host)
	end
	return self
end

function Strip:show(snapshot, width, shown)
	local entries = {}
	for _, entry in ipairs(snapshot) do
		if shown and not entry.hidden then
			entries[#entries + 1] = entry
		end
	end
	local options = self.options
	local columns = math.max(1, math.floor((width + 1) / (options.cell_width + 1)))
	local ordered = Table.ordered(entries, {
		value = Presentation.remaining,
		tie = function(a, b)
			return a.nano_id == b.nano_id and 0 or a.nano_id < b.nano_id and -1 or 1
		end,
	})
	if options.lines then
		for index = #ordered, columns * options.lines + 1, -1 do
			ordered[index] = nil
		end
	end
	local count = #ordered
	local lines = math.ceil(count / columns)
	local capacity = options.padded and lines * columns or count
	local across = options.padded and columns or math.min(capacity, columns)
	ui.size(self.host, math.max(0, across * (options.cell_width + 1) - 1), -1)
	ui.visible(self.host, count > 0)
	self.cells:show(ordered, capacity)
	return lines > 0 and lines * (options.cell_height + 1) - 1 or 0
end

function Strip:destroy()
	self.cells:destroy()
end

return Strip
