extends Control

const FUEL_TANK_COSTS: Array[int] = [180, 350, 540, 760, 1000, 1250, 1500]
const FUEL_RANGE_PER_TANK := 260.0
const ROCKET_COSTS: Array[int] = [300, 500, 750, 1000]
const MAX_ROCKETS := 5
const SAVE_PATH := "user://earthward_save.json"
const LEADERBOARD_PATH := "user://earthward_leaderboard.json"
const MAX_LEADERBOARD_RUNS := 10
const ALIEN_SPAWN_CHANCE := 0.30
const ALIEN_FIGHT_ROUNDS := 4
const ALIEN_HITS_TO_WIN := 3
const SAVE_INTERVAL := 12.0
const CLIMATE_DECAY_PER_SECOND := 0.1 # Earth loses six health points per active minute.
const SURVEY_DURATION := 4.5
const PROBE_DURATION := 3.2
const LANDING_GREEN_START := 0.40
const LANDING_GREEN_END := 0.60
const LANDING_SWEEP_TIME := 1.25

# The scene owns all UI and map nodes. This script updates them from expedition data.
@onready var solar_map: Node = $MapPanel/MapContent/SolarMap
@onready var menu_overlay: Node = $MenuOverlay
@onready var camera_follow_toggle: CheckButton = $MapPanel/MapContent/CameraFollowToggle
@onready var flight_audio_player: AudioStreamPlayer = $FlightAudio
@onready var landing_audio_player: AudioStreamPlayer = $LandingAudio
@onready var alert_audio_player: AudioStreamPlayer = $AlertAudio
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
@onready var landing_challenge_panel: Control = $SidebarScroll/PanelStack/MissionPanel/Content/LandingChallenge
@onready var alien_sprite: TextureRect = $SidebarScroll/PanelStack/MissionPanel/Content/LandingChallenge/AlienSprite
@onready var landing_hint: Label = $SidebarScroll/PanelStack/MissionPanel/Content/LandingChallenge/Hint
@onready var landing_track: Control = $SidebarScroll/PanelStack/MissionPanel/Content/LandingChallenge/TimingTrack
@onready var landing_marker: ColorRect = $SidebarScroll/PanelStack/MissionPanel/Content/LandingChallenge/TimingTrack/Marker
@onready var land_button: Button = $SidebarScroll/PanelStack/MissionPanel/Content/LandButton
@onready var fleet_status_value: Label = $SidebarScroll/PanelStack/FleetPanel/Content/Status
@onready var buy_rocket_button: Button = $SidebarScroll/PanelStack/FleetPanel/Content/BuyRocketButton
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

# Each mission stores its own rocket, route, timing, and cargo state.
var active_missions: Array[Dictionary] = []
var rockets_owned := 1
var next_rocket_id := 1
var landing_rocket_id := -1
var landing_qte_elapsed := 0.0
var landing_marker_position := 0.0

var rng := RandomNumberGenerator.new()
var mission_feed := "Choose a destination and send a rocket."
var _ui_refresh_clock := 0.0
var _save_clock := 0.0
# The menu pauses all simulation clocks until the player starts or resumes a run.
var game_started := false
var game_paused := false
var run_elapsed_seconds := 0.0
var run_finished := false
var run_result_record: Dictionary = {}
var leaderboard_runs: Array[Dictionary] = []


func _ready() -> void:
	rng.randomize()
	planet_data = solar_map.call("get_planet_catalog")
	_load_game()
	primary_button.pressed.connect(_on_primary_pressed)
	fuel_button.pressed.connect(_on_fuel_pressed)
	restore_button.pressed.connect(_on_restore_pressed)
	buy_rocket_button.pressed.connect(_on_buy_rocket_pressed)
	land_button.pressed.connect(_on_land_pressed)
	camera_follow_toggle.toggled.connect(_on_camera_follow_toggled)
	solar_map.connect("planet_selected", Callable(self, "_on_planet_selected"))
	menu_overlay.connect("play_requested", Callable(self, "_on_play_requested"))
	menu_overlay.connect("resume_requested", Callable(self, "_on_resume_requested"))
	menu_overlay.connect("main_menu_requested", Callable(self, "_on_main_menu_requested"))
	menu_overlay.connect("quit_requested", Callable(self, "_on_quit_requested"))
	menu_overlay.connect("reset_progress_requested", Callable(self, "_on_reset_progress_requested"))
	_refresh_interface()
	_update_mission_presentation()
	_load_leaderboard()
	menu_overlay.call("set_leaderboard_runs", leaderboard_runs)
	menu_overlay.call("set_run_finished", run_finished)
	if run_finished:
		menu_overlay.call("show_run_result", run_result_record)
	elif earth_health <= 0.0:
		_finish_run(false)
	else:
		_check_for_victory()


