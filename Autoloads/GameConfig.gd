extends Node

## Global configuration, game balance, class specs, cosmetics, building catalogs,
## deterministic terrain math, and official mythology for Cronicas del Orden y el Caos.

const GAME_TITLE: String = "Crónicas del Orden y el Caos"
const PROTOCOL_VERSION: String = "1.0.0-rc1"

# Network configuration
const DEFAULT_HOST: String = "127.0.0.1"
const DEFAULT_PORT: int = 7777
const MAX_CLIENTS: int = 128
const SNAPSHOT_RATE_HZ: float = 20.0
const SNAPSHOT_INTERVAL: float = 1.0 / SNAPSHOT_RATE_HZ

# Account roles (Zero automatic karma; creator avatars are GM accounts)
const ROLE_PLAYER: String = "PLAYER"
const ROLE_AVATAR_ORDEN: String = "AVATAR_ORDEN"
const ROLE_AVATAR_CAOS: String = "AVATAR_CAOS"

# Organic player-declared philosophies (never enforced by NPC guards or karma bars)
const PHILOSOPHY_NEUTRAL: String = "Neutral"
const PHILOSOPHY_ORDER: String = "El Orden"
const PHILOSOPHY_CHAOS: String = "El Caos"

# Gracia Combativa (24h real-time cycle, +100% all stats stacking)
const COMBAT_GRACE_DURATION_SEC: float = 86400.0
const COMBAT_GRACE_MULTIPLIER: float = 2.0

# Infinite procedural world streaming & hardware budget (Ryzen 3 / Vega 8 / 8GB RAM)
const CHUNK_SIZE: float = 64.0
const CHUNK_RESOLUTION: int = 20
const GROUND_CHUNK_RADIUS: int = 2 # 5x5 active chunks on foot / low altitude
const FLIGHT_CHUNK_RADIUS: int = 3 # 7x7 active chunks with low LOD when flying high
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

# Official Mythology (Exact text required for IntroLore.tscn and MainMenu)
const OFFICIAL_LORE_CHAPTERS: Array[String] = [
	"Antes de que existieran las murallas o las cenizas, dos Arquitectos Primordiales forjaron este mundo desde el vacío: El Orden, creador de la piedra, la ley, los reinos y el comercio que une a los mortales; y El Caos, señor de la llama indómita, la libertad absoluta y la tempestad que derrumba todo imperio.",
	"Incapaces de destruirse entre sí, entregaron a los mortales la magia arcana y el dominio de los dragones, dejando que sean ellos quienes decidan el destino de la tierra. Aquí nadie nace bendecido ni maldito: llegás como un alma neutral, y tus propias manos escribirán si levantás ciudades bajo el estandarte del Orden o si las reducís a escombros bajo la sombra del Caos.",
	"Pero los dioses observan. Una vez cada ciclo solar, los Avatares del Orden y del Caos descienden de los cielos y eligen a un mortal al azar —sin importar su linaje ni su fuerza— para otorgarle la Gracia Combativa, duplicando todo su poder durante veinticuatro horas para inclinar la balanza de la historia."
]

const OFFICIAL_LORE_FULL: String = (
	"Antes de que existieran las murallas o las cenizas, dos Arquitectos Primordiales forjaron este mundo desde el vacío: "
	+ "[b]El Orden[/b], creador de la piedra, la ley, los reinos y el comercio que une a los mortales; y "
	+ "[b]El Caos[/b], señor de la llama indómita, la libertad absoluta y la tempestad que derrumba todo imperio.\n\n"
	+ "Incapaces de destruirse entre sí, entregaron a los mortales la magia arcana y el dominio de los dragones, "
	+ "dejando que sean ellos quienes decidan el destino de la tierra. Aquí nadie nace bendecido ni maldito: "
	+ "llegás como un alma neutral, y tus propias manos escribirán si levantás ciudades bajo el estandarte del Orden "
	+ "o si las reducís a escombros bajo la sombra del Caos.\n\n"
	+ "Pero los dioses observan. Una vez cada ciclo solar, los Avatares del Orden y del Caos descienden de los cielos "
	+ "y eligen a un mortal al azar —sin importar su linaje ni su fuerza— para otorgarle la [b]Gracia Combativa[/b], "
	+ "duplicando todo su poder durante veinticuatro horas para inclinar la balanza de la historia."
)

