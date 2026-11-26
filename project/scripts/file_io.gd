class_name FileIO
extends RefCounted
## Files and the browser: the plan kept in user:// (IndexedDB in the browser), downloads, opening a
## file (the browser's file picker, or a file dropped on the window), reading the clipboard, and the
## short summary screen readers hear. The browser side is window.seatwise in shell.html.

signal file_opened(text: String, file_name: String)
## Something went wrong; the message is ready to show.
signal failed(message: String)

const PLAN_PATH := "user://seatwise.json"
const MAX_FILE_BYTES := 2 * 1024 * 1024

## Where the plan is kept (the tests point it elsewhere).
var plan_path := PLAN_PATH
var _js: JavaScriptObject
var _open_callback: JavaScriptObject
var _clipboard_callback: JavaScriptObject
var _clipboard_done := Callable()
var _announced := ""


func _init() -> void:
	if OS.has_feature("web"):
		_js = JavaScriptBridge.get_interface("seatwise")


## True when the page offers the browser helpers (the file picker and the clipboard).
func has_browser() -> bool:
	return _js != null


# ------------------------------------------------------------------ The saved plan

## The plan saved last time: {"found": false} on a first visit, else {"found": true, "text": String}.
func load_plan() -> Dictionary:
	if not FileAccess.file_exists(plan_path):
		return {"found": false}
	return {"found": true, "text": FileAccess.get_file_as_string(plan_path)}


## Saves the plan. False when the browser does not let it (a private window, storage full).
func save_plan(text: String) -> bool:
	var file := FileAccess.open(plan_path, FileAccess.WRITE)
	if file == null:
		return false
	var ok := file.store_string(text)
	file.close()
	return ok


# ------------------------------------------------------------------ Files in and out

## Downloads a file (in the browser) or saves it under user://exports. Returns what to tell the user.
func download(bytes: PackedByteArray, file_name: String, mime: String) -> String:
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(bytes, file_name, mime)
		return "Downloaded %s" % file_name
	DirAccess.make_dir_recursive_absolute("user://exports")
	var path := "user://exports/" + file_name
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		return "Could not save %s" % file_name
	var ok := out.store_buffer(bytes)
	out.close()
	return ("Saved " + ProjectSettings.globalize_path(path)) if ok else "Could not save %s" % file_name


## Opens the browser's file picker; the file arrives through file_opened (or failed).
func pick_file() -> void:
	if _js == null:
		failed.emit("Drop a .seatwise.json plan or a .csv guest list onto the window")
		return
	if _open_callback == null:
		_open_callback = JavaScriptBridge.create_callback(_on_picked)
	_js.openFile(_open_callback, MAX_FILE_BYTES)


func _on_picked(args: Array) -> void:
	var problem: String = str(args[2]) if args.size() > 2 else ""
	if problem == "too-big":
		failed.emit("That file is too big for a guest list")
	elif problem != "":
		failed.emit("The browser could not read that file")
	else:
		file_opened.emit(str(args[0]), str(args[1]))


## Reads a file dropped on the window, with the same size limit as the file picker.
func read_dropped(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		failed.emit("Could not read %s" % path.get_file())
	elif file.get_length() > MAX_FILE_BYTES:
		failed.emit("That file is too big for a guest list")
	else:
		file_opened.emit(file.get_as_text(), path.get_file())


# ------------------------------------------------------------------ The page around the App

## Reads text from the clipboard (the browser may ask first). done gets the text.
func read_clipboard(done: Callable) -> void:
	if _js == null:
		return
	_clipboard_done = done
	if _clipboard_callback == null:
		_clipboard_callback = JavaScriptBridge.create_callback(_on_clipboard)
	_js.readClipboard(_clipboard_callback)


func _on_clipboard(args: Array) -> void:
	var problem: String = str(args[1]) if args.size() > 1 else ""
	if problem != "":
		failed.emit("The browser did not let Seatwise read the clipboard. Paste into the box instead.")
	elif _clipboard_done.is_valid():
		_clipboard_done.call(str(args[0]))


## Updates the short summary screen readers hear (the plan itself is a picture to them).
func announce(text: String) -> void:
	if _js != null and text != _announced:
		_announced = text
		_js.announce(text)
