extends Node

## Global configuration for Cronicas del Orden y el Caos (Release 2.0).
## Includes 5 Classes, 5 Races, 2 Indestructible Safe Zones, 5 World Regions + Wayshrines,
## 30-Day Monthly Territorial Seasons, Levels 1-8000 (Infinity for Admins), 150-Slot Backpack,
## House & Storage Building, 4-Piece Armor Sets, Elemental Forging, Survival Cooking,
## Supreme Dragon World Bosses, 4-Player Dungeons, and Official 4-Act Cinematic Script.

const GAME_TITLE: String = "Crónicas del Orden y el Caos"
const PROTOCOL_VERSION: String = "2.0.0"

# Network configuration
const DEFAULT_HOST: String = "127.0.0.1"
const DEFAULT_PORT: int = 7777
const MAX_CLIENTS: int = 128
const SNAPSHOT_RATE_HZ: float = 20.0
const SNAPSHOT_INTERVAL: float = 1.0 / SNAPSHOT_RATE_HZ

# Roles & Power Hierarchy
const ROLE_PLAYER: String = "PLAYER"
const ROLE_AVATAR_ORDEN: String = "AVATAR_ORDEN"
const ROLE_AVATAR_CAOS: String = "AVATAR_CAOS"
const MAX_PLAYER_LEVEL: int = 8000
const BACKPACK_MAX_SLOTS: int = 150
const STORAGE_CHEST_SLOTS: int = 60
const MAX_PARTY_SIZE: int = 4
const DUNGEON_REQUIRED_PARTY: int = 4

# Factions / Alignment
const PHILOSOPHY_NEUTRAL: String = "Neutral"
const PHILOSOPHY_ORDER: String = "El Orden"
const PHILOSOPHY_CHAOS: String = "El Caos"

# Gracia Combativa & Monthly Territorial Season
const COMBAT_GRACE_DURATION_SEC: float = 86400.0
const COMBAT_GRACE_MULTIPLIER: float = 2.0
const SEASON_DURATION_SEC: float = 2592000.0 # 30 real days
const COOKING_BUFF_DURATION_SEC: float = 900.0 # 15 minutes

# Infinite procedural world streaming & hardware budget (Ryzen 3 / Vega 8 / 8GB RAM)
const CHUNK_SIZE: float = 64.0
const CHUNK_RESOLUTION: int = 20
const GROUND_CHUNK_RADIUS: int = 2
const FLIGHT_CHUNK_RADIUS: int = 3
const FLIGHT_HIGH_ALTITUDE_THRESHOLD: float = 22.0
const FLOATING_ORIGIN_THRESHOLD: float = 2000.0
const WATER_LEVEL: float = -3.0
const DAY_CYCLE_DURATION_SEC: float = 600.0

var world_seed: int = 847291
var world_origin_offset: Vector3 = Vector3.ZERO
var _noise_continental: FastNoiseLite = null
var _noise_ridges: FastNoiseLite = null
var _noise_rivers: FastNoiseLite = null

# Physics collision layers (bitmasks)
const LAYER_TERRAIN: int = 1
const LAYER_PLAYERS: int = 2
const LAYER_DRAGONS: int = 4
const LAYER_BUILDINGS: int = 8
const LAYER_PROJECTILES: int = 16
const LAYER_INTERACTABLES: int = 32

# Official 4-Act Intro Cinematic Script (Release 2.0)
const INTRO_CINEMATIC_ACTS: Array[Dictionary] = [
	{
		"act": "Acto I — El Equilibrio Primordial",
		"duration": 7.5,
		"text": "Antes de que existieran los reinos, el mundo respiraba bajo dos fuerzas eternas: la Luz Inmutable del Orden, que forjó la piedra, la ley y la memoria; y la Llama Indómita del Caos, que dio origen al viento, la ambición y el cambio."
	},
	{
		"act": "Acto II — La Ruptura y la Guerra de los Dragones",
		"duration": 7.5,
		"text": "Cuando los antiguos reyes intentaron encadenar ambas fuerzas, el cielo se quebró. Los dragones ancestrales despertaron de las cumbres, las fortalezas ardieron y los cinco reinos quedaron divididos entre ruinas, bestias colosales y fronteras sin ley."
	},
	{
		"act": "Acto III — El Descenso de los Avatares",
		"duration": 7.5,
		"text": "Cada veinticuatro horas, el firmamento vuelve a abrirse. Los dos Avatares supremos descienden al mundo mortal para reclamar dominio sobre la tierra y otorgar la Gracia Combativa a los guerreros que demuestren ser dignos en batalla."
	},
	{
		"act": "Acto IV — El Santuario y la Frontera",
		"duration": 8.0,
		"text": "Tu viaje comienza tras las murallas del Santuario del Alba, el último refugio donde las armas permanecen envainadas. Pero al cruzar sus puertas hacia el mundo abierto, no existen reglas ni piedad: forjá tu acero, dominá los cielos sobre un dragón y defendé tu botín con tu vida."
	}
]

# Legacy Lore Chapters (kept for IntroLore.tscn compatibility)
const OFFICIAL_LORE_CHAPTERS: Array[String] = [
	"Antes de que existieran las murallas o las cenizas, dos Arquitectos Primordiales forjaron este mundo desde el vacío: El Orden, creador de la piedra, la ley, los reinos y el comercio que une a los mortales; y El Caos, señor de la llama indómita, la libertad absoluta y la tempestad que derrumba todo imperio.",
	"Incapaces de destruirse entre sí, entregaron a los mortales la magia arcana y el dominio de los dragones, dejando que sean ellos quienes decidan el destino de la tierra. Aquí nadie nace bendecido ni maldito: llegás como un alma neutral, y tus propias manos escribirán si levantás ciudades bajo el estandarte del Orden o si las reducís a escombros bajo la sombra del Caos.",
	"Pero los dioses observan. Una vez cada ciclo solar, los Avatares del Orden y del Caos descienden de los cielos y eligen a un mortal al azar —sin importar su linaje ni su fuerza— para otorgarle la Gracia Combativa, duplicando todo su poder durante veinticuatro horas para inclinar la balanza de la historia."
]

