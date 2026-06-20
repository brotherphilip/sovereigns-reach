shader_type canvas_item;
render_mode blend_mul;
// Soft, drifting CLOUD SHADOWS cast over the whole scene in daytime. Animated fbm noise
// scrolls across the world; where it crosses the coverage threshold the ground darkens.
// `coverage` 0→1 grows from a few sparse patches on a fine day to a heavy overcast (driven
// by the weather build-up). `daylight` fades it out at night. Multiply blend = it only
// darkens, never brightens. GPU-only animation (TIME), one static quad underneath.

uniform float coverage = 0.30;        // 0 clear … 1 overcast
uniform float darkness = 0.32;        // how dark a full shadow core gets
uniform vec2  wind      = vec2(0.7, 0.28);  // drift direction (world)
uniform float wind_speed = 7.0;       // world px/sec drift
uniform float scale     = 0.0011;     // noise frequency (per world px) — larger, rounder blobs
uniform float daylight  = 1.0;        // 0 at night → no cloud shadows

varying vec2 world_pos;

void vertex() { world_pos = VERTEX; }

// Smooth gradient (Perlin-style) noise — gradients, not value cells, so there are NO grid
// artefacts / axis-aligned hard edges (the value-noise version showed those). Range ~[-1,1].
vec2 grad(vec2 i) {
	float a = fract(sin(dot(i, vec2(127.1, 311.7))) * 43758.5453) * 6.2831853;
	return vec2(cos(a), sin(a));
}
float gnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);   // quintic → C2 smooth, no creases
	float a = dot(grad(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0));
	float b = dot(grad(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(grad(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(grad(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
// Rotated octaves (decorrelate grids) → organic, edge-free cloud field in 0..1.
float fbm(vec2 p) {
	const mat2 R = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	float v = 0.0; float amp = 0.5;
	for (int k = 0; k < 4; k++) { v += amp * gnoise(p); p = R * p * 2.0 + 3.1; amp *= 0.5; }
	return v * 0.5 + 0.5;
}

void fragment() {
	vec2 p = world_pos * scale + wind * (TIME * wind_speed * scale);
	// Domain warp: bend the field by another noise so blobs are billowy, never grid-like.
	vec2 w = vec2(fbm(p + 1.7), fbm(p + 9.2)) - 0.5;
	float n = fbm(p + w * 1.2);
	// SOFT density: a gentle, wide ramp (no threshold edge). coverage lifts the whole field.
	float lo = mix(0.62, 0.05, clamp(coverage, 0.0, 1.0));
	float dens = smoothstep(lo, lo + 0.55, n);          // 0.55-wide feather → fully gradient
	float dark = dens * darkness * clamp(daylight, 0.0, 1.0);
	COLOR = vec4(vec3(1.0 - dark), 1.0);
}
