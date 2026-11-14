-- Mission briefs shared between the Info, Missions and Mission Terminal windows of one package
-- (ndgui-mission-hub). The client only hands a mission's briefing to the Info window (Look at
-- mission / Ctrl-click an offer); Info captures the page here and the other windows show it.
-- Stored in ui.storage (per package, shared by every character), keyed by the mission title, which
-- is the same (shortened) title the Missions list and the terminal offers show.
local B = {}

local PREFIX, INDEX, SEQ = "brief:", "brief_index", "brief_seq"
local KEEP = 80 -- briefs remembered
local US = string.char(31) -- field separator
local EQ = string.char(30) -- key/value separator

local function read(key)
	local ok, value = pcall(function() return ui.storage.read(key) end)
	return ok and type(value) == "string" and value or ""
end

local function write(key, value)
	pcall(function() ui.storage.write(key, value) end)
end

local function trim(text)
	return ((text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function number(text)
	local digits = (text or ""):gsub(",", "")
	return tonumber(digits)
end

-- Best guess at where a mission sends you: the last "in <Capitalised Words>" of the briefing,
-- e.g. "...the target is in RomeBlue, in a place called the Rome house." -> "RomeBlue".
local SKIP = { The = true, A = true, An = true, This = true, That = true, Your = true, Our = true, Their = true }
function B.zone(text)
	text = text or ""
	local best
	for start in text:gmatch("()[Ii]n ") do
		local rest = text:sub(start + 3)
		local words = {}
		for word in rest:gmatch("%S+") do
			local clean = word:gsub("[%.,;:!%?%)]+$", "")
			if not clean:match("^%u") or SKIP[clean] then
				break
			end
			words[#words + 1] = clean
			if clean ~= word or #words >= 3 then
				break
			end
		end
		if #words > 0 then
			best = table.concat(words, " ")
		end
	end
	return best
end

-- Parse an Info page (InfoLine[]) into a brief, or nil when it is not a mission page.
-- Mission pages: a title line, "Description:", the briefing, "Reward:", "Cash: N credits",
-- "Experience: (Up to) N XP.", "Item reward:" and the item.
function B.capture(lines)
	if type(lines) ~= "table" or #lines == 0 then
		return nil
	end
	local brief = { title = nil, text = {}, cash = nil, xp = nil, item = nil, icon = 0, time = nil }
	local section
	local is_mission = false
	for _, line in ipairs(lines) do
		local text = trim(line.text)
		if not brief.title and line.tone == "title" and text ~= "" then
			brief.title = text
		elseif text:match("^Description:?$") then
			section, is_mission = "description", true
		elseif text:match("^Reward:?$") then
			section, is_mission = "reward", true
		elseif text:match("^Item reward:?$") then
			section = "item"
		elseif text:match("^Cash:") then
			brief.cash = number(text:match("([%d,]+)"))
		elseif text:match("^Experience:") then
			brief.xp = number(text:match("([%d,]+)%s*XP")) or number(text:match("([%d,]+)"))
		elseif text:match("^Realtime left:") then
			brief.time = trim(text:match("^Realtime left:%s*(.-)%.?$"))
		elseif line.item and section == "item" and not brief.item then
			brief.item = text ~= "" and text or "Item"
			brief.icon = tonumber(line.icon) or 0
		elseif section == "description" and text ~= "" then
			brief.text[#brief.text + 1] = text
		end
	end
	if not is_mission or not brief.title then
		return nil
	end
	brief.text = table.concat(brief.text, " ")
	brief.zone = B.zone(brief.text)
	return brief
end

local function encode(brief)
	local parts = {}
	for _, key in ipairs({ "title", "text", "cash", "xp", "item", "icon", "time", "zone" }) do
		local value = brief[key]
		if value ~= nil and value ~= "" then
			parts[#parts + 1] = key .. EQ .. tostring(value):gsub("[" .. US .. EQ .. "]", " ")
		end
	end
	return table.concat(parts, US)
end

local function decode(text)
	if text == "" then
		return nil
	end
	local brief = {}
	for part in (text .. US):gmatch("(.-)" .. US) do
		local key, value = part:match("^(.-)" .. EQ .. "(.*)$")
		if key then
			brief[key] = value
		end
	end
	brief.cash, brief.xp, brief.icon = tonumber(brief.cash), tonumber(brief.xp), tonumber(brief.icon) or 0
	return brief.title and brief or nil
end

function B.save(brief)
	if not brief or not brief.title then
		return
	end
	write(PREFIX .. brief.title, encode(brief))
	-- remember the order, forget the oldest
	local titles = {}
	for title in (read(INDEX) .. US):gmatch("(.-)" .. US) do
		if title ~= "" and title ~= brief.title then
			titles[#titles + 1] = title
		end
	end
	titles[#titles + 1] = brief.title
	while #titles > KEEP do
		write(PREFIX .. table.remove(titles, 1), "")
	end
	write(INDEX, table.concat(titles, US))
	write(SEQ, tostring((tonumber(read(SEQ)) or 0) + 1))
end

function B.load(title)
	if not title or title == "" then
		return nil
	end
	return decode(read(PREFIX .. title))
end

-- Titles are shortened in places ("Mission Assignment MXIL: The..."), so compare loosely: drop a
-- trailing "...", an "Assignment XXXX:" style prefix, case and spacing; one may be a prefix of the other.
local function norm(title)
	local t = string.lower(trim(title)):gsub("%.%.%.$", ""):gsub("…$", "")
	t = t:gsub("^mission assignment%s+%w+:%s*", "")
	return trim((t:gsub("%s+", " ")))
end

local function same(a, b)
	if a == "" or b == "" then
		return false
	end
	local short, long = a, b
	if #short > #long then
		short, long = long, short
	end
	return #short >= 6 and long:sub(1, #short) == short
end

-- The brief for a title as the Missions list or a terminal offer shows it, or nil.
function B.find(title)
	local exact = B.load(title)
	if exact then
		return exact
	end
	local want = norm(title)
	local found
	for stored in (read(INDEX) .. US):gmatch("(.-)" .. US) do
		if stored ~= "" and same(norm(stored), want) then
			found = stored -- newest wins (the index is oldest first)
		end
	end
	return found and B.load(found) or nil
end

-- Changes whenever Info saves a brief: poll it to refresh.
function B.revision()
	return read(SEQ)
end

local function thousands(n)
	local digits = tostring(math.floor(n))
	return (digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end
B.thousands = thousands

-- "1,986 credits · 365 XP · RomeBlue"
function B.summary(brief, with_zone)
	if not brief then
		return ""
	end
	local parts = {}
	if brief.cash then parts[#parts + 1] = thousands(brief.cash) .. " credits" end
	if brief.xp then parts[#parts + 1] = thousands(brief.xp) .. " XP" end
	if with_zone ~= false and brief.zone then parts[#parts + 1] = brief.zone end
	return table.concat(parts, "  ·  ")
end

-- All searchable text of a brief (watch list matching).
function B.haystack(brief)
	if not brief then
		return ""
	end
	return table.concat({ brief.title or "", brief.text or "", brief.item or "", brief.zone or "" }, " ")
end

return B
