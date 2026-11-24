shader_type spatial;
// Increment 29: a settler's or raider's body, dressed. The body mesh carries
// its regions in the vertex colour (baked by tools/build_characters.gd):
// red a shirt (or coat), green trousers, blue boots; none of them, skin.
// Each person gets their own colours, and what they wear over a region
// (armour, Wool Clothes) is drawn by overriding that region's colour.

uniform sampler2D skin_texture : source_color, filter_linear_mipmap;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
instance uniform vec4 skin_tint : source_color = vec4(1.0);
instance uniform vec4 shirt_color : source_color = vec4(0.5, 0.4, 0.3, 1.0);
instance uniform vec4 trousers_color : source_color = vec4(0.28, 0.27, 0.24, 1.0);
instance uniform vec4 boots_color : source_color = vec4(0.22, 0.16, 0.11, 1.0);
// Long sleeves (1) or rolled to the elbow (0): the alpha of the vertex
// colour marks the forearm.
instance uniform float long_sleeves = 1.0;
// Plated armour: shinier, harder
instance uniform float shirt_metal = 0.0;
instance uniform float trousers_metal = 0.0;
// How far cloth stands off the skin (m)
uniform float cloth_thickness = 0.008;
// Worn and dirty
uniform float grime = 0.35;
// 29.1: all skin (the head under an outfit, and the outfits' bare hands and
// arms, which carry no regions)
uniform bool bare = false;

varying vec4 region;
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
	region = bare ? vec4(0.0) : COLOR;
	// Sleeves rolled up: the forearm's skin shows
	float shirt = region.r * mix(1.0 - region.a, 1.0, long_sleeves);
	region.r = shirt;
	float cloth = clamp(shirt + region.g + region.b, 0.0, 1.0);
	VERTEX += NORMAL * cloth_thickness * cloth * (1.0 + region.b * 1.5);
	local_pos = VERTEX;
}

void fragment() {
	vec3 skin = texture(skin_texture, UV).rgb * skin_tint.rgb;
	float shirt = region.r;
	float trousers = region.g;
	float boots = region.b;
	float cloth = clamp(shirt + trousers + boots, 0.0, 1.0);
	// Weave and wear: a little variation over the cloth, darker low down
	float n = noise(local_pos * 40.0) * 0.5 + noise(local_pos * 9.0) * 0.5;
	float dirt = grime * (0.6 + 0.4 * n) * clamp(1.0 - local_pos.y / 1.2, 0.0, 1.0);
	vec3 cloth_col = shirt_color.rgb * shirt + trousers_color.rgb * trousers + boots_color.rgb * boots;
	cloth_col = cloth_col / max(cloth, 0.001);
	cloth_col *= 0.85 + 0.25 * n;
	cloth_col = mix(cloth_col, vec3(0.32, 0.27, 0.2) * cloth_col * 1.6, dirt * 0.5);
	ALBEDO = mix(skin, cloth_col, cloth);
	float metal = shirt * shirt_metal + trousers * trousers_metal;
	METALLIC = metal;
	ROUGHNESS = mix(0.6, mix(0.92, 0.45, metal), cloth);
	// The body's muscle detail only shows on skin
	NORMAL_MAP = mix(texture(normal_texture, UV).rgb, vec3(0.5, 0.5, 1.0), cloth);
	NORMAL_MAP_DEPTH = 1.0;
}
