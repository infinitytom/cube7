class_name LevelHub
extends Node
## GitHub 关卡库：玩家做的关卡存在一个 GitHub 仓库的 levels/ 目录里，每关一个文件。
##   文件名 = 关卡内容指纹（SHA-256 前 16 位，不含关卡名）.txt，内容 = 分享码（CUBE7:...）
##   → 同样的关卡不管改成什么名字，文件名都一样：上传前先查一下这个文件在不在，在就是重复，不再上传。
## 读取（浏览关卡库）是公开的，不需要登录；上传需要一个对这个仓库有写权限的 GitHub 令牌（在编辑器菜单里从剪贴板粘贴）。
## 没有令牌也行：打开浏览器，在 GitHub 网页上提交（仓库主人合并后就进库）。

const DEFAULT_REPO := "degnrui/cube7-levels"
const BRANCH := "main"
const FOLDER := "levels"
const CFG := "user://github.cfg"
const LIST_MAX := 30

var repo := DEFAULT_REPO
var token := ""
var api := "https://api.github.com"     ## 测试时可以指到本地假服务器

func _ready() -> void:
	var c := ConfigFile.new()
	if c.load(CFG) == OK:
		repo = str(c.get_value("github", "repo", DEFAULT_REPO))
		token = str(c.get_value("github", "token", ""))
		api = str(c.get_value("github", "api", api))

func save_cfg() -> void:
	var c := ConfigFile.new()
	c.set_value("github", "repo", repo)
	c.set_value("github", "token", token)
	if api != "https://api.github.com":
		c.set_value("github", "api", api)
	c.save(CFG)

## "owner/name" 或 GitHub 网址都认
static func parse_repo(text: String) -> String:
	var t := text.strip_edges().trim_suffix("/").trim_suffix(".git")
	var i := t.find("github.com/")
	if i >= 0:
		t = t.substr(i + 11)
	var parts := t.split("/", false)
	if parts.size() < 2:
		return ""
	var re := RegEx.create_from_string("^[A-Za-z0-9_.-]+$")
	if re.search(parts[0]) == null or re.search(parts[1]) == null:
		return ""
	return parts[0] + "/" + parts[1]

static func file_name(d: LevelData) -> String:
	return d.content_hash().left(16) + ".txt"

func _headers(auth: bool) -> PackedStringArray:
	var h := PackedStringArray(["User-Agent: Cube7-Game", "Accept: application/vnd.github+json", "X-GitHub-Api-Version: 2022-11-28"])
	if auth and token != "":
		h.append("Authorization: Bearer " + token)
	return h

## 返回 [网络结果, HTTP 状态码, 正文字符串]
func _req(url: String, method := HTTPClient.METHOD_GET, body := "", auth := true) -> Array:
	var r := HTTPRequest.new()
	r.timeout = 20.0
	add_child(r)
	var err := r.request(url, _headers(auth), method, body)
	if err != OK:
		r.queue_free()
		return [err, 0, ""]
	var res: Array = await r.request_completed
	r.queue_free()
	return [res[0], res[1], (res[3] as PackedByteArray).get_string_from_utf8()]

func _path_url(name: String) -> String:
	return "%s/repos/%s/contents/%s/%s" % [api, repo, FOLDER, name]

## 这一关在库里有没有：1 有（重复）、0 没有、-1 查不了（网络 / 仓库不存在）
func exists(d: LevelData) -> int:
	var r := await _req(_path_url(file_name(d)) + "?ref=" + BRANCH)
	if r[0] != HTTPRequest.RESULT_SUCCESS:
		return -1
	if r[1] == 200:
		return 1
	if r[1] == 404:
		# 404 可能是“文件不存在”，也可能是“仓库不存在”：看一下仓库本身
		var rr := await _req("%s/repos/%s" % [api, repo])
		return 0 if rr[0] == HTTPRequest.RESULT_SUCCESS and rr[1] == 200 else -1
	return -1

## 上传。返回 {"status": "ok"/"duplicate"/"need_token"/"error", "msg": String}
func upload(d: LevelData) -> Dictionary:
	var e := await exists(d)
	if e == 1:
		return {"status": "duplicate", "msg": "关卡库里已经有一模一样的关卡了（%s），不重复上传" % file_name(d)}
	if e == -1:
		return {"status": "error", "msg": "连不上关卡库 %s（检查网络，或仓库是否存在）" % repo}
	if token == "":
		return {"status": "need_token", "msg": "还没有设置 GitHub 令牌"}
	var body := JSON.stringify({
		"message": "新关卡：%s" % d.name,
		"content": Marshalls.utf8_to_base64(d.share_code()),
		"branch": BRANCH,
	})
	var r := await _req(_path_url(file_name(d)), HTTPClient.METHOD_PUT, body)
	if r[0] == HTTPRequest.RESULT_SUCCESS and (r[1] == 201 or r[1] == 200):
		return {"status": "ok", "msg": "已上传到 %s：%s" % [repo, d.name]}
	if r[1] == 422:
		return {"status": "duplicate", "msg": "关卡库里已经有一模一样的关卡了"}
	if r[1] == 401 or r[1] == 403:
		return {"status": "error", "msg": "令牌没有这个仓库的写权限（HTTP %d）" % r[1]}
	return {"status": "error", "msg": "上传失败（HTTP %d）" % r[1]}

## 没有令牌时：在浏览器里打开 GitHub 的“新建文件”页面，内容已经填好，点提交就行
func browser_submit_url(d: LevelData) -> String:
	return "https://github.com/%s/new/%s/%s?filename=%s&value=%s" % [repo, BRANCH, FOLDER, file_name(d), d.share_code().uri_encode()]

## 浏览关卡库：返回 [{"name": String, "file": String, "data": LevelData}]，最新的在前面没法保证，按文件名排序
func list_levels() -> Dictionary:
	var r := await _req("%s/repos/%s/contents/%s?ref=%s" % [api, repo, FOLDER, BRANCH])
	if r[0] != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "msg": "连不上关卡库（网络）", "levels": []}
	if r[1] == 404:
		return {"ok": true, "msg": "关卡库还是空的", "levels": []}
	if r[1] != 200:
		return {"ok": false, "msg": "读取关卡库失败（HTTP %d）" % r[1], "levels": []}
	var items = JSON.parse_string(r[2])
	if not (items is Array):
		return {"ok": false, "msg": "关卡库的格式不对", "levels": []}
	var out: Array = []
	var seen := {}
	for it in items:
		if out.size() >= LIST_MAX:
			break
		if not (it is Dictionary) or not str(it.get("name", "")).ends_with(".txt"):
			continue
		var url := str(it.get("download_url", ""))
		if url == "":
			continue
		var rr := await _req(url, HTTPClient.METHOD_GET, "", false)
		if rr[0] != HTTPRequest.RESULT_SUCCESS or rr[1] != 200:
			continue
		var d := LevelData.from_share_code(rr[2])
		if d == null:
			continue
		# 库里万一有内容重复的（比如网页上手动提交的），只列一次
		var h := d.content_hash()
		if seen.has(h):
			continue
		seen[h] = true
		out.append({"name": d.name, "file": str(it.name), "data": d})
	return {"ok": true, "msg": "" if not out.is_empty() else "关卡库还是空的", "levels": out}
