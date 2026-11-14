class_name DB
extends RefCounted
## Таблицы игры: оружие, снаряжение, экономика, скины, кейсы.

# скорость — м/с (как в CS: 250 ед/с = 6.35 м/с); урон и пробитие брони — близко к оригинальному жанру
const W := {
	"knife": {"name": "سكين", "slot": 3, "cls": "knife", "price": 0, "dmg": 40, "dmg2": 65, "pen": 0.85, "rpm": 150, "mag": 0, "res": 0, "reload": 0.0,
		"speed": 6.35, "rmod": 1.0, "reward": 1500, "auto": true, "hold": "knife", "snd": "knife"},
	"glock": {"name": "جي 18", "slot": 2, "cls": "pistol", "team": "t", "price": 200, "dmg": 30, "pen": 0.47, "rpm": 400, "mag": 20, "res": 120, "reload": 2.2,
		"speed": 6.1, "rmod": 0.85, "reward": 300, "auto": false, "hold": "pistol", "snd": "pistol", "rec": [1.1, 0.5, 6.0], "spread": [0.35, 2.6, 6.0], "wall": 0.5, "sight": "rmr"},
	"usp": {"name": "يو إس بي", "slot": 2, "cls": "pistol", "team": "ct", "price": 200, "dmg": 35, "pen": 0.505, "rpm": 352, "mag": 12, "res": 24, "reload": 2.2,
		"speed": 6.1, "rmod": 0.91, "reward": 300, "auto": false, "hold": "pistol", "snd": "usp", "rec": [1.2, 0.4, 6.0], "spread": [0.22, 2.4, 6.0], "wall": 0.5, "sight": "rmr"},
	"deagle": {"name": "نسر الصحراء", "slot": 2, "cls": "pistol", "price": 700, "dmg": 53, "pen": 0.932, "rpm": 267, "mag": 7, "res": 35, "reload": 2.2,
		"speed": 5.85, "rmod": 0.92, "reward": 300, "auto": false, "hold": "pistol", "snd": "deagle", "rec": [3.6, 1.1, 4.5], "spread": [0.3, 4.2, 8.0], "wall": 1.2, "sight": "rmr"},
	"mac10": {"name": "ماك", "slot": 1, "cls": "smg", "team": "t", "price": 1050, "dmg": 29, "pen": 0.575, "rpm": 800, "mag": 30, "res": 100, "reload": 2.6,
		"speed": 6.1, "rmod": 0.8, "reward": 600, "auto": true, "hold": "smg", "snd": "smg", "rec": [0.75, 0.55, 7.0], "spread": [0.55, 1.4, 5.0], "wall": 0.6, "sight": "holo"},
	"mp9": {"name": "إم بي 9", "slot": 1, "cls": "smg", "team": "ct", "price": 1250, "dmg": 26, "pen": 0.6, "rpm": 857, "mag": 30, "res": 120, "reload": 2.1,
		"speed": 6.1, "rmod": 0.87, "reward": 600, "auto": true, "hold": "smg", "snd": "smg", "rec": [0.7, 0.5, 7.0], "spread": [0.5, 1.3, 5.0], "wall": 0.6, "sight": "holo"},
	"shotgun": {"name": "خرطوش", "slot": 1, "cls": "shotgun", "price": 1050, "dmg": 26, "pellets": 9, "pen": 0.5, "rpm": 68, "mag": 8, "res": 32, "reload": 0.55,
		"speed": 5.6, "rmod": 0.7, "reward": 900, "auto": false, "hold": "rifle", "snd": "shotgun", "rec": [5.0, 1.0, 4.0], "spread": [2.6, 3.2, 6.0], "wall": 0.3, "sight": "holo"},
	"ak": {"name": "كلاشنكوف", "slot": 1, "cls": "rifle", "team": "t", "price": 2700, "dmg": 36, "pen": 0.775, "rpm": 600, "mag": 30, "res": 90, "reload": 2.5,
		"speed": 5.46, "rmod": 0.98, "reward": 300, "auto": true, "hold": "rifle", "snd": "ak", "rec": [1.05, 0.75, 6.5], "spread": [0.18, 3.6, 9.0], "wall": 1.6, "sight": "acog"},
	"m4": {"name": "إم 4", "slot": 1, "cls": "rifle", "team": "ct", "price": 2900, "dmg": 33, "pen": 0.7, "rpm": 666, "mag": 30, "res": 90, "reload": 3.1,
		"speed": 5.7, "rmod": 0.97, "reward": 300, "auto": true, "hold": "rifle", "snd": "m4", "rec": [0.85, 0.6, 7.0], "spread": [0.16, 3.2, 9.0], "wall": 1.4, "sight": "acog"},
	"awp": {"name": "الشاهين", "slot": 1, "cls": "sniper", "price": 4750, "dmg": 115, "pen": 0.975, "rpm": 41, "mag": 5, "res": 30, "reload": 3.7,
		"speed": 5.08, "rmod": 0.99, "reward": 100, "auto": false, "hold": "rifle", "snd": "sniper", "rec": [6.0, 0.6, 3.0], "spread": [2.2, 6.0, 12.0], "scope": true, "wall": 2.2, "sight": "sniper"},
	"he": {"name": "متفجّرة", "slot": 4, "cls": "nade", "price": 300, "speed": 6.2, "hold": "nade"},
	"flash": {"name": "وميضية", "slot": 4, "cls": "nade", "price": 200, "speed": 6.2, "hold": "nade"},
	"smoke": {"name": "دخانية", "slot": 4, "cls": "nade", "price": 300, "speed": 6.2, "hold": "nade"},
	"molotov": {"name": "حارقة", "slot": 4, "cls": "nade", "price": 400, "speed": 6.2, "hold": "nade"},
	"decoy": {"name": "خداعية", "slot": 4, "cls": "nade", "price": 50, "speed": 6.2, "hold": "nade"},
	"c4": {"name": "القنبلة", "slot": 5, "cls": "c4", "price": 0, "speed": 6.35, "hold": "c4"},
}
const NADES := ["he", "flash", "smoke", "molotov", "decoy"]

