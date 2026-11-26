class_name SidePanel
extends VBoxContainer
## The side panel: three tabs (Guests, Tables, Selected) over a scrolling page. Beside the plan on
## wide screens, below it on phones.

## Room kept free at the bottom of the pages, so the last rows can scroll clear of the host's round
## return button in the bottom-right corner of the page (64 units are about 52 CSS px on a phone).
const CORNER_CLEARANCE := 64

var guests: GuestPage
var tables: TablePage
var inspector: Inspector
var scroll: ScrollContainer
var _tabs := {}
var _pages := {}


func _init(plan: Seating, view: VenueView) -> void:
	add_theme_constant_override("separation", 8)
	guests = GuestPage.new(plan, view)
	tables = TablePage.new(plan, view)
	inspector = Inspector.new(plan, view)
	_pages = {"guests": guests, "tables": tables, "piece": inspector}
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 4)
	add_child(tab_row)
	for spec in [["guests", "Guests"], ["tables", "Tables"], ["piece", "Selected"]]:
		var page_id: String = spec[0]
		var tab := Ui.button(spec[1], func() -> void: show_page(page_id))
		tab.toggle_mode = true
		tab.custom_minimum_size = Vector2(0, 42)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_row.add_child(tab)
		_tabs[page_id] = tab
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var padding := MarginContainer.new()
	padding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	padding.add_theme_constant_override("margin_bottom", CORNER_CLEARANCE)
	scroll.add_child(padding)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	padding.add_child(stack)
	for key: String in _pages:
		stack.add_child(_pages[key])


## Shows a page: "guests", "tables" or "piece" (the selected guest or table).
func show_page(page: String) -> void:
	for key: String in _pages:
		(_pages[key] as Control).visible = key == page
	for key: String in _tabs:
		(_tabs[key] as Button).set_pressed_no_signal(key == page)
	scroll.scroll_vertical = 0


func refresh() -> void:
	guests.refresh()
	tables.refresh()
	inspector.refresh()


## Beside the plan (wide), or below it with a fixed height for its list on a phone.
func set_wide(wide: bool, window_height: float) -> void:
	custom_minimum_size = Vector2(330, 0) if wide else Vector2.ZERO
	size_flags_vertical = Control.SIZE_EXPAND_FILL if wide else Control.SIZE_FILL
	scroll.custom_minimum_size = Vector2.ZERO if wide else Vector2(0, clampf(window_height * 0.36, 230.0, 400.0))
