-- What the chat VM learns from chat lines (no presentation, no host calls: tested offline).
--
-- Sniff.new() -> s;  s.read(message, context) -> list of { topic, fields } for the bus:
--   alert  tells to you, your name said by someone else, a watch word      {k, who, text, id}
--   locks  the Raid window's "Raid Locks" answer (header line + the lines after it)  {text, id}
--   loot   "You received <item>" style lines (not credits / XP / points)   {item, id}
--   cmd    "ndgui <command> [args]" typed where only you see it            {c, a, id}
-- context = { self_name = "Bob", words = { "omni-med", ... } (lower case), now = ms }
-- message = the client's ChatMessage (kind, sender, channel, body, sent, time_ms, structured).
ui.define("intel.sniff", function()
	local S = {}

	S.LOCKS_FOLLOW_MS = 2500 -- lines arriving this soon after "Raid locks:" belong to the list
	local NOT_LOOT = { "credit", "xp", "experience", "point", "damage", "health", "nano", "heal" }

	local function lower(text)
		return string.lower(text or "")
	end

	local function trim(text)
		return ((text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
	end

	-- a whole word, any case: "bob" in "hey Bob!" but not in "bobcat"
	function S.has_word(text, word)
		if not word or word == "" then
			return false
		end
		local escaped = word:gsub("(%W)", "%%%1")
		return lower(text):find("%f[%w]" .. lower(escaped) .. "%f[^%w]") ~= nil
	end

	function S.loot_item(body)
		body = trim(body)
		local item = body:match("^You received (.+)$") or body:match("^You looted (.+)$")
			or body:match("^You picked up (.+)$") or body:match("^You obtained (.+)$")
			or body:match("^You got (.+)$") or body:match("^(.+) was added to your inventory")
		if not item then
			return nil
		end
		item = item:gsub("[%.!]+$", "")
		local check = lower(item)
		for _, word in ipairs(NOT_LOOT) do
			if check:find(word, 1, true) then
				return nil
			end
		end
		if item == "" or #item > 120 then
			return nil
		end
		return item
	end

	-- "ndgui alts", "/ndgui watch omni-med"; also inside a longer local notice ("Unknown command: /ndgui alts")
	function S.command(body)
		local text = lower(body)
		local rest = text:match("^%s*/?ndgui%s+(.+)$") or text:match("[%s:'\"/]ndgui%s+(.+)$")
		if not rest then
			return nil
		end
		rest = trim(rest:gsub("[%.'\"]+$", ""))
		local command, args = rest:match("^(%a+)%s*(.*)$")
		if not command then
			return nil
		end
		return command, trim(args)
	end

	local function message_id(message)
		local body = message.body or ""
		return table.concat({ tostring(message.time_ms or 0), message.kind or "", message.sender or "", tostring(#body),
			body:sub(1, 24) }, ":")
	end

	function S.new()
		local s = { locks = nil }

		function s.read(message, context)
			local out = {}
			local body = message.body or ""
			local kind = message.kind or ""
			local now = context.now or message.time_ms or 0
			local id = message_id(message)
			local mine = message.sent or (context.self_name and message.sender == context.self_name)
			local notice = kind == "system" or kind == "local" or not message.structured

			-- commands: typed where nobody else reads them (a local notice, or a tell you sent)
			if notice or (kind == "tell" and message.sent) then
				local command, args = S.command(body)
				if command then
					out[#out + 1] = { "cmd", { c = command, a = args, id = id } }
					return out
				end
			end

			-- raid locks: "Raid locks:" / "No raid locks." and the lines right after it
			local header = trim(body)
			if notice and (header:find("^Raid locks:") or header == "No raid locks.") then
				s.locks = { text = header, at = now, id = id }
				out[#out + 1] = { "locks", { text = s.locks.text, id = s.locks.id } }
				return out
			elseif notice and s.locks and now - s.locks.at <= S.LOCKS_FOLLOW_MS and header ~= "" then
				s.locks.text = s.locks.text .. "\n" .. header
				s.locks.at = now
				s.locks.lines = (s.locks.lines or 1) + 1
				-- a new id per version: the HUD drops ids it has seen (several chat windows send the same)
				out[#out + 1] = { "locks", { text = s.locks.text, id = s.locks.id .. "+" .. s.locks.lines } }
				return out
			end

			if notice then
				local item = S.loot_item(body)
				if item then
					out[#out + 1] = { "loot", { item = item, id = id } }
				end
				return out
			end
			if mine then
				return out
			end

			local who = message.sender or ""
			if kind == "tell" then
				out[#out + 1] = { "alert", { k = "tell", who = who, text = body:sub(1, 240), id = id } }
				return out
			end
			local first = context.self_name and context.self_name:match("^(%S+)")
			if first and #first >= 3 and S.has_word(body, first) then
				out[#out + 1] = { "alert", { k = "name", who = who, ch = message.channel or "", text = body:sub(1, 240), id = id } }
				return out
			end
			for _, word in ipairs(context.words or {}) do
				if S.has_word(body, word) then
					out[#out + 1] = { "alert", { k = "word", w = word, who = who, ch = message.channel or "", text = body:sub(1, 240), id = id } }
					return out
				end
			end
			return out
		end

		return s
	end

	return S
end)
