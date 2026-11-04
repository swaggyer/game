extends SceneTree

const Campaign = preload("res://scripts/campaign.gd")
var failures: Array = []
var checks: int = 0


func _initialize() -> void:
	var game = Campaign.new()
	game.save_path = "user://campaign-test-isolated.json"
	_remove_test_saves(game.save_path)
	_check(game.chapters.size() == 7, "seven authored chapters load")
	_check(not game.stage_data(20).is_empty() and game.stage_data(21).is_empty(), "exactly 21 authored stages")
	_check(game.level() == 1 and game.max_hp() == 110 and game.difficulty == "explorer", "new game defaults to explorer with starting cloak HP")
	_check(game.attack() == 12 and game.defense() == 3, "starting equipment stats")
	_check(game.available_skills() == ["spark"], "no unearned source abilities at start")
	_check(not game.equip("weapon", "constellation_blade"), "locked equipment rejected")
	_check(not game.complete_stage(20)["first_clear"], "locked stage cannot grant rewards")
	_check(game.completed.is_empty() and game.xp == 0, "locked stage has no side effects")
	var total_xp: int = 0
	var reward_crystals: int = 0
	var reward_gold: int = 0
	for index in range(21):
		var result: Dictionary = game.complete_stage(index)
		_check(result["first_clear"], "stage %d first clear accepted" % index)
		total_xp += int(result["xp"])
		reward_crystals += int(result["crystals"])
		reward_gold += int(result["gold"])
		var snapshot: Array = [game.xp, game.crystals, game.gold, game.completed.size()]
		_check(not game.complete_stage(index)["first_clear"], "stage %d replay has no first-clear reward" % index)
		_check(snapshot == [game.xp, game.crystals, game.gold, game.completed.size()], "stage %d replay does not duplicate rewards" % index)
		if index == 4:
			_check(not game.available_skills().has("fire"), "fire unavailable before forest boss")
		if index == 5:
			_check(game.available_skills().has("fire"), "forest completion grants fire")
		if index == 8:
			_check(game.available_skills().has("wind"), "windmill completion grants wind")
		if index == 11:
			_check(game.available_skills().has("water"), "water completion grants shield")
		if index == 14:
			_check(game.available_skills().has("space"), "ruins completion grants portal")
	_check(total_xp == 11400 and game.xp == 11400 and game.level() == 20, "main quest alone reaches level20 with exactly11400XP")
	_check(reward_crystals == 272 and reward_gold == 325, "chapter budgets preserve all crystals and gold")
	_check(game.progress == 20 and game.completed.size() == 21, "final stage stays within valid progress bounds")
	_check(game.available_skills().size() == 5, "all four source skills plus initial spark")
	_check(game.available_equipment("accessory").size() == 1, "optional sidequest gear is not awarded by main campaign")
	_check(game.equip("weapon", "constellation_blade"), "earned weapon can be equipped")
	var base_attack: int = game.attack()
	var initial_crystals: int = game.crystals
	_check(game.upgrade("weapon") and game.upgrade("weapon") and game.upgrade("weapon"), "three slot upgrades succeed")
	_check(not game.upgrade("weapon"), "upgrade cap of three enforced")
	_check(game.crystals == initial_crystals - 65 and game.attack() == base_attack + 6, "upgrade prices and attack formula")
	_check(game.equip("weapon", "training_sword") and game.upgrades["weapon"] == 3, "slot upgrades persist when swapping weapon")
	game.reset_upgrades()
	_check(game.crystals == initial_crystals and game.upgrades["weapon"] == 0, "upgrade reset refunds100percent")
	game.crystals = 9
	_check(not game.upgrade("armor") and game.crystals == 9, "insufficient crystals do not mutate state")
	_check(not game.upgrade("not-a-slot"), "unknown upgrade slot rejected")
	game.fruits = 2
	var maximum: int = game.max_hp()
	_check(game.heal_item(float(maximum)) == maximum and game.fruits == 2, "full HP does not consume supply")
	_check(game.heal_item(float(maximum - 10)) == maximum and game.fruits == 1, "healing clamps at max HP")
	_check(game.heal_item(1.0) == 1.0 and game.fruits == 1, "shared supply cooldown prevents immediate repeat")
	game.stage = 20
	game.selected_skill = "space"
	game.active_character = 1
	game.boss_phases["lantern_devourer"] = 2
	_check(game.save_game(), "first atomic save succeeds")
	game.gold = 123
	_check(game.save_game(), "second atomic save preserves a backup")
	var loaded = Campaign.new()
	loaded.save_path = game.save_path
	_check(loaded.load_save(), "save can be read")
	_check(loaded.stage == 20 and loaded.completed.size() == 21 and loaded.gold == 123, "stage and resources survive reload")
	_check(loaded.selected_skill == "space" and loaded.active_character == 1 and loaded.boss_phases.get("lantern_devourer") == 2, "skill character and boss phase survive reload")
	var corrupt: FileAccess = FileAccess.open(game.save_path, FileAccess.WRITE)
	corrupt.store_string("{truncated-save")
	corrupt.close()
	_check(loaded.load_save(), "damaged primary recovers from last-good backup")
	_check(loaded.gold == 325, "backup recovers previous successful save")
	var malformed: Dictionary = {
		"version": 1, "completed": [0, 1, 999, "bad", 4], "equipped": {"weapon": "constellation_blade"},
		"upgrades": {"weapon": 800, "armor": "bad"}, "stage": 900, "xp": "bad", "crystals": -7,
		"fruits": 99, "active_character": 80, "difficulty": "bad", "selected_skill": "space", "boss_phases": []
	}
	corrupt = FileAccess.open(game.save_path, FileAccess.WRITE)
	corrupt.store_string(JSON.stringify(malformed))
	corrupt.close()
	_check(loaded.load_save(), "malformed fields are tolerated in a valid save envelope")
	_check(loaded.completed == [0, 1] and loaded.progress == 2 and loaded.stage == 2, "invalid indices cannot unlock campaign")
	_check(loaded.xp == 0 and loaded.crystals == 0 and loaded.fruits == 5 and loaded.active_character == 1, "resource fields are bounded and type checked")
	_check(loaded.difficulty == "explorer" and loaded.selected_skill == "spark" and loaded.equipped["weapon"] == "training_sword", "invalid difficulty ability and equipment fall back safely")
	_check(loaded.upgrades["weapon"] == 3 and loaded.upgrades["armor"] == 0, "upgrade fields are bounded and type checked")
	loaded.reset_game()
	_check(loaded.progress == 0 and loaded.completed.is_empty() and loaded.level() == 1 and loaded.fruits == 2, "new adventure resets all campaign state")
	_remove_test_saves(game.save_path)
	if failures.is_empty():
		print("CAMPAIGN TESTS PASSED: %d checks" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + str(failure))
		quit(1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _remove_test_saves(path: String) -> void:
	for suffix in ["", ".bak", ".tmp"]:
		var absolute: String = ProjectSettings.globalize_path(path + suffix)
		if FileAccess.file_exists(absolute):
			DirAccess.remove_absolute(absolute)
