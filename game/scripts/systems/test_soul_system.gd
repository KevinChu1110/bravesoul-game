extends SceneTree
## godot --headless -s res://scripts/systems/test_soul_system.gd


func _initialize() -> void:
	var ok := true
	var ss = root.get_node_or_null("SoulSystem")
	var gs = root.get_node_or_null("GameState")
	if ss == null or gs == null:
		push_error("autoload missing")
		quit(1)
		return
	gs.reset_new_game()
	gs.weapon_tier = 2
	gs.weapon_atk = 9
	gs.gold = 500
	gs.soul_vessel = "綠葫蘆"
	gs.soul_free_draws = 1
	gs.soul_free_day = ss.today_key()
	ss.ensure_slots()
	if ss.slot_count() != 1:
		push_error("tier2 should have 1 slot got %d" % ss.slot_count())
		ok = false
	else:
		print("slots OK")

	var starter: Dictionary = ss.grant_starter_soul()
	if starter.is_empty():
		push_error("starter empty")
		ok = false
	var b: Dictionary = ss.total_equipped_bonus()
	if int(b.get("atk", 0)) < 1:
		push_error("starter should give atk")
		ok = false
	else:
		print("starter equip OK atk+", b.get("atk"))

	## 免費抽一次
	var before_free: int = int(gs.soul_free_draws)
	var rolled: Dictionary = ss.ritual()
	if rolled.is_empty() or int(gs.soul_free_draws) != before_free - 1:
		push_error("free ritual fail free=%s soul=%s" % [gs.soul_free_draws, rolled])
		ok = false
	else:
		print("free ritual OK ", ss.soul_display(rolled), " vessel=", gs.soul_vessel)

	## 付費抽：無免費時扣金
	gs.soul_free_draws = 0
	var cost: int = ss.vessel_cost()
	var gold0: int = int(gs.gold)
	var paid: Dictionary = ss.ritual()
	if paid.is_empty() or int(gs.gold) != gold0 - cost:
		push_error("paid ritual fail gold %s→%s cost %s" % [gold0, gs.gold, cost])
		ok = false
	else:
		print("paid ritual OK -%d gold vessel=%s" % [cost, gs.soul_vessel])

	## ×10：有錢就能連抽；錢不夠就停
	gs.soul_free_draws = 0
	gs.soul_vessel = "綠葫蘆"
	gs.gold = ss.vessel_cost() * 10
	if not ss.can_ritual_batch(10):
		push_error("should afford x10")
		ok = false
	var bag0: int = gs.souls.size()
	var batch: Array = ss.ritual_batch(10)
	if batch.size() < 1:
		push_error("x10 empty")
		ok = false
	elif gs.souls.size() != bag0 + batch.size():
		push_error("x10 bag mismatch")
		ok = false
	else:
		print("x10 OK n=%d gold_left=%d vessel=%s" % [batch.size(), gs.gold, gs.soul_vessel])
	gs.gold = 0
	gs.soul_free_draws = 0
	if ss.can_ritual_batch(10):
		push_error("x10 should deny empty gold")
		ok = false

	## 橙葫蘆 100% 神 → 必摔綠
	gs.soul_vessel = "橙葫蘆"
	gs.soul_free_draws = 1
	gs.gold = 5000
	var orange: Dictionary = ss.ritual()
	if str(orange.get("quality", "")) != "神" or str(gs.soul_vessel) != "綠葫蘆":
		push_error("orange should yield 神 and reset green got q=%s v=%s" % [
			orange.get("quality"), gs.soul_vessel
		])
		ok = false
	else:
		print("orange jackpot reset OK ", ss.soul_display(orange))

	## 合成：塞 3 顆同款
	gs.souls = []
	gs.soul_slots = [""]
	for i in 3:
		gs.souls.append({
			"id": "t%d" % i, "star": "破軍", "quality": "凡", "level": 0, "equipped": false
		})
	var fused: Dictionary = ss.fuse("破軍", "凡", 0)
	if fused.is_empty() or int(fused.get("level", -1)) != 1:
		push_error("fuse fail")
		ok = false
	else:
		print("fuse OK ", ss.soul_display(fused), " bag=", ss.bag_souls().size())

	gs.weapon_tier = 6
	ss.ensure_slots()
	if ss.slot_count() != 2:
		push_error("tier6 slots")
		ok = false
	else:
		print("tier6 slots OK")

	if ss.STARS.size() < 14:
		push_error("need 14 stars got %d" % ss.STARS.size())
		ok = false
	else:
		print("fourteen stars OK")

	## 神魂＝神品質戰魂，最高 10 級（聚俠網）；凡品仍 3 階
	if ss.fuse_max_level("凡") != 3 or ss.fuse_max_level("神") != 10:
		push_error("fuse cap 凡/神")
		ok = false
	else:
		print("shen cap 10 OK")
	gs.souls = []
	gs.soul_slots = [""]
	for i in 3:
		gs.souls.append({
			"id": "s%d" % i, "star": "天機", "quality": "神", "level": 9, "equipped": false
		})
	if not ss.can_fuse("天機", "神", 9):
		push_error("神 lv9 should fuse to 10")
		ok = false
	var shen: Dictionary = ss.fuse("天機", "神", 9)
	if shen.is_empty() or int(shen.get("level", 0)) != 10:
		push_error("神 fuse to 10 fail %s" % shen)
		ok = false
	elif ss.can_fuse("天機", "神", 10):
		push_error("神 should stop at 10")
		ok = false
	else:
		print("shen lv10 OK ", ss.soul_display(shen))

	## 入魂對比：空槽應顯示從 0 起的增減
	gs.souls = [{
		"id": "cmp1", "star": "破軍", "quality": "凡", "level": 0, "equipped": false
	}]
	gs.soul_slots = [""]
	var cmp: Dictionary = ss.compare_embed("cmp1", 0)
	if str(cmp.get("line", "")).find("槽1") < 0:
		push_error("compare line missing slot %s" % cmp)
		ok = false
	else:
		print("embed compare OK ", cmp.get("line"))

	if ok:
		print("SOUL_OK")
		quit(0)
	else:
		print("SOUL_FAIL")
		quit(1)
