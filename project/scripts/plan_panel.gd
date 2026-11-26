class_name PlanPanel
extends PanelContainer
## The plan in its frame, with what floats on it: the status badge (top left), Seat everyone
## (top right), the zoom buttons (bottom right) and the toast (just above the zoom buttons).

signal seat_everyone_pressed
signal status_pressed

const INSET := 10.0
## The space between the toast and the zoom buttons below it.
const TOAST_GAP := 8.0

var view: VenueView
var status: Button
var seat_button: Button
var zoom_box: HBoxContainer
var toast: Label
var _toast_timer: Timer


func _init(plan: Seating) -> void:
	add_theme_stylebox_override("panel", UiTheme.box(UiTheme.BG, 12, 0, UiTheme.FRAME_LINE, 1))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_stretch_ratio = 1.7
	view = VenueView.new()
	view.seating = plan
	view.custom_minimum_size = Vector2(160, 220)
	add_child(view)

	status = Button.new()
	status.focus_mode = Control.FOCUS_ALL
	status.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	status.add_theme_font_size_override("font_size", 14)
	status.custom_minimum_size = Vector2(0, Ui.TAP)
	status.pressed.connect(status_pressed.emit)
	_pin(status, Vector2(0, 0))
	view.add_child(status)

	seat_button = Ui.button("Seat everyone", seat_everyone_pressed.emit, true)
	seat_button.icon = UiTheme.icon("spark")
	seat_button.tooltip_text = "Seats every guest who has no seat yet and improves the whole plan. Locked seats stay."
	seat_button.custom_minimum_size = Vector2(0, 46)
	_pin(seat_button, Vector2(1, 0))
	view.add_child(seat_button)

	zoom_box = HBoxContainer.new()
	zoom_box.add_theme_constant_override("separation", 4)
	for spec in [["minus", "Zoom out (-)", func() -> void: view.zoom_center(1.0 / 1.25)], ["plus", "Zoom in (+)", func() -> void: view.zoom_center(1.25)], ["fit", "Show every table (0)", view.fit]]:
		var b := Ui.icon_button(spec[0], spec[1], spec[2])
		b.custom_minimum_size = Vector2(44, 44)
		zoom_box.add_child(b)
	_pin(zoom_box, Vector2(1, 1))
	view.add_child(zoom_box)

	# The toast hangs from a point above the zoom buttons and grows upwards, so a long message never
	# covers them.
	toast = Ui.label("", 14)
	toast.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.TOAST, 8, 12))
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.visible = false
	toast.anchor_left = 0.5
	toast.anchor_right = 0.5
	toast.anchor_top = 1.0
	toast.anchor_bottom = 1.0
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast.grow_vertical = Control.GROW_DIRECTION_BEGIN
	view.add_child(toast)
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(func() -> void: toast.visible = false)
	add_child(_toast_timer)


## Pins a control to a corner of the plan, INSET px in, at the size of its content (it grows away
## from the corner when its content grows). corner: (0 or 1, 0 or 1) for left/right and top/bottom.
static func _pin(control: Control, corner: Vector2) -> void:
	control.anchor_left = corner.x
	control.anchor_right = corner.x
	control.anchor_top = corner.y
	control.anchor_bottom = corner.y
	var inset := Vector2(INSET, INSET) * (Vector2.ONE - corner * 2.0)
	control.offset_left = inset.x
	control.offset_right = inset.x
	control.offset_top = inset.y
	control.offset_bottom = inset.y
	control.grow_horizontal = Control.GROW_DIRECTION_BEGIN if corner.x > 0.5 else Control.GROW_DIRECTION_END
	control.grow_vertical = Control.GROW_DIRECTION_BEGIN if corner.y > 0.5 else Control.GROW_DIRECTION_END


## Shows a short message for a few seconds, wrapped to the width of the plan when it is long.
func show_toast(text: String, seconds := 2.8) -> void:
	if text == "":
		return
	toast.text = text
	toast.autowrap_mode = TextServer.AUTOWRAP_OFF
	toast.custom_minimum_size = Vector2.ZERO
	var room := view.size.x - 24.0
	var width := minf(toast.get_minimum_size().x, room)
	if width >= room:
		toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		toast.custom_minimum_size = Vector2(room, 0)
	toast.offset_left = -width / 2.0
	toast.offset_right = width / 2.0
	var lift := INSET + zoom_box.get_combined_minimum_size().y + TOAST_GAP
	toast.offset_top = -lift
	toast.offset_bottom = -lift
	toast.visible = true
	_toast_timer.start(seconds)


## Shows how the plan stands in the badge, and returns it in a sentence for screen readers,
## e.g. "42 guests, 40 seated, 2 things to look at".
func update_status(plan: Seating) -> String:
	var wishes := plan.wish_problems()
	var waiting := plan.unseated().size()
	var good := wishes.is_empty() and waiting == 0 and not plan.guests.is_empty()
	var color := UiTheme.TOAST
	var text_color := UiTheme.TEXT
	if good:
		status.text = "Everyone seated, every wish kept"
		color = Color("173a2b")
		text_color = UiTheme.GOOD
	elif not wishes.is_empty():
		status.text = "%d %s to look at" % [wishes.size(), "thing" if wishes.size() == 1 else "things"]
		color = Color("4a1f22")
		text_color = Color("ffd2cf")
	else:
		status.text = "%d waiting for a seat" % waiting
	# Every state gets the same padding, so the badge never clips its text when pressed or hovered.
	for state in ["normal", "pressed", "hover_pressed"]:
		status.add_theme_stylebox_override(state, UiTheme.box(color, 16, 12))
	status.add_theme_stylebox_override("hover", UiTheme.box(color.lightened(0.06), 16, 12))
	status.add_theme_stylebox_override("focus", UiTheme.box(Color.TRANSPARENT, 16, 12, UiTheme.FOCUS))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		status.add_theme_color_override(state, text_color)
	status.reset_size()
	var standing := "every wish kept" if wishes.is_empty() else status.text
	return "%d guests, %d seated, %s" % [plan.guests.size(), plan.guests.size() - waiting, standing]


## Shows Seat everyone at work (progress from 0 to 1), or ready again with progress < 0.
func show_progress(progress: float) -> void:
	view.busy = progress >= 0.0
	seat_button.disabled = view.busy
	seat_button.text = "Seating… %d%%" % roundi(100.0 * progress) if view.busy else "Seat everyone"
