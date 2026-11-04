extends RefCounted
## Shared team progression. Main-quest rewards and source crystals are granted once.
## The authored JSON is the source of chapter text, stats, enemies and equipment.

const SAVE_VERSION: int = 1
const SAVE_PATH: String = "user://campaign.json"
const LEVEL_CAP: int = 20
const XP_CAP: int = 11400
const UPGRADE_COSTS: Array = [10, 20, 35]
const SLOTS: Array = ["weapon", "armor", "accessory", "shield", "bell"]
const SKILL_NAMES: Dictionary = {
	"spark": "微光", "fire": "星火", "wind": "御风", "water": "水罩", "space": "星门"
}
const INITIAL_EQUIPMENT: Dictionary = {
	"weapon": "training_sword", "armor": "travel_cloak", "accessory": ""
}

var chapters: Array = []
var systems: Dictionary = {}
var progress: int = 0
var stage: int = 0
var xp: int = 0
var crystals: int = 0
var gold: int = 0
var fruits: int = 2
var active_character: int = 0
var difficulty: String = "explorer"
var selected_skill: String = "spark"
var equipped: Dictionary = INITIAL_EQUIPMENT.duplicate()
var upgrades: Dictionary = {"weapon": 0, "armor": 0, "accessory": 0, "shield": 0, "bell": 0}
var completed: Array = []
var boss_phases: Dictionary = {}
var has_save: bool = false
## Overridden by the isolated test suite; production uses SAVE_PATH.
var save_path: String = SAVE_PATH
var _levels: Array = []
var _equipment: Dictionary = {}
var _consumable_ready_ms: int = 0


func _init() -> void:
	var story: Dictionary = _read_json("res://data/chapters.json")
	chapters = story.get("chapters", [])
	systems = _read_json("res://data/systems.json")
	var chapter_rewards: Array = systems.get("combat", {}).get("experience", {}).get("chapterRewards", [])
	for chapter_index in range(chapters.size()):
		var chapter: Dictionary = chapters[chapter_index]
		var chapter_levels: Array = chapter.get("levels", [])
		var rewards: Dictionary = chapter_rewards[chapter_index] if chapter_index < chapter_rewards.size() else {}
		var quest_xp: Array = rewards.get("questXp", [0, 0, 0])
		for level_index in range(chapter_levels.size()):
			var entry: Dictionary = chapter_levels[level_index].duplicate(true)
			entry["chapter_index"] = chapter_index
			entry["chapter_id"] = chapter.get("id", "")
			entry["chapter_name"] = chapter.get("title", "")
			entry["chapter_summary"] = chapter.get("summary", "")
			entry["region"] = chapter.get("region", "")
			entry["quest_xp"] = int(quest_xp[level_index]) if level_index < quest_xp.size() else 0
			entry["index"] = _levels.size()
			entry["level_index"] = level_index
			entry["boss_id"] = chapter.get("bossId", "") if level_index == chapter_levels.size() - 1 else ""
			_levels.append(entry)
	for item in systems.get("equipment", []):
		if item is Dictionary and item.has("id"):
			_equipment[str(item["id"])] = item


func stage_data(index: int = -1) -> Dictionary:
	var resolved: int = stage if index == -1 else index
	if resolved < 0 or resolved >= _levels.size():
		return {}
	return _levels[resolved].duplicate(true)


func level() -> int:
	var result: int = 1
	while result < LEVEL_CAP and xp >= 30 * result * (result + 1):
		result += 1
	return result


func equipment_data(id: String) -> Dictionary:
	return _equipment.get(id, {}).duplicate(true)


func _equipped_stat(slot: String, stat: String) -> float:
	var item: Dictionary = _equipment.get(str(equipped.get(slot, "")), {})
	return float(item.get("stats", {}).get(stat, 0))


func max_hp() -> int:
	var hp: float = 100 + 5 * (level() - 1)
	hp += _equipped_stat("armor", "hp") + _equipped_stat("accessory", "hp")
	hp += int(upgrades.get("armor", 0)) * 5 + int(upgrades.get("accessory", 0)) * 3
	var multiplier: float = 1.3 if difficulty == "gentle" else 1.0
	return int(round(hp * multiplier))


