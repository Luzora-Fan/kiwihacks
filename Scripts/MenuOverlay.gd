extends Control

# The game controller owns simulation state while this scene owns menu navigation.
signal play_requested
signal resume_requested
signal main_menu_requested
signal quit_requested
signal reset_progress_requested

const SETTINGS_PATH := "user://earthward_settings.cfg"
const GUIDE_STEPS := [
	{
		"title": "Choose a destination",
		"text": "Select a planet on the map. Its distance, resources, and survey status appear in the destination panel.",
	},
	{
		"title": "Check your range",
		"text": "The ship starts with a range of 260 units. If a planet is too far away, use Upgrade fuel in the sidebar. Each fuel tank costs credits.",
	},
	{
		"title": "Launch a survey",
		"text": "Choose a planet in range and launch a rocket. At the planet, press E or click Land, then stop the marker in the green zone. Red means a crash and costs 20% of your credits.",
	},
	{
		"title": "Restore Earth",
		"text": "Returned cargo earns credits. Earth loses health while a run is active. Use Restore Earth to improve its health and raise the value of future cargo.",
	},
	{
		"title": "Explore again",
		"text": "A surveyed planet can be visited again with a free rocket. Buy more rockets to run missions at the same time. Turn on Follow rocket to track the fleet, or drag the map to pan.",
	},
	{
		"title": "Win and compare runs",
		"text": "Scan every planet and restore Earth to 100% to win. Your best runs stay on the leaderboard when you reset progress.",
	},
]

@onready var main_page: VBoxContainer = $Card/Pages/MainPage
@onready var title_background: TextureRect = $TitleBackground
@onready var settings_page: VBoxContainer = $Card/Pages/SettingsPage
@onready var controls_page: VBoxContainer = $Card/Pages/ControlsPage
@onready var guide_page: VBoxContainer = $Card/Pages/GuidePage
@onready var credits_page: VBoxContainer = $Card/Pages/CreditsPage
@onready var pause_page: VBoxContainer = $Card/Pages/PausePage
@onready var leaderboard_page: VBoxContainer = $Card/Pages/LeaderboardPage
@onready var volume_slider: HSlider = $Card/Pages/SettingsPage/VolumeRow/VolumeSlider
@onready var volume_value: Label = $Card/Pages/SettingsPage/VolumeRow/VolumeValue
@onready var fullscreen_toggle: CheckButton = $Card/Pages/SettingsPage/FullscreenToggle
@onready var reset_confirmation: ConfirmationDialog = $ResetConfirmation
@onready var guide_step_count: Label = $Card/Pages/GuidePage/StepCount
@onready var guide_step_title: Label = $Card/Pages/GuidePage/StepTitle
@onready var guide_step_text: Label = $Card/Pages/GuidePage/StepText
@onready var guide_previous_button: Button = $Card/Pages/GuidePage/Navigation/PreviousButton
@onready var guide_next_button: Button = $Card/Pages/GuidePage/Navigation/NextButton
@onready var leaderboard_title: Label = $Card/Pages/LeaderboardPage/Title
@onready var leaderboard_summary: Label = $Card/Pages/LeaderboardPage/Summary
@onready var leaderboard_list: ItemList = $Card/Pages/LeaderboardPage/LeaderboardList
@onready var leaderboard_new_run_button: Button = $Card/Pages/LeaderboardPage/Actions/NewRunButton
@onready var leaderboard_main_menu_button: Button = $Card/Pages/LeaderboardPage/Actions/MainMenuButton
@onready var leaderboard_back_button: Button = $Card/Pages/LeaderboardPage/Actions/BackButton

var _return_page := "main"
var _master_bus_index := -1
var _current_guide_step := 0
var _leaderboard_runs: Array[Dictionary] = []