# Two Indestructible Safe Zones (Capital Sanctuaries)
const SAFE_ZONES: Array[Dictionary] = [
	{
		"id": "bastion_orden",
		"name": "Santuario del Alba (Bastión del Orden)",
		"faction": PHILOSOPHY_ORDER,
		"center_xz": Vector2(0.0, 0.0),
		"radius": 34.0
	},
	{
		"id": "ciudadela_caos",
		"name": "Ciudadela del Caos (Santuario del Caos)",
		"faction": PHILOSOPHY_CHAOS,
		"center_xz": Vector2(260.0, 260.0),
		"radius": 34.0
	}
]

# 5 Main World Regions + Dragon Valley
const WORLD_REGIONS: Array[Dictionary] = [
	{"id": "bastion_alba", "name": "Bastión del Alba", "center_xz": Vector2(0.0, 0.0), "radius": 130.0, "default_owner": PHILOSOPHY_ORDER, "color": Color(0.95, 0.84, 0.38)},
	{"id": "paramos_ceniza", "name": "Páramos de Ceniza", "center_xz": Vector2(220.0, 200.0), "radius": 160.0, "default_owner": PHILOSOPHY_CHAOS, "color": Color(0.92, 0.3, 0.18)},
	{"id": "bosque_susurros", "name": "Bosque de Susurros", "center_xz": Vector2(-190.0, 140.0), "radius": 150.0, "default_owner": PHILOSOPHY_NEUTRAL, "color": Color(0.26, 0.72, 0.36)},
	{"id": "cumbres_escarcha", "name": "Cumbres de Escarcha", "center_xz": Vector2(-170.0, -200.0), "radius": 165.0, "default_owner": PHILOSOPHY_NEUTRAL, "color": Color(0.58, 0.84, 1.0)},
	{"id": "costa_corsarios", "name": "Costa de los Corsarios", "center_xz": Vector2(200.0, -180.0), "radius": 170.0, "default_owner": PHILOSOPHY_NEUTRAL, "color": Color(0.24, 0.62, 0.78)}
]

# Discoverable Wayshrines for Fast Travel via World Map (M)
const WAYSHRINES: Array[Dictionary] = [
	{"id": "ws_alba", "name": "Ermita del Santuario del Alba", "region": "Bastión del Alba", "xz": Vector2(0.0, 22.0), "default_unlocked": true},
	{"id": "ws_caos", "name": "Ermita de la Ciudadela del Caos", "region": "Páramos de Ceniza", "xz": Vector2(260.0, 240.0), "default_unlocked": true},
	{"id": "ws_susurros", "name": "Ermita del Bosque de Susurros", "region": "Bosque de Susurros", "xz": Vector2(-175.0, 125.0), "default_unlocked": false},
	{"id": "ws_escarcha", "name": "Ermita de las Cumbres de Escarcha", "region": "Cumbres de Escarcha", "xz": Vector2(-150.0, -185.0), "default_unlocked": false},
	{"id": "ws_corsarios", "name": "Ermita de la Costa de los Corsarios", "region": "Costa de los Corsarios", "xz": Vector2(180.0, -165.0), "default_unlocked": false},
	{"id": "ws_draconico", "name": "Ermita del Valle Dracónico", "region": "Valle Dracónico", "xz": Vector2(30.0, -235.0), "default_unlocked": false}
]

# 5 Playable Races for the 3D Character Creator
const RACES: Dictionary = {
	"HUMAN_VALLEY": {"name": "Humano del Valle", "desc": "Versátil constructor de reinos y comerciante incansable.", "default_skin": Color(0.86, 0.69, 0.56), "scale_y": 1.0},
	"ASTRAL_ELF": {"name": "Elfo Astral", "desc": "Alto y ágil, afín a la magia antigua de las ermitas.", "default_skin": Color(0.9, 0.84, 0.78), "scale_y": 1.07},
	"DRACONID": {"name": "Dracónido", "desc": "Linaje escamoso forjado en fuego primordial y tempestad.", "default_skin": Color(0.58, 0.24, 0.2), "scale_y": 1.06},
	"FORGE_DWARF": {"name": "Enano de la Forja", "desc": "Robusto maestro del yunque, el hierro y la piedra.", "default_skin": Color(0.82, 0.64, 0.5), "scale_y": 0.86},
	"ABYSS_SHADOW": {"name": "Sombra del Abismo", "desc": "Ser crepuscular de ojos luminosos nacido en la frontera sin ley.", "default_skin": Color(0.32, 0.28, 0.38), "scale_y": 1.02}
}

