class_name MagicProjectile
extends Area3D

## Physical dodgeable magic projectile (Fireball, Runic Slash, Judgment Beam, Shadow Dagger, Meteor).
## Moves along its trajectory and reports hits to WorldAuthority on the server.

const SHADER_PROJECTILE: Shader = preload("res://Client/Shaders/magic_projectile.gdshader")

var projectile_id: int = 0
var owner_peer_id: int = 0
var velocity: Vector3 = Vector3.ZERO
var damage: float = 30.0
var splash_radius: float = 0.0
var building_damage_mult: float = 1.25
var lifetime: float = 3.5
var color: Color = Color(1.0, 0.45, 0.1)

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
var _age: float = 0.0
var _detonated: bool = false


func setup(p_id: int, p_owner: int, world_origin: Vector3, direction: Vector3, speed: float, p_damage: float, p_splash: float, p_color: Color, p_scale: float = 1.0) -> void:
	projectile_id = p_id
	owner_peer_id = p_owner
	global_position = GameConfig.world_to_local(world_origin)
	velocity = direction.normalized() * speed
	damage = p_damage
	splash_radius = p_splash
	color = p_color
	scale = Vector3.ONE * p_scale


func _ready() -> void:
	collision_layer = GameConfig.LAYER_PROJECTILES
	collision_mask = GameConfig.LAYER_TERRAIN | GameConfig.LAYER_PLAYERS | GameConfig.LAYER_BUILDINGS
	if mesh_instance != null:
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = SHADER_PROJECTILE
		mat.set_shader_parameter("outer_color", color)
		mat.set_shader_parameter("core_color", color.lightened(0.65))
		mesh_instance.material_override = mat
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	if _detonated:
		return
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	global_position += velocity * delta
	var wp: Vector3 = GameConfig.local_to_world(global_position)
	var ground_y: float = GameConfig.sample_terrain_height(wp.x, wp.z)
	if wp.y <= ground_y + 0.15:
		_detonate(null)


func _on_body_entered(body: Node3D) -> void:
	if _detonated:
		return
	if body is PlayerController:
		var pc: PlayerController = body as PlayerController
		if pc.peer_id == owner_peer_id:
			return
	_detonate(body)


func _detonate(hit_body: Node3D) -> void:
	if _detonated:
		return
	_detonated = true
	if NetworkManager.is_server_running():
		var wa: Node = get_tree().get_first_node_in_group("world_authority")
		if wa != null and wa.has_method("server_on_projectile_impact"):
			wa.call("server_on_projectile_impact", owner_peer_id, GameConfig.local_to_world(global_position), damage, splash_radius, building_damage_mult, hit_body)
	queue_free()
