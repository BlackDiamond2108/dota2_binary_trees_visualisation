
TreeView = {}
function TreeView:Init()
    self.units = {}; self.edges = {}; self.queue = {}; self.busy = false; self.pendingDeaths = {}
    self.incident = {}; self.visual = {}; self.openDeathBatch = nil
    self.sequence = 0
    self.session = tostring(RandomInt(100000, 999999))
    self.origin = Vector(0, 0, 0)
    print("[tree_visualizer] HTTP API: " .. type(CreateHTTPRequestScriptVM))
    ListenToGameEvent("player_chat", function(event) self:Chat(event.text or "", event.playerid or event.PlayerID) end, nil)
    ListenToGameEvent("entity_killed", function(event)
        local unit = EntIndexToHScript(event.entindex_killed)
        if unit then self:NodeKilled(unit) end
    end, nil)
    -- Also detect entities removed by native abilities without a usable death event.
    GameRules:GetGameModeEntity():SetContextThink("BSTDeathWatch", function()
        for key, unit in pairs(self.units) do
            if unit:IsNull() or not unit:IsAlive() then self:DeleteDeadKey(key) end
        end
        return 0.1
    end, 0.1)
    Convars:RegisterCommand("bst", function(_, command, value)
        self:Chat("-" .. (command or "tree") .. (value and (" " .. value) or ""))
    end, "BST: demo, insert N, delete N, find N, clear, tree", 0)
end
function TreeView:Say(message)
    print("[tree_visualizer] " .. message)
    GameRules:SendCustomMessage("BST: " .. message, 0, 0)
end
function TreeView:Chat(text, playerId)
    local command, rest = text:match("^%-([%a_]+)%s*(.-)%s*$")
    if not command then return end
    if SandboxTools and SandboxTools:Command(command, rest, playerId) then return end
    if command == "big_demo" then
        local size = rest == "" and 75 or tonumber(rest)
        if not size or (rest ~= "" and not rest:match("^%d+$")) or size < 1 or size > 2147483647 then
            self:Say("Usage: -big_demo [positive integer]"); return
        end
        self:Request("big_demo/" .. size); return
    end
    local simple = {demo="demo", clear="clear", tree="state"}
    if simple[command] and rest == "" then
        -- Pending deaths are acknowledged by their batch before this state request.
        self:Request(simple[command]); return
    end
    if command == "insert" or command == "delete" or command == "find" then
        local value = tonumber(rest)
        if not rest:match("^%-?%d+$") or not value or value < -2147483648 or value > 2147483647 then
            self:Say("Use an int32 integer, e.g. -insert 42"); return
        end
        self:Request(command .. "/" .. string.format("%.0f", value)); return
    end
    if command == "help" then self:Say("-demo | -big_demo [N] | -insert N | -delete N | -find N | -clear | -tree | -gold [N] | -lvlup [N] | -refresh | -change_hero pudge | -clean") end
end
-- Explicit commands close the current death batch to preserve command order.
function TreeView:Request(endpoint)
    if endpoint == "state" and self.failedDeaths then
        for key in pairs(self.failedDeaths) do self:QueueDeath(key) end
        self.failedDeaths = nil
    end
    if self.openDeathBatch then self.openDeathBatch.ready = true; self.openDeathBatch = nil end
    if #self.queue >= 128 then self:Say("Queue full; wait a moment"); return end
    table.insert(self.queue, {endpoint=endpoint, ready=true})
    self:Next()
end
function TreeView:Next()
    if self.busy or #self.queue == 0 or not self.queue[1].ready then return end
    self.busy = true
    local operation = table.remove(self.queue, 1)
    if self.openDeathBatch == operation then self.openDeathBatch = nil end
    local ok, err = pcall(function()
        local request = CreateHTTPRequestScriptVM(operation.keys and "POST" or "GET",
            "http://127.0.0.1:8765/" .. operation.endpoint)
        if not request then self:FileRequest(operation); return end
        if operation.keys then request:SetHTTPRequestRawPostBody("text/plain", table.concat(operation.keys, " ")) end
        request:SetHTTPRequestAbsoluteTimeoutMS(10000)
        request:Send(function(response)
            self:Finish(operation, response.StatusCode == 200 and response.Body or nil,
                "HTTP " .. tostring(response.StatusCode))
        end)
    end)
    if not ok then self:Finish(operation, nil, tostring(err)) end
