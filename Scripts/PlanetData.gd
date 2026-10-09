extends Resource
class_name PlanetData

# Planet values live in .tres resources so adding a world does not require gameplay-code edits.
@export var id := ""
@export var display_name := ""
@export var distance := 0.0
@export var distance_label := ""
@export_multiline var description := ""
@export var resource := ""
@export var crate_price := 1
@export var crate_min := 1
@export var crate_max := 1
@export var sprite: Texture2D


func to_dictionary() -> Dictionary:
	# Keep the sprite on its authored marker. This record contains the data used by gameplay and UI.
	return {
		"id": id,
		"name": display_name,
		"distance": distance,
		"distance_label": distance_label,
		"description": description,
		"resource": resource,
		"crate_price": crate_price,
		"crate_min": crate_min,
		"crate_max": crate_max,
	}
