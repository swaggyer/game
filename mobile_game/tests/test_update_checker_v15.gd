extends SceneTree
const Checker=preload("res://scripts/update_checker.gd")
class OfflineChecker extends "res://scripts/update_checker.gd":
	var starts:int=0
	var start_result:Error=OK
	func _send_request()->Error:
		starts+=1
		return start_result
var checks:int=0
var failures:Array[String]=[]
var results:Array[Dictionary]=[]

func _initialize()->void:call_deferred("_run")

func _fixture(tag:String="v1.6.0")->Dictionary:
	var version:String=tag.trim_prefix("v")
	var name:String="StarLanternIsland-v%s-arm64.apk"%version
	return {"tag_name":tag,"draft":false,"prerelease":false,"body":"新增玩法与性能修复。",
		"html_url":Checker.RELEASE_ROOT+"/tag/"+tag,"assets":[{"name":name,"state":"uploaded","browser_download_url":Checker.RELEASE_ROOT+"/download/"+tag+"/"+name}]}

func _parse(checker:Node,data:Dictionary)->Dictionary:return checker.parse_release(JSON.stringify(data))

func _run()->void:
	var owner:Node=Node.new();root.add_child(owner)
	var checker=OfflineChecker.new();checker.current_version="1.5.0-github-update";checker.target_platform="Android";checker.setup(owner)
	_check(checker.process_mode==Node.PROCESS_MODE_ALWAYS and checker.http.process_mode==Node.PROCESS_MODE_ALWAYS,"metadata processing continues under title/game pause")
	_check(checker.http.timeout==8.0 and checker.http.use_threads,"network is threaded and bounded by eight seconds")
	_check(checker.http.body_size_limit==524288 and checker.http.max_redirects==0,"metadata has bounded memory and cannot redirect to another host")
	checker.setup(owner);_check(checker.get_child_count()==1,"setup does not create duplicate HTTP requests")
	checker.check_finished.connect(func(value:Dictionary):results.append(value))
	var data:Dictionary=_fixture()
	var result:Dictionary=_parse(checker,data)
	_check(result.status=="update" and result.version=="1.6.0","new stable release recognized")
	_check(result.url==data.assets[0].browser_download_url and result.asset_kind=="apk","exact arm64 APK selected")
	_check(result.notes==data.body,"release notes preserved as plain text")
	for platform:String in ["iOS","Windows","macOS","Linux"]:
		checker.target_platform=platform
		result=_parse(checker,_fixture())
		_check(result.status=="update" and result.asset_kind=="release" and result.url==_fixture().html_url,platform+" uses the formal release page instead of an Android package")
		_check(not result.url.ends_with(".apk"),platform+" is never prompted to download an APK")
	checker.target_platform="Android"
	for tag:String in ["v1.5.0","v1.4.99","v0.9.0"]:
		result=_parse(checker,_fixture(tag))
		_check(result.status=="current" and result.version=="1.5.0" and result.url.is_empty(),"same or older release never offers a downgrade: "+tag)
	for comparison:Array in [["1.10","1.9",1],["v1.10.0","1.9.99",1],["2.0.0","1.999.999",1],["1.2.10","1.2.9",1],["1.5.0-mobile","v1.5.0",0],["1.5","1.5.0+build.1",0],["0.99.0","1.0.0",-1],["999999999999999999999.0.0","999999999999999999998.9.9",1]]:
		_check(Checker.compare_versions(comparison[0],comparison[1])==comparison[2],"numeric semantic ordering: "+str(comparison))
	checker.current_version="1.9.0"
	_check(_parse(checker,_fixture("v1.10.0")).status=="update","HTTP metadata uses numeric ordering rather than lexical sorting")
	checker.current_version="1.5.0-local"
	for flag:String in ["draft","prerelease"]:
		data=_fixture();data[flag]=true
		_check(_parse(checker,data).status=="error",flag+" releases rejected")
		data[flag]="false"
		_check(_parse(checker,data).status=="error","malformed release flag rejected: "+flag)
	data=_fixture();data.erase("draft");_check(_parse(checker,data).status=="error","missing release publication flags rejected")
	for bad:String in ["v1.6.0-beta.1","v1.6.0+build","v01.6.0","v1.6","1.6.0/evil","v1.6.0?x=1","v1.6.0%2f.."," v1.6.0","../../1.6.0"]:
		data=_fixture();data.tag_name=bad
		_check(_parse(checker,data).status=="error","unsafe or non-stable tag rejected: "+bad)
	for bad:String in ["http://github.com/swaggyer/game/releases/download/v1.6.0/StarLanternIsland-v1.6.0-arm64.apk","https://github.com.evil.invalid/swaggyer/game/releases/download/v1.6.0/StarLanternIsland-v1.6.0-arm64.apk","https://evil.invalid/update.apk","file:///tmp/update.apk","javascript:alert(1)","https://github.com/swaggyer/other/releases/download/v1.6.0/StarLanternIsland-v1.6.0-arm64.apk","https://github.com/swaggyer/game/releases/download/v1.6.0/StarLanternIsland-v1.6.0-arm64.apk?redirect=evil","https://github.com/swaggyer/game/releases/download/v1.6.0/StarLanternIsland-v1.6.0-arm64.apk#fragment"]:
		data=_fixture();data.assets[0].browser_download_url=bad
		result=_parse(checker,data)
		_check(result.status=="error" and result.url.is_empty() and not Checker.is_allowed_url(bad),"malicious download URL rejected: "+bad)
	data=_fixture();data.assets=[]
	result=_parse(checker,data)
	_check(result.status=="update" and result.asset_kind=="release" and result.url==data.html_url,"no APK falls back to this repository's exact release page")
	for bad:String in ["https://evil.invalid/releases/tag/v1.6.0","https://github.com/swaggyer/game/releases/tag/v1.6.0?x=1","https://github.com/swaggyer/game/releases/tag/v1.6.0/../evil"]:
		data.html_url=bad
		_check(_parse(checker,data).status=="error" and not Checker.is_allowed_url(bad),"unsafe release fallback rejected")
	data=_fixture();data.assets[0].name="StarLanternIsland-v1.6.0-arm32.apk"
	_check(_parse(checker,data).asset_kind=="release","wrong architecture/name cannot be offered as an APK")
	data=_fixture();data.assets.append(data.assets[0].duplicate())
	_check(_parse(checker,data).status=="error","duplicate matching APK rejected")
	data=_fixture();data.assets[0].state="open"
	_check(_parse(checker,data).asset_kind=="release","upload still in progress is not offered for download")
	for body:String in ["", "{", "[]", "null", "true", "\"text\""]:
		result=checker.parse_release(body)
		_check(result.status=="error" and result.url.is_empty(),"malformed JSON cannot create an update action")
	data=_fixture();data.assets={}
	_check(_parse(checker,data).status=="error","non-array attachments rejected")
	data=_fixture();data.body="长".repeat(5000)
	_check(_parse(checker,data).notes.length()<=Checker.MAX_NOTES+3,"release notes bounded for the mobile dialog")
	_check(checker.parse_release(" ".repeat(Checker.MAX_BODY_BYTES+1)).error_code=="body_limit","oversized JSON rejected before parsing")
	_check(checker.parse_release("",200,HTTPRequest.RESULT_TIMEOUT).error_code=="timeout","offline fixture covers native HTTP timeout result")
	for response:int in [403,429]:_check(checker.parse_release("{}",response).error_code=="rate_limit","GitHub rate limit handled without retry: %d"%response)
	_check(checker.parse_release("{}",404).error_code=="not_found","missing public release handled")
	_check(checker.parse_release("{}",500).status=="error","server errors handled")
	_check(checker.parse_release("{}",200,HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR).status=="error","TLS failure cannot bypass HTTPS verification")
	_check(checker.check(false) and checker.checking and checker.starts==1,"first startup check starts once without blocking")
	_check(not checker.check(true) and not checker.check(false) and checker.starts==1,"in-flight checks cannot reenter")
	paused=true
	checker._on_request_completed(HTTPRequest.RESULT_SUCCESS,200,PackedStringArray(),JSON.stringify(_fixture()).to_utf8_buffer())
	_check(not checker.checking and results.size()==1 and results[0].status=="update" and not results[0].manual,"paused startup check delivers its result once")
	checker._on_request_completed(HTTPRequest.RESULT_TIMEOUT,0,PackedStringArray(),PackedByteArray())
	_check(results.size()==1,"late or duplicate completion cannot emit a second dialog")
	_check(not checker.check(false) and checker.starts==1,"automatic check cannot run again during this launch")
	_check(checker.check(true) and checker.starts==2,"manual check can run after automatic completion")
	checker._on_request_completed(HTTPRequest.RESULT_TIMEOUT,0,PackedStringArray(),PackedByteArray())
	_check(results.size()==2 and results[1].manual and results[1].error_code=="timeout" and not checker.checking,"manual timeout clears busy state and reports a retryable error")
	checker.start_result=ERR_CANT_CONNECT
	_check(checker.check(true) and checker.checking,"immediate request failure is reported asynchronously")
	await process_frame
	_check(not checker.checking and results.size()==3 and results[2].error_code=="request_start","request-start error completes even while the tree is paused")
	_check(checker.http.download_file.is_empty(),"metadata check does not create an automatic download file")
	paused=false;owner.queue_free();await process_frame;await process_frame
	checker=null;owner=null
	for failure:String in failures:printerr("FAIL: "+failure)
	print("GITHUB UPDATE CHECKER V1.5 %s: %d offline checks; no real HTTP requests"%["PASSED" if failures.is_empty() else "FAILED",checks])
	quit(0 if failures.is_empty() else 1)

func _check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message)
