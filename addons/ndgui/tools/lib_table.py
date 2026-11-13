"""Build ndgui-lib/lua/table.lua: Core's table.lua with hideable columns.

Run from the ndgui folder:  python tools/lib_table.py
Right-click any column header -> Move left / Move right / Reset column order, then the
columns (tick = shown) + "Show all columns". Order persists as <preference>.col_order; lists
with native rows (Inventory list, NCU) apply a new order the next time the window loads.
Hidden ids persist per table as <preference>.col_hidden (",id,id,"). At least one column
always stays visible; toggling is refused in combat like resizing. Every ndgui-* package
that used ui.require("core.table") is pointed at ui.require("notum.ndgui-lib/table")
(fork_windows.py / fork_hud.py do the same on regeneration). Re-run after a client update.
"""
import glob, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ADDONS = os.path.normpath(os.path.join(HERE, "..", ".."))
CORE = os.path.normpath(os.path.join(ADDONS, "..", "Packages", "Core", "table.lua"))
OUT = os.path.join(ADDONS, "ndgui-lib", "lua", "table.lua")
OLD_REQ, NEW_REQ = 'ui.require("core.table")', 'ui.require("notum.ndgui-lib/table")'

PATCHES = [
    # hidden set, read with the other column preferences
    ("""		local saved = {}
		local ids = Preferences.read_array(self.preference .. ".col_id", "text")""",
     """		self.hidden = {}
		for id in (ui.preference.read(self.preference .. ".col_hidden") or ""):gmatch("[^,]+") do
			self.hidden[id] = true
		end
		local shown = 0
		for _, column in ipairs(self.columns) do
			if not self.hidden[column.id] then
				shown = shown + 1
			end
		end
		if shown == 0 then
			self.hidden = {}
		end
		local saved = {}
		local ids = Preferences.read_array(self.preference .. ".col_id", "text")"""),
    # fit_columns: hidden columns take no room
    ("""		local overflow = 12 + #self.columns * self.style.gap - width
		for _, preferred in ipairs(self.preferred_widths) do
			overflow = overflow + preferred
		end
		for index, column in ipairs(self.columns) do
			local preferred = self.preferred_widths[index]""",
     """		local overflow = 12 - width
		for index, preferred in ipairs(self.preferred_widths) do
			if self:column_shown(index) then
				overflow = overflow + preferred + self.style.gap
			end
		end
		for index, column in ipairs(self.columns) do
			local preferred = self:column_shown(index) and self.preferred_widths[index] or (column.minimum or 5)"""),
    # cells of hidden columns are collapsed
    ("""		local column, width, cell = self.columns[index], self.widths[index], row.cells[index]
		ui.size(cell.root, width + self.style.gap, self.row_height)""",
     """		local column, width, cell = self.columns[index], self.widths[index], row.cells[index]
		if not cell or not cell.root then
			return
		end
		local shown = self:column_shown(index)
		if cell.shown ~= shown then
			ui.visible(cell.root, shown)
			cell.shown = shown
		end
		if not shown then
			ui.size(cell.root, 0, self.row_height)
			return
		end
		ui.size(cell.root, width + self.style.gap, self.row_height)"""),
    ("""		local width, heading = self.widths[index], self.headers[index]
		ui.size(heading.root, width + self.style.gap, self.style.header_height)
		ui.size(heading.title, math.max(1, width - self.style.inset), self.style.header_height)""",
     """		local width, heading = self.widths[index], self.headers[index]
		ui.visible(heading.root, self:column_shown(index))
		if self:column_shown(index) then
			ui.size(heading.root, width + self.style.gap, self.style.header_height)
			-- fixed columns (icons) have no divider: let the heading use that room, so a 16px icon
			-- column gets a real header box instead of a 10px sliver that reads as part of the next column
			local title_width = self.columns[index].resizable == false and width + self.style.gap - 2
				or width - self.style.inset
			ui.size(heading.title, math.max(1, title_width), self.style.header_height)
		else
			ui.size(heading.root, 0, self.style.header_height)
		end"""),
    ("""		local total = 0
		for _, column_width in ipairs(self.widths) do
			total = total + column_width + self.style.gap
		end""",
     """		local total = 0
		for column_index, column_width in ipairs(self.widths) do
			if self:column_shown(column_index) then
				total = total + column_width + self.style.gap
			end
		end"""),
    # native (collection) rows adopted in combat: keep hidden cells collapsed
    ("""			self.rows[index] = row
		end
	end""",
     """			self.rows[index] = row
			for column_index = 1, #self.columns do
				self:cell_width(row, column_index)
			end
		end
	end"""),
    # the column API
    ("""	function Table:drop_target(binding)""",
     """	function Table:column_shown(index)
		local column = self.columns[index]
		return not (column and self.hidden and self.hidden[column.id])
	end

	function Table:apply_columns()
		for index = 1, #self.columns do
			self:apply_width(index)
		end
		if self.width and self.options.fit_columns then
			self:set_width(self.width)
		end
		local parts = { "," }
		for _, column in ipairs(self.columns) do
			if self.hidden[column.id] then
				parts[#parts + 1] = column.id .. ","
			end
		end
		ui.preference.write(self.preference .. ".col_hidden", #parts > 1 and table.concat(parts) or "", "text")
	end

	function Table:toggle_column(index)
		if ui.in_combat() then
			return
		end
		local column = self.columns[index]
		if not self.hidden[column.id] then
			local shown = 0
			for other = 1, #self.columns do
				if self:column_shown(other) then
					shown = shown + 1
				end
			end
			if shown <= 1 then
				return
			end
		end
		self.hidden[column.id] = not self.hidden[column.id] or nil
		self:apply_columns()
	end

	-- Column order: saved ids first (in saved order), then any others in package order.
	function Table:order_columns()
		local by_id, used, ordered = {}, {}, {}
		for _, column in ipairs(self.options.columns) do
			by_id[column.id] = column
		end
		for id in (ui.preference.read(self.preference .. ".col_order") or ""):gmatch("[^,]+") do
			if by_id[id] and not used[id] then
				ordered[#ordered + 1], used[id] = by_id[id], true
			end
		end
		for _, column in ipairs(self.options.columns) do
			if not used[column.id] then
				ordered[#ordered + 1] = column
			end
		end
		self.columns = ordered
	end

	function Table:build_headers()
		local style, saved = self.style, self.saved_widths
		for index, column in ipairs(self.columns) do
			assert(not (self.options.collection and column.kind == "custom"), "Custom cells require package-owned rows")
			local width = saved[column.id] or column.width
			self.widths[index] = math.max(column.minimum or 5, math.min(column.maximum or 1000, width))
			self.preferred_widths[index] = self.widths[index]
			local fragment = ui.shared_layout(style.header)
			local heading =
				{ root = fragment, title = ui.find(fragment, "heading"), divider = ui.find(fragment, "divider") }
			self.headers[index] = heading
			ui.text_alignment(heading.title, column.alignment or "left")
			ui.add(self.header, fragment)
			local id = column.id
			ui.on_pointer_release(heading.title, "right", function()
				self:column_menu(heading.title, id)
			end)
			if column.value then
				ui.on_click(heading.title, function()
					self:sort_by(id)
				end)
			end
			local resizable = column.resizable ~= false
			ui.visible(heading.divider, resizable)
			if resizable then
				local initial
				ui.on_drag_start(heading.divider, function()
					initial = self.widths[index]
				end)
				ui.on_drag(heading.divider, function(offset)
					if initial == nil then
						return
					end
					self:resize_column(index, initial + offset)
					self:save_widths()
				end)
			end
			self:apply_width(index)
		end
		self:headings()
	end

	-- Rebuild header and rows in the current self.columns order (package-owned rows only;
	-- native collection rows are cloned from a prototype once, so those apply on next load).
	function Table:rebuild()
		for index, column in ipairs(self.columns) do
			if self.preferred_widths[index] then
				self.saved_widths[column.id] = self.preferred_widths[index]
			end
		end
		for _, heading in ipairs(self.headers) do
			ui.destroy(heading.root)
		end
		for _, row in ipairs(self.rows) do
			ui.destroy(row.root)
		end
		self.headers, self.widths, self.preferred_widths, self.rows = {}, {}, {}, {}
		self:build_headers()
		if self.width and self.options.fit_columns then
			self:set_width(self.width)
		end
		self:show(self.entries)
	end

	-- Columns as they will be ordered: native collection tables only re-order on next load,
	-- so their pending order is kept apart from the live self.columns.
	function Table:order_list()
		if not self.options.collection then
			return self.columns
		end
		if not self.next_columns then
			self.next_columns = {}
			for index, column in ipairs(self.columns) do
				self.next_columns[index] = column
			end
		end
		return self.next_columns
	end

	function Table:save_order()
		local parts = { "," }
		for _, column in ipairs(self:order_list()) do
			parts[#parts + 1] = column.id .. ","
		end
		ui.preference.write(self.preference .. ".col_order", table.concat(parts), "text")
	end

	function Table:move_column(id, step)
		if ui.in_combat() then
			return
		end
		local list, from = self:order_list(), nil
		for index, column in ipairs(list) do
			if column.id == id then
				from = index
			end
		end
		local to = from and from + step
		if not to or to < 1 or to > #list then
			return
		end
		if self.options.collection then
			-- saved order only; native rows pick it up the next time the window loads
			list[from], list[to] = list[to], list[from]
			self:save_order()
			return
		end
		for index, column in ipairs(self.columns) do
			self.saved_widths[column.id] = self.preferred_widths[index]
		end
		self.columns[from], self.columns[to] = self.columns[to], self.columns[from]
		self:save_order()
		self:rebuild()
		self:save_widths()
	end

	function Table:reset_order()
		if ui.in_combat() then
			return
		end
		ui.preference.write(self.preference .. ".col_order", "", "text")
		if self.options.collection then
			self.next_columns = {}
			for index, column in ipairs(self.options.columns) do
				self.next_columns[index] = column
			end
			return
		end
		for index, column in ipairs(self.columns) do
			self.saved_widths[column.id] = self.preferred_widths[index]
		end
		self:order_columns()
		self:rebuild()
	end

	function Table:column_menu(anchor, id)
		if ui.in_combat() then
			return
		end
		ui.menu.clear(anchor)
		pcall(ui.menu.style, anchor, "context")
		local list = self:order_list()
		local position, title_of = 0, ""
		for index, column in ipairs(list) do
			if column.id == id then
				position = index
				title_of = column.title ~= "" and column.title or (column.kind == "icon" and "Icon" or column.id)
			end
		end
		local later = self.options.collection and "  (after restart)" or ""
		if position > 1 then
			ui.menu.add(anchor, "Move " .. title_of .. " left" .. later, false, function() self:move_column(id, -1) end)
		else
			ui.menu.label(anchor, "Move " .. title_of .. " left")
		end
		if position > 0 and position < #list then
			ui.menu.add(anchor, "Move " .. title_of .. " right" .. later, false, function() self:move_column(id, 1) end)
		else
			ui.menu.label(anchor, "Move " .. title_of .. " right")
		end
		ui.menu.add(anchor, "Reset column order" .. later, false, function() self:reset_order() end)
		ui.menu.separator(anchor)
		for index, column in ipairs(self.columns) do
			local title = column.title ~= "" and column.title or (column.kind == "icon" and "Icon" or column.id)
			ui.menu.add(anchor, title, self:column_shown(index), function()
				self:toggle_column(index)
			end)
		end
		ui.menu.separator(anchor)
		ui.menu.add(anchor, "Show all columns", false, function()
			if not ui.in_combat() then
				self.hidden = {}
				self:apply_columns()
			end
		end)
		ui.menu.show(anchor)
	end

	function Table:drop_target(binding)"""),
]


