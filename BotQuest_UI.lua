-- ============================================================
--  BotQuest_UI.lua  v2.5.2 — Edición Tablón + Resultados + Minimapa
--  FIX: Contadores dinámicos que no se congelan (segundos siempre activos)
--  FIX 2: Eliminado solapamiento de Cooldown cuando la misión está "En Curso"
-- ============================================================

BotQuestUI = {}
BotQuestUI.frames = {}
BotQuestUI.rows = {}

local COOLDOWN_DURATION = 43200 
local UI = {
    W = 480, H = 590, ROW_H = 68, ROW_PAD = 5, ICON_SZ = 44,
    BG = { 0.06, 0.06, 0.10, 0.97 }, BORDER = { 0.25, 0.45, 0.80, 1.00 }, TEXT_MAIN = { 0.92, 0.92, 0.96, 1.00 },
}

local function MakeBorder(f, r, g, b, a)
    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        tile = true, tileSize = 16, edgeSize = 1, insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    f:SetBackdropColor(UI.BG[1], UI.BG[2], UI.BG[3], UI.BG[4])
    f:SetBackdropBorderColor(r or UI.BORDER[1], g or UI.BORDER[2], b or UI.BORDER[3], a or UI.BORDER[4])
end

local function MakeFS(parent, size, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", size, "OUTLINE")
    fs:SetTextColor(r or 1, g or 1, b or 1)
    return fs
end

local function EnsureDatabase()
    if not BotQuestDB then BotQuestDB = {} end
    if not BotQuestDB.questCooldowns then BotQuestDB.questCooldowns = {} end
    if not BotQuestDB.historyLogs then BotQuestDB.historyLogs = {} end
end

local function FormatCooldownTime(seconds)
    if seconds <= 0 then return "00s" end
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = math.floor(seconds % 60)
    if h > 0 then
        return string.format("%02dh %02dm %02ds", h, m, s)
    elseif m > 0 then
        return string.format("%02dm %02ds", m, s)
    else
        return string.format("%02ds", s)
    end
end

-- ============================================================
--  CREACIÓN DE LA INTERFAZ PRINCIPAL
-- ============================================================
function BotQuestUI:Init()
    if self.mainFrame then return end
    EnsureDatabase()

    local f = CreateFrame("Frame", "BotQuestMainFrame", UIParent)
    if BotQuestDB and BotQuestDB.uiWidth and BotQuestDB.uiHeight then
        f:SetSize(BotQuestDB.uiWidth, BotQuestDB.uiHeight)
    else
        f:SetSize(UI.W, UI.H)
    end
    f:SetPoint("CENTER", 0, 0)
    f:EnableMouse(true); f:SetMovable(true); f:SetResizable(true); f:SetMinResize(480, 500); f:SetMaxResize(900, 800)
    f:RegisterForDrag("LeftButton"); f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if BotQuestDB then
            BotQuestDB.uiWidth = self:GetWidth()
            BotQuestDB.uiHeight = self:GetHeight()
        end
    end)
    MakeBorder(f)
    self.mainFrame = f; f:Hide()

    -- Botón de arrastre para redimensionar (Grip en esquina inferior derecha)
    local rb = CreateFrame("Button", nil, f)
    rb:SetSize(16, 16); rb:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    local rt = rb:CreateTexture(nil, "OVERLAY")
    rt:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    rt:SetAllPoints(rb)
    rb:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then f:StartSizing("BOTTOMRIGHT") end
    end)
    rb:SetScript("OnMouseUp", function(self)
        f:StopMovingOrSizing()
        if BotQuestDB then
            BotQuestDB.uiWidth = f:GetWidth()
            BotQuestDB.uiHeight = f:GetHeight()
        end
    end)

    local title = MakeFS(f, 15, 0, 0.8, 1)
    title:SetPoint("TOPLEFT", 15, -15); title:SetText("BotQuest — Tablón de Misiones")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    close:SetScript("OnClick", function() f:Hide(); if self.historyPanel then self.historyPanel:Hide() end end)

    local leftPanel = CreateFrame("Frame", nil, f)
    leftPanel:SetPoint("TOPLEFT", 15, -50); leftPanel:SetPoint("BOTTOMLEFT", 15, 70); leftPanel:SetWidth(230)
    MakeBorder(leftPanel, 0.15, 0.15, 0.2, 0.8)
    self.leftPanel = leftPanel

    local scrollFrame = CreateFrame("ScrollFrame", "BotQuestListScrollFrame", leftPanel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 6, -6); scrollFrame:SetPoint("BOTTOMRIGHT", -26, 6)

    local scrollChild = CreateFrame("Frame", "BotQuestListScrollChild", scrollFrame)
    scrollChild:SetSize(200, 1); scrollFrame:SetScrollChild(scrollChild)
    self.scrollChild = scrollChild

    local rightPanel = CreateFrame("Frame", nil, f)
    rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 10, 0); rightPanel:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -15, 70)
    MakeBorder(rightPanel, 0.15, 0.15, 0.2, 0.8); self.rightPanel = rightPanel

    self.qTitle = MakeFS(rightPanel, 14, 1, 0.82, 0)
    self.qTitle:SetPoint("TOPLEFT", 12, -15); self.qTitle:SetPoint("TOPRIGHT", -12, -15); self.qTitle:SetJustifyH("LEFT")

    self.qCooldownText = MakeFS(rightPanel, 11, 1, 0.3, 0.3)
    self.qCooldownText:SetPoint("TOPLEFT", 12, -35); self.qCooldownText:SetPoint("TOPRIGHT", -12, -35); self.qCooldownText:SetJustifyH("LEFT")
    self.qCooldownText:Hide()

    self.qDesc = MakeFS(rightPanel, 11, UI.TEXT_MAIN[1], UI.TEXT_MAIN[2], UI.TEXT_MAIN[3])
    self.qDesc:SetPoint("TOPLEFT", 12, -55); self.qDesc:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -12, 165)
    self.qDesc:SetJustifyH("LEFT"); self.qDesc:SetJustifyV("TOP"); self.qDesc:SetNonSpaceWrap(true)

    local rewardBox = CreateFrame("Frame", nil, rightPanel)
    rewardBox:SetSize(185, 60); rewardBox:SetPoint("BOTTOM", rightPanel, "BOTTOM", 0, 95)
    MakeBorder(rewardBox, 0.2, 0.2, 0.25, 0.6); self.rewardBox = rewardBox
    
    self.rewardIcon = rewardBox:CreateTexture(nil, "ARTWORK")
    self.rewardIcon:SetSize(UI.ICON_SZ, UI.ICON_SZ); self.rewardIcon:SetPoint("LEFT", 10, 0)
    
    self.rewardText = MakeFS(rewardBox, 10, 1, 1, 1)
    self.rewardText:SetPoint("LEFT", self.rewardIcon, "RIGHT", 8, 0)

    self.startBtn = CreateFrame("Button", nil, rightPanel, "UIPanelButtonTemplate")
    self.startBtn:SetSize(140, 26); self.startBtn:SetPoint("BOTTOM", rightPanel, "BOTTOM", 0, 45); self.startBtn:SetText("Enviar Bots")
    self.startBtn:SetScript("OnClick", function()
        if self.selectedQuest then
            if not BotQuestDB.questCooldowns then BotQuestDB.questCooldowns = {} end
            BotQuestDB.questCooldowns[self.selectedQuest.id] = time() + COOLDOWN_DURATION
            BotQuestSendMission(self.selectedQuest)
            self:RenderQuestList()
        end
    end)

    self.refreshBtn = CreateFrame("Button", nil, rightPanel, "UIPanelButtonTemplate")
    self.refreshBtn:SetSize(140, 24); self.refreshBtn:SetPoint("TOP", self.startBtn, "BOTTOM", 0, -6); self.refreshBtn:SetText("Preguntar al grupo")
    self.refreshBtn:SetScript("OnClick", function()
        if self.selectedQuest then BotQuestQueryPower(self.selectedQuest.difficulty) end
    end)

    -- PANEL DE PROGRESO INTEGRADO
    local progressPanel = CreateFrame("Frame", nil, rightPanel)
    progressPanel:SetAllPoints(rightPanel); progressPanel:Hide(); self.progressPanel = progressPanel

    local progMainTitle = MakeFS(progressPanel, 14, 1, 0.7, 0)
    progMainTitle:SetPoint("TOP", 0, -35); progMainTitle:SetText("MISIÓN EN CURSO")
    self.progTitle = MakeFS(progressPanel, 11, 0.9, 0.9, 0.9); self.progTitle:SetPoint("TOP", progMainTitle, "BOTTOM", 0, -15)

    local pBar = CreateFrame("StatusBar", nil, progressPanel)
    pBar:SetSize(175, 18); pBar:SetPoint("CENTER", progressPanel, "CENTER", 0, 10)
    pBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar"); pBar:SetStatusBarColor(0, 0.7, 1); pBar:SetMinMaxValues(0, 100)
    self.progressBar = pBar

    self.progTimeText = MakeFS(pBar, 10, 1, 1, 1); self.progTimeText:SetPoint("CENTER", 0, 0)

    local cancelBtn = CreateFrame("Button", nil, progressPanel, "UIPanelButtonTemplate")
    cancelBtn:SetSize(130, 24); cancelBtn:SetPoint("BOTTOM", progressPanel, "BOTTOM", 0, 35); cancelBtn:SetText("Abortar Misión")
    cancelBtn:SetScript("OnClick", function()
        StaticPopupDialogs["CONFIRM_CANCEL_BOTQUEST"] = {
            text = "¿Abortar misión?", button1 = "Sí", button2 = "No",
            OnAccept = function()
                if SlashCmdList["BOTQUEST"] then SlashCmdList["BOTQUEST"]("reset") end
                SendChatMessage(".npcb unhide", "SAY")
                if BotQuestUI.selectedQuest then BotQuestDB.questCooldowns[BotQuestUI.selectedQuest.id] = 0 end
                progressPanel:Hide()
                BotQuestUI:RenderQuestList()
            end, timeout = 0, whileDead = true, hideOnEscape = true,
        }
        StaticPopup_Show("CONFIRM_CANCEL_BOTQUEST")
    end)

    local powerFrame = CreateFrame("Frame", nil, f)
    powerFrame:SetHeight(40); powerFrame:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 140, 15); powerFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -15, 15)
    MakeBorder(powerFrame, 0.15, 0.3, 0.5, 0.9); self.powerFrame = powerFrame

    self.powerText = MakeFS(powerFrame, 11, 0, 0.9, 1); self.powerText:SetPoint("CENTER", powerFrame, "CENTER", 0, 0)
    self:AddHistoryButton()
    self:RenderQuestList()