# 5 Playable Medieval Magic Classes
const CLASSES: Dictionary = {
	"ARCANE_KNIGHT": {
		"name": "Caballero Arcano",
		"role": "Vanguardia / Tanque con Espada y Escudo",
		"description": "Maestro del acero rúnico y barreras arcanas. Resiste asedios y protege escuadras.",
		"accent_color": Color(0.28, 0.62, 0.96),
		"weapon_style": "sword_shield",
		"max_hp": 145.0,
		"max_mana": 95.0,
		"max_stamina": 125.0,
		"attack_power": 24.0,
		"spell_power": 20.0,
		"defense": 15.0,
		"move_speed": 6.4,
		"abilities": [
			{"id": "runic_slash", "name": "Tajo Rúnico", "cost_mana": 18.0, "cost_stamina": 10.0, "cooldown": 4.0, "damage": 36.0, "range": 14.0, "type": "projectile", "color": Color(0.35, 0.78, 1.0), "desc": "Onda arcana cortante evadible."},
			{"id": "arcane_shield", "name": "Escudo Arcano", "cost_mana": 25.0, "cost_stamina": 0.0, "cooldown": 10.0, "shield": 70.0, "duration": 6.0, "type": "shield", "color": Color(0.3, 0.65, 1.0), "desc": "Barrera mágica que absorbe daño."},
			{"id": "aegis_slam", "name": "Impacto de Égida", "cost_mana": 22.0, "cost_stamina": 20.0, "cooldown": 8.0, "damage": 40.0, "radius": 5.5, "type": "aoe", "color": Color(0.45, 0.8, 1.0), "desc": "Golpe sísmico que daña enemigos cercanos."},
			{"id": "oath_surge", "name": "Impulso del Juramento", "cost_mana": 30.0, "cost_stamina": 0.0, "cooldown": 16.0, "buff_mult": 1.25, "duration": 8.0, "type": "buff", "color": Color(0.95, 0.85, 0.4), "desc": "Aumenta ataque y defensa un 25% por 8s."}
		]
	},
	"PYROMANCER": {
		"name": "Hechicero Elemental",
		"role": "Artillería Arcana / Fuego, Rayo y Hielo",
		"description": "Canaliza llamas primordiales y energía elemental capaz de derribar murallas y jefes.",
		"accent_color": Color(0.98, 0.42, 0.14),
		"weapon_style": "staff",
		"max_hp": 105.0,
		"max_mana": 155.0,
		"max_stamina": 95.0,
		"attack_power": 15.0,
		"spell_power": 35.0,
		"defense": 8.0,
		"move_speed": 6.6,
		"abilities": [
			{"id": "fireball", "name": "Bola de Fuego", "cost_mana": 22.0, "cost_stamina": 0.0, "cooldown": 2.5, "damage": 44.0, "range": 32.0, "splash": 3.5, "type": "projectile", "color": Color(1.0, 0.42, 0.1), "desc": "Proyectil ígneo explosivo para PvP y asedio."},
			{"id": "flame_nova", "name": "Nova Elemental", "cost_mana": 30.0, "cost_stamina": 10.0, "cooldown": 7.0, "damage": 48.0, "radius": 6.5, "type": "aoe", "color": Color(1.0, 0.55, 0.12), "desc": "Anillo expansivo elemental alrededor del lanzador."},
			{"id": "meteor_strike", "name": "Lluvia de Cenizas", "cost_mana": 45.0, "cost_stamina": 0.0, "cooldown": 12.0, "damage": 70.0, "range": 28.0, "splash": 5.5, "type": "projectile", "color": Color(1.0, 0.2, 0.05), "desc": "Proyectil pesado de asedio contra ciudades y jefes."},
			{"id": "blazing_dash", "name": "Carrera Ígnea", "cost_mana": 20.0, "cost_stamina": 15.0, "cooldown": 9.0, "dash_dist": 10.0, "type": "dash", "color": Color(1.0, 0.65, 0.2), "desc": "Impulso veloz con invulnerabilidad breve."}
		]
	},
	"SHADOW_ASSASSIN": {
		"name": "Sombra Oscura",
		"role": "Infiltración / Sigilo y Críticos",
		"description": "Acechador letal de la frontera sin ley. Domina el sigilo, la movilidad y las emboscadas.",
		"accent_color": Color(0.68, 0.32, 0.94),
		"weapon_style": "daggers",
		"max_hp": 110.0,
		"max_mana": 95.0,
		"max_stamina": 150.0,
		"attack_power": 31.0,
		"spell_power": 18.0,
		"defense": 9.0,
		"move_speed": 7.5,
		"abilities": [
			{"id": "shadow_dagger", "name": "Daga Umbría", "cost_mana": 14.0, "cost_stamina": 12.0, "cooldown": 2.2, "damage": 34.0, "range": 22.0, "type": "projectile", "color": Color(0.68, 0.25, 0.95), "desc": "Hoja veloz de sombra."},
			{"id": "shadow_step", "name": "Paso Sombrío", "cost_mana": 20.0, "cost_stamina": 20.0, "cooldown": 7.0, "dash_dist": 12.0, "type": "dash", "color": Color(0.5, 0.15, 0.85), "desc": "Salto con invulnerabilidad temporal."},
			{"id": "smoke_vanish", "name": "Velo de Sombras", "cost_mana": 26.0, "cost_stamina": 10.0, "cooldown": 13.0, "duration": 5.0, "type": "stealth", "color": Color(0.28, 0.12, 0.42), "desc": "Invisibilidad táctica por 5s."},
			{"id": "execution_flurry", "name": "Ejecución Letal", "cost_mana": 25.0, "cost_stamina": 30.0, "cooldown": 10.0, "damage": 62.0, "radius": 4.2, "type": "aoe", "color": Color(0.85, 0.18, 0.55), "desc": "Torbellino crítico letal de corto alcance."}
		]
	},
	"VALLEY_HUNTER": {
		"name": "Cazador del Valle",
		"role": "Tirador / Movilidad y Precisión",
		"description": "Rastreador experto de bosques y cumbres. Castiga a distancia y caza dragones ancestrales.",
		"accent_color": Color(0.28, 0.84, 0.45),
		"weapon_style": "bow",
		"max_hp": 115.0,
		"max_mana": 100.0,
		"max_stamina": 140.0,
		"attack_power": 28.0,
		"spell_power": 22.0,
		"defense": 10.0,
		"move_speed": 7.2,
		"abilities": [
			{"id": "piercing_arrow", "name": "Flecha Perforante", "cost_mana": 12.0, "cost_stamina": 14.0, "cooldown": 2.0, "damage": 38.0, "range": 36.0, "type": "projectile", "color": Color(0.35, 0.96, 0.52), "desc": "Disparo de alta velocidad preciso hacia la retícula."},
			{"id": "volley_rain", "name": "Andanada del Bosque", "cost_mana": 24.0, "cost_stamina": 18.0, "cooldown": 7.5, "damage": 46.0, "radius": 6.0, "type": "aoe", "color": Color(0.45, 0.9, 0.4), "desc": "Ráfaga de flechas en área."},
			{"id": "evasive_leap", "name": "Salto del Cazador", "cost_mana": 15.0, "cost_stamina": 18.0, "cooldown": 6.5, "dash_dist": 11.0, "type": "dash", "color": Color(0.4, 0.88, 0.65), "desc": "Reposicionamiento veloz con invulnerabilidad."},
			{"id": "hunter_focus", "name": "Ojo de Halcón", "cost_mana": 25.0, "cost_stamina": 0.0, "cooldown": 14.0, "buff_mult": 1.3, "duration": 9.0, "type": "buff", "color": Color(0.95, 0.9, 0.35), "desc": "Aumenta todo el daño un 30% durante 9s."}
		]
	},
	"WAR_CLERIC": {
		"name": "Clérigo de Guerra",
		"role": "Soporte Bélico / Sanación y Escudos",
		"description": "Portador de luz y restauración grupal. Esencial en mazmorras de 4 jugadores y asedios.",
		"accent_color": Color(0.96, 0.84, 0.32),
		"weapon_style": "mace_shield",
		"max_hp": 130.0,
		"max_mana": 145.0,
		"max_stamina": 105.0,
		"attack_power": 21.0,
		"spell_power": 30.0,
		"defense": 13.0,
		"move_speed": 6.3,
		"abilities": [
			{"id": "divine_heal", "name": "Sanación Grupal", "cost_mana": 26.0, "cost_stamina": 0.0, "cooldown": 5.0, "heal": 65.0, "radius": 12.0, "type": "heal", "color": Color(0.98, 0.92, 0.5), "desc": "Sana al lanzador y a su grupo (Party) cercano."},
			{"id": "radiant_barrier", "name": "Barrera Radiante", "cost_mana": 28.0, "cost_stamina": 0.0, "cooldown": 9.5, "shield": 85.0, "duration": 7.0, "type": "shield", "color": Color(1.0, 0.95, 0.65), "desc": "Escudo sagrado que absorbe daño."},
			{"id": "judgment_beam", "name": "Haz de Juicio", "cost_mana": 24.0, "cost_stamina": 0.0, "cooldown": 5.5, "damage": 42.0, "range": 28.0, "type": "projectile", "color": Color(1.0, 0.92, 0.45), "desc": "Proyectil de luz pura."},
			{"id": "consecrated_ground", "name": "Suelo Consagrado", "cost_mana": 34.0, "cost_stamina": 10.0, "cooldown": 13.0, "damage": 35.0, "heal": 35.0, "radius": 7.0, "type": "aoe", "color": Color(1.0, 0.88, 0.35), "desc": "Daña enemigos y sana aliados cercanos."}
		]
	}
}

