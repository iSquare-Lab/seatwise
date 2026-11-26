class_name PlanFile
extends RefCounted
## Plans as files: the .seatwise.json format (saved in the browser and downloaded), the guest list as
## CSV, and file names. Reading a file never trusts it: ids, seats and wishes are checked and cleaned.

const APP_ID := "seatwise"
const FORMAT_VERSION := 1


static func to_dict(plan: Seating) -> Dictionary:
	var pairs: Array = []
	for p in plan.apart:
		pairs.append([p.x, p.y])
	return {"app": APP_ID, "version": FORMAT_VERSION, "title": plan.title, "tables": plan.tables.duplicate(true), "guests": plan.guests.duplicate(true), "apart": pairs}


static func to_json(plan: Seating) -> String:
	return JSON.stringify(to_dict(plan), "  ")


## Reads a saved plan. Returns {"error": ""} plus clean "title", "tables", "guests", "apart" and
## "next_id" for Seating.apply(), or {"error": why it could not}.
static func parse(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK or not (parser.data is Dictionary) or parser.data.get("app", "") != APP_ID:
		return {"error": "This is not a Seatwise plan."}
	var data: Dictionary = parser.data
	var new_tables: Array[Dictionary] = []
	var new_guests: Array[Dictionary] = []
	var top := 0
	var guest_ids := {}
	for raw: Variant in _list(data, "guests"):
		if raw is Dictionary and guest_ids.size() < Seating.MAX_GUESTS:
			var g := {
				"id": int(raw.get("id", 0)), "name": str(raw.get("name", "Guest")).left(60), "group": str(raw.get("group", "")).left(40),
				"diet": str(raw.get("diet", "")).left(30), "party": int(raw.get("party", 0)), "locked": bool(raw.get("locked", false)),
			}
			if g.id <= 0 or guest_ids.has(g.id):
				continue
			guest_ids[g.id] = true
			new_guests.append(g)
			top = maxi(top, g.id)
	for g in new_guests:
		if not guest_ids.has(g.party):
			g.party = g.id
	var seated := {}
	for raw: Variant in _list(data, "tables"):
		if not (raw is Dictionary):
			continue
		var t := {
			"id": int(raw.get("id", 0)), "shape": str(raw.get("shape", "round")), "seats": clampi(int(raw.get("seats", 8)), 1, Seating.MAX_SEATS),
			"x": float(raw.get("x", 0)), "y": float(raw.get("y", 0)), "rot": fposmod(float(raw.get("rot", 0)), 360.0),
			"name": str(raw.get("name", "Table")).left(40), "guests": [],
		}
		if not (t.shape in Seating.SHAPES):
			t.shape = "round"
		var list: Array = raw.get("guests") if raw.get("guests") is Array else []
		for i in t.seats:
			var g := int(list[i]) if i < list.size() else 0
			if g != 0 and (not guest_ids.has(g) or seated.has(g)):
				g = 0
			if g != 0:
				seated[g] = true
			t.guests.append(g)
		new_tables.append(t)
		top = maxi(top, t.id)
	var new_apart: Array[Vector2i] = []
	for raw: Variant in _list(data, "apart"):
		if raw is Array and raw.size() == 2 and guest_ids.has(int(raw[0])) and guest_ids.has(int(raw[1])) and int(raw[0]) != int(raw[1]):
			new_apart.append(Vector2i(mini(int(raw[0]), int(raw[1])), maxi(int(raw[0]), int(raw[1]))))
	var title := str(data.get("title", "Our event")).strip_edges().left(60)
	var next_id := top + 1
	# Table ids must be unique and must not clash with guest ids.
	var seen := {}
	for t in new_tables:
		if seen.has(t.id) or t.id <= 0 or guest_ids.has(t.id):
			t.id = next_id
			next_id += 1
		seen[t.id] = true
	return {
		"error": "", "title": title if title != "" else "Our event", "tables": new_tables, "guests": new_guests,
		"apart": new_apart, "next_id": next_id,
	}


static func _list(data: Dictionary, key: String) -> Array:
	return data.get(key) if data.get(key) is Array else []


## A CSV cell. Text a spreadsheet would run as a formula (starting with = + - @) gets a ' first, and
## a cell with a comma, a quote or a line break is quoted.
static func csv_cell(value: String) -> String:
	if value.length() > 0 and value[0] in ["=", "+", "-", "@"]:
		value = "'" + value
	if value.contains(",") or value.contains("\"") or value.contains("\n"):
		return "\"" + value.replace("\"", "\"\"") + "\""
	return value


## The guest list with tables and seats, sorted by last name.
static func to_csv(plan: Seating) -> String:
	var lines: Array[String] = ["Name,Table,Seat,Group,Diet"]
	for row in plan.seat_list():
		var cells: Array[String] = []
		for c in row:
			cells.append(csv_cell(c))
		lines.append(",".join(cells))
	return "\n".join(lines) + "\n"


## A file name from the event name: "Wedding dinner (example)" -> "wedding-dinner-example".
static func file_base(title: String) -> String:
	var base := title.to_lower().validate_filename().replace(" ", "-").replace("(", "").replace(")", "")
	return base if base != "" else "seating"
