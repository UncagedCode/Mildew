// Opening-titles tunnel: aggressive 1998 CGI stripes rushing past (inside of a cylinder).
shader_type spatial;
render_mode unshaded, cull_front;

uniform vec3 col_a = vec3(0.32, 0.08, 0.55);
uniform vec3 col_b = vec3(0.05, 0.55, 0.6);
uniform vec3 col_c = vec3(0.75, 0.85, 0.25);
uniform float speed = 1.6;

void fragment() {
	vec2 uv = UV;
	float rings = fract(uv.y * 14.0 - TIME * speed);
	float spokes = fract(uv.x * 12.0 + TIME * 0.15);
	vec3 c = mix(col_a, col_b, smoothstep(0.35, 0.65, rings));
	c = mix(c, col_c, step(0.94, rings) * 0.8);
	c += step(0.97, spokes) * 0.35;
	float depth_fade = smoothstep(0.0, 0.6, uv.y);
	ALBEDO = c * (0.35 + 0.65 * depth_fade);
}
