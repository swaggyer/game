extends SceneTree
var failures:Array=[]
var checks=0
func _initialize()->void:call_deferred("_run")
func _run()->void:
	change_scene_to_file("res://scenes/main.tscn")
	await process_frame;await process_frame
	var game=current_scene
	_check(paused and game.ui.title_screen.visible,"actual main opens paused title")
	_check(game.auto_update_checked,"normal scene launch schedules an automatic check")
	if game.update_checker.checking:await game.update_checker.check_finished
	_check(game.update_checker.last_result.get("status","")=="current","actual HTTPS automatic result reaches paused main scene")
	_check(not game.ui._update_checking,"automatic completion restores update button")
	var fixture={"draft":false,"prerelease":false,"tag_name":"v99.0.0","html_url":"https://github.com/swaggyer/game/releases/tag/v99.0.0","assets":[],"body":"界面回归测试，不是已发布版本。"}
	var info=game.update_checker.parse_release(JSON.stringify(fixture));info.manual=true
	game._update_check_finished(info)
	_check(game.ui.update_screen.visible and paused,"validated future release opens isolated update notice")
	game.ui._hide_update_result();game._start(false)
	if game.ui.dialog_screen.visible:game.ui._close_dialog()
	game._update_check_finished(info)
	_check(not game.ui.update_screen.visible and not paused,"late release response does not interrupt gameplay")
	game.ui.show_title()
	_check(game.ui.update_screen.visible and paused,"pending release appears after returning to title")
	game.hero_actions.game=null;game.locomotion.game=null;game.queue_free();await process_frame;await process_frame
	for failure in failures:printerr(failure)
	print("UPDATE MAIN V15: %d checks; %d failures; actual public HTTPS plus future-release fixture"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
func _check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message)
