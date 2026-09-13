extends RefCounted
# Procedural art shared by every combat effect. Each texture is drawn once per
# process and reused, so the game ships no sprite sheets and still avoids the
# flat coloured cards that made hits look like floating bubbles.

static var star_image: Texture2D
static var flame_image: Texture2D
static var smoke_image: Texture2D
static var streak_image: Texture2D
static var hole_image: Texture2D

static func noise(x: float, y: float) -> float:
	# Cheap deterministic hash: enough to break up silhouettes that are otherwise
	# perfect circles, which is exactly what reads as a bubble.
	return fposmod(sin(x * 12.9898 + y * 78.233) * 43758.5453, 1.0)

static func flame_texture() -> Texture2D:
	# A flame tongue: hot white root, orange licking tip, pointing towards +V so a
	# velocity-aligned particle shoots it along its own direction of travel.
	if flame_image: return flame_image
	var width := 64
	var height := 128
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		var along := float(y) / (height - 1)
		# Widest just behind the root, tapering to a thin flickering tip.
		var span := pow(1.0 - along, .55) * (.18 + .30 * sin(along * PI * .85))
		span *= 1.0 + .22 * sin(along * 17.0) + .12 * noise(along * 31.0, 3.7)
		for x in width:
			var across := absf(float(x) / (width - 1) - .5) * 2.0
			var body := 0.0 if span <= 0.0 else maxf(0.0, 1.0 - across / span)
			var heat := clampf(pow(body, .7) * (1.0 - along * .75), 0.0, 1.0)
			var tint := Color("ff5a08").lerp(Color("fff4d2"), heat)
			tint.a = clampf(pow(body, 1.6) * (1.0 - pow(along, 2.2)), 0.0, 1.0)
			image.set_pixel(x, y, tint)
	flame_image = ImageTexture.create_from_image(image)
	return flame_image

static func star_texture() -> Texture2D:
	# The head-on pop of a muzzle flash: five-lobed star around a white hot core.
	if star_image: return star_image
	var size := 96
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := (size - 1) * .5
	for y in size:
		for x in size:
			var offset := Vector2(x - center, y - center) / center
			var radius := offset.length()
			var lobe := .34 + .66 * pow(absf(cos(offset.angle() * 2.5)), 1.4)
			var star := maxf(0.0, 1.0 - radius / lobe)
			var core := maxf(0.0, 1.0 - radius / .30)
			var heat := clampf(pow(core, .75) + pow(star, 3.0) * .35, 0.0, 1.0)
			var tint := Color("ff6a12").lerp(Color("fff6da"), heat)
			tint.a = clampf(pow(star, 2.2) * .85 + pow(core, 2.4), 0.0, 1.0)
			image.set_pixel(x, y, tint)
	star_image = ImageTexture.create_from_image(image)
	return star_image

static func star_mesh(size: float) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = particle_material(star_texture(), true, false)
	return quad

static func smoke_texture() -> Texture2D:
	# Torn, uneven puff. The rim is pushed around by noise so overlapping particles
	# read as one ragged cloud instead of a stack of soap bubbles.
	if smoke_image: return smoke_image
	var size := 96
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := (size - 1) * .5
	for y in size:
		for x in size:
			var offset := Vector2(x - center, y - center) / center
			var angle := offset.angle()
			var rim := .52 + .16 * sin(angle * 3.0 + 1.7) + .12 * sin(angle * 7.0) + .10 * noise(angle * 9.0, 5.1)
			var falloff := maxf(0.0, 1.0 - offset.length() / rim)
			var body := pow(falloff, 1.5) * (.72 + .28 * noise(x * .21, y * .19))
			image.set_pixel(x, y, Color(1, 1, 1, clampf(body, 0.0, 1.0)))
	smoke_image = ImageTexture.create_from_image(image)
	return smoke_image

static func streak_texture() -> Texture2D:
	# Tracer and spark body: a bright head at +V fading into a thin tail, meant for
	# a quad that is stretched along its travel direction.
	if streak_image: return streak_image
	var width := 32
	var height := 128
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		var along := float(y) / (height - 1)
		var head := pow(1.0 - along, 1.8)
		var thickness := .16 + .40 * head
		for x in width:
			var across := absf(float(x) / (width - 1) - .5) * 2.0
			var body := maxf(0.0, 1.0 - across / thickness)
			var core := pow(body, 4.0)
			var tint := Color("ff9a2e").lerp(Color("fffbe8"), clampf(core + head * .5, 0.0, 1.0))
			tint.a = clampf(pow(body, 2.0) * (.18 + .82 * head), 0.0, 1.0)
			image.set_pixel(x, y, tint)
	streak_image = ImageTexture.create_from_image(image)
	return streak_image

