extends Node
## Public release metadata only. Download/installation is deliberately owned by
## the UI's explicit user action; this node never downloads an APK or opens URLs.
signal check_finished(result:Dictionary)

const API_URL:String="https://api.github.com/repos/swaggyer/game/releases/latest"
const RELEASE_ROOT:String="https://github.com/swaggyer/game/releases"
const TIMEOUT_SECONDS:float=8.0
const MAX_BODY_BYTES:int=524288
const MAX_NOTES:int=4000
var checking:bool=false
var current_version:String=""
var target_platform:String=OS.get_name()
var http:HTTPRequest
var last_result:Dictionary={}
var _automatic_checked:bool=false
var _manual:bool=false

func setup(game:Node=null)->void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	if get_parent()==null and is_instance_valid(game):game.add_child(self)
	if current_version.is_empty():current_version=str(ProjectSettings.get_setting("application/config/version",""))
	if is_instance_valid(http):return
	http=HTTPRequest.new();http.name="GitHubReleaseMetadata"
	http.process_mode=Node.PROCESS_MODE_ALWAYS
	http.use_threads=true;http.timeout=TIMEOUT_SECONDS
	http.body_size_limit=MAX_BODY_BYTES;http.max_redirects=0
	add_child(http)
	http.request_completed.connect(_on_request_completed)

func check(manual:bool=false)->bool:
	if checking or (not manual and _automatic_checked):return false
	if not is_instance_valid(http):setup()
	if not manual:_automatic_checked=true
	_manual=manual;checking=true
	var error:Error=_send_request()
	if error!=OK:
		_finish.call_deferred(_error("无法开始检查更新，请稍后重试。","request_start"))
	return true

func _send_request()->Error:
	# No credentials, tokens, device identifiers or player data leave the game.
	return http.request(API_URL,PackedStringArray([
		"Accept: application/vnd.github+json",
		"X-GitHub-Api-Version: 2022-11-28",
		"User-Agent: StarLanternIsland-UpdateChecker"]),HTTPClient.METHOD_GET)

func _on_request_completed(request_result:int,response_code:int,_headers:PackedStringArray,body:PackedByteArray)->void:
	if not checking:return
	_finish(parse_release(body.get_string_from_utf8(),response_code,request_result))

func _finish(result:Dictionary)->void:
	if not checking:return
	checking=false
	result["manual"]=_manual
	last_result=result.duplicate(true)
	check_finished.emit(result.duplicate(true))

func parse_release(body:String,http_code:int=200,request_result:int=HTTPRequest.RESULT_SUCCESS)->Dictionary:
	if request_result==HTTPRequest.RESULT_TIMEOUT:return _error("检查更新超时，请稍后重试。","timeout")
	if request_result!=HTTPRequest.RESULT_SUCCESS:return _error("暂时无法连接更新服务器，请稍后重试。","network")
	if http_code in [403,429]:return _error("GitHub 请求较多，请稍后再检查。","rate_limit")
	if http_code==404:return _error("暂未找到公开的正式版本。","not_found")
	if http_code!=200:return _error("更新服务器暂不可用，请稍后重试。","http")
	if body.to_utf8_buffer().size()>MAX_BODY_BYTES:return _error("更新信息过大，已停止处理。","body_limit")
	var json:JSON=JSON.new()
	if json.parse(body)!=OK or not json.data is Dictionary:return _error("更新信息格式不正确，请稍后重试。","json")
	var release:Dictionary=json.data
	if not release.get("draft") is bool or not release.get("prerelease") is bool:
		return _error("更新信息缺少正式发布状态。","schema")
	if release.draft or release.prerelease:return _error("当前没有可用的正式更新。","not_stable")
	if not release.get("tag_name") is String:return _error("更新版本号无效。","version")
	var tag:String=release.tag_name
	var version:String=_release_version(tag)
	var installed:String=normalize_version(current_version if not current_version.is_empty() else str(ProjectSettings.get_setting("application/config/version","")))
	if version.is_empty() or installed.is_empty():return _error("更新版本号无效。","version")
	if compare_versions(version,installed)<=0:
		return {"status":"current","version":installed,"latest_version":version,"notes":"","url":"","message":"当前已是最新版本。"}
	var assets:Variant=release.get("assets",[])
	if not assets is Array:return _error("更新附件信息无效。","schema")
	var expected_name:String="StarLanternIsland-v%s-arm64.apk"%version
	var expected_url:String=RELEASE_ROOT+"/download/"+tag+"/"+expected_name
	var download_url:String=""
	if target_platform=="Android":
		for asset:Variant in assets:
			if not asset is Dictionary:continue
			if asset.get("name")!=expected_name:continue
			if not download_url.is_empty():return _error("更新附件重复，已停止处理。","asset")
			if asset.has("state") and asset.state!="uploaded":continue
			if not asset.get("browser_download_url") is String or asset.browser_download_url!=expected_url:
				return _error("更新链接未通过验证，请稍后重试。","url")
			if not is_allowed_url(expected_url):return _error("更新链接未通过验证。","url")
			download_url=expected_url
	var kind:String="apk"
	if download_url.is_empty():
		var page:String=RELEASE_ROOT+"/tag/"+tag
		if release.get("html_url")!=page or not is_allowed_url(page):return _error("发布页面链接未通过验证。","url")
		download_url=page;kind="release"
	var notes:String=release.body if release.get("body") is String else ""
	if notes.length()>MAX_NOTES:notes=notes.left(MAX_NOTES)+"\n…"
	return {"status":"update","version":version,"latest_version":version,"tag":tag,
		"notes":notes,"url":download_url,"asset_kind":kind,"message":"发现新版本 "+version+"。"}