func _process(delta: float) -> void:
	_sync_flight_audio()
	if not game_started or game_paused:
		return

	# Advance climate, mission clocks, and the active landing marker.
	run_elapsed_seconds += delta
	if earth_health > 0.0:
		var previous_earth_health := earth_health
		earth_health = maxf(0.0, earth_health - delta * CLIMATE_DECAY_PER_SECOND)
		if previous_earth_health > 30.0 and earth_health <= 30.0:
			alert_audio_player.play()
	if earth_health <= 0.0:
		_finish_run(false)
		return

	var missions_changed := _advance_missions(delta)
	if _start_pending_alien_challenge():
		missions_changed = true
	if missions_changed:
		_save_game()
		_refresh_interface()
	if _check_for_victory():
		return

	if landing_rocket_id >= 0:
		landing_qte_elapsed += delta
		landing_marker_position = _landing_marker_at(landing_qte_elapsed)

	_update_mission_presentation()
	_update_landing_challenge()
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


func _next_rocket_cost() -> int:
	if rockets_owned >= MAX_ROCKETS:
		return 0
	return ROCKET_COSTS[rockets_owned - 1]


func _earth_restore_cost() -> int:
	return 100 + roundi((100.0 - earth_health) * 0.45)


func _active_mission_index(rocket_id: int) -> int:
	for index in range(active_missions.size()):
		if int(active_missions[index].get("rocket_id", -1)) == rocket_id:
			return index
	return -1


func _mission_for_rocket(rocket_id: int) -> Dictionary:
	var index := _active_mission_index(rocket_id)
	if index < 0:
		return {}
	return active_missions[index]


func _has_mission_for_planet(planet_id: String) -> bool:
	for mission in active_missions:
		if String(mission.get("planet_id", "")) == planet_id:
			return true
	return false


func _landing_target_mission() -> Dictionary:
	if landing_rocket_id >= 0:
		var active_landing := _mission_for_rocket(landing_rocket_id)
		var active_phase := String(active_landing.get("phase", ""))
		if active_phase == "landing_qte" or active_phase == "alien_combat":
			return active_landing
	for mission in active_missions:
		if String(mission.get("phase", "")) == "awaiting_landing":
			return mission
	for mission in active_missions:
		if String(mission.get("phase", "")) == "alien_combat":
			return mission
	return {}


func _featured_mission() -> Dictionary:
	var landing_mission := _landing_target_mission()
	if not landing_mission.is_empty():
		return landing_mission
	if not active_missions.is_empty():
		return active_missions[0]
	return {}


func _on_planet_selected(planet_id: String) -> void:
	selected_planet_id = planet_id
	_refresh_interface()


func _on_play_requested() -> void:
	if run_finished:
		menu_overlay.call("show_run_result", run_result_record)
		return
	game_started = true
	game_paused = false
	_start_pending_alien_challenge()
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


func _on_camera_follow_toggled(locked: bool) -> void:
	solar_map.call("set_camera_locked_to_ship", locked)


func _on_quit_requested() -> void:
	_save_game()
	get_tree().quit()


func _on_reset_progress_requested() -> void:
	# Replace the save with the same starting state as a new run.
	credits = 210
	earth_health = 76.0
	fuel_tier = 0
	fuel_range = 260.0
	selected_planet_id = "veyra"
	scanned_planet_ids.clear()
	planet_reports.clear()
	active_missions.clear()
	rockets_owned = 1
	next_rocket_id = 1
	landing_rocket_id = -1
	landing_qte_elapsed = 0.0
	landing_marker_position = 0.0
	run_elapsed_seconds = 0.0
	run_finished = false
	run_result_record.clear()
	mission_feed = "Choose a destination and send a rocket."
	_ui_refresh_clock = 0.0
	_save_clock = 0.0
	game_started = false
	game_paused = false
	camera_follow_toggle.set_pressed_no_signal(false)
	solar_map.call("set_camera_locked_to_ship", false)
	solar_map.call("reset_camera_view")
	_refresh_interface()
	_update_mission_presentation()
	_save_game()
	menu_overlay.call("set_run_finished", false)
	menu_overlay.call("set_leaderboard_runs", leaderboard_runs)
	menu_overlay.call("show_main_menu")


func _unhandled_key_input(event: InputEvent) -> void:
	if not game_started or not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	if key_event.keycode == KEY_ESCAPE:
		game_paused = not game_paused
		if game_paused:
			menu_overlay.call("show_pause_menu")
		else:
			menu_overlay.call("hide_overlay")
		get_viewport().set_input_as_handled()
	elif key_event.keycode == KEY_E and not game_paused:
		if not _landing_target_mission().is_empty():
			_on_land_pressed()
			get_viewport().set_input_as_handled()


