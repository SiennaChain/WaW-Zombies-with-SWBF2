-- Adds the arena to Battlefront II's Instant Action list, and, if it was built
-- to, starts it by itself. The game runs this once while its menus load.
--
-- The arena shows up under three combinations, one per roster:
--   Galactic Civil War, Conquest     -> WAWg_con  (Empire and Alliance)
--   Clone Wars, Conquest             -> WAWc_con  (Republic and Separatists)
--   Galactic Civil War, Hero Assault -> WAWg_eli  (every hero and villain)

local sp_n = table.getn(sp_missionselect_listbox_contents)
sp_missionselect_listbox_contents[sp_n+1] = { mapluafile = "WAW%s_%s", era_g = 1, era_c = 1, mode_con_g = 1, mode_con_c = 1, mode_eli_g = 1, }
local mp_n = table.getn(mp_missionselect_listbox_contents)
mp_missionselect_listbox_contents[mp_n+1] = sp_missionselect_listbox_contents[sp_n+1]

-- associate this mission name with the current downloadable content directory
-- first arg: mapluafile from above
-- second arg: mission script name
-- third arg: level memory modifier
AddDownloadableContent("WAW","WAWg_con",4)
AddDownloadableContent("WAW","WAWc_con",4)
AddDownloadableContent("WAW","WAWg_eli",4)

-- Starting by itself.
--
-- The hidden game is no use sitting at a menu. build.ps1 fills in which
-- roster to go into, or leaves this empty for "stay at the menu".
--
-- On PC the menus go: profile screen (ifs_login), then the single player tab
-- (ifs_sp_campaign). There is no main menu screen in between, which is where
-- the first attempt at this waited and so never ran. Two things are done:
--
--   1. On the profile screen, the profile that is already highlighted (the
--      last one used) is logged in the way the game itself logs in a profile
--      named on its command line.
--   2. On arriving at the single player tab, the arena is launched the way
--      Instant Action launches a map.
--
-- Both are reached by wrapping the two functions every screen calls by name,
-- its "enter" and "update" defaults, rather than by changing the screens'
-- own tables: that works whether or not the screens exist yet when this runs.
--
-- There is no log to read in the shipped game, so each step leaves a string
-- in memory ("wawbf-trace:<step>") that tools/probe can look for. The strings
-- are put together at run time so that finding one means the step ran.
local AUTO_START = "@AUTO_START@"

local function Trace(step)
    gWawTrace = "wawbf-trace:" .. step
end

local function LaunchArena()
    -- The fourth letter of a mission's name is its era: WAWg_con, WAWc_con.
    local era = string.sub(AUTO_START, 4, 4)
    local team1, team2 = "common.sides.all.name", "common.sides.imp.name"
    if era == "c" then
        team1, team2 = "common.sides.rep.name", "common.sides.cis.name"
    end
    Trace("launching-" .. AUTO_START)
    if ifelem_shellscreen_fnStopMovie then
        ifelem_shellscreen_fnStopMovie()
    end
    gPickedMapList = { { Map = AUTO_START, Side = 1, SideChar = era, Team1 = team1, Team2 = team2, } }
    ScriptCB_SetGameRules("instantaction")
    ScriptCB_SetDifficulty(ScriptCB_GetDifficulty())
    ScriptCB_SetMissionNames(gPickedMapList, nil)
    ScriptCB_SetTeamNames(ScriptCB_getlocalizestr(team1), ScriptCB_getlocalizestr(team2))
    Trace("entering-" .. AUTO_START)
    ScriptCB_EnterMission()
    Trace("entered-" .. AUTO_START)
end

if AUTO_START ~= "" and gIFShellScreenTemplate_fnEnter and gIFShellScreenTemplate_fnUpdate then
    Trace("hooks-in")

    local defaultEnter = gIFShellScreenTemplate_fnEnter
    gIFShellScreenTemplate_fnEnter = function(this, bFwd)
        defaultEnter(this, bFwd)
        if bFwd and not gWawArenaStarted and (this == ifs_sp_campaign or this == ifs_main) then
            gWawArenaStarted = 1
            LaunchArena()
        end
    end

    -- Half a second on the profile screen with profiles listed and nothing
    -- else going on, then log the highlighted one in. ifs_login's own update
    -- does the rest when it sees iForceLoginTime.
    local defaultUpdate = gIFShellScreenTemplate_fnUpdate
    local idle = 0
    gIFShellScreenTemplate_fnUpdate = function(this, fDt)
        defaultUpdate(this, fDt)
        if this == ifs_login and not gWawLoginForced and not gWawArenaStarted then
            if ifs_login_listbox_contents and table.getn(ifs_login_listbox_contents) > 0 and
               not this.iForceLoginTime and not ScriptCB_IsPlayerLoggedIn() then
                idle = idle + 1
                if idle > 30 then
                    gWawLoginForced = 1
                    local profile = ifs_login_listbox_layout.SelectedIdx or 1
                    if profile < 1 or profile > table.getn(ifs_login_listbox_contents) then
                        profile = 1
                    end
                    Trace("logging-in-profile-" .. profile)
                    this.iForceLoginIdx = profile
                    this.iForceLoginTime = 2
                end
            else
                idle = 0
            end
        end
    end
elseif AUTO_START ~= "" then
    Trace("no-hooks")
end

-- all done
newEntry = nil
n = nil
