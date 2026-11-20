require("tree_view")
require("sandbox_tools")
-- Local BST playground on Valve's precompiled test_basic map.
function Precache(context)
    PrecacheUnitByNameSync("npc_dota_hero_pudge", context)
    PrecacheUnitByNameSync("npc_tree_node", context)
    PrecacheResource("particle", "particles/units/heroes/hero_wisp/wisp_tether.vpcf", context)
end

function Activate()
    print("[tree_visualizer] Addon loaded on " .. GetMapName())
    TreeView:Init()
    SandboxTools:Init()
    local mode = GameRules:GetGameModeEntity()
    mode:SetCustomGameForceHero("npc_dota_hero_pudge")
    mode:SetFogOfWarDisabled(true)
    mode:SetDaynightCycleDisabled(true)
    GameRules:SetTimeOfDay(0.5)
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_GOODGUYS, 1)
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_BADGUYS, 0)
    GameRules:SetCustomGameSetupTimeout(0)
    GameRules:SetHeroSelectionTime(0)
    GameRules:SetPreGameTime(0)
    GameRules:SetPostGameTime(0)
    GameRules:SetCreepSpawningEnabled(false)
    ListenToGameEvent("npc_spawned", function(event)
        local unit = EntIndexToHScript(event.entindex)
        if unit and unit:IsRealHero() then
            local hook = unit:FindAbilityByName("pudge_meat_hook")
            if hook then hook:SetLevel(4) end
            unit:SetMana(unit:GetMaxMana())
            unit:SetContextThink("BSTHookPractice", function()
                if unit:IsNull() then return nil end
                if unit:IsAlive() then
                    unit:SetMana(unit:GetMaxMana())
                    local ability = unit:FindAbilityByName("pudge_meat_hook")
                    if ability then ability:EndCooldown() end
                end
                return 0.5
            end, 0.5)
            print("[tree_visualizer] Hero ready: " .. unit:GetUnitName())
            if not TreeView.started then
                TreeView.started = true
                TreeView.origin = unit:GetAbsOrigin() + Vector(0, 450, 0)
                TreeView:Request("state")
                GameRules:SendCustomMessage("BST: -demo | -insert 42 | -delete 42 | -find 42 | -clear | -tree", 0, 0)
            end
        end
    end, nil)
end
