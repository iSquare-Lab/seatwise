class_name MainMenu
extends Button
## The Menu button and its list. The list opens under the button with its right edge lined up with
## the button's, so it keeps the page margin instead of touching the window edge.

## The item picked: one of the ids in ITEMS.
signal chosen(action: String)

const ITEMS := [
	["new", "New event"], ["example", "Load the example wedding"], [],
	["open", "Open a plan or a guest list…"], ["save", "Save the plan as a file"],
	["chart", "Download the seating chart (PNG)"], ["list", "Download the seat list (PNG)"], ["csv", "Download the guest list (CSV)"], [],
	["clear", "Take everyone off their seats"], ["help", "How to use Seatwise"],
]

var popup := PopupMenu.new()
var _actions: Array[String] = []


func _init() -> void:
	text = "Menu"
	icon = UiTheme.icon("menu")
	tooltip_text = "Menu"
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(46, 46)
	for item: Array in ITEMS:
		if item.is_empty():
			popup.add_separator()
		else:
			popup.add_item(item[1], _actions.size())
			_actions.append(item[0])
	popup.id_pressed.connect(func(id: int) -> void: chosen.emit(_actions[id]))
	add_child(popup)
	pressed.connect(open)


func open() -> void:
	var button := Rect2(get_screen_position(), size)
	popup.reset_size()
	var width := maxi(popup.size.x, int(button.size.x))
	popup.size = Vector2i(width, popup.size.y)
	popup.position = Vector2i(int(button.end.x) - width, int(button.end.y) + 4)
	popup.popup()
