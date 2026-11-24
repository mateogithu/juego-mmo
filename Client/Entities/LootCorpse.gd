class_name LootCorpse
extends Area3D

## Lootable corpse/chest dropped in the open world when a player dies in PvP.
## Holds non-cosmetic resources, gear, and gold; cosmetics are never lost.

var loot_id: int = 0
var victim_name: String = ""
var gold_amount: int = 0
var items: Dictionary = {}

@onready var visual_root: Node3D = $VisualRoot
@onready var label_3d: Label3D = $Label3D


func setup(p_id: int, p_victim: String, world_pos: Vector3, p_gold: int, p_items: Dictionary) -> void:
	loot_id = p_id
	victim_name = p_victim
	gold_amount = p_gold
	items = p_items.duplicate(true)
	name = "Loot_%d" % p_id
	global_position = GameConfig.world_to_local(world_pos)
	if is_node_ready():
		_refresh_visual()


func _ready() -> void:
	add_to_group("loot_corpses")
	collision_layer = GameConfig.LAYER_INTERACTABLES
	collision_mask = 0
	_refresh_visual()


func _refresh_visual() -> void:
	ProceduralMeshFactory.build_loot_chest_visual(visual_root)
	if label_3d != null:
		label_3d.text = "[E / Y] Botín de %s (%d oro)" % [victim_name, gold_amount]
