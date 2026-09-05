// Renders the packed fluid state to screen with a velocity-driven rainbow.
// Ported from the source display fragment shader.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

uniform sampler2D u_field : filter_linear;
uniform float u_time;

vec3 hsv2rgb(float h, float s, float v) {
	vec3 rgb = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return v * mix(vec3(1.0), rgb, s);
}

void fragment() {
	vec4 data = texture(u_field, UV);

	float dye = data.b;
	vec2 vel = data.rg * 2.0 - 1.0;

	float hue = fract(u_time * 0.08 + UV.x * 0.3 + UV.y * 0.2 + length(vel) * 2.0);
	vec3 rainbow = hsv2rgb(hue, 1.0, 1.0);
	vec3 color = rainbow * dye;
	color = mix(vec3(0.0), color, smoothstep(0.001, 0.05, dye));

	COLOR = vec4(color, 1.0);
}
