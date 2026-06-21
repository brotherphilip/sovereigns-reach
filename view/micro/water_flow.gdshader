shader_type canvas_item;
render_mode blend_mix;
// Animated river/sea surface. The water mesh is built once (static, organic rounded
// tiles); the GPU animates it via TIME with no per-frame CPU work. Each vertex COLOR
// carries the channel's downstream flow direction (rg, encoded 0..1), a water-type
// flag (b: 0=river, 1=coastal) and a depth/interior amount (a: 1=deep centre, 0=bank)
// so the shader can deepen open water and lace foam along the shoreline.

uniform float flow_speed = 0.35;
// Muted, slightly desaturated blue-teal so the water sits with the warm painterly
// buildings/grass instead of glaring as vivid cobalt (iter230, user palette feedback).
uniform vec4 river_deep  : source_color = vec4(0.10, 0.26, 0.40, 1.0);
uniform vec4 river_lite  : source_color = vec4(0.27, 0.48, 0.60, 1.0);
uniform vec4 coast_deep  : source_color = vec4(0.16, 0.40, 0.52, 1.0);
uniform vec4 coast_lite  : source_color = vec4(0.40, 0.64, 0.70, 1.0);
uniform vec4 shallow_col : source_color = vec4(0.46, 0.69, 0.72, 1.0);
uniform vec4 foam_col    : source_color = vec4(0.88, 0.93, 0.94, 1.0);

varying vec2 world_pos;
varying vec3 flow_info;
varying float edge_interior;

void vertex() {
	world_pos = VERTEX;
	flow_info = COLOR.rgb;          // rg = flow dir (encoded), b = type flag
	edge_interior = COLOR.a;        // 1 = deep centre, 0 = bank
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
	// Domain-warp the ripples so the current curls and braids instead of marching in
	// straight lines — reads as water finding its way round the bends.
	vec2 warp = (vec2(vnoise(p * 1.6 + t * 0.20), vnoise(p * 1.6 - t * 0.16)) - 0.5) * 1.1;
	float n = vnoise(p - fdir * (t * 0.9) + warp) * 0.6
			+ vnoise(p * 2.3 - fdir * (t * 1.7) + warp * 0.5) * 0.4;
	// Highlight bands sweeping downstream along the current.
	float along = dot(world_pos, fdir) * 0.06;
	float bands = sin(along * 6.2831 - t * 2.2 + n * 4.0);
	float hl = smoothstep(0.62, 1.0, bands) * 0.12;   // calmer, less busy flow highlights
	// Sparse glints, on the open water only (kept off the foamy banks).
	float spark = smoothstep(0.90, 1.0, vnoise(p * 6.5 - fdir * t * 1.3 + warp));
	spark *= 0.22 * edge_interior;

	vec4 deep = mix(river_deep, coast_deep, flow_info.b);
	vec4 lite = mix(river_lite, coast_lite, flow_info.b);
	vec3 col = mix(deep.rgb, lite.rgb, clamp(n, 0.0, 1.0));
	// Depth shading: deepen the centre, fade to a lighter shallow tint at the banks.
	float shore = clamp(1.0 - edge_interior, 0.0, 1.0);
	col = mix(col, col * 0.80, edge_interior * 0.45);
	col = mix(col, shallow_col.rgb, shore * 0.22);
	col += hl + spark;
	// Animated foam lace hugging the shoreline (only the outermost band, so small ponds
	// don't wash out to pale).
	float foam_n = vnoise(p * 5.0 + warp * 2.0 + t * 0.7);
	float foam = smoothstep(0.62, 0.95, shore) * smoothstep(0.52, 0.85, foam_n);
	col = mix(col, foam_col.rgb, foam * 0.42);
	COLOR = vec4(col, 1.0);
}
