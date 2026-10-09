extends Control

const FUEL_TANK_COSTS: Array[int] = [180, 350, 540, 760, 1000, 1250, 1500]
const FUEL_RANGE_PER_TANK := 260.0
const SAVE_PATH := "user://earthward_save.json"
const SAVE_INTERVAL := 12.0
const CLIMATE_DECAY_PER_SECOND := 0.025
const SURVEY_DURATION := 4.5
const PROBE_DURATION := 3.2

# The scene owns all UI and map nodes. This script updates their state from the expedition data.
@onready var solar_map: Node = $MapPanel/MapContent/SolarMap
@onready var menu_overlay: Node = $MenuOverlay
@onready var credits_value: Label = $Header/Content/CreditsChip/Stack/Value
@onready var range_value: Label = $Header/Content/RangeChip/Stack/Value
@onready var ship_value: Label = $Header/Content/ShipChip/Stack/Value
@onready var earth_header_value: Label = $Header/Content/EarthChip/Stack/Value
@onready var target_status: Label = $SidebarScroll/PanelStack/TargetPanel/Content/Heading/Status
@onready var target_title: Label = $SidebarScroll/PanelStack/TargetPanel/Content/Title
@onready var target_description: Label = $SidebarScroll/PanelStack/TargetPanel/Content/Description
@onready var distance_value: Label = $SidebarScroll/PanelStack/TargetPanel/Content/Metrics/DistanceStack/Value
@onready var resource_value: Label = $SidebarScroll/PanelStack/TargetPanel/Content/Metrics/ResourceStack/Value
@onready var range_note: Label = $SidebarScroll/PanelStack/TargetPanel/Content/RangeNote
@onready var primary_button: Button = $SidebarScroll/PanelStack/TargetPanel/Content/PrimaryButton
@onready var fuel_button: Button = $SidebarScroll/PanelStack/TargetPanel/Content/FuelButton
@onready var mission_phase_value: Label = $SidebarScroll/PanelStack/MissionPanel/Content/Phase
@onready var mission_detail_value: Label = $SidebarScroll/PanelStack/MissionPanel/Content/Detail
@onready var mission_progress_bar: ProgressBar = $SidebarScroll/PanelStack/MissionPanel/Content/Progress
@onready var mission_feed_value: Label = $SidebarScroll/PanelStack/MissionPanel/Content/Feed
@onready var earth_health_value: Label = $SidebarScroll/PanelStack/EarthPanel/Content/Heading/Health
@onready var earth_progress_bar: ProgressBar = $SidebarScroll/PanelStack/EarthPanel/Content/Progress
@onready var earth_status_value: Label = $SidebarScroll/PanelStack/EarthPanel/Content/Status
@onready var restore_button: Button = $SidebarScroll/PanelStack/EarthPanel/Content/RestoreButton

var credits := 210
var earth_health := 76.0
var fuel_tier := 0
var fuel_range := 260.0
var selected_planet_id := "veyra"
var planet_data: Array[Dictionary] = []
var scanned_planet_ids: Array[String] = []
var planet_reports: Dictionary = {}

var mission_phase := "idle"
var mission_planet_id := ""
var mission_was_probe := false
var mission_duration := 0.0
var mission_time_left := 0.0
var mission_reward := 0
var mission_crates := 0
var mission_cargo_resource := ""
var mission_research_bonus := 0
var rng := RandomNumberGenerator.new()
var mission_feed := "Choose a destination and launch your first survey."
var _ui_refresh_clock := 0.0
var _save_clock := 0.0
# The menu pauses all simulation clocks until the player starts or resumes a run.
var game_started := false
var game_paused := false


func _ready() -> void:
	rng.randomize()
	planet_data = solar_map.call("get_planet_catalog")
	_load_game()
	primary_button.pressed.connect(_on_primary_pressed)
	fuel_button.pressed.connect(_on_fuel_pressed)
	restore_button.pressed.connect(_on_restore_pressed)
	solar_map.connect("planet_selected", Callable(self, "_on_planet_selected"))
	menu_overlay.connect("play_requested", Callable(self, "_on_play_requested"))
	menu_overlay.connect("resume_requested", Callable(self, "_on_resume_requested"))
	menu_overlay.connect("main_menu_requested", Callable(self, "_on_main_menu_requested"))
	_refresh_interface()
	_update_mission_presentation()


func _process(delta: float) -> void:
	if not game_started or game_paused:
		return

	# Advance climate and mission clocks every frame, while refreshing text and saving less often.
	if earth_health > 0.0:
		earth_health = maxf(0.0, earth_health - delta * CLIMATE_DECAY_PER_SECOND)

	if mission_phase != "idle":
		mission_time_left = maxf(0.0, mission_time_left - delta)
		if mission_time_left <= 0.0:
			_advance_mission()

	_update_mission_presentation()
	_ui_refresh_clock += delta
	if _ui_refresh_clock >= 0.16:
		_ui_refresh_clock = 0.0
		_refresh_interface()

	_save_clock += delta
	if _save_clock >= SAVE_INTERVAL:
		_save_clock = 0.0
		_save_game()