end

-- ============================================================
--  PANELES Y ANIMACIONES DE RESULTADO (Éxito/Fallo)
-- ============================================================
function BotQuestUI:CreateResultPanel()
    if self.resultPanel then return end
    local rp = CreateFrame("Frame", nil, self.rightPanel)
    rp:SetAllPoints(self.rightPanel)
    rp:Hide()
    self.resultPanel = rp

    self.resTitle = MakeFS(rp, 16, 1, 1, 1)
    self.resTitle:SetPoint("TOP", 0, -30)

    self.resIcon = rp:CreateTexture(nil, "ARTWORK")
    self.resIcon:SetSize(52, 52)
    self.resIcon:SetPoint("CENTER", rp, "CENTER", 0, 10)

    self.resText = MakeFS(rp, 12, 1, 1, 1)
    self.resText:SetPoint("TOP", self.resIcon, "BOTTOM", 0, -15)

    local okBtn = CreateFrame("Button", nil, rp, "UIPanelButtonTemplate")
    okBtn:SetSize(120, 26)
    okBtn:SetPoint("BOTTOM", rp, "BOTTOM", 0, 20)
    okBtn:SetText("Continuar")
    okBtn:SetScript("OnClick", function()
        rp:Hide()
        if BotQuestUI.selectedQuest then BotQuestUI:SelectQuest(BotQuestUI.selectedQuest) end
        BotQuestUI:RenderQuestList()
    end)
