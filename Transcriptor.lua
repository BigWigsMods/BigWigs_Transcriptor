local ADDON_NAME = ...

-------------------------------------------------------------------------------
-- Module Declaration
--

local plugin = BigWigs:NewPlugin("Transcriptor")
if not plugin then return end

-------------------------------------------------------------------------------
-- Locals
--

local logging = nil
local events = {
	"PLAYER_REGEN_DISABLED",
	"PLAYER_REGEN_ENABLED",
	"CHAT_MSG_MONSTER_EMOTE",
	"CHAT_MSG_MONSTER_SAY",
	"CHAT_MSG_MONSTER_WHISPER",
	"CHAT_MSG_MONSTER_YELL",
	"CHAT_MSG_RAID_WARNING",
	"CHAT_MSG_RAID_BOSS_EMOTE",
	"RAID_BOSS_EMOTE",
	"RAID_BOSS_WHISPER",
	"PLAYER_TARGET_CHANGED",
	"UNIT_SPELLCAST_START",
	"UNIT_SPELLCAST_STOP",
	"UNIT_SPELLCAST_SUCCEEDED",
	"UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_CHANNEL_START",
	"UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_POWER",
	"UPDATE_WORLD_STATES",
	"WORLD_STATE_UI_TIMER_UPDATE",
	"COMBAT_LOG_EVENT_UNFILTERED",
	"INSTANCE_ENCOUNTER_ENGAGE_UNIT",
	"BigWigs_Message",
	"BigWigs_StartBar",
	--"BigWigs_Debug",
}
for i,v in ipairs(events) do
	events[v] = v
	events[i] = nil
end

-------------------------------------------------------------------------------
-- Locale
--

local L = LibStub("AceLocale-3.0"):NewLocale("Big Wigs: Transcriptor", "enUS", true)
if L then
	L["Transcriptor"] = true
	L["Automatically start Transcriptor logging when you pull a boss and stop when you win or wipe."] = true

	L["Your Transcriptor DB has been reset! You can still view the contents of the DB in your SavedVariables folder until you exit the game or reload your ui."] = true
	L["Disabling auto-logging because Transcriptor is currently using %.01f MB of memory. Clear some logs before re-enabling."] = true

	L["Enable for LFR"] = true
	L["Stored logs - Click to delete"] = true
	L["No logs recorded"] = true
	L["%d stored events over %.01f seconds."] = true
	L["|cff20ff20Win!|r "] = true
	L["Ignored Events"] = true
end
L = LibStub("AceLocale-3.0"):GetLocale("Big Wigs: Transcriptor")

-------------------------------------------------------------------------------
-- Options
--

plugin.defaultDB = {
	enabled = false,
	enabledLFR = false,
	ignoredEvents = {}
}

local function GetOptions()
	local logs = Transcriptor:GetAll()

	local options = {
		name = L["Transcriptor"],
		type = "group",
		get = function(info) return plugin.db.profile[info[#info]] end,
		set = function(info, value) plugin.db.profile[info[#info]] = value end,
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
				set = function(info, value)
					plugin.db.profile[info[#info]] = value
					plugin:Disable()
					plugin:Enable()
				end,
				order = 2,
			},
			enabledLFR = {
				type = "toggle",
				name = L["Enable for LFR"],
				set = function(info, value)
					plugin.db.profile[info[#info]] = value
					plugin:Disable()
					plugin:Enable()
				end,
				disabled = function() return not plugin.db.profile.enabled end,
				order = 3,
			},
			logs = {
				type = "group",
				inline = true,
				name = L["Stored logs - Click to delete"],
				func = function(info) logs[info[#info]] = nil end,
				order = 10,
				width = "full",
				args = {},
			},
			ignoredEvents = {
				type = "multiselect",
				name = L["Ignored Events"],
				get = function(info, key) return TranscriptDB.ignoredEvents[key] end,
				set = function(info, value) TranscriptDB.ignoredEvents[value] = not TranscriptDB.ignoredEvents[value] or nil end,
				values = events,
				order = 20,
				width = "full",
			},
		},
	}

	for key, log in next, logs do
		if key ~= "ignoredEvents" then
			local desc = nil
			local count = log.total and #log.total or 0
			if count > 0 then
				desc = L["%d stored events over %.01f seconds."]:format(count, log.total[count]:match("^<(.-)%s"))
				if log.BigWigs_Message and log.BigWigs_Message[#log.BigWigs_Message]:find("bosskill", nil, true) then
					desc = L["|cff20ff20Win!|r "]..desc
				end
			end
			options.args.logs.args[key] = {
				type = "execute",
				name = key,
				desc = desc,
				width = "full",
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

function plugin:Print(...)
	print("|cffffff00", ...)
end

function plugin:OnPluginEnable()
	if Transcriptor and TranscriptDB == nil then -- try to fix memory overflow error
		self:Print(L["Your Transcriptor DB has been reset! You can still view the contents of the DB in your SavedVariables folder until you exit the game or reload your ui."])
		TranscriptDB = { ignoredEvents = {} }
		for k, v in next, self.db.profile.ignoredEvents do
			TranscriptDB.ignoredEvents[k] = v
		end
	elseif not TranscriptDB.ignoredEvents then
		TranscriptDB.ignoredEvents = {}
	end

	if self.db.profile.enabled then
		if BigWigs then
			self:RegisterMessage("BigWigs_OnBossEngage", "Start")
			self:RegisterMessage("BigWigs_OnBossWin", "Stop")
			self:RegisterMessage("BigWigs_OnBossWipe", "Stop")
		end
	end
end

function plugin:OnPluginDisable()
	if logging and Transcriptor:IsLogging() then
		Transcriptor:StopLog()
	end
	logging = nil
end

-------------------------------------------------------------------------------
-- Event Handlers
--

function plugin:Start()
	-- check memory before starting
	local mem = GetAddOnMemoryUsage(ADDON_NAME)/1000
	if mem > 40 then
		self:Print(L["Disabling auto-logging because Transcriptor is currently using %.01f MB of memory. Clear some logs before re-enabling."]:format(mem))
		self.db.profile.enabled = nil
		self:Disable()
		self:Enable()
		return
	end

	local diff = select(3, GetInstanceInfo()) or 0
	if diff > 2 and diff < (self.db.profile.enabledLFR and 8 or 7) then
		-- should the plugin stop your current log and take over? (current behavior)
		-- or leave Transcriptor alone and not do anything (starting or stopping) until you stop the current log yourself?
		if Transcriptor:IsLogging() then
			Transcriptor:StopLog(true)
		end
		wipe(self.db.profile.ignoredEvents)
		for k, v in next, TranscriptDB.ignoredEvents do
			if v == true then self.db.profile.ignoredEvents[k] = v end
		end
		Transcriptor:StartLog()
		logging = true
	end
end

function plugin:Stop()
	if logging then
		if Transcriptor:IsLogging() then
			Transcriptor:StopLog()
		end
		logging = nil
	end
end

