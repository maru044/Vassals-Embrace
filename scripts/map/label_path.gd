class_name LabelPath
## 区域脊线曲线：从区域顶点（世界 XZ）计算脊柱曲线。
## 方法：仅用 3 个控制点（最左端 → 质心 → 最右端）生成二次贝塞尔单弧线，
## 圆润自然、不过点，无多余弯折（Master 定：单弧线，不要十几二十个控制点）。
## 返回：{ points: PackedVector3Array(世界坐标脊线采样点), length: float(脊线长度), ctrl: Array(3个控制点) }

const SPINE_SAMPLES := 24   # 二次贝塞尔采样密度


static func compute_spine(verts: PackedVector3Array) -> Dictionary:
	if verts.size() < 3:
		return {"points": PackedVector3Array(), "length": 0.0, "ctrl": []}
	var xmin := INF
	var xmax := -INF
	var sum := Vector3.ZERO
	for v in verts:
		xmin = minf(xmin, v.x)
		xmax = maxf(xmax, v.x)
		sum += v
	var centroid: Vector3 = sum / float(verts.size())
	if xmax - xmin < 0.01:
		return {"points": PackedVector3Array([centroid]), "length": 0.0, "ctrl": []}
	# 最左 / 最右 10% 条带的中心（贴合区域两端）
	var band := (xmax - xmin) * 0.1
	var start := _band_center(verts, xmin, xmin + band)
	var end := _band_center(verts, xmax - band, xmax)
	# 二次贝塞尔：3 控制点 = 起点 / 质心 / 终点 → 单弧线
	var ctrl: Array = [start, centroid, end]
	var points := PackedVector3Array()
	for i in SPINE_SAMPLES + 1:
		var t := float(i) / float(SPINE_SAMPLES)
		points.append(_bezier2(start, centroid, end, t))
	# 脊线长度
	var length := 0.0
	for i in points.size() - 1:
		length += points[i].distance_to(points[i + 1])
	return {"points": points, "length": length, "ctrl": ctrl}


## 取 x 落在 [lo, hi] 条带内的顶点平均位置（区域端部的代表点）。
static func _band_center(verts: PackedVector3Array, lo: float, hi: float) -> Vector3:
	var s := Vector3.ZERO
	var n := 0
	for v in verts:
		if v.x >= lo and v.x <= hi:
			s += v
			n += 1
	if n > 0:
		return s / float(n)
	return (verts[0] + verts[verts.size() - 1]) * 0.5


## 二次贝塞尔：3 控制点单弧线（不通过控制点，圆润）。
static func _bezier2(p0: Vector3, p1: Vector3, p2: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return u * u * p0 + 2.0 * u * t * p1 + t * t * p2
