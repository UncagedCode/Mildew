// Mildew broadcast treatment: simulates late-90s analogue transmission on top of a
// clean high-resolution render. Readability first (docs/08): effects are restrained and
// every parameter is driven by the presentation code (tape generation / incidents).
shader_type canvas_item;

uniform vec2 src_size = vec2(1440.0, 1080.0);
uniform float softness : hint_range(0.0, 2.5) = 0.75;     // horizontal analogue softness (px)
uniform float chroma : hint_range(0.0, 4.0) = 1.1;        // chroma misregistration (px)
uniform float scanline : hint_range(0.0, 0.5) = 0.07;     // interlace impression
uniform float noise_amt : hint_range(0.0, 0.25) = 0.028;
uniform float vignette : hint_range(0.0, 1.0) = 0.28;
uniform float bloom : hint_range(0.0, 1.0) = 0.22;
uniform float saturation : hint_range(0.0, 2.0) = 1.06;
uniform float flicker : hint_range(0.0, 0.1) = 0.01;
uniform float tracking : hint_range(0.0, 1.0) = 0.0;      // tape tracking error (rare)
uniform float dropout : hint_range(0.0, 1.0) = 0.0;       // tape dropout streaks (rare)
uniform float signal_loss : hint_range(0.0, 1.0) = 0.0;   // fictional static (never for real status)
uniform vec3 tint = vec3(1.02, 1.0, 0.97);

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 uv = UV;
	vec2 px = 1.0 / src_size;
	float t = TIME;
	// Tracking error: a rolling band of horizontally displaced lines.
	if (tracking > 0.0) {
		float band_y = fract(t * 0.21);
		float d = abs(uv.y - band_y);
		float band = smoothstep(0.09, 0.0, d);
		float line_noise = hash(vec2(floor(uv.y * src_size.y * 0.5), floor(t * 30.0))) - 0.5;
		uv.x += band * tracking * (0.012 + line_noise * 0.02);
		uv.x += tracking * 0.0015 * sin(uv.y * 40.0 + t * 7.0);
	}
	vec2 dx = vec2(px.x * softness, 0.0);
	vec2 cx = vec2(px.x * chroma, 0.0);
	vec3 g = texture(TEXTURE, uv).rgb * 0.5 + texture(TEXTURE, uv + dx).rgb * 0.25 + texture(TEXTURE, uv - dx).rgb * 0.25;
	float r = texture(TEXTURE, uv + cx).r;
	float b = texture(TEXTURE, uv - cx).b;
	vec3 col = vec3(mix(g.r, r, 0.65), g.g, mix(g.b, b, 0.65));
	// Cheap highlight bloom / CRT glow.
	col += max(col - 0.72, 0.0) * bloom * 1.6;
	// Saturation + slight warm broadcast tint.
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, saturation) * tint;
	// Interlace impression (2px period at reference height).
	float sl = 0.5 + 0.5 * sin(uv.y * src_size.y * 3.14159265);
	col *= 1.0 - scanline * sl;
	// Grain / noise.
	float n = hash(uv * src_size + vec2(t * 61.0, t * 17.0)) - 0.5;
	col += n * noise_amt;
	// Dropout: short bright horizontal streaks.
	if (dropout > 0.0) {
		float row = floor(uv.y * src_size.y / 3.0);
		float hit = step(1.0 - dropout * 0.02, hash(vec2(row, floor(t * 24.0))));
		float seg = step(hash(vec2(row, 3.0)), uv.x) * step(uv.x, hash(vec2(row, 3.0)) + 0.15);
		col = mix(col, vec3(0.92), hit * seg);
	}
	if (signal_loss > 0.0) {
		float s = hash(uv * src_size * 0.5 + vec2(t * 97.0));
		col = mix(col, vec3(s), signal_loss);
	}
	// Flicker + vignette.
	col *= 1.0 - flicker * hash(vec2(floor(t * 50.0), 1.0));
	vec2 v = uv - 0.5;
	col *= 1.0 - vignette * dot(v, v) * 1.6;
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