def build():
    code = open(CORE, encoding="utf-8").read()
    m = re.match(r'\s*ui\.define\("core\.table", function\(\)\n(.*)\nend\)\s*$', code, re.S)
    if not m:
        raise SystemExit("Core/table.lua changed shape: no ui.define(\"core.table\", ...) wrapper")
    body = m.group(1)
    # The header loop in Table.create moves into Table:build_headers (below) so a column move
    # can rebuild the header in the new order; check the loop is still the shape we replace.
    start = '\t\tfor index, column in ipairs(self.columns) do\n\t\t\tassert(not (options.collection and column.kind == "custom")'
    end = '\t\tself:headings()\n\t\tif options.collection then'
    if body.count(start) != 1 or body.count(end) != 1:
        raise SystemExit("Core/table.lua changed upstream; header loop not found")
    loop = body[body.index(start):body.index(end) + len("\t\tself:headings()\n")]
    for needed in ("ui.shared_layout(style.header)", "self:sort_by(column.id)", "self:resize_column(index, initial + offset)",
                   "self:apply_width(index)"):
        if needed not in loop:
            raise SystemExit("Core/table.lua header loop changed upstream: " + needed)
    body = body.replace(loop, "\t\tself.saved_widths = saved\n\t\tself:order_columns()\n\t\tself:build_headers()\n")
    for old, new in PATCHES:
        if body.count(old) != 1:
            raise SystemExit("Core/table.lua changed upstream; patch anchor not found:\n" + old.splitlines()[0])
        body = body.replace(old, new)
    head = ("-- ndGUI: generated by ndgui/tools/lib_table.py from UI/Packages/Core/table.lua. Do not hand-edit.\n"
            "-- Adds hideable columns (right-click a header).\n")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "w", encoding="utf-8", newline="\n").write(head + body + "\n")


def repoint():
    n = 0
    for path in glob.glob(os.path.join(ADDONS, "ndgui-*", "*.lua")):
        code = open(path, encoding="utf-8").read()
        if OLD_REQ in code:
            open(path, "w", encoding="utf-8", newline="\n").write(code.replace(OLD_REQ, NEW_REQ))
            n += 1
    return n


if __name__ == "__main__":
    build()
    print(f"lib table written; {repoint()} packages repointed")
