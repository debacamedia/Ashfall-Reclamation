shader_type canvas_item;
// The map picture (Increment 17) with the parts you haven't explored
// hidden: `fog` covers the same ground as the picture, one pixel per 8 m
// cell, white where you've been. Its soft (linear) edges are roughened with
// noise so the explored area has a torn, hand-drawn edge.

uniform sampler2D fog : filter_linear;
uniform sampler2D grain : filter_linear, repeat_enable;
uniform vec3 unexplored : source_color = vec3(0.13, 0.12, 0.105);
uniform bool reveal_all = false;

void fragment() {
	vec3 map = texture(TEXTURE, UV).rgb;
	float n = texture(grain, UV * 5.0).r;
	float seen = reveal_all ? 1.0 : smoothstep(0.32, 0.6, texture(fog, UV).r + (n - 0.5) * 0.3);
	// Unexplored: dark, with only a faint hint of the land's light and shade
	float lum = dot(map, vec3(0.3, 0.55, 0.15));
	vec3 hidden = unexplored * (0.85 + 0.3 * n) + vec3(lum * 0.07);
	COLOR = vec4(mix(hidden, map, seen), 1.0);
}
