class_name UiStyle
extends RefCounted
## Shared look of the game: black iron, ember orange, dark red borders (same as the main menu).
## Fonts: Cinzel (display, dramatic capitals) and Barlow Condensed (body text).

const MENU_RED := Color(0.62, 0.06, 0.1)
const PANEL_BG := Color(0.05, 0.034, 0.034, 0.94)

static var _cache := {}


static func display_font(weight := 700) -> Font:
	var key := "display%d" % weight
	if _cache.has(key):
		return _cache[key]
	var base = load("res://assets/fonts/Cinzel-Variable.ttf")
	var out: Font = ThemeDB.fallback_font
	if base != null:
		var fv := FontVariation.new()
		fv.base_font = base
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): weight}
		out = fv
	_cache[key] = out
	return out


static func body_font() -> Font:
	if _cache.has("body"):
		return _cache["body"]
	var base = load("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
	var out: Font = base if base != null else ThemeDB.fallback_font
	_cache["body"] = out
	return out


static func box(bg: Color, border: Color, width := 2, margin := 6.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.8)
	sb.shadow_size = 3
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin * 0.7
	sb.content_margin_bottom = margin * 0.7
	return sb


static func panel() -> StyleBoxFlat:
	return box(PANEL_BG, MENU_RED, 3, 9.0)


static func _toggle_icon(on: bool) -> ImageTexture:
	var w := 40
	var h := 20
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var r := h * 0.5
	var knob := Vector2(w - r if on else r, r)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var seg := Vector2(clampf(p.x, r, w - r), r)
			var d := p.distance_to(seg)
			if d > r - 0.5:
				continue
			var col := Color(0.62, 0.27, 0.07) if on else Color(0.09, 0.05, 0.045)
			if d > r - 2.5:
				col = Hud.EMBER if on else MENU_RED
			if p.distance_to(knob) <= r - 4.0:
				col = Color(0.06, 0.02, 0.01) if on else Hud.ORANGE_DIM
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func editor_theme() -> Theme:
	var t := Hud.make_theme()
	var body := body_font()
	var disp := display_font(700)
	t.default_font = body
	t.default_font_size = 17
	for cls in ["Label", "CheckButton", "LineEdit", "SpinBox", "ItemList", "PopupMenu", "RichTextLabel", "TooltipLabel"]:
		t.set_font("font", cls, body)
		t.set_font_size("font_size", cls, 17)
	for cls in ["Button", "OptionButton", "MenuButton"]:
		t.set_font("font", cls, disp)
		t.set_font_size("font_size", cls, 15)
		t.set_color("font_color", cls, Hud.EMBER)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, Color(0.06, 0.02, 0.01))
		t.set_color("font_hover_pressed_color", cls, Color(0.06, 0.02, 0.01))
		t.set_color("font_disabled_color", cls, Color(0.4, 0.3, 0.25))
		t.set_color("font_outline_color", cls, Color(0, 0, 0, 0.9))
		t.set_constant("outline_size", cls, 3)
		t.set_stylebox("normal", cls, box(Color(0.07, 0.05, 0.05, 0.92), MENU_RED, 3, 8.0))
		t.set_stylebox("hover", cls, box(Color(0.2, 0.09, 0.05, 0.95), Hud.EMBER, 3, 8.0))
		t.set_stylebox("pressed", cls, box(Hud.ORANGE, Color(0, 0, 0), 3, 8.0))
		t.set_stylebox("hover_pressed", cls, box(Hud.ORANGE, Color(0, 0, 0), 3, 8.0))
		t.set_stylebox("disabled", cls, box(Color(0.05, 0.04, 0.04, 0.85), Color(0.2, 0.08, 0.08), 3, 8.0))
	t.set_font("bold_font", "RichTextLabel", disp)
	t.set_font("normal_font", "RichTextLabel", body)
	t.set_font_size("normal_font_size", "RichTextLabel", 17)
	t.set_font_size("bold_font_size", "RichTextLabel", 17)
	for cls2 in ["CheckButton"]:
		for st in ["checked", "checked_mirrored"]:
			t.set_icon(st, cls2, _toggle_icon(true))
		for st2 in ["unchecked", "unchecked_mirrored"]:
			t.set_icon(st2, cls2, _toggle_icon(false))
		for st3 in ["checked_disabled", "checked_disabled_mirrored"]:
			t.set_icon(st3, cls2, _toggle_icon(true))
		for st4 in ["unchecked_disabled", "unchecked_disabled_mirrored"]:
			t.set_icon(st4, cls2, _toggle_icon(false))
		t.set_color("font_color", cls2, Hud.AMBER)
	# text fields
	t.set_stylebox("normal", "LineEdit", box(Color(0.03, 0.02, 0.02, 0.95), Hud.ORANGE_DIM, 2, 6.0))
	t.set_stylebox("focus", "LineEdit", box(Color(0.06, 0.035, 0.03, 0.95), Hud.ORANGE, 2, 6.0))
	t.set_stylebox("read_only", "LineEdit", box(Color(0.03, 0.02, 0.02, 0.95), MENU_RED, 2, 6.0))
	t.set_color("font_color", "LineEdit", Hud.EMBER)
	t.set_color("caret_color", "LineEdit", Hud.ORANGE)
	t.set_color("selection_color", "LineEdit", Color(0.95, 0.42, 0.08, 0.45))
	# lists and popup menus
	t.set_stylebox("panel", "ItemList", box(Color(0.03, 0.02, 0.02, 0.95), MENU_RED, 2, 4.0))
	for st5 in ["selected", "selected_focus"]:
		t.set_stylebox(st5, "ItemList", box(Hud.ORANGE_DIM, Hud.ORANGE, 1, 2.0))
	t.set_stylebox("hovered", "ItemList", box(Color(0.2, 0.09, 0.05, 0.9), MENU_RED, 1, 2.0))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	t.set_color("font_color", "ItemList", Hud.AMBER)
	t.set_color("font_hovered_color", "ItemList", Color.WHITE)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_stylebox("panel", "PopupMenu", box(Color(0.04, 0.03, 0.03, 0.98), MENU_RED, 3, 6.0))
	t.set_stylebox("hover", "PopupMenu", box(Hud.ORANGE_DIM, Hud.ORANGE, 1, 3.0))
	t.set_color("font_color", "PopupMenu", Hud.AMBER)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_font("font", "PopupMenu", disp)
	t.set_font_size("font_size", "PopupMenu", 15)
	t.set_stylebox("panel", "TooltipPanel", box(Color(0.04, 0.03, 0.03, 0.98), Hud.ORANGE_DIM, 2, 6.0))
	# sliders, scroll bars, separators
	t.set_stylebox("slider", "HSlider", box(Color(0.03, 0.02, 0.02), MENU_RED, 1, 2.0))
	var gf := StyleBoxFlat.new()
	gf.bg_color = Hud.ORANGE
	gf.set_corner_radius_all(2)
	gf.content_margin_top = 3
	gf.content_margin_bottom = 3
	t.set_stylebox("grabber_area", "HSlider", gf)
	var gh := gf.duplicate()
	gh.bg_color = Hud.EMBER
	t.set_stylebox("grabber_area_highlight", "HSlider", gh)
	for bar in ["VScrollBar", "HScrollBar"]:
		var sbg := StyleBoxFlat.new()
		sbg.bg_color = Color(0.03, 0.02, 0.02)
		t.set_stylebox("scroll", bar, sbg)
		var g1 := StyleBoxFlat.new()
		g1.bg_color = Hud.ORANGE_DIM
		g1.set_corner_radius_all(2)
		t.set_stylebox("grabber", bar, g1)
		var g2 := g1.duplicate()
		g2.bg_color = Hud.ORANGE
		t.set_stylebox("grabber_highlight", bar, g2)
		t.set_stylebox("grabber_pressed", bar, g2)
	for sep in ["HSeparator", "VSeparator"]:
		var ln := StyleBoxLine.new()
		ln.color = MENU_RED
		ln.thickness = 2
		ln.vertical = (sep == "VSeparator")
		t.set_stylebox("separator", sep, ln)
	return t