func _on_primary_pressed() -> void:
	if active_missions.size() >= rockets_owned:
		return
	var planet := _planet_by_id(selected_planet_id)
	if planet.is_empty():
		return
	if _has_mission_for_planet(selected_planet_id):
		mission_feed = "A rocket is already assigned to this planet."
		_refresh_interface()
		return
	if not scanned_planet_ids.has(selected_planet_id) and float(planet["distance"]) > fuel_range:
		mission_feed = "Upgrade the ship's fuel range before exploring this world."
		_refresh_interface()
		return

	# The first visit surveys a world. Repeat visits collect smaller resource caches.
	var is_probe := scanned_planet_ids.has(selected_planet_id)
	var flight_duration := _flight_duration(float(planet["distance"]))
	var mission := {
		"rocket_id": next_rocket_id,
		"planet_id": selected_planet_id,
		"is_probe": is_probe,
		"phase": "outbound",
		"duration": flight_duration,
		"time_left": flight_duration,
		"reward": 0,
		"crates": 0,
		"cargo_resource": "",
		"research_bonus": 0,
		"resource_multiplier": 1.0,
		"alien_pending": rng.randf() < ALIEN_SPAWN_CHANCE,
	}
	next_rocket_id += 1
	active_missions.append(mission)
	if is_probe:
		mission_feed = "Free rocket launched to harvest another cache from %s." % planet["name"]
	else:
		mission_feed = "Survey ship dispatched to %s. Cargo is sold on return." % planet["name"]
	_start_pending_alien_challenge()
	_save_game()
	_refresh_interface()


func _on_buy_rocket_pressed() -> void:
	if rockets_owned >= MAX_ROCKETS:
		return
	var cost := _next_rocket_cost()
	if credits < cost:
		mission_feed = "Not enough credits to add another rocket."
		_refresh_interface()
		return

	credits -= cost
	rockets_owned += 1
	mission_feed = "Rocket added to the fleet. More missions can now run at once."
	_save_game()
	_refresh_interface()


func _on_land_pressed() -> void:
	var mission := _landing_target_mission()
	if mission.is_empty():
		return

	var rocket_id := int(mission["rocket_id"])
	var mission_index := _active_mission_index(rocket_id)
	if mission_index < 0:
		return
	var phase := String(mission["phase"])
	if phase == "awaiting_landing":
		mission["phase"] = "landing_qte"
		active_missions[mission_index] = mission
		landing_rocket_id = rocket_id
		landing_qte_elapsed = 0.0
		landing_marker_position = 0.0
		mission_feed = "Landing approach started. Stop the marker in the green zone."
		landing_audio_player.play()
	elif phase == "landing_qte":
		_resolve_landing_challenge(mission_index, mission)
	elif phase == "alien_combat":
		_resolve_alien_challenge(mission_index, mission)
	_start_pending_alien_challenge()
	_save_game()
	_update_mission_presentation()
	_update_landing_challenge()
	_refresh_interface()


func _resolve_landing_challenge(mission_index: int, mission: Dictionary) -> void:
	var planet := _planet_by_id(String(mission["planet_id"]))
	landing_rocket_id = -1
	landing_qte_elapsed = 0.0

	if landing_marker_position >= LANDING_GREEN_START and landing_marker_position <= LANDING_GREEN_END:
		_start_scanning(mission_index, mission)
		mission_feed = "Safe landing on %s. Scanning and extraction started." % planet.get("name", "the planet")
		return

	# A failed approach crashes the mission and removes one fifth of current credits.
	var lost_credits := roundi(float(credits) * 0.2)
	credits = maxi(0, credits - lost_credits)
	active_missions.remove_at(mission_index)
	solar_map.call("shake_screen", 8.0)
	mission_feed = "Rocket crashed at %s. Lost CR %d." % [planet.get("name", "the planet"), lost_credits]


func _begin_alien_combat(mission_index: int, mission: Dictionary) -> void:
	# Pause the outbound flight until the four strike encounter is resolved.
	mission["phase_before_alien"] = String(mission.get("phase", "outbound"))
	mission["phase"] = "alien_combat"
	mission["alien_pending"] = false
	mission["alien_attempts"] = 0
	mission["alien_hits"] = 0
	active_missions[mission_index] = mission
	landing_rocket_id = int(mission["rocket_id"])
	landing_qte_elapsed = 0.0
	landing_marker_position = 0.0
	mission_feed = "An alien intercepted the rocket en route to %s. Hit green on 3 of 4 strikes to win." % _planet_by_id(String(mission["planet_id"])).get("name", "the planet")


func _start_scanning(mission_index: int, mission: Dictionary) -> void:
	# The same scan duration applies whether or not an alien encounter happened.
	mission["phase"] = "scanning"
	var scan_duration := PROBE_DURATION if bool(mission["is_probe"]) else SURVEY_DURATION
	mission["duration"] = scan_duration
	mission["time_left"] = scan_duration
	active_missions[mission_index] = mission


