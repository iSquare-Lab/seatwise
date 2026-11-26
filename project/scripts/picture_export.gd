class_name PictureExport
extends RefCounted
## The downloadable pictures: the seating chart (the plan drawn on white) and the alphabetical
## "find your seat" list for the entrance. Each is drawn once in an off-screen viewport and saved as PNG.

const INK := Color("2b2721")
const SUBTLE := Color("6b6355")
const LINK := Color("3f6df2")


## The seating chart as PNG bytes. host is any node in the tree (the viewport is added under it).
static func chart(host: Node, plan: Seating) -> PackedByteArray:
	var area := VenueView.plan_rect(plan)
	var scale := clampf(2200.0 / maxf(area.size.x, area.size.y), 0.6, 1.6)
	var header := 130.0
	var size_px := Vector2i(Vector2(area.size.x * scale + 80.0, area.size.y * scale + header + 40.0))
	var seated := plan.guests.size() - plan.unseated().size()
	var image: Image = await _render(host, size_px, func(frame: Control) -> void:
		_header(frame, plan.title, "%d guests at %d tables" % [seated, plan.tables.size()])
		var picture := VenueView.new()
		picture.export_mode = true
		picture.text_scale = 1.5
		picture.seating = plan
		picture.position = Vector2(40, header)
		picture.size = Vector2(size_px) - Vector2(80, header + 40.0)
		frame.add_child(picture)
		picture.refresh()
		picture.fit())
	return image.save_png_to_buffer()


## The "find your seat" list in up to three columns, sorted by last name, as PNG bytes.
static func seat_list(host: Node, plan: Seating) -> PackedByteArray:
	var rows := plan.seat_list()
	var columns := 1 if rows.size() <= 25 else (2 if rows.size() <= 70 else 3)
	var per_column := maxi(1, ceili(rows.size() / float(columns)))
	var line := 40.0
	var header := 150.0
	var size_px := Vector2i(int(560 * columns + 80), int(header + per_column * line + 60))
	var image: Image = await _render(host, size_px, func(frame: Control) -> void:
		_header(frame, plan.title, "Find your seat")
		for i in rows.size():
			@warning_ignore("integer_division")
			var col := i / per_column
			var row := i % per_column
			var top := header + row * line
			frame.add_child(_cell(rows[i][0], Vector2(48 + col * 560, top), 360.0, INK))
			frame.add_child(_cell(rows[i][1] if rows[i][1] != "" else "-", Vector2(48 + col * 560 + 370, top), 160.0, LINK)))
	return image.save_png_to_buffer()


static func _cell(text: String, at: Vector2, width: float, color: Color) -> Label:
	var cell := Label.new()
	cell.text = text
	cell.position = at
	cell.size = Vector2(width, 40.0)
	cell.clip_text = true
	cell.add_theme_font_size_override("font_size", 24)
	cell.add_theme_color_override("font_color", color)
	return cell


static func _header(frame: Control, title: String, subtitle: String) -> void:
	var big := Label.new()
	big.text = title
	big.position = Vector2(48, 26)
	big.add_theme_font_size_override("font_size", 40)
	big.add_theme_color_override("font_color", INK)
	frame.add_child(big)
	var sub := Label.new()
	sub.text = subtitle
	sub.position = Vector2(50, 80)
	sub.add_theme_font_size_override("font_size", 22)
	sub.add_theme_color_override("font_color", SUBTLE)
	frame.add_child(sub)


## Draws what build adds to a white frame, once, and returns the picture.
static func _render(host: Node, viewport_size: Vector2i, build: Callable) -> Image:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	var frame := Control.new()
	frame.size = Vector2(viewport_size)
	frame.theme = host.get_tree().root.theme
	var white := ColorRect.new()
	white.color = Color.WHITE
	white.size = Vector2(viewport_size)
	frame.add_child(white)
	viewport.add_child(frame)
	build.call(frame)
	host.add_child(viewport)
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	return image
