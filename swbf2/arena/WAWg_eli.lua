--
-- Arena roster: every hero and villain, as the game's own hero assault mode
-- groups them. This is the only roster with Aayla Secura and Ki-Adi-Mundi.
-- See WAW_arena.lua.
--

ScriptCB_DoFile("WAW_arena")

function ScriptPostLoad()
    ArenaPostLoad()
end

function ScriptInit()
    ArenaInit{
        era = "gcw",
        sides = {
            { "all", { "all_hero_luke_jedi", "all_hero_hansolo_tat", "all_hero_leia", "all_hero_chewbacca" } },
            { "imp", { "imp_hero_darthvader", "imp_hero_emperor", "imp_hero_bobafett" } },
            { "rep", { "rep_hero_yoda", "rep_hero_macewindu", "rep_hero_anakin", "rep_hero_aalya",
                       "rep_hero_kiyadimundi", "rep_hero_obiwan" } },
            { "cis", { "cis_hero_grievous", "cis_hero_darthmaul", "cis_hero_countdooku", "cis_hero_jangofett" } },
        },
        teams = {
            { name = "hero", classes = { "all_hero_hansolo_tat", "all_hero_chewbacca", "all_hero_luke_jedi",
                                         "rep_hero_obiwan", "rep_hero_yoda", "rep_hero_macewindu",
                                         "all_hero_leia", "rep_hero_aalya", "rep_hero_kiyadimundi" } },
            { name = "villain", classes = { "imp_hero_bobafett", "imp_hero_darthvader", "cis_hero_darthmaul",
                                            "cis_hero_jangofett", "cis_hero_grievous", "imp_hero_emperor",
                                            "rep_hero_anakin", "cis_hero_countdooku" } },
        },
    }
end
