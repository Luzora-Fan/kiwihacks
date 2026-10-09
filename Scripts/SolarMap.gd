extends Control

signal planet_selected(planet_id: String)

const ROCKET_SCENE := preload("res://Rocket.tscn")
const SHAKE_DURATION := 0.32

@onready var world: Control = $MapViewport/World
@onready var marker_container: Control = $MapViewport/World/PlanetMarkers
@onready var rocket_container: Node2D = $MapViewport/World/Rockets
@onready var earth_sprite: TextureRect = $MapViewport/World/EarthSprite

var markers: Dictionary = {}
var rockets: Dictionary = {}
var planet_data: Array[Dictionary] = []
var selected_id := ""
var scanned_ids: Array[String] = []
var fuel_range := 260.0
var camera_locked_to_ship := false
var _initial_view_framed := false
var _camera_position := Vector2.ZERO
var _shake_time_left := 0.0
var _shake_strength := 0.0
var _shake_offset := Vector2.ZERO

var _pointer_down := false
var _dragging := false
var _press_position := Vector2.ZERO
var _press_candidate := ""


func _ready() -> void:
	_camera_position = world.position
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


func _process(delta: float) -> void:
	# Keep the temporary shake separate from camera movement and map dragging.
	if _shake_time_left > 0.0:
		_shake_time_left = maxf(0.0, _shake_time_left - delta)
		var fade := _shake_time_left / SHAKE_DURATION
		_shake_offset = Vector2(
			randf_range(-1.0, 1.0),
			randf_range(-1.0, 1.0)
		) * _shake_strength * fade
	else:
		_shake_strength = 0.0
		_shake_offset = Vector2.ZERO
	_apply_world_position()


func get_planet_catalog() -> Array[Dictionary]:
	return planet_data


func set_camera_locked_to_ship(locked: bool) -> void:
	# Center on the oldest active rocket when camera lock is enabled.
	camera_locked_to_ship = locked
	if not camera_locked_to_ship:
		return
	var target_position := _earth_center()
	if not rockets.is_empty():
		var first_rocket: AnimatedSprite2D = rockets.values()[0]
		target_position = first_rocket.position
	_center_camera_on_position(target_position)


func reset_camera_view() -> void:
	# Let the next map update frame Earth and the selected starting planet again.
	_initial_view_framed = false


func shake_screen(intensity: float = 8.0) -> void:
	# Shake the map view briefly after an impact without moving the HUD.
	_shake_time_left = SHAKE_DURATION
	_shake_strength = maxf(0.0, intensity)


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
	# Frame Earth and the starting selection once, then preserve player panning.
	if not _initial_view_framed and size.x > 0.0 and size.y > 0.0 and markers.has(selected_id):
		var target_marker: Control = markers[selected_id]
		var target_center: Vector2 = target_marker.position + target_marker.call("get_body_center")
		var focus_point := (_earth_center() + target_center) * 0.5
		_camera_position = size * 0.5 - focus_point
		_clamp_pan()
		_initial_view_framed = true
	for planet in planet_data:
		var planet_id := String(planet["id"])
		if not markers.has(planet_id):
			continue
		var reachable := float(planet["distance"]) <= fuel_range
		var surveyed := scanned_ids.has(planet_id)
		markers[planet_id].call("set_state", planet_id == selected_id, surveyed, reachable)


func set_mission_states(missions: Array[Dictionary]) -> void:
	# Rockets are dynamic gameplay actors instantiated from the authored rocket scene.
	var active_rocket_ids: Dictionary = {}
	var camera_target := _earth_center()
	var has_camera_target := false
	for mission in missions:
		var rocket_id := int(mission.get("rocket_id", -1))
		var planet_id := String(mission.get("planet_id", ""))
		if rocket_id < 0 or not markers.has(planet_id):
			continue

		var rocket: AnimatedSprite2D
		if rockets.has(rocket_id):
			rocket = rockets[rocket_id]
		else:
			rocket = ROCKET_SCENE.instantiate() as AnimatedSprite2D
			rocket.name = "Rocket_%d" % rocket_id
			rocket_container.add_child(rocket)
			rocket.play("default")
			rockets[rocket_id] = rocket

		var target_marker: Control = markers[planet_id]
		var target_center: Vector2 = target_marker.position + target_marker.call("get_body_center")
		var progress := clampf(float(mission.get("progress", 0.0)), 0.0, 1.0)
		var eased_progress := _ease_in_out(progress)
		var phase := String(mission.get("phase", ""))
		var rocket_position := target_center
		var travel_direction := target_center - _earth_center()
		if phase == "outbound":
			rocket_position = _earth_center().lerp(target_center, eased_progress)
		elif phase == "returning":
			rocket_position = target_center.lerp(_earth_center(), eased_progress)
			travel_direction = -travel_direction

		rocket.position = rocket_position
		rocket.rotation = travel_direction.angle() + PI * 0.5
		active_rocket_ids[rocket_id] = true
		if not has_camera_target:
			camera_target = rocket_position
			has_camera_target = true

	for rocket_id in rockets.keys():
		if not active_rocket_ids.has(rocket_id):
			var rocket: AnimatedSprite2D = rockets[rocket_id]
			rocket.queue_free()
			rockets.erase(rocket_id)

	if camera_locked_to_ship:
		_center_camera_on_position(camera_target)


func _earth_center() -> Vector2:
	return earth_sprite.position + earth_sprite.size * 0.5


func _ease_in_out(progress: float) -> float:
	# Slow each rocket at launch and arrival without changing the flight time.
	return progress * progress * (3.0 - 2.0 * progress)


func _gui_input(event: InputEvent) -> void:
	# Treat a press and release as selection, then switch to panning after a short drag.
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
		if _dragging and not camera_locked_to_ship:
			_camera_position += event.relative
			_clamp_pan()
		accept_event()


func _planet_at(pointer_position: Vector2) -> String:
	# Hit testing uses world coordinates because the map can be panned in its viewport.
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
	# Keep the world over the viewport while limiting movement to its edges.
	var minimum_x := minf(0.0, size.x - world.size.x)
	var minimum_y := minf(0.0, size.y - world.size.y)
	_camera_position.x = clampf(_camera_position.x, minimum_x, 0.0)
	_camera_position.y = clampf(_camera_position.y, minimum_y, 0.0)
	_apply_world_position()


func _center_camera_on_position(target_position: Vector2) -> void:
	if not camera_locked_to_ship or size.x <= 0.0 or size.y <= 0.0:
		return
	_camera_position = size * 0.5 - target_position
	_clamp_pan()


func _apply_world_position() -> void:
	world.position = _camera_position + _shake_offset


func _fit_world_to_markers() -> void:
	# Include room past the farthest authored marker for labels and selection rings.
	var right_edge := world.size.x
	var bottom_edge := world.size.y
	for marker in markers.values():
		right_edge = maxf(right_edge, marker.position.x + marker.size.x + 60.0)
		bottom_edge = maxf(bottom_edge, marker.position.y + marker.size.y + 60.0)
	world.size = Vector2(right_edge, bottom_edge)
	marker_container.size = world.size