func attack() -> int:
	return 10 + 2 * (level() - 1) + int(_equipped_stat("weapon", "attack")) + int(_equipped_stat("accessory", "attack")) + int(upgrades.get("weapon", 0)) * 2


func defense() -> int:
	var shield: Dictionary = _equipment.get("star_pattern_shield", {})
	return int(floor(float(level() - 1) / 4.0)) + int(shield.get("stats", {}).get("defense", 2)) + int(_equipped_stat("armor", "defense")) + int(_equipped_stat("accessory", "defense")) + int(upgrades.get("armor", 0))


func chapter_finished(index: int) -> bool:
	if index < 0 or index >= chapters.size():
		return false
	var first: int = index * 3
	for i in range(first, first + chapters[index].get("levels", []).size()):
		if not completed.has(i):
			return false
	return true


func complete_stage(index: int) -> Dictionary:
	var result: Dictionary = {
		"first_clear": false, "xp": 0, "crystals": 0, "gold": 0,
		"new_level": level(), "unlocked_skills": [], "equipment": []
	}
	if index < 0 or index >= _levels.size():
		result["error"] = "invalid_stage"
		return result
	if index > progress:
		result["error"] = "locked_stage"
		return result
	if completed.has(index):
		result["error"] = "already_completed"
		return result
	var old_skills: Array = available_skills()
	var old_items: Array = _available_ids()
	var entry: Dictionary = _levels[index]
	var chapter_index: int = int(entry["chapter_index"])
	var local_index: int = int(entry["level_index"])
	var chapter_rewards: Array = systems.get("combat", {}).get("experience", {}).get("chapterRewards", [])
	var rewards: Dictionary = chapter_rewards[chapter_index] if chapter_index < chapter_rewards.size() else {}
	var reward_xp: int = int(entry.get("quest_xp", 0))
	# Allocate each chapter's fixed budget over its three stages without rounding loss.
	var reward_crystals: int = _third_share(int(rewards.get("crystals", 0)), local_index)
	var reward_gold: int = _third_share(int(rewards.get("gold", 0)), local_index)
	completed.append(index)
	completed.sort()
	xp = mini(XP_CAP, maxi(0, xp) + reward_xp)
	crystals += reward_crystals
	gold += reward_gold
	progress = mini(_levels.size() - 1, maxi(progress, index + 1))
	fruits = maxi(2, fruits)
	result["first_clear"] = true
	result["xp"] = reward_xp
	result["crystals"] = reward_crystals
	result["gold"] = reward_gold
	result["new_level"] = level()
	for skill in available_skills():
		if not old_skills.has(skill):
			result["unlocked_skills"].append(skill)
	for id in _available_ids():
		if not old_items.has(id):
			result["equipment"].append(equipment_data(id))
	# Source crystal acquisition is permanent and is represented by available_skills.
	return result


func _third_share(total: int, local_index: int) -> int:
	var share: int = int(floor(float(total) / 3.0))
	return share + (total - share * 3 if local_index == 2 else 0)


func available_skills() -> Array:
	var skills: Array = ["spark"]
	var source_skills: Array = ["fire", "wind", "water", "space"]
	for i in range(source_skills.size()):
		if chapter_finished(i + 1):
			skills.append(source_skills[i])
	return skills


func skill_name(id: String) -> String:
	return SKILL_NAMES.get(id, "微光")


func _item_available(item: Dictionary) -> bool:
	# Optional accessories remain side-quest rewards: this main-campaign prototype
	# does not silently award them in lieu of their authored side quests.
	if "支线" in str(item.get("acquisition", "")):
		return false
	var id: String = str(item.get("id", ""))
	if id == "twin_star_brooch":
		return completed.has(15)
	if id == "moon_current_staff":
		return completed.has(10)
	if id == "dragon_royal_crown":
		return completed.has(19)
	var chapter_id: String = str(item.get("unlockChapter", "prologue"))
	if chapter_id == "prologue":
		return true
	for i in range(chapters.size()):
		if str(chapters[i].get("id", "")) == chapter_id:
			return chapter_finished(i)
	return false


