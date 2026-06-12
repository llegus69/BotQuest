-- ============================================================
--  BotQuest_Core.lua  v1.7.1  — Lua puro, sin AceAddon
--  Soporte de persistencia corregido para Cooldowns de misiones
-- ============================================================

local COMM_PREFIX = "BQST"
BotQuestState = {
    active = false, questId = nil, questName = nil, difficulty = nil,
    startTime = nil, duration = nil, elapsed = 0, cooldownExpiry = 0,
    power = { botCount = 0, powerScore = 0, successPct = 0, hasTank = false, hasHealer = false, ready = false }
}
BotQuestDB = BotQuestDB or {}
local tickFrame = nil

local function BQPrint(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[BotQuest]|r " .. tostring(msg)) end
local function BQSendToServer(payload) SendChatMessage("BQST:" .. payload, "SAY") end

-- ============================================================
--  PERSISTENCIA CON HISTORIAL APARTADO
-- ============================================================
local function SaveDB()
    BotQuestDB.activeMission  = BotQuestState.active and {
        questId = BotQuestState.questId, questName = BotQuestState.questName,
        difficulty = BotQuestState.difficulty, startTime = BotQuestState.startTime, duration = BotQuestState.duration
    } or nil
    BotQuestDB.completedTotal = BotQuestDB.completedTotal or 0
    BotQuestDB.failedTotal    = BotQuestDB.failedTotal or 0
    BotQuestDB.goldEarned     = BotQuestDB.goldEarned or 0
    BotQuestDB.cooldownExpiry = BotQuestState.cooldownExpiry
    BotQuestDB.historyLogs    = BotQuestDB.historyLogs or {}
    BotQuestDB.questCooldowns = BotQuestDB.questCooldowns or {}
    BotQuestDB.minimapAngle   = BotQuestDB.minimapAngle or 45
end

local function LoadDB()
    BotQuestDB = BotQuestDB or {}
    BotQuestDB.completedTotal = BotQuestDB.completedTotal or 0
    BotQuestDB.failedTotal    = BotQuestDB.failedTotal or 0
    BotQuestDB.goldEarned     = BotQuestDB.goldEarned or 0
    BotQuestDB.cooldownExpiry = BotQuestDB.cooldownExpiry or 0
    BotQuestDB.historyLogs    = BotQuestDB.historyLogs or {}
    BotQuestDB.questCooldowns = BotQuestDB.questCooldowns or {}
    BotQuestDB.minimapAngle   = BotQuestDB.minimapAngle or 45
    BotQuestState.cooldownExpiry = BotQuestDB.cooldownExpiry
end

local function AddLocalLog(questName, difficulty, success, rewardText, gold, botsStr, successPct)
    local newLog = {
        questName  = questName or "Aventura Desconocida",
        difficulty = difficulty or "NORMAL",
        success    = success,
        rewardText = rewardText or "Ninguna",
        gold       = gold or 0,
        bots       = botsStr or "Ninguno",
        chance     = successPct or 0,
        timeStr    = date("%d/%m %H:%M")
    }
    table.insert(BotQuestDB.historyLogs, 1, newLog)
    if #BotQuestDB.historyLogs > 50 then table.remove(BotQuestDB.historyLogs, 51) end
end

-- ============================================================
--  COOLDOWN Y TIMER
-- ============================================================
local function GetCooldownRemaining() return math.max(0, BotQuestState.cooldownExpiry - time()) end
local function SetCooldown(seconds) BotQuestState.cooldownExpiry = time() + seconds; BotQuestDB.cooldownExpiry = BotQuestState.cooldownExpiry end
local function ClearCooldown() BotQuestState.cooldownExpiry = 0; BotQuestDB.cooldownExpiry = 0 end

local function StopTick() if tickFrame then tickFrame:SetScript("OnUpdate", nil) end end
local function StartTick()
    if not tickFrame then tickFrame = CreateFrame("Frame") end
    local lastTime = 0
    tickFrame:SetScript("OnUpdate", function(self, elapsed)
        lastTime = lastTime + elapsed
        if lastTime < 1 then return end
        lastTime = 0
        if not BotQuestState.active then StopTick(); return end

        BotQuestState.elapsed = time() - BotQuestState.startTime
        local remaining = BotQuestState.duration - BotQuestState.elapsed

        if BotQuestUI then BotQuestUI:UpdateProgressBar() end
        if remaining <= 0 then
            StopTick()
            SendChatMessage(".npcb unhide", "SAY")
            BQPrint("Tiempo completado. Esperando resultado del servidor...")
            if BotQuestUI then BotQuestUI:ShowWaitingResult() end
        end
    end)
end

-- ============================================================
--  ACCIONES PRINCIPALES
-- ============================================================
function BotQuestSendMission(quest)
    if BotQuestState.active then BQPrint("Tus bots ya estan en mision."); return end
    local cd = GetCooldownRemaining()
    if cd > 0 then
        BQPrint(string.format("Cooldown activo: %d min %d s.", math.floor(cd/60), cd%60))
        return
    end

    local payload = table.concat({ "START", quest.id, tostring(UnitLevel("player")), tostring(quest.duration), tostring(quest.goldMin), tostring(quest.goldMax), quest.difficulty }, "\t")
    BQSendToServer(payload)
    SendChatMessage(".npcb hide", "SAY")

    BotQuestState.active = true; BotQuestState.questId = quest.id; BotQuestState.questName = quest.name
    BotQuestState.difficulty = quest.difficulty; BotQuestState.startTime = time()
    BotQuestState.duration = quest.duration; BotQuestState.elapsed = 0

    SaveDB(); StartTick()
    BQPrint(string.format("Mision |cffffcc00%s|r iniciada.", quest.name))
end

function BotQuestQueryPower(difficulty)
    BotQuestState.power.ready = false
    BQSendToServer(table.concat({"QUERY_POWER", difficulty or "NORMAL"}, "\t"))
end

local function OnMissionComplete(gold, itemId, quality, itemName, botsStr, successPct)
    local questName, difficulty = BotQuestState.questName, BotQuestState.difficulty
    StopTick()
    BotQuestDB.completedTotal = (BotQuestDB.completedTotal or 0) + 1
    BotQuestDB.goldEarned     = (BotQuestDB.goldEarned or 0) + (gold or 0)
    BotQuestState.active      = false
    BotQuestState.questId, BotQuestState.questName = nil, nil
    
    local itemText = (itemId and itemId > 0) and ("Ítem: " .. itemName) or "Solo Divisas"
    AddLocalLog(questName, difficulty, true, itemText, gold, botsStr, successPct)
    SaveDB(); ClearCooldown()

    SendChatMessage(".npcb unhide", "SAY")
    PlaySound("QuestCompleted")

    local qColors = {[1]="|cffffffff",[2]="|cff1eff00",[3]="|cff0070dd"}
    BQPrint(string.format("Mision |cffffcc00%s|r completada! Oro: %s", questName or "?", gold and BotQuestData:FormatGold(gold) or "0"))
    if itemId and tonumber(itemId) > 0 then BQPrint("Item: " .. (qColors[quality] or "|cff1eff00") .. "[" .. (itemName or "?") .. "]|r") end

    if BotQuestUI then
        BotQuestUI:ShowCompleteAnimation(questName, gold, itemId, quality, itemName)
        if BotQuestUI.historyPanel and BotQuestUI.historyPanel:IsShown() then BotQuestUI:UpdateHistoryDisplay() end
    end
end

local function OnMissionFail(reason, cdSecs, successPct, botCount, powerScore, botsStr)
    local questName, difficulty = BotQuestState.questName, BotQuestState.difficulty
    StopTick()
    BotQuestDB.failedTotal = (BotQuestDB.failedTotal or 0) + 1
    BotQuestState.active = false
    BotQuestState.questId, BotQuestState.questName = nil, nil

    if reason == "CANCELLED" then
        AddLocalLog(questName, difficulty, false, "Abortada por Jugador", 0, "Ninguno", 0)
        SaveDB(); SendChatMessage(".npcb unhide", "SAY"); BQPrint("Mision cancelada.")
        if BotQuestUI and BotQuestUI.historyPanel and BotQuestUI.historyPanel:IsShown() then BotQuestUI:UpdateHistoryDisplay() end
        return
    end

    AddLocalLog(questName, difficulty, false, "Derrota del Escuadrón", 0, botsStr, successPct)
    if cdSecs and cdSecs > 0 then SetCooldown(cdSecs) end
    SaveDB(); SendChatMessage(".npcb unhide", "SAY")

    PlaySound("igQuestFailed")

    BQPrint(string.format("|cffff4444Mision fallida!|r Prob: %s%% Bots: %d Poder: %.1f", tostring(successPct or "?"), botCount or 0, powerScore or 0))
    if cdSecs and cdSecs > 0 then BQPrint(string.format("|cffff8800Cooldown: %d min.|r", math.ceil(cdSecs/60))) end

    if BotQuestUI then
        BotQuestUI:ShowFailAnimation(questName, cdSecs, successPct, botCount, powerScore)
        if BotQuestUI.historyPanel and BotQuestUI.historyPanel:IsShown() then BotQuestUI:UpdateHistoryDisplay() end
    end
end

local function OnSystemMessage(self, event, message)
    if not message or message:sub(1,5) ~= "BQST:" then return end
    local parts = {}
    for token in message:sub(6):gmatch("[^\t]+") do parts[#parts+1] = token end
    if #parts == 0 then return end

    if parts[1] == "COMPLETE" then
        OnMissionComplete(tonumber(parts[3]), tonumber(parts[4]), tonumber(parts[5]), parts[6], parts[7], tonumber(parts[8]))
    elseif parts[1] == "FAIL" then
        OnMissionFail(parts[2], tonumber(parts[3]) or 0, parts[4], tonumber(parts[5]) or 0, tonumber(parts[6]) or 0, parts[7])
    elseif parts[1] == "COOLDOWN" then
        local secs = tonumber(parts[2]) or 0
        if secs > 0 then SetCooldown(secs) end
    elseif parts[1] == "POWER_QUERY" or parts[1] == "POWER_REPORT" then
        local p = BotQuestState.power
        p.botCount, p.powerScore, p.successPct = tonumber(parts[2]) or 0, tonumber(parts[3]) or 0, tonumber(parts[4]) or 0
        p.hasTank, p.hasHealer, p.ready = (parts[5] == "1"), (parts[6] == "1"), true
        if tonumber(parts[7] or 0) > GetCooldownRemaining() then SetCooldown(tonumber(parts[7])) end
        if BotQuestUI then BotQuestUI:OnPowerDataReceived() end
    end
end

local function BotQuestChatFilter(self, event, msg, ...) if msg and msg:sub(1, 5) == "BQST:" then return true end end
ChatFrame_AddMessageEventFilter("CHAT_MSG_SAY", BotQuestChatFilter)
ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", BotQuestChatFilter)

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        LoadDB()
        local saved = BotQuestDB.activeMission
        if saved then
            local remaining = saved.duration - (time() - saved.startTime)
            if remaining > 0 then
                BotQuestState.active = true; BotQuestState.questId = saved.questId; BotQuestState.questName = saved.questName
                BotQuestState.difficulty = saved.difficulty; BotQuestState.startTime = saved.startTime; BotQuestState.duration = saved.duration
                BotQuestState.elapsed = time() - saved.startTime
                StartTick()
            else
                BotQuestDB.activeMission = nil; SendChatMessage(".npcb unhide", "SAY")
            end
        end
        if BotQuestUI and BotQuestUI.CreateMinimapButton then BotQuestUI:CreateMinimapButton() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if BotQuestDB and BotQuestDB.cooldownExpiry then BotQuestState.cooldownExpiry = BotQuestDB.cooldownExpiry end
        BotQuestQueryPower("NORMAL")
    elseif event == "CHAT_MSG_SYSTEM" then OnSystemMessage(self, event, ...) end
end)

SLASH_BOTQUEST1, SLASH_BOTQUEST2 = "/bq", "/botquest"
SlashCmdList["BOTQUEST"] = function(msg)
    if msg == "reset" then BotQuestState.active = false; BotQuestDB.activeMission = nil; ClearCooldown(); BQPrint("Estado reseteado.")
    elseif msg == "stats" then BQPrint(string.format("Completadas: %d Fallidas: %d", BotQuestDB.completedTotal or 0, BotQuestDB.failedTotal or 0))
    else if BotQuestUI then BotQuestUI:Toggle() end end
end

BotQuestIsOnMission = function() return BotQuestState.active end
BotQuestGetProgress = function() return BotQuestState.active and math.min(BotQuestState.elapsed / BotQuestState.duration, 1) or 0 end
BotQuestGetRemaining = function() return BotQuestState.active and math.max(0, BotQuestState.duration - BotQuestState.elapsed) or 0 end
BotQuestGetPowerData = function() return BotQuestState.power end
BotQuestGetCooldown      = function() return GetCooldownRemaining() end