func _ready() -> void:
	_master_bus_index = AudioServer.get_bus_index("Master")
	_load_settings()
	$Card/Pages/MainPage/PlayButton.pressed.connect(_on_play_pressed)
	$Card/Pages/MainPage/GuideButton.pressed.connect(_open_guide_from_main)
	$Card/Pages/MainPage/LeaderboardButton.pressed.connect(_open_leaderboard_from_main)
	$Card/Pages/MainPage/SettingsButton.pressed.connect(_open_settings_from_main)
	$Card/Pages/MainPage/ControlsButton.pressed.connect(_open_controls_from_main)
	$Card/Pages/MainPage/CreditsButton.pressed.connect(_open_credits_from_main)
	$Card/Pages/MainPage/QuitButton.pressed.connect(_on_quit_pressed)
	$Card/Pages/SettingsPage/BackButton.pressed.connect(_return_to_previous_page)
	$Card/Pages/SettingsPage/ResetProgressButton.pressed.connect(_on_reset_progress_pressed)
	reset_confirmation.confirmed.connect(_on_reset_progress_confirmed)
	$Card/Pages/ControlsPage/BackButton.pressed.connect(_return_to_previous_page)
	$Card/Pages/GuidePage/Navigation/PreviousButton.pressed.connect(_on_previous_guide_step_pressed)
	$Card/Pages/GuidePage/Navigation/NextButton.pressed.connect(_on_next_guide_step_pressed)
	$Card/Pages/GuidePage/ReturnButton.pressed.connect(_return_to_previous_page)
	$Card/Pages/CreditsPage/BackButton.pressed.connect(_return_to_previous_page)
	$Card/Pages/PausePage/ResumeButton.pressed.connect(_on_resume_pressed)
	$Card/Pages/PausePage/GuideButton.pressed.connect(_open_guide_from_pause)
	$Card/Pages/PausePage/LeaderboardButton.pressed.connect(_open_leaderboard_from_pause)
	$Card/Pages/PausePage/SettingsButton.pressed.connect(_open_settings_from_pause)
	$Card/Pages/PausePage/ControlsButton.pressed.connect(_open_controls_from_pause)
	$Card/Pages/PausePage/CreditsButton.pressed.connect(_open_credits_from_pause)
	$Card/Pages/PausePage/MainMenuButton.pressed.connect(_on_main_menu_pressed)
	$Card/Pages/PausePage/QuitButton.pressed.connect(_on_quit_pressed)
	leaderboard_new_run_button.pressed.connect(_on_leaderboard_new_run_pressed)
	leaderboard_main_menu_button.pressed.connect(_on_main_menu_pressed)
	leaderboard_back_button.pressed.connect(_return_to_previous_page)
	volume_slider.value_changed.connect(_on_volume_changed)
	volume_slider.drag_ended.connect(_on_volume_drag_ended)
	volume_slider.focus_exited.connect(_save_settings)
	fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	_show_page("main")


func show_main_menu() -> void:
	visible = true
	_return_page = "main"
	_show_page("main")


func show_pause_menu() -> void:
	visible = true
	_show_page("pause")


func hide_overlay() -> void:
	visible = false


func set_run_finished(finished: bool) -> void:
	# Let players reopen their final results after returning to the main menu.
	var play_button: Button = $Card/Pages/MainPage/PlayButton
	play_button.text = "View run results" if finished else "Play"


func set_leaderboard_runs(runs: Array) -> void:
	# Copy records so the menu can redraw its list without owning save data.
	_leaderboard_runs.clear()
	for run in runs:
		if run is Dictionary:
			_leaderboard_runs.append(run)
	_refresh_leaderboard()


func show_run_result(record: Dictionary) -> void:
	# The result page also shows earlier runs for an immediate comparison.
	_return_page = "main"
	var won := String(record.get("outcome", "")) == "WIN"
	leaderboard_title.text = "EARTH RESTORED" if won else "RUN ENDED"
	var score := int(record.get("score", 0))
	var scanned := int(record.get("planets_scanned", 0))
	var total := int(record.get("planet_total", 0))
	var elapsed := _format_run_time(int(record.get("elapsed_seconds", 0)))
	if won:
		leaderboard_summary.text = "Every planet scanned and Earth restored to 100%.\nFinal score %d after %s." % [score, elapsed]
	else:
		leaderboard_summary.text = "Earth reached 0% health.\nScore %d with %d of %d planets scanned in %s." % [score, scanned, total, elapsed]
	leaderboard_new_run_button.visible = true
	leaderboard_main_menu_button.visible = true
	leaderboard_back_button.visible = false
	_refresh_leaderboard()
	visible = true
	_show_page("leaderboard")


func _show_page(page_name: String) -> void:
	# Pages share one card, with only the requested screen visible at a time.
	# Keep title art on menu pages, then reveal the game behind the pause overlay.
	title_background.visible = page_name != "pause" and _return_page != "pause"
	main_page.visible = page_name == "main"
	settings_page.visible = page_name == "settings"
	controls_page.visible = page_name == "controls"
	guide_page.visible = page_name == "guide"
	credits_page.visible = page_name == "credits"
	pause_page.visible = page_name == "pause"
	leaderboard_page.visible = page_name == "leaderboard"


func _open_settings_from_main() -> void:
	_return_page = "main"
	_show_page("settings")


func _open_settings_from_pause() -> void:
	_return_page = "pause"
	_show_page("settings")


func _open_controls_from_main() -> void:
	_return_page = "main"
	_show_page("controls")


func _open_controls_from_pause() -> void:
	_return_page = "pause"
	_show_page("controls")


func _open_guide_from_main() -> void:
	_return_page = "main"
	_open_guide()


func _open_guide_from_pause() -> void:
	_return_page = "pause"
	_open_guide()


func _open_guide() -> void:
	_update_guide_step(0)
	_show_page("guide")


func _open_leaderboard_from_main() -> void:
	_open_leaderboard("main")


func _open_leaderboard_from_pause() -> void:
	_open_leaderboard("pause")


