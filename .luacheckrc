std = "lua51"
max_line_length = false
codes = true

ignore = {
	"11[13]/TranscriptDB",
	"12[12]/TranscriptIgnore",
	"143/string",
	"143/table",
	"211/L", -- unused variable L
	"542", -- empty if branch
}
not_globals = {
	"arg", -- arg is a standard global, so without this it won't error when we typo "args" in a module
}
read_globals = {
	"BigWigs",
	"BigWigsAPI",
	"C_Timer",
	"date",
	"ENABLE",
	"GameTooltip",
	"GetAddOnMemoryUsage",
	"GetDifficultyInfo",
	"GetInstanceInfo",
	"GetLocale",
	"GetRealZoneText",
	"InCombatLockdown",
	"LibStub",
	"RESET",
	"time",
	"TranscriptIgnore",
	"Transcriptor",
	"UNKNOWN",
	"UpdateAddOnMemoryUsage",
	"WOW_PROJECT_ID",
}
