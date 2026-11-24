# Crónicas del Orden y el Caos — Release 2.0 (Godot 4.x MMORPG)

MMORPG Sandbox Medieval 3D multijugador en tiempo real (**Godot Engine 4.x**, GDScript 2.0 estricto, renderizador `Mobile`), optimizado para **AMD Ryzen 3 / Radeon Vega 8 / 8 GB RAM**.

## Novedades de Release 2.0 — Guerra Territorial Orden vs. Caos y Ecosistema MMORPG Completo

1. **Modelos 3D Reales (.glb CC0) y Texturas PBR 1K:**
   - Personajes riggeados con `Skeleton3D` + `AnimationPlayer` (76 animaciones) en `Assets/Models/`: `player_knight.glb`, `player_mage.glb`, `player_rogue.glb`, `player_cleric.glb`, `player_ranger.glb` y dragón alado riggeado `dragon.glb`.
   - Texturas PBR 1K (Albedo, Normal OpenGL y Roughness) de pasto, tierra, roca y piedra medieval en `Assets/Textures/` conectadas a `terrain.gdshader` y estructuras.
2. **Intro Cinemática 3D en Tiempo Real (`Client/UI/IntroCinematic.tscn`):**
   - Valle tormentoso con choque energético dorado del Orden vs. llamas del Caos, dragones surcando el cielo y los 4 Actos oficiales del guion (con botón **"Saltar [ESC]"** y acceso **"Ver Historia"** desde el menú principal). Bypass automático en modo `--server`.
3. **Dos Zonas Seguras Indestructibles + Guerra Territorial Asimétrica + Reinicio de Temporada (30 Días):**
   - **Santuario del Alba / Bastión del Orden** `(0, 0)` y **Ciudadela del Caos** `(260, 260)`: amurallados, PvP y robos 100% bloqueados (*"Bajo protección del Santuario"*), con Forja, Alquimia, Fogata de Cocina, Tablón de Mercado y Ermita inicial.
   - Al cruzar hacia el mundo abierto suena cuerno de guerra + banner rojo (*"⚔️ HAS ENTRADO EN ZONA PVP Y CONQUISTA"*) con **botín total (Full Loot)**.
   - El **Orden** conquista construyendo ciudades/casas/murallas/altares; el **Caos** conquista sitiando y destruyendo estructuras.
   - **Temporada Mensual (30 días):** proclama ganador, reinicia únicamente edificaciones y control territorial, conservando intactos niveles, mochilas (150), equipo, oro y dragones.
4. **Intervención de los Dioses, Balanceo Poblacional y Modo Incógnito (`GodsInterventionSystem.gd`):**
   - `AvatarOrden` (`orden_creador`) y `AvatarCaos` (`caos_creador`): rango **♾️**, **Maná/Estamina/Magia ilimitados (coste 0, cooldown 0)**, mochila infinita, cosméticos gratis y acceso solitario a mazmorras.
   - Botón exclusivo **`🎭 Encarnar como Novato (Nivel 1)`** en `F1` para mezclarse de incógnito ocultando `♾️` y aura, botón **`⚡ Gracia Combativa a Toda mi Facción`** y **`🔄 Reiniciar Temporada`**.
   - **Bendición de Equilibrio** automática cuando una facción supera ampliamente en población a la otra (+35% daño, +30% defensa, +50% XP).
5. **Niveles 1–8.000, Jefes Dragón Supremos y Dragón en la Mochila (150 Espacios):**
   - Los **Jefes Dragón Supremos** del **Valle Dracónico** sueltan la **`Piedra de Vínculo de Dragón`** (`dragon_mount_stone`).
   - Invocar el dragón (`G` / `X`) desata una tormenta con rayos y trueno, FOV dinámico (`72°–92°`) y aliento de fuego. Al desmontar regresa automáticamente a tu mochila de 150 espacios (y puede ser saqueado si morís en PvP).
6. **Casas de Jugadores, Cajones de Guardado (60 Espacios), Mazmorras de 4 Jugadores y Forja Elemental:**
   - Construcción de casas (`house_foundation`, `house_wall`, `house_roof`, `house_door`) y **Cajón de Guardado** con llave (`storage_chest`) persistente en `user://server_database.json`.
   - **Sistema de Grupo (4 jugadores)** sin fuego amigo, XP compartida y requisito de 4 jugadores para entrar a las **Mazmorras Complejas de 3 Cámaras** (`Catacumbas del Caos`, `Cripta del Orden Antiguo`).
   - **Sets de Armadura de 4 piezas** (Yelmo, Pecho, Piernas, Botas — Pesada/Media/Ligera con pasivas) y **Forja Elemental** (Fuego, Rayo, Hielo).
   - **Economía 100% de Jugadores** (sin tiendas NPC), **Trueque Directo P2P**, **Supervivencia y Cocina en Fogata**, **Mapa Mundial de 5 Regiones (`M`) + Minimapa + 6 Ermitas (Wayshrines)** y **Creador de Personaje 3D** (5 Clases, 5 Razas).

## Controles Rápidos (Teclado/Mouse y Joystick en paralelo)
- **Movimiento / Cámara:** `WASD` / Stick Izquierdo • Mouse / Stick Derecho • `V` / `R3` / Rueda: 1ª/3ª Persona
- **Combate:** `LMB` / `RT`: Atacar / Aliento Dragón • `RMB` / `LT`: Bloquear / Planear • `1–4` / `LB-RB`: Habilidades • `Q` / `B`: Esquivar (iframes)
- **Mundo y Menús:** `G` / `X`: Invocar/Guardar Dragón • `E` / `Y`: Interactuar (Botín, Cajones, Ermitas, Forja, Fogata, Mazmorras, Recursos) • `M`: Mapa del Mundo • `B`: Construir Casas/Murallas • `I`: Mochila/Forja/Mercado • `Tab`: Grupo/Reinos/Contratos • `T`: Tienda Cosmética • `F1`: Consola de Avatar Primordial

## Lanzar Servidor Dedicado (Headless)
```bash
godot --headless --path . -- --server --port=7777
```