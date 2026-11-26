-- A message bus between the VMs of ONE package, over that package's ui.storage.
--
-- The client runs each role of a multi-role package in its own Lua VM (ndgui-intel: chat, floating
-- combat text, zone notice; ndgui-mission-hub: Info, Missions, Mission Terminal). The VMs share
-- nothing in Lua, but they share the package's storage, and storage reads/writes are synchronous
-- host calls on the UI thread. So one VM can write and another read in its next update:
--
--   events  Bus.publish(topic, fields)      append to a ring of RING records
--           local r = Bus.reader()          a cursor that starts at "now" (no replay of old sessions)
--           r.poll(function(topic, fields, seq) ... end)
--   state   Bus.set(key, text) / Bus.get(key)   last value wins (positions, settings, records)
--   lease   Bus.lease(name, owner, now, ttl)    one VM holds it while it keeps renewing within ttl ms
--
-- Fields are a flat table of text; encode/decode drop the two separator bytes from values.
-- Storage is per installation (every character on this machine), 4096 bytes per value, so events
-- are capped at MAX bytes and older events are overwritten.
local B = {}

local US, RS = string.char(31), string.char(30) -- record / field separators
local RING = 96
local MAX = 3800
B.RING, B.MAX = RING, MAX

local function read(key)
	local ok, value = pcall(ui.storage.read, key)
	if ok and type(value) == "string" then
		return value
	end
	return ""
end

local function write(key, value)
	return (pcall(ui.storage.write, key, value))
end

B.read, B.write = read, write

local function clean(value)
	return (tostring(value):gsub("[" .. US .. RS .. "]", " "))
end

-- {a="1", b="x"} -> "a<RS>1<US>b<RS>x" (sorted, so equal tables encode equally)
function B.encode(fields)
	local parts = {}
	for key, value in pairs(fields or {}) do
		parts[#parts + 1] = clean(key) .. RS .. clean(value)
	end
	table.sort(parts)
	return table.concat(parts, US)
end

function B.decode(text)
	local fields = {}
	for item in (text or ""):gmatch("[^" .. US .. "]+") do
		local key, value = item:match("^(.-)" .. RS .. "(.*)$")
		if key then
			fields[key] = value
		end
	end
	return fields
end

local function top()
	return tonumber(read("bus:seq")) or 0
end

function B.publish(topic, fields)
	local seq = top() + 1
	local payload = B.encode(fields)
	if #payload > MAX then
		payload = payload:sub(1, MAX)
	end
	write("bus:" .. (seq % RING), seq .. US .. clean(topic) .. US .. payload)
	write("bus:seq", tostring(seq))
	return seq
end

local RECORD = "^(%d+)" .. US .. "([^" .. US .. "]*)" .. US .. "(.*)$"

-- options.replay = n: also deliver up to the last n events already on the bus
function B.reader(options)
	local r = { last = top() }
	if options and options.replay then
		r.last = math.max(0, r.last - math.min(options.replay, RING))
	end
	function r.poll(handler)
		local now_top = top()
		if now_top < r.last then
			r.last = now_top -- storage was cleared
		end
		if now_top - r.last > RING then
			r.last = now_top - RING -- fell behind: the oldest ones are gone
		end
		for seq = r.last + 1, now_top do
			local s, topic, payload = read("bus:" .. (seq % RING)):match(RECORD)
			if tonumber(s) == seq then
				handler(topic, B.decode(payload), seq)
			end
		end
		r.last = now_top
	end
	return r
end

function B.get(key)
	return read("st:" .. key)
end

function B.set(key, value)
	if B.get(key) ~= value then
		write("st:" .. key, value or "")
	end
end

-- true while `owner` holds lease `name`: free, stale (not renewed within ttl ms) or already ours
function B.lease(name, owner, now, ttl)
	local who, at = read("lease:" .. name):match("^(.-)" .. US .. "(%d+)$")
	at = tonumber(at)
	if who == nil or who == owner or at == nil or now - at > ttl or at > now + ttl then
		write("lease:" .. name, owner .. US .. math.floor(now))
		return true
	end
	return false
end

function B.release(name, owner)
	local who = read("lease:" .. name):match("^(.-)" .. US)
	if who == owner then
		write("lease:" .. name, "")
	end
end

-- short stable hash for storage keys (keys are limited to 128 bytes)
function B.hash(text)
	local h1, h2 = 5381, 52711
	for i = 1, #text do
		local c = text:byte(i)
		h1 = (h1 * 33 + c) % 4294967296
		h2 = (h2 * 31 + c) % 4294967296
	end
	return string.format("%08x%08x", h1, h2)
end

return B
