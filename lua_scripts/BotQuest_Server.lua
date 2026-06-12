-- ============================================================
--  BotQuest_Server.lua  v1.3.2  (Eluna — AzerothCore + NPCBots)
--
--  NOVEDADES v1.3.2:
--  · ¡Integración con estadísticas de equipo (Pseudo-GS)! Ahora el Poder
--    del grupo lee los atributos de characters_npcbot_stats de tu AddOn.
-- ============================================================

local COMM_PREFIX = "BQST"

-- ============================================================
--  CONFIGURACIÓN GENERAL
-- ============================================================
local CFG = {
    QUALITIES              = { 1, 2, 3 },
    ITEM_CLASSES           = { 2, 4 },
    ARMOR_SUBCLASS_EXCLUDE = { 0, 11, 12, 13, 14 },
    WEAPON_SUBCLASS_EXCLUDE= {},
    FLAG_BLACKLIST         = 2048 + 524288,
    FLAGS_EXTRA_BLACKLIST  = 3,
    MIN_ITEM_LEVEL         = 5,
    MAX_PER_POOL           = 300,
    LEVEL_RANGES = {
        [1]={1,10}, [2]={11,20}, [3]={21,30}, [4]={31,40},
        [5]={41,50},[6]={51,60}, [7]={61,70}, [8]={71,80},
    },

    BASE_SUCCESS = { EASY = 0.55, NORMAL = 0.40, HARD = 0.25, ELITE = 0.10 },
    POWER_PER_POINT = 0.02,
    MAX_SUCCESS = 0.95,
    MIN_SUCCESS = 0.05,

    FAIL_COOLDOWN_SECS = { EASY = 120, NORMAL = 300, HARD = 600, ELITE = 1200 },

    CLASS_ROLE_WEIGHT = {
        [1]=1.3, [2]=1.5, [3]=1.0, [4]=1.1, [5]=1.4,
        [6]=1.3, [7]=1.4, [8]=1.0, [9]=1.0, [11]=1.5,
    },
    DEFAULT_ROLE_WEIGHT = 1.0,
    COMPOSITION_BONUS = 3.0,
}

local ItemPools          = {}
local ItemPoolsByQuality = {}
local PoolsReady         = false
local QUALITY_WEIGHTS = { [1]=50, [2]=35, [3]=15 }
local QUALITY_COLOR   = { [1]="|cffffffff", [2]="|cff1eff00", [3]="|cff0070dd" }
local QUALITY_NAME    = { [1]="Común", [2]="Poco común", [3]="Raro" }
local FailCooldowns = {}
local ActiveMissions = {}

BOT_TABLE_NAME = nil   
BOT_OWNER_COL  = nil   

-- ============================================================
--  CARGA DE ITEMS DESDE BD
-- ============================================================
local function BuildSubclassExclusion(cls, list)
    if #list == 0 then return "" end
    return string.format(" AND NOT (class=%d AND subclass IN (%s))", cls, table.concat(list, ","))
end

