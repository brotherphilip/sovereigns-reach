shader_type canvas_item;
// Screen-space RAIN: a dense curtain of fine, short, fast streaks across 3 parallax depth
// layers + a cool wet wash so the whole scene reads rained-on. Streaks are thin and only
// semi-opaque (rain reads as MANY faint strokes, not a few bright scratches). Driven by
// `intensity` (0 dry → 1 downpour). GPU-only via TIME; one full-screen rect under the HUD.

uniform float intensity = 0.0;     // 0 none … 1 downpour
uniform float slant     = 0.13;    // horizontal lean
uniform vec4  streak_col : source_color = vec4(0.86, 0.90, 0.97, 1.0);
uniform vec4  wet_wash   : source_color = vec4(0.34, 0.40, 0.50, 1.0);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

// One layer of streaks: `cols` columns wide, `dashes` short dashes per column height,
// `spd` fall speed, `thin` across-column sharpness. Returns 0..1 coverage.
float layer(vec2 uv, float t, float cols, float dashes, float spd, float thin) {
	uv.x += uv.y * slant;
	uv.x *= cols;
	float colf = floor(uv.x);
	float r = hash21(vec2(colf, 3.0));
	float fx = fract(uv.x) - 0.5;
	float across = exp(-fx * fx * thin);                 // soft thin line across the column
	float y = uv.y * dashes + t * spd * (0.7 + r * 0.7) + r * 17.0;
	float fy = fract(y);
	float along = smoothstep(0.0, 0.12, fy) * (1.0 - smoothstep(0.12, 0.55, fy));  // short dash w/ tail
	return across * along;
}

void fragment() {
	float I = clamp(intensity, 0.0, 1.0);
	if (I <= 0.001) {
		COLOR = vec4(0.0);
	} else {
		vec2 uv = UV;
		float t = TIME;
		// Three depth sheets: far (fine/dense) → near (coarser/faster).
		float r = layer(uv, t, 150.0, 22.0, 2.6, 130.0) * 0.45
				+ layer(uv, t,  95.0, 17.0, 2.1,  90.0) * 0.55
				+ layer(uv, t,  60.0, 13.0, 1.7,  60.0) * 0.65;
		r = clamp(r, 0.0, 1.0) * I;
		// Cool wet wash that grows with intensity → the scene looks wet even between streaks.
		float wash = wet_wash.a * (0.08 + 0.20 * I);
		vec3 col = mix(wet_wash.rgb, streak_col.rgb, r);
		float a = max(r * 0.5, wash);                    // streaks stay semi-transparent
		COLOR = vec4(col, a);
	}
}
