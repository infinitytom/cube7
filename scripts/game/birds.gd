class_name Birds
extends Node3D
## 远处成群盘旋的白色小鸟（像海鸥一样拍几下翅膀、滑翔一阵）。MultiMesh 一次画完。

var center := Vector3.ZERO
var radius := 40.0
var count := 7
var seed_v := 1
var speed := 0.12

var _mm: MultiMeshInstance3D
var _offs: Array[Vector3] = []
var _phase: Array[float] = []
var _t := 0.0

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 color : source_color = vec3(1.0, 1.0, 1.0);
void vertex() {
	float ph = INSTANCE_CUSTOM.x * 6.2831;
	float flap = sin(TIME * 9.0 + ph) * step(0.0, sin(TIME * 0.7 + ph));
	float side = abs(VERTEX.x);
	VERTEX.y += flap * side * 0.8;
}
void fragment() {
	ALBEDO = color;
}
"""

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	# 一只鸟：身体 + 两片折角的翅膀（V 字形）
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [
		[Vector3(0, 0, -0.35), Vector3(-0.2, 0.05, 0.1), Vector3(-1.1, 0.25, 0.25)],
		[Vector3(0, 0, -0.35), Vector3(-1.1, 0.25, 0.25), Vector3(-0.5, 0.1, 0.35)],
		[Vector3(0, 0, -0.35), Vector3(0.2, 0.05, 0.1), Vector3(1.1, 0.25, 0.25)],
		[Vector3(0, 0, -0.35), Vector3(1.1, 0.25, 0.25), Vector3(0.5, 0.1, 0.35)],
		[Vector3(0, 0, -0.45), Vector3(-0.12, 0, 0.4), Vector3(0.12, 0, 0.4)],
	]
	for tri in pts:
		for v in tri:
			st.add_vertex(v)
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	mat.shader = sh
	mesh.surface_set_material(0, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = count
	_mm = MultiMeshInstance3D.new()
	_mm.multimesh = mm
	_mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mm)
	for i in count:
		_offs.append(Vector3(rng.randf_range(-6, 6), rng.randf_range(-2, 2), rng.randf_range(-6, 6)))
		_phase.append(rng.randf())
		mm.set_instance_custom_data(i, Color(_phase[i], 0, 0, 0))
	_t = rng.randf() * 100.0

func _process(delta: float) -> void:
	_t += delta
	var mm := _mm.multimesh
	for i in count:
		var a := _t * speed + _phase[i] * 0.25
		var wob := Vector3(sin(_t * 0.5 + i), sin(_t * 0.8 + i * 2.0) * 0.6, cos(_t * 0.4 + i)) * 1.5
		var p := center + Vector3(cos(a) * radius, sin(a * 0.7) * 4.0, sin(a) * radius) + _offs[i] + wob
		var tangent := Vector3(-sin(a), 0.0, cos(a))
		var b := Basis.looking_at(tangent, Vector3.UP).scaled(Vector3.ONE * 0.55)
		mm.set_instance_transform(i, Transform3D(b, p))
