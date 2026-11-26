class_name UiTheme
extends RefCounted
## The look of the editor: colours, rounded boxes, the theme, and the icons (res://icons/*.svg,
## imported at twice their size so they stay sharp on high-density screens).

const BG := Color("13161d")
const PANEL := Color("1b1f28")
const BUTTON := Color("262b37")
const BUTTON_HOVER := Color("313848")
const ON := Color("2f4378")
const ACCENT := Color("3f6df2")
const TEXT := Color("eef0f6")
const MUTED := Color("9aa3b5")
const GOOD := Color("5fd39a")
const BAD := Color("ff7a73")
const FOCUS := Color("ffd166")
const FIELD := Color("0f1217")
const FIELD_LINE := Color("323846")
const TOAST := Color("2c3140")
const FRAME_LINE := Color("232836")

static var _dots := {}


## A rounded box. margin is the side padding; top and bottom get 70% of it.
static func box(color: Color, radius: int = 10, margin: int = 10, border: Color = Color.TRANSPARENT, border_width: int = 2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin * 0.7
	style.content_margin_bottom = margin * 0.7
	if border.a > 0.0:
		style.set_border_width_all(border_width)
		style.border_color = border
	style.anti_aliasing = true
	return style


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16
	for type in ["Label", "Button", "MenuButton", "LineEdit", "TextEdit", "PopupMenu"]:
		t.set_color("font_color", type, TEXT)
	for type in ["Button", "MenuButton"]:
		t.set_color("font_hover_color", type, TEXT)
		t.set_color("font_pressed_color", type, TEXT)
		t.set_color("font_focus_color", type, TEXT)
		t.set_color("font_hover_pressed_color", type, TEXT)
		t.set_color("font_disabled_color", type, Color(MUTED, 0.5))
		t.set_color("icon_disabled_color", type, Color(1, 1, 1, 0.3))
		t.set_stylebox("normal", type, box(BUTTON))
		t.set_stylebox("hover", type, box(BUTTON_HOVER))
		t.set_stylebox("pressed", type, box(ON))
		t.set_stylebox("hover_pressed", type, box(ON.lightened(0.08)))
		t.set_stylebox("disabled", type, box(Color(BUTTON, 0.5)))
		t.set_stylebox("focus", type, box(Color.TRANSPARENT, 10, 10, FOCUS))
		t.set_constant("icon_max_width", type, 22)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 16, 18))
	t.set_stylebox("panel", "PopupMenu", box(PANEL, 10, 8, BUTTON, 1))
	t.set_stylebox("hover", "PopupMenu", box(BUTTON_HOVER, 6))
	t.set_color("font_hover_color", "PopupMenu", TEXT)
	t.set_color("font_separator_color", "PopupMenu", MUTED)
	# Menu rows at least 40 px high, for fingers.
	t.set_constant("v_separation", "PopupMenu", 18)
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, box(FIELD, 8, 10, FIELD_LINE, 1))
		t.set_stylebox("focus", type, box(FIELD, 8, 10, FOCUS))
		t.set_color("caret_color", type, TEXT)
		t.set_color("font_placeholder_color", type, Color(MUTED, 0.7))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_stylebox("panel", "TooltipPanel", box(TOAST, 6, 8))
	t.set_font_size("font_size", "TooltipLabel", 14)
	return t


## One of the line icons in res://icons (undo, redo, menu, fit, plus, minus, turn, spark).
static func icon(name: String) -> Texture2D:
	return load("res://icons/%s.svg" % name) as Texture2D


## A soft round dot, used as the colour mark of list rows.
static func dot(color: Color) -> Texture2D:
	var key := color.to_html()
	if _dots.has(key):
		return _dots[key]
	var image := Image.create_empty(28, 28, false, Image.FORMAT_RGBA8)
	for y in 28:
		for x in 28:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(14, 14))
			image.set_pixel(x, y, Color(color, clampf(13.5 - d, 0.0, 1.0)))
	_dots[key] = ImageTexture.create_from_image(image)
	return _dots[key]