func _resolve_alien_challenge(mission_index: int, mission: Dictionary) -> void:
	var hit := landing_marker_position >= LANDING_GREEN_START and landing_marker_position <= LANDING_GREEN_END
	var attempts := int(mission.get("alien_attempts", 0)) + 1
	var hits := int(mission.get("alien_hits", 0)) + (1 if hit else 0)
	mission["alien_attempts"] = attempts
	mission["alien_hits"] = hits

	if attempts < ALIEN_FIGHT_ROUNDS:
		active_missions[mission_index] = mission
		landing_qte_elapsed = 0.0
		landing_marker_position = 0.0
		mission_feed = "Strike hit. %d of 4 landed in the green zone." % hits if hit else "Strike missed. %d of 4 landed in the green zone." % hits
		return

	landing_rocket_id = -1
	landing_qte_elapsed = 0.0
	mission["resource_multiplier"] = 2.0 if hits >= ALIEN_HITS_TO_WIN else 0.5
	mission["phase"] = String(mission.get("phase_before_alien", "outbound"))
	mission.erase("phase_before_alien")
	mission["alien_attempts"] = 0
	mission["alien_hits"] = 0
	active_missions[mission_index] = mission
	if hits >= ALIEN_HITS_TO_WIN:
		mission_feed = "Alien defeated. Resources from this survey will be doubled."
	else:
		mission_feed = "Alien fight lost. Resources from this survey will be halved."
	_start_pending_alien_challenge()


func _start_pending_alien_challenge() -> bool:
	# Continue a saved fight before starting queued encounters or landing challenges.
	if landing_rocket_id >= 0:
		return false
	for mission in active_missions:
		if String(mission.get("phase", "")) == "alien_combat":
			landing_rocket_id = int(mission["rocket_id"])
			landing_marker_position = _landing_marker_at(landing_qte_elapsed)
			return true
	for mission in active_missions:
		if String(mission.get("phase", "")) == "awaiting_landing":
			return false
	for index in range(active_missions.size()):
		var mission: Dictionary = active_missions[index]
		if String(mission.get("phase", "")) != "outbound" or not bool(mission.get("alien_pending", false)):
			continue
		_begin_alien_combat(index, mission)
		return true
	return false


func _flight_duration(distance: float) -> float:
	return 3.2 + distance / 220.0


func _advance_missions(delta: float) -> bool:
	var changed := false
	var index := active_missions.size() - 1
	while index >= 0:
		var mission: Dictionary = active_missions[index]
		var phase := String(mission.get("phase", ""))
		if ["outbound", "scanning", "returning"].has(phase):
			var previous_time_left := float(mission.get("time_left", 0.0))
			mission["time_left"] = maxf(0.0, float(mission.get("time_left", 0.0)) - delta)
			active_missions[index] = mission
			if float(mission["time_left"]) <= 0.0:
				if phase == "outbound" and bool(mission.get("alien_pending", false)):
					# Hold arrival until this rocket's queued encounter gets its turn.
					changed = changed or (previous_time_left > 0.0)
				else:
					_advance_mission_at(index, mission)
					changed = true
		index -= 1
	return changed


func _advance_mission_at(index: int, mission: Dictionary) -> void:
	var phase := String(mission["phase"])
	var planet := _planet_by_id(String(mission["planet_id"]))
	if planet.is_empty():
		active_missions.remove_at(index)
		mission_feed = "A mission ended because its destination is no longer available."
		return

	if phase == "outbound":
		mission["phase"] = "awaiting_landing"
		mission["time_left"] = 0.0
		active_missions[index] = mission
		landing_audio_player.play()
		mission_feed = "Rocket arrived at %s. Press E or click Land to start." % planet["name"]
	elif phase == "scanning":
		mission = _finish_scan(mission)
		var return_duration := _flight_duration(float(planet["distance"]))
		mission["phase"] = "returning"
		mission["duration"] = return_duration
		mission["time_left"] = return_duration
		active_missions[index] = mission
		mission_feed = "Cargo: %d crates of %s. Sale on arrival: CR %d." % [
			int(mission["crates"]),
			String(mission["cargo_resource"]),
			int(mission["reward"]),
		]
	elif phase == "returning":
		credits += int(mission["reward"])
		mission_feed = "%s returned. Sold %d crates of %s for CR %d." % [
			String(planet["name"]),
			int(mission["crates"]),
			String(mission["cargo_resource"]),
			int(mission["reward"]),
		]
		active_missions.remove_at(index)