func _planet_by_id(planet_id: String) -> Dictionary:
	for planet in planet_data:
		if String(planet["id"]) == planet_id:
			return planet
	return {}


func _current_fuel_cost() -> int:
	if fuel_tier >= FUEL_TANK_COSTS.size():
		return 0
	return FUEL_TANK_COSTS[fuel_tier]


func _earth_restore_cost() -> int:
	return 100 + roundi((100.0 - earth_health) * 0.45)


func _on_planet_selected(planet_id: String) -> void:
	selected_planet_id = planet_id
	_refresh_interface()


func _on_play_requested() -> void:
	game_started = true
	game_paused = false
	menu_overlay.call("hide_overlay")
	_refresh_interface()
	_update_mission_presentation()


func _on_resume_requested() -> void:
	game_paused = false
	menu_overlay.call("hide_overlay")


func _on_main_menu_requested() -> void:
	_save_game()
	game_started = false
	game_paused = false
	menu_overlay.call("show_main_menu")


func _unhandled_key_input(event: InputEvent) -> void:
	if not game_started or not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo or key_event.keycode != KEY_ESCAPE:
		return

	game_paused = not game_paused
	if game_paused:
		menu_overlay.call("show_pause_menu")
	else:
		menu_overlay.call("hide_overlay")
	get_viewport().set_input_as_handled()


func _on_primary_pressed() -> void:
	if mission_phase != "idle":
		return
	var planet := _planet_by_id(selected_planet_id)
	if planet.is_empty():
		return
	if not scanned_planet_ids.has(selected_planet_id) and float(planet["distance"]) > fuel_range:
		mission_feed = "Upgrade the ship's fuel range before exploring this world."
		_refresh_interface()
		return

	# First visits use the survey ship. Later visits send a cheaper, repeatable resource rocket.
	mission_planet_id = selected_planet_id
	mission_was_probe = scanned_planet_ids.has(mission_planet_id)
	mission_reward = 0
	mission_phase = "outbound"
	mission_duration = _flight_duration(float(planet["distance"]))
	mission_time_left = mission_duration
	if mission_was_probe:
		mission_feed = "Free rocket launched to harvest another cache from %s." % planet["name"]
	else:
		mission_feed = "Survey ship dispatched to %s. Cargo is sold on return." % planet["name"]
	_save_game()
	_refresh_interface()


func _on_fuel_pressed() -> void:
	if fuel_tier >= FUEL_TANK_COSTS.size():
		return
	var cost := _current_fuel_cost()
	if credits < cost:
		mission_feed = "Not enough credits for the next fuel tank."
		_refresh_interface()
		return

	credits -= cost
	fuel_tier += 1
	fuel_range = 260.0 + FUEL_RANGE_PER_TANK * fuel_tier
	mission_feed = "Fuel tank upgraded. New maximum range: %d units." % roundi(fuel_range)
	_save_game()
	_refresh_interface()


func _on_restore_pressed() -> void:
	if earth_health >= 99.5:
		return
	var cost := _earth_restore_cost()
	if credits < cost:
		mission_feed = "Not enough credits to fund Earth's restoration systems."
		_refresh_interface()
		return

	credits -= cost
	earth_health = minf(100.0, earth_health + 24.0)
	mission_feed = "Restoration investment deployed. Earth vitality improved."
	_save_game()
	_refresh_interface()


func _flight_duration(distance: float) -> float:
	return 3.2 + distance / 220.0


func _advance_mission() -> void:
	# Missions always move through outbound, scanning, and returning before paying out cargo.
	if mission_phase == "outbound":
		mission_phase = "scanning"
		mission_duration = PROBE_DURATION if mission_was_probe else SURVEY_DURATION
		mission_time_left = mission_duration
		mission_feed = "Ship arrived at %s. Automated scan and extraction started." % _planet_by_id(mission_planet_id)["name"]
	elif mission_phase == "scanning":
		_finish_scan()
		mission_phase = "returning"
		mission_duration = _flight_duration(float(_planet_by_id(mission_planet_id)["distance"]))
		mission_time_left = mission_duration
		mission_feed = "Cargo: %d crates of %s. Sale on arrival: CR %d." % [mission_crates, mission_cargo_resource, mission_reward]
	elif mission_phase == "returning":
		var completed_planet := _planet_by_id(mission_planet_id)
		var sold_crates := mission_crates
		var sold_resource := mission_cargo_resource
		credits += mission_reward
		mission_feed = "%s returned. Sold %d crates of %s for CR %d." % [completed_planet["name"], sold_crates, sold_resource, mission_reward]
		mission_phase = "idle"
		mission_planet_id = ""
		mission_time_left = 0.0
		mission_duration = 0.0
		mission_reward = 0
		mission_crates = 0
		mission_cargo_resource = ""
		mission_research_bonus = 0
	_save_game()
	_refresh_interface()


