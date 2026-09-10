// Renders the packed fluid state to screen, tinted from a growing ROYGBIV ramp.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

uniform sampler2D u_field : filter_linear;
uniform float u_time;
uniform float u_palette_count = 7.0;

uniform float u_bloom       = 0.0;
uniform int   u_bloom_index = 0;

const vec3 ROYGBIV[7] = {
	vec3(1.00, 0.05, 0.05),
	vec3(1.00, 0.45, 0.00),
	vec3(1.00, 0.85, 0.00),
	vec3(0.10, 0.85, 0.20),
	vec3(0.10, 0.40, 1.00),
	vec3(0.32, 0.10, 0.78),
	vec3(0.62, 0.10, 0.96)
};

vec3 ramp(float t, float count) {
	float span = max(count - 1.0, 0.0);
	float pingpong = abs(fract(t) * 2.0 - 1.0);
	float x = pingpong * span;
	int i = int(floor(x));
	int j = min(i + 1, 6);
	i = min(i, 6);
	vec3 col = mix(ROYGBIV[i], ROYGBIV[j], fract(x));
	return mix(vec3(0.5), col, clamp(count, 0.0, 1.0));
}

void fragment() {
	vec4 data = texture(u_field, UV);

	float dye = data.b;
	vec2 vel = data.rg * 2.0 - 1.0;

	float t = u_time * 0.08 + UV.x * 0.3 + UV.y * 0.2 + length(vel) * 2.0;
	vec3 tint = ramp(t, u_palette_count);

	vec3 color = tint * dye;
	color = mix(vec3(0.0), color, smoothstep(0.001, 0.05, dye));

	if (u_bloom > 0.0) {
		float radial = mix(1.0, 0.55, length(UV - 0.5) / 0.7071);
		color += ROYGBIV[clamp(u_bloom_index, 0, 6)] * (u_bloom * u_bloom) * radial;
	}

	COLOR = vec4(color, 1.0);
}