func _finish_scan(mission: Dictionary) -> Dictionary:
	var planet := _planet_by_id(String(mission["planet_id"]))
	if planet.is_empty():
		return mission

	# Repeat probes collect less and do not replace the first survey report.
	if bool(mission["is_probe"]):
		var probe_min := maxi(1, floori(float(planet["crate_min"]) / 2.0))
		var probe_max := maxi(probe_min, floori(float(planet["crate_max"]) / 2.0) + 1)
		mission["crates"] = rng.randi_range(probe_min, probe_max)
		mission["research_bonus"] = 0
		mission["cargo_resource"] = String(planet["resource"])
	else:
		mission["crates"] = rng.randi_range(int(planet["crate_min"]), int(planet["crate_max"]))
		mission["research_bonus"] = 42
		mission["cargo_resource"] = String(planet["resource"])
		if not scanned_planet_ids.has(String(mission["planet_id"])):
			scanned_planet_ids.append(String(mission["planet_id"]))

	var resource_multiplier := float(mission.get("resource_multiplier", 1.0))
	if resource_multiplier < 1.0:
		mission["crates"] = floori(float(mission["crates"]) * resource_multiplier)
	else:
		mission["crates"] = roundi(float(mission["crates"]) * resource_multiplier)
	if not bool(mission["is_probe"]):
		planet_reports[String(mission["planet_id"])] = "No safe settlement conditions. %d crates of %s secured." % [
			int(mission["crates"]),
			String(planet["resource"]),
		]
	var cargo_value := int(mission["crates"]) * int(planet["crate_price"])
	mission["reward"] = roundi(float(cargo_value + int(mission["research_bonus"])) * _recovery_efficiency())
	return mission


func _check_for_victory() -> bool:
	# The win condition uses the current authored planet catalog, including new planets.
	if run_finished or planet_data.is_empty():
		return false
	if scanned_planet_ids.size() < planet_data.size() or earth_health < 100.0:
		return false
	_finish_run(true)
	return true


func _finish_run(won: bool) -> void:
	# Save each completed run once while keeping run history separate from progress.
	if run_finished:
		return

	game_started = false
	game_paused = false
	var planets_scanned := scanned_planet_ids.size()
	var elapsed_seconds := roundi(run_elapsed_seconds)
	var score := _run_score(planets_scanned, credits, earth_health, elapsed_seconds, won)

	run_result_record = {
		"outcome": "WIN" if won else "EARTH LOST",
		"score": score,
		"planets_scanned": planets_scanned,
		"planet_total": planet_data.size(),
		"earth_health": roundi(earth_health),
		"credits": credits,
		"elapsed_seconds": elapsed_seconds,
		"date": Time.get_datetime_string_from_system(false, false),
	}
	run_finished = true
	leaderboard_runs.append(run_result_record.duplicate())
	leaderboard_runs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("score", 0)) > int(b.get("score", 0))
	)
	if leaderboard_runs.size() > MAX_LEADERBOARD_RUNS:
		leaderboard_runs.resize(MAX_LEADERBOARD_RUNS)
	_save_leaderboard()
	_save_game()
	_refresh_interface()
	menu_overlay.call("set_run_finished", true)
	menu_overlay.call("set_leaderboard_runs", leaderboard_runs)
	menu_overlay.call("show_run_result", run_result_record)


func _run_score(planets_scanned: int, remaining_credits: int, final_earth_health: float, elapsed_seconds: int, won: bool) -> int:
	# Reward exploration, Earth's condition, saved credits, and faster runs.
	var speed_bonus := maxi(0, 3600 - maxi(0, elapsed_seconds))
	var score := maxi(0, planets_scanned) * 10000
	score += maxi(0, remaining_credits) + roundi(clampf(final_earth_health, 0.0, 100.0) * 100.0) + speed_bonus
	if won:
		score += 100000
	return score


func _save_leaderboard() -> void:
	# Run records survive progress resets so players can compare expeditions.
	var file := FileAccess.open(LEADERBOARD_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not save Earthward leaderboard: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(leaderboard_runs))
	file.close()


func _load_leaderboard() -> void:
	if not FileAccess.file_exists(LEADERBOARD_PATH):
		return
	var file := FileAccess.open(LEADERBOARD_PATH, FileAccess.READ)
	if file == null:
		push_warning("Could not read Earthward leaderboard: %s" % error_string(FileAccess.get_open_error()))
		return
	var parsed_data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	var saved_runs: Array = []
	if parsed_data is Array:
		saved_runs = parsed_data
	elif parsed_data is Dictionary:
		# Accept the brief ordinal-label format while returning to the ranked list format.
		var runs_value: Variant = parsed_data.get("runs", [])
		if runs_value is Array:
			saved_runs = runs_value
	else:
		push_warning("Earthward leaderboard is invalid. It will be replaced after the next run.")
		return
	for saved_record in saved_runs:
		if not saved_record is Dictionary:
			continue
		var record: Dictionary = saved_record.duplicate()
		record.erase("win_number")
		var won := String(record.get("outcome", "")) == "WIN"
		record["score"] = _run_score(
			int(record.get("planets_scanned", 0)),
			int(record.get("credits", 0)),
			float(record.get("earth_health", 0.0)),
			int(record.get("elapsed_seconds", 0)),
			won
		)
		leaderboard_runs.append(record)
	leaderboard_runs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("score", 0)) > int(b.get("score", 0))
	)
	if leaderboard_runs.size() > MAX_LEADERBOARD_RUNS:
		leaderboard_runs.resize(MAX_LEADERBOARD_RUNS)