# Destructible Player Building Catalog (Fortifications, Houses & Storage Chests)
const BUILD_PIECES: Dictionary = {
	"wall": {"name": "Muralla de Piedra", "max_hp": 480.0, "size": Vector3(6.0, 4.5, 1.4), "cost": {"stone": 12, "wood": 4}, "color": Color(0.55, 0.55, 0.58), "territory_pts": 15, "desc": "Expande territorio del Orden y defiende ciudades."},
	"gate": {"name": "Puerta Fortificada", "max_hp": 400.0, "size": Vector3(6.0, 4.8, 1.4), "cost": {"stone": 10, "wood": 10}, "color": Color(0.46, 0.34, 0.22), "territory_pts": 15, "desc": "Cerradura para dueño/grupo (E / Y)."},
	"tower": {"name": "Torre de Vigía", "max_hp": 650.0, "size": Vector3(4.2, 9.5, 4.2), "cost": {"stone": 20, "wood": 8}, "color": Color(0.5, 0.5, 0.54), "territory_pts": 25, "desc": "Torre de defensa y expansión territorial."},
	"house_foundation": {"name": "Cimiento de Casa", "max_hp": 520.0, "size": Vector3(6.0, 0.7, 6.0), "cost": {"stone": 10, "wood": 8}, "color": Color(0.52, 0.48, 0.44), "territory_pts": 10, "desc": "Base para construir tu casa y colocar cajones."},
	"house_wall": {"name": "Pared de Casa", "max_hp": 360.0, "size": Vector3(6.0, 3.8, 0.6), "cost": {"wood": 10, "stone": 4}, "color": Color(0.46, 0.32, 0.2), "territory_pts": 8, "desc": "Pared de madera y piedra para refugio."},
	"house_roof": {"name": "Techo de Casa", "max_hp": 320.0, "size": Vector3(6.4, 1.2, 6.4), "cost": {"wood": 12}, "color": Color(0.36, 0.2, 0.16), "territory_pts": 6, "desc": "Techo medieval para cerrar tu refugio."},
	"house_door": {"name": "Puerta con Cerradura", "max_hp": 380.0, "size": Vector3(6.0, 3.8, 0.7), "cost": {"wood": 10, "iron_ore": 4}, "color": Color(0.42, 0.28, 0.16), "territory_pts": 10, "desc": "Solo el dueño o su grupo pueden abrirla (E / Y)."},
	"storage_chest": {"name": "Cajón de Guardado (60 Esp.)", "max_hp": 340.0, "size": Vector3(1.6, 1.1, 1.1), "cost": {"wood": 14, "iron_ore": 6}, "color": Color(0.48, 0.3, 0.14), "territory_pts": 5, "desc": "Guarda ítems, sets y tu Dragón fuera de la mochila (E / Y)."},
	"altar_order": {"name": "Altar del Orden", "max_hp": 560.0, "size": Vector3(3.2, 3.8, 3.2), "cost": {"stone": 15, "arcane_ore": 8}, "color": Color(0.88, 0.78, 0.36), "territory_pts": 40, "desc": "Reclama dominio territorial para El Orden."},
	"altar_chaos": {"name": "Altar del Caos", "max_hp": 560.0, "size": Vector3(3.2, 3.8, 3.2), "cost": {"stone": 15, "arcane_ore": 8}, "color": Color(0.84, 0.22, 0.16), "territory_pts": 40, "desc": "Consagra la región bajo El Caos."},
	"trade_post": {"name": "Puesto Comercial", "max_hp": 320.0, "size": Vector3(4.5, 3.6, 3.5), "cost": {"wood": 14, "stone": 6}, "color": Color(0.62, 0.44, 0.24), "territory_pts": 12, "desc": "Puesto personal para comerciar en el Mercado."}
}