# Playable Medieval Magic Classes (Skill-based, no artificial level-gating)
const CLASSES: Dictionary = {
	"ARCANE_KNIGHT": {
		"name": "Caballero Arcano",
		"role": "Vanguardia / Espada y Escudos Mágicos",
		"description": "Maestro del acero rúnico y barreras arcanas. Resiste asedios y rompe líneas enemigas.",
		"accent_color": Color(0.28, 0.62, 0.96),
		"weapon_style": "sword_shield",
		"max_hp": 140.0,
		"max_mana": 90.0,
		"max_stamina": 120.0,
		"attack_power": 24.0,
		"spell_power": 20.0,
		"defense": 14.0,
		"move_speed": 6.4,
		"abilities": [
			{"id": "runic_slash", "name": "Tajo Rúnico", "cost_mana": 18.0, "cost_stamina": 10.0, "cooldown": 4.0, "damage": 34.0, "range": 14.0, "type": "projectile", "color": Color(0.35, 0.78, 1.0), "desc": "Lanza una onda arcana cortante evadible."},
			{"id": "arcane_shield", "name": "Escudo Arcano", "cost_mana": 25.0, "cost_stamina": 0.0, "cooldown": 10.0, "shield": 65.0, "duration": 6.0, "type": "shield", "color": Color(0.3, 0.65, 1.0), "desc": "Crea una barrera mágica que absorbe daño."},
			{"id": "aegis_slam", "name": "Impacto de Égida", "cost_mana": 22.0, "cost_stamina": 20.0, "cooldown": 8.0, "damage": 38.0, "radius": 5.5, "type": "aoe", "color": Color(0.45, 0.8, 1.0), "desc": "Golpea el suelo dañando y empujando enemigos cercanos."},
			{"id": "oath_surge", "name": "Impulso del Juramento", "cost_mana": 30.0, "cost_stamina": 0.0, "cooldown": 16.0, "buff_mult": 1.25, "duration": 8.0, "type": "buff", "color": Color(0.95, 0.85, 0.4), "desc": "Aumenta el poder de ataque y defensa un 25% por 8s."}
		]
	},
	"PYROMANCER": {
		"name": "Piromante",
		"role": "Artillería Arcana / Fuego y Asedio",
		"description": "Canaliza llamas primordiales capaces de pulverizar escuadrones y murallas fortificadas.",
		"accent_color": Color(0.98, 0.42, 0.14),
		"weapon_style": "staff",
		"max_hp": 100.0,
		"max_mana": 150.0,
		"max_stamina": 95.0,
		"attack_power": 14.0,
		"spell_power": 34.0,
		"defense": 7.0,
		"move_speed": 6.6,
		"abilities": [
			{"id": "fireball", "name": "Bola de Fuego", "cost_mana": 22.0, "cost_stamina": 0.0, "cooldown": 2.5, "damage": 42.0, "range": 32.0, "splash": 3.5, "type": "projectile", "color": Color(1.0, 0.42, 0.1), "desc": "Proyectil ígneo explosivo que daña jugadores y estructuras."},
			{"id": "flame_nova", "name": "Nova de Llamas", "cost_mana": 30.0, "cost_stamina": 10.0, "cooldown": 7.0, "damage": 46.0, "radius": 6.5, "type": "aoe", "color": Color(1.0, 0.55, 0.12), "desc": "Anillo expansivo de fuego alrededor del lanzador."},
			{"id": "meteor_strike", "name": "Lluvia de Cenizas", "cost_mana": 45.0, "cost_stamina": 0.0, "cooldown": 12.0, "damage": 68.0, "range": 28.0, "splash": 5.5, "type": "projectile", "color": Color(1.0, 0.2, 0.05), "desc": "Proyectil pesado de asedio con enorme daño a murallas."},
			{"id": "blazing_dash", "name": "Carrera Ígnea", "cost_mana": 20.0, "cost_stamina": 15.0, "cooldown": 9.0, "dash_dist": 10.0, "type": "dash", "color": Color(1.0, 0.65, 0.2), "desc": "Impulso veloz envuelto en llamas con invulnerabilidad breve."}
		]
	},
	"WAR_CLERIC": {
		"name": "Clérigo de Guerra",
		"role": "Soporte Bélico / Sanación y Luz",
		"description": "Portador de luz divina y maza consagrada. Sana aliados y castiga herejes en combate cercano.",
		"accent_color": Color(0.96, 0.84, 0.32),
		"weapon_style": "mace_shield",
		"max_hp": 125.0,
		"max_mana": 135.0,
		"max_stamina": 105.0,
		"attack_power": 20.0,
		"spell_power": 28.0,
		"defense": 12.0,
		"move_speed": 6.3,
		"abilities": [
			{"id": "divine_heal", "name": "Sanación Divina", "cost_mana": 28.0, "cost_stamina": 0.0, "cooldown": 5.5, "heal": 55.0, "radius": 8.0, "type": "heal", "color": Color(0.98, 0.92, 0.5), "desc": "Restaura salud propia y de aliados cercanos."},
			{"id": "radiant_barrier", "name": "Barrera Radiante", "cost_mana": 30.0, "cost_stamina": 0.0, "cooldown": 10.0, "shield": 75.0, "duration": 7.0, "type": "shield", "color": Color(1.0, 0.95, 0.65), "desc": "Escudo sagrado que absorbe impactos físicos y mágicos."},
			{"id": "judgment_beam", "name": "Haz de Juicio", "cost_mana": 26.0, "cost_stamina": 0.0, "cooldown": 6.0, "damage": 40.0, "range": 26.0, "type": "projectile", "color": Color(1.0, 0.92, 0.45), "desc": "Lanza un proyectil de luz pura veloz."},
			{"id": "consecrated_ground", "name": "Suelo Consagrado", "cost_mana": 36.0, "cost_stamina": 10.0, "cooldown": 14.0, "damage": 32.0, "heal": 30.0, "radius": 6.5, "type": "aoe", "color": Color(1.0, 0.88, 0.35), "desc": "Estallido sagrado que daña rivales y sana al lanzador."}
		]
	},
	"SHADOW_ASSASSIN": {
		"name": "Asesino Sombrío",
		"role": "Infiltración / Movilidad y Críticos",
		"description": "Acechador letal de las sombras. Domina el sigilo, el reposicionamiento rápido y los golpes críticos.",
		"accent_color": Color(0.68, 0.32, 0.94),
		"weapon_style": "daggers",
		"max_hp": 105.0,
		"max_mana": 95.0,
		"max_stamina": 145.0,
		"attack_power": 30.0,
		"spell_power": 18.0,
		"defense": 8.0,
		"move_speed": 7.4,
		"abilities": [
			{"id": "shadow_dagger", "name": "Daga Umbría", "cost_mana": 14.0, "cost_stamina": 12.0, "cooldown": 2.2, "damage": 32.0, "range": 22.0, "type": "projectile", "color": Color(0.68, 0.25, 0.95), "desc": "Lanza una hoja de sombra rápida y silenciosa."},
			{"id": "shadow_step", "name": "Paso Sombrío", "cost_mana": 20.0, "cost_stamina": 20.0, "cooldown": 7.0, "dash_dist": 12.0, "type": "dash", "color": Color(0.5, 0.15, 0.85), "desc": "Salto instantáneo que otorga invulnerabilidad y aumenta el próximo golpe."},
			{"id": "smoke_vanish", "name": "Velo de Sombras", "cost_mana": 26.0, "cost_stamina": 10.0, "cooldown": 13.0, "duration": 5.0, "type": "stealth", "color": Color(0.28, 0.12, 0.42), "desc": "Te vuelve casi invisible durante 5s y potencia velocidad."},
			{"id": "execution_flurry", "name": "Ejecución Letal", "cost_mana": 25.0, "cost_stamina": 30.0, "cooldown": 10.0, "damage": 58.0, "radius": 4.2, "type": "aoe", "color": Color(0.85, 0.18, 0.55), "desc": "Torbellino crítico de corto alcance contra objetivos cercanos."}
		]
	}
}