func _recovery_efficiency() -> float:
	# A healthier Earth makes returned cargo more valuable.
	return 0.65 + earth_health / 100.0 * 0.35


func _landing_marker_at(elapsed: float) -> float:
	var sweep_position := fposmod(elapsed / LANDING_SWEEP_TIME, 2.0)
	if sweep_position <= 1.0:
		return sweep_position
	return 2.0 - sweep_position


func _update_landing_challenge() -> void:
	var mission := _landing_target_mission()
	if mission.is_empty():
		landing_challenge_panel.visible = false
		alien_sprite.visible = false
		land_button.visible = false
		return

	landing_challenge_panel.visible = true
	land_button.visible = true
	var phase := String(mission["phase"])
	var is_alien_fight := phase == "alien_combat"
	alien_sprite.visible = is_alien_fight
	var planet := _planet_by_id(String(mission["planet_id"]))
	var planet_name := String(planet.get("name", "planet"))
	if phase == "landing_qte":
		landing_hint.text = "Press E or click Land while the marker is in the green zone."
		land_button.text = "Land now"
		landing_marker.visible = true
	elif is_alien_fight:
		var next_round := int(mission.get("alien_attempts", 0)) + 1
		landing_hint.text = "Alien intercept near %s. Round %d of 4. Hit green 3 times to win." % [planet_name, next_round]
		land_button.text = "Strike now"
		landing_marker.visible = true
	else:
		landing_hint.text = "Arrival at %s. Press E or click Start landing." % planet_name
		land_button.text = "Start landing"
		landing_marker.visible = false
	if phase == "landing_qte" or is_alien_fight:
		var marker_width := landing_marker.size.x
		var travel_width := maxf(0.0, landing_track.size.x - marker_width)
		landing_marker.position.x = travel_width * landing_marker_position


func _update_mission_presentation() -> void:
	var map_missions: Array[Dictionary] = []
	for mission in active_missions:
		var map_mission: Dictionary = mission.duplicate()
		map_mission["progress"] = _mission_phase_progress(mission)
		map_missions.append(map_mission)
	solar_map.call("set_mission_states", map_missions)


func _mission_phase_progress(mission: Dictionary) -> float:
	var phase := String(mission.get("phase", ""))
	if phase == "awaiting_landing" or phase == "landing_qte" or phase == "alien_combat":
		return 1.0
	var duration := float(mission.get("duration", 0.0))
	if duration <= 0.0:
		return 0.0
	return clampf(1.0 - float(mission.get("time_left", 0.0)) / duration, 0.0, 1.0)


func _sync_flight_audio() -> void:
	# Play the flight sound while any rocket travels between Earth and a planet.
	var is_in_transit := false
	for mission in active_missions:
		var phase := String(mission.get("phase", ""))
		if phase == "outbound" or phase == "returning":
			is_in_transit = true
			break
	var should_play := game_started and not game_paused and is_in_transit
	if should_play and not flight_audio_player.playing:
		flight_audio_player.play()
	elif not should_play and flight_audio_player.playing:
		flight_audio_player.stop()


