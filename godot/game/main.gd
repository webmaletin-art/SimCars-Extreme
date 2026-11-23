extends Node
## Raíz del juego: carga el perfil, muestra el menú sobre la sala de exhibición y arranca / cierra la partida.

const Profile := preload("res://game/save/profile.gd")
const Showroom := preload("res://game/ui/showroom.gd")
const Menu := preload("res://game/ui/menu.gd")
const Play := preload("res://game/play.gd")
const Garage := preload("res://game/data/garage.gd")
const Gfx := preload("res://game/ui/gfx.gd")

var profile: Dictionary
var showroom: Node3D
var menu: Control
var layer: CanvasLayer
var play: Node3D

func _ready() -> void:
	profile = Profile.load_profile()
	Gfx.apply_screen(get_tree(), profile["settings"])
	var args := OS.get_cmdline_user_args()
	if "--play" in args or "--autotest" in args:
		for a in args:
			if a.begins_with("--car="):
				profile["car"] = a.substr(6)
			elif a.begins_with("--char="):
				profile["char"] = a.substr(7)
		_start_play()
		return
	_show_menu()
	for a in args:
		if a.begins_with("--menu-shot="):
			var path := a.substr(12)
			var screen := "main"
			for b in args:
				if b.begins_with("--screen="):
					screen = b.substr(9)
			if screen != "main":
				menu.call("_" + screen)
			await get_tree().create_timer(1.6).timeout
			get_viewport().get_texture().get_image().save_png(path)
			get_tree().quit()

func _show_menu() -> void:
	if play != null:
		play.queue_free()
		play = null
	get_viewport().scaling_3d_scale = 1.0
	showroom = Showroom.new()
	add_child(showroom)
	layer = CanvasLayer.new()
	add_child(layer)
	menu = Menu.new()
	menu.profile = profile
	menu.showroom = showroom
	layer.add_child(menu)
	menu.play_pressed.connect(_start_play)
	menu.quit_pressed.connect(func() -> void: get_tree().quit())

func _start_play() -> void:
	if showroom != null:
		showroom.queue_free()
		showroom = null
	if layer != null:
		layer.queue_free()
		layer = null
	play = Play.new()
	play.profile = profile
	play.exit_to_menu.connect(func() -> void:
		Profile.save_profile(profile)
		_show_menu())
	add_child(play)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		Profile.save_profile(profile)