end
function TreeView:Finish(operation, body, err)
    if body then
        local ok, renderError = pcall(function() self:Complete(operation, body) end)
        if not ok then self:Say("Render error: " .. tostring(renderError)) end
    else
        -- Retry killed keys on the next explicit -tree, without an endless retry loop.
        self.failedDeaths = self.failedDeaths or {}
        for _, key in ipairs(operation.keys or {}) do self.failedDeaths[key] = true end
        self:Say("Backend error: " .. tostring(err) .. "; use -tree to retry")
    end
    self.busy = false
    GameRules:GetGameModeEntity():SetContextThink("BSTNext", function() self:Next(); return nil end, 0)
end
function TreeView:RemoveEdge(childKey)
    local edge = self.edges[childKey]
    if not edge then return end
    ParticleManager:DestroyParticle(edge.particle, true)
    ParticleManager:ReleaseParticleIndex(edge.particle)
    if self.incident[edge.parent] then self.incident[edge.parent][childKey] = nil end
    if self.incident[childKey] then self.incident[childKey][childKey] = nil end
    self.edges[childKey] = nil
end
function TreeView:Render(body)
    local count, status = body:match("^BST1 (%d+) ([%w_]+)")
    if not count then error("Invalid server response") end
    count = tonumber(count)
    local nodes, alive = {}, {}
    for key, parent, rank, depth, mark in body:gmatch("\n(%-?%d+) ([%w%-]+) (%d+) (%d+) (%d+)") do
        table.insert(nodes, {key=key, parent=parent, rank=tonumber(rank), depth=tonumber(depth), mark=mark=="1"})
        alive[key] = true
    end
    if #nodes ~= count then error("Incomplete tree response") end
    local spacing = math.min(190, 3200 / math.max(1, count - 1))
    local scale = math.max(0.24, math.min(0.7, spacing / 190 * 0.7))
    for _, node in ipairs(nodes) do
        if not self.pendingDeaths[node.key] then
            local pos = self.origin + Vector((node.rank - (count - 1)/2)*spacing, -node.depth*230, 0)
            pos.z = GetGroundHeight(pos, nil) + 100
            local unit, old = self.units[node.key], self.visual[node.key]
            if not unit or unit:IsNull() or not unit:IsAlive() then
                if unit and not unit:IsNull() then UTIL_Remove(unit) end
                unit = CreateUnitByName("npc_tree_node", pos, false, nil, nil, DOTA_TEAM_BADGUYS)
                if not unit then error("Cannot create npc_tree_node") end
                unit.bstKey = node.key; self.units[node.key] = unit; old = nil
            end
            if not old or old.scale ~= scale then unit:SetModelScale(scale) end
            if not old or old.x ~= pos.x or old.y ~= pos.y or old.z ~= pos.z then unit:SetAbsOrigin(pos) end
            if not old or old.mark ~= node.mark then
                unit:SetCustomHealthLabel(node.key, node.mark and 255 or 120, 230, node.mark and 40 or 255)
                unit:SetRenderColor(node.mark and 255 or 150, node.mark and 200 or 220, node.mark and 40 or 255)
            end
            self.visual[node.key] = {x=pos.x, y=pos.y, z=pos.z, scale=scale, mark=node.mark}
        end
    end
    local desired = {}
    for _, node in ipairs(nodes) do
        if node.parent ~= "none" then
            local child, parent = self.units[node.key], self.units[node.parent]
            if child and parent and not child:IsNull() and not parent:IsNull() and child:IsAlive() and parent:IsAlive() then
                desired[node.key] = {parent=node.parent, source=parent, target=child}
            end
        end
    end
    local removed, created = 0, 0
    for key, edge in pairs(self.edges) do
        local wanted = desired[key]
        if not wanted or edge.parent ~= wanted.parent or edge.source ~= wanted.source or edge.target ~= wanted.target then
            self:RemoveEdge(key); removed = removed + 1
        end
    end
    for key, wanted in pairs(desired) do
        if not self.edges[key] then
            local p = ParticleManager:CreateParticle("particles/units/heroes/hero_wisp/wisp_tether.vpcf", PATTACH_CUSTOMORIGIN, nil)
            ParticleManager:SetParticleControlEnt(p, 0, wanted.source, PATTACH_POINT_FOLLOW, "attach_hitloc", wanted.source:GetAbsOrigin(), true)
            ParticleManager:SetParticleControlEnt(p, 1, wanted.target, PATTACH_POINT_FOLLOW, "attach_hitloc", wanted.target:GetAbsOrigin(), true)
            wanted.particle = p; self.edges[key] = wanted
            self.incident[wanted.parent] = self.incident[wanted.parent] or {}; self.incident[wanted.parent][key] = true
            self.incident[key] = self.incident[key] or {}; self.incident[key][key] = true
            created = created + 1
        end
    end
    for key, unit in pairs(self.units) do
        if not alive[key] then
            if not unit:IsNull() then UTIL_Remove(unit) end
            self.units[key] = nil; self.pendingDeaths[key] = nil; self.visual[key] = nil
        end
    end
    print("[tree_visualizer] Render nodes=" .. count .. " edges_added=" .. created .. " edges_removed=" .. removed)
    self:Say(status .. "; nodes=" .. count)
