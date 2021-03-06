# BigWigs_Transcriptor

**This addon is a BigWigs plugin and requires BigWigs to run.**

Simple addon that uses BigWigs for pull/win/wipe detection and starts or stops
Transcriptor logging accordingly. Makes it easy to get segmented boss logs when
you're analyzing an encounter. Also allows you to easily remove individual logs!

Should note that if you're wiping a lot and not clearing logs, memory usage can
get high and at some point the game will throw an error and nil out
Transcriptor's database the next time the UI loads, ie, you lose everything! If
that happens, your SavedVars/Transcriptor.lua will still have whatever was last
saved to it until you reload UI or logout, so copy it somewhere else if you
want to save it.

Defaults to being disabled. Settings are in the BigWigs config (`/bw`) or via
`/bwts`.

## Download

<https://www.curseforge.com/wow/addons/bigwigs_transcriptor>