# Destructible Player Building Catalog
const BUILD_PIECES: Dictionary = {
	"wall": {
		"name": "Muralla de Piedra",
		"max_hp": 450.0,
		"size": Vector3(6.0, 4.5, 1.4),
		"cost": {"stone": 12, "wood": 4},
		"color": Color(0.55, 0.55, 0.58),
		"desc": "Defensa sólida para proteger ciudades del Orden."
	},
	"gate": {
		"name": "Puerta Fortificada",
		"max_hp": 380.0,
		"size": Vector3(6.0, 4.8, 1.4),
		"cost": {"stone": 10, "wood": 10},
		"color": Color(0.46, 0.34, 0.22),
		"desc": "Acceso fortificado que el dueño o su reino pueden abrir y cerrar (E)."
	},
	"tower": {
		"name": "Torre de Vigía",
		"max_hp": 620.0,
		"size": Vector3(4.2, 9.5, 4.2),
		"cost": {"stone": 20, "wood": 8},
		"color": Color(0.5, 0.5, 0.54),
		"desc": "Estructura elevada para vigilancia y aterrizaje de dragones."
	},
	"altar_order": {
		"name": "Altar del Orden",
		"max_hp": 520.0,
		"size": Vector3(3.2, 3.8, 3.2),
		"cost": {"stone": 15, "arcane_ore": 8},
		"color": Color(0.88, 0.78, 0.36),
		"desc": "Monumento de piedra y luz que declara territorio del Orden."
	},
	"altar_chaos": {
		"name": "Altar del Caos",
		"max_hp": 520.0,
		"size": Vector3(3.2, 3.8, 3.2),
		"cost": {"stone": 15, "arcane_ore": 8},
		"color": Color(0.84, 0.22, 0.16),
		"desc": "Monumento en llamas que consagra la zona bajo el Caos."
	},
	"trade_post": {
		"name": "Puesto Comercial",
		"max_hp": 300.0,
		"size": Vector3(4.5, 3.6, 3.5),
		"cost": {"wood": 14, "stone": 6},
		"color": Color(0.62, 0.44, 0.24),
		"desc": "Permite comerciar bienes y oro directamente entre jugadores (E)."
	}
}

