extends Control

signal planet_selected(planet_id: String)

@onready var world: Control = $MapViewport/World
@onready var marker_container: Control = $MapViewport/World/PlanetMarkers
@onready var ship_sprite: TextureRect = $MapViewport/World/ShipSprite
@onready var earth_sprite: TextureRect = $MapViewport/World/EarthSprite

var markers: Dictionary = {}
var planet_data: Array[Dictionary] = []
var selected_id := ""
var scanned_ids: Array[String] = []
var fuel_range := 260.0
var mission_phase := "idle"
var mission_planet_id := ""
var mission_progress := 0.0
var _initial_view_framed := false

var _pointer_down := false
var _dragging := false
var _press_position := Vector2.ZERO
var _press_candidate := ""


func _ready() -> void:
	# Build the catalog from planet markers already placed in SolarMap.tscn.
	for marker in marker_container.get_children():
		var marker_data: Dictionary = marker.call("get_planet_data")
		if marker_data.is_empty():
			continue
		var planet_id := String(marker_data["id"])
		if markers.has(planet_id):
			push_warning("More than one planet marker uses id '%s'." % planet_id)
			continue
		markers[planet_id] = marker
		planet_data.append(marker_data)
	_fit_world_to_markers()
	_clamp_pan()


func get_planet_catalog() -> Array[Dictionary]:
	return planet_data


func configure(
	planet_catalog: Array[Dictionary],
	selected_planet: String,
	surveyed_planets: Array[String],
	range_limit: float
) -> void:
	planet_data = planet_catalog
	selected_id = selected_planet
	scanned_ids = surveyed_planets
	fuel_range = range_limit
	# Frame Earth and the starting selection once. later configure calls must preserve player panning.
	if not _initial_view_framed and size.x > 0.0 and size.y > 0.0 and markers.has(selected_id):
		var earth_center := earth_sprite.position + earth_sprite.size * 0.5
		var target_marker: Control = markers[selected_id]
		var target_center: Vector2 = target_marker.position + target_marker.call("get_body_center")
		var focus_point := (earth_center + target_center) * 0.5
		world.position = size * 0.5 - focus_point
		_clamp_pan()
		_initial_view_framed = true
	for planet in planet_data:
		var planet_id := String(planet["id"])
		if not markers.has(planet_id):
			continue
		var reachable := float(planet["distance"]) <= fuel_range
		var surveyed := scanned_ids.has(planet_id)
		markers[planet_id].call("set_state", planet_id == selected_id, surveyed, reachable)


func set_mission_state(phase: String, target_id: String, progress: float) -> void:
	# Move the pre-placed rocket sprite along the authored Earth-to-planet route.
	mission_phase = phase
	mission_planet_id = target_id
	mission_progress = clampf(progress, 0.0, 1.0)
	ship_sprite.visible = mission_phase != "idle" and markers.has(mission_planet_id)
	if not ship_sprite.visible:
		return

	var earth_center := earth_sprite.position + earth_sprite.size * 0.5
	var target_marker: Control = markers[mission_planet_id]
	var target_center: Vector2 = target_marker.position + target_marker.call("get_body_center")
	var ship_position := earth_center
	if mission_phase == "outbound":
		ship_position = earth_center.lerp(target_center, mission_progress)
	elif mission_phase == "scanning":
		ship_position = target_center
	elif mission_phase == "returning":
		ship_position = target_center.lerp(earth_center, mission_progress)

	var travel_direction := target_center - earth_center
	if mission_phase == "returning":
		travel_direction = -travel_direction
	ship_sprite.position = ship_position - ship_sprite.size * 0.5
	ship_sprite.rotation = travel_direction.angle() + PI * 0.5


func _gui_input(event: InputEvent) -> void:
	# Treat a press/release as selection, but switch to panning after a short movement threshold.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pointer_down = true
			_dragging = false
			_press_position = event.position
			_press_candidate = _planet_at(event.position)
			accept_event()
		elif _pointer_down:
			if not _dragging and not _press_candidate.is_empty():
				planet_selected.emit(_press_candidate)
			_pointer_down = false
			_press_candidate = ""
			accept_event()
	elif event is InputEventMouseMotion and _pointer_down:
		if not _dragging and event.position.distance_to(_press_position) > 6.0:
			_dragging = true
		if _dragging:
			world.position += event.relative
			_clamp_pan()
		accept_event()


func _planet_at(pointer_position: Vector2) -> String:
	# Hit testing uses world coordinates because the map can be panned inside its viewport.
	var world_position := pointer_position - world.position
	for planet in planet_data:
		var planet_id := String(planet["id"])
		if not markers.has(planet_id):
			continue
		var marker: Control = markers[planet_id]
		if Rect2(marker.position, marker.size).has_point(world_position):
			return planet_id
	return ""


func _clamp_pan() -> void:
	# Keep the world covering the viewport while allowing it to move no farther than its edges.
	var minimum_x := minf(0.0, size.x - world.size.x)
	var minimum_y := minf(0.0, size.y - world.size.y)
	world.position.x = clampf(world.position.x, minimum_x, 0.0)
	world.position.y = clampf(world.position.y, minimum_y, 0.0)


func _fit_world_to_markers() -> void:
	# Include extra room after the farthest authored marker for its labels and selection ring.
	var right_edge := world.size.x
	var bottom_edge := world.size.y
	for marker in markers.values():
		right_edge = maxf(right_edge, marker.position.x + marker.size.x + 60.0)
		bottom_edge = maxf(bottom_edge, marker.position.y + marker.size.y + 60.0)
	world.size = Vector2(right_edge, bottom_edge)
	marker_container.size = world.size
