class_name Dice
## 全局随机判定器（引擎①底座）：统一随机源，供战斗 / 事件 / 聊天 / 选举复用。
## - d10()     → 0~9（战斗士气公式用）
## - d100()    → 0~99（事件权重 / 判定用）
## - chance(p) → 0~1 概率判定
## - range_roll(a, b) → [a, b] 闭区间整数
## 所有引擎共用同一 RandomNumberGenerator，首次调用时随机化。

static var _rng := RandomNumberGenerator.new()
static var _seeded := false


static func _ensure_seed() -> void:
	if not _seeded:
		_seeded = true
		_rng.randomize()


## D10：0~9（战斗公式：伤害 = max(双方总士气) × 0.2 × (1 + 0.1 × d10)）
static func d10() -> int:
	_ensure_seed()
	return _rng.randi_range(0, 9)


## D100：0~99（事件权重、百分比判定）
static func d100() -> int:
	_ensure_seed()
	return _rng.randi_range(0, 99)


## 概率判定：p 为 0~1，返回是否命中
static func chance(p: float) -> bool:
	_ensure_seed()
	return _rng.randf() < p


## 闭区间随机整数 [a, b]
static func range_roll(a: int, b: int) -> int:
	_ensure_seed()
	return _rng.randi_range(a, b)