func _open_leaderboard(return_page: String) -> void:
	# Show past results without changing the current run or its pause state.
	_return_page = return_page
	leaderboard_title.text = "HIGH SCORES"
	leaderboard_summary.text = "Best runs on this device. Records stay after a progress reset."
	leaderboard_new_run_button.visible = false
	leaderboard_main_menu_button.visible = false
	leaderboard_back_button.visible = true
	_refresh_leaderboard()
	_show_page("leaderboard")


func _refresh_leaderboard() -> void:
	leaderboard_list.clear()
	if _leaderboard_runs.is_empty():
		leaderboard_list.add_item("No completed runs yet.")
		return
	for index in range(_leaderboard_runs.size()):
		var run: Dictionary = _leaderboard_runs[index]
		var elapsed := int(run.get("elapsed_seconds", 0))
		var minutes := floori(float(elapsed) / 60.0)
		var seconds := elapsed % 60
		var outcome := String(run.get("outcome", "RUN"))
		var scanned := int(run.get("planets_scanned", 0))
		var total := int(run.get("planet_total", 0))
		var row := "%02d  %s  %7d  %d/%d  %02d:%02d" % [
			index + 1,
			outcome,
			int(run.get("score", 0)),
			scanned,
			total,
			minutes,
			seconds,
		]
		leaderboard_list.add_item(row)


func _format_run_time(seconds: int) -> String:
	var minutes := floori(float(seconds) / 60.0)
	return "%02d:%02d" % [minutes, seconds % 60]


func _update_guide_step(step_index: int) -> void:
	# Keep the walkthrough text and navigation buttons in sync with the current step.
	var last_step := GUIDE_STEPS.size() - 1
	var safe_step := clampi(step_index, 0, last_step)
	var step: Dictionary = GUIDE_STEPS[safe_step]
	guide_step_count.text = "Step %d of %d" % [safe_step + 1, GUIDE_STEPS.size()]
	guide_step_title.text = String(step["title"])
	guide_step_text.text = String(step["text"])
	guide_previous_button.disabled = safe_step == 0
	guide_next_button.text = "Finish" if safe_step == last_step else "Next"
	_current_guide_step = safe_step


func _on_previous_guide_step_pressed() -> void:
	_update_guide_step(_current_guide_step - 1)


func _on_next_guide_step_pressed() -> void:
	if _current_guide_step >= GUIDE_STEPS.size() - 1:
		_return_to_previous_page()
		return
	_update_guide_step(_current_guide_step + 1)


func _open_credits_from_main() -> void:
	_return_page = "main"
	_show_page("credits")


func _open_credits_from_pause() -> void:
	_return_page = "pause"
	_show_page("credits")


func _return_to_previous_page() -> void:
	_show_page(_return_page)


func _on_play_pressed() -> void:
	play_requested.emit()


func _on_resume_pressed() -> void:
	resume_requested.emit()


func _on_main_menu_pressed() -> void:
	main_menu_requested.emit()


func _on_quit_pressed() -> void:
	quit_requested.emit()


func _on_reset_progress_pressed() -> void:
	reset_confirmation.popup_centered()


func _on_reset_progress_confirmed() -> void:
	reset_progress_requested.emit()


func _on_leaderboard_new_run_pressed() -> void:
	# Starting from the result screen deliberately replaces only the current save.
	reset_progress_requested.emit()


func _on_volume_changed(value: float) -> void:
	volume_value.text = "%d%%" % roundi(value * 100.0)
	if _master_bus_index >= 0:
		AudioServer.set_bus_volume_linear(_master_bus_index, value)


func _on_volume_drag_ended(value_changed: bool) -> void:
	if value_changed:
		_save_settings()


func _on_fullscreen_toggled(enabled: bool) -> void:
	# Apply the display change immediately and keep it for the next launch.
	var target_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != target_mode:
		DisplayServer.window_set_mode(target_mode)
	_save_settings()


func _load_settings() -> void:
	# Use the current engine defaults when no user settings file exists yet.
	var config := ConfigFile.new()
	var volume := AudioServer.get_bus_volume_linear(_master_bus_index) if _master_bus_index >= 0 else 1.0
	var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	if config.load(SETTINGS_PATH) == OK:
		volume = clampf(float(config.get_value("audio", "master_volume", volume)), 0.0, 1.0)
		fullscreen = bool(config.get_value("display", "fullscreen", fullscreen))
	volume_slider.value = volume
	volume_value.text = "%d%%" % roundi(volume * 100.0)
	fullscreen_toggle.button_pressed = fullscreen
	if _master_bus_index >= 0:
		AudioServer.set_bus_volume_linear(_master_bus_index, volume)
	var target_mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != target_mode:
		DisplayServer.window_set_mode(target_mode)


func _save_settings() -> void:
	# Store only the options exposed by this prototype menu.
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", volume_slider.value)
	config.set_value("display", "fullscreen", fullscreen_toggle.button_pressed)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save Earthward settings: %s" % error_string(error))