end

function BotQuestUI:ShowWaitingResult()
    if self.progTimeText then self.progTimeText:SetText("Esperando reporte...") end
end

function BotQuestUI:ShowCompleteAnimation(questName, gold, itemId, quality, itemName)
    self:CreateResultPanel()
    if self.progressPanel then self.progressPanel:Hide() end
    self.qTitle:Hide(); self.qCooldownText:Hide(); self.qDesc:Hide(); self.rewardBox:Hide(); self.startBtn:Hide(); self.refreshBtn:Hide()

    MakeBorder(self.resultPanel, 0.2, 0.8, 0.2, 0.95)
    self.resTitle:SetText("|cff44ff44¡MISIÓN COMPLETADA!|r")

    if itemId and itemId > 0 then
        local itemNameInfo, _, _, _, _, _, _, _, _, itemIcon = GetItemInfo(itemId)
        self.resIcon:SetTexture(itemIcon or "Interface\\Icons\\INV_Box_01")
        self.resText:SetText(string.format("Oro: %s\nBotín: %s", BotQuestData:FormatGold(gold), itemNameInfo or itemName))
    else
        self.resIcon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
        self.resText:SetText(string.format("Oro: %s", BotQuestData:FormatGold(gold)))
    end

    self.resultPanel:Show()
    self:RenderQuestList()