# Items & Non-Cosmetic Craftable Equipment (Lootable on death)
const ITEMS: Dictionary = {
	"wood": {"name": "Madera", "type": "resource", "stackable": true, "value": 3},
	"stone": {"name": "Piedra", "type": "resource", "stackable": true, "value": 4},
	"arcane_ore": {"name": "Mineral Arcano", "type": "resource", "stackable": true, "value": 12},
	"health_potion": {"name": "Poción de Vida", "type": "consumable", "heal": 60.0, "stackable": true, "value": 25},
	"mana_potion": {"name": "Poción de Maná", "type": "consumable", "mana": 65.0, "stackable": true, "value": 25},
	"siege_charge": {"name": "Carga de Asedio", "type": "consumable", "siege_damage": 180.0, "stackable": true, "value": 60},
	"iron_blade": {"name": "Espada de Acero Forjado", "type": "weapon", "atk_bonus": 8.0, "stackable": false, "value": 80},
	"arcane_greatsword": {"name": "Mandoble Arcano", "type": "weapon", "atk_bonus": 16.0, "spell_bonus": 8.0, "stackable": false, "value": 180},
	"ember_staff": {"name": "Báculo de Brasas", "type": "weapon", "spell_bonus": 18.0, "stackable": false, "value": 170},
	"knight_plate": {"name": "Coraza del Reino", "type": "armor", "def_bonus": 9.0, "hp_bonus": 35.0, "stackable": false, "value": 190}
}

