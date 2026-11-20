SandboxTools = {changing = {}}
local function integer(text, default, low, high)
    if text == "" then return default end
    if not text:match("^%d+$") then return nil end
    local number = tonumber(text)
    if not number or number < low or number > high then return nil end
    return number
end
function SandboxTools:CleanMap()
    GridNav:DestroyTreesAroundPoint(Vector(0, 0, 0), 30000, false)
    local removed = 0
    -- Only disposable map props; units, floor/world geometry and game logic stay intact.
    for _, classname in ipairs({"dota_item_rune", "dota_rune_spawner", "prop_dynamic", "prop_physics", "prop_physics_override"}) do
        for _, entity in pairs(Entities:FindAllByClassname(classname)) do
            if not entity:IsNull() then UTIL_Remove(entity); removed = removed + 1 end
        end
    end
    print("[tree_visualizer] Map cleanup: trees cleared, props/runes removed=" .. removed)
end
function SandboxTools:Init()
    GameRules:SetUseUniversalShopMode(true)
    GameRules:GetGameModeEntity():SetCanSellAnywhere(true)
    -- Developer sandbox: native easy-buy puts all shops in range and makes items free.
    SendToServerConsole("sv_cheats 1")
    SendToServerConsole("dota_easybuy 1")
    GameRules:SetTreeRegrowTime(999999)
    GameRules:SetRuneSpawnTime(999999)
    local mode = GameRules:GetGameModeEntity()
    mode:SetContextThink("BSTMapCleanup", function()
        self:CleanMap()
        print("[tree_visualizer] Shop anywhere: easybuy=" .. tostring(Convars:GetFloat("dota_easybuy")))
        -- A map may spawn a rune after its activation scripts run.
        mode:SetContextThink("BSTNoRunes", function()
            for _, rune in pairs(Entities:FindAllByClassname("dota_item_rune")) do UTIL_Remove(rune) end
            return 1
        end, 1)
        return nil
    end, 1)
end
function SandboxTools:Command(command, rest, playerId)
    if command == "clean" then self:CleanMap(); TreeView:Say("Map props, runes and trees cleared"); return true end
    if command ~= "gold" and command ~= "lvlup" and command ~= "change_hero" and command ~= "refresh" then return false end
    playerId = tonumber(playerId)
    if not playerId or not PlayerResource:IsValidPlayerID(playerId) then
        TreeView:Say("Use this command in your player chat"); return true
    end
    local hero = PlayerResource:GetSelectedHeroEntity(playerId)
    if not hero or hero:IsNull() then TreeView:Say("Choose a hero first"); return true end
    if command == "refresh" then
        if rest ~= "" then TreeView:Say("Usage: -refresh"); return true end
        if not hero:IsAlive() then hero:RespawnHero(false, false) end
        hero:SetHealth(hero:GetMaxHealth())
        hero:SetMana(hero:GetMaxMana())
        for i = 0, hero:GetAbilityCount() - 1 do
            local ability = hero:GetAbilityByIndex(i)
            if ability then ability:EndCooldown(); ability:RefreshCharges() end
        end
        for i = 0, 20 do
            local item = hero:GetItemInSlot(i)
            if item then item:EndCooldown(); item:RefreshCharges() end
        end
        TreeView:Say("Refreshed health, mana, abilities and items")
    elseif command == "gold" then
        local amount = integer(rest, 10000, 0, 1000000)
        if not amount then TreeView:Say("Usage: -gold [0..1000000]"); return true end
        PlayerResource:ModifyGold(playerId, amount, true, 0)
        TreeView:Say("Added gold: " .. amount)
    elseif command == "lvlup" then
        local amount = integer(rest, 1, 1, 30)
        if not amount then TreeView:Say("Usage: -lvlup [1..30]"); return true end
        local target = math.min(30, hero:GetLevel() + amount)
        while hero:GetLevel() < target do
            local old = hero:GetLevel(); hero:HeroLevelUp(true)
            if hero:GetLevel() == old then break end
        end
        TreeView:Say("Hero level: " .. hero:GetLevel())
    else
        local name = rest:lower()
        if not name:match("^[a-z_]+$") then TreeView:Say("Usage: -change_hero pudge"); return true end
        if not name:match("^npc_dota_hero_") then name = "npc_dota_hero_" .. name end
        local heroId = DOTAGameManager:GetHeroIDByName(name)
        if not heroId or heroId <= 0 then TreeView:Say("Unknown hero: " .. rest); return true end
        if self.changing[playerId] then TreeView:Say("Hero is still loading"); return true end
        self.changing[playerId] = true
        TreeView:Say("Loading " .. name)
        PrecacheUnitByNameAsync(name, function()
            self.changing[playerId] = nil
            local current = PlayerResource:GetSelectedHeroEntity(playerId)
            if not current or current:IsNull() then return end
            local position, gold, xp = current:GetAbsOrigin(), PlayerResource:GetGold(playerId), current:GetCurrentXP()
            local replacement = PlayerResource:ReplaceHeroWith(playerId, name, gold, xp)
            if replacement then
                FindClearSpaceForUnit(replacement, position, true)
                replacement:SetMana(replacement:GetMaxMana())
                TreeView:Say("Hero changed to " .. name)
            else TreeView:Say("Hero replacement failed") end
        end, playerId)
    end
    return true
end
