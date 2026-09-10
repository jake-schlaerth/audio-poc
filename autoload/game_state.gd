extends Node

const MAX_SKILL_TIER: int = 7
const SKILL_COST_BASE: int = 10
const SKILL_COST_SCALE: int = 25

const MAX_AUTO_TIER: int = 6
const AUTO_COST_BASE: int = 50
const AUTO_COST_SCALE: int = 25

var points: int = 0
var skill_tier: int = 0
var auto_tier: int = 0


func click_value() -> int:
	var value: int = 1
	for _i: int in skill_tier:
		value *= 10
	return value


func next_skill_multiplier() -> int:
	var value: int = 10
	for _i: int in skill_tier:
		value *= 10
	return value


func next_skill_cost() -> int:
	var cost: int = SKILL_COST_BASE
	for _i: int in skill_tier:
		cost *= SKILL_COST_SCALE
	return cost


func can_buy_skill() -> bool:
	return skill_tier < MAX_SKILL_TIER and points >= next_skill_cost()


func buy_skill() -> bool:
	if not can_buy_skill():
		return false
	points -= next_skill_cost()
	skill_tier += 1
	return true


func auto_unlocked() -> bool:
	return auto_tier > 0


func auto_interval() -> float:
	return maxf(3.5 * pow(0.78, float(auto_tier - 1)), 0.45)


func auto_value() -> int:
	return maxi(click_value() * auto_tier, 1)


func next_auto_cost() -> int:
	var cost: int = AUTO_COST_BASE
	for _i: int in auto_tier:
		cost *= AUTO_COST_SCALE
	return cost


func can_buy_auto() -> bool:
	return auto_tier < MAX_AUTO_TIER and points >= next_auto_cost()


func buy_auto() -> bool:
	if not can_buy_auto():
		return false
	points -= next_auto_cost()
	auto_tier += 1
	return true


func format_number(value: int) -> String:
	var digits: String = str(absi(value))
	var grouped: String = ""
	var seen: int = 0
	for index: int in range(digits.length() - 1, -1, -1):
		grouped = digits[index] + grouped
		seen += 1
		if seen % 3 == 0 and index > 0:
			grouped = "," + grouped
	return "-" + grouped if value < 0 else grouped
