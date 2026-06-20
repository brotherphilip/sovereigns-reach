shader_type canvas_item;
render_mode blend_mul;
// Soft, drifting CLOUD SHADOWS cast over the whole scene in daytime. Animated fbm noise
// scrolls across the world; where it crosses the coverage threshold the ground darkens.
// `coverage` 0→1 grows from a few sparse patches on a fine day to a heavy overcast (driven
// by the weather build-up). `daylight` fades it out at night. Multiply blend = it only
// darkens, never brightens. GPU-only animation (TIME), one static quad underneath.

uniform float coverage = 0.30;        // 0 clear … 1 overcast
uniform float darkness = 0.34;        // how dark a full shadow core gets
uniform float softness = 0.18;        // edge feather of the shadow patches
uniform vec2  wind      = vec2(0.7, 0.28);  // drift direction (world)
uniform float wind_speed = 7.0;       // world px/sec drift
uniform float scale     = 0.0016;     // noise frequency (per world px)
uniform float daylight  = 1.0;        // 0 at night → no cloud shadows

varying vec2 world_pos;

void vertex() { world_pos = VERTEX; }

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float fbm(vec2 p) {
	return vnoise(p) * 0.6 + vnoise(p * 2.1 + 5.2) * 0.3 + vnoise(p * 4.3 + 11.7) * 0.1;
}

void fragment() {
	vec2 p = world_pos * scale + wind * (TIME * wind_speed * scale);
	float n = fbm(p);
	// coverage raises the cloud field: higher coverage → lower threshold → more shadow.
	float thr = mix(0.78, 0.30, clamp(coverage, 0.0, 1.0));
	float shadow = smoothstep(thr - softness, thr + softness, n);
	float dark = shadow * darkness * clamp(daylight, 0.0, 1.0);
	COLOR = vec4(vec3(1.0 - dark), 1.0);
}
