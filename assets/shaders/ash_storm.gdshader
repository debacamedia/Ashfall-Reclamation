shader_type canvas_item;
// Blowing ash over the screen near a zone's edge (StormEffects).
// `intensity` 0..1; streaks drift sideways with the wind.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 ash_color : source_color = vec4(0.46, 0.41, 0.36, 1.0);
uniform vec2 wind = vec2(0.35, 0.04);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = SCREEN_UV * vec2(3.0, 1.6);
	float t = TIME;
	// Big soft billows, then fine streaks stretched along the wind
	float billow = fbm(uv * 1.3 - wind * t * 0.6);
	float streak = fbm(vec2(uv.x * 0.6, uv.y * 9.0) - vec2(wind.x * t * 2.2, wind.y * t));
	float edge = smoothstep(0.15, 0.95, distance(SCREEN_UV, vec2(0.5)) * 1.4);
	float a = intensity * (0.45 + 0.35 * billow + 0.25 * streak + 0.25 * edge);
	COLOR = vec4(ash_color.rgb * (0.85 + 0.3 * billow), clamp(a, 0.0, 0.92));
}