# Items, 4-Piece Armor Sets (Heavy/Medium/Light), Elemental Weapons, Survival Food & Dragon Stone
const ITEMS: Dictionary = {
	# Gatherable resources (with rarity & reference player-economy value)
	"wood": {"name": "Madera Antigua", "type": "resource", "rarity": "Común", "rarity_col": Color(0.82, 0.84, 0.86), "value": 4},
	"stone": {"name": "Piedra Tallada", "type": "resource", "rarity": "Común", "rarity_col": Color(0.82, 0.84, 0.86), "value": 4},
	"iron_ore": {"name": "Mineral de Hierro", "type": "resource", "rarity": "Poco Común", "rarity_col": Color(0.35, 0.92, 0.45), "value": 9},
	"silver_ore": {"name": "Veta de Plata", "type": "resource", "rarity": "Raro", "rarity_col": Color(0.42, 0.75, 1.0), "value": 25},
	"gold_ore": {"name": "Veta de Oro Puro", "type": "resource", "rarity": "Épico", "rarity_col": Color(0.85, 0.45, 1.0), "value": 55},
	"arcane_ore": {"name": "Cristal Arcano", "type": "resource", "rarity": "Raro", "rarity_col": Color(0.35, 0.82, 1.0), "value": 18},
	"alchemy_herb": {"name": "Hierba Alquímica", "type": "resource", "rarity": "Poco Común", "rarity_col": Color(0.35, 0.96, 0.58), "value": 11},
	"raw_meat": {"name": "Carne Fresca de Caza", "type": "resource", "rarity": "Común", "rarity_col": Color(0.95, 0.65, 0.55), "value": 8},
	"dungeon_essence": {"name": "Esencia de Mazmorra", "type": "resource", "rarity": "Épico", "rarity_col": Color(0.78, 0.42, 1.0), "value": 90},
	"mythic_ingot": {"name": "Lingote Mítico", "type": "resource", "rarity": "Épico", "rarity_col": Color(0.82, 0.45, 1.0), "value": 110},
	"arcane_gem": {"name": "Gema Arcana Pura", "type": "resource", "rarity": "Épico", "rarity_col": Color(0.45, 0.88, 1.0), "value": 115},
	"boss_blueprint": {"name": "Plano de Armadura Mítica", "type": "resource", "rarity": "Legendario", "rarity_col": Color(1.0, 0.8, 0.25), "value": 240},

	# Supreme Dragon Mount Item (stored inside 150-slot backpack or house chest!)
	"dragon_mount_stone": {"name": "Sello de Dragón Ancestral", "type": "mount", "rarity": "Mítico", "rarity_col": Color(1.0, 0.45, 0.15), "value": 2500},

	# Consumables & Cooked Meals (Hunger restoration + 15-min buffs)
	"health_potion": {"name": "Poción de Vida", "type": "consumable", "heal": 75.0, "rarity": "Común", "value": 25},
	"mana_potion": {"name": "Poción de Maná", "type": "consumable", "mana": 80.0, "rarity": "Común", "value": 25},
	"elixir_fury": {"name": "Elixir de Furia Arcana", "type": "consumable", "buff_mult": 1.25, "duration": 45.0, "rarity": "Raro", "value": 70},
	"siege_charge": {"name": "Carga de Asedio", "type": "consumable", "siege_damage": 220.0, "rarity": "Raro", "value": 65},
	"roasted_feast": {"name": "Asado del Valle (+15m Vida)", "type": "food", "hunger": 55.0, "food_buff": "hp", "rarity": "Poco Común", "value": 30},
	"arcane_stew": {"name": "Estofado Arcano (+15m Maná/Poder)", "type": "food", "hunger": 65.0, "food_buff": "power", "rarity": "Raro", "value": 45},
	"traveler_bread": {"name": "Pan de Hierbas (+Saciedad)", "type": "food", "hunger": 38.0, "food_buff": "stamina", "rarity": "Común", "value": 15},

	# 4-Piece Armor Sets: HEAVY (Placas: +25% HP, +20% Mitigation)
	"heavy_helmet": {"name": "Yelmo de Placas (Pesada)", "type": "helmet", "armor_line": "heavy", "def_bonus": 6.0, "hp_bonus": 25.0, "rarity": "Épico", "value": 180},
	"heavy_chest": {"name": "Pechera de Placas (Pesada)", "type": "chest", "armor_line": "heavy", "def_bonus": 12.0, "hp_bonus": 55.0, "rarity": "Épico", "value": 260},
	"heavy_legs": {"name": "Grebas de Placas (Pesada)", "type": "legs", "armor_line": "heavy", "def_bonus": 9.0, "hp_bonus": 35.0, "rarity": "Épico", "value": 210},
	"heavy_boots": {"name": "Botas de Placas (Pesada)", "type": "boots", "armor_line": "heavy", "def_bonus": 5.0, "hp_bonus": 20.0, "rarity": "Épico", "value": 160},

	# 4-Piece Armor Sets: MEDIUM (Cuero/Escamas: +20% Speed, +18% Crit, -15% Stamina Cost)
	"medium_helmet": {"name": "Capucha de Escamas (Media)", "type": "helmet", "armor_line": "medium", "def_bonus": 4.0, "atk_bonus": 6.0, "rarity": "Épico", "value": 180},
	"medium_chest": {"name": "Cota de Escamas (Media)", "type": "chest", "armor_line": "medium", "def_bonus": 8.0, "atk_bonus": 12.0, "rarity": "Épico", "value": 260},
	"medium_legs": {"name": "Pantalones de Escamas (Media)", "type": "legs", "armor_line": "medium", "def_bonus": 6.0, "atk_bonus": 8.0, "rarity": "Épico", "value": 210},
	"medium_boots": {"name": "Botas de Sombra (Media)", "type": "boots", "armor_line": "medium", "def_bonus": 4.0, "atk_bonus": 5.0, "rarity": "Épico", "value": 160},

	# 4-Piece Armor Sets: LIGHT (Túnicas Arcanas: +30% Spell/Heal, +25% Mana Regen, -20% Mana Cost)
	"light_helmet": {"name": "Diadema Arcana (Ligera)", "type": "helmet", "armor_line": "light", "def_bonus": 3.0, "spell_bonus": 8.0, "rarity": "Épico", "value": 180},
	"light_chest": {"name": "Túnica Arcana (Ligera)", "type": "chest", "armor_line": "light", "def_bonus": 5.0, "spell_bonus": 16.0, "rarity": "Épico", "value": 260},
	"light_legs": {"name": "Calzas Rúnicas (Ligera)", "type": "legs", "armor_line": "light", "def_bonus": 4.0, "spell_bonus": 10.0, "rarity": "Épico", "value": 210},
	"light_boots": {"name": "Sandalias Astrales (Ligera)", "type": "boots", "armor_line": "light", "def_bonus": 3.0, "spell_bonus": 7.0, "rarity": "Épico", "value": 160},

	# Elemental Weapons & Staves (Fire = Pure DMG / High Cost, Lightning = Balanced / Stun, Ice = Heal/Shield/Slow)
	"iron_blade": {"name": "Espada de Hierro", "type": "weapon", "element": "none", "atk_bonus": 9.0, "rarity": "Común", "value": 60},
	"fire_greatsword": {"name": "Mandoble de Fuego (Fuego)", "type": "weapon", "element": "fire", "atk_bonus": 34.0, "spell_bonus": 12.0, "rarity": "Legendario", "value": 460},
	"lightning_blade": {"name": "Espada de Rayo (Rayo)", "type": "weapon", "element": "lightning", "atk_bonus": 26.0, "spell_bonus": 14.0, "rarity": "Legendario", "value": 440},
	"ice_halberd": {"name": "Alabarda Glacial (Hielo)", "type": "weapon", "element": "ice", "atk_bonus": 22.0, "def_bonus": 12.0, "rarity": "Legendario", "value": 440},
	"fire_staff": {"name": "Bastón de Llama Pura (Fuego)", "type": "weapon", "element": "fire", "spell_bonus": 38.0, "rarity": "Legendario", "value": 470},
	"lightning_staff": {"name": "Bastón de Tormenta (Rayo)", "type": "weapon", "element": "lightning", "spell_bonus": 30.0, "rarity": "Legendario", "value": 450},
	"ice_staff": {"name": "Bastón de Restauración Glacial (Hielo)", "type": "weapon", "element": "ice", "spell_bonus": 28.0, "heal_bonus": 0.4, "rarity": "Legendario", "value": 460},
	"lightning_daggers": {"name": "Dagas de Relámpago (Rayo)", "type": "weapon", "element": "lightning", "atk_bonus": 29.0, "rarity": "Legendario", "value": 440},
	"fire_bow": {"name": "Arco de Ceniza Ardiente (Fuego)", "type": "weapon", "element": "fire", "atk_bonus": 32.0, "rarity": "Legendario", "value": 450}
}