func _available_ids() -> Array:
	var result: Array = []
	for id in _equipment:
		if _item_available(_equipment[id]):
			result.append(id)
	return result


func available_equipment(slot: String) -> Array:
	var result: Array = []
	for item in systems.get("equipment", []):
		var category: String = str(item.get("categoryId", ""))
		var matches: bool = category == slot
		if slot == "shield":
			matches = str(item.get("id", "")) == "star_pattern_shield"
		elif slot == "bell":
			matches = str(item.get("id", "")) == "echo_bell"
		if matches and _item_available(item):
			result.append(item.duplicate(true))
	return result


func equip(slot: String, id: String) -> bool:
	if not INITIAL_EQUIPMENT.has(slot):
		return false
	if slot == "accessory" and id.is_empty():
		equipped[slot] = ""
		return true
	for item in available_equipment(slot):
		if str(item.get("id", "")) == id:
			equipped[slot] = id
			return true
	return false


func upgrade(slot: String) -> bool:
	if not SLOTS.has(slot):
		return false
	var current: int = int(upgrades.get(slot, 0))
	if current < 0 or current >= UPGRADE_COSTS.size():
		return false
	var price: int = int(UPGRADE_COSTS[current])
	if crystals < price:
		return false
	crystals -= price
	upgrades[slot] = current + 1
	return true


func reset_upgrades() -> void:
	for slot in SLOTS:
		var count: int = clampi(int(upgrades.get(slot, 0)), 0, 3)
		for i in range(count):
			crystals += int(UPGRADE_COSTS[i])
		upgrades[slot] = 0


func heal_item(current_hp: float) -> float:
	var hp: float = clampf(current_hp, 0.0, float(max_hp()))
	var now: int = Time.get_ticks_msec()
	if hp >= max_hp() or fruits <= 0 or now < _consumable_ready_ms:
		return hp
	var heal: float = 35.0
	if str(equipped.get("accessory", "")) == "sunstar_pendant":
		heal += 5.0
	fruits -= 1
	_consumable_ready_ms = now + 2000
	return minf(float(max_hp()), hp + heal)


func save_game() -> bool:
	var document: Dictionary = {
		"version": SAVE_VERSION, "progress": progress, "stage": stage,
		"xp": xp, "crystals": crystals, "gold": gold, "fruits": fruits,
		"active_character": active_character, "difficulty": difficulty,
		"selected_skill": selected_skill, "equipped": equipped.duplicate(),
		"upgrades": upgrades.duplicate(), "completed": completed.duplicate(),
		"boss_phases": boss_phases.duplicate(true)
	}
	var destination: String = ProjectSettings.globalize_path(save_path)
	var temporary: String = destination + ".tmp"
	var backup: String = destination + ".bak"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(document, "\t"))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		return false
	if FileAccess.file_exists(destination):
		# Keep a last-good backup when replacing a damaged primary save.
		if _valid_document(_read_json(destination)):
			if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK:
				return false
			if DirAccess.rename_absolute(destination, backup) != OK:
				return false
		elif DirAccess.remove_absolute(destination) != OK:
			return false
	if DirAccess.rename_absolute(temporary, destination) != OK:
		if not FileAccess.file_exists(destination) and FileAccess.file_exists(backup):
			DirAccess.copy_absolute(backup, destination)
		return false
	has_save = true
	return true


func load_save() -> bool:
	var document: Dictionary = _read_json(save_path)
	if not _valid_document(document):
		document = _read_json(save_path + ".bak")
	if not _valid_document(document):
		has_save = false
		return false
	_apply_document(document)
	has_save = true
	return true


