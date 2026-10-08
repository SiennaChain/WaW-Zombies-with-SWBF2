--
-- Arena roster: heroes and villains, grouped as the game's own hero assault
-- mode groups them, with ordinary soldiers for company: a clone trooper with
-- the heroes, a stormtrooper and a battle droid with the villains.
-- See WAW_arena.lua.
--
-- Who is in it is bounded by something other than the ten places a team has
-- on the spawn screen. A mission can hold only so many different sets of
-- animations (the game's code has 24 places for them), and the game's own
-- seventeen heroes and villains use every one. Going over does not fail
-- politely: the game reads through a null pointer while the mission loads.
--
--   - A clone trooper or a stormtrooper costs nothing: they move like the
--     human heroes already here.
--   - A battle droid moves like nothing else here, so it costs a place, and
--     a hero with animations all his own had to make way. Ki-Adi-Mundi did.
--   - Jango Fett was taken out by request, which freed nothing: Boba Fett
--     uses the same animations. He could come back at no cost.
--
-- The battle droid is the space battles' marine. On the ground the
-- Separatists' rifleman is the super battle droid, which fires from its
-- wrist; the plain droid carrying a rifle only turns up aboard ships.
--

ScriptCB_DoFile("WAW_arena")

function ScriptPostLoad()
    ArenaPostLoad()
end

function ScriptInit()
    ArenaInit{
        era = "both",
        sides = {
            { "all", { "all_hero_luke_jedi", "all_hero_hansolo_tat", "all_hero_leia", "all_hero_chewbacca" } },
            { "imp", { "imp_hero_darthvader", "imp_hero_emperor", "imp_hero_bobafett", "imp_inf_rifleman" } },
            { "rep", { "rep_hero_yoda", "rep_hero_macewindu", "rep_hero_anakin", "rep_hero_aalya",
                       "rep_hero_obiwan", "rep_inf_ep3_rifleman" } },
            { "cis", { "cis_hero_grievous", "cis_hero_darthmaul", "cis_hero_countdooku", "cis_inf_marine" } },
        },
        teams = {
            { name = "hero", classes = { "all_hero_hansolo_tat", "all_hero_chewbacca", "all_hero_luke_jedi",
                                         "rep_hero_obiwan", "rep_hero_yoda", "rep_hero_macewindu",
                                         "all_hero_leia", "rep_hero_aalya", "rep_inf_ep3_rifleman" } },
            { name = "villain", classes = { "imp_hero_bobafett", "imp_hero_darthvader", "cis_hero_darthmaul",
                                            "cis_hero_grievous", "imp_hero_emperor", "rep_hero_anakin",
                                            "cis_hero_countdooku", "imp_inf_rifleman", "cis_inf_marine" } },
        },
    }
end