const CRAFT_RECIPES: Dictionary = {
	# Survival Cooking (Campfire)
	"traveler_bread": {"station": "campfire", "output_qty": 2, "cost": {"alchemy_herb": 2, "wood": 1}},
	"roasted_feast": {"station": "campfire", "output_qty": 2, "cost": {"raw_meat": 2, "wood": 2}},
	"arcane_stew": {"station": "campfire", "output_qty": 2, "cost": {"raw_meat": 2, "alchemy_herb": 3, "arcane_ore": 1}},
	# Alchemy
	"health_potion": {"station": "alchemy", "output_qty": 2, "cost": {"alchemy_herb": 2, "wood": 2}},
	"mana_potion": {"station": "alchemy", "output_qty": 2, "cost": {"alchemy_herb": 2, "arcane_ore": 1}},
	"elixir_fury": {"station": "alchemy", "output_qty": 1, "cost": {"alchemy_herb": 4, "arcane_ore": 3}},
	"siege_charge": {"station": "alchemy", "output_qty": 1, "cost": {"iron_ore": 4, "arcane_ore": 4}},
	# Player-Driven Coin Minting (smelt mined ore into Coins — ZERO infinite NPC gold!)
	"mint_silver_coins": {"station": "forge", "mint_gold": 35, "cost": {"silver_ore": 2}},
	"mint_gold_coins": {"station": "forge", "mint_gold": 90, "cost": {"gold_ore": 2}},
	# Basic Forge
	"iron_blade": {"station": "forge", "output_qty": 1, "cost": {"wood": 4, "iron_ore": 6}},
	# 4-Piece Heavy Set (Dungeon materials)
	"heavy_helmet": {"station": "forge", "output_qty": 1, "cost": {"iron_ore": 8, "dungeon_essence": 2}},
	"heavy_chest": {"station": "forge", "output_qty": 1, "cost": {"iron_ore": 14, "dungeon_essence": 3, "mythic_ingot": 1}},
	"heavy_legs": {"station": "forge", "output_qty": 1, "cost": {"iron_ore": 10, "dungeon_essence": 2}},
	"heavy_boots": {"station": "forge", "output_qty": 1, "cost": {"iron_ore": 7, "dungeon_essence": 1}},
	# 4-Piece Medium Set
	"medium_helmet": {"station": "forge", "output_qty": 1, "cost": {"iron_ore": 6, "alchemy_herb": 4, "dungeon_essence": 2}},
	"medium_chest": {"station": "forge", "output_qty": 1, "cost": {"iron_ore": 10, "alchemy_herb": 6, "dungeon_essence": 3}},
	"medium_legs": {"station": "forge", "output_qty": 1, "cost": {"iron_ore": 8, "alchemy_herb": 4, "dungeon_essence": 2}},
	"medium_boots": {"station": "forge", "output_qty": 1, "cost": {"iron_ore": 6, "dungeon_essence": 1}},
	# 4-Piece Light Set
	"light_helmet": {"station": "forge", "output_qty": 1, "cost": {"arcane_ore": 6, "dungeon_essence": 2}},
	"light_chest": {"station": "forge", "output_qty": 1, "cost": {"arcane_ore": 12, "dungeon_essence": 3, "arcane_gem": 1}},
	"light_legs": {"station": "forge", "output_qty": 1, "cost": {"arcane_ore": 8, "dungeon_essence": 2}},
	"light_boots": {"station": "forge", "output_qty": 1, "cost": {"arcane_ore": 5, "dungeon_essence": 1}},
	# Elemental Weapons & Staves
	"fire_greatsword": {"station": "forge", "output_qty": 1, "cost": {"iron_ore": 12, "mythic_ingot": 2, "dungeon_essence": 3}},
	"lightning_blade": {"station": "forge", "output_qty": 1, "cost": {"iron_ore": 12, "arcane_gem": 2, "dungeon_essence": 3}},
	"ice_halberd": {"station": "forge", "output_qty": 1, "cost": {"iron_ore": 12, "arcane_ore": 8, "dungeon_essence": 3}},
	"fire_staff": {"station": "forge", "output_qty": 1, "cost": {"wood": 10, "arcane_gem": 2, "dungeon_essence": 3}},
	"lightning_staff": {"station": "forge", "output_qty": 1, "cost": {"wood": 10, "arcane_gem": 2, "dungeon_essence": 3}},
	"ice_staff": {"station": "forge", "output_qty": 1, "cost": {"wood": 10, "arcane_gem": 2, "dungeon_essence": 3}},
	"lightning_daggers": {"station": "forge", "output_qty": 1, "cost": {"iron_ore": 10, "arcane_gem": 2, "dungeon_essence": 3}},
	"fire_bow": {"station": "forge", "output_qty": 1, "cost": {"wood": 12, "mythic_ingot": 2, "dungeon_essence": 3}}
}

