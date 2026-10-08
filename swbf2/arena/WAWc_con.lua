--
-- Arena roster: Clone Wars. The Republic's and the Separatists' soldiers, and
-- four heroes each. See WAW_arena.lua.
--

ScriptCB_DoFile("WAW_arena")

function ScriptPostLoad()
    ArenaPostLoad()
end

function ScriptInit()
    local rep = { "rep_inf_ep3_rifleman", "rep_inf_ep3_rocketeer", "rep_inf_ep3_sniper",
                  "rep_inf_ep3_engineer", "rep_inf_ep3_officer", "rep_inf_ep3_jettrooper",
                  "rep_hero_obiwan", "rep_hero_yoda", "rep_hero_macewindu", "rep_hero_anakin" }
    local cis = { "cis_inf_rifleman", "cis_inf_rocketeer", "cis_inf_sniper", "cis_inf_engineer",
                  "cis_inf_officer", "cis_inf_droideka",
                  "cis_hero_darthmaul", "cis_hero_countdooku", "cis_hero_grievous", "cis_hero_jangofett" }
    ArenaInit{
        era = "cw",
        sides = { { "rep", rep }, { "cis", cis } },
        teams = { { name = "rep", classes = rep }, { name = "cis", classes = cis } },
        droidekas = 3,
    }
end
