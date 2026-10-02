// Ugly 1998 chrome for extruded logos: a matcap-style environment ramp + moving glint.
shader_type spatial;
render_mode unshaded, cull_back;

uniform vec3 tint = vec3(1.0, 1.0, 1.0);
uniform vec3 sky_top = vec3(1.0, 1.0, 1.0);
uniform vec3 sky_low = vec3(0.55, 0.62, 0.95);
uniform vec3 horizon = vec3(0.06, 0.02, 0.12);
uniform vec3 ground_low = vec3(0.32, 0.12, 0.38);
uniform vec3 ground_high = vec3(0.95, 0.7, 0.42);
uniform float glint_speed = 0.6;

void fragment() {
	vec3 n = normalize(NORMAL);
	float y = n.y * 0.5 + 0.5 + n.x * 0.12;
	vec3 c;
	if (y > 0.5) {
		c = mix(sky_low, sky_top, smoothstep(0.52, 0.95, y));
	} else {
		c = mix(ground_low, ground_high, smoothstep(0.05, 0.47, y));
	}
	c = mix(c, horizon, smoothstep(0.035, 0.0, abs(y - 0.5)));
	float fres = pow(1.0 - clamp(dot(n, normalize(VIEW)), 0.0, 1.0), 2.5);
	c += fres * vec3(0.5, 0.45, 0.7);
	float glint = pow(max(0.0, sin(n.x * 5.0 + n.y * 2.0 + TIME * glint_speed * 3.0)), 60.0);
	c += glint * 1.2;
	ALBEDO = c * tint;
}
