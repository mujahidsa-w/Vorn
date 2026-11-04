extends Control
## In-game smartphone: wallet transfers, contacts and Vorn Market access.

const UI = preload("res://scripts/ui/ui.gd")

var hud
var panel: Control
var body: Control
var title: Label
var status := ""
var status_col := Game.C_DIM
var amount_input: LineEdit
var recipient_input: LineEdit
var phone_open := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build_phone()

func _build_phone() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.02, 0.48)
	Game.lay(shade, [0, 0, 1, 1], [0, 0, 0, 0])
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	panel = Control.new()
	Game.lay(panel, [1, 0, 1, 0], [-540, 74, -55, 1000])
	add_child(panel)
	var frame := UI.paint(panel, _draw_frame, Rect2(0, 0, 0, 0), true)
	Game.lay(frame, [0, 0, 1, 1], [0, 0, 0, 0])
	var close := UI.button(panel, "×", "", 30, Rect2(430, 18, 62, 52), toggle, Game.C_RED)
	close.set("centered", true)
	title = Game.label("VORN PHONE", 30, Game.font_wide, Color.WHITE)
	UI.rect(title, 30, 26, 360, 45)
	panel.add_child(title)
	var tabs := [["WALLET", "wallet"], ["CONTACTS", "contacts"], ["MARKET", "market"]]
	for i in tabs.size():
		var b := UI.button(panel, tabs[i][0], "", 16, Rect2(24 + i * 154, 92, 142, 44), _show_app.bind(tabs[i][1]), Game.C_CYAN)
		b.set("centered", true)
	body = Control.new()
	UI.rect(body, 24, 154, 444, 770)
	panel.add_child(body)
	_show_app("wallet")