end
function TreeView:FileRequest(operation)
    self.sequence = self.sequence + 1
    local id = self.session .. "_" .. tostring(self.sequence)
    if operation.keys then
        print("[BST_BATCH_BEGIN] " .. id .. " " .. #operation.keys)
        -- Short log records avoid engine console line truncation, but form ONE HTTP POST.
        for start = 1, #operation.keys, 64 do
            print("[BST_BATCH_PART] " .. id .. " " .. table.concat(operation.keys, ",", start, math.min(start + 63, #operation.keys)))
        end
        print("[BST_BATCH_END] " .. id)
    else print("[BST_REQUEST] " .. id .. " " .. operation.endpoint) end
    local deadline = Time() + 10
    GameRules:GetGameModeEntity():SetContextThink("BSTBridge", function()
        local response = LoadKeyValues("scripts/npc/tree_response.txt")
        if response and response.id == id then
            local body = nil
            if not response.error then
                local lines = {"BST1 " .. response.count .. " " .. response.status}
                for _, row in pairs(response.rows or {}) do lines[#lines+1] = row end
                body = table.concat(lines, "\n") .. "\n"
            end
            self:Finish(operation, body, response.error)
            return nil
        end
        if Time() > deadline then self:Finish(operation, nil, "Bridge timeout"); return nil end
        return 0.03
    end, 0.03)
end
function TreeView:NodeKilled(unit)
    local key = unit.bstKey
    if key and self.units[key] == unit then self:DeleteDeadKey(key) end
end
function TreeView:DeleteDeadKey(key)
    if self.pendingDeaths[key] then return end
    self.pendingDeaths[key] = true
    local incident = self.incident[key] or {}
    local remove = {}; for child in pairs(incident) do remove[#remove+1] = child end
    for _, child in ipairs(remove) do self:RemoveEdge(child) end
    self:QueueDeath(key)
end
function TreeView:QueueDeath(key)
    local batch = self.openDeathBatch
    if not batch then
        batch = {endpoint="delete_many", keys={}, ready=false}
        self.openDeathBatch = batch; table.insert(self.queue, batch)
        GameRules:GetGameModeEntity():SetContextThink("BSTDeathBatch", function()
            batch.ready = true
            if self.openDeathBatch == batch then self.openDeathBatch = nil end
            self:Next(); return nil
        end, 0.08)
    end
    batch.keys[#batch.keys+1] = key
end
function TreeView:Complete(operation, body)
    if operation.keys then
        for _, key in ipairs(operation.keys) do self.pendingDeaths[key] = nil end
        print("[tree_visualizer] Batch acknowledged: " .. #operation.keys .. " keys")
    else
        local key = operation.endpoint:match("^delete/(%-?%d+)$")
        if key then self.pendingDeaths[key] = nil end
    end
    self:Render(body)
end
