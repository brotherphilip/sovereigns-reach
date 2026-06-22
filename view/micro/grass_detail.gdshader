shader_type canvas_item;
render_mode blend_mul;
// Multiplies fine GRASS-BLADE detail onto the flat terrain tiles drawn underneath, so the
// ground reads as real textured turf instead of a solid colour — while the base tile keeps
// carrying the season/biome TINT (multiply preserves hue). Sampled by WORLD position so the
// texture flows continuously across tiles (seams only at the texture's repeat, not per-tile).
//
// iter322: the blade texture alone was UNIFORM — every green tile got the identical pattern,
// so a wide field read as a flat paint-bucket carpet (the loop's most-cited "lifeless ground"
// note). This adds the missing MACRO variation, all procedural and sampled by world position
// (a few ALU ops/fragment, no extra geometry or draw calls): large soft patches of lusher vs
// drier grass (brightness mottle + a gentle warm/cool hue drift) and faint clover-clump flecks.
// DecorChunk still draws the discrete props (flowers, pebbles, tufts) on top.

uniform sampler2D grass_tex : repeat_enable, filter_linear_mipmap;
uniform float tile_world = 220.0;   // world px per texture repeat
uniform float tex_mean   = 0.55;    // texture's mean luminance (detail centres on 1.0)
uniform float strength   = 0.55;    // 0 = flat, 1 = full blade contrast
uniform float mottle     = 0.14;    // depth of the large lush/dry brightness patches
uniform float hue_drift  = 0.085;   // warm(dry) / cool(lush) per-patch hue shift
uniform float fleck      = 0.08;    // faint lightening of small clover/blade clumps

varying vec2 world_pos;

// sin-free hash — stable across the whole bounded map (sin(big)*K bands on some GPUs).
float hash1(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash1(i);
	float b = hash1(i + vec2(1.0, 0.0));
	float c = hash1(i + vec2(0.0, 1.0));
	float d = hash1(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 2-octave fractal value noise — soft organic patches.
float fbm(vec2 p) {
	return vnoise(p) * 0.65 + vnoise(p * 2.13 + vec2(5.2, 1.3)) * 0.35;
}

void vertex() {
	world_pos = VERTEX;
}

void fragment() {
	vec3 t = texture(grass_tex, world_pos / tile_world).rgb;
	float L = dot(t, vec3(0.299, 0.587, 0.114));
	// Centre the blade detail on 1.0 and scale by strength.
	float blade = mix(1.0, L / tex_mean, strength);

	// ── Macro meadow variation: broad regions (~17 tiles) blended with medium patches (~8 tiles),
	//    so the field has both large lush/dry zones and finer rolling texture within them. ──
	float macro_a = fbm(world_pos * (1.0 / 255.0));
	float macro_b = fbm(world_pos * (1.0 / 560.0) + vec2(19.0, 4.0));
	float macro = mix(macro_a, macro_b, 0.45);
	float mott = mix(1.0 - mottle, 1.0 + mottle, macro);
	float warm = smoothstep(0.45, 0.85, macro);   // dry, sun-bleached patch
	float cool = smoothstep(0.45, 0.15, macro);   // lush, shaded patch
	vec3 hue = vec3(1.0) + hue_drift * (warm * vec3(0.55, 0.18, -0.65) + cool * vec3(-0.35, 0.05, 0.35));

	// ── Faint clover/blade clumps — sparse small lightening dabs for micro texture variety. ──
	float fn = fbm(world_pos * (1.0 / 30.0) + vec2(11.0, 7.0));
	float clover = smoothstep(0.70, 0.92, fn) * fleck;

	vec3 col = vec3(blade) * mott * hue * (1.0 + clover);
	COLOR = vec4(clamp(col, vec3(0.55), vec3(1.6)), 1.0);
}
