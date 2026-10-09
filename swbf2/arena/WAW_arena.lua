--
-- The arena: the map the hidden Battlefront II sits in while World at War is
-- being played. This file is the part every roster shares.
--
-- The world is the mod tools' blank template with everything that could
-- interfere taken out, the ground and the sky included (build.ps1 does that
-- part): whatever this game draws is then the player's, and its whole picture
-- can be laid over World at War's. Nobody is in it but the player's unit,
-- nothing can kill that unit, and there is no objective, so the mission never
-- ends.
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

-- How far (metres, up being positive) a unit is moved before it is taken
-- away, so that its going is not seen.
local OUT_OF_SIGHT = -2000

-- What each character carries, as a kit number. World at War hands its player
-- the weapons that match the kit (waw/mod has that half, docs/PHASE3.md the
-- list), so that what it shoots and what is seen here agree. A character not
-- listed is kit 0, "not known", and World at War leaves its player alone.
--
-- The bridge cannot ask this script anything, and the game keeps no class
-- names in memory for it to read. But it can read the unit's health, and
-- nothing else uses that: full health is FULL_HEALTH * (1 + says / 65536),
-- where what it says is the kit with the numbers further down added.
local KIT = {
    all_hero_hansolo_tat = 1,                                   -- a heavy pistol
    rep_inf_ep3_rifleman = 2, imp_inf_rifleman = 2,             -- a blaster rifle and a pistol
    cis_inf_marine       = 3,                                   -- a blaster rifle
    imp_hero_bobafett    = 4,                                   -- a rifle that fires in bursts
    all_hero_chewbacca   = 5,                                   -- the bowcaster
    all_hero_leia        = 6,                                   -- a pistol that fires a beam
    -- A lightsaber, and from here on the kit says which abilities go with it.
    all_hero_luke_jedi   = 7, rep_hero_obiwan     = 7,          -- throwing it, and Force push
    rep_hero_macewindu   = 7, cis_hero_darthmaul  = 7,
    rep_hero_aalya       = 8,                                   -- throwing it, and Force pull
    rep_hero_anakin      = 9, imp_hero_darthvader = 9,          -- throwing it, and Force choke
    rep_hero_yoda        = 10,                                  -- Force pull and Force push
    cis_hero_countdooku  = 11,                                  -- Force lightning and Force choke
    cis_hero_grievous    = 12,                                  -- nothing but the lightsabers
    imp_hero_emperor     = 13,                                  -- as Count Dooku, but he glides: World at War
                                                                -- is not to be heard walking for him
}

-- Two more things the bridge needs to know about the character go in with
-- the kit, as numbers added to it:
local IS_HERO = 32    -- a hero or a villain: always shown from behind
local IS_MELEE = 64   -- fights with a lightsaber: its abilities are worked by a different button (docs/PHASE3.md)
local FIRST_MELEE_KIT = 7

-- And a third: who the character is, as a number times WHO_TIMES. Several
-- characters share a kit, and World at War shows the player's name on its
-- scoreboard: the character's, which its bridge has by this number ([waw]
-- character_names in its wawbf.ini; the two lists have to agree).
local WHO_TIMES = 128
local WHO = {
    all_hero_hansolo_tat = 1,  rep_inf_ep3_rifleman = 2,  imp_inf_rifleman    = 3,
    cis_inf_marine       = 4,  imp_hero_bobafett    = 5,  all_hero_chewbacca  = 6,
    all_hero_leia        = 7,  all_hero_luke_jedi   = 8,  rep_hero_obiwan     = 9,
    rep_hero_macewindu   = 10, cis_hero_darthmaul   = 11, rep_hero_aalya      = 12,
    rep_hero_anakin      = 13, imp_hero_darthvader  = 14, rep_hero_yoda       = 15,
    cis_hero_countdooku  = 16, cis_hero_grievous    = 17, imp_hero_emperor    = 18,
}

