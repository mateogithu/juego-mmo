# Crónicas del Orden y el Caos — MMORPG Sandbox Medieval Infinito (v1.1 RC1)

MMORPG Sandbox 3D en **Godot Engine 4.x (GDScript 2.0 tipado estático)** optimizado para hardware integrado (**AMD Ryzen 3 / Radeon Vega 8 / 8 GB RAM**), 100% autocontenido sin dependencias externas faltantes.

## Características Principales
- **Mundo Abierto Procedural Infinito con Origen Flotante (*Floating Origin*):** Streaming determinista basado en `world_seed` (5x5 chunks en tierra y 7x7 con LOD reducido en vuelo alto, liberando sectores lejanos con `queue_free()`). Desplaza el origen automáticamente al superar 2.000 m para evitar temblores de precisión 3D, guardando únicamente deltas de estructuras y cofres por chunk `(chunk_x, chunk_z)`.
- **Cámara estilo The Elder Scrolls:** Alternancia fluida entre **Primera Persona** (arma/hechizos visibles en manos o vista de jinete sobre el dragón) y **Tercera Persona** orbital sobre el hombro, con retícula fija central (*Crosshair*).
- **Soporte Completo de Joystick (Gamepad) + Teclado/Mouse en paralelo:** Navegación en menús (`focus_neighbor`), combate, vuelo de dragón y construcción 100% jugables con control Xbox/PlayStation.
- **Sandbox 100% impulsado por jugadores (Cero Karma Automático):** Todos comienzan **Neutrales**. Sin barras de moral ni guardias NPC.
- **Orden vs. Caos y Avatares de Creadores (`F1`):** Cuentas GM preconfiguradas (`AvatarOrden` / `orden_creador` y `AvatarCaos` / `caos_creador`).
- **Evento Diario — Gracia Combativa:** Cada 24 horas reales el servidor elige a 1 jugador conectado al azar y duplica todas sus estadísticas (**x2.0 / +100%**, acumulable) con aura divina en el jugador y su dragón.
- **Dragones Voladores (`G` / `X`), 4 Clases Medievales, Construcción/Asedio (`B`), Economía (`I`), Tienda Cosmética 0% Pay-to-Win (`T`) y Mitología Oficial (`IntroLore.tscn`).**

## Controles (Teclado/Mouse y Gamepad)
| Acción | Teclado / Mouse | Gamepad (Xbox / PS) |
|---|---|---|
| Mover / Dirigir Dragón | `WASD` | Stick Izquierdo |
| Rotar Cámara 360° | Mouse | Stick Derecho (deadzone 0.15) |
| Alternar 1ª / 3ª Persona | `V` o Rueda del Mouse | Click Stick Derecho (`R3`) |
| Ataque Primario / Fuego Dragón / Construir | `Click Izq.` | Gatillo Derecho (`RT` / `R2`) |
| Bloqueo / Hechizo Rápido / Planear Dragón | `Click Der.` | Gatillo Izquierdo (`LT` / `L2`) |
| Saltar / Ascender en Dragón | `Espacio` | Sur (`A` / Cruz) |
| Esquive (*iframes*) / Descender Dragón | `Q`, `Alt`, `Ctrl` | Este (`B` / Círculo) |
| Invocar o Montar/Desmontar Dragón | `G` | Oeste (`X` / Cuadrado) |
| Interactuar / Saquear / Mercado / Puerta | `E` | Norte (`Y` / Triángulo) |
| Correr / Impulso Turbo en Dragón | `Shift` | Click Stick Izquierdo (`L3`) |
| Rotar Habilidad Rápida / Pieza Construcción | `1`–`4` / `1`–`6` | Bumpers (`LB` / `RB`) |
| Construcción / Inventario / Reinos / Tienda | `B` / `I` / `Tab` / `T` | Cruceta (`D-Pad` Arriba/Abajo/Izq/Der) |
| Consola de Avatar de Creador | `F1` | `F1` |
| Pausa / Volver | `Esc` | `Start` / `B` en menús |