func _finish_scan() -> void:
	var planet := _planet_by_id(mission_planet_id)
	if planet.is_empty():
		return

	# Repeat probes collect less and do not replace the report from the first survey.
	if mission_was_probe:
		var probe_min := maxi(1, floori(float(planet["crate_min"]) / 2.0))
		var probe_max := maxi(probe_min, floori(float(planet["crate_max"]) / 2.0) + 1)
		mission_crates = rng.randi_range(probe_min, probe_max)
		mission_research_bonus = 0
		mission_cargo_resource = String(planet["resource"])
		mission_feed = "Rocket collected %d crates of %s." % [mission_crates, mission_cargo_resource]
	else:
		mission_crates = rng.randi_range(int(planet["crate_min"]), int(planet["crate_max"]))
		mission_research_bonus = 42
		mission_cargo_resource = String(planet["resource"])
		scanned_planet_ids.append(mission_planet_id)
		planet_reports[mission_planet_id] = "No safe settlement conditions. %d crates of %s secured." % [mission_crates, planet["resource"]]
		mission_feed = "%s is uninhabitable. %d crates of %s are aboard." % [planet["name"], mission_crates, planet["resource"]]

	var cargo_value := mission_crates * int(planet["crate_price"])
	mission_reward = roundi(float(cargo_value + mission_research_bonus) * _recovery_efficiency())


func _recovery_efficiency() -> float:
	# A healthier Earth makes returned cargo more valuable, linking restoration to exploration.
	return 0.65 + earth_health / 100.0 * 0.35


func _update_mission_presentation() -> void:
	var progress := 0.0
	if mission_phase != "idle" and mission_duration > 0.0:
		progress = clampf(1.0 - mission_time_left / mission_duration, 0.0, 1.0)
	solar_map.call("set_mission_state", mission_phase, mission_planet_id, progress)


func _refresh_interface() -> void:
	# Render the current simulation state into existing controls and marker instances.
	credits_value.text = "CR %d" % credits
	range_value.text = "%d units" % roundi(fuel_range)
	ship_value.text = "Docked at Earth" if mission_phase == "idle" else mission_phase.capitalize()
	solar_map.call("configure", planet_data, selected_planet_id, scanned_planet_ids, fuel_range)

	var planet := _planet_by_id(selected_planet_id)
	if not planet.is_empty():
		var surveyed := scanned_planet_ids.has(selected_planet_id)
		target_title.text = String(planet["name"])
		target_status.text = "Surveyed" if surveyed else "Not surveyed"
		var report := ""
		if surveyed:
			report = "\n" + String(planet_reports.get(selected_planet_id, "No safe settlement conditions detected."))
		target_description.text = String(planet["description"]) + report
		distance_value.text = String(planet["distance_label"])
		resource_value.text = String(planet["resource"])

		var can_reach := float(planet["distance"]) <= fuel_range
		if surveyed:
			range_note.text = "Surveyed · repeat rocket flights are free."
		elif can_reach:
			range_note.text = "In range · no launch fee."
		else:
			range_note.text = "Out of range · upgrade fuel to reach this planet."

		if mission_phase != "idle":
			primary_button.text = "Mission in progress"
			primary_button.disabled = true
		elif surveyed:
			primary_button.text = "Send free rocket"
			primary_button.disabled = false
		elif can_reach:
			primary_button.text = "Launch survey"
			primary_button.disabled = false
		else:
			primary_button.text = "Out of range"
			primary_button.disabled = true

	var tank_cost := _current_fuel_cost()
	if fuel_tier >= FUEL_TANK_COSTS.size():
		fuel_button.text = "Maximum range"
		fuel_button.disabled = true
	else:
		fuel_button.text = "Upgrade fuel · CR %d" % tank_cost
		fuel_button.disabled = credits < tank_cost

	mission_progress_bar.value = _mission_progress() * 100.0
	match mission_phase:
		"outbound":
			mission_phase_value.text = "Travelling to %s" % String(_planet_by_id(mission_planet_id).get("name", ""))
			mission_detail_value.text = "Outbound flight - %d seconds left." % ceili(mission_time_left)
		"scanning":
			mission_phase_value.text = "Scanning surface"
			mission_detail_value.text = "Scanning and collecting resources."
		"returning":
			mission_phase_value.text = "Returning to Earth"
			mission_detail_value.text = "Estimated sale on arrival: CR %d." % mission_reward
		_:
			mission_phase_value.text = "Ready"
			mission_detail_value.text = "Select a planet to begin."
	mission_feed_value.text = mission_feed

	earth_health_value.text = "%d%%" % roundi(earth_health)
	earth_header_value.text = earth_health_value.text
	earth_progress_bar.value = earth_health
	if earth_health > 65.0:
		earth_status_value.text = "Atmosphere holding · sale efficiency %d%%." % roundi(_recovery_efficiency() * 100.0)
	elif earth_health > 30.0:
		earth_status_value.text = "Climate stress rising · invest in restoration."
	else:
		earth_status_value.text = "Critical climate stress · recovery yields are falling."
	var restore_cost := _earth_restore_cost()
	if earth_health >= 99.5:
		restore_button.text = "Earth is stable"
		restore_button.disabled = true
	else:
		restore_button.text = "Restore Earth · CR %d" % restore_cost
		restore_button.disabled = credits < restore_cost


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_game()