end

function BotQuestUI:ShowFailAnimation(questName, cdSecs, successPct, botCount, powerScore)
    self:CreateResultPanel()
    if self.progressPanel then self.progressPanel:Hide() end
    self.qTitle:Hide(); self.qCooldownText:Hide(); self.qDesc:Hide(); self.rewardBox:Hide(); self.startBtn:Hide(); self.refreshBtn:Hide()

    MakeBorder(self.resultPanel, 0.8, 0.2, 0.2, 0.95)
    self.resTitle:SetText("|cffff2222¡MISIÓN FALLADA!|r")
    self.resIcon:SetTexture("Interface\\Icons\\Ability_Warrior_DefensiveStance")
    
    self.resText:SetText(string.format("Tus bots fueron derrotados.\nTenías un %s%% de éxito.\n\nDescanso: %d min", successPct or "??", math.ceil((cdSecs or 0)/60)))

    self.resultPanel:Show()
    self:RenderQuestList()
end

-- ============================================================
--  PANEL MODULAR DE VISUALIZACIÓN DE LOGS Y PROBABILIDADES
-- ============================================================
function BotQuestUI:CreateHistoryPanel()
    if self.historyPanel then return end

    local hp = CreateFrame("Frame", "BotQuestHistoryPanel", self.mainFrame)
    hp:SetSize(450, 420); hp:SetPoint("LEFT", self.mainFrame, "RIGHT", 8, 0)
    hp:EnableMouse(true); hp:SetMovable(true); hp:RegisterForDrag("LeftButton"); hp:SetScript("OnDragStart", hp.StartMoving); hp:SetScript("OnDragStop", hp.StopMovingOrSizing)
    MakeBorder(hp, 0.2, 0.45, 0.7, 0.98); hp:Hide(); self.historyPanel = hp

    local hTitle = MakeFS(hp, 13, 0, 0.8, 1); hTitle:SetPoint("TOPLEFT", 15, -15); hTitle:SetText("Registro de Misiones Recientes (Logs)")
    local hClose = CreateFrame("Button", nil, hp, "UIPanelCloseButton"); hClose:SetPoint("TOPRIGHT", -5, -5); hClose:SetScript("OnClick", function() hp:Hide() end)

    local scrollFrame = CreateFrame("ScrollFrame", "BotQuestHistoryScrollFrame", hp, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -45); scrollFrame:SetPoint("BOTTOMRIGHT", -30, 15)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame); scrollChild:SetSize(390, 1); scrollFrame:SetScrollChild(scrollChild); self.historyContent = scrollChild
    self.historyLines = {}
end

function BotQuestUI:UpdateHistoryDisplay()
    self:CreateHistoryPanel()
    EnsureDatabase()
    for _, line in ipairs(self.historyLines) do line:Hide() end

    local logs = BotQuestDB.historyLogs or {}
    local yOffset = -5

    if #logs == 0 then
        if not self.noLogsText then self.noLogsText = MakeFS(self.historyContent, 12, 0.6, 0.6, 0.6); self.noLogsText:SetPoint("TOPLEFT", 10, -10); self.noLogsText:SetText("No se registran expediciones de bots todavía.") end
        self.noLogsText:Show(); return
    elseif self.noLogsText then self.noLogsText:Hide() end

    for i, log in ipairs(logs) do
        if not self.historyLines[i] then
            local box = CreateFrame("Frame", nil, self.historyContent)
            box:SetSize(385, 52); MakeBorder(box, 0.15, 0.15, 0.2, 0.5)
            local txt = MakeFS(box, 10, 1, 1, 1); txt:SetPoint("TOPLEFT", 8, -6); txt:SetWidth(370); txt:SetJustifyH("LEFT"); txt:SetJustifyV("TOP")
            box.fs = txt; self.historyLines[i] = box
        end

        local box = self.historyLines[i]
        local statusColor = log.success and "|cff44ff44[ÉXITO]|r" or "|cffff2222[FALLO]|r"
        local goldText = log.gold > 0 and BotQuestData:FormatGold(log.gold) or "0g"
        local displayBots = log.bots:gsub(",", ", ")
        local chanceText = log.chance and (log.chance .. "%") or "??%"

        box.fs:SetText(string.format("|cff88ccff%s|r %s |cffffcc00%s|r (|cffffffff%s|r)  —  Prob: |cff00ccff%s|r\n|cffaaaaaaBotín:|r %s (%s)\n|cff888888Grupo:|r |cff00ffcc%s|r",
            log.timeStr or "", statusColor, log.questName, log.difficulty, chanceText, goldText, log.rewardText, displayBots))
        
        box:SetPoint("TOPLEFT", 0, yOffset); box:Show()
        yOffset = yOffset - 58
    end
    self.historyContent:SetHeight(math.abs(yOffset) + 10)