-- What each character carries that it does not carry in the game as shipped.
-- World at War has to be able to do whatever this game shows, so:
--   - anything that is not a weapon, a grenade, a Force power or a thrown
--     lightsaber goes (the fusion cutter, the rallying cries);
--   - every charge and bomb becomes that side's grenade, which World at War
--     matches with its own.
-- A weapon is named by its place among the class's weapons. "" takes the
-- weapon away.
--   - Chewbacca's rocket launcher goes, and nothing takes its place (the
--     user's decision): he has the bowcaster. His launcher fires a rocket
--     the player then steers, looking out from it; nothing in World at War
--     flies that way, and no character is left on the screen while it does.
--     Three other launchers were tried in its place and each stopped the
--     game dead the moment he took it in hand, seen from behind: the
--     Alliance soldier's rocket launcher (carried on the shoulder, which he
--     has no way of doing), a copy of that told to be held like a rifle, and
--     the Wookiee soldier's grenade launcher, which is held like a rifle and
--     is the same shape as his own. (Through his eyes the last was fine: it
--     is his body that cannot do it.)
local CARRIES = {
    all_hero_hansolo_tat = { [2] = "", [3] = "all_weap_inf_thermaldetonator", [4] = "" },
    all_hero_chewbacca   = { [2] = "", [3] = "all_weap_inf_thermaldetonator", [4] = "" },
    all_hero_leia        = { [3] = "" },
    imp_hero_bobafett    = { [4] = "imp_weap_inf_thermaldetonator" },
    cis_hero_grievous    = { [2] = "" },
}

-- World at War keeps count of the ammunition, the grenades and the rockets
-- (they are bought at its walls), and stops this game using what it has run
-- out of. So here every weapon that counts at all is given more than a
-- session will use. The places are the class's weapons after CARRIES.
local PLENTY = 99
local COUNTED = {
    all_hero_hansolo_tat = { 3 },
    all_hero_chewbacca   = { 3 },
    all_hero_leia        = { 2 },
    imp_hero_bobafett    = { 2, 3, 4 },
    rep_inf_ep3_rifleman = { 3 },
    imp_inf_rifleman     = { 3 },
    cis_inf_marine       = { 2, 3 },
}

-- Recoil is World at War's. There a shot kicks the view, and the bridge has
-- this game aim wherever that view really points. This game's own way of
-- making a weapon harder to hold on target is to scatter its shots, more the
-- longer it is fired; with both, a bolt drawn here would leave the line World
-- at War's shot took. So every weapon the kits use is made to shoot straight.
-- (The bowcaster's fan is a pattern, not scatter, and stays.)
local STRAIGHT = {
    "YawSpread", "PitchSpread", "SpreadPerShot", "SpreadLimit",
    "StandStillSpread", "StandMoveSpread", "CrouchStillSpread", "CrouchMoveSpread",
    "ProneStillSpread", "ProneMoveSpread",
}
local KIT_WEAPONS = {
    "rep_weap_inf_rifle", "rep_weap_inf_pistol", "imp_weap_inf_rifle", "imp_weap_inf_pistol",
    "cis_weap_inf_rifle", "cis_weap_inf_rocket_launcher",
    "all_weap_hero_hanpistol", "all_weap_inf_bowcaster",
    "all_weap_hero_targetpistol", "imp_weap_hero_bobarifle", "imp_weap_hero_flamethrower",
    "imp_weap_inf_wrist_rocket",
}

-- The crosshair in third person. This game's own camera looks down on the
-- character from behind, some degrees below where the character is aiming
-- (ten, as shipped), and draws the crosshair where the aim then falls in its
-- picture: that many degrees above the middle. But the picture World at War
-- is shown is drawn from World at War's camera, which looks along the aim,
-- and there a shot lands in or near the middle. With no tilt this game's
-- crosshair is in the middle too. (Exactly where a shot lands depends on how
-- far off the target is and how steeply the player is looking down; the
-- World at War bridge draws a small crosshair of its own at that point.)
--
-- 45 was tried, to send this game's crosshair off the top of the screen and
-- leave only the bridge's. Every unit then fell through the floor from the
-- moment it appeared: whatever else the game uses this number for, it is not
-- only the camera. 0 and 10 are known to be safe.
local CAMERA_TILT = 0

-- How high each kind of character jumps is left as the game has it, and World
-- at War's player is made to jump the same ([waw] jump_heights in its
-- wawbf.ini, by kit). The Emperor jumps a metre higher than everyone else
-- with a lightsaber, and shares a kit with Count Dooku; he is brought into
-- line with the others.
local JUMPS = { imp_hero_emperor = 3.5 }

local arena = nil        -- the roster ArenaInit was given
local chosen = { 1, 1 }  -- which of each team's characters the player is, or will be next
local waiting = nil      -- { team =, place =, looks = } while the old unit goes away
local playing = nil      -- the class the player was last put in the world as
local first = nil        -- the team the player is first put in the world on, if the roster says who they start as (ArenaInit)

-- Full health for the character in play, with its kit in it.
local function FullHealth()
    local kit = (playing and KIT[playing]) or 0
    local says = kit
    if playing and string.find(playing, "_hero_", 1, true) then
        says = says + IS_HERO
    end
    if kit >= FIRST_MELEE_KIT then
        says = says + IS_MELEE
    end
    says = says + WHO_TIMES * ((playing and WHO[playing]) or 0)
    return FULL_HEALTH * (1 + says / 65536)
