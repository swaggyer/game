extends "res://scripts/area_map_v11.gd"
## Terrain stays retained; map markers do not need the combat frame rate.
var _marker_elapsed:=0.0
var _fit_size:=Vector2(-1,-1)
var _fit_bounds:=Rect2()
var _fit_expanded:=false
var _fitted_rect:=Rect2()

func _process(delta:float)->void:
	if not is_visible_in_tree():return
	_marker_elapsed+=delta
	if _marker_elapsed<1.0/15.0:return
	_marker_elapsed=fmod(_marker_elapsed,1.0/15.0)
	super._process(delta)

func _map_rect()->Rect2:
	if size!=_fit_size or bounds!=_fit_bounds or expanded!=_fit_expanded:
		_fit_size=size;_fit_bounds=bounds;_fit_expanded=expanded
		_fitted_rect=super._map_rect()
	return _fitted_rect