# Colossal Open-World Bosses (including Supreme Dragon World Bosses in Valle Draconico!)
const WORLD_BOSSES: Array[Dictionary] = [
	{
		"id": "chaos_behemoth",
		"name": "Behemot de Obsidiana del Caos",
		"title": "Titán de la Llama Indómita",
		"style": "behemoth",
		"is_supreme_dragon": false,
		"spawn_xz": Vector2(125.0, 95.0),
		"max_hp": 1800.0,
		"damage": 38.0,
		"aoe_damage": 68.0,
		"aoe_radius": 9.5,
		"aggro_range": 42.0,
		"respawn_sec": 300.0,
		"xp_reward": 2400
	},
	{
		"id": "order_seraphim",
		"name": "Coloso Serafín del Orden",
		"title": "Guardián de la Piedra Eterna",
		"style": "seraphim",
		"is_supreme_dragon": false,
		"spawn_xz": Vector2(-130.0, -90.0),
		"max_hp": 1900.0,
		"damage": 36.0,
		"aoe_damage": 64.0,
		"aoe_radius": 10.0,
		"aggro_range": 42.0,
		"respawn_sec": 300.0,
		"xp_reward": 2500
	},
	{
		"id": "supreme_dragon_ignis",
		"name": "Ignis, Dragón Primordial del Nido",
		"title": "Jefe Supremo del Valle Dracónico (Suelta Montura de Dragón)",
		"style": "wyrm",
		"is_supreme_dragon": true,
		"spawn_xz": Vector2(20.0, -265.0),
		"max_hp": 4200.0,
		"damage": 58.0,
		"aoe_damage": 95.0,
		"aoe_radius": 13.0,
		"aggro_range": 62.0,
		"respawn_sec": 420.0,
		"xp_reward": 8000
	},
	{
		"id": "supreme_dragon_tempest",
		"name": "Vaelor, Wyrm de la Tempestad",
		"title": "Jefe Supremo del Valle Dracónico (Suelta Montura de Dragón)",
		"style": "wyrm",
		"is_supreme_dragon": true,
		"spawn_xz": Vector2(-115.0, -280.0),
		"max_hp": 4400.0,
		"damage": 60.0,
		"aoe_damage": 98.0,
		"aoe_radius": 13.5,
		"aggro_range": 62.0,
		"respawn_sec": 420.0,
		"xp_reward": 8500
	}
]

# Complex Multi-Room 4-Player Dungeons (Solo mode unlocked exclusively for AvatarOrden & AvatarCaos)
const DUNGEONS: Array[Dictionary] = [
	{
		"id": "catacombs_chaos",
		"name": "Catacumbas del Caos (4 Jugadores)",
		"theme": "chaos",
		"entrance_xz": Vector2(78.0, -64.0),
		"arena_origin": Vector3(0.0, -140.0, 0.0),
		"boss_name": "Señor de las Cenizas",
		"boss_hp": 1450.0,
		"xp_reward": 3200
	},
	{
		"id": "crypt_order",
		"name": "Cripta del Orden Antiguo (4 Jugadores)",
		"theme": "order",
		"entrance_xz": Vector2(-82.0, 72.0),
		"arena_origin": Vector3(280.0, -140.0, 0.0),
		"boss_name": "Centinela Rúnico Supremo",
		"boss_hp": 1550.0,
		"xp_reward": 3500
	}
]

# Zero Pay-to-Win Cosmetic Shop Catalog (0% combat stats impact; free for AvatarOrden & AvatarCaos)
const COSMETIC_ARMORS: Dictionary = {
	"default_iron": {"name": "Acero del Viajero", "price_crowns": 0, "primary": Color(0.45, 0.48, 0.54), "secondary": Color(0.24, 0.22, 0.22), "trim": Color(0.72, 0.68, 0.56), "metallic": 0.65, "roughness": 0.42},
	"order_paladin_gold": {"name": "Armadura Dorada del Orden", "price_crowns": 350, "primary": Color(0.88, 0.76, 0.34), "secondary": Color(0.92, 0.94, 0.98), "trim": Color(0.32, 0.68, 1.0), "metallic": 0.85, "roughness": 0.25},
	"chaos_obsidian": {"name": "Placas de Obsidiana del Caos", "price_crowns": 350, "primary": Color(0.14, 0.11, 0.16), "secondary": Color(0.28, 0.08, 0.08), "trim": Color(0.98, 0.32, 0.12), "metallic": 0.78, "roughness": 0.3},
	"astral_silver": {"name": "Malla de Plata Estelar", "price_crowns": 450, "primary": Color(0.78, 0.84, 0.94), "secondary": Color(0.22, 0.26, 0.46), "trim": Color(0.55, 0.88, 1.0), "metallic": 0.9, "roughness": 0.2},
	"royal_crimson": {"name": "Manto Real Carmesí", "price_crowns": 300, "primary": Color(0.58, 0.12, 0.16), "secondary": Color(0.2, 0.18, 0.22), "trim": Color(0.95, 0.8, 0.35), "metallic": 0.6, "roughness": 0.35}
}

const COSMETIC_DRAGONS: Dictionary = {
	"crimson_wyrm": {"name": "Dragón Carmesí", "price_crowns": 0, "scales": Color(0.68, 0.16, 0.14), "belly": Color(0.84, 0.66, 0.44), "wings": Color(0.45, 0.1, 0.1), "breath": Color(1.0, 0.45, 0.12)},
	"azure_drake": {"name": "Dragón Zafiro Arcano", "price_crowns": 400, "scales": Color(0.16, 0.44, 0.86), "belly": Color(0.7, 0.86, 0.98), "wings": Color(0.1, 0.26, 0.62), "breath": Color(0.32, 0.78, 1.0)},
	"emerald_ancient": {"name": "Dragón Esmeralda Antiguo", "price_crowns": 400, "scales": Color(0.14, 0.58, 0.34), "belly": Color(0.74, 0.84, 0.56), "wings": Color(0.08, 0.38, 0.22), "breath": Color(0.35, 0.96, 0.48)},
	"celestial_white": {"name": "Dragón Blanco del Orden", "price_crowns": 600, "scales": Color(0.92, 0.94, 0.98), "belly": Color(0.98, 0.86, 0.48), "wings": Color(0.82, 0.86, 0.96), "breath": Color(1.0, 0.94, 0.55)},
	"abyssal_black": {"name": "Dragón Abisal del Caos", "price_crowns": 600, "scales": Color(0.12, 0.1, 0.15), "belly": Color(0.42, 0.14, 0.18), "wings": Color(0.22, 0.06, 0.12), "breath": Color(0.94, 0.22, 0.68)}
}

const COSMETIC_TRAILS: Dictionary = {
	"none": {"name": "Sin Estela", "price_crowns": 0, "color": Color(1.0, 1.0, 1.0, 0.0)},
	"ember_sparks": {"name": "Estela de Brasas", "price_crowns": 250, "color": Color(1.0, 0.45, 0.1, 0.9)},
	"starlight_ribbon": {"name": "Estela Estelar", "price_crowns": 300, "color": Color(0.5, 0.85, 1.0, 0.9)},
	"golden_order": {"name": "Estela Dorada", "price_crowns": 350, "color": Color(1.0, 0.88, 0.35, 0.9)},
	"shadow_mist": {"name": "Estela Umbría", "price_crowns": 300, "color": Color(0.65, 0.2, 0.95, 0.9)}
}