end

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
    playing = class
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
    if unit then
        first = nil
    end
    if not unit then
        -- (The very first time, on the team of whoever the roster says the
        -- player starts as, whichever team the game put them on.)
        local to = waiting or { team = first or team }
        waiting = nil
        Appear(character, to.team, to.place)
    elseif waiting then
        waiting.looks = waiting.looks + 1
        if waiting.looks > GIVE_UP_AFTER then
            Trace("still-here")
            waiting = nil
            SetProperty(unit, "CurHealth", FullHealth())
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
            -- The only way to take a unit away is to kill it, and a unit that
            -- dies falls over where it stands and may drop something. So it
            -- is put far below the floor first: it dies, and drops whatever
            -- it drops, where nothing looks.
            SetEntityMatrix(unit, CreateMatrix(0, 0, 0, 0, 0, OUT_OF_SIGHT, 0, waiting.place))
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
                    SetProperty(unit, "MaxHealth", FullHealth())
                    SetProperty(unit, "CurHealth", FullHealth())
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

    -- Who the player starts as, if the roster says (start = a class): that
    -- character's team, and its place among that team's characters. Without
    -- it, the first of team 1's.
    if roster.start then
        for team = ATT, DEF do
            for place, class in ipairs(roster.teams[team].classes) do
                if class == roster.start then
                    first = team
                    chosen[team] = place
                end
            end
        end
    end

    -- No "pick a team" screen: the player starts on team 1 and changes side,
    -- like character, by asking.
    if ForceHumansOntoTeam1 then
        ForceHumansOntoTeam1()
    end

    -- Ours as well as the game's own. Ours is the same pack built from the mod
    -- tools' sources with one change: the part of the HUD that shows the
    -- weapons is higher up the screen, and every other part is off it
    -- (build.ps1 says how). The game then has two HUDs, its own where it
    -- always is and ours; the bridge lets only the place of our weapons be
    -- drawn to ([overlay] hud_keep), and that is all that is seen of either.
    -- (Ours alone would be simpler, and the game does not start with it.)
    ReadDataFile("dc:ingame.lvl")
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

    -- One era's sounds, and only one. Each era's pack for a planet carries
    -- one bank of recordings, and of two such the game takes in the first
    -- and not the second: with both read, in either order and from this
    -- planet's file or another's, only the first era's weapons were heard
    -- (measured, each character firing in turn: the clone trooper's rifle at
    -- a fifth of full scale read first and nothing read second, and the
    -- stormtrooper's the other way about). A roster that mixes eras ("both")
    -- gets the Empire's and the Alliance's, which is also the pack with every
    -- hero's sounds in it. Its Clone Wars troopers' weapons are in a small
    -- bank of the arena's own, read ahead of it (build.ps1 makes it, out of
    -- the game's own recordings): four firing sounds, under the names those
    -- weapons ask for.
    if roster.era == "cw" then
        ReadDataFile("sound\\tat.lvl;tat2cw")
    else
        if roster.era == "both" then
            ReadDataFile("dc:sound\\waw.lvl;wawcw")
        end
        ReadDataFile("sound\\tat.lvl;tat2gcw")
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
            SetClassProperty(class, "TiltValue", CAMERA_TILT)
            if JUMPS[class] then
                SetClassProperty(class, "JumpHeight", JUMPS[class])
            end
            for place, weapon in pairs(CARRIES[class] or {}) do
                SetClassProperty(class, "WeaponName" .. place, weapon)
            end
            for _, place in ipairs(COUNTED[class] or {}) do
                SetClassProperty(class, "WeaponAmmo" .. place, PLENTY)
            end
        end
    end

    -- A weapon whose side this roster did not load is not there to change.
    for _, weapon in ipairs(KIT_WEAPONS) do
        for _, property in ipairs(STRAIGHT) do
            pcall(SetClassProperty, weapon, property, 0)
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

    -- Nothing is opened to play music, the soldiers' chatter or Tatooine's
    -- wind: World at War is the game being played, and what is wanted of this
    -- one's sound is its weapons (which come with the sides' own sound files,
    -- read above), now that it can be heard at all (the bridge keeps its
    -- sound playing while another window has the keyboard). And the levels
    -- are set to match: effects and the master all the way up, music and both
    -- kinds of talk off, whatever the player's profile for this game says.
    if ScriptCB_GetVolumes and ScriptCB_SetVolumes then
        local music, effects, voice, chatter, most, master = ScriptCB_GetVolumes()
        if most then
            ScriptCB_SetVolumes(0, most, 0, 0, most)
        end
    end
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
