shader_type canvas_item;

// Modified by Claude Code (with attribution to original author):
//   - added a slow horizontal nebula band drifting for a sense of depth
//   - added a soft radial vignette so foreground panels read better
//   - widened the star palette toward cooler tones to sit closer to the
//     navy/cyan accents used in the rest of the UI
//   - exposed `nebula_color` and `vignette_strength` as uniforms for tuning
// Star field generation, hash2 and twinkle behaviour are unchanged.

uniform vec3 sky_color: source_color = vec3(0.03, 0.05, 0.11);
uniform vec3 nebula_color: source_color = vec3(0.16, 0.10, 0.32);
uniform float scroll_speed: hint_range(0.0, 0.5) = 0.04;
uniform float vignette_strength: hint_range(0.0, 1.0) = 0.40;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

void fragment() {
	vec2 uv = UV * vec2(16.0, 9.0);
	vec3 color = sky_color;

	// 2 sparse layers — large, bright, well-separated stars
	for (int i = 0; i < 2; i++) {
		float scale = 3.5 + float(i) * 2.5;   // wider grid = fewer stars
		float drift = scroll_speed * (0.08 + float(i) * 0.06);
		vec2 p    = uv * scale + vec2(TIME * drift, TIME * drift * 0.45);
		vec2 cell = floor(p);
		vec2 f    = fract(p);

		vec2 star = hash2(cell);
		float dist = length(f - star);

		// Only draw stars when the random seed says so (~40% of cells)
		float visible = step(0.6, hash2(cell + 0.5).x);
		float twinkle = sin(TIME * 1.8 + dot(star, vec2(23.4, 47.8))) * 0.25 + 0.75;
		float brightness = smoothstep(0.11, 0.0, dist) * twinkle * visible;

		vec3 star_color = mix(vec3(0.74, 0.88, 1.0), vec3(0.95, 0.85, 0.55), star.x);
		color += star_color * brightness * 1.15;
	}

	// Nebula band — soft horizontal cloud crossing the upper third, slowly drifting.
	// (Claude Code addition.)
	float band_y    = 0.55 + sin(UV.x * 1.7 + TIME * 0.05) * 0.05;
	float band      = exp(-pow((UV.y - band_y) * 3.4, 2.0));
	float band_drift = sin(UV.x * 2.4 + TIME * 0.04) * 0.5 + 0.5;
	color += nebula_color * band * band_drift * 0.22;

	// Original very faint nebula tint
	float n = sin(UV.x * 5.5 + TIME * 0.07) * sin(UV.y * 3.5 + TIME * 0.04);
	color += vec3(0.05, 0.10, 0.25) * max(n * 0.025, 0.0);

	// Radial vignette so panels sit on a slightly darker frame.
	// (Claude Code addition.)
	vec2 d = UV - 0.5;
	float r = dot(d, d);
	color *= mix(1.0, 1.0 - vignette_strength, clamp(r * 1.7, 0.0, 1.0));

	COLOR = vec4(color, 1.0);
}
