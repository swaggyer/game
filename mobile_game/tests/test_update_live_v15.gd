extends SceneTree
var checker:Node
var finished=false
func _initialize()->void:call_deferred("_run")
func _run()->void:
	checker=load("res://scripts/update_checker.gd").new();root.add_child(checker);checker.setup()
	checker.current_version="1.0.0";checker.target_platform="Android"
	checker.check_finished.connect(func(result):
		finished=true;print("LIVE UPDATE RESULT "+JSON.stringify(result))
		var success=result.status=="update" and checker.is_allowed_url(result.url) and bool(result.manual)
		checker.queue_free();paused=false;await process_frame;quit(0 if success else 1))
	paused=true
	checker.check(true)
	await create_timer(12,true).timeout
	if not finished:printerr("LIVE UPDATE CALLBACK TIMEOUT");quit(1)
