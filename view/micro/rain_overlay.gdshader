shader_type canvas_item;
// Screen-space RAIN: layered slanted streaks falling across the view + a faint cool wash so
// the whole scene reads wet/overcast. Driven by `intensity` (0 dry → 1 downpour); STORM pushes
// it highest. Pure GPU animation via TIME; one full-screen rect.

uniform float intensity = 0.0;     // 0 none … 1 downpour
uniform float slant     = 0.16;    // horizontal lean of the streaks
uniform vec4  rain_tint : source_color = vec4(0.74, 0.80, 0.88, 1.0);
uniform vec4  wet_wash  : source_color = vec4(0.36, 0.42, 0.52, 1.0);

float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453); }

// One sheet of streaks: `cols` columns, falling at `spd`, each a short bright dash.
float sheet(vec2 uv, float t, float cols, float spd, float len) {
	uv.x += uv.y * slant;
	uv.x *= cols;
	float colf = floor(uv.x);
	float ph = hash(vec2(colf, 7.0));          // per-column phase + on/off
	if (ph < 0.35) return 0.0;                  // gaps so it isn't a solid curtain
	float y = uv.y * (1.4 + ph * 0.8) + t * spd + ph;
	float fy = fract(y);
	// a dash: bright head fading to tail
	float dash = smoothstep(0.0, 0.04, fy) * (1.0 - smoothstep(0.04, len, fy));
	// soften across the column width
	float fx = abs(fract(uv.x) - 0.5);
	float across = 1.0 - smoothstep(0.18, 0.5, fx);
	return dash * across;
}

void fragment() {
	float I = clamp(intensity, 0.0, 1.0);
	if (I <= 0.001) { COLOR = vec4(0.0); }
	else {
		float t = TIME;
		vec2 uv = UV;
		// Two parallax sheets (far thin/fast-looking + near bigger) for depth.
		float s = sheet(uv, t, 60.0, 1.3, 0.55) * 0.6
				+ sheet(uv, t, 34.0, 1.0, 0.7) * 0.8;
		s = clamp(s, 0.0, 1.0) * I;
		// Faint cool wash that grows with intensity → the scene looks rained-on.
		float wash = wet_wash.a * (0.10 + 0.22 * I);
		vec3 col = mix(rain_tint.rgb, wet_wash.rgb, 0.5);
		float a = max(s, wash);
		COLOR = vec4(mix(wet_wash.rgb, rain_tint.rgb, s), a);
	}
}
