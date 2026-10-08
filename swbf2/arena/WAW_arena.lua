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
-- A roster (WAWg_con.lua and its siblings) says who can be picked on the
-- spawn screen. The screen has room for ten classes a team and there are two
-- teams, so one roster holds twenty characters at most; that is why there is
-- more than one.
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
                    SetProperty(unit, "MaxHealth", 1e+37)
                    SetProperty(unit, "CurHealth", 1e+37)
                end
            end
        end
    )

end

function ArenaInit(roster)

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
