-- Drop-in for core.icon_grid when the cell template is a stacked well (BitmapView chrome
-- behind an ItemSlotView named ndgui_slot). icon_grid binds the template root; this module
-- routes icon / content / bind / fade to the inner slot so chrome is never the bind target.
-- Size helpers (create / slots) come from Core so callers can swap the require only.
local Security = ui.require("core.security")
local Core = ui.require("core.icon_grid")

local SlotCells = {}
SlotCells.__index = SlotCells

local fields = {
	{ name = "icon", write = ui.icon, empty = 0 },
	{ name = "tooltip", write = ui.tooltip, empty = "" },
	{ name = "badge", write = ui.badge, empty = "" },
	{ name = "overlay", write = ui.overlay, empty = "" },
	{ name = "enabled", write = ui.enabled, empty = true },
	{ name = "opacity", write = ui.opacity, empty = 1 },
	{ name = "selected", write = ui.selected, empty = false },
	{ name = "corner", write = ui.corner, empty = "" },
	{ name = "center", write = ui.center, empty = "" },
	{ name = "progress", write = ui.progress, empty = 0 },
}

local function resolve_slot(root)
	for _, name in ipairs({ "ndgui_slot", "ncu_slot", "action_slot", "trade_slot", "nano_slot" }) do
		local ok, slot = pcall(ui.find, root, name)
		if ok and slot then
			return slot
		end
	end
	return root
end

local function target(cell)
	return cell.slot or cell.root
end

function SlotCells.cells(options)
	assert(
		options.host and (options.template or options.views) and options.binding,
		"Grid cells require a host, template or fixed views, and binding"
	)
	assert(
		options.button == nil or options.button == "left" or options.button == "right",
		"Unsupported grid button"
	)
	assert(
		options.secondary_action == nil
			or (
				options.action
				and (options.secondary_button == "left" or options.secondary_button == "right")
				and options.secondary_button ~= (options.button or "left")
			),
		"Secondary grid actions require the other supported button"
	)
	local self = setmetatable({ options = options, cells = {} }, SlotCells)
	if options.collection and not ui.in_combat() then
		self.prototype = self:create_cell()
		ui.collection(options.collection, options.host, self.prototype.root)
	end
	Security.observe(self)
	return self
end

function SlotCells:create_cell()
	local root
	if self.options.views then
		root = self.options.views[#self.cells + 1]
	elseif self.options.shared then
		root = ui.shared_layout(self.options.template)
	else
		root = ui.load(self.options.template)
	end
	local cell = { root = root, slot = resolve_slot(root), values = {} }
	if not self.options.views then
		ui.add(self.options.host, cell.root)
	end
	if self.options.activate then
		local function activate()
			if cell.entry and cell.content then
				self.options.activate(cell.entry)
			end
		end
		local hit = target(cell)
		if self.options.button == "right" then
			ui.on_pointer_release(hit, "right", activate)
		else
			ui.on_click(hit, activate)
		end
	end
	return cell
end

function SlotCells:bind(cell, entry)
	cell.entry = entry
	if not cell.slot then
		cell.slot = resolve_slot(cell.root)
	end
	local view = target(cell)
	local locked = ui.in_combat()
	local content = entry ~= nil and (not self.options.content or self.options.content(entry))
	if cell.content ~= content then
		ui.content(view, content)
		cell.content = content
	end
	local binding = entry and self.options.binding(entry) or 0
	if not locked and ui.binding(view) ~= binding then
		ui.bind(view, binding)
	end
	for _, field in ipairs(fields) do
		local value = field.empty
		local read = self.options[field.name]
		if entry and read then
			value = read(entry)
		end
		if
			not (locked and (field.name == "enabled" or field.name == "selected"))
			and cell.values[field.name] ~= value
		then
			field.write(view, value)
			cell.values[field.name] = value
		end
	end
	if self.options.action and not locked then
		ui.action(view, self.options.action, binding, self.options.button or "left")
		if self.options.secondary_action then
			ui.action(view, self.options.secondary_action, binding, self.options.secondary_button)
		end
	end
	local faded = entry ~= nil and self.options.faded and self.options.faded(entry) or false
	local tint = entry and self.options.tint and self.options.tint(entry) or ""
	if cell.faded ~= faded or cell.tint ~= tint then
		ui.fade(view, faded, tint)
		cell.faded, cell.tint = faded, tint
	end
end

function SlotCells:retire()
	local cell = self.cells[#self.cells]
	cell.entry = nil
	ui.destroy(cell.root)
	self.cells[#self.cells] = nil
end

function SlotCells:show(entries, capacity, length)
	self.entries, self.capacity, self.length = entries, capacity, length
	if ui.in_combat() then
		if self.options.collection then
			local previous = {}
			for _, cell in ipairs(self.cells) do
				previous[cell.root] = cell
			end
			self.cells = {}
			for index = 1, ui.child_count(self.options.host) do
				local root = ui.child(self.options.host, index)
				local cell = previous[root] or { root = root, values = {} }
				cell.slot = resolve_slot(root)
				self.cells[index] = cell
			end
		end
		local by_binding = {}
		for _, entry in pairs(entries) do
			by_binding[self.options.binding(entry)] = entry
		end
		for _, cell in ipairs(self.cells) do
			self:bind(cell, by_binding[ui.binding(target(cell))])
		end
		return
	end
	local count = math.max(length or #entries, capacity or 0)
	assert(not self.options.views or count == #self.options.views, "Fixed cells must retain their layout positions")
	if self.options.views then
		while #self.cells < count do
			self.cells[#self.cells + 1] = self:create_cell()
		end
	elseif self.options.stable then
		self.cells = Security.reconcile(self.options.host, self.cells, entries, count, self.options.binding,
			function() return self:create_cell() end,
			function(cell) cell.entry = nil; ui.destroy(cell.root) end,
			function(cell) return ui.binding(target(cell)) end)
	else
		while #self.cells > count do self:retire() end
		while #self.cells < count do self.cells[#self.cells + 1] = self:create_cell() end
	end
	for index, cell in ipairs(self.cells) do
		self:bind(cell, entries[index])
	end
end

function SlotCells:on_lockdown(locked)
	if not locked and self.entries then
		self:show(self.entries, self.capacity, self.length)
	end
end

function SlotCells:clear()
	if ui.in_combat() then
		return
	end
	while #self.cells > 0 do
		self:retire()
	end
end

function SlotCells:destroy()
	Security.forget(self)
	self:clear()
	if self.prototype then
		ui.destroy(self.prototype.root)
	end
end

SlotCells.create = Core.create
SlotCells.slots = Core.slots

return SlotCells
