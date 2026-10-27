shader_type spatial;
// The ground of a whole zone (Increment 15): one dry-dirt texture laid in
// world space, tinted per area by the vertex colour (darker round Black
// Ridge, redder by the gulch, sandier at the coast), broken up by large
// patches, darker and greyer on slopes, and wet sand below the waterline.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_tex : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform sampler2D patches : filter_linear, repeat_enable;
uniform float tile = 0.2;
uniform float patch_scale = 0.0013;
uniform vec3 patch_tint : source_color = vec3(0.78, 0.72, 0.64);
uniform vec3 slope_tint : source_color = vec3(0.55, 0.5, 0.46);
uniform vec3 wet_tint : source_color = vec3(0.5, 0.46, 0.4);
uniform float water_level = -0.35;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 uv = world_pos.xz * tile;
	vec3 base = texture(albedo_tex, uv).rgb;
	// Two scales of the same texture so it doesn't visibly repeat
	base = mix(base, texture(albedo_tex, uv * 0.23 + vec2(0.37, 0.11)).rgb, 0.35);
	// Two scales of the patch noise, so its tiling never lines up
	float p = texture(patches, world_pos.xz * patch_scale).r * 0.6
			+ texture(patches, world_pos.xz * patch_scale * 3.7 + vec2(0.31, 0.77)).r * 0.4;
	vec3 tint = COLOR.rgb * mix(vec3(1.0), patch_tint, smoothstep(0.35, 0.75, p));
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	tint = mix(tint, tint * slope_tint, smoothstep(0.08, 0.35, slope));
	float wet = smoothstep(water_level + 0.5, water_level - 0.2, world_pos.y);
	tint = mix(tint, tint * wet_tint, wet);
	ALBEDO = base * tint;
	ROUGHNESS = mix(0.8 + 0.2 * texture(roughness_tex, uv).r, 0.35, wet * 0.7);
	SPECULAR = 0.3;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = 0.8;
}