const CRAFT_RECIPES: Dictionary = {
	"health_potion": {"output_qty": 2, "cost": {"wood": 3, "arcane_ore": 1}},
	"mana_potion": {"output_qty": 2, "cost": {"arcane_ore": 2}},
	"siege_charge": {"output_qty": 1, "cost": {"stone": 6, "arcane_ore": 4}},
	"iron_blade": {"output_qty": 1, "cost": {"wood": 4, "stone": 8}},
	"arcane_greatsword": {"output_qty": 1, "cost": {"stone": 12, "arcane_ore": 10}},
	"ember_staff": {"output_qty": 1, "cost": {"wood": 10, "arcane_ore": 10}},
	"knight_plate": {"output_qty": 1, "cost": {"stone": 16, "arcane_ore": 8}}
}

# Zero Pay-to-Win Cosmetic Shop Catalog (0% combat stats impact)
const COSMETIC_ARMORS: Dictionary = {
	"default_iron": {
		"name": "Acero del Viajero",
		"price_crowns": 0,
		"primary": Color(0.45, 0.48, 0.54),
		"secondary": Color(0.24, 0.22, 0.22),
		"trim": Color(0.72, 0.68, 0.56),
		"metallic": 0.65,
		"roughness": 0.42
	},
	"order_paladin_gold": {
		"name": "Armadura Dorada del Orden",
		"price_crowns": 350,
		"primary": Color(0.88, 0.76, 0.34),
		"secondary": Color(0.92, 0.94, 0.98),
		"trim": Color(0.32, 0.68, 1.0),
		"metallic": 0.85,
		"roughness": 0.25
	},
	"chaos_obsidian": {
		"name": "Placas de Obsidiana del Caos",
		"price_crowns": 350,
		"primary": Color(0.14, 0.11, 0.16),
		"secondary": Color(0.28, 0.08, 0.08),
		"trim": Color(0.98, 0.32, 0.12),
		"metallic": 0.78,
		"roughness": 0.3
	},
	"astral_silver": {
		"name": "Malla de Plata Estelar",
		"price_crowns": 450,
		"primary": Color(0.78, 0.84, 0.94),
		"secondary": Color(0.22, 0.26, 0.46),
		"trim": Color(0.55, 0.88, 1.0),
		"metallic": 0.9,
		"roughness": 0.2
	},
	"royal_crimson": {
		"name": "Manto Real Carmesí",
		"price_crowns": 300,
		"primary": Color(0.58, 0.12, 0.16),
		"secondary": Color(0.2, 0.18, 0.22),
		"trim": Color(0.95, 0.8, 0.35),
		"metallic": 0.6,
		"roughness": 0.35
	}
}

