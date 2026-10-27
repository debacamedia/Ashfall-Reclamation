shader_type spatial;
// The sea off the early zone's west coast: grey-green water with slow
// crossing swells (two scrolling normal maps) and a lighter rim where it
// catches the sky at a glancing angle.

uniform sampler2D waves : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 deep : source_color = vec3(0.12, 0.2, 0.22);
uniform vec3 shallow : source_color = vec3(0.3, 0.38, 0.36);
uniform float wave_scale = 0.025;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 uv = world_pos.xz * wave_scale;
	vec3 n1 = texture(waves, uv + vec2(TIME * 0.006, TIME * 0.004)).rgb;
	vec3 n2 = texture(waves, uv * 1.7 - vec2(TIME * 0.005, -TIME * 0.007)).rgb;
	NORMAL_MAP = normalize(mix(n1, n2, 0.5));
	NORMAL_MAP_DEPTH = 0.6;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(deep, shallow, fres);
	ROUGHNESS = 0.12;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