static func bullet_hole_texture() -> Texture2D:
	# Punched hole with a bright dust rim and a few radial cracks, so a hit leaves
	# something readable on concrete even in the dark rooms.
	if hole_image: return hole_image
	var size := 96
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := (size - 1) * .5
	for y in size:
		for x in size:
			var offset := Vector2(x - center, y - center) / center
			var angle := offset.angle()
			var wobble := .045 * sin(angle * 3.0 + 1.1) + .035 * sin(angle * 7.0 + 2.6) + .05 * noise(angle * 21.0, 1.3)
			var radius := offset.length() * (1.0 + wobble)
			var tint := Color(0.05, 0.045, 0.04)
			var alpha := 0.0
			if radius < .24:
				alpha = 1.0
			elif radius < .46:
				# Crushed lip around the hole: bright dust catching the room light.
				var lip := (radius - .24) / .22
				tint = Color(0.05, 0.045, 0.04).lerp(Color(0.58, 0.56, 0.53), pow(lip, .55))
				alpha = 1.0 - pow(lip, 2.0) * .40
			elif radius < .92:
				# Scattered dust and hairline cracks thrown outwards from the impact.
				var fade := 1.0 - (radius - .46) / .46
				var crack := pow(absf(sin(angle * 6.0 + noise(angle, .4) * 3.0)), 9.0)
				tint = Color(0.48, 0.47, 0.45)
				alpha = fade * (.16 + .55 * crack) * (.55 + .45 * noise(x * .3, y * .3))
			tint.a = clampf(alpha, 0.0, 1.0)
			image.set_pixel(x, y, tint)
	hole_image = ImageTexture.create_from_image(image)
	return hole_image

static func particle_material(texture: Texture2D, additive: bool, align_to_velocity: bool) -> StandardMaterial3D:
	var fx := StandardMaterial3D.new()
	fx.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fx.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fx.cull_mode = BaseMaterial3D.CULL_DISABLED
	fx.albedo_texture = texture
	fx.vertex_color_use_as_albedo = true
	fx.disable_receive_shadows = true
	if additive: fx.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	# Round art may billboard freely. Velocity-aligned art must not: billboarding
	# would throw away the direction of travel that makes it read as a streak.
	if !align_to_velocity:
		fx.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		fx.billboard_keep_scale = true
	return fx

static func cross_mesh(width: float, length: float, texture: Texture2D, additive: bool) -> ArrayMesh:
	# Two quads crossed around the local Y axis. Combined with align_y particles it
	# gives a streak that keeps its travel direction and still has a visible face
	# from almost any camera angle — the cheap stand-in for a stretched billboard.
	var half_width := width * .5
	var half_length := length * .5
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for plane in 2:
		var side := Vector3(half_width, 0, 0) if plane == 0 else Vector3(0, 0, half_width)
		var facing := Vector3(0, 0, 1) if plane == 0 else Vector3(1, 0, 0)
		var top := Vector3(0, half_length, 0)
		vertices.append_array([-side + top, side + top, side - top, -side - top])
		uvs.append_array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		for corner in 4: normals.append(facing)
		var base := plane * 4
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, particle_material(texture, additive, true))
	return mesh

static func streak_mesh(width: float, length: float) -> ArrayMesh:
	return cross_mesh(width, length, streak_texture(), true)

static func flame_mesh(width: float, length: float) -> ArrayMesh:
	return cross_mesh(width, length, flame_texture(), true)

static func smoke_mesh(size: float) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = particle_material(smoke_texture(), false, false)
	return quad

static func fade_curve(from: float, to: float) -> Curve:
	var curve := Curve.new()
	curve.min_value = minf(from, to)
	curve.max_value = maxf(from, to)
	curve.add_point(Vector2(0, from))
	curve.add_point(Vector2(1, to))
	return curve

static func alpha_ramp(from: Color, to: Color) -> Gradient:
	var ramp := Gradient.new()
	ramp.set_color(0, from)
	ramp.set_color(1, to)
	return ramp

static func aim_basis(direction: Vector3) -> Basis:
	# Maps the local +Y of a stretched quad onto `direction`.
	var up := Vector3.UP if absf(direction.normalized().y) < .95 else Vector3.FORWARD
	return Basis.looking_at(direction, up) * Basis.from_euler(Vector3(-PI * .5, 0, 0))

static func surface_basis(normal: Vector3) -> Basis:
	# Maps the local +Z of a flat quad onto `normal`, for decals lying on a wall.
	var up := Vector3.UP if absf(normal.normalized().y) < .95 else Vector3.FORWARD
	return Basis.looking_at(-normal, up)
