-- ============================================================
--  BotQuest_LiveLog.lua — Módulo de Inmersión RPG Autónomo V23
--  Ventana Compacta Sin Avatares (Texto Optimizado y Limpio)
-- ============================================================

local tipoMarco = BackdropTemplateMixin and "BackdropTemplate" or nil
local LiveLog = CreateFrame("Frame", "BotQuest_LiveLogFrame", UIParent, tipoMarco)
LiveLog:SetSize(290, 360) -- Altura reajustada al diseño compacto sin avatares
LiveLog:SetPoint("CENTER", 0, 0)
LiveLog:EnableMouse(true)
LiveLog:SetMovable(true)
LiveLog:RegisterForDrag("LeftButton")
LiveLog:SetScript("OnDragStart", LiveLog.StartMoving)
LiveLog:SetScript("OnDragStop", LiveLog.StopMovingOrSizing)

LiveLog:SetFrameStrata("HIGH")
LiveLog:SetFrameLevel(10)
LiveLog:Hide()

local botonEnviarOriginal = nil
local tiempoInicioSimulado = nil

local function GetSafeTime()
    local t = (type(time) == "function" and time()) 
    if not t or t == 0 then
        t = (type(GetTime) == "function" and math.floor(GetTime())) or 123456
    end
    return t
end

if LiveLog.SetBackdrop then
    LiveLog:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        tile = true, tileSize = 16, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    LiveLog:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    LiveLog:SetBackdropBorderColor(0.25, 0.45, 0.80, 1.00)
end

local title = LiveLog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 14, -15)
title:SetTextColor(0, 0.9, 1, 1)
title:SetText("Bitácora")

local close = CreateFrame("Button", nil, LiveLog, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -2, -2)
close:SetScript("OnClick", function() LiveLog:Hide() end)

-- ============================================================
--  ZONA DE SCROLL (REPOSICIONADA HACIA ARRIBA)
-- ============================================================
local scrollFrame = CreateFrame("ScrollFrame", "BotQuestLiveLogScroll", LiveLog, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 14, -45)
scrollFrame:SetPoint("BOTTOMRIGHT", -30, 45)

local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollChild:SetSize(225, 260)
scrollFrame:SetScrollChild(scrollChild)

local logText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
logText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
logText:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, 0)
logText:SetJustifyH("LEFT")
logText:SetJustifyV("TOP")
logText:SetTextColor(1, 1, 1, 1)

logText:SetWordWrap(true)
logText:SetNonSpaceWrap(false)

