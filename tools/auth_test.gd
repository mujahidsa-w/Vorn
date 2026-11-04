extends Node
## Simulates the browser: GET /login, then POST /token with fake tokens.
func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	Online.sign_out()
	Online.signed_in.connect(func(): print("SIGNED_IN name=", Online.display_name, " uid=", Online.uid, " guest=", Online.guest))
	Online.auth_failed.connect(func(m): print("FAILED ", m))
	Online.sign_in_google()
	print("waiting=", Online.google_waiting(), " url=", Online.login_url())
	var url := Online.login_url()
	var t0 := Thread.new()
	t0.start(func(): var o := []; OS.execute("curl", ["-s", "-m", "10", "--noproxy", "*", url], o); return o[0])
	while t0.is_alive():
		await get_tree().process_frame
	var page: String = t0.wait_to_finish()
	print("page bytes=", page.length(), " has_cfg=", page.contains("ms-company-e7166.firebaseapp.com"), " placeholder_left=", page.contains("__CFG__"))
	var body := JSON.stringify({"uid": "TESTUID123", "idToken": "x", "refreshToken": "r-token", "name": "Mujahid Test", "email": "a@b.c"})
	var bf := FileAccess.open("user://body.json", FileAccess.WRITE); bf.store_string(body); bf.close()
	var bpath := "@" + ProjectSettings.globalize_path("user://body.json")
	var t := Thread.new()
	t.start(func(): var o := []; OS.execute("curl", ["-sS", "-m", "10", "--noproxy", "*", "-X", "POST", "-H", "Content-Type: application/json", "-d", bpath, "http://localhost:%d/token" % Online._port], o, true); return o[0])
	while t.is_alive():
		await get_tree().process_frame
	print("post reply=", t.wait_to_finish())
	await get_tree().create_timer(1.5).timeout
	print("server closed=", not Online.google_waiting(), " saved=", FileAccess.file_exists("user://auth.cfg"))
	Online.sign_out()
	get_tree().quit()