func _ready() -> void:
	set_world_seed(world_seed)


func set_world_seed(seed_val: int) -> void:
	world_seed = seed_val
	_noise_continental = FastNoiseLite.new()
	_noise_continental.seed = world_seed
	_noise_continental.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_continental.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_continental.fractal_octaves = 4
	_noise_continental.frequency = 0.0032

	_noise_ridges = FastNoiseLite.new()
	_noise_ridges.seed = world_seed + 1337
	_noise_ridges.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_noise_ridges.fractal_octaves = 3
	_noise_ridges.frequency = 0.0022

	_noise_rivers = FastNoiseLite.new()
	_noise_rivers.seed = world_seed + 7919
	_noise_rivers.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise_rivers.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_rivers.fractal_octaves = 2
	_noise_rivers.frequency = 0.0018


func _ensure_noise() -> void:
	if _noise_continental == null:
		set_world_seed(world_seed)


func world_to_chunk(world_pos: Vector3) -> Vector2i:
	return Vector2i(int(floorf(world_pos.x / CHUNK_SIZE)), int(floorf(world_pos.z / CHUNK_SIZE)))


func chunk_key(coord: Vector2i) -> String:
	return "%d,%d" % [coord.x, coord.y]


func local_to_world(local_pos: Vector3) -> Vector3:
	return local_pos + world_origin_offset


func world_to_local(world_pos: Vector3) -> Vector3:
	return world_pos - world_origin_offset


func sample_terrain_height(x: float, z: float) -> float:
	_ensure_noise()
	var dist_origin: float = sqrt(x * x + z * z)
	var dist_chaos: float = Vector2(x - 260.0, z - 260.0).length()
	var flat_o: float = clampf((dist_origin - 36.0) / 50.0, 0.0, 1.0)
	flat_o = flat_o * flat_o * (3.0 - 2.0 * flat_o)
	var flat_c: float = clampf((dist_chaos - 36.0) / 50.0, 0.0, 1.0)
	flat_c = flat_c * flat_c * (3.0 - 2.0 * flat_c)
	var blend: float = minf(flat_o, flat_c)

	var cont: float = _noise_continental.get_noise_2d(x, z)
	var ridge_raw: float = clampf(_noise_ridges.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	var mountain_mask: float = smoothstep(0.18, 0.72, cont)
	var mountains: float = pow(ridge_raw, 1.8) * 58.0 * mountain_mask
	var rolling: float = cont * 16.0 + 3.5

	var river_n: float = absf(_noise_rivers.get_noise_2d(x, z))
	var river_cut: float = 0.0
	if river_n < 0.075:
		var rt: float = 1.0 - (river_n / 0.075)
		river_cut = -8.5 * rt * rt

	var height: float = rolling + mountains + river_cut
	return lerpf(1.5, height, blend)


func sample_terrain_normal(x: float, z: float) -> Vector3:
	var eps: float = 1.0
	var h_l: float = sample_terrain_height(x - eps, z)
	var h_r: float = sample_terrain_height(x + eps, z)
	var h_d: float = sample_terrain_height(x, z - eps)
	var h_u: float = sample_terrain_height(x, z + eps)
	return Vector3(h_l - h_r, 2.0 * eps, h_d - h_u).normalized()


func get_region_id_at(world_pos: Vector3) -> String:
	var p2: Vector2 = Vector2(world_pos.x, world_pos.z)
	var best_id: String = "bastion_alba"
	var best_dist: float = 999999.0
	for reg: Dictionary in WORLD_REGIONS:
		var d: float = p2.distance_to(reg["center_xz"] as Vector2)
		if d < best_dist:
			best_dist = d
			best_id = str(reg["id"])
	return best_id


func get_chunk_resources(coord: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var h: int = (world_seed * 73856093) ^ (coord.x * 19349663) ^ (coord.y * 83492791)
	rng.seed = h
	var count: int = rng.randi_range(2, 3)
	var origin_x: float = float(coord.x) * CHUNK_SIZE
	var origin_z: float = float(coord.y) * CHUNK_SIZE
	for slot: int in range(count):
		var wx: float = origin_x + rng.randf_range(6.0, CHUNK_SIZE - 6.0)
		var wz: float = origin_z + rng.randf_range(6.0, CHUNK_SIZE - 6.0)
		# Keep both capital sanctuaries clear of wild nodes
		if Vector2(wx, wz).length() < 38.0 or Vector2(wx - 260.0, wz - 260.0).length() < 38.0:
			continue
		var wy: float = sample_terrain_height(wx, wz)
		if wy < WATER_LEVEL + 0.5:
			continue
		var roll: float = rng.randf()
		var rtype: String = "wood"
		if wy > 18.0:
			if roll < 0.25:
				rtype = "gold_ore"
			elif roll < 0.55:
				rtype = "silver_ore"
			else:
				rtype = "arcane_ore"
		elif roll < 0.2:
			rtype = "wood"
		elif roll < 0.4:
			rtype = "iron_ore"
		elif roll < 0.56:
			rtype = "alchemy_herb"
		elif roll < 0.68:
			rtype = "raw_meat"
		elif roll < 0.78:
			rtype = "stone"
		elif roll < 0.88:
			rtype = "arcane_ore"
		elif roll < 0.95:
			rtype = "silver_ore"
		else:
			rtype = "gold_ore"
		out.append({
			"key": "%d,%d:%d" % [coord.x, coord.y, slot],
			"chunk": coord,
			"slot": slot,
			"type": rtype,
			"world_pos": Vector3(wx, wy, wz)
		})
	return out


func is_avatar_role(role: String) -> bool:
	return role == ROLE_AVATAR_ORDEN or role == ROLE_AVATAR_CAOS


func format_duration(seconds_left: float) -> String:
	var total: int = maxi(0, int(ceilf(seconds_left)))
	var hours: int = int(floorf(float(total) / 3600.0))
	var minutes: int = int(floorf(float(total % 3600) / 60.0))
	var secs: int = total % 60
	return "%02d:%02d:%02d" % [hours, minutes, secs]
