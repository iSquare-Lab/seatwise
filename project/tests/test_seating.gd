extends SceneTree
## The logic tests: the seating model, pasted lists, the solver, files, history, and the plan view's
## hit testing and name labels. No window needed.
## Run from the repository root: godot --headless --path project --script res://tests/test_seating.gd
## Exits with 1 when a check fails.

var failures := 0
var checks := 0


func _init() -> void:
	var tests: Array[Callable] = [
		test_tables, test_seats_and_households, test_problems, test_guest_limit,
		test_pasted_lists, test_quoted_csv_rows, test_csv_cells, test_example_wedding,
		test_seat_everyone, test_solver_steps, test_solver_edge_cases,
		test_files, test_broken_files, test_file_names, test_history, test_undo_limit,
		test_hit_testing, test_name_labels,
	]
	for test in tests:
		print(test.get_method())
		test.call()
	print("%d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(condition: bool, what: String) -> void:
	checks += 1
	if condition:
		print("  ok  ", what)
	else:
		failures += 1
		printerr("  FAIL ", what)


# ------------------------------------------------------------------ Helpers

func names(s: Seating, ids: Array) -> Array[String]:
	var out: Array[String] = []
	for id: int in ids:
		out.append(s.get_guest(id).name)
	return out


func same_table(s: Seating, a: int, b: int) -> bool:
	var x := s.seat_of(a)
	var y := s.seat_of(b)
	return not x.is_empty() and not y.is_empty() and x.table == y.table


func adjacent(s: Seating, a: int, b: int) -> bool:
	if not same_table(s, a, b):
		return false
	var t := s.get_table(s.seat_of(a).table)
	for pair in Seating.neighbours(t):
		var x: int = t.guests[pair.x]
		var y: int = t.guests[pair.y]
		if (x == a and y == b) or (x == b and y == a):
			return true
	return false


func kinds(s: Seating) -> Array:
	return s.problems().map(func(p: Dictionary) -> String: return p.kind)


func seated_example(seed_value: int = 7) -> Seating:
	var w := Seating.new()
	w.load_example()
	w.auto_seat(seed_value)
	return w


# ------------------------------------------------------------------ Model

func test_tables() -> void:
	var s := Seating.new()
	var round_table := s.get_table(s.add_table("round", 8, 0, 0))
	var seats := Seating.seat_positions(round_table)
	check(seats.size() == 8, "a round table for 8 has 8 seats")
	var radius := seats[0].length()
	var even := true
	for p in seats:
		even = even and absf(p.length() - radius) < 0.01
	check(even and radius > Seating.table_size(round_table).x / 2.0, "round seats sit evenly around the table, outside its edge")
	check(seats[0].distance_to(seats[1]) >= 50.0, "there is elbow room between round seats")
	check(Seating.neighbours(round_table).size() == 8, "round seats wrap around: 8 pairs of neighbours")
	var outward := Seating.seat_outward(round_table)
	var facing := true
	for i in seats.size():
		facing = facing and outward[i].is_equal_approx(seats[i].normalized())
	check(facing, "round seats face straight out from the table")
	var head := s.get_table(s.add_table("head", 5, 0, 0))
	check(Seating.neighbours(head).size() == 4 and Seating.seat_positions(head).size() == 5, "a head table is one row: 4 pairs for 5 seats")
	var long := s.get_table(s.add_table("rect", 10, 0, 0))
	var long_seats := Seating.seat_positions(long)
	check(long_seats.size() == 10, "a long table for 10 has 10 seats")
	var ends := 0
	for p in long_seats:
		if absf(p.y) < 0.01:
			ends += 1
	check(ends == 2, "a long table for 10 has a seat at each end")
	var long_out := Seating.seat_outward(long)
	check(long_out[0] == Vector2.UP and long_out[4] == Vector2.RIGHT and long_out[5] == Vector2.DOWN and long_out[9] == Vector2.LEFT, "long-table seats face away from their side")
	var small_ends := 0
	for p in Seating.seat_positions(s.get_table(s.add_table("rect", 6, 0, 0))):
		if absf(p.y) < 0.01:
			small_ends += 1
	check(small_ends == 0, "a small rectangular table has no end seats")
	check(s.capacity() == 8 + 5 + 10 + 6, "capacity counts every seat")
	long.rot = 90.0
	var turned := Seating.seat_positions(long)
	check(absf(turned[0].x - (-long_seats[0].y)) < 0.01 and absf(turned[0].y - long_seats[0].x) < 0.01, "turning a table turns its seats")
	check(Seating.seat_outward(long)[0].is_equal_approx(Vector2.RIGHT), "turning a table turns where its seats face")
	check(s.get_table(s.add_table("round", 99, 0, 0)).seats == Seating.MAX_SEATS, "tables have at most 24 seats")
	check(s.get_table(s.add_table("hexagon", 4, 0, 0)).shape == "round", "an unknown shape becomes round")


func test_seats_and_households() -> void:
	var e := Seating.new()
	var t1 := e.add_table("round", 4, 0, 0)
	var t2 := e.add_table("round", 4, 300, 0)
	var anna := e.add_guest("Anna Berg", "Family")
	var ben := e.add_guest("Ben Berg", "Family")
	var cleo := e.add_guest("Cleo Diaz", "Work")
	check(e.unseated().size() == 3, "new guests are unseated")
	e.seat(anna, t1, 0)
	check(e.seat_of(anna) == {"table": t1, "seat": 0}, "seating a guest")
	e.seat(ben, t1, 0)
	check(e.seat_of(ben).seat == 0 and e.seat_of(anna).is_empty(), "taking a seat from someone unseated leaves them without one")
	e.seat(anna, t2, 1)
	e.seat(anna, t1, 0)
	check(e.seat_of(anna).seat == 0 and e.seat_of(ben) == {"table": t2, "seat": 1}, "moving onto a taken seat swaps the two guests")
	e.join_party(anna, ben)
	check(e.party_members(e.get_guest(anna).party).size() == 2, "joining makes a household")
	e.leave_party(ben)
	check(e.party_members(e.get_guest(anna).party).size() == 1, "leaving a household")
	e.remove_guest(cleo)
	check(e.get_guest(cleo).is_empty() and e.get_table(t1).guests.count(cleo) == 0, "removing a guest frees their seat")
	e.set_seats(t1, 1)
	check(e.get_table(t1).guests == [anna], "fewer seats keep who was seated first")
	check(e.diet_counts().is_empty(), "no diets, no counts")
	e.seat(ben, t2, 0)
	e.get_guest(ben).locked = true
	e.clear_seats(true)
	check(e.seat_of(ben).table == t2 and e.seat_of(anna).is_empty(), "taking everyone off their seats keeps locked seats")


func test_problems() -> void:
	var e := Seating.new()
	var t1 := e.add_table("round", 4, 0, 0)
	var t2 := e.add_table("round", 4, 300, 0)
	var anna := e.add_guest("Anna Berg")
	var ben := e.add_guest("Ben Berg")
	var cleo := e.add_guest("Cleo Diaz")
	check(kinds(e) == [Seating.PROBLEM_WAITING], "guests without a seat, with seats free, are just waiting")
	check(e.wish_problems().is_empty(), "waiting guests are not a broken wish")
	e.seat(anna, t1, 0)
	e.seat(ben, t2, 0)
	e.seat(cleo, t1, 1)
	e.join_party(anna, ben)
	var split := e.problems().filter(func(p: Dictionary) -> bool: return p.kind == Seating.PROBLEM_SPLIT)
	check(split.size() == 1 and split[0].text == "Anna Berg and Ben Berg are split across 2 tables", "a split household is reported in words")
	e.leave_party(ben)
	e.set_apart(anna, cleo)
	var apart := e.wish_problems()
	check(apart.size() == 1 and apart[0].kind == Seating.PROBLEM_APART and apart[0].text == "Anna Berg and Cleo Diaz should not sit at Table 1 together", "people who should be apart are reported in words")
	e.set_apart(cleo, anna, false)
	check(e.problems().is_empty(), "removing the wish clears the problem")
	e.set_seats(t1, 1)
	e.set_seats(t2, 1)
	e.add_guest("Dan Eze")
	var no_room := e.wish_problems()
	check(no_room.size() == 1 and no_room[0].kind == Seating.PROBLEM_NO_ROOM and no_room[0].text.contains("no seat: add 2 more seats"), "too few seats are reported with how many are missing")


func test_guest_limit() -> void:
	var s := Seating.new()
	for i in Seating.MAX_GUESTS - 1:
		s.add_guest("Guest %d" % i)
	check(s.room_for_guests() == 1, "room is counted down to the limit")
	var couple := s.import_text("Tom & Lisa Meyer")
	check(couple.is_empty() and s.guests.size() == Seating.MAX_GUESTS - 1, "a couple that does not fit is not split: neither is added")
	var read := GuestImport.read(s, "Ann Lee\nBo Kim\nCy Ross")
	check(read.added.size() == 1 and read.full and s.guests.size() == Seating.MAX_GUESTS, "a long list stops at the limit and says so")
	check(s.add_guest("One too many") == 0 and s.guests.size() == Seating.MAX_GUESTS, "add_guest refuses guests past the limit")


func test_pasted_lists() -> void:
	var p := Seating.new()
	var added := p.import_text("Name,Group,Diet\nFamily:\nTom & Lisa Meyer\nAnna Berg, Friends, Vegetarian\n\n# a comment\nJo Kim +1\nSam and Alex\n\"Lee, Ann\"\tWork\tvegan\n")
	check(added.size() == 8, "a pasted list adds every guest, households included")
	check(names(p, added).slice(0, 3) == ["Tom Meyer", "Lisa Meyer", "Anna Berg"], "\"Tom & Lisa Meyer\" becomes two guests with the shared surname")
	check(p.get_guest(added[0]).party == p.get_guest(added[1]).party, "a couple on one line is one household")
	check(p.get_guest(added[0]).group == "Family" and p.get_guest(added[2]).group == "Friends", "\"Group:\" lines set the group; a group on the line wins")
	check(p.get_guest(added[2]).diet == "vegetarian", "diets are read and kept in lower case")
	check(p.get_guest(added[4]).name == "Guest of Jo Kim" and p.get_guest(added[4]).party == p.get_guest(added[3]).party, "\"+1\" adds a guest in the same household")
	check(names(p, added).slice(5, 7) == ["Sam", "Alex"], "\"Sam and Alex\" without a surname")
	check(p.get_guest(added[7]).name == "Lee, Ann" and p.get_guest(added[7]).group == "Work" and p.get_guest(added[7]).diet == "vegan", "tab-separated rows from a spreadsheet")
	check(p.diet_counts() == {"vegetarian": 1, "vegan": 1}, "diet counts across the event")
	check(Seating.sort_key("Lisa Meyer") < Seating.sort_key("Tom Meyer") and Seating.sort_key("Anna Berg") < Seating.sort_key("Lisa Meyer"), "lists sort by last name")
	check(p.import_text("\n  \n# only comments\nFamily:\n").is_empty(), "a list without names adds nobody")


func test_quoted_csv_rows() -> void:
	check(GuestImport.split_row("\"Lee, Ann\",Work,vegan") == ["Lee, Ann", "Work", "vegan"], "a quoted cell keeps its comma")
	check(GuestImport.split_row("\"Say \"\"Hi\"\" Jo\", Friends") == ["Say \"Hi\" Jo", "Friends"], "\"\" inside quotes is one quote")
	check(GuestImport.split_row("Anna Berg,  \"Old, friends\" ,") == ["Anna Berg", "Old, friends", ""], "spaces around a quoted cell are ignored")
	check(GuestImport.split_row("O\"Brien, Work") == ["O\"Brien", "Work"], "a quote inside a name stays")
	check(GuestImport.split_row("\"Lee, Ann\"\tWork, Sales\tvegan") == ["Lee, Ann", "Work, Sales", "vegan"], "tab-separated rows keep commas in cells")
	check(GuestImport.rows("\"Lee,\nAnn\",Work,vegan\nBo Kim") == PackedStringArray(["\"Lee, Ann\",Work,vegan", "Bo Kim"]), "a quoted cell with a line break keeps its row together")
	check(GuestImport.rows("\"Lee, Ann,Work\nBo Kim\nCy Ross") == PackedStringArray(["\"Lee, Ann,Work", "Bo Kim", "Cy Ross"]), "a quote that never closes does not swallow the lines below")
	check(GuestImport.rows("A\n\"B\n\nC\",x\nD").size() == 3, "a quoted cell may span blank lines")
	var multi := Seating.new()
	var multi_ids := multi.import_text("\"Lee,\nAnn\",Work,vegan\nBo Kim")
	check(multi_ids.size() == 2 and multi.get_guest(multi_ids[0]).name == "Lee, Ann" and multi.get_guest(multi_ids[0]).diet == "vegan", "a spreadsheet cell with a line break gives one guest, not two")
	var s := Seating.new()
	var ids := s.import_text("Name,Group,Diet\n\"Lee, Ann\",Work,vegan\n\"Okafor, Paul\",\"Family, mine\",\n")
	check(ids.size() == 2, "a CSV with quoted names adds one guest per row")
	var lee := s.get_guest(ids[0])
	check(lee.name == "Lee, Ann" and lee.group == "Work" and lee.diet == "vegan", "a quoted CSV row keeps the whole name, the group and the meal")
	check(s.get_guest(ids[1]).group == "Family, mine", "a quoted group keeps its comma")


func test_csv_cells() -> void:
	check(PlanFile.csv_cell("Anna Berg") == "Anna Berg", "plain cells stay as they are")
	check(PlanFile.csv_cell("a, b") == "\"a, b\"" and PlanFile.csv_cell("say \"hi\"") == "\"say \"\"hi\"\"\"", "cells with commas or quotes are quoted")
	check(PlanFile.csv_cell("=1+1") == "'=1+1" and PlanFile.csv_cell("@cmd") == "'@cmd" and PlanFile.csv_cell("-2") == "'-2", "formulas are written as text")
	check(PlanFile.csv_cell("=HYPERLINK(\"x\",\"y\")") == "\"'=HYPERLINK(\"\"x\"\",\"\"y\"\")\"", "a formula with quotes and commas is defanged, then quoted")
	check(PlanFile.csv_cell("+1, plus one") == "\"'+1, plus one\"", "a formula with a comma is defanged, then quoted")


func test_example_wedding() -> void:
	var w := Seating.new()
	w.load_example()
	check(w.guests.size() == 38 and w.tables.size() == 6 and w.capacity() >= 38, "the example has 38 guests at six tables with enough seats")
	var groups := {}
	for g in w.guests:
		groups[g.group] = groups.get(g.group, 0) + 1
	check(groups == {"Wedding party": 6, "Mara's family": 8, "Jonas's family": 8, "University friends": 7, "Work": 6, "Neighbours": 3}, "the example's groups come from its \"Group:\" lines")
	var nils_guest := w.find_guest("Guest of Nils Lindqvist")
	check(nils_guest != 0 and w.get_guest(nils_guest).party == w.get_guest(w.find_guest("Nils Lindqvist")).party, "\"Nils Lindqvist +1\" brings a guest in his household")
	check(w.get_guest(w.find_guest("Rosa García")).party == w.get_guest(w.find_guest("Luis García")).party, "\"Rosa & Luis García\" is a couple")
	check(w.diet_counts() == {"vegetarian": 3, "vegan": 1, "kids": 3, "gluten-free": 1}, "the example's meals")
	check(w.apart.size() == 2 and w.is_apart(w.find_guest("Ben Carter"), w.find_guest("Hanna Berg")), "the example keeps two pairs apart")
	var head: Dictionary = w.tables[0]
	check(head.guests[2] == w.find_guest("Mara Lindqvist") and head.guests[3] == w.find_guest("Jonas Lindqvist"), "the couple sits in the middle of the head table")
	check(w.get_guest(head.guests[2]).locked and w.get_guest(head.guests[3]).locked, "the couple's seats are locked")
	check(w.unseated().size() == 36, "everyone else waits for Seat everyone")


# ------------------------------------------------------------------ The solver

func test_seat_everyone() -> void:
	var w := Seating.new()
	w.load_example()
	var mara := w.find_guest("Mara Lindqvist")
	var mara_seat := w.seat_of(mara)
	var score := w.auto_seat(7)
	check(w.unseated().is_empty(), "seat everyone: nobody is left without a seat")
	check(w.problems().is_empty(), "seat everyone: no wish is broken (%s)" % ", ".join(w.problems().map(func(x: Dictionary) -> String: return x.text)))
	check(w.seat_of(mara) == mara_seat, "locked guests stay where they are")
	var couples_together := true
	var households := w.parties()
	for party: int in households:
		var members: Array = households[party]
		if members.size() == 2:
			couples_together = couples_together and adjacent(w, members[0], members[1])
	check(couples_together, "every couple sits side by side")
	check(not same_table(w, w.find_guest("Karl Lindqvist"), w.find_guest("Henrik Weber")), "the two fathers sit at different tables")
	var head_table: Dictionary = w.tables[0]
	var party_at_head := true
	for g in w.guests:
		if g.group == "Wedding party":
			party_at_head = party_at_head and w.seat_of(g.id).get("table", -1) == head_table.id
	check(party_at_head, "the whole wedding party sits at the head table")
	var groups_ok := 0
	for t in w.tables:
		var seen := {}
		for g: int in t.guests:
			if g != 0:
				seen[w.get_guest(g).group] = true
		if seen.size() <= 2:
			groups_ok += 1
	check(groups_ok >= w.tables.size() - 1, "tables mostly keep groups together (%d of %d tables have at most 2 groups)" % [groups_ok, w.tables.size()])
	check(is_equal_approx(score, SeatingSolver.score(w)), "the score returned is the plan's score")
	var again := Seating.new()
	again.load_example()
	check(is_equal_approx(again.auto_seat(7), score) and again.to_json() == w.to_json(), "the same seed gives the same seating")
	var seeds_ok := 0
	for seed_value in [1, 2, 3, 4, 5]:
		var other := seated_example(seed_value)
		if other.problems().is_empty():
			seeds_ok += 1
	check(seeds_ok == 5, "every seed seats the example without a broken wish (%d of 5)" % seeds_ok)


func test_solver_steps() -> void:
	var w := Seating.new()
	w.load_example()
	var solver := SeatingSolver.new(w, 7)
	check(solver.progress() == 0.0, "the solver starts at 0%")
	var calls := 0
	var last := -1.0
	var rising := true
	var everyone_after_first := false
	while solver.step():
		calls += 1
		if calls == 1:
			everyone_after_first = w.unseated().is_empty()
		rising = rising and solver.progress() > last
		last = solver.progress()
	check(everyone_after_first, "the first step seats everyone who waits, so the tables fill up at once")
	check(calls == SeatingSolver.ROUNDS + 1 and solver.progress() == 1.0, "one step to seat, one per round, then done at 100%")
	check(rising, "progress only goes up")
	check(not solver.step(), "a finished solver does nothing more")
	var batch := Seating.new()
	batch.load_example()
	batch.auto_seat(7)
	check(batch.to_json() == w.to_json(), "step by step (as the App runs it) gives the same plan as auto_seat")
	check(is_equal_approx(solver.temperature(0), SeatingSolver.START_TEMPERATURE) and solver.temperature(SeatingSolver.ROUNDS - 1) == 0.0, "the solver cools down to 0 in the last round")


func test_solver_edge_cases() -> void:
	var better := Seating.new()
	better.load_example()
	SeatingSolver.place_unseated(better)
	check(better.unseated().is_empty(), "placing seats everyone who waits when there is room")
	var greedy := SeatingSolver.score(better)
	var solver := SeatingSolver.new(better, 3)
	solver.anneal(4000, 0.0)
	check(SeatingSolver.score(better) <= greedy, "improving never makes it worse at temperature 0")
	var direct := Seating.new()
	direct.load_example()
	var anneal_first := SeatingSolver.new(direct, 2)
	anneal_first.anneal(100, 5.0)
	check(direct.unseated().is_empty(), "calling anneal() first still seats everyone who waits")
	var fresh := Seating.new()
	fresh.load_example()
	var then_step := SeatingSolver.new(fresh, 2)
	then_step.polish()
	while then_step.step():
		pass
	check(fresh.unseated().is_empty() and fresh.wish_problems().is_empty(), "polish() then step() runs the whole solver without skipping anyone")
	var tight := Seating.new()
	tight.add_table("round", 2, 0, 0)
	tight.add_table("round", 2, 200, 0)
	var x := tight.add_guest("X")
	var y := tight.add_guest("Y")
	tight.add_guest("Z")
	tight.join_party(x, y)
	tight.auto_seat(1)
	check(same_table(tight, x, y) and tight.unseated().is_empty(), "a household is kept together when it fits")
	var over := Seating.new()
	over.add_table("round", 2, 0, 0)
	for i in 3:
		over.add_guest("G%d" % i)
	over.auto_seat(1)
	check(over.unseated().size() == 1, "with too few seats, the rest wait unseated")
	var empty := Seating.new()
	check(empty.auto_seat(1) == 0.0 and empty.problems().is_empty(), "an empty plan is fine")
	var no_tables := Seating.new()
	no_tables.add_guest("A")
	no_tables.auto_seat(1)
	check(no_tables.unseated().size() == 1, "without tables nobody is seated, and nothing breaks")
	var locked := Seating.new()
	var t := locked.add_table("round", 4, 0, 0)
	var a := locked.add_guest("A")
	locked.seat(a, t, 3)
	locked.get_guest(a).locked = true
	locked.auto_seat(1)
	check(locked.seat_of(a) == {"table": t, "seat": 3}, "a locked guest alone is left alone")


# ------------------------------------------------------------------ Files and history

func test_files() -> void:
	var w := seated_example()
	var csv := w.to_csv()
	check(csv.begins_with("Name,Table,Seat,Group,Diet\n") and csv.split("\n", false).size() == w.guests.size() + 1, "the CSV has a header and one row per guest")
	var rows := w.seat_list()
	check(rows[0][0] == "Hanna Berg" and rows[0][1] != "", "the find-your-seat list is alphabetical by last name, with tables")
	var json := w.to_json()
	var copy := Seating.new()
	check(copy.from_json(json) == "" and copy.to_json() == json, "a plan saves and loads unchanged")
	check(copy.from_json("{\"app\":\"other\"}") != "" and copy.from_json("nope") != "" and copy.to_json() == json, "other files are refused and change nothing")
	var parsed := PlanFile.parse(json)
	check(parsed.error == "" and parsed.guests.size() == w.guests.size() and parsed.next_id > 0, "parse() gives clean data to apply")
	var applied := Seating.new()
	applied.apply(parsed)
	check(applied.to_json() == json, "applying parsed data gives the same plan")


func test_broken_files() -> void:
	var copy := Seating.new()
	var messy := "{\"app\":\"seatwise\",\"guests\":[{\"id\":5,\"name\":\"A\"},{\"id\":5,\"name\":\"B\"},{\"id\":6,\"name\":\"C\",\"party\":99}],\"tables\":[{\"id\":5,\"seats\":3,\"guests\":[5,5,77]}],\"apart\":[[5,5],[5,6]]}"
	check(copy.from_json(messy) == "" and copy.guests.size() == 2 and copy.get_guest(6).party == 6, "repeated or broken guests in a file are cleaned up")
	check(copy.tables[0].guests == [5, 0, 0] and copy.tables[0].id != 5 and copy.apart.size() == 1, "seats point only at real guests, ids are unique, broken wishes are dropped")
	check(copy.from_json("{\"app\":\"seatwise\",\"guests\":\"abc\",\"tables\":7,\"apart\":null}") == "" and copy.guests.is_empty() and copy.tables.is_empty(), "lists of the wrong type are read as empty")
	var big := {"app": "seatwise", "guests": []}
	for i in Seating.MAX_GUESTS + 20:
		big.guests.append({"id": i + 1, "name": "G%d" % i})
	check(copy.from_json(JSON.stringify(big)) == "" and copy.guests.size() == Seating.MAX_GUESTS, "a file with too many guests keeps the first 600")
	var id := copy.add_guest("x")
	check(id == 0, "and then no more can be added")
	var shapes := "{\"app\":\"seatwise\",\"tables\":[{\"id\":1,\"shape\":\"star\",\"seats\":99,\"rot\":-90,\"name\":\"\"}]}"
	check(copy.from_json(shapes) == "" and copy.tables[0].shape == "round" and copy.tables[0].seats == Seating.MAX_SEATS and copy.tables[0].rot == 270.0, "table shapes, seat counts and turns are kept in range")


func test_file_names() -> void:
	check(PlanFile.file_base("Wedding dinner (example)") == "wedding-dinner-example", "file names come from the event name")
	check(PlanFile.file_base("") == "seating", "an empty event name gives \"seating\"")
	var odd := PlanFile.file_base("Anna/Ben: \"party\"?")
	check(not odd.contains("/") and not odd.contains(":") and not odd.contains("\"") and not odd.contains("?") and not odd.contains(" "), "file names have no characters a file system refuses (%s)" % odd)


func test_history() -> void:
	var h := Seating.new()
	h.checkpoint()
	h.add_guest("A")
	check(h.undo() and h.guests.is_empty() and h.redo() and h.guests.size() == 1, "undo and redo")
	h.checkpoint()
	h.drop_checkpoint_if_unchanged()
	check(h.can_undo() and h.undo() and h.guests.is_empty() and not h.can_undo(), "an unchanged step leaves no extra undo")
	h.redo()
	h.checkpoint()
	h.add_guest("B")
	h.discard_to_checkpoint()
	check(h.guests.size() == 1 and not h.can_redo(), "a cancelled drag goes back without a redo step")
	h.checkpoint()
	h.add_guest("C")
	h.undo()
	h.checkpoint()
	check(not h.can_redo(), "a new change clears redo")


func test_undo_limit() -> void:
	var h := Seating.new()
	for i in Seating.MAX_UNDO + 15:
		h.checkpoint()
		h.add_guest("G%d" % i)
	var undone := 0
	while h.undo():
		undone += 1
	check(undone == Seating.MAX_UNDO, "undo keeps the last %d steps (undid %d)" % [Seating.MAX_UNDO, undone])
	check(h.guests.size() == 15, "the oldest steps are the ones forgotten")


# ------------------------------------------------------------------ The plan view

func make_view(plan: Seating, view_size: Vector2) -> VenueView:
	var view := VenueView.new()
	view.seating = plan
	view.size = view_size
	view.refresh()
	view.fit()
	return view


func test_hit_testing() -> void:
	var w := seated_example()
	var view := make_view(w, Vector2(1200, 800))
	var all_seats := true
	for t in w.tables:
		var seats := Seating.seat_positions(t)
		for i in seats.size():
			all_seats = all_seats and view.seat_at(view.to_screen(seats[i])) == Vector2i(t.id, i)
	check(all_seats, "seat_at finds every seat at its centre")
	var round_table: Dictionary = w.tables[1]
	var first := Seating.seat_positions(round_table)[0]
	var near := view.to_screen(first + Vector2(VenueView.SEAT_RADIUS * 0.9, 0))
	check(view.seat_at(near) == Vector2i(round_table.id, 0), "seat_at forgives a tap near the edge of a seat")
	var centre := view.to_screen(Vector2(round_table.x, round_table.y))
	check(view.seat_at(centre) == Vector2i(-1, -1) and view.table_at(centre) == round_table.id, "the middle of a table is the table, not a seat")
	var floor_point := view.to_screen(view.content_rect().position + Vector2(5, 5))
	check(view.seat_at(floor_point) == Vector2i(-1, -1) and view.table_at(floor_point) == -1, "the empty floor is neither")
	var long: Dictionary = w.tables[4]
	long.rot = 90.0
	var along := view.to_screen(Vector2(long.x, long.y + Seating.table_size(long).x * 0.4))
	var across := view.to_screen(Vector2(long.x + Seating.table_size(long).x * 0.4, long.y))
	check(view.table_at(along) == long.id and view.table_at(across) != long.id, "a turned table is hit where it now stands")
	view.view_scale = 0.2
	view.offset = Vector2.ZERO
	var small := Seating.seat_positions(round_table)[0]
	var finger := view.to_screen(small) + Vector2(0, -12)
	check(view.seat_at(finger) == Vector2i(round_table.id, 0), "when seats are small on screen, a finger nearby still hits one")
	view.zoom_at(Vector2(100, 100), 99.0)
	check(view.view_scale == VenueView.MAX_SCALE, "zoom stops at the largest scale")
	view.zoom_at(Vector2(100, 100), 0.0)
	check(view.view_scale == VenueView.MIN_SCALE, "zoom stops at the smallest scale")
	view.free()


func labels_overlap(labels: Array[Dictionary]) -> int:
	var count := 0
	for i in labels.size():
		for j in range(i + 1, labels.size()):
			if (labels[i].rect as Rect2).intersects(labels[j].rect):
				count += 1
	return count


func labels_on_seats(view: VenueView, plan: Seating, labels: Array[Dictionary]) -> int:
	var count := 0
	var r := VenueView.SEAT_RADIUS * view.view_scale
	for t in plan.tables:
		for p in Seating.seat_positions(t):
			for label in labels:
				if LabelLayout.rect_hits_circle(label.rect, view.to_screen(p), r):
					count += 1
	return count


func test_name_labels() -> void:
	check(LabelLayout.rect_hits_circle(Rect2(0, 0, 10, 10), Vector2(12, 5), 3.0) and not LabelLayout.rect_hits_circle(Rect2(0, 0, 10, 10), Vector2(14, 14), 3.0), "rect_hits_circle")
	var items: Array[Dictionary] = []
	for i in 5:
		items.append({"anchor": Vector2(100 + i * 20, 100), "radius": 8.0, "dir": Vector2.DOWN, "size": Vector2(40, 14)})
	var rects := LabelLayout.place(items, PackedVector3Array(), [], 2.0)
	var shown := rects.filter(func(r: Rect2) -> bool: return r.has_area())
	var clear := true
	for i in shown.size():
		for j in range(i + 1, shown.size()):
			clear = clear and not (shown[i] as Rect2).intersects(shown[j])
	check(clear and shown.size() >= 3, "names of close seats step outwards instead of piling up (%d of 5 shown)" % shown.size())
	check(rects[0].position.y >= 100 + 8 + 2, "a name starts below its seat when the seat faces down")
	var w := seated_example()
	for view_size in [Vector2(1440, 860), Vector2(1000, 700)]:
		var view := make_view(w, view_size)
		var labels := view.name_labels()
		check(labels.size() >= 30, "at %s, most names are shown (%d of %d)" % [view_size, labels.size(), w.guests.size()])
		check(labels_overlap(labels) == 0, "at %s, no two names overlap" % view_size)
		check(labels_on_seats(view, w, labels) == 0, "at %s, no name covers a seat" % view_size)
		view.free()
	var phone := make_view(w, Vector2(374, 420))
	var small := phone.name_labels()
	check(labels_overlap(small) == 0 and labels_on_seats(phone, w, small) == 0, "on a phone, the names shown do not overlap (%d shown)" % small.size())
	var chosen := w.find_guest("Amira Haddad")
	phone.zoom_center(3.0)
	phone.select_guest(chosen)
	phone.show_guest(chosen)
	var picked := phone.name_labels()
	check(not picked.is_empty() and picked[0].text == "Amira Haddad", "the selected guest gets their full name first")
	phone.free()
	var cached := make_view(w, Vector2(1000, 700))
	var first := cached.name_labels()
	check(is_same(first, cached.name_labels()), "names are placed once and kept while nothing changes")
	cached.zoom_center(1.1)
	check(not is_same(first, cached.name_labels()), "zooming places them again")
	var before_refresh := cached.name_labels()
	cached.refresh()
	check(not is_same(before_refresh, cached.name_labels()), "a changed plan places them again")
	cached.zoom_center(3.0)
	var close_up := cached.name_labels()
	var near := Rect2(Vector2.ZERO, cached.size).grow(VenueView.SEAT_RADIUS * cached.view_scale * 6.0)
	check(close_up.size() < w.guests.size() and close_up.all(func(l: Dictionary) -> bool: return near.intersects(l.rect)), "zoomed in, only the names near the view are placed (%d)" % close_up.size())
	cached.free()
	check(VenueView.label_text({"name": "Mara Lindqvist"}, false, false) == "Mara" and VenueView.label_text({"name": "Mara Lindqvist"}, false, true) == "Mara L." and VenueView.label_text({"name": "Guest of Nils Lindqvist"}, false, false) == "Guest", "name labels: first name, \"First L.\" on the printed chart, \"Guest\" for a +1")
