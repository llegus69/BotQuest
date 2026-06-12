-- ============================================================
--  BotQuest_Elites.lua  v1.1  (Módulo de Misiones Élite - FIX)
-- ============================================================

local yaInyectado = false

local function InyectarMisionesElite()
    -- Si ya se inyectaron, no hacemos nada más
    if yaInyectado then return end

    -- Forzar la comprobación o inicialización segura de la tabla en el servidor
    if not BotQuestData then
        BotQuestData = {}
    end
    if not BotQuestData.QUESTS then
        BotQuestData.QUESTS = {}
    end

    -- Pool de misiones Élite (Dificultad base x2 simulada por "ELITE")
    local nuevasMisiones = {
        {
            id         = "ELITE_01",
            name       = "[ÉLITE] El Azote de Stratholme",
            desc       = "Envía a tus mejores hombres a limpiar los remanentes de la Plaga. La resistencia es feroz y requerirá una coordinación perfecta.",
            minLevel   = 55,
            maxLevel   = 60,
            duration   = 1800, -- 30 min
            goldMin    = 150000, -- 15g
            goldMax    = 300000, -- 30g
            difficulty = "ELITE",
            icon       = "Interface\\Icons\\Spell_Shadow_AnimateDead",
        },
        {
            id         = "ELITE_02",
            name       = "[ÉLITE] Núcleo de Magma: Incursión",
            desc       = "Los señores de fuego amenazan con despertar. Solo un grupo con equipamiento excepcional (GS) saldrá con vida.",
            minLevel   = 60,
            maxLevel   = 80,
            duration   = 3600, -- 1 hora
            goldMin    = 500000, -- 50g
            goldMax    = 1000000, -- 100g
            difficulty = "ELITE",
            icon       = "Interface\\Icons\\Spell_Fire_LavaSpread",
        },
        {
            id         = "ELITE_03",
            name       = "[DESAFÍO] Asalto a la Ciudadela",
            desc       = "Una misión suicida a las puertas del Trono helado. El escalado de poder requerido es absurdo.",
            minLevel   = 80,
            maxLevel   = 80,
            duration   = 5400, -- 1h 30m
            goldMin    = 2000000, -- 200g
            goldMax    = 5000000, -- 500g
            difficulty = "ELITE",
            icon       = "Interface\\Icons\\Achievement_Boss_TheLichKing",
        }
    }

    -- Inyección limpia en la tabla global
    for _, quest in ipairs(nuevasMisiones) do
        table.insert(BotQuestData.QUESTS, quest)
    end

    yaInyectado = true
    print(string.format("[BotQuest-Elites] ¡Módulo acoplado con éxito! Se han inyectado %d misiones élite.", #nuevasMisiones))
end

-- EVENTO: Cuando un jugador logea, nos aseguramos de que el entorno esté inicializado y cargamos las misiones
local function OnPlayerLoginElite(event, player)
    if not yaInyectado then
        InyectarMisionesElite()
    end
end

-- Registro del evento de Login (Event ID 3 es PLAYER_EVENT_ON_LOGIN)
RegisterPlayerEvent(3, OnPlayerLoginElite)

-- Intento secundario automático a los 10 segundos por si acaso
CreateLuaEvent(function() 
    if not yaInyectado then 
        InyectarMisionesElite() 
    end 
end, 10000, 1)