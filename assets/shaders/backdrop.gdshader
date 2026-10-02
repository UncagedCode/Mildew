// Studio back-wall panels: loud purple->teal gradients with cheap sheen.
shader_type spatial;
render_mode unshaded;
uniform vec3 top = vec3(0.30, 0.10, 0.50);
uniform vec3 bottom = vec3(0.05, 0.45, 0.50);
uniform float sheen = 0.25;
void fragment() {
	vec3 c = mix(bottom, top, UV.y < 0.0 ? 0.0 : 1.0 - UV.y);
	c += sheen * pow(max(0.0, sin(UV.x * 3.14159)), 6.0) * 0.6;
	c += 0.04 * sin(UV.y * 60.0);
	ALBEDO = c;
}
