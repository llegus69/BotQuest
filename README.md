# BotQuest

[![WoW Version](https://img.shields.io/badge/World%20of%20Warcraft-WotLK%203.3.5a-orange.svg?style=for-the-badge)](https://github.com/)
[![Framework](https://img.shields.io/badge/Server-Eluna%20Lua%20Engine-blue.svg?style=for-the-badge)](https://github.com/ElunaLuaEngine/Eluna)
[![Core](https://img.shields.io/badge/Core-AzerothCore%20%2F%20TrinityCore-red.svg?style=for-the-badge)](https://www.azerothcore.org/)
[![Addon-Type](https://img.shields.io/badge/Interface-Pure%20Lua%20%28No%20Ace3%29-brightgreen.svg?style=for-the-badge)](https://github.com/)

**BotQuest** es un ecosistema RPG inmersivo de gestión y simulación de misiones para servidores privados de World of Warcraft (WotLK 3.3.5a). El sistema permite a los jugadores enviar a sus **NPCBots** a misiones automatizadas en segundo plano a través de un tablón de anuncios interactivo, simulando las mecánicas de seguidores (estilo *Garrisons* de Warlords of Draenor o *Sedes de Clase* de Legion).

El proyecto consta de dos partes acopladas que se comunican mediante paquetes de chat (`SAY` con prefijo `BQST`):
1. **Script de Servidor (Eluna):** Maneja la base de datos, calcula el "Pseudo-GS" de los bots basándose en sus estadísticas reales, valida los estados de manera segura y entrega recompensas.
2. **Addon de Cliente (Lua Nativo):** Ofrece interfaces visuales avanzadas para el tablón, resultados gráficos animables, un módulo de bitácora narrativa en tiempo real (`LiveLog`) e integración con el Minimapa.

---

## 🚀 Características Principales

* **Tablón Automatizado e Inteligente:** Las misiones disponibles se filtran automáticamente de acuerdo al nivel del personaje del jugador (`GetQuestsForLevel`).
* **Integración con Estadísticas de NPCBots (Pseudo-GS):** El servidor lee directamente la tabla `characters_npcbot_stats` para evaluar los atributos reales del equipamiento de los bots y calcular su poder de combate.
* **Bono de Composición de Rol (Trinidad RPG):** Otorga un multiplicador de éxito directo si el grupo de bots enviados cuenta con al menos un **Tanque** y un **Sanador** (`hasTank` / `hasHealer`).
* **Inmersión con Diario Narrativo (LiveLog):** Una bitácora de eventos compacta que simula los combates, encuentros y peripecias de los bots en tiempo real mientras avanza la barra de progreso.
* **Persistencia Avanzada y Soporte Offline:** Si el jugador se desconecta del juego mientras la misión está en curso, el servidor procesa el fin de la misión de forma transparente (`OnPlayerLogin` offline hook).
* **Misiones Élite Dinámicas:** Módulo acoplado para misiones de fin de juego (Nivel 80) que exigen escalados de poder absurdamente altos y otorgan grandes botines de oro y honor.

---

🛠️ Instalación

1. Requisitos Previos
Un servidor basado en AzerothCore o TrinityCore con el módulo de Eluna Lua Engine correctamente compilado.
El módulo de NPCBots instalado y operativo en tu núcleo.
2. Configuración en el Servidor
Dirígete a la carpeta de scripts de Eluna (habitualmente ../lua_scripts/).
Sube los archivos BotQuest_Server.lua y BotQuest_Elites.lua.
Reinicia tu servidor o ejecuta .lua reload si tienes los permisos GM correspondientes.
3. Instalación en el Cliente
Extrae o clona la carpeta BotQuest dentro de la ruta de instalación de tu juego: World of Warcraft/Interface/AddOns/.
Asegúrate de que la ruta estructural contenga el archivo .toc en la raíz (ej. AddOns/BotQuest/BotQuest.toc).
Inicia el juego y asegúrate de marcar la casilla "Cargar accesorios antiguos" en la pestaña de Accesorios.

📊 Mecánicas de Combate y Éxito

La fórmula matemática implementada en el servidor evalúa probabilísticamente el riesgo frente al poder bruto:
Probabilidad Base: Definida por el nivel de peligro intrínseco de la misión:

Fácil (EASY): 55% base.
Normal (NORMAL): 40% base.
Difícil (HARD): 25% base.
Élite (ELITE): 10% base.

Escalado de Equipo: Multiplicador basado en los atributos de fuerza, agilidad e intelecto que tengan asignados los bots activos multiplicados por un coeficiente de 0.02 por punto.
Pesos de Clase Clave: Las clases híbridas y versátiles (como Paladines y Druidas) aportan un coeficiente multiplicador superior de 1.5 en el cálculo de poder debido a su adaptabilidad.
Límites de Seguridad: Para salvaguardar la experiencia de juego, las probabilidades de éxito final están topadas por el script entre un mínimo de 5% y un máximo de 95% (siempre existe riesgo latente o probabilidad de un milagro).

🕹️ Comandos del Sistema

Comandos de Chat (Jugador)
Puedes interactuar de manera directa utilizando los comandos de barra /bq o /botquest:
/bq — Abre o cierra de manera síncrona el Tablón de Misiones principal.
/bq stats — Desiega en tu chat local un informe histórico del total de misiones completadas con éxito, fallidas y el oro neto acumulado.
/bq reset — Comando de emergencia. Restablece el estado de los marcos locales, detiene los temporizadores visuales y limpia los datos corruptos de sesión.
/bql — Alterna la visualización independiente de la ventana de bitácora narrativa en tiempo real (LiveLog).

Comandos de Consola (Administrador / GM)
.bq reload — Vacía las cachés de memoria del servidor Eluna, recompila dinámicamente las listas de plantillas válidas desde item_template y regenera los pools de recompensas sin necesidad de reiniciar el reino.

⚙️ Configuración y Personalización
El archivo BotQuest_Server.lua cuenta con un bloque de configuración (CFG) modular al inicio del archivo que puedes editar para equilibrar la economía de tu servidor:

local CFG = {
    QUALITIES              = { 1, 2, 3 },       -- Calidades permitidas para el loot (Común, Poco Común, Raro)
    MIN_ITEM_LEVEL         = 5,                 -- Nivel de objeto mínimo para ingresar a las pools
    MAX_PER_POOL           = 300,               -- Límite máximo de ítems cacheados por rango de nivel
    COOLDOWN_DURATION      = 43200,             -- Cooldown de penalización por fallo (12 horas por defecto)
    
    -- Ajustes de porcentajes base
    BASE_SUCCESS = { EASY = 0.55, NORMAL = 0.40, HARD = 0.25, ELITE = 0.10 }
}

## 📁 Estructura del Proyecto

Para mantener tu repositorio ordenado, distribuye tus archivos de la siguiente manera:

```text
├── Addon/
│   └── BotQuest/
│       ├── BotQuest.toc          # Archivo de metadatos para la carga del cliente de WoW
│       ├── BotQuest_Core.lua     # Lógica central del cliente, eventos de red y persistencia
│       ├── BotQuest_Data.lua     # Repositorio local de misiones, formatos y pools de objetos
│       ├── BotQuest_UI.lua       # Contenedor del Tablón, renders de filas, resultados y Minimapa
│       └── BotQuest_LiveLog.lua  # Interfaz del diario de inmersión RPG y simulador de bitácora
└── Server/
    ├── BotQuest_Server.lua       # Núcleo maestro de Eluna (AzerothCore / TrinityCore)
    └── BotQuest_Elites.lua       # Inyector de misiones Élite de nivel alto para el servidor



