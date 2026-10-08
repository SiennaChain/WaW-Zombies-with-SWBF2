--
-- Arena roster: Galactic Civil War. The Empire's and the Alliance's soldiers,
-- and their own heroes. See WAW_arena.lua.
--

ScriptCB_DoFile("WAW_arena")

function ScriptPostLoad()
    ArenaPostLoad()
end

function ScriptInit()
    local imp = { "imp_inf_rifleman", "imp_inf_rocketeer", "imp_inf_sniper", "imp_inf_engineer",
                  "imp_inf_officer", "imp_inf_dark_trooper",
                  "imp_hero_darthvader", "imp_hero_emperor", "imp_hero_bobafett" }
    local all = { "all_inf_rifleman", "all_inf_rocketeer", "all_inf_sniper", "all_inf_engineer",
                  "all_inf_officer", "all_inf_wookiee",
                  "all_hero_luke_jedi", "all_hero_hansolo_tat", "all_hero_leia", "all_hero_chewbacca" }
    ArenaInit{
        era = "gcw",
        sides = { { "imp", imp }, { "all", all } },
        teams = { { name = "imp", classes = imp }, { name = "all", classes = all } },
    }
end
