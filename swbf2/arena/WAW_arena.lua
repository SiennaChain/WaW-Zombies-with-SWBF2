--
-- The arena: the map the hidden Battlefront II sits in while World at War is
-- being played. This file is the part every roster shares.
--
-- The world is the mod tools' blank template with everything that could
-- interfere taken out. Nobody is in it but the player's unit, nothing can
-- kill that unit, and there is no objective, so the mission never ends.
-- World at War owns the fight; this game only has to keep a character
-- standing there.
--
-- A roster (WAWg_con.lua and its siblings) says who the player can be. The
-- spawn screen has room for ten classes a team and there are two teams, so
-- one roster holds twenty characters at most; that is why there is more than
-- one.
--
-- The player does not have to use that screen. The mission puts them in the
-- world as team 1's first character as soon as it starts, and the bridge can
-- ask for the next character of either team at any time (F10 and F11 by
-- default): see Look, below.
--
--   ArenaInit{
--       era   = "gcw", "cw" or "both",  -- which eras' sounds and voices to load
--       sides = { { "all", { "all_inf_rifleman", ... } }, ... },  -- what to load, from which side
--       teams = { { name = "imp", classes = { ... } },            -- team 1
--                 { name = "all", classes = { ... } } },          -- team 2
--       droidekas = 0,                  -- how many can exist at once
--   }
--
-- Built and installed by build.ps1 in this folder.
--

local ATT = 1
local DEF = 2

-- World at War draws with a field of view of 65 unless the player has changed
-- it. Battlefront's soldiers use 70 in first person and 65 in third, measured
-- the same way (the angle across a 4:3 picture), so both are set to 65. The
-- two pictures can only be laid over each other if they agree, and the
-- bridge's log says whether they do.
local FIELD_OF_VIEW = 65

-- How many magazines a soldier carries for its first weapon (the stock
-- rifleman has four).
local SPARE_MAGAZINES = 99

-- The player's unit cannot be hurt: World at War decides that. So its health
-- is free to carry a message. The bridge cannot call into this script, but it
-- can write to the unit, and this script can read the unit's health; the
-- bridge asks for a change of character by setting the health to one of
-- these, and a timer here looks for it. Both are still far more than
-- anything could take away. (The same numbers are in wawbf.ini.)
local FULL_HEALTH = 1e+37
local ASK_NEXT = { 9e+36, 8e+36 }  -- the next of team 1's characters, the next of team 2's
local LOOK_EVERY = 0.1             -- seconds
local GIVE_UP_AFTER = 30           -- looks to wait for the old unit to go before forgetting the request

-- Where the player appears when there is no unit to take the place of.
local SPAWN_PATH = "cp1_spawn"

local arena = nil        -- the roster ArenaInit was given
local chosen = { 1, 1 }  -- which of each team's characters the player is, or will be next
local waiting = nil      -- { team =, place =, looks = } while the old unit goes away

-- The shipped game keeps no log, so each step leaves a string in memory that
-- tools/probe/bfluatrace.ps1 can look for.
local function Trace(step)
    gWawArenaTrace = "wawbf-trace:arena-" .. step
end

-- The player's character and its team. A character exists whether or not it
-- is in the world; it is nil only until the player is on a team.
local function FindHuman()
    for team = ATT, DEF do
        for member = 0, GetTeamSize(team) - 1 do
            local character = GetTeamMember(team, member)
            if character and IsCharacterHuman(character) then
                return character, team
            end
        end
    end
end

-- Puts the player in the world as its team's chosen character.
local function Appear(character, team, place)
    local class = arena.teams[team].classes[chosen[team]]
    Trace("appear-" .. class)
    SelectCharacterTeam(character, team)
    SelectCharacterClass(character, class)
    SpawnCharacter(character, place or GetPathPoint(SPAWN_PATH, 0))
end

-- Which team's next character the bridge is asking for, if it is.
local function Asked(unit)
    local health, most = GetObjectHealth(unit)
    if most and health and most < health then
        health = most
    end
    if not health or health > (FULL_HEALTH + ASK_NEXT[1]) / 2 then
        return nil
    end
    return health > (ASK_NEXT[1] + ASK_NEXT[2]) / 2 and ATT or DEF
end

-- The player is always in the world: with no unit (the mission has just
-- started) it is given one, without the spawn screen. When the bridge asks,
-- the unit is replaced, where it stands, by the next character of the team
-- asked for. Asking for the other team's goes to the one last used there.
local function Look()
    local character, team = FindHuman()
    if not character then
        return
    end
    local unit = GetCharacterUnit(character)
    if not unit then
        local to = waiting or { team = team }
        waiting = nil
        Appear(character, to.team, to.place)
    elseif waiting then
        waiting.looks = waiting.looks + 1
        if waiting.looks > GIVE_UP_AFTER then
            Trace("still-here")
            waiting = nil
            SetProperty(unit, "CurHealth", FULL_HEALTH)
        end
    else
        local asked = Asked(unit)
        if asked then
            if asked == team then
                chosen[asked] = chosen[asked] + 1
                if chosen[asked] > table.getn(arena.teams[asked].classes) then
                    chosen[asked] = 1
                end
            end
            Trace("asked-" .. asked)
            waiting = { team = asked, place = GetEntityMatrix(unit), looks = 0 }
            KillObject(unit)
        end
    end