const COSMETIC_DRAGONS: Dictionary = {
	"crimson_wyrm": {
		"name": "Dragón Carmesí (Estándar)",
		"price_crowns": 0,
		"scales": Color(0.68, 0.16, 0.14),
		"belly": Color(0.84, 0.66, 0.44),
		"wings": Color(0.45, 0.1, 0.1),
		"breath": Color(1.0, 0.45, 0.12)
	},
	"azure_drake": {
		"name": "Dragón Zafiro Arcano",
		"price_crowns": 400,
		"scales": Color(0.16, 0.44, 0.86),
		"belly": Color(0.7, 0.86, 0.98),
		"wings": Color(0.1, 0.26, 0.62),
		"breath": Color(0.32, 0.78, 1.0)
	},
	"emerald_ancient": {
		"name": "Dragón Esmeralda Antiguo",
		"price_crowns": 400,
		"scales": Color(0.14, 0.58, 0.34),
		"belly": Color(0.74, 0.84, 0.56),
		"wings": Color(0.08, 0.38, 0.22),
		"breath": Color(0.35, 0.96, 0.48)
	},
	"celestial_white": {
		"name": "Dragón Blanco del Orden",
		"price_crowns": 600,
		"scales": Color(0.92, 0.94, 0.98),
		"belly": Color(0.98, 0.86, 0.48),
		"wings": Color(0.82, 0.86, 0.96),
		"breath": Color(1.0, 0.94, 0.55)
	},
	"abyssal_black": {
		"name": "Dragón Abisal del Caos",
		"price_crowns": 600,
		"scales": Color(0.12, 0.1, 0.15),
		"belly": Color(0.42, 0.14, 0.18),
		"wings": Color(0.22, 0.06, 0.12),
		"breath": Color(0.94, 0.22, 0.68)
	}
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


## Deterministic infinite terrain height function based on world_seed.
## Produces seamless endless valleys, rivers, highlands, and soaring dragon peaks
## identically on Server and all Clients without streaming map data over the network.
func sample_terrain_height(x: float, z: float) -> float:
	_ensure_noise()
	var dist_origin: float = sqrt(x * x + z * z)
	# Gentle starter sanctuary plateau around (0, 0) for initial spawns and first kingdoms
	var origin_blend: float = clampf((dist_origin - 30.0) / 55.0, 0.0, 1.0)
	origin_blend = origin_blend * origin_blend * (3.0 - 2.0 * origin_blend)

	var cont: float = _noise_continental.get_noise_2d(x, z) # -1..1
	var ridge_raw: float = clampf(_noise_ridges.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	var mountain_mask: float = smoothstep(0.18, 0.72, cont)
	var mountains: float = pow(ridge_raw, 1.8) * 58.0 * mountain_mask

	var rolling: float = cont * 16.0 + 3.5

	# Winding infinite river network where river noise crosses 0
	var river_n: float = absf(_noise_rivers.get_noise_2d(x, z))
	var river_cut: float = 0.0
	if river_n < 0.075:
		var rt: float = 1.0 - (river_n / 0.075)
		river_cut = -8.5 * rt * rt

	var height: float = rolling + mountains + river_cut
	return lerpf(1.5, height, origin_blend)


func sample_terrain_normal(x: float, z: float) -> Vector3:
	var eps: float = 1.0
	var h_l: float = sample_terrain_height(x - eps, z)
	var h_r: float = sample_terrain_height(x + eps, z)
	var h_d: float = sample_terrain_height(x, z - eps)
	var h_u: float = sample_terrain_height(x, z + eps)
	return Vector3(h_l - h_r, 2.0 * eps, h_d - h_u).normalized()


## Deterministically generates resource veins (wood, stone, arcane_ore) for ANY infinite chunk.
## Server and Clients compute the exact same resource IDs and world positions from world_seed.
func get_chunk_resources(coord: Vector2i) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var h: int = (world_seed * 73856093) ^ (coord.x * 19349663) ^ (coord.y * 83492791)
	rng.seed = h
	var count: int = rng.randi_range(1, 2)
	var origin_x: float = float(coord.x) * CHUNK_SIZE
	var origin_z: float = float(coord.y) * CHUNK_SIZE
	for slot: int in range(count):
		var wx: float = origin_x + rng.randf_range(6.0, CHUNK_SIZE - 6.0)
		var wz: float = origin_z + rng.randf_range(6.0, CHUNK_SIZE - 6.0)
		# Keep immediate center sanctuary clear
		if absf(wx) < 16.0 and absf(wz) < 16.0:
			continue
		var wy: float = sample_terrain_height(wx, wz)
		if wy < WATER_LEVEL + 0.5:
			continue
		var roll: float = rng.randf()
		var rtype: String = "wood"
		if wy > 16.0:
			rtype = "arcane_ore" if roll < 0.6 else "stone"
		elif roll < 0.38:
			rtype = "stone"
		elif roll < 0.58:
			rtype = "arcane_ore"
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
	var hours: int = total / 3600
	var minutes: int = (total % 3600) / 60
	var secs: int = total % 60
	return "%02d:%02d:%02d" % [hours, minutes, secs]
