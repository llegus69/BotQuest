-- ============================================================
--  BotQuest_EliteLootExtension.lua
--  Extensión modular de loot para misiones Élites
--  NO MODIFICA EL NÚCLEO ORIGINAL DE BOTQUEST
-- ============================================================

local originalAddItem = nil
local originalSendBroadcastMessage = nil
local methodsHooked = false

local BQ_EliteMissions = {}
local BQ_ActiveEliteReward = {}

-- Función auxiliar para asegurar que la llamada provenga del sistema BotQuest
local function IsCalledFromBotQuest()
    local i = 2
    while true do
        local info = debug.getinfo(i, "S")
        if not info then break end
        if info.source and info.source:find("BotQuest_Server.lua") then
            return true
        end
        i = i + 1
    end
    return false
end

-- Busca un ítem aleatorio en item_template respetando las restricciones del core
local function GetRandomEliteItem(level, targetQuality)
    local lo, hi = 1, 80
    local LEVEL_RANGES = {
        {1,10}, {11,20}, {21,30}, {31,40},
        {41,50}, {51,60}, {61,70}, {71,80}
    }
    for _, r in ipairs(LEVEL_RANGES) do
        if level >= r[1] and level <= r[2] then
            lo, hi = r[1], r[2]
            break
        end
    end

    -- Query adaptada de los filtros originales de BotQuest
    local query = string.format([[
        SELECT entry, name FROM item_template 
        WHERE Quality = %d AND class IN (2, 4) AND ItemLevel >= 5
          AND ((RequiredLevel >= %d AND RequiredLevel <= %d) OR (RequiredLevel = 0 AND ItemLevel BETWEEN %d AND %d))
          AND (flags & 526336) = 0 AND (flagsExtra & 3) = 0 AND bonding IN (0,2,3)
          AND NOT (class=2 AND subclass IN (0,11,12,13,14))
        ORDER BY RAND() LIMIT 1
    ]], targetQuality, lo, hi, math.floor(lo*1.2), math.floor(hi*1.5))

    local res = WorldDBQuery(query)
    if res then
        return res:GetUInt32(0), res:GetString(1)
    end

    -- Búsqueda de respaldo general si el rango por nivel es demasiado estricto
    local fallbackQuery = string.format([[
        SELECT entry, name FROM item_template 
        WHERE Quality = %d AND class IN (2, 4) AND RequiredLevel <= %d
        ORDER BY RAND() LIMIT 1
    ]], targetQuality, level)
    
    local res2 = WorldDBQuery(fallbackQuery)
    if res2 then
        return res2:GetUInt32(0), res2:GetString(1)
    end

    -- Ítems por defecto definitivos en caso de bases de datos vacías
    if targetQuality == 4 then
        return 16863, "Yelmo de cenizas"
    else
        return 16862, "Botas de fango"
    end
end

-- Función interna para inyectar los ganchos (hooks) de forma segura usando un puntero real
local function HookPlayerMethods(player)
    if methodsHooked then return end
    
    local PlayerMeta = getmetatable(player)
    if not PlayerMeta then return end

    originalAddItem = PlayerMeta.AddItem
    originalSendBroadcastMessage = PlayerMeta.SendBroadcastMessage

    -- Interceptamos el método AddItem nativo de Eluna
    PlayerMeta.AddItem = function(self, itemId, count, ...)
        local guid = self:GetGUIDLow()
        
        if BQ_EliteMissions[guid] and IsCalledFromBotQuest() then
            local currentLevel = self:GetLevel()
            local targetQuality = (currentLevel >= 55) and 4 or 3 
            
            local newItemId, newItemName = GetRandomEliteItem(currentLevel, targetQuality)
            
            BQ_ActiveEliteReward[guid] = {
                id = newItemId,
                name = newItemName,
                quality = targetQuality
            }
            
            return originalAddItem(self, newItemId, count, ...)
        end
        return originalAddItem(self, itemId, count, ...)
    end

    -- Interceptamos los mensajes de chat/addon para sincronizar la interfaz
    PlayerMeta.SendBroadcastMessage = function(self, msg, ...)
        local guid = self:GetGUIDLow()
        local reward = BQ_ActiveEliteReward[guid]
        
        if reward and IsCalledFromBotQuest() then
            if msg:find("Item:") then
                local qColors = { [3] = "|cff0070dd", [4] = "|cffa335ee" }
                local qNames  = { [3] = "Raro", [4] = "Épico" }
                local color = qColors[reward.quality] or "|cffffffff"
                local name = qNames[reward.quality] or ""
                msg = string.format("  |cffffcc00Item:|r %s[%s]|r  |cff888888(%s)|r", color, reward.name, name)
            
            elseif msg:find("BQST:COMPLETE") then
                local parts = {}
                for token in msg:gmatch("[^\t]+") do 
                    parts[#parts+1] = token 
                end
                if #parts >= 6 then
                    parts[4] = tostring(reward.id)
                    parts[5] = tostring(reward.quality)
                    parts[6] = reward.name
                    msg = table.concat(parts, "\t")
                end
                
                BQ_ActiveEliteReward[guid] = nil
                BQ_EliteMissions[guid] = nil
            end
        else
            if IsCalledFromBotQuest() and (msg:find("BQST:FAIL") or msg:find("Misión fallida")) then
                BQ_EliteMissions[guid] = nil
                BQ_ActiveEliteReward[guid] = nil
            end
        end
        
        return originalSendBroadcastMessage(self, msg, ...)
    end

    methodsHooked = true
    print("[BotQuest Extension] Métodos globales de Player interceptados con éxito.")
end

-- Registramos un evento de chat en paralelo para detectar cuándo inicia una misión Élite
local function BQ_Elite_OnPlayerChat(event, player, msg, msgType, lang)
    -- Asegurar el enganche si no se hizo en el login
    HookPlayerMethods(player)

    if msg:sub(1, 5) ~= "BQST:" then return end
    
    local parts = {}
    for token in msg:sub(6):gmatch("[^\t]+") do 
        parts[#parts+1] = token 
    end
    if #parts == 0 then return end

    if parts[1] == "START" and parts[7] == "ELITE" then
        local guid = player:GetGUIDLow()
        BQ_EliteMissions[guid] = true
    elseif parts[1] == "CANCEL" then
        local guid = player:GetGUIDLow()
        BQ_EliteMissions[guid] = nil
    end
end
RegisterPlayerEvent(18, BQ_Elite_OnPlayerChat)

-- Forzar enganche inmediato en cuanto un jugador conecte al mundo
RegisterPlayerEvent(3, function(event, player)
    HookPlayerMethods(player)
end)

print("[BotQuest Extension] Módulo de recompensas Élites cargado (A la espera del primer jugador).")