shader_type spatial;
// Increment 29.1: a piece of a Quaternius outfit (Modular Character Outfits:
// a shirt, sleeves, trousers, boots, a hood…), its own textures, tinted per
// person and worn: a little dirt, more of it low down.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
// Occlusion, roughness, metal
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap;
// Each person's (raiders' darker, Marauders' soot-black)
instance uniform vec4 tint : source_color = vec4(1.0);
uniform float grime = 0.3;

varying vec3 local_pos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec3 col = texture(albedo_texture, UV).rgb * tint.rgb;
	float n = noise(local_pos * 9.0) * 0.6 + noise(local_pos * 40.0) * 0.4;
	float dirt = grime * (0.6 + 0.4 * n) * clamp(1.0 - local_pos.y / 1.2, 0.0, 1.0);
	col = mix(col, vec3(0.32, 0.27, 0.2) * col * 1.6, dirt * 0.5);
	ALBEDO = col;
	vec3 orm = texture(orm_texture, UV).rgb;
	AO = orm.r;
	ROUGHNESS = clamp(orm.g + dirt * 0.1, 0.0, 1.0);
	METALLIC = orm.b;
	NORMAL_MAP = texture(normal_texture, UV).rgb;
	NORMAL_MAP_DEPTH = 1.0;
}
