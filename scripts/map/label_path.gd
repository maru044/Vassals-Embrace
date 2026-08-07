class_name LabelPath
## 区域脊线曲线：从区域顶点（世界 XZ）计算脊柱曲线。
## 方法：横向扫掠（按 x 分箱取 z 中心，沿地图短边 x）→ 中心线平滑 → 均匀三次 B 样条（控制点近似曲线，NURBS 感，圆润不过点）。
## 返回：{ points: PackedVector3Array(世界坐标脊线采样点), length: float(脊线长度) }

const SWEEP_BINS := 14
const SAMPLES_PER_SEG := 8


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
	if span < 0.01:
		return {"points": PackedVector3Array([centroid]), "length": 0.0}

	# 横向扫掠中心线（每 bin 取 z 中心，沿地图短边 x）
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

	# 中心线 z 平滑（减少折线/形变）
	ctrl = _smooth_ctrl(ctrl)

	# 均匀三次 B 样条采样（控制点近似曲线，不通过点，圆润）
	var points := PackedVector3Array()
	if ctrl.size() >= 4:
		for i in ctrl.size() - 3:
			var p0: Vector3 = ctrl[i]
			var p1: Vector3 = ctrl[i + 1]
			var p2: Vector3 = ctrl[i + 2]
			var p3: Vector3 = ctrl[i + 3]
			# 最后一段采到 t=1（曲线真实终点），保证末端平滑、切线自然。
			# 不再硬接控制点（旧代码 append ctrl[n-2]/ctrl[n-1] 会产生末端折角，
			# 导致落在末段的字符（最后一个字）切线突变而"歪脖子"）。
			var segs := SAMPLES_PER_SEG + 1 if i == ctrl.size() - 4 else SAMPLES_PER_SEG
			for s in segs:
				var t := float(s) / float(SAMPLES_PER_SEG)
				points.append(_bspline(p0, p1, p2, p3, t))
	else:
		for p in ctrl:
			points.append(p as Vector3)

	# 脊线长度
	var length := 0.0
	for i in points.size() - 1:
		length += points[i].distance_to(points[i + 1])
	return {"points": points, "length": length}


static func _smooth_ctrl(ctrl: Array) -> Array:
	if ctrl.size() < 4:
		return ctrl
	var out: Array = [ctrl[0]]
	for i in range(1, ctrl.size() - 1):
		var p0: Vector3 = ctrl[i - 1]
		var p1: Vector3 = ctrl[i]
		var p2: Vector3 = ctrl[i + 1]
		out.append(Vector3(p1.x, 0.0, (p0.z + p1.z * 2.0 + p2.z) * 0.25))
	out.append(ctrl[ctrl.size() - 1])
	return out


static func _bspline(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	# 均匀三次 B 样条基函数（控制点近似）
	var t2 := t * t
	var t3 := t2 * t
	return (1.0 / 6.0) * (
		(1.0 - 3.0 * t + 3.0 * t2 - t3) * p0 +
		(4.0 - 6.0 * t2 + 3.0 * t3) * p1 +
		(1.0 + 3.0 * t + 3.0 * t2 - 3.0 * t3) * p2 +
		t3 * p3
	)
