shader_type canvas_item;
render_mode blend_mul;
// Multiplies fine GRASS-BLADE detail onto the flat terrain tiles drawn underneath, so the
// ground reads as real textured turf instead of a solid colour — while the base tile keeps
// carrying the season/biome TINT (multiply preserves hue). Sampled by WORLD position so the
// texture flows continuously across tiles (seams only at the texture's repeat, not per-tile).

uniform sampler2D grass_tex : repeat_enable, filter_linear_mipmap;
uniform float tile_world = 220.0;   // world px per texture repeat
uniform float tex_mean   = 0.55;    // texture's mean luminance (detail centres on 1.0)
uniform float strength   = 0.55;    // 0 = flat, 1 = full blade contrast

varying vec2 world_pos;

void vertex() {
	world_pos = VERTEX;
}

void fragment() {
	vec3 t = texture(grass_tex, world_pos / tile_world).rgb;
	float L = dot(t, vec3(0.299, 0.587, 0.114));
	// Centre the detail on 1.0 and scale by strength → multiply lightens/darkens the base
	// tile by the blade pattern without shifting its colour.
	float d = mix(1.0, L / tex_mean, strength);
	COLOR = vec4(vec3(d), 1.0);
}