func _save_game() -> void:
	# Persist mission timing as well as upgrades so an in-progress trip can resume after restart.
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not save Earthward progress: %s" % error_string(FileAccess.get_open_error()))
		return

	var save_data := {
		"save_version": 2,
		"credits": credits,
		"earth_health": earth_health,
		"fuel_tier": fuel_tier,
		"selected_planet_id": selected_planet_id,
		"scanned_planet_ids": scanned_planet_ids,
		"planet_reports": planet_reports,
		"mission_feed": mission_feed,
		"mission_phase": mission_phase,
		"mission_planet_id": mission_planet_id,
		"mission_was_probe": mission_was_probe,
		"mission_duration": mission_duration,
		"mission_time_left": mission_time_left,
		"mission_reward": mission_reward,
		"mission_crates": mission_crates,
		"mission_cargo_resource": mission_cargo_resource,
		"mission_research_bonus": mission_research_bonus,
	}
	file.store_string(JSON.stringify(save_data))
	file.close()


func _load_game() -> void:
	# Ignore saved planet IDs that no longer exist in the authored planet catalog.
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("Could not read Earthward progress: %s" % error_string(FileAccess.get_open_error()))
		return

	var parsed_data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed_data is Dictionary:
		push_warning("Earthward save file is invalid. Starting a new expedition.")
		return

	var save_data: Dictionary = parsed_data
	credits = maxi(0, int(save_data.get("credits", credits)))
	earth_health = clampf(float(save_data.get("earth_health", earth_health)), 0.0, 100.0)
	fuel_tier = clampi(int(save_data.get("fuel_tier", fuel_tier)), 0, FUEL_TANK_COSTS.size())
	fuel_range = 260.0 + FUEL_RANGE_PER_TANK * fuel_tier

	var saved_planet_id := String(save_data.get("selected_planet_id", selected_planet_id))
	if not _planet_by_id(saved_planet_id).is_empty():
		selected_planet_id = saved_planet_id

	var saved_scanned_ids: Variant = save_data.get("scanned_planet_ids", [])
	if saved_scanned_ids is Array:
		for saved_id in saved_scanned_ids:
			var planet_id := String(saved_id)
			if not _planet_by_id(planet_id).is_empty() and not scanned_planet_ids.has(planet_id):
				scanned_planet_ids.append(planet_id)

	var saved_reports: Variant = save_data.get("planet_reports", {})
	if saved_reports is Dictionary:
		for key in saved_reports:
			var planet_id := String(key)
			if scanned_planet_ids.has(planet_id):
				planet_reports[planet_id] = String(saved_reports[key])

	mission_feed = String(save_data.get("mission_feed", mission_feed))
	var saved_phase := String(save_data.get("mission_phase", "idle"))
	var saved_mission_planet := String(save_data.get("mission_planet_id", ""))
	if ["outbound", "scanning", "returning"].has(saved_phase) and not _planet_by_id(saved_mission_planet).is_empty():
		mission_phase = saved_phase
		mission_planet_id = saved_mission_planet
		mission_was_probe = bool(save_data.get("mission_was_probe", false))
		mission_duration = maxf(0.1, float(save_data.get("mission_duration", 0.1)))
		mission_time_left = clampf(float(save_data.get("mission_time_left", mission_duration)), 0.0, mission_duration)
		mission_reward = maxi(0, int(save_data.get("mission_reward", 0)))
		mission_crates = maxi(0, int(save_data.get("mission_crates", 0)))
		mission_cargo_resource = String(save_data.get("mission_cargo_resource", ""))
		mission_research_bonus = maxi(0, int(save_data.get("mission_research_bonus", 0)))


func _mission_progress() -> float:
	# Convert remaining phase time into a normalized progress value for the map and progress bar.
	if mission_phase == "idle" or mission_duration <= 0.0:
		return 0.0
	return clampf(1.0 - mission_time_left / mission_duration, 0.0, 1.0)