func _refresh_interface() -> void:
	# Render expedition state into controls that are already present in Main.tscn.
	credits_value.text = "CR %d" % credits
	range_value.text = "%d units" % roundi(fuel_range)
	ship_value.text = "Docked at Earth" if active_missions.is_empty() else "%d active" % active_missions.size()
	solar_map.call("configure", planet_data, selected_planet_id, scanned_planet_ids, fuel_range)
	solar_map.call("set_earth_health", earth_health)

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
		var planet_is_assigned := _has_mission_for_planet(selected_planet_id)
		var has_ready_rocket := active_missions.size() < rockets_owned
		if surveyed:
			range_note.text = "Surveyed · repeat rocket flights are free."
		elif can_reach:
			range_note.text = "In range · no launch fee."
		else:
			range_note.text = "Out of range · upgrade fuel to reach this planet."

		if planet_is_assigned:
			primary_button.text = "Rocket already assigned"
			primary_button.disabled = true
		elif not can_reach and not surveyed:
			primary_button.text = "Out of range"
			primary_button.disabled = true
		elif not has_ready_rocket:
			primary_button.text = "No rockets ready"
			primary_button.disabled = true
		elif surveyed:
			primary_button.text = "Send free rocket"
			primary_button.disabled = false
		else:
			primary_button.text = "Launch survey"
			primary_button.disabled = false

	var fuel_cost := _current_fuel_cost()
	if fuel_tier >= FUEL_TANK_COSTS.size():
		fuel_button.text = "Maximum range"
		fuel_button.disabled = true
	else:
		fuel_button.text = "Upgrade fuel · CR %d" % fuel_cost
		fuel_button.disabled = credits < fuel_cost

	var ready_rockets := maxi(0, rockets_owned - active_missions.size())
	fleet_status_value.text = "%d owned · %d ready · %d active" % [
		rockets_owned,
		ready_rockets,
		active_missions.size(),
	]
	if rockets_owned >= MAX_ROCKETS:
		buy_rocket_button.text = "Fleet maximum reached"
		buy_rocket_button.disabled = true
	else:
		var rocket_cost := _next_rocket_cost()
		buy_rocket_button.text = "Buy rocket · CR %d" % rocket_cost
		buy_rocket_button.disabled = credits < rocket_cost

	var featured_mission := _featured_mission()
	if featured_mission.is_empty():
		mission_phase_value.text = "Ready"
		mission_detail_value.text = "Select a planet to begin."
	else:
		var mission_planet := _planet_by_id(String(featured_mission["planet_id"]))
		var planet_name := String(mission_planet.get("name", "planet"))
		match String(featured_mission["phase"]):
			"outbound":
				mission_phase_value.text = "Travelling to %s" % planet_name
				mission_detail_value.text = "Outbound flight, %d seconds left." % ceili(float(featured_mission["time_left"]))
			"awaiting_landing":
				mission_phase_value.text = "Ready to land at %s" % planet_name
				mission_detail_value.text = "Start the landing challenge to begin scanning."
			"landing_qte":
				mission_phase_value.text = "Landing challenge"
				mission_detail_value.text = "Stop the marker in the green zone."
			"alien_combat":
				mission_phase_value.text = "Alien encounter"
				mission_detail_value.text = "Win 3 of 4 strikes to double cargo. Otherwise, cargo is halved."
			"scanning":
				mission_phase_value.text = "Scanning %s" % planet_name
				mission_detail_value.text = "Scanning and collecting resources."
			"returning":
				mission_phase_value.text = "Returning to Earth"
				mission_detail_value.text = "Estimated sale on arrival: CR %d." % int(featured_mission["reward"])
	mission_progress_bar.value = _mission_phase_progress(featured_mission) * 100.0
	mission_feed_value.text = mission_feed
	_update_landing_challenge()

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
	if earth_health >= 100.0:
		restore_button.text = "Earth is stable"
		restore_button.disabled = true
	else:
		restore_button.text = "Restore Earth · CR %d" % restore_cost
		restore_button.disabled = credits < restore_cost


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
	if earth_health >= 100.0:
		return
	var cost := _earth_restore_cost()
	if credits < cost:
		mission_feed = "Not enough credits to fund Earth's restoration systems."
		_refresh_interface()
		return

	credits -= cost
	earth_health = minf(100.0, earth_health + 24.0)
	mission_feed = "Restoration investment deployed. Earth vitality improved."
	if _check_for_victory():
		return
	_save_game()
	_refresh_interface()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_game()