end

function ArenaPostLoad()

    -- Only the player. The command posts are still there to spawn from, but
    -- no conquest objective is started, so holding or losing them decides
    -- nothing.
    AllowAISpawn(ATT, false)
    AllowAISpawn(DEF, false)

    -- World at War decides when the player is hurt or dies. Here the unit
    -- must simply never go away, whatever it falls off or walks into.
    OnCharacterSpawn(
        function(character)
            if IsCharacterHuman(character) then
                local unit = GetCharacterUnit(character)
                if unit then
                    SetProperty(unit, "MaxHealth", FULL_HEALTH)
                    SetProperty(unit, "CurHealth", FULL_HEALTH)
                end
            end
        end
    )

    -- A mistake in Look must not stop the looking.
    local timer = CreateTimer("waw_look")
    SetTimerValue(timer, LOOK_EVERY)
    StartTimer(timer)
    OnTimerElapse(
        function(elapsed)
            local ok, problem = pcall(Look)
            if not ok then
                Trace("problem-" .. tostring(problem))
            end
            SetTimerValue(elapsed, LOOK_EVERY)
            StartTimer(elapsed)
        end,
        timer
    )
    Trace("looking")

end

function ArenaInit(roster)

    arena = roster

    -- No "pick a team" screen: the player starts on team 1 and changes side,
    -- like character, by asking.
    if ForceHumansOntoTeam1 then
        ForceHumansOntoTeam1()
    end

    ReadDataFile("ingame.lvl")

    SetMaxFlyHeight(40)
    SetMaxPlayerFlyHeight(40)

    SetMemoryPoolSize ("ClothData",20)
    SetMemoryPoolSize ("Combo",50)              -- should be ~ 2x number of jedi classes
    SetMemoryPoolSize ("Combo::State",650)      -- should be ~12x #Combo
    SetMemoryPoolSize ("Combo::Transition",650) -- should be a bit bigger than #Combo::State
    SetMemoryPoolSize ("Combo::Condition",650)  -- should be a bit bigger than #Combo::State
    SetMemoryPoolSize ("Combo::Attack",550)     -- should be ~8-12x #Combo
    SetMemoryPoolSize ("Combo::DamageSample",6000)  -- should be ~8-12x #Combo::Attack
    SetMemoryPoolSize ("Combo::Deflect",100)     -- should be ~1x #combo

    -- A roster that mixes eras asks for "both", so that nobody is silent.
    if roster.era ~= "cw" then
        ReadDataFile("sound\\tat.lvl;tat2gcw")
    end
    if roster.era ~= "gcw" then
        ReadDataFile("sound\\tat.lvl;tat2cw")
    end

    for _, side in ipairs(roster.sides) do
        ReadDataFile("SIDE\\" .. side[1] .. ".lvl", unpack(side[2]))
    end

    -- What setup_teams.lua does, without its limit of six named slots a team.
    -- Reinforcements of -1 mean "no limit": a team that cannot run out cannot
    -- lose.
    for team, info in ipairs(roster.teams) do
        SetTeamName(team, info.name)
        SetTeamIcon(team, info.name .. "_icon", "hud_reinforcement_icon", "flag_icon")
        SetUnitCount(team, 8)
        SetReinforcementCount(team, -1)
        for _, class in ipairs(info.classes) do
            AddUnitClass(team, class, 1, 2)
            SetClassProperty(class, "FirstPersonFOV", FIELD_OF_VIEW)
            SetClassProperty(class, "ThirdPersonFOV", FIELD_OF_VIEW)
            -- There is nothing in the arena to take ammunition from, and a
            -- soldier that has shot its four magazines at zombies is left
            -- with a weapon that does nothing. So it carries more magazines
            -- than a session will use. (0 is the game's own "never runs
            -- out" and also works, showing an infinity sign for the count;
            -- reloading by hand has only been checked with a real number.)
            SetClassProperty(class, "WeaponAmmo1", SPARE_MAGAZINES)
        end
    end

    --  Level Stats
    ClearWalkers()
    AddWalkerType(0, roster.droidekas or 0) -- special -> droidekas
    AddWalkerType(1, 0) -- 1x2 (1 pair of legs)
    AddWalkerType(2, 0) -- 2x2 (2 pairs of legs)
    AddWalkerType(3, 0) -- 3x2 (3 pairs of legs)

    local weaponCnt = 1024
    SetMemoryPoolSize("Aimer", 75)
    SetMemoryPoolSize("AmmoCounter", weaponCnt)
    SetMemoryPoolSize("BaseHint", 1024)
    SetMemoryPoolSize("EnergyBar", weaponCnt)
    SetMemoryPoolSize("EntityCloth", 41)
    SetMemoryPoolSize("EntityFlyer", 32)
    SetMemoryPoolSize("EntityHover", 32)
    SetMemoryPoolSize("EntityLight", 200)
    SetMemoryPoolSize("EntitySoundStream", 4)
    SetMemoryPoolSize("EntitySoundStatic", 45)
    SetMemoryPoolSize("FLEffectObject::OffsetMatrix", 120)
    SetMemoryPoolSize("MountedTurret", 32)
    SetMemoryPoolSize("Navigator", 128)
    SetMemoryPoolSize("Obstacle", 1024)
    SetMemoryPoolSize("PathNode", 1024)
    SetMemoryPoolSize("SoundSpaceRegion", 64)
    SetMemoryPoolSize("TentacleSimulator", 24)
    SetMemoryPoolSize("TreeGridStack", 1024)
    SetMemoryPoolSize("UnitAgent", 128)
    SetMemoryPoolSize("UnitController", 128)
    SetMemoryPoolSize("Weapon", weaponCnt)

    SetSpawnDelay(1.0, 0.25)
    ReadDataFile("dc:WAW\\WAW.lvl", "WAW_conquest")
    SetDenseEnvironment("false")

    --  Sound Stats

    -- No hero theme or announcer every time a hero is picked.
    ScriptCB_EnableHeroMusic(0)
    ScriptCB_EnableHeroVO(0)

    if roster.era == "cw" then
        voiceSlow = OpenAudioStream("sound\\global.lvl", "rep_unit_vo_slow")
        AudioStreamAppendSegments("sound\\global.lvl", "cis_unit_vo_slow", voiceSlow)
        AudioStreamAppendSegments("sound\\global.lvl", "des_unit_vo_slow", voiceSlow)
        AudioStreamAppendSegments("sound\\global.lvl", "global_vo_slow", voiceSlow)

        voiceQuick = OpenAudioStream("sound\\global.lvl", "rep_unit_vo_quick")
        AudioStreamAppendSegments("sound\\global.lvl", "cis_unit_vo_quick", voiceQuick)

        OpenAudioStream("sound\\global.lvl",  "cw_music")
    else
        voiceSlow = OpenAudioStream("sound\\global.lvl", "all_unit_vo_slow")
        AudioStreamAppendSegments("sound\\global.lvl", "imp_unit_vo_slow", voiceSlow)
        if roster.era == "both" then
            AudioStreamAppendSegments("sound\\global.lvl", "rep_unit_vo_slow", voiceSlow)
            AudioStreamAppendSegments("sound\\global.lvl", "cis_unit_vo_slow", voiceSlow)
        end
        AudioStreamAppendSegments("sound\\global.lvl", "des_unit_vo_slow", voiceSlow)
        AudioStreamAppendSegments("sound\\global.lvl", "global_vo_slow", voiceSlow)

        voiceQuick = OpenAudioStream("sound\\global.lvl",  "all_unit_vo_quick")
        AudioStreamAppendSegments("sound\\global.lvl",  "imp_unit_vo_quick", voiceQuick)
        if roster.era == "both" then
            AudioStreamAppendSegments("sound\\global.lvl", "rep_unit_vo_quick", voiceQuick)
            AudioStreamAppendSegments("sound\\global.lvl", "cis_unit_vo_quick", voiceQuick)
        end

        OpenAudioStream("sound\\global.lvl",  "gcw_music")
    end
    OpenAudioStream("sound\\tat.lvl",  "tat2")
    OpenAudioStream("sound\\tat.lvl",  "tat2")

    SetSoundEffect("ScopeDisplayZoomIn",  "binocularzoomin")
    SetSoundEffect("ScopeDisplayZoomOut", "binocularzoomout")
    SetSoundEffect("SpawnDisplayUnitChange",       "shell_select_unit")
    SetSoundEffect("SpawnDisplayUnitAccept",       "shell_menu_enter")
    SetSoundEffect("SpawnDisplaySpawnPointChange", "shell_select_change")
    SetSoundEffect("SpawnDisplaySpawnPointAccept", "shell_menu_enter")
    SetSoundEffect("SpawnDisplayBack",             "shell_menu_exit")

    --  Camera Stats
    AddCameraShot(0.974338, -0.222180, 0.035172, 0.008020, -82.664650, 23.668301, 43.955681);
end