-- ============================================================
--  PLANTILLAS DEL RELATO RPG
-- ============================================================
local LogTemplates = {
    Fase1 = {
        "Tus enviados revisan los mapas una última vez y cruzan la frontera.",
        "El clima se vuelve hostil, pero el grupo avanza con paso firme.",
        "Se reportan discusiones menores sobre quién cargará los suministros.",
        "El grupo avanza con sigilo, evitando patrullas enemigas.",
        "Una lluvia torrencial empapa el equipo, ralentizando la marcha inicial.",
        "El explorador del grupo divisa las primeras señales de territorio peligroso.",
        "Afilando las armas sobre la marcha; la tensión se palpa en el ambiente.",
        "El grupo avanza a paso ligero aprovechando la densa niebla de la mañana.",
        "Se realiza un recuento rápido de raciones antes de adentrarse en lo desconocido.",
        "El viento sopla con fuerza en contra, complicando el avance por el sendero.",
        "Tus bots intercambian bromas para aliviar la tensión del viaje.",
        "Se detectan runas antiguas talladas en los árboles del camino. Avanzan alerta.",
        "Un riachuelo helado bloquea el paso, pero el grupo lo cruza sin incidentes.",
        "Ajustando las correas de las armaduras; el camino empieza a empinarse.",
        "El grupo sigue las coordenadas del tablón con precisión militar."
    },
    Fase2 = {
        "El grupo encuentra un viejo campamento abandonado y recoge leña seca.",
        "Se divisan huellas frescas de bestias en el lodo. Armas listas.",
        "Tus bots preparan una pequeña hoguera donde se disponen a descansar.",
        "Un desprendimiento de rocas bloquea el sendero; buscan una ruta alternativa.",
        "Encuentran un riachuelo de agua cristalina y rellenan sus cantimploras.",
        "Uno de tus bots recolecta algunas plantas medicinales extrañas por si acaso.",
        "El grupo rescata a un comerciante herido que les da indicaciones útiles.",
        "Un cuervo negro sigue al grupo desde las alturas. Se sienten observados.",
        "Se detienen un instante a reparar una bota rota antes de seguir la marcha.",
        "Tus bots encuentran un cofre podrido enterrado, pero solo contenía chatarra.",
        "El mapa parece confuso en esta sección; el grupo debate qué rumbo tomar.",
        "Se percibe un fuerte olor a azufre y humo en el aire. El peligro acecha cerca.",
        "El grupo se refugia brevemente bajo una caverna para evitar una tormenta.",
        "Se escuchan ecos extraños entre los árboles, pero el grupo no se desvía.",
        "El escuadrón descubre un atajo que les ahorra varios kilómetros de caminata."
    },
    Fase3 = {
        "¡Emboscada! Criaturas salvajes asaltan la retaguardia del grupo.",
        "Se cruzan con una patrulla enemiga. Comienza un intercambio de golpes.",
        "El grupo cae en una trampa de la zona, obligándolos a combatir.",
        "El combate se intensifica, pero el escuadrón logra mantener la formación.",
        "Varios enemigos intentan flanquear al grupo, obligándolos a retroceder y cubrirse.",
        "¡Fuego cruzado! Un nido de avispas gigantes ataca al grupo en mitad del camino.",
        "Tus bots se ven obligados a repeler una jauría de lobos hambrientos.",
        "Un hechizo enemigo estalla cerca del sanador, desatando el caos un momento.",
        "El guerrero del grupo bloquea un golpe crítico con su escudo, salvando el día.",
        "Combate cerrado en el fango; la superioridad táctica de tus bots empieza a notarse.",
        "Un bandido oculto hiere levemente a un bot, pero el grupo responde con furia.",
        "Flechas envenenadas llueven desde las copas de los árboles. ¡A cubierto!",
        "El grupo despliega barreras mágicas para contener una oleada de no-muertos.",
        "Un bot desata un contraataque devastador que hace retroceder a los asaltantes.",
        "El fragor de las espadas y los conjuros resuena por todo el valle."
    },
    Fase4 = {
        "Se divisan las estructuras principales del objetivo. Comienza el despliegue.",
        "Tus bots inician el asalto definitivo. El acero resuena en la distancia.",
        "El líder enemigo planta cara a tus bots. Se decide el destino de la expedición.",
        "Bajo una lluvia de flechas y hechizos, el grupo arremete con furia.",
        "La tensión es máxima; el grupo gasta sus últimos recursos en el asalto final.",
        "¡Las puertas fortificadas ceden! Tus bots irrumpen en el corazón del bastión.",
        "El objetivo principal está a la vista, custodiado por una guardia de élite.",
        "Un bot activa una runa de poder para potenciar el golpe final del grupo.",
        "El suelo tiembla mientras el jefe enemigo concentra su magia oscura.",
        "Un asalto coordinado rodea las defensas enemigas. La victoria se saborea.",
        "Tus bots luchan con el último aliento, decididos a completar el contrato.",
        "Se destruyen los suministros del rival mientras el caos consume el campamento.",
        "Un choque brutal entre líderes decide el rumbo definitivo de la batalla.",
        "El bastión enemigo empieza a derrumbarse debido al feroz intercambio mágico.",
        "Tus enviados aseguran el perímetro tras un último y agónico empuje."
    }
}