func _save_game() -> void:
	# Save every mission independently so concurrent flights survive a restart.
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not save Earthward progress: %s" % error_string(FileAccess.get_open_error()))
		return

	var save_data := {
		"save_version": 5,
		"credits": credits,
		"earth_health": earth_health,
		"fuel_tier": fuel_tier,
		"selected_planet_id": selected_planet_id,
		"scanned_planet_ids": scanned_planet_ids,
		"planet_reports": planet_reports,
		"mission_feed": mission_feed,
		"rockets_owned": rockets_owned,
		"next_rocket_id": next_rocket_id,
		"active_missions": active_missions,
		"landing_rocket_id": landing_rocket_id,
		"landing_qte_elapsed": landing_qte_elapsed,
		"run_elapsed_seconds": run_elapsed_seconds,
		"run_finished": run_finished,
		"run_result_record": run_result_record,
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
	rockets_owned = clampi(int(save_data.get("rockets_owned", rockets_owned)), 1, MAX_ROCKETS)
	next_rocket_id = maxi(1, int(save_data.get("next_rocket_id", next_rocket_id)))
	var used_rocket_ids: Dictionary = {}
	if save_data.has("active_missions") and save_data["active_missions"] is Array:
		for saved_mission in save_data["active_missions"]:
			if saved_mission is Dictionary:
				_restore_saved_mission(saved_mission, used_rocket_ids)
	else:
		_restore_legacy_mission(save_data, used_rocket_ids)

	rockets_owned = clampi(maxi(rockets_owned, active_missions.size()), 1, MAX_ROCKETS)
	var highest_rocket_id := 0
	for mission in active_missions:
		highest_rocket_id = maxi(highest_rocket_id, int(mission["rocket_id"]))
	next_rocket_id = maxi(next_rocket_id, highest_rocket_id + 1)
	landing_rocket_id = int(save_data.get("landing_rocket_id", -1))
	landing_qte_elapsed = maxf(0.0, float(save_data.get("landing_qte_elapsed", 0.0)))

	var active_landing := _mission_for_rocket(landing_rocket_id)
	var active_landing_phase := String(active_landing.get("phase", ""))
	if active_landing.is_empty() or not ["landing_qte", "alien_combat"].has(active_landing_phase):
		landing_rocket_id = -1
		landing_qte_elapsed = 0.0
		for index in range(active_missions.size()):
			var mission: Dictionary = active_missions[index]
			if String(mission.get("phase", "")) == "landing_qte":
				mission["phase"] = "awaiting_landing"
				active_missions[index] = mission
	landing_marker_position = _landing_marker_at(landing_qte_elapsed)
	run_elapsed_seconds = maxf(0.0, float(save_data.get("run_elapsed_seconds", 0.0)))
	run_finished = bool(save_data.get("run_finished", false))
	var saved_result: Variant = save_data.get("run_result_record", {})
	if saved_result is Dictionary:
		run_result_record = saved_result


func _restore_saved_mission(saved_mission: Dictionary, used_rocket_ids: Dictionary) -> void:
	if active_missions.size() >= MAX_ROCKETS:
		return
	var planet_id := String(saved_mission.get("planet_id", ""))
	var phase := String(saved_mission.get("phase", ""))
	var valid_phases := ["outbound", "awaiting_landing", "landing_qte", "alien_combat", "scanning", "returning"]
	if _planet_by_id(planet_id).is_empty() or not valid_phases.has(phase):
		return

	var rocket_id := maxi(1, int(saved_mission.get("rocket_id", next_rocket_id)))
	if used_rocket_ids.has(rocket_id):
		rocket_id = next_rocket_id
	next_rocket_id = maxi(next_rocket_id, rocket_id + 1)
	used_rocket_ids[rocket_id] = true
	var duration := maxf(0.1, float(saved_mission.get("duration", 0.1)))
	var time_left := clampf(float(saved_mission.get("time_left", duration)), 0.0, duration)
	if phase == "awaiting_landing" or phase == "landing_qte":
		time_left = 0.0
	active_missions.append({
		"rocket_id": rocket_id,
		"planet_id": planet_id,
		"is_probe": bool(saved_mission.get("is_probe", false)),
		"phase": phase,
		"duration": duration,
		"time_left": time_left,
		"reward": maxi(0, int(saved_mission.get("reward", 0))),
		"crates": maxi(0, int(saved_mission.get("crates", 0))),
		"cargo_resource": String(saved_mission.get("cargo_resource", "")),
		"research_bonus": maxi(0, int(saved_mission.get("research_bonus", 0))),
		"resource_multiplier": float(saved_mission.get("resource_multiplier", 1.0)),
		"alien_pending": bool(saved_mission.get("alien_pending", false)),
		"phase_before_alien": String(saved_mission.get("phase_before_alien", "outbound")),
		"alien_attempts": clampi(int(saved_mission.get("alien_attempts", 0)), 0, ALIEN_FIGHT_ROUNDS - 1),
		"alien_hits": clampi(int(saved_mission.get("alien_hits", 0)), 0, ALIEN_FIGHT_ROUNDS),
	})


func _restore_legacy_mission(save_data: Dictionary, used_rocket_ids: Dictionary) -> void:
	# Convert the version 2 single mission into the new mission list.
	var phase := String(save_data.get("mission_phase", "idle"))
	var planet_id := String(save_data.get("mission_planet_id", ""))
	if not ["outbound", "scanning", "returning"].has(phase):
		return
	_restore_saved_mission({
		"rocket_id": 1,
		"planet_id": planet_id,
		"is_probe": bool(save_data.get("mission_was_probe", false)),
		"phase": phase,
		"duration": float(save_data.get("mission_duration", 0.1)),
		"time_left": float(save_data.get("mission_time_left", 0.1)),
		"reward": int(save_data.get("mission_reward", 0)),
		"crates": int(save_data.get("mission_crates", 0)),
		"cargo_resource": String(save_data.get("mission_cargo_resource", "")),
		"research_bonus": int(save_data.get("mission_research_bonus", 0)),
	}, used_rocket_ids)
