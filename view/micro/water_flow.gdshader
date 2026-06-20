shader_type canvas_item;
render_mode blend_mix;
// Extremely light river/water flow. The water mesh is built once (static) — the GPU
// animates it via TIME with no per-frame CPU work. Each tile's vertex COLOR carries
// the local downstream flow direction (rg, encoded 0..1) baked at load so the current
// follows the river's bends, and a water-type flag (b: 0=river, 1=coastal).

uniform float flow_speed = 0.35;
// Muted, slightly desaturated blue-teal so the water sits with the warm painterly
// buildings/grass instead of glaring as vivid cobalt (iter230, user palette feedback).
uniform vec4 river_deep  : source_color = vec4(0.11, 0.28, 0.42, 1.0);
uniform vec4 river_lite  : source_color = vec4(0.27, 0.48, 0.60, 1.0);
uniform vec4 coast_deep  : source_color = vec4(0.20, 0.44, 0.54, 1.0);
uniform vec4 coast_lite  : source_color = vec4(0.40, 0.64, 0.70, 1.0);

varying vec2 world_pos;
varying vec3 flow_info;

void vertex() {
	world_pos = VERTEX;
	flow_info = COLOR.rgb;          // rg = flow dir (encoded), b = type flag
}

// Cheap value noise (one hash, smooth interp).
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}
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

void fragment() {
	vec2 fdir = normalize(flow_info.rg * 2.0 - 1.0);
	float t = TIME * flow_speed;
	vec2 p = world_pos * 0.02;
	// Two noise layers drifting downstream at slightly different rates.
	float n = vnoise(p - fdir * (t * 0.9)) * 0.6
			+ vnoise(p * 2.3 - fdir * (t * 1.7)) * 0.4;
	// Highlight bands sweeping along the current.
	float along = dot(world_pos, fdir) * 0.06;
	float bands = sin(along * 6.2831 - t * 2.2 + n * 4.0);
	float hl = smoothstep(0.62, 1.0, bands) * 0.14;   // calmer, less busy flow highlights

	vec4 deep = mix(river_deep, coast_deep, flow_info.b);
	vec4 lite = mix(river_lite, coast_lite, flow_info.b);
	vec3 col = mix(deep.rgb, lite.rgb, clamp(n, 0.0, 1.0)) + hl;
	COLOR = vec4(col, 1.0);
}