func _valid_document(document: Dictionary) -> bool:
	if document.is_empty() or not document.get("completed", null) is Array:
		return false
	if not document.get("equipped", null) is Dictionary or not document.get("upgrades", null) is Dictionary:
		return false
	var version: Variant = document.get("version", 0)
	return (version is int or version is float) and float(version) == float(SAVE_VERSION)


func _apply_document(document: Dictionary) -> void:
	# Recover only a contiguous, valid campaign prefix. A malformed index cannot
	# open a chapter or award a source skill whose story has not been completed.
	var candidate: Array = []
	for value in document.get("completed", []):
		if value is int or value is float:
			if not is_finite(float(value)) or float(value) < 0 or float(value) >= _levels.size():
				continue
			var index: int = int(value)
			if float(index) == float(value) and index >= 0 and index < _levels.size() and not candidate.has(index):
				candidate.append(index)
	completed.clear()
	for index in range(_levels.size()):
		if not candidate.has(index):
			break
		completed.append(index)
	progress = mini(completed.size(), maxi(0, _levels.size() - 1))
	stage = _safe_int(document.get("stage", 0), 0, 0, progress)
	xp = _safe_int(document.get("xp", 0), 0, 0, XP_CAP)
	crystals = _safe_int(document.get("crystals", 0), 0, 0, 999999)
	gold = _safe_int(document.get("gold", 0), 0, 0, 999999)
	fruits = _safe_int(document.get("fruits", 2), 2, 0, 5)
	active_character = _safe_int(document.get("active_character", 0), 0, 0, 1)
	var saved_difficulty: String = str(document.get("difficulty", "explorer"))
	difficulty = saved_difficulty if ["gentle", "explorer", "brave"].has(saved_difficulty) else "explorer"
	var skill: String = str(document.get("selected_skill", "spark"))
	selected_skill = skill if available_skills().has(skill) else "spark"
	equipped = INITIAL_EQUIPMENT.duplicate()
	var saved_equipment: Dictionary = document.get("equipped", {})
	for slot in INITIAL_EQUIPMENT:
		equip(slot, str(saved_equipment.get(slot, INITIAL_EQUIPMENT[slot])))
	var saved_upgrades: Dictionary = document.get("upgrades", {})
	for slot in SLOTS:
		upgrades[slot] = _safe_int(saved_upgrades.get(slot, 0), 0, 0, 3)
	boss_phases.clear()
	var saved_phases: Variant = document.get("boss_phases", {})
	if saved_phases is Dictionary:
		for key in saved_phases:
			var normalized: String = str(key)
			if normalized.is_valid_int():
				var index: int = normalized.to_int()
				if index >= 0 and index <= progress:
					boss_phases[normalized] = _safe_int(saved_phases[key], 0, 0, 3)
			elif _known_boss(normalized):
				boss_phases[normalized] = _safe_int(saved_phases[key], 0, 0, 3)
	_consumable_ready_ms = 0


func _known_boss(id: String) -> bool:
	for index in range(mini(progress + 1, _levels.size())):
		if str(_levels[index].get("boss_id", "")) == id:
			return true
	return false


func _safe_int(value: Variant, fallback: int, minimum: int, maximum: int) -> int:
	if value is int:
		return clampi(value, minimum, maximum)
	if value is float and is_finite(value):
		return int(clampf(value, float(minimum), float(maximum)))
	return fallback


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser: JSON = JSON.new()
	var error: Error = parser.parse(file.get_as_text().trim_prefix("\ufeff"))
	file.close()
	if error != OK or not parser.data is Dictionary:
		return {}
	return parser.data


func reset_game() -> void:
	progress = 0
	stage = 0
	xp = 0
	crystals = 0
	gold = 0
	fruits = 2
	active_character = 0
	difficulty = "explorer"
	selected_skill = "spark"
	equipped = INITIAL_EQUIPMENT.duplicate()
	upgrades = {"weapon": 0, "armor": 0, "accessory": 0, "shield": 0, "bell": 0}
	completed.clear()
	boss_phases.clear()
	_consumable_ready_ms = 0
	has_save = false