-- ============================================================
--  GENERADOR DE BITÁCORA DETERMINISTA
-- ============================================================
local function GenerarTextoBitacora(startTime, duration)
    local ahora = GetSafeTime()
    local st = tonumber(startTime) or ahora
    local dur = tonumber(duration) or 120
    if dur <= 0 then dur = 120 end

    local tiempoTranscurrido = ahora - st
    local tiempoRestante = dur - tiempoTranscurrido
    local progreso = math.min(tiempoTranscurrido / dur, 1)
    
    local function ElegirFrase(lista, multiplicador)
        local semilla = math.floor(st * multiplicador + (multiplicador * 13))
        local indice = (semilla % #lista) + 1
        return lista[indice]
    end
    
    local iconoFase1 = "|TInterface\\Icons\\INV_Misc_Map02:20:20:0:0|t "
    local iconoFase2 = "|TInterface\\Icons\\Ability_Tracking:20:20:0:0|t "
    local iconoFase3 = "|TInterface\\Icons\\Ability_DualWield:20:20:0:0|t "
    local iconoFase4 = "|TInterface\\Icons\\inv_qirajidol_life:20:20:0:0|t "

    local logs = {}
    
    table.insert(logs, iconoFase1 .. ElegirFrase(LogTemplates.Fase1, 107))
    
    if progreso >= 0.25 then 
        table.insert(logs, iconoFase2 .. ElegirFrase(LogTemplates.Fase2, 223)) 
    end
    
    if progreso >= 0.50 then 
        table.insert(logs, iconoFase3 .. ElegirFrase(LogTemplates.Fase3, 359)) 
    end
    
    if progreso >= 0.80 then 
        table.insert(logs, iconoFase4 .. ElegirFrase(LogTemplates.Fase4, 491)) 
    end
    
    if tiempoRestante <= 10 or progreso >= 1 then 
        local iconoFinal = "|TInterface\\Icons\\Spell_Nature_Regeneration:20:20:0:0|t "
        table.insert(logs, iconoFinal .. "|cff00ff00La suerte está echada. Regresando para informar...|r") 
    end

    return table.concat(logs, "\n\n")
end

-- ============================================================
--  MOTOR DE ACTUALIZACIÓN INTERNO
-- ============================================================
local function EjecutarRefresco()
    local enMision = false
    local sTime, dur

    if type(BotQuestDB) == "table" and BotQuestDB.activeMission then
        sTime = BotQuestDB.activeMission.startTime
        dur = BotQuestDB.activeMission.duration
        if sTime and dur then enMision = true end
    end

    if not enMision and type(BotQuestIsOnMission) == "function" and BotQuestIsOnMission() then
        enMision = true
    end

    if not enMision and botonEnviarOriginal and not botonEnviarOriginal:IsEnabled() then
        enMision = true
    end

    if enMision then
        if not sTime or not dur then
            if not tiempoInicioSimulado then tiempoInicioSimulado = GetSafeTime() end
            sTime = tiempoInicioSimulado
            dur = 120
        end
        logText:SetText(GenerarTextoBitacora(sTime, dur))
    else
        tiempoInicioSimulado = nil
        logText:SetText("|cff888888[Estado: En Espera]|r\n\nNo hay expediciones.\n\nManda a tus bots a la aventura.")
    end

    local alturaReal = logText:GetStringHeight()
    if alturaReal and alturaReal > 0 then
        scrollChild:SetHeight(alturaReal + 25)
    else
        scrollChild:SetHeight(260)
    end
end

local function RefrescarDiario()
    local exitoso, errorMsg = pcall(EjecutarRefresco)
    if not exitoso then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[Error Diario BotQuest]:|r " .. tostring(errorMsg))
    end
end

local refrescarBtn = CreateFrame("Button", nil, LiveLog, "UIPanelButtonTemplate")
refrescarBtn:SetSize(130, 22)
refrescarBtn:SetPoint("BOTTOM", LiveLog, "BOTTOM", 0, 12)
refrescarBtn:SetText("Refrescar")
refrescarBtn:SetScript("OnClick", function()
    RefrescarDiario()
end)

local acumulador = 0
LiveLog:SetScript("OnUpdate", function(self, elapsed)
    if not LiveLog:IsShown() then return end
    acumulador = acumulador + elapsed
    if acumulador >= 1 then
        acumulador = 0
        RefrescarDiario()
    end
end)

LiveLog:SetScript("OnShow", function()
    RefrescarDiario()
end)

-- ============================================================
--  INYECTOR DE INTERFAZ
-- ============================================================
local botonCreado = false
local Detector = CreateFrame("Frame")
Detector:SetScript("OnUpdate", function(self, elapsed)
    if BotQuestMainFrame and not botonCreado then
        
        local children = { BotQuestMainFrame:GetChildren() }
        for _, child in ipairs(children) do
            if child:IsObjectType("Button") then
                local txt = child:GetText()
                if txt and txt ~= "Historial Log" and txt ~= "" then
                    local txtLower = string.lower(txt)
                    if string.find(txtLower, "enviar") or string.find(txtLower, "bot") or string.find(txtLower, "mision") then
                        botonEnviarOriginal = child
                        break
                    end
                end
            end
        end

        local diarioBtn = CreateFrame("Button", nil, BotQuestMainFrame, "UIPanelButtonTemplate")
        diarioBtn:SetSize(110, 22)
        diarioBtn:SetPoint("BOTTOMLEFT", BotQuestMainFrame, "BOTTOMLEFT", 145, 24)
        diarioBtn:SetText("Diario")
        
        diarioBtn:SetScript("OnClick", function()
            if LiveLog:IsShown() then
                LiveLog:Hide()
            else
                LiveLog:Show()
                RefrescarDiario()
            end
        end)
        
        botonCreado = true
        Detector:SetScript("OnUpdate", nil)
    end
end)

-- ============================================================
--  COMANDO /bql
-- ============================================================
SLASH_BOTQUESTLOG1 = "/bql"
SlashCmdList["BOTQUESTLOG"] = function()
    if LiveLog:IsShown() then
        LiveLog:Hide()
    else
        LiveLog:Show()
        RefrescarDiario()
    end
end