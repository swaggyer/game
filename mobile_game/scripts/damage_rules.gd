extends RefCounted
## A landed enemy attack always costs at least a quarter of TEAM MAXIMUM HP.
## Dodge, active protection and the shared grace timer are handled by the scene
## before calling this resolver. Traps and falls use the separate legacy rule.

static func enemy_damage(max_hp:float,base_damage:float,defense:float,difficulty:String,front_guard:bool,shield_upgrade:int=0) -> float:
	var ordinary:float=environment_damage(base_damage,defense,difficulty)
	if front_guard:
		var reduction:float=0.75+0.05*clampi(shield_upgrade,0,3)
		ordinary=maxf(1.0,ceilf(ordinary*(1.0-reduction)))
	var minimum:float=ceilf(maxf(0.0,max_hp)*0.25)
	return maxf(minimum,ordinary)

static func environment_damage(base_damage:float,defense:float,difficulty:String) -> float:
	var multiplier:float=0.65 if difficulty=="gentle" else (0.85 if difficulty=="explorer" else 1.0)
	return maxf(1.0,roundf(base_damage*multiplier)-defense)
