class_name LabelPath
## 区域脊线曲线：从区域顶点（世界 XZ）计算脊柱曲线。
## 方法：最左端→质心→最右端 + 横向扫掠（按 x 分箱取 z 中心）→ Catmull-Rom 样条平滑。
## 返回：{ points: PackedVector3Array(世界坐标脊线采样点), length: float(脊线长度) }

const SWEEP_BINS := 16
const SAMPLES_PER_SEG := 6


static func compute_spine(verts: PackedVector3Array) -> Dictionary:
	if verts.size() < 3:
		return {"points": PackedVector3Array(), "length": 0.0}

	var xmin := INF
	var xmax := -INF
	var centroid := Vector3.ZERO
	for v in verts:
		xmin = minf(xmin, v.x)
		xmax = maxf(xmax, v.x)
		centroid += v
	centroid /= float(verts.size())

	var span := xmax - xmin
	if span < 0.001:
		return {"points": PackedVector3Array([centroid]), "length": 0.0}

	# 横向扫掠中心线（每 bin 取 z 中心）
	var ctrl: Array = []
	var bin_w := span / float(SWEEP_BINS)
	for i in SWEEP_BINS + 1:
		var bx := xmin + bin_w * float(i)
		var sum_z := 0.0
		var count := 0
		for v in verts:
			if v.x >= bx - bin_w * 0.5 and v.x <= bx + bin_w * 0.5:
				sum_z += v.z
				count += 1
		if count > 0:
			ctrl.append(Vector3(bx, 0.0, sum_z / float(count)))
	if ctrl.size() < 2:
		ctrl.append(centroid)

	# Catmull-Rom 样条采样
	var points := PackedVector3Array()
	for i in ctrl.size() - 1:
		var p0: Vector3 = ctrl[maxi(i - 1, 0)]
		var p1: Vector3 = ctrl[i]
		var p2: Vector3 = ctrl[i + 1]
		var p3: Vector3 = ctrl[mini(i + 2, ctrl.size() - 1)]
		for s in SAMPLES_PER_SEG:
			var t := float(s) / float(SAMPLES_PER_SEG)
			points.append(_catmull(p0, p1, p2, p3, t))
	points.append(ctrl[ctrl.size() - 1] as Vector3)

	# 脊线长度
	var length := 0.0
	for i in points.size() - 1:
		length += points[i].distance_to(points[i + 1])
	return {"points": points, "length": length}


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		(2.0 * p1) +
		(-p0 + p2) * t +
		(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
		(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)
