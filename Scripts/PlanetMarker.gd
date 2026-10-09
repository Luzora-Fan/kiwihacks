extends Control

# Each hand-placed marker reads its appearance and stats from a PlanetData resource.
@export var planet_data: PlanetData

@onready var sprite: TextureRect = $Sprite
@onready var selection_ring: Panel = $SelectionRing
@onready var uninhabitable_badge: Panel = $UninhabitableBadge
@onready var title_label: Label = $Title
@onready var distance_label: Label = $Distance
@onready var surveyed_label: Label = $Surveyed


func _ready() -> void:
	if planet_data == null:
		return
	sprite.texture = planet_data.sprite
	title_label.text = planet_data.display_name
	distance_label.text = planet_data.distance_label


func get_planet_data() -> Dictionary:
	if planet_data == null:
		return {}
	return planet_data.to_dictionary()


func get_body_center() -> Vector2:
	# Mission travel targets the planet art, not the larger label-and-hitbox container.
	return sprite.position + sprite.size * 0.5


func set_state(selected: bool, surveyed: bool, reachable: bool) -> void:
	# Keep selection, habitability status, and fuel reach visible on the authored marker.
	selection_ring.visible = selected
	uninhabitable_badge.visible = surveyed
	surveyed_label.visible = surveyed
	sprite.modulate = Color.WHITE if reachable or surveyed else Color(0.68, 0.7, 0.74, 0.78)
