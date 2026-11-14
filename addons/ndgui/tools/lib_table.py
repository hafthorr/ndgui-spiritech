"""Build ndgui-lib/lua/table.lua: Core's table.lua with movable columns, and hideable columns on every list.

Run from the ndgui folder:  python tools/lib_table.py
Since the Nov 2026 client, Core hides columns itself (<preference>.col_hidden, a Preferences array), but only
for tables that pass column_menu (Inventory, bank, bags). This build turns that on for every table and swaps
the stock header menu for ours: right-click any column header -> Move left / Move right / Reset column order,
then the columns (tick = shown) + "Show all columns". Order persists as <preference>.col_order; lists with
native rows (Inventory list, NCU) apply a new order the next time the window loads. At least one column always
stays visible; changes are refused in combat like resizing. Hidden ids saved by older ndGUI (",id,id," text)
are read once and rewritten in the stock format. Every ndgui-* package that used ui.require("core.table") is
pointed at ui.require("notum.ndgui-lib/table") (fork_windows.py / fork_hud.py do the same on regeneration).
Re-run after a client update.
"""
import glob, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ADDONS = os.path.normpath(os.path.join(HERE, "..", ".."))
CORE = os.path.normpath(os.path.join(ADDONS, "..", "Packages", "Core", "table.lua"))
OUT = os.path.join(ADDONS, "ndgui-lib", "lua", "table.lua")
OLD_REQ, NEW_REQ = 'ui.require("core.table")', 'ui.require("notum.ndgui-lib/table")'

PATCHES = [
    # every table loads its hidden columns (stock: only column_menu tables)
    ("""		if options.column_menu then
			local hidden = {}
			for _, id in ipairs(Preferences.read_array(self.preference .. ".col_hidden", "text")) do""",
     """		do
			local hidden = {}
			for _, id in ipairs(self:read_hidden()) do"""),
    # the column API (order, our header menu, hide/show for every table)
    ("""	function Table:drop_target(binding)""",
     """	-- Hidden ids: the stock Preferences array; older ndGUI saved ",id,id," text under the same key.
	function Table:read_hidden()
		local key = self.preference .. ".col_hidden"
		local ok, ids = pcall(Preferences.read_array, key, "text")
		if ok and type(ids) == "table" then
			return ids
		end
		local read_ok, text = pcall(ui.preference.read, key)
		ids = {}
		if read_ok and type(text) == "string" then
			for id in text:gmatch("[^,]+") do
				ids[#ids + 1] = id
			end
		end
		self.migrate_hidden = true
		return ids
	end

	function Table:write_hidden()
		local ids = {}
		for index, column in ipairs(self.columns) do
			if not self:shown(index) then
				ids[#ids + 1] = column.id
			end
		end
		pcall(Preferences.write_array, self.preference .. ".col_hidden", ids, "text")
	end

	function Table:apply_hidden()
		for index = 1, #self.columns do
			local shown = self:shown(index)
			if self.headers[index] then
				ui.visible(self.headers[index].root, shown)
			end
			for _, row in ipairs(self.rows) do
				if row.cells[index] then
					ui.visible(row.cells[index].root, shown)
				end
			end
			if self.prototype and self.prototype.cells[index] then
				ui.visible(self.prototype.cells[index].root, shown)
			end
		end
		if self.options.fit_columns and self.width then
			self:set_width(self.width)
		end
		for index = 1, #self.columns do
			self:apply_width(index)
		end
		self:write_hidden()
	end

	function Table:ndgui_toggle(index)
		if ui.in_combat() then
			return
		end
		local hiding = self:shown(index)
		if hiding and self:shown_count() <= 1 then
			return
		end
		self.hidden[self.columns[index].id] = hiding or nil
		self:apply_hidden()
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
			ui.visible(fragment, self:shown(index))
			ui.add(self.header, fragment)
			local id = column.id
			heading.id = id
			ui.on_pointer_release(heading.title, "right", function()
				self:ndgui_column_menu(heading.title, id)
			end)
			if column.value then
				ui.on_click(heading.title, function()
					self:sort_by(id)
				end)
			end
			local resizable = column.resizable ~= false
			-- the bar also separates fixed columns (icons) from their neighbour; only resizable ones drag
			ui.visible(heading.divider, true)
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
		if self.migrate_hidden then
			self.migrate_hidden = nil
			self:write_hidden()
		end
	end

	-- Rebuild header and rows in the current self.columns order (package-owned rows only;
	-- native collection rows are cloned from a prototype once, so those apply on next load).
	function Table:rebuild()
		-- widths belong to the column each header was built for, not to the (possibly re-ordered) slot
		for index, heading in ipairs(self.headers) do
			if self.preferred_widths[index] then
				self.saved_widths[heading.id] = self.preferred_widths[index]
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

	function Table:ndgui_column_menu(anchor, id)
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
		-- titled columns only: the stock loader ignores hidden untitled (icon) columns
		for index, column in ipairs(self.columns) do
			if column.title ~= "" then
				ui.menu.add(anchor, column.title, self:shown(index), function()
					self:ndgui_toggle(index)
				end)
			end
		end
		ui.menu.separator(anchor)
		ui.menu.add(anchor, "Show all columns", false, function()
			if not ui.in_combat() then
				self.hidden = {}
				self:apply_hidden()
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
            "-- Movable columns, and hideable columns on every table (right-click a header).\n")
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