func _draw_frame(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(r, Color(0.015, 0.025, 0.065, 0.98))
	c.draw_rect(r, Color(Game.C_CYAN, 0.72), false, 2.0)
	c.draw_line(Vector2(24, 78), Vector2(r.size.x - 24, 78), Color(1, 1, 1, 0.12), 1.0)
	c.draw_circle(Vector2(r.size.x * 0.5, 32), 4, Game.C_GREEN)

func _show_app(app: String) -> void:
	for child in body.get_children():
		child.queue_free()
	status = ""
	match app:
		"wallet": _wallet_app()
		"contacts": _contacts_app()
		"market": _market_app()

func _wallet_app() -> void:
	var h := Game.label("VORN WALLET", 25, Game.font_wide, Color.WHITE)
	UI.rect(h, 12, 12, 400, 40)
	body.add_child(h)
	var balance := Game.label("BANK  $" + Game.fmt(int(Game.player.get("bank", 0))), 30, Game.font_semi, Game.C_GOLD)
	UI.rect(balance, 12, 62, 400, 48)
	body.add_child(balance)
	var cash := Game.label("CASH  $" + Game.fmt(int(Game.player.get("coins", 0))), 18, Game.font_tag, Game.C_DIM)
	UI.rect(cash, 12, 108, 400, 30)
	body.add_child(cash)
	var dep := UI.button(body, "DEPOSIT $500", "plus", 18, Rect2(12, 160, 190, 52), _deposit, Game.C_GREEN)
	dep.set("centered", true)
	var wit := UI.button(body, "WITHDRAW $500", "back", 18, Rect2(218, 160, 190, 52), _withdraw, Game.C_GOLD)
	wit.set("centered", true)
	var recipient := Game.label("RECIPIENT", 15, Game.font_tag, Game.C_DIM)
	UI.rect(recipient, 12, 250, 390, 25)
	body.add_child(recipient)
	recipient_input = LineEdit.new()
	recipient_input.placeholder_text = "Friend name or code"
	recipient_input.add_theme_font_size_override("font_size", 19)
	Game.lay(recipient_input, [0, 0, 0, 0], [12, 278, 408, 326])
	body.add_child(recipient_input)
	var amount := Game.label("AMOUNT", 15, Game.font_tag, Game.C_DIM)
	UI.rect(amount, 12, 342, 390, 25)
	body.add_child(amount)
	amount_input = LineEdit.new()
	amount_input.placeholder_text = "Amount"
	amount_input.add_theme_font_size_override("font_size", 19)
	Game.lay(amount_input, [0, 0, 0, 0], [12, 370, 210, 418])
	body.add_child(amount_input)
	var send := UI.button(body, "TRANSFER", "go", 18, Rect2(224, 370, 184, 48), _transfer, Game.C_CYAN)
	send.set("centered", true)
	var note := Game.label(status, 17, Game.font_med, status_col)
	UI.rect(note, 12, 460, 410, 70)
	body.add_child(note)
	var history := Game.label("TRANSFER SECURITY\nTransfers are recorded in your citizen ledger.", 15, Game.font_tag, Game.C_DIM)
	UI.rect(history, 12, 570, 400, 80)
	body.add_child(history)

func _contacts_app() -> void:
	var h := Game.label("CONTACTS", 25, Game.font_wide, Color.WHITE)
	UI.rect(h, 12, 12, 400, 40)
	body.add_child(h)
	var y := 70.0
	if Online.friends.is_empty():
		var empty := Game.label("No contacts yet. Add friends from the Community menu.", 18, Game.font_med, Game.C_DIM)
		UI.rect(empty, 12, y, 400, 80)
		body.add_child(empty)
		return
	for friend in Online.friends:
		var row := Game.label(str(friend.name) + "  •  " + ("ONLINE" if friend.online else "OFFLINE"), 19, Game.font_semi, Game.C_GREEN if friend.online else Game.C_DIM)
		UI.rect(row, 12, y, 410, 45)
		body.add_child(row)
		y += 54.0

func _market_app() -> void:
	var h := Game.label("VORN MARKET", 25, Game.font_wide, Color.WHITE)
	UI.rect(h, 12, 12, 400, 40)
	body.add_child(h)
	var sub := Game.label("BUY FROM ANYWHERE IN THE CITY", 14, Game.font_tag, Game.C_CYAN)
	UI.rect(sub, 12, 48, 410, 28)
	body.add_child(sub)
	var y := 92.0
	for car in Commerce.CARS:
		var b := UI.button(body, "%s  $%s" % [car.name, Game.fmt(int(car.price))], "car", 16, Rect2(12, y, 410, 48), _buy_car.bind(str(car.id)), Game.C_GOLD)
		b.set("centered", true)
		y += 58.0
	for property in Commerce.PROPERTIES:
		var p := UI.button(body, "%s  $%s" % [property.name, Game.fmt(int(property.price))], "home", 16, Rect2(12, y, 410, 48), _buy_property.bind(str(property.id)), Game.C_CYAN)
		p.set("centered", true)
		y += 58.0
	var note := Game.label(status, 16, Game.font_med, status_col)
	UI.rect(note, 12, 600, 410, 80)
	body.add_child(note)

func _deposit() -> void:
	status = "Deposited $500." if Roleplay.deposit(500) else "Not enough cash to deposit $500."
	status_col = Game.C_GREEN if status.begins_with("Deposited") else Game.C_RED
	_show_app("wallet")

func _withdraw() -> void:
	status = "Withdrew $500." if Roleplay.withdraw(500) else "Not enough bank balance."
	status_col = Game.C_GREEN if status.begins_with("Withdrew") else Game.C_RED
	_show_app("wallet")

func _transfer() -> void:
	var recipient := recipient_input.text.strip_edges() if recipient_input else ""
	var amount := int(amount_input.text) if amount_input else 0
	if recipient == "" or amount <= 0:
		status = "Enter a recipient and a valid amount."
		status_col = Game.C_RED
	else:
		if Roleplay.withdraw(amount):
			var ledger: Array = Game.player.get("transactions", [])
			ledger.append({"type": "transfer", "to": recipient, "amount": amount, "time": Time.get_datetime_string_from_system()})
			Game.player["transactions"] = ledger
			Game.save_data()
			status = "Transferred $%d to %s." % [amount, recipient]
			status_col = Game.C_GREEN
		else:
			status = "Transfer failed: insufficient funds."
			status_col = Game.C_RED
	_show_app("wallet")

func _buy_car(id: String) -> void:
	status = "Vehicle purchased." if Commerce.purchase_car(id) else "Purchase failed or already owned."
	status_col = Game.C_GREEN if status.begins_with("Vehicle") else Game.C_RED
	_show_app("market")

func _buy_property(id: String) -> void:
	status = "Property purchased." if Commerce.purchase_property(id) else "Purchase failed or already owned."
	status_col = Game.C_GREEN if status.begins_with("Property") else Game.C_RED
	_show_app("market")

func toggle() -> void:
	phone_open = not phone_open
	visible = phone_open
	get_tree().paused = phone_open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if phone_open else Input.MOUSE_MODE_CAPTURED
	if phone_open:
		_show_app("wallet")
	Game.play_sfx("click" if phone_open else "back")
