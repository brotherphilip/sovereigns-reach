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
// Speckled pixel mosaic (user request): the surface is broken into chunky square cells,
// each a slightly different shade — like sunlight faceting off little ripples. On rivers
// the lattice LAPS downstream along the current; on still water it barely drifts and each
// block instead twinkles on its own phase, so a calm pond still GLISTENS in place.
uniform float speckle_size   = 9.0;   // cell size in world px (smaller = finer speckle)
uniform float speckle_amount = 0.16;  // light/dark spread between blocks
uniform float speckle_glint  = 0.10;  // extra punch on the few blocks catching the sun
uniform float speckle_speed  = 0.7;   // how fast the lattice laps downstream
uniform float speckle_blur   = 0.5;   // 0 = hard pixel blocks, 0.5 = fully soft/blurred

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

// One mosaic cell's shade (0..1), including its own glisten twinkle phase.
float cell_shade(vec2 ci) {
	float a = hash(ci);
	float b = hash(ci + vec2(37.2, 17.9));
	float twk = 0.5 + 0.5 * sin(TIME * 2.2 + a * 6.2831);
	return mix(a, b, twk);
}

// Soft (blurred) mosaic value at grid position g — bilinear blend of the four surrounding
// cells with a smoothstep'd weight (speckle_blur: 0 = hard pixel edges, 0.5 = fully soft).
float cell_field(vec2 g) {
	vec2 ci = floor(g);
	vec2 bw = smoothstep(vec2(0.5 - speckle_blur), vec2(0.5 + speckle_blur), fract(g));
	float s00 = cell_shade(ci);
	float s10 = cell_shade(ci + vec2(1.0, 0.0));
	float s01 = cell_shade(ci + vec2(0.0, 1.0));
	float s11 = cell_shade(ci + vec2(1.0, 1.0));
	return mix(mix(s00, s10, bw.x), mix(s01, s11, bw.x), bw.y);
}

void fragment() {
	vec2 fdir = normalize(flow_info.rg * 2.0 - 1.0);
	// Rivers run more active; still/coastal water stays calm (lower effective speed).
	float move = mix(1.0, 0.45, flow_info.b);
	float t = TIME * flow_speed * move;
	vec2 p = world_pos * 0.02;
	// Domain-warp the ripples so the current curls and braids instead of marching in
	// straight lines — reads as water finding its way round the bends.
	vec2 warp = (vec2(vnoise(p * 1.6 + t * 0.20), vnoise(p * 1.6 - t * 0.16)) - 0.5) * 1.1;
	// Three octaves: a broad swell, a mid undulation, and a fast fine ripple so the
	// surface is visibly alive without obvious tiling (each octave on its own scale/phase).
	float n = vnoise(p - fdir * (t * 1.0) + warp) * 0.50
			+ vnoise(p * 2.3 - fdir * (t * 1.9) + warp * 0.5) * 0.32
			+ vnoise(p * 5.1 - fdir * (t * 3.2) + warp * 0.3) * 0.18;

	vec4 deep = mix(river_deep, coast_deep, flow_info.b);
	vec4 lite = mix(river_lite, coast_lite, flow_info.b);
	vec3 col = mix(deep.rgb, lite.rgb, clamp(n, 0.0, 1.0));
	// Depth shading. A lake/sea should read as a basin: noticeably darker in the open
	// centre and brightening toward the banks, not one flat sheet of blue.
	//   depth  = how far into open water (smoothstepped centre weight, stronger darkening)
	//   shore  = how close to the bank, FEATHERED with a wide smoothstep so water fades
	//            into a shallow shimmer at the edge instead of a hard line.
	float depth = smoothstep(0.15, 0.95, edge_interior);
	float shore = smoothstep(0.0, 0.78, 1.0 - edge_interior);
	col = mix(col, col * 0.62, depth * 0.70);                 // deepen the open centre
	col = mix(col, shallow_col.rgb, shore * 0.40);            // lighter, shallow bank tint

	// --- Speckled mosaic (soft / blurred) ----------------------------------------------
	// World-anchored mosaic, fully blurred into soft blobs (cell_field). Two overlapping
	// octaves at different scales/offsets so the blobs don't line up on the grid — reads
	// as soft faceting, not squares. Rivers scroll the lattice downstream (lapping);
	// still/coastal water barely drifts (flow_amt small) but every cell pulses on its own
	// phase so it glistens without obvious motion.
	float flow_amt = mix(1.0, 0.16, flow_info.b);                 // river laps, coast nearly still
	vec2 g = world_pos / speckle_size - fdir * (TIME * speckle_speed * flow_amt);
	float cell_v = cell_field(g) * 0.62 + cell_field(g * 0.55 + vec2(11.3, 5.1)) * 0.38;
	float calm = 0.55 + 0.45 * edge_interior;                     // gentler speckle at the banks
	col += (cell_v - 0.5) * (speckle_amount * 2.0) * calm;
	// A few patches flare bright as the light catches them — the glisten.
	col += smoothstep(0.80, 1.0, cell_v) * speckle_glint * edge_interior;

	// Drifting specular glint: a soft band of sunlight that slides slowly across the
	// surface (crests of the fine ripple catching the light), so even open water sparkles.
	float glint_n = vnoise(p * 3.4 + warp * 1.2 + vec2(t * 0.6, -t * 0.4));
	float glint = smoothstep(0.74, 0.98, glint_n * 0.6 + n * 0.4);
	col += glint * 0.16 * (0.4 + 0.6 * edge_interior);

	// Animated foam lace hugging the shoreline (only the outermost band, so small ponds
	// don't wash out to pale).
	float foam_n = vnoise(p * 5.0 + warp * 2.0 + t * 0.7);
	float foam = smoothstep(0.62, 0.95, shore) * smoothstep(0.52, 0.85, foam_n);
	col = mix(col, foam_col.rgb, foam * 0.42);
	COLOR = vec4(col, 1.0);
}