# прицелы на оружии (вид через сам прицел, без накладки на экран):
#   zoom — кратность линзы (1 — коллиматор, картинка мира видна сквозь стекло), fov_k — сужение обзора при прицеливании,
#   sens — чувствительность, move — скорость, relief — расстояние от глаза до окуляра, м; spread_k — разброс стоя
const SIGHTS := {
	"rmr": {"name": "مصغّر أحمر", "zoom": 1.0, "fov_k": 0.88, "sens": 0.85, "move": 0.8, "relief": 0.30, "spread_k": 0.7, "ads_t": 0.16},
	"holo": {"name": "هولوغرافي", "zoom": 1.0, "fov_k": 0.84, "sens": 0.8, "move": 0.75, "relief": 0.20, "spread_k": 0.65, "ads_t": 0.2},
	"acog": {"name": "منظار ×3", "zoom": 3.0, "fov_k": 0.80, "sens": 0.42, "move": 0.65, "relief": 0.065, "spread_k": 0.5, "ads_t": 0.26},
	"sniper": {"name": "منظار قنّاص ×8", "zoom": 8.0, "fov_k": 0.76, "sens": 0.2, "move": 0.48, "relief": 0.058, "spread_k": 0.0, "ads_t": 0.32},
}
const GEAR := {
	"kevlar": {"name": "سترة واقية", "price": 650},
	"helmet": {"name": "سترة وخوذة", "price": 1000},
	"kit": {"name": "عدّة التفكيك", "price": 400, "team": "ct"},
}
const BUY := [
	["مسدسات", ["glock", "usp", "deagle"]],
	["رشاشات وخرطوش", ["mac10", "mp9", "shotgun"]],
	["بنادق", ["ak", "m4", "awp"]],
	["قنابل", ["he", "flash", "smoke", "molotov", "decoy"]],
	["معدّات", ["kevlar", "helmet", "kit"]],
]

# экономика
const START_MONEY := 800
const MAX_MONEY := 16000
const WIN_ELIM := 3250
const WIN_BOMB := 3500
const LOSS := [1400, 1900, 2400, 2900, 3400]
const PLANT_BONUS := 300
const PLANT_LOSS_BONUS := 800