end

function BotQuestUI:AddHistoryButton()
    if self.historyBtn then return end
    local btn = CreateFrame("Button", nil, self.mainFrame, "UIPanelButtonTemplate")
    btn:SetSize(115, 24); btn:SetPoint("BOTTOMLEFT", 15, 23); btn:SetText("Historial Logs")
    btn:SetScript("OnClick", function() if self.historyPanel and self.historyPanel:IsShown() then self.historyPanel:Hide() else self:UpdateHistoryDisplay(); self.historyPanel:Show() end end)
    self.historyBtn = btn
end

-- ============================================================
--  LOGICA PRINCIPAL ADAPTADA Y CORREGIDA
-- ============================================================
function BotQuestUI:SelectQuest(quest)
    self.selectedQuest = quest
    if not quest then return end
    EnsureDatabase()

    if self.resultPanel and self.resultPanel:IsShown() then self.resultPanel:Hide() end

    -- FIX: Si la misión está activa, ocultamos el cooldown explícitamente para evitar solapamientos
    if BotQuestIsOnMission() then
        self.qTitle:Hide(); self.qCooldownText:Hide(); self.qDesc:Hide(); self.rewardBox:Hide(); self.startBtn:Hide(); self.refreshBtn:Hide()
        self.progressPanel:Show(); self.progTitle:SetText(quest.name); self:UpdateProgressBar()
        return
    else
        self.progressPanel:Hide(); self.qTitle:Show(); self.qDesc:Show(); self.rewardBox:Show(); self.startBtn:Show(); self.refreshBtn:Show()
    end

    self.qTitle:SetText(quest.name)
    local cdExpiry = BotQuestDB.questCooldowns[quest.id] or 0
    local remainingCd = cdExpiry - time()
    local globalCd = BotQuestGetCooldown and BotQuestGetCooldown() or 0

    if remainingCd > 0 then 
        self.startBtn:Disable(); self.startBtn:SetText("Misión en Cooldown") 
    elseif globalCd > 0 then
        self.startBtn:Disable(); self.startBtn:SetText("Bots Descansando")
    else 
        self.startBtn:Enable(); self.startBtn:SetText("Enviar Bots") 
    end

    local diffData = BotQuestData.DIFFICULTY[quest.difficulty] or { label="Normal", color="ffffffff" }
    local desc = "|cff88aaeeNivel Mín:|r " .. tostring(quest.minLevel) .. "\n|cff88aaeeDuración:|r " .. tostring(BotQuestData:FormatDuration(quest.duration)) .. "\n|cff88aaeeDificultad:|r |c" .. tostring(diffData.color) .. tostring(diffData.label) .. "|r\n\n"
    desc = desc .. tostring(quest.desc or "Aventura en el tablón.")
    self.qDesc:SetText(desc)

    -- Solo pintamos el Cooldown si la misión no está corriendo en segundo plano
    if remainingCd > 0 then
        self.qCooldownText:SetText("|cffff3333Reutilización:|r |cffffffffDisponible en " .. FormatCooldownTime(remainingCd) .. "|r")
        self.qCooldownText:Show()
    else
        self.qCooldownText:Hide()
    end

    if quest.isPvP then
        self.rewardIcon:SetTexture("Interface\\Icons\\INV_BannerPVP_01"); self.rewardText:SetText("|cff00ff00Recompensa PvP:\n" .. tostring(quest.honorPoints or 0) .. " Honor")
    else
        self.rewardIcon:SetTexture(quest.icon or "Interface\\Icons\\INV_Misc_Bag_07"); self.rewardText:SetText("|cff00ff00Recompensa:\n" .. BotQuestData:FormatGold(quest.goldMin) .. "\n+ Objeto (según nivel)")
    end
    BotQuestQueryPower(quest.difficulty)
