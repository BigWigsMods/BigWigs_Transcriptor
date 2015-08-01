
local _, scope = ...

-------------------------------------------------------------------------------
-- Module Declaration
--

local plugin = BigWigs:NewPlugin("Transcriptor")
if not plugin then return end

-------------------------------------------------------------------------------
-- Locals
--

local ipairs, next, print, split = ipairs, next, print, string.split
local sort, concat, tremove, wipe = table.sort, table.concat, table.remove, table.wipe
local tonumber, ceil, floor = tonumber, math.ceil, math.floor
local huge = math.huge

local events = nil
local logging = nil
local timer = nil

local temp = {}
local function quartiles(t)
	wipe(temp)
	for i = 1, #t do
		temp[i] = tonumber(t[i])
	end
	sort(temp)
	local count = #temp

	-- stupid small data sets
	if count == 0 then
		return 0, 0
	elseif count == 1 then
		return temp[1], temp[1]
	elseif count == 2 then
		return temp[1], temp[2]
	end

	local q1, q3
	if count % 2 == 0 then -- should i average or just use the inner indexes?
		q1 = (temp[ceil(count / 4)] + temp[ceil(count / 4) + 1]) / 2
		q3 = (temp[floor(count * .75)] + temp[floor(count * .75) + 1]) / 2
	else
		q1 = temp[ceil(count / 4)]
		q3 = temp[ceil(count * .75)]
	end
	return q1, q3
end

-- GLOBALS: ENABLE GameTooltip InterfaceOptionsFrame_OpenToCategory LibStub SLASH_BigWigs_Transcriptor1 Transcriptor TranscriptDB
-- GLOBALS: UpdateAddOnMemoryUsage GetAddOnMemoryUsage InCombatLockdown collectgarbage
-------------------------------------------------------------------------------
-- Locale
--

local L = LibStub("AceLocale-3.0"):NewLocale("Big Wigs: Transcriptor", "enUS", true)
L["Transcriptor"] = true
L["Automatically start Transcriptor logging when you pull a boss and stop when you win or wipe."] = true

L["Your Transcriptor DB has been reset! You can still view the contents of the DB in your SavedVariables folder until you exit the game or reload your UI."] = true
L["Transcriptor is currently using %.01f MB of memory. You should clear some logs or risk losing them."] = true
L["Log deleted."] = true

L["Start with pull timer"] = true
L["Start Transcriptor logging from a pull timer at two seconds remaining."] = true
L["Show spell cast details"] = true
L["Include some spell stats and the time between casts in the log tooltip when available."] = true
L["Delete short logs"] = true
L["Automatically delete logs shorter than 30 seconds."] = true
L["Stored logs (%s) - Click to delete"] = true
L["No logs recorded"] = true
L["%d stored events over %.01f seconds. %s"] = true
L["|cff20ff20Win!|r"] = true
L["Ignored Events"] = true
L["Clear All"] = true

L = LibStub("AceLocale-3.0"):GetLocale("Big Wigs: Transcriptor")

-------------------------------------------------------------------------------
-- Options
--

plugin.defaultDB = {
	enabled = false,
	onpull = false,
	details = false,
	delete = false,
}

local function cmp(a, b) return a:match("%-(.*)") < b:match("%-(.*)") end
local sorted = {}