# тайминги раунда, с
const T_FREEZE := 7.0
const T_ROUND := 115.0
const T_BOMB := 40.0
const T_PLANT := 3.2
const T_DEFUSE := 10.0
const T_DEFUSE_KIT := 5.0
const T_END := 6.0
const T_BUY := 25.0

# зоны попадания: множитель урона
const ZONE := {"head": 4.0, "chest": 1.0, "stomach": 1.25, "legs": 0.75}

# ------------------------------------------------------------------ скины (свои, по листу fx_skins)
# вид: 0 диагональные полосы, 1 блоки, 2 сплошной, 3 цифровой камуфляж, 4 тонкие линии
const SKINS := {
	"dune": {"name": "الكثيب", "kind": 0, "a": Color(0.72, 0.60, 0.36), "b": Color(0.80, 0.62, 0.16), "rar": 0},
	"oasis": {"name": "الواحة", "kind": 0, "a": Color(0.16, 0.17, 0.18), "b": Color(0.25, 0.62, 0.62), "rar": 1},
	"ember": {"name": "الجمر", "kind": 1, "a": Color(0.86, 0.84, 0.80), "b": Color(0.70, 0.25, 0.10), "rar": 2},
	"bronze": {"name": "البرونز", "kind": 2, "a": Color(0.55, 0.36, 0.14), "b": Color(0.30, 0.20, 0.09), "rar": 0},
	"pixel": {"name": "بكسل", "kind": 3, "a": Color(0.30, 0.36, 0.18), "b": Color(0.62, 0.64, 0.44), "rar": 1},
	"night": {"name": "رحلة ليلية", "kind": 4, "a": Color(0.09, 0.12, 0.24), "b": Color(0.90, 0.90, 0.92), "rar": 3},
	"crimson": {"name": "القرمزي", "kind": 0, "a": Color(0.36, 0.03, 0.05), "b": Color(0.05, 0.05, 0.06), "rar": 3},
	"gold": {"name": "المذهّب", "kind": 2, "a": Color(0.95, 0.72, 0.22), "b": Color(0.6, 0.4, 0.08), "rar": 4},
}
const RAR_NAME := ["عسكري", "محظور", "سرّي", "خفيّ", "أسطوري"]
const RAR_COL := [Color(0.30, 0.42, 1.0), Color(0.53, 0.28, 1.0), Color(0.83, 0.17, 0.90), Color(0.92, 0.29, 0.29), Color(1.0, 0.84, 0.0)]
const RAR_ODDS := [0.60, 0.24, 0.11, 0.04, 0.01]
const SKIN_WEAPONS := ["ak", "m4", "awp", "deagle", "glock", "usp", "mac10", "mp9", "shotgun", "knife"]
const CASES := {
	"kasbah": {"name": "صندوق «القصبة»", "price": 500, "skins": ["dune", "oasis", "ember", "bronze", "pixel", "night", "crimson", "gold"]},
}

static func skin_id(weapon: String, skin: String) -> String:
	return weapon + ":" + skin

static func skin_title(id: String) -> String:
	var p := id.split(":")
	return "%s | %s" % [W[p[0]]["name"], SKINS[p[1]]["name"]]

static func roll_case(case_id: String, rng: RandomNumberGenerator) -> String:
	var pool: Array = CASES[case_id]["skins"]
	var r := rng.randf()
	var acc := 0.0
	var rar := 0
	for i in RAR_ODDS.size():
		acc += RAR_ODDS[i]
		if r <= acc:
			rar = i
			break
	var cand := []
	for s in pool:
		if SKINS[s]["rar"] == rar:
			cand.append(s)
	if cand.is_empty():
		cand = pool.duplicate()
	var skin: String = cand[rng.randi() % cand.size()]
	var wl := SKIN_WEAPONS
	if rar < 4:
		wl = SKIN_WEAPONS.slice(0, 9)
	else:
		wl = ["knife", "awp", "ak"]
	return skin_id(wl[rng.randi() % wl.size()], skin)
