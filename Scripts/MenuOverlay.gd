extends Control

# The game controller owns simulation state while this scene owns menu navigation.
signal play_requested
signal resume_requested
signal main_menu_requested
signal quit_requested
signal reset_progress_requested

const SETTINGS_PATH := "user://earthward_settings.cfg"

@onready var main_page: VBoxContainer = $Card/Pages/MainPage
@onready var settings_page: VBoxContainer = $Card/Pages/SettingsPage
@onready var controls_page: VBoxContainer = $Card/Pages/ControlsPage
@onready var credits_page: VBoxContainer = $Card/Pages/CreditsPage
@onready var pause_page: VBoxContainer = $Card/Pages/PausePage
@onready var volume_slider: HSlider = $Card/Pages/SettingsPage/VolumeRow/VolumeSlider
@onready var volume_value: Label = $Card/Pages/SettingsPage/VolumeRow/VolumeValue
@onready var fullscreen_toggle: CheckButton = $Card/Pages/SettingsPage/FullscreenToggle
@onready var reset_confirmation: ConfirmationDialog = $ResetConfirmation

var _return_page := "main"
var _master_bus_index := -1


func _ready() -> void:
	_master_bus_index = AudioServer.get_bus_index("Master")
	_load_settings()
	$Card/Pages/MainPage/PlayButton.pressed.connect(_on_play_pressed)
	$Card/Pages/MainPage/SettingsButton.pressed.connect(_open_settings_from_main)
	$Card/Pages/MainPage/ControlsButton.pressed.connect(_open_controls_from_main)
	$Card/Pages/MainPage/CreditsButton.pressed.connect(_open_credits_from_main)
	$Card/Pages/MainPage/QuitButton.pressed.connect(_on_quit_pressed)
	$Card/Pages/SettingsPage/BackButton.pressed.connect(_return_to_previous_page)
	$Card/Pages/SettingsPage/ResetProgressButton.pressed.connect(_on_reset_progress_pressed)
	reset_confirmation.confirmed.connect(_on_reset_progress_confirmed)
	$Card/Pages/ControlsPage/BackButton.pressed.connect(_return_to_previous_page)
	$Card/Pages/CreditsPage/BackButton.pressed.connect(_return_to_previous_page)
	$Card/Pages/PausePage/ResumeButton.pressed.connect(_on_resume_pressed)
	$Card/Pages/PausePage/SettingsButton.pressed.connect(_open_settings_from_pause)
	$Card/Pages/PausePage/ControlsButton.pressed.connect(_open_controls_from_pause)
	$Card/Pages/PausePage/CreditsButton.pressed.connect(_open_credits_from_pause)
	$Card/Pages/PausePage/MainMenuButton.pressed.connect(_on_main_menu_pressed)
	$Card/Pages/PausePage/QuitButton.pressed.connect(_on_quit_pressed)
	volume_slider.value_changed.connect(_on_volume_changed)
	volume_slider.drag_ended.connect(_on_volume_drag_ended)
	volume_slider.focus_exited.connect(_save_settings)
	fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	_show_page("main")


func show_main_menu() -> void:
	visible = true
	_show_page("main")


func show_pause_menu() -> void:
	visible = true
	_show_page("pause")


func hide_overlay() -> void:
	visible = false


func _show_page(page_name: String) -> void:
	# Pages share one card, with only the requested screen visible at a time.
	main_page.visible = page_name == "main"
	settings_page.visible = page_name == "settings"
	controls_page.visible = page_name == "controls"
	credits_page.visible = page_name == "credits"
	pause_page.visible = page_name == "pause"


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
