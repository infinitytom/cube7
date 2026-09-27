class_name Kit
extends RefCounted
## 现成素材（Kenney，CC0）的统一入口：按短名取模型 / 网格。
## 画风：Kenney 新版粉彩配色——薄荷绿草地、珊瑚色泥土、淡紫科技件、阳光黄点缀。

const ROOT := "res://assets/kenney/"

static var _scenes := {}
static var _meshes := {}

static func scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(ROOT + path + ".glb")
	return _scenes[path]

## 实例化一个模型（Node3D）
static func model(path: String) -> Node3D:
	var s := scene(path)
	return s.instantiate() as Node3D if s else Node3D.new()

## 取模型里第一个网格（用于 MultiMesh 批量摆放、金币等）
static func mesh(path: String) -> Mesh:
	if not _meshes.has(path):
		var n := model(path)
		var found: Mesh = null
		for c in n.find_children("*", "MeshInstance3D", true, false):
			found = (c as MeshInstance3D).mesh
			break
		n.free()
		_meshes[path] = found
	return _meshes[path]

## 模型的包围盒（模型自身坐标系）
static func bounds(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var xf := Transform3D()
		var cur: Node = mi
		while cur != n and cur is Node3D:
			xf = (cur as Node3D).transform * xf
			cur = cur.get_parent()
		var b := xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

# 常用素材短名
const TREES := ["platformer/tree", "platformer/tree-pine", "tower-defense/detail-tree-large", "tower-defense/detail-tree"]
const SMALL_TREES := ["platformer/tree-pine-small", "tower-defense/detail-tree"]
const FLOWERS := ["platformer/flowers", "platformer/flowers-tall"]
const PLANTS := ["platformer/plant", "platformer/grass", "platformer/mushrooms"]
const ROCKS := ["platformer/rocks", "platformer/stones", "tower-defense/detail-rocks"]
const COIN := "platformer/coin-gold"
const FLAG := "platformer/flag"
const CRYSTAL := "tower-defense/detail-crystal"