static func _error(message:String,code:String)->Dictionary:
	return {"status":"error","version":"","notes":"","url":"","message":message,"error_code":code}

static func _digits(value:String)->bool:
	if value.is_empty():return false
	for index:int in range(value.length()):
		var code:int=value.unicode_at(index)
		if code<48 or code>57:return false
	return true

static func normalize_version(value:String)->String:
	if value!=value.strip_edges() or value.length()>128:return ""
	var base:String=value
	if base.begins_with("v") or base.begins_with("V"):base=base.substr(1)
	base=base.get_slice("+",0).get_slice("-",0)
	var components:PackedStringArray=base.split(".",true)
	if components.size()<1 or components.size()>3:return ""
	var normalized:PackedStringArray=PackedStringArray()
	for component:String in components:
		if not _digits(component):return ""
		while component.length()>1 and component.begins_with("0"):component=component.substr(1)
		normalized.append(component)
	while normalized.size()<3:normalized.append("0")
	return ".".join(normalized)

static func compare_versions(a:String,b:String)->int:
	var first:String=normalize_version(a)
	var second:String=normalize_version(b)
	if first.is_empty() or second.is_empty():return 0
	var left:PackedStringArray=first.split(".")
	var right:PackedStringArray=second.split(".")
	for index:int in range(3):
		# Comparing numeric strings by length avoids integer overflow in metadata.
		if left[index].length()!=right[index].length():return 1 if left[index].length()>right[index].length() else -1
		var order:int=left[index].casecmp_to(right[index])
		if order!=0:return 1 if order>0 else -1
	return 0

static func _release_version(tag:String)->String:
	if tag.length()>96:return ""
	var base:String=tag.substr(1) if tag.begins_with("v") or tag.begins_with("V") else tag
	var parts:PackedStringArray=base.split(".",true)
	if parts.size()!=3:return ""
	for part:String in parts:
		if not _digits(part) or (part.length()>1 and part.begins_with("0")):return ""
	return normalize_version(tag)

static func is_allowed_url(url:String)->bool:
	var page_prefix:String=RELEASE_ROOT+"/tag/"
	if url.begins_with(page_prefix):return not _release_version(url.substr(page_prefix.length())).is_empty()
	var download_prefix:String=RELEASE_ROOT+"/download/"
	if not url.begins_with(download_prefix):return false
	var pieces:PackedStringArray=url.substr(download_prefix.length()).split("/",true)
	if pieces.size()!=2:return false
	var version:String=_release_version(pieces[0])
	return not version.is_empty() and pieces[1]=="StarLanternIsland-v%s-arm64.apk"%version

func _exit_tree()->void:
	checking=false
	if is_instance_valid(http):http.cancel_request()
