class_name Hub
## Lobby sections that live on the player's profile: daily missions, rank, mail with gifts and events.

const TIERS := [["برونزي", 0], ["فضي", 300], ["ذهبي", 800], ["بلاتيني", 1600], ["ماسي", 2800], ["التاج", 4500], ["إيس", 7000], ["الفاتح", 10000]]
const MISSIONS := [
	["العب مباراة واحدة", "matches", 1, 150],
	["العب 3 مباريات", "matches", 3, 350],
	["اقضِ على 5 مقاتلين", "kills", 5, 300],
	["اقضِ على 15 مقاتلاً", "kills", 15, 700],
	["افز بمباراة", "wins", 1, 800],
]
const MAIL := [
	["welcome", "أهلاً بك في AURUM MOBILE", "هدية البداية من استوديوهات صقر.", 500],
	["season1", "الموسم الأول بدأ", "جزيرة بوروفايا مفتوحة. خذ رصيداً لصندوق الذهب.", 500],
	["online", "اللعب أونلاين", "سجّل الدخول والعب مع لاعبين حقيقيين.", 300],
]

static func today() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]

static func weekend() -> bool:
	## the weekend event: double credits on Friday and Saturday
	return Time.get_date_dict_from_system()["weekday"] in [5, 6]

static func daily() -> Dictionary:
	var p := G.profile
	var d: Dictionary = p.get("daily", {})
	if String(d.get("day", "")) != today():
		d = {"day": today(), "base": {"matches": int(p["matches"]), "kills": int(p["kills"]), "wins": int(p["wins"])}, "claimed": []}
		p["daily"] = d
	return d

static func progress(i: int) -> int:
	var d := daily()
	var m: Array = MISSIONS[i]
	return clampi(int(G.profile[m[1]]) - int(d["base"][m[1]]), 0, int(m[2]))

static func claim(i: int) -> bool:
	var d := daily()
	if i in d["claimed"] or progress(i) < int(MISSIONS[i][2]):
		return false
	(d["claimed"] as Array).append(i)
	G.add_credits(int(MISSIONS[i][3]))
	return true

static func points() -> int:
	var p := G.profile
	return int(p["wins"]) * 60 + int(p["kills"]) * 8 + int(p["matches"]) * 12

static func tier() -> Array:
	## [name, index, progress to the next tier 0..1]
	var pt := points()
	var idx := 0
	for i in TIERS.size():
		if pt >= int(TIERS[i][1]):
			idx = i
	var nxt := float(TIERS[mini(idx + 1, TIERS.size() - 1)][1])
	var k := 1.0 if idx == TIERS.size() - 1 else clampf((pt - float(TIERS[idx][1])) / maxf(1.0, nxt - float(TIERS[idx][1])), 0.0, 1.0)
	return [TIERS[idx][0], idx, k]

static func mail_open(id: String) -> bool:
	return id in (G.profile.get("mail", []) as Array)

static func mail_claim(i: int) -> void:
	var m: Array = MAIL[i]
	if mail_open(m[0]):
		return
	var got: Array = G.profile.get("mail", [])
	got.append(m[0])
	G.profile["mail"] = got
	G.add_credits(int(m[3]))

static func unread() -> int:
	var n := 0
	for m in MAIL:
		if not mail_open(m[0]):
			n += 1
	return n