local function GetOptions()
	local logs = Transcriptor:GetAll()

	if not events then
		events = {}
		for i,v in ipairs(Transcriptor.events) do
			events[v] = v
		end
	end

	UpdateAddOnMemoryUsage()
	local mem = GetAddOnMemoryUsage("Transcriptor") / 1000
	mem = ("|cff%s%.01f MB|r"):format(mem > 60 and "ff2020" or "ffffff", mem)

	local options = {
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
				order = 3,
			},
			delete = {
				type = "toggle",
				name = L["Delete short logs"],
				desc = L["Automatically delete logs shorter than 30 seconds."],
				get = function(info) return plugin.db.profile.delete end,
				set = function(info, value) plugin.db.profile.delete = value end,
				order = 4,
			},
			details = {
				type = "toggle",
				name = L["Show spell cast details"],
				desc = L["Include some spell stats and the time between casts in the log tooltip when available."],
				get = function(info) return plugin.db.profile.details end,
				set = function(info, value) plugin.db.profile.details = value end,
				order = 5,
			},
			logs = {
				type = "group",
				inline = true,
				name = L["Stored logs (%s) - Click to delete"]:format(mem),
				func = function(info)
					Transcriptor:Clear(info.arg)
					GameTooltip:Hide()
					collectgarbage()
				end,
				order = 10,
				width = "full",
				args = {},
			},
			ignoredEvents = {
				type = "multiselect",
				name = L["Ignored Events"],
				get = function(info, key) return TranscriptDB.ignoredEvents[key] end,
				set = function(info, key, value)
					local value = value or nil
					TranscriptDB.ignoredEvents[key] = value
					plugin.db.global.ignoredEvents[key] = value
				end,
				values = events,
				order = 20,
				width = "double",
			},
		},
	}

	for key, log in next, logs do
		if key ~= "ignoredEvents" then
			local desc = nil
			local count = #log.total
			if count > 0 then
				desc = L["%d stored events over %.01f seconds. %s"]:format(count, log.total[count]:match("^<(.-)%s"), log.BOSS_KILL and L["|cff20ff20Win!|r"] or "")
				if plugin.db.profile.details and log.TIMERS then
					desc = ("%s\n"):format(desc)
					for _, event in ipairs{"SPELL_CAST_START", "SPELL_CAST_SUCCESS"} do
						local spells = log.TIMERS[event]
						if spells then
							desc = ("%s\n%s\n"):format(desc, event)
							wipe(sorted)
							for spell in next, spells do sorted[#sorted + 1] = spell end
							sort(sorted, cmp)
							for _, spell in ipairs(sorted) do
								local spellId, spellName = split("-", spell, 2)
								local values = {split(",", spells[spell])}
								local _, pull = split(":", tremove(values, 1))
								if #values == 0 then
									desc = ("%s|cfffed000%s (%d)|r | Count: |cff20ff20%d|r | From pull: |cff20ff20%.01f|r\n"):format(desc, spellName, spellId, 1, pull)
								else
									-- use the lower and upper quartiles to find outliers
									local q1, q3 = quartiles(values)
									local iqr = q3 - q1
									local lower = q1 - (1.5 * iqr)
									local upper = q3 + (1.5 * iqr)
									local count, total, low, high = 0, 0, huge, 0
									for i = 1, #values do
										values[i] = tonumber(values[i])
										local v = values[i]
										if lower <= v and v <= upper then
											count = count + 1
											total = total + v
											if v < low then low = v end
											if v > high then high = v end
										else
											values[i] = ("|cffff7f3f%s|r"):format(v) -- outlier
										end
										if i % 24 == 0 then -- simple wrapping
												values[i] = ("\n    %s"):format(values[i])
										end
									end
									if low == high then
										desc = ("%s|cfffed000%s (%d)|r | Count: |cff20ff20%d|r | From pull: |cff20ff20%.01f|r | CD: |cff20ff20%.01f|r\n"):format(desc, spellName, spellId, #values + 1, pull, low)
									else
										desc = ("%s|cfffed000%s (%d)|r | Count: |cff20ff20%d|r | Avg: |cff20ff20%.01f|r | Min: |cff20ff20%.01f|r | Max: |cff20ff20%.01f|r | From pull: |cff20ff20%.01f|r\n    %s\n"):format(desc, spellName, spellId, #values + 1, total / count, low, high, pull, concat(values, ", "))
									end
								end
							end
						end
					end
				end
			end
			options.args.logs.args[key] = {
				type = "execute",
				name = key,
				desc = desc,
				width = "full",
				arg = key,
				disabled = InCombatLockdown,
			}
		end
	end
	if not next(options.args.logs.args) then
		options.args.logs.args["no_logs"] = {
			type = "description",
			name = "\n"..L["No logs recorded"].."\n",
			fontSize = "medium",
			width = "full",
		}
	else
		options.args.logs.args["clear_all"] = {
				type = "execute",
				name = L["Clear All"],
				width = "full",
				func = function()
					Transcriptor:ClearAll()
					GameTooltip:Hide()
					collectgarbage()
				end,
				disabled = InCombatLockdown,
				order = 0,
			}
	end

	return options
end

plugin.subPanelOptions = {
	key = "Big Wigs: Transcriptor",
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
	-- can't set a default global table as a plugin :(
	if not self.db.global.ignoredEvents then
		self.db.global.ignoredEvents = {}
	end
	-- cleanup old savedvars
	if self.db.profile.ignoredEvents then
		for k, v in next, self.db.profile.ignoredEvents do
			self.db.global.ignoredEvents[k] = v
		end
		self.db.profile.ignoredEvents = nil
	end

	-- try to fix memory overflow error
	if Transcriptor and TranscriptDB == nil then
		print("\n|cffff2020" .. L["Your Transcriptor DB has been reset! You can still view the contents of the DB in your SavedVariables folder until you exit the game or reload your UI."])
		TranscriptDB = { ignoredEvents = {} }
		for k, v in next, self.db.global.ignoredEvents do
			TranscriptDB.ignoredEvents[k] = v
		end
	elseif not TranscriptDB.ignoredEvents then
		TranscriptDB.ignoredEvents = {}
	end

	self:RegisterMessage("BigWigs_ProfileUpdate")
	if self.db.profile.enabled then
		if self.db.profile.onpull then
			self:RegisterMessage("BigWigs_StartPull")
			self:RegisterMessage("BigWigs_StopPull")
		end
		self:RegisterMessage("BigWigs_OnBossEngage", "Start")
		self:RegisterMessage("BigWigs_OnBossWin") -- delayed Stop
		self:RegisterMessage("BigWigs_OnBossWipe", "Stop")
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
	LibStub("AceConfigDialog-3.0"):Open("BigWigs", "Big Wigs: Transcriptor")
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

function plugin:Start()
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

function plugin:BigWigs_OnBossWin()
	-- catch the end events
	self:ScheduleTimer("Stop", 5)
end

function plugin:Stop(silent)
	logging = nil
	if Transcriptor:IsLogging() then
		local logName = Transcriptor:StopLog()
		if self.db.profile.delete and logName then
			local log = Transcriptor:Get(logName)
			if #log.total == 0 or tonumber(log.total[#log.total]:match("^<(.-)%s")) < 30 then
				Transcriptor:Clear(logName)
				print("|cffff2020" .. L["Log deleted."])
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
end