end

function BotQuestUI:RenderQuestList()
    if not self.scrollChild then return end
    EnsureDatabase()
    
    local availableQuests = BotQuestData:GetQuestsForLevel(UnitLevel("player") or 80)
    if self.rows then for _, row in ipairs(self.rows) do row:Hide() end end
    self.rows = {}

    local contentHeight = 0
    for i, quest in ipairs(availableQuests) do
        local row = CreateFrame("Button", nil, self.scrollChild)
        row:SetSize(200, UI.ROW_H); row:SetPoint("TOPLEFT", 2, -((i-1) * (UI.ROW_H + UI.ROW_PAD)))
        
        local remainingCd = (BotQuestDB.questCooldowns[quest.id] or 0) - time()
        if remainingCd > 0 then MakeBorder(row, 0.4, 0.2, 0.2, 0.3) else MakeBorder(row, 0.2, 0.2, 0.25, 0.5) end

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(36, 36); icon:SetPoint("LEFT", 8, 0); icon:SetTexture(quest.icon or "Interface\\Icons\\INV_Misc_Bag_07")
        if remainingCd > 0 then icon:SetVertexColor(0.4, 0.4, 0.4) else icon:SetVertexColor(1, 1, 1) end

        local nameFS = MakeFS(row, 11, 1, 1, 1); nameFS:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2); nameFS:SetText(quest.name)
        local typeFS = MakeFS(row, 9, 0.6, 0.6, 0.6); typeFS:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 2)
        
        if remainingCd > 0 then
            typeFS:SetText(string.format("|cffff2222CD: %s|r", FormatCooldownTime(remainingCd)))
            row.cdTimerText = typeFS
        else
            local diffData = BotQuestData.DIFFICULTY[quest.difficulty] or { label="Normal", color="ffffffff" }
            typeFS:SetText(string.format("Dif: |c%s%s|r", diffData.color, diffData.label))
        end

        row:SetScript("OnClick", function() self:SelectQuest(quest) end)
        row.questRef = quest; table.insert(self.rows, row)
        contentHeight = i * (UI.ROW_H + UI.ROW_PAD)
    end
    self.scrollChild:SetHeight(contentHeight)
end

function BotQuestUI:UpdateActiveCooldowns()
    if not self.rows then return end
    EnsureDatabase()
    local needRefresh = false
    
    -- 1. Actualizar contadores del listado izquierdo
    for _, row in ipairs(self.rows) do
        if row.questRef then
            local remainingCd = (BotQuestDB.questCooldowns[row.questRef.id] or 0) - time()
            if remainingCd > 0 then 
                if row.cdTimerText then 
                    row.cdTimerText:SetText(string.format("|cffff2222CD: %s|r", FormatCooldownTime(remainingCd))) 
                else 
                    needRefresh = true 
                end
            else 
                if row.cdTimerText then needRefresh = true end
            end
        end
    end
    
    -- 2. Actualizar contador de la derecha (Solo si la misión NO está activa y corriendo)
    if self.selectedQuest and self.rightPanel:IsShown() then
        if BotQuestIsOnMission() then
            if self.qCooldownText then self.qCooldownText:Hide() end
        else
            local remainingCd = (BotQuestDB.questCooldowns[self.selectedQuest.id] or 0) - time()
            if self.qCooldownText then
                if remainingCd > 0 then
                    self.qCooldownText:SetText("|cffff3333Reutilización:|r |cffffffffDisponible en " .. FormatCooldownTime(remainingCd) .. "|r")
                    self.qCooldownText:Show()
                else
                    self.qCooldownText:Hide()
                end
            end
        end
    end

    if needRefresh then 
        self:RenderQuestList() 
        if self.selectedQuest and not BotQuestIsOnMission() then
            local quest = self.selectedQuest
            local cdExpiry = BotQuestDB.questCooldowns[quest.id] or 0
            local remainingCd = cdExpiry - time()
            local globalCd = BotQuestGetCooldown and BotQuestGetCooldown() or 0

            if remainingCd > 0 then 
                self.startBtn:Disable(); self.startBtn:SetText("Misión en Cooldown") 
            elseif globalCd > 0 then
                self.startBtn:Disable(); self.startBtn:SetText("Bots Descansando")
            else 
                self.startBtn:Enable(); self.startBtn:SetText("Enviar Bots") 
            end
        end
    end
