local _, ns = ...

-------------------------------------------------------------------------------
-- Module Declaration
--

local plugin = BigWigs:NewPlugin("Transcriptor")
if not plugin then return end

-------------------------------------------------------------------------------
-- Locals
--

-- luacheck: globals Transcriptor TranscriptDB TranscriptIgnore
local ipairs, next, print, split, trim = ipairs, next, print, string.split, string.trim
local sort, concat, tremove, wipe = table.sort, table.concat, table.remove, table.wipe
local tonumber, ceil, floor = tonumber, math.ceil, math.floor

local logging = nil
local timer = nil

local temp = {}
local function quartiles(t)
	wipe(temp)
	for i = 1, #t do
		local v = tonumber(t[i])
		if v then
			temp[#temp+1] = v
		elseif t[i]:find("/", nil, true) then
			local _,v = split("/", t[i])
			v = tonumber(v)
			if v then
				temp[#temp+1] = v
			end
		end
	end
	sort(temp)
	local count = #temp

	-- stupid small data sets
	if count == 0 then
		return 0, 0, 0, 0, 0
	elseif count == 1 then
		local a = temp[1]
		return a, a, a, a, 1
	elseif count == 2 then
		local a, b = temp[1], temp[2]
		return a, b, a, b, 2
	end

	local q1, q3
	if count % 2 == 0 then -- should i average or just use the inner indexes?
		q1 = (temp[ceil(count / 4)] + temp[ceil(count / 4) + 1]) / 2
		q3 = (temp[floor(count * .75)] + temp[floor(count * .75) + 1]) / 2
	else
		q1 = temp[ceil(count / 4)]
		q3 = temp[ceil(count * .75)]
	end
	return q1, q3, temp[1], temp[count], count
end

local function isWin(log)
	local killed, encounter = nil, nil
	if log.COMBAT then
		-- should probably handle multiple encounters in one log, but meh
		for _, line in next, log.COMBAT do
			if line:find("ENCOUNTER_START", nil, true) then
				encounter = line:match("ENCOUNTER_START#%d+#(.-)#") -- "<61.75 21:43:59> [ENCOUNTER_START] ENCOUNTER_START#1954#Maiden of Virtue#23#5"
			elseif line:find("BOSS_KILL", nil, true) then
				encounter = line:match("#(.-)$") -- "<220.90 21:46:38> [BOSS_KILL] 1954#Maiden of Virtue"
				killed = true
				break
			end
		end
	end
	local duration = log.total and tonumber(log.total[#log.total]:match("^<(.-)%s")) or 0
	return killed, duration, encounter
end

local function parseLogName(logName)
	-- logNameFormat = "[date("%Y-%m-%d")]@[date("%H:%M:%S")] - %d/%d/%s/%s/%s@%s (version) (wowVersion.buildRevision)"
	local year, month, day, hour, min, sec, info = logName:match("^%[(%d+)-(%d+)-(%d+)%]@%[(%d+):(%d+):(%d+)%] %- (.+@[^ ]+)")
	if not info then return end
	local timestamp = time({day=day,month=month,year=year,hour=hour,min=min,sec=sec})

	return info, timestamp
end

-------------------------------------------------------------------------------
-- Locale
--

local L = setmetatable({}, { __newindex = function(t, k, v) rawset(t, k, v == true and k or v) end })
ns.L = L

L["Transcriptor"] = true
L["Automatically start Transcriptor logging when you pull a boss and stop when you win or wipe."] = true

L["Your Transcriptor DB has been reset! You can still view the contents of the DB in your SavedVariables folder until you exit the game or reload your UI."] = true
L["Transcriptor is currently using %.01f MB of memory. You should clear some logs or risk losing them."] = true
L["Log deleted."] = true

L["Raid only"] = true
L["Only enable logging while in a raid instance."] = true
L["Start with pull timer"] = true
L["Start Transcriptor logging from a pull timer at two seconds remaining."] = true
L["Show spell cast details"] = true
L["Include some spell stats and the time between casts in the log tooltip when available."] = true
L["Delete short logs"] = true
L["Automatically delete logs shorter than 30 seconds."] = true
L["Keep one log per fight"] = true
L["Only keep a log for the longest attempt or latest kill of an encounter."] = true
L["Stored logs (%s / %s) - Click to delete"] = true
L["No logs recorded"] = true
L["%d stored events over %.01f seconds. %s"] = true
L["Ignored Events"] = true
L["Clear All"] = true

L.win = "|cff20ff20%s " .. _G.WIN .. "|r"
L.failed = "|cffff2020%s " .. _G.FAILED .. "|r"

-------------------------------------------------------------------------------
-- Options
--

plugin.defaultDB = {
	enabled = false,
	onpull = false,
	details = false,
	delete = false,
	keepone = false,
	raid = false,
}

local GetOptions
do
	local function cmp(a, b) return a:match("%-(.*)") < b:match("%-(.*)") end
	local sorted = {}
	local timerEvents = {"SPELL_CAST_START", "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED"}

	local function GetDescription(info)
		local log = Transcriptor:Get(info.arg)
		if not log then return end

		local numEvents = log.total and #log.total or 0
		if numEvents == 0 then return end

		local killed, duration, encounter = isWin(log)
		local result = encounter and (killed and L.win:format(encounter) or L.failed:format(encounter)) or ""
		local desc = L["%d stored events over %.01f seconds. %s"]:format(numEvents, duration, result)
		if not log.TIMERS or not plugin.db.profile.details then
			return desc
		end

		desc = ("%s\n"):format(desc)
		for _, event in ipairs(timerEvents) do
			if log.TIMERS[event] then
				desc = ("%s\n%s\n"):format(desc, event)

				local spells = CopyTable(log.TIMERS[event])
				if spells[1] then
					-- un-funkify this shit (convert the new indexed table format back into a keyed table)
					for i = 1, #spells do
						local k, v = split("=", spells[i], 2)
						local spellName, spellId, npc = k:match("(.+)-(%d+)-(npc:%d+)") -- Armageddon-240910-npc:117269
						k = ("%s-%s-%s"):format(spellId, spellName, npc)                -- 240910-Armageddon-npc:117269
						spells[k] = v
						spells[i] = nil
					end
				end

				wipe(sorted)
				for spell in next, spells do sorted[#sorted + 1] = spell end
				sort(sorted, cmp)
				for _, spell in ipairs(sorted) do
					local spellId, spellName = split("-", spell, 2)
					local npc = spellName:match("-(npc:.+)")
					if npc then
						spellName = spellName:gsub("%-npc:.+$", "")
						npc = (" %s"):format(npc)
					end
					local values = {split(",", spells[spell])}
					local _, pull = split(":", tremove(values, 1))
					if #values == 0 then
						desc = ("%s|cfffed000%s (%d)%s|r | Count: |cff20ff20%d|r | From pull: |cff20ff20%.01f|r\n"):format(desc, spellName, spellId, npc or "", 1, pull)
					else
						-- use the lower and upper quartiles to find outliers
						local q1, q3, low, high, count = quartiles(values)
						if low == high then
							desc = ("%s|cfffed000%s (%d)%s|r | Count: |cff20ff20%d|r | From pull: |cff20ff20%.01f|r | CD: |cff20ff20%.01f|r\n"):format(desc, spellName, spellId, npc or "", count + 1, pull, low)
						else
							local iqr = q3 - q1
							local lower = q1 - (1.5 * iqr)
							local upper = q3 + (1.5 * iqr)
							local count, total = 0, 0
							for i = 1, #values do
								local v = tonumber(values[i])
								if not v then -- handle "stage" times
									if values[i+1] then
										local fromStage,fromLast = trim(values[i+1]):match("^(.+)/(.+)$")
										if fromLast then
											values[i] = ("|cffffff9a%s (+%s)|r"):format(values[i], fromStage)
											values[i+1] = fromLast
										end
									else
										values[i] = ("|cffffff9a%s|r"):format(values[i])
									end
								else
									if lower <= v and v <= upper then
										count = count + 1
										total = total + v
									else
										v = ("|cffff7f3f%s|r"):format(v) -- outlier
									end
									values[i] = v
								end
								if i % 24 == 0 then -- simple wrapping
									values[i] = ("\n    %s"):format(values[i])
								end
							end
							desc = ("%s|cfffed000%s (%d)|r | Count: |cff20ff20%d|r | Avg: |cff20ff20%.01f|r | Min: |cff20ff20%.01f|r | Max: |cff20ff20%.01f|r | From pull: |cff20ff20%.01f|r\n    %s\n"):format(desc, spellName, spellId, count + 1, total / count, low, high, pull, concat(values, ", "))
						end
					end
				end
			end
		end

		return desc
	end


	local options = nil

	function GetOptions()
		if not options then
			local events = {}
			for _, v in next, Transcriptor.events do
				events[v] = v
			end

			local function get(info)
				return plugin.db.profile[info[#info]]
			end
			local function set(info, value)
				plugin.db.profile[info[#info]] = value
			end

			options = {
				name = L["Transcriptor"],
				type = "group",
				args = {
					heading = {
						type = "description",
						name = L["Automatically start Transcriptor logging when you pull a boss and stop when you win or wipe."].."\n",
						fontSize = "medium",
						width = "full",
						order = 1,
					},
					enabled = {
						type = "toggle",
						name = ENABLE,
						get = function(info) return plugin.db.profile.enabled end,
						set = function(info, value)
							plugin.db.profile.enabled = value
							plugin:Disable()
							plugin:Enable()
						end,
						order = 2,
					},
					raid = {
						type = "toggle",
						name = L["Raid only"],
						desc = L["Only enable logging while in a raid instance."],
						get = get,
						set = set,
						order = 3,
					},
					onpull = {
						type = "toggle",
						name = L["Start with pull timer"],
						desc = L["Start Transcriptor logging from a pull timer at two seconds remaining."],
						get = function(info) return plugin.db.profile.onpull end,
						set = function(info, value)
							plugin.db.profile.onpull = value
							plugin:Disable()
							plugin:Enable()
						end,
						order = 4,
					},
					delete = {
						type = "toggle",
						name = L["Delete short logs"],
						desc = L["Automatically delete logs shorter than 30 seconds."],
						get = get,
						set = set,
						order = 5,
					},
					keepone = {
						type = "toggle",
						name = L["Keep one log per fight"],
						desc = L["Only keep a log for the longest attempt or latest kill of an encounter."],
						get = get,
						set = set,
						order = 6,
					},
					details = {
						type = "toggle",
						name = L["Show spell cast details"],
						desc = L["Include some spell stats and the time between casts in the log tooltip when available."],
						get = get,
						set = set,
						order = 7,
					},
					logs = {
						type = "group",
						inline = true,
						name = function()
							local count = 0
							for _ in next, Transcriptor:GetAll() do count = count + 1 end

							UpdateAddOnMemoryUsage()
							local mem = GetAddOnMemoryUsage("Transcriptor") / 1000
							mem = ("|cff%s%.01f MB|r"):format(mem > 60 and "ff2020" or "ffffff", mem)

							return L["Stored logs (%s / %s) - Click to delete"]:format(("|cffffffff%d|r"):format(count), mem)
						end,
						func = function(info)
							Transcriptor:Clear(info.arg)
							GameTooltip:Hide()
							collectgarbage()
						end,
						width = "full",
						order = 10,
						args = {},
					},
					ignoredEvents = {
						type = "multiselect",
						name = L["Ignored Events"],
						get = function(info, key) return TranscriptIgnore[key] end,
						set = function(info, key, value)
							TranscriptIgnore[key] = value or nil
						end,
						values = events,
						width = "double",
						order = 20,
					},
				},
			}
		end
		wipe(options.args.logs.args)

		local logs = Transcriptor:GetAll()
		for key, log in next, logs do
			options.args.logs.args[key] = {
				type = "execute",
				name = key,
				desc = GetDescription,
				arg = key,
				width = "full",
				disabled = InCombatLockdown,
			}
		end

		if next(logs) then
			options.args.logs.args["clear_all"] = {
				type = "execute",
				name = L["Clear All"],
				func = function()
					Transcriptor:ClearAll()
					GameTooltip:Hide()
					collectgarbage()
				end,
				width = "full",
				order = 0,
				disabled = InCombatLockdown,
			}
		else
			options.args.logs.args["no_logs"] = {
				type = "description",
				name = "\n"..L["No logs recorded"].."\n",
				fontSize = "medium",
				width = "full",
			}
		end

		return options
	end
end

plugin.subPanelOptions = {
	key = "BigWigs: Transcriptor",
	name = L["Transcriptor"],
	options = GetOptions,
}

-------------------------------------------------------------------------------
-- Initialization
--

local function Refresh()
	local ACR = LibStub("AceConfigRegistry-3.0", true)
	if ACR then -- make sure it's loaded (provided by BigWigs_Options)
		ACR:NotifyChange("BigWigs")
	end
end

function plugin:BigWigs_ProfileUpdate()
	self:Disable()
	self:Enable()
end

function plugin:OnPluginEnable()
	-- cleanup old savedvars
	self.db.profile.ignoredEvents = nil
	self.db.global.ignoredEvents = nil

	-- try to fix memory overflow error
	if Transcriptor and TranscriptDB == nil then
		print("\n|cffff2020" .. L["Your Transcriptor DB has been reset! You can still view the contents of the DB in your SavedVariables folder until you exit the game or reload your UI."])
		TranscriptDB = {}
	end

	self:RegisterMessage("BigWigs_ProfileUpdate")
	if self.db.profile.enabled then
		if self.db.profile.onpull then
			self:RegisterMessage("BigWigs_StartPull")
			self:RegisterMessage("BigWigs_StopPull")
		end
		self:RegisterEvent("ENCOUNTER_START")
		self:RegisterEvent("ENCOUNTER_END")
		-- catch fights that have a module but don't use ENCOUNTER events
		self:RegisterMessage("BigWigs_OnBossEngage")
		self:RegisterMessage("BigWigs_OnBossWin")
		self:RegisterMessage("BigWigs_OnBossWipe")
	end
	self:RegisterEvent("PLAYER_REGEN_DISABLED", Refresh)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", Refresh)
end

function plugin:OnPluginDisable()
	if logging then
		self:Stop()
	end
	timer = nil
end

SLASH_BigWigs_Transcriptor1 = "/bwts"
SlashCmdList.BigWigs_Transcriptor = function()
	LibStub("AceConfigDialog-3.0"):Open("BigWigs", "BigWigs: Transcriptor")
end

-------------------------------------------------------------------------------
-- Event Handlers
--

function plugin:BigWigs_StartPull(_, _, seconds)
	if seconds > 2 then
		self:CancelTimer(timer)
		timer = self:ScheduleTimer("Start", seconds-2)
	else
		self:Start()
	end
end

function plugin:BigWigs_StopPull()
	if timer then
		self:CancelTimer(timer)
		timer = nil
	end
end

function plugin:BigWigs_OnBossEngage(_, module, diff)
	if not module.engageId then
		self:Start()
	end
end

function plugin:BigWigs_OnBossWin(_, module)
	if not module.engageId then
		self:ScheduleTimer("Stop", 5) -- catch the end events
	end
end

function plugin:BigWigs_OnBossWipe(_, module)
	if not module.engageId then
		self:Stop()
	end
end

function plugin:ENCOUNTER_START(_, id, name, diff, size)
	-- XXX this will start logging dungeons and shit for people without little wigs
	self:Start()
end

function plugin:ENCOUNTER_END(_, id, name, diff, size, status)
	self:ScheduleTimer("Stop", 5) -- catch the end events
end

function plugin:Start()
	local _, instanceType = GetInstanceInfo()
	if instanceType ~= "raid" and self.db.profile.raid then return end

	if timer then
		self:CancelTimer(timer)
		timer = nil
	end
	-- stop your current log and start a new one
	if Transcriptor:IsLogging() and not logging then
		self:Stop(true)
	end
	if not Transcriptor:IsLogging() then
		Transcriptor:StartLog()
		logging = true
	end
end

function plugin:Stop(silent)
	logging = nil
	if not Transcriptor:IsLogging() then return end

	local logName = Transcriptor:StopLog()

	if self.db.profile.delete and logName then
		local log = Transcriptor:Get(logName)
		if #log.total == 0 or tonumber(log.total[#log.total]:match("^<(.-)%s")) < 30 then
			Transcriptor:Clear(logName)
			print("|cffff2020" .. L["Log deleted."])
			logName = nil
		end
	end

	if self.db.profile.keepone and logName then
		local log = Transcriptor:Get(logName)
		local encounter = parseLogName(logName)
		if isWin(log) then
			-- delete previous logs
			for name, log in next, Transcriptor:GetAll() do
				if name ~= logName and name:find(encounter, nil, true) then
					Transcriptor:Clear(logName)
				end
			end
		else
			-- keep the longest attempt or last kill
			local encounterLogs = {}
			local lastWin, lastWinTime = nil, nil
			local longLog, longLogTime = nil, nil
			for name, log in next, Transcriptor:GetAll() do
				local e, t = parseLogName(name)
				if e == encounter then
					encounterLogs[name] = true
					local k, d = isWin(log)
					if k and (not lastWin or t > lastWinTime) then
						lastWin = name
						lastWinTime = t
					end
					if not longLog or d > longLogTime then
						longLog = name
						longLogTime = d
					end
				end
			end
			local winner = lastWin or longLog
			for name in next, encounterLogs do
				if name ~= winner then
					Transcriptor:Clear(name)
				end
			end
		end
	end

	if not silent then
		-- check memory
		UpdateAddOnMemoryUsage()
		local mem = GetAddOnMemoryUsage("Transcriptor") / 1000
		if mem > 60 then
			print("\n|cffff2020" .. L["Transcriptor is currently using %.01f MB of memory. You should clear some logs or risk losing them."]:format(mem))
		end
	end
end