local function LoadItemPool(idx)
    local range  = CFG.LEVEL_RANGES[idx]
    if not range then return end
    local lo, hi = range[1], range[2]

    local query = string.format([[
        SELECT entry, name, Quality FROM item_template
        WHERE Quality IN (%s) AND class IN (%s) AND ItemLevel >= %d
          AND ((RequiredLevel >= %d AND RequiredLevel <= %d) OR (RequiredLevel = 0 AND ItemLevel BETWEEN %d AND %d))
          AND (flags & %d) = 0 AND (flagsExtra & %d) = 0 AND bonding IN (0,2,3) %s %s
        ORDER BY RAND() LIMIT %d
    ]], table.concat(CFG.QUALITIES, ","), table.concat(CFG.ITEM_CLASSES, ","), CFG.MIN_ITEM_LEVEL, lo, hi, math.floor(lo*1.2), math.floor(hi*1.5), CFG.FLAG_BLACKLIST, CFG.FLAGS_EXTRA_BLACKLIST, BuildSubclassExclusion(2, CFG.ARMOR_SUBCLASS_EXCLUDE), BuildSubclassExclusion(4, CFG.WEAPON_SUBCLASS_EXCLUDE), CFG.MAX_PER_POOL)

    local res = WorldDBQuery(query)
    local pool, byQ = {}, {}
    if res then
        repeat
            local entry   = res:GetUInt32(0)
            local name    = res:GetString(1)
            local quality = res:GetUInt8(2)
            pool[#pool+1] = { id=entry, name=name, quality=quality }
            byQ[quality]  = byQ[quality] or {}
            byQ[quality][#byQ[quality]+1] = entry
        until not res:NextRow()
    end
    ItemPools[idx], ItemPoolsByQuality[idx] = pool, byQ
    print(string.format("[BotQuest] Pool %d (lvl %d-%d): %d items cargados.", idx, lo, hi, #pool))
end

local function LoadAllItemPools()
    print("[BotQuest] Cargando pools de items...")
    for i = 1, #CFG.LEVEL_RANGES do LoadItemPool(i) end
    PoolsReady = true
    print("[BotQuest] Pools listos.")
end

-- ============================================================
--  SELECCIÓN DE ITEM ALEATORIO
-- ============================================================
local function GetRangeIndex(level)
    for idx, r in ipairs(CFG.LEVEL_RANGES) do if level >= r[1] and level <= r[2] then return idx end end
    return 8
end

local function PickQuality()
    local total, acc = 0, 0
    for _,q in ipairs(CFG.QUALITIES) do total = total + (QUALITY_WEIGHTS[q] or 0) end
    local roll = math.random(1, total)
    for _,q in ipairs(CFG.QUALITIES) do acc = acc + (QUALITY_WEIGHTS[q] or 0); if roll <= acc then return q end end
    return CFG.QUALITIES[1]
end

local function PickRandomItemForLevel(level)
    local idx  = GetRangeIndex(level)
    local byQ  = ItemPoolsByQuality[idx]
    if not byQ or not next(byQ) then return 6256, "Tela de lino", 1 end

    local itemId, itemName, quality
    for _ = 1, 3 do
        local q    = PickQuality()
        local pool = byQ[q]
        if pool and #pool > 0 then
            itemId, quality = pool[math.random(1, #pool)], q
            for _, item in ipairs(ItemPools[idx]) do if item.id == itemId then itemName = item.name; break end end
            break
        end
    end
    if not itemId then
        local p = ItemPools[idx]
        local x = p[math.random(1,#p)]
        itemId, itemName, quality = x.id, x.name, x.quality
    end
    return itemId, itemName or "Desconocido", quality or 1
end

-- ============================================================
--  SISTEMA DE PODER Y EXTRACCIÓN DE LOGS (MODIFICADO CON GS)
-- ============================================================
local function GetBotNamesString(player)
    local names = {}
    if player.GetNPCBots then
        local bots = player:GetNPCBots()
        if bots then for _, bot in ipairs(bots) do table.insert(names, bot:GetName()) end end
    else
        local guidLow = player:GetGUIDLow()
        if BOT_TABLE_NAME and BOT_TABLE_NAME ~= "NOT_FOUND" and BOT_OWNER_COL then
            local query = string.format("SELECT entry FROM %s WHERE %s = %d", BOT_TABLE_NAME, BOT_OWNER_COL, guidLow)
            local res = CharDBQuery(query)
            if res then
                repeat
                    local entry = res:GetUInt32(0)
                    local infoQ = WorldDBQuery(string.format("SELECT name FROM creature_template WHERE entry = %d LIMIT 1", entry))
                    if infoQ then table.insert(names, infoQ:GetString(0)) end
                until not res:NextRow()
            end
        end
    end
    return #names == 0 and "Ninguno" or table.concat(names, ",")
end

local function CalculateGroupPower(player)
    local power, details, hasTank, hasHealer, botCount = 0, {}, false, false, 0
    local TANK_CLASSES   = { [1]=true, [2]=true, [6]=true, [11]=true }
    local HEALER_CLASSES = { [2]=true, [5]=true, [7]=true, [11]=true }
    local guidLow = player:GetGUIDLow()

    -- Asegurar detección de tablas de bots
    if not BOT_TABLE_NAME then
        local candidates = { "npcbots", "characters_npcbots", "character_npcbot", "characters_npcbot" }
        for _, tbl in ipairs(candidates) do
            local check = CharDBQuery(string.format("SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = '%s' LIMIT 1", tbl))
            if check then BOT_TABLE_NAME = tbl; break end
        end
        if not BOT_TABLE_NAME then BOT_TABLE_NAME = "NOT_FOUND" end
    end

    if BOT_TABLE_NAME ~= "NOT_FOUND" and not BOT_OWNER_COL then
        local colCheck = CharDBQuery(string.format("SELECT column_name FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = '%s' AND column_name IN ('guid','owner') LIMIT 1", BOT_TABLE_NAME))
        BOT_OWNER_COL = colCheck and colCheck:GetString(0) or "guid"
    end

    -- 1) RECOPILAR LAS ENTRADAS (ENTRIES) DE LOS BOTS CONTRATADOS
    local botEntries = {}
    if player.GetNPCBots then
        local bots = player:GetNPCBots()
        if bots then
            for _, bot in ipairs(bots) do
                botEntries[bot:GetEntry()] = true
            end
        end
    else
        if BOT_TABLE_NAME ~= "NOT_FOUND" and BOT_OWNER_COL then
            local query = string.format("SELECT entry FROM %s WHERE %s = %d", BOT_TABLE_NAME, BOT_OWNER_COL, guidLow)
            local res = CharDBQuery(query)
            if res then
                repeat
                    local entry = res:GetUInt32(0)
                    botEntries[entry] = true
                until not res:NextRow()
            end
        end
    end

    -- 2) CONSULTAR LA BASE DE DATOS DE ESTADÍSTICAS (BOTSTATS) PARA ESOS BOTS
    local botGearBonus = {}
    if next(botEntries) then
        local entryList = {}
        for entry, _ in pairs(botEntries) do table.insert(entryList, entry) end
        
        local statsQuery = CharDBQuery(string.format([[
            SELECT entry, attackPower, spellPower, stamina 
            FROM characters_npcbot_stats 
            WHERE entry IN (%s)
        ]], table.concat(entryList, ",")))

        if statsQuery then
            repeat
                local entry = statsQuery:GetUInt32(0)
                local ap    = statsQuery:GetUInt32(1) or 0
                local sp    = statsQuery:GetUInt32(2) or 0
                local sta   = statsQuery:GetUInt32(3) or 0

                -- Fórmula adaptada para calcular el valor de equipo (Pseudo-GS)
                -- Puedes ajustar el divisor (600) si quieres que el equipo influya más o menos
                local gearValue = (ap + (sp * 1.5) + (sta * 10)) / 600
                botGearBonus[entry] = math.max(0, gearValue)
            until not statsQuery:NextRow()
        end
    end

    -- 3) CÁLCULO FINAL DE PODER (EN VIVO O POR BASE DE DATOS)
    if player.GetNPCBots then
        local bots = player:GetNPCBots()
        if bots then
            for _, bot in ipairs(bots) do
                botCount = botCount + 1
                local cls, lvl = bot:GetClass(), bot:GetLevel()
                local entry = bot:GetEntry()
                local weight = CFG.CLASS_ROLE_WEIGHT[cls] or CFG.DEFAULT_ROLE_WEIGHT
                local levelFactor = math.max(0.5, lvl / player:GetLevel())
                
                -- Contribución Base
                local contribution = weight * levelFactor

                -- Sumar bonificador de equipo (GS) si existe información de estadísticas
                if botGearBonus[entry] then
                    contribution = contribution + botGearBonus[entry]
                end

                power = power + contribution
                if TANK_CLASSES[cls] then hasTank = true end
                if HEALER_CLASSES[cls] then hasHealer = true end
                details[#details+1] = { class=cls, level=lvl, weight=weight, levelFactor=levelFactor, contribution=contribution }
            end
        end
    else
        if BOT_TABLE_NAME ~= "NOT_FOUND" and BOT_OWNER_COL then
            local query = string.format("SELECT entry FROM %s WHERE %s = %d", BOT_TABLE_NAME, BOT_OWNER_COL, guidLow)
            local res = CharDBQuery(query)
            if res then
                repeat
                    botCount = botCount + 1
                    local entry = res:GetUInt32(0)
                    local infoQ = WorldDBQuery(string.format("SELECT unit_class, minlevel FROM creature_template WHERE entry = %d LIMIT 1", entry))
                    if infoQ then
                        local cls, lvl = infoQ:GetUInt8(0), infoQ:GetUInt8(1)
                        local weight = CFG.CLASS_ROLE_WEIGHT[cls] or CFG.DEFAULT_ROLE_WEIGHT
                        local levelFactor = math.max(0.5, lvl / player:GetLevel())
                        
                        -- Contribución Base
                        local contribution = weight * levelFactor

                        -- Sumar bonificador de equipo (GS) si existe información de estadísticas
                        if botGearBonus[entry] then
                            contribution = contribution + botGearBonus[entry]
                        end

                        power = power + contribution
                        if TANK_CLASSES[cls] then hasTank = true end
                        if HEALER_CLASSES[cls] then hasHealer = true end
                    end
                until not res:NextRow()
            end
        end
    end

    if hasTank and hasHealer and botCount >= 2 then power = power + CFG.COMPOSITION_BONUS end
    return power, details, hasTank, hasHealer, botCount
end

local function CalculateSuccessChance(power, difficulty)
    local base = CFG.BASE_SUCCESS[difficulty] or 0.30
    local bonus = power * CFG.POWER_PER_POINT
    return math.max(CFG.MIN_SUCCESS, math.min(CFG.MAX_SUCCESS, base + bonus))
end

local function RollSuccess(chance) return math.random() <= chance end

local function SetFailCooldown(guid, difficulty)
    local secs = CFG.FAIL_COOLDOWN_SECS[difficulty] or 300
    FailCooldowns[guid] = os.time() + secs
    return secs
end

local function GetRemainingCooldown(guid)
    local expiry = FailCooldowns[guid]
    if not expiry then return 0 end
    local remaining = expiry - os.time()
    if remaining <= 0 then FailCooldowns[guid] = nil; return 0 end
    return remaining
end

local function ParsePayload(msg)
    local parts = {}
    for token in msg:gmatch("[^	]+") do parts[#parts+1] = token end
    return parts
end

local function BuildPayload(...) return table.concat({...}, "	") end
local function HidePlayerBots(player) player:SendBroadcastMessage("|cff00ccff[BotQuest]|r Tus bots parten en misión...") end
local function UnhidePlayerBots(player) player:SendBroadcastMessage("|cff00ff00[BotQuest]|r ¡Tus bots han regresado!") end

-- ============================================================
--  ENTREGAR RECOMPENSAS
-- ============================================================
local function DeliverRewards(player, questId, goldMin, goldMax, botsStr, chance)
    local gold = math.random(tonumber(goldMin), tonumber(goldMax))
    player:ModifyMoney(gold)

    local isPvP = false
    local honorAmount = 0
    local chancePct = string.format("%.0f", (chance or 0) * 100)

    if BotQuestData and BotQuestData.QUESTS then
        for _, q in ipairs(BotQuestData.QUESTS) do
            if q.id == questId then
                if q.isPvP then isPvP = true; honorAmount = q.honorPoints or 0 end
                break
            end
        end
    end

    if isPvP then
        if honorAmount > 0 then
            if player.ModifyHonor then player:ModifyHonor(honorAmount) else player:SetHonor(player:GetHonor() + honorAmount) end
        end

        player:SendBroadcastMessage("|cff00ff00[BotQuest]|r ¡Misión completada!")
        player:SendBroadcastMessage(string.format("  |cffffcc00Oro:|r +%dg %dp %dc", math.floor(gold/10000), math.floor((gold%10000)/100), gold%100))
        player:SendBroadcastMessage(string.format("  |cffcc0000Honor:|r +%d puntos", honorAmount))

        local payload = BuildPayload("COMPLETE", questId, tostring(gold), "0", "1", honorAmount .. " Puntos de Honor", botsStr, chancePct)
        player:SendBroadcastMessage("BQST:" .. payload)
    else
        local level = player:GetLevel()
        local itemId, itemName, quality = PickRandomItemForLevel(level)
        player:AddItem(itemId, 1)

        local qColor = QUALITY_COLOR[quality] or "|cffffffff"
        local qName  = QUALITY_NAME[quality]  or ""

        player:SendBroadcastMessage("|cff00ff00[BotQuest]|r ¡Misión completada!")
        player:SendBroadcastMessage(string.format("  |cffffcc00Oro:|r +%dg %dp %dc", math.floor(gold/10000), math.floor((gold%10000)/100), gold%100))
        player:SendBroadcastMessage(string.format("  |cffffcc00Item:|r %s[%s]|r  |cff888888(%s)|r", qColor, itemName, qName))

        local payload = BuildPayload("COMPLETE", questId, tostring(gold), tostring(itemId), tostring(quality), itemName, botsStr, chancePct)
        player:SendBroadcastMessage("BQST:" .. payload)
    end
end

-- ============================================================
--  RESOLVER MISIÓN
-- ============================================================
local function ResolveMission(player, mission)
    local guid = tostring(player:GetGUIDLow())
    local botsStr = GetBotNamesString(player)
    local power, details, hasTank, hasHealer, botCount = CalculateGroupPower(player)
    local chance = CalculateSuccessChance(power, mission.difficulty)
    local success = RollSuccess(chance)

    print(string.format("[BotQuest] Resolución '%s' | %s | Bots:%d Poder:%.1f Prob:%.0f%% → %s", mission.questId, player:GetName(), botCount, power, chance * 100, success and "ÉXITO" or "FALLO"))
    UnhidePlayerBots(player)

    if success then
        DeliverRewards(player, mission.questId, mission.goldMin, mission.goldMax, botsStr, chance)
        local summaryPayload = BuildPayload("POWER_REPORT", tostring(botCount), string.format("%.1f", power), string.format("%.0f", chance * 100), hasTank and "1" or "0", hasHealer and "1" or "0")
        player:SendBroadcastMessage("BQST:" .. summaryPayload)
    else
        local cooldownSecs = SetFailCooldown(guid, mission.difficulty)
        player:SendBroadcastMessage("|cffff4444[BotQuest]|r ¡Misión fallida! Tus bots regresan derrotados.")
        player:SendBroadcastMessage(string.format("|cffff8800[BotQuest]|r Cooldown de penalización: |cffffffff%d min|r.", math.ceil(cooldownSecs / 60)))

        local failPayload = BuildPayload("FAIL", "DEFEAT", tostring(cooldownSecs), string.format("%.0f", chance * 100), tostring(botCount), string.format("%.1f", power), botsStr)
        player:SendBroadcastMessage("BQST:" .. failPayload)
    end
    ActiveMissions[guid] = nil
end

-- ============================================================
--  INICIAR MISIÓN Y COMUNICACIÓN
-- ============================================================
local function StartMission(player, parts)
    if #parts < 7 then return end
    local guid       = tostring(player:GetGUIDLow())
    local questId    = parts[2]
    local duration   = math.max(30, math.min(tonumber(parts[4]) or 300, 3600))
    local goldMin    = tonumber(parts[5]) or 100
    local goldMax    = tonumber(parts[6]) or 500
    local difficulty = parts[7] or "NORMAL"

    local cd = GetRemainingCooldown(guid)
    if cd > 0 then
        player:SendBroadcastMessage(string.format("|cffff4444[BotQuest]|r Bots recuperándose. Restante: |cffffffff%d min %d s|r.", math.floor(cd/60), cd%60))
        player:SendBroadcastMessage("BQST:" .. BuildPayload("COOLDOWN", tostring(cd)))
        return
    end

    local power, _, hasTank, hasHealer, botCount = CalculateGroupPower(player)
    local chance = CalculateSuccessChance(power, difficulty)

    if ActiveMissions[guid] then ActiveMissions[guid].cancelled = true end
    HidePlayerBots(player)

    local compBonus = (hasTank and hasHealer and botCount >= 2) and " |cff00ff00[Bonus composición activo]|r" or ""
    player:SendBroadcastMessage(string.format("|cff00ccff[BotQuest]|r Grupo: |cffffffff%d bots|r | Poder: |cffffcc00%.1f|r | Probabilidad: |cffffcc00%.0f%%|r%s", botCount, power, chance * 100, compBonus))

    ActiveMissions[guid] = { questId = questId, difficulty = difficulty, endTime = os.time() + duration, goldMin = goldMin, goldMax = goldMax, cancelled  = false }

    local capturedGuid, fullGuid = guid, player:GetGUID()
    CreateLuaEvent(function()
        local mission = ActiveMissions[capturedGuid]
        if not mission or mission.cancelled or mission.questId ~= questId then return end
        local p = GetPlayerByGUID(fullGuid)
        if p then ResolveMission(p, mission) else ActiveMissions[capturedGuid] = nil end
    end, duration * 1000, 1)
end

local function CancelMission(player)
    local guid = tostring(player:GetGUIDLow())
    if ActiveMissions[guid] then
        ActiveMissions[guid].cancelled = true
        ActiveMissions[guid] = nil
        UnhidePlayerBots(player)
        player:SendBroadcastMessage("|cffff8800[BotQuest]|r Misión cancelada. Sin recompensa.")
        player:SendBroadcastMessage("BQST:" .. BuildPayload("FAIL","CANCELLED","0","0","0","0","Ninguno"))
    end
end

local function QueryPower(player, parts)
    local difficulty = parts[2] or "NORMAL"
    local power, _, hasTank, hasHealer, botCount = CalculateGroupPower(player)
    local chance = CalculateSuccessChance(power, difficulty)
    local cd     = GetRemainingCooldown(tostring(player:GetGUIDLow()))

    local payload = BuildPayload("POWER_QUERY", tostring(botCount), string.format("%.1f", power), string.format("%.0f", chance * 100), hasTank and "1" or "0", hasHealer and "1" or "0", tostring(cd))
    player:SendBroadcastMessage("BQST:" .. payload)
end

local function OnPlayerChat(event, player, msg, msgType, lang)
    if msg:sub(1, 5) ~= "BQST:" then return end
    local parts = ParsePayload(msg:sub(6))
    if #parts == 0 then return false end

    if parts[1] == "START" then if not PoolsReady then player:SendBroadcastMessage("|cffff4444[BotQuest]|r Cargando pools..."); return false end; StartMission(player, parts)
    elseif parts[1] == "CANCEL" then CancelMission(player)
    elseif parts[1] == "QUERY_POWER" then QueryPower(player, parts) end
    return false 
end
RegisterPlayerEvent(18, OnPlayerChat)

local function OnPlayerLogin(event, player)
    local guid = tostring(player:GetGUIDLow())
    local cd = GetRemainingCooldown(guid)
    if cd > 0 then
        player:SendBroadcastMessage(string.format("|cffff8800[BotQuest]|r Cooldown de penalización activo: %d min %d s.", math.floor(cd/60), cd%60))
        player:SendBroadcastMessage("BQST:" .. BuildPayload("COOLDOWN", tostring(cd)))
    end

    local mission = ActiveMissions[guid]
    if not mission or mission.cancelled then return end

    if os.time() >= mission.endTime then
        UnhidePlayerBots(player)
        local chance = CalculateSuccessChance(0, mission.difficulty)
        if RollSuccess(chance) then
            DeliverRewards(player, mission.questId, mission.goldMin, mission.goldMax, "Desconocido (Offline)", chance)
            player:SendBroadcastMessage("|cff00ff00[BotQuest]|r ¡Misión terminada offline! Recompensa en tus mochilas.")
        else
            local secs = SetFailCooldown(guid, mission.difficulty)
            player:SendBroadcastMessage(string.format("|cffff4444[BotQuest]|r Misión fallida offline. Cooldown: %d min.", math.ceil(secs/60)))
            player:SendBroadcastMessage("BQST:" .. BuildPayload("FAIL","DEFEAT",tostring(secs),string.format("%.0f", chance * 100),"0","0","Desconocido (Offline)"))
        end
        ActiveMissions[guid] = nil
    else
        local rem = mission.endTime - os.time()
        player:SendBroadcastMessage(string.format("|cff00ccff[BotQuest]|r Misión en curso — %d min %d s restantes.", math.floor(rem/60), rem%60))
    end
end
RegisterPlayerEvent(3, OnPlayerLogin)

local function OnChat(event, player, msg)
    if not player:IsGM() then return end
    if msg == ".bq reload" then PoolsReady=false; LoadAllItemPools(); return false end
end
RegisterPlayerEvent(18, OnChat)
CreateLuaEvent(function() LoadAllItemPools() end, 3000, 1)

print("[BotQuest] Cargado correctamente con soporte de Pseudo-GS.")