end

function BotQuestUI:OnPowerDataReceived()
    local p = BotQuestGetPowerData()
    if not p or not self.powerText then return end
    local pctColor = p.successPct < 40 and "ffff2222" or (p.successPct < 75 and "ffff8800" or "ff44ff44")
    self.powerText:SetText(string.format("Bots: |cffffffff%d|r Poder: |cffffffff%.1f|r Éxito: |c%s%.0f%%|r", p.botCount, p.powerScore, pctColor, p.successPct))
end

function BotQuestUI:UpdateProgressBar()
    if not BotQuestIsOnMission() then
        if self.progressPanel and self.progressPanel:IsShown() and not (self.resultPanel and self.resultPanel:IsShown()) then 
            self.progressPanel:Hide(); if self.selectedQuest then self:SelectQuest(self.selectedQuest) end 
        end
        return
    end
    if self.progressPanel and not self.progressPanel:IsShown() then
        if self.resultPanel then self.resultPanel:Hide() end
        self.qTitle:Hide(); self.qCooldownText:Hide(); self.qDesc:Hide(); self.rewardBox:Hide(); self.startBtn:Hide(); self.refreshBtn:Hide(); self.progressPanel:Show()
    end
    local pctPercent, rem = (BotQuestGetProgress() or 0) * 100, BotQuestGetRemaining() or 0
    if self.progressBar then self.progressBar:SetValue(pctPercent) end
    if self.progTimeText then if rem > 0 then self.progTimeText:SetText(string.format("%d min %d s", math.floor(rem/60), rem%60)) end end
end

function BotQuestUI:Toggle()
    self:Init()
    if self.mainFrame:IsShown() then 
        self.mainFrame:Hide(); if self.historyPanel then self.historyPanel:Hide() end 
    else 
        self.mainFrame:Show(); self:RenderQuestList(); if self.selectedQuest then self:SelectQuest(self.selectedQuest) end 
    end
end

-- ============================================================
--  BOTÓN DEL MINIMAPA
-- ============================================================
function BotQuestUI:CreateMinimapButton()
    if self.minimapBtn then return end
    
    local btn = CreateFrame("Button", "BotQuestMinimapBtn", Minimap)
    btn:SetSize(32, 32); btn:SetFrameStrata("MEDIUM"); btn:SetFrameLevel(8); btn:SetMovable(true); btn:RegisterForDrag("RightButton")
    
    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Map02")
    icon:SetSize(20, 20); icon:SetPoint("CENTER", 0, 0)
    
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54); border:SetPoint("TOPLEFT", 0, 0)
    
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    
    BotQuestDB = BotQuestDB or {}
    local angle = BotQuestDB.minimapAngle or 45
    local x = math.cos(math.rad(angle)) * 80
    local y = math.sin(math.rad(angle)) * 80
    btn:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 52 - x, y - 52)
    
    btn:SetScript("OnClick", function(self, button) if button == "LeftButton" then BotQuestUI:Toggle() end end)
    
    btn:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            local angle = math.deg(math.atan2(py - my, px - mx))
            local nx = math.cos(math.rad(angle)) * 80
            local ny = math.sin(math.rad(angle)) * 80
            self:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 52 + nx, ny - 52)
            BotQuestDB.minimapAngle = angle
        end)
    end)
    
    btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil); self:UnlockHighlight() end)
    
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText("BotQuest")
        GameTooltip:AddLine("Clic Izquierdo: Abrir Tablón de Misiones", 1, 1, 1)
        GameTooltip:AddLine("Clic Derecho (Mantener): Mover el botón", 0.5, 0.5, 0.5); GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
    
    self.minimapBtn = btn
end

-- ============================================================
--  MOTOR DE REFRESCO (TICKER)
-- ============================================================
local totalTimer = 0
local timerFrame = CreateFrame("Frame")
timerFrame:SetScript("OnUpdate", function(self, elapsed)
    totalTimer = totalTimer + elapsed
    if totalTimer >= 1.0 then
        totalTimer = 0
        BotQuestUI:UpdateActiveCooldowns()
        if BotQuestMainFrame and BotQuestMainFrame:IsShown() then
            BotQuestUI:UpdateProgressBar()
        end
    end
end)