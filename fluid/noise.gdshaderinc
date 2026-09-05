// Shared noise & utility functions, ported verbatim from the source GLSL.
// #include this from a .gdshader with:  #include "res://fluid/noise.gdshaderinc"

// Hash without sin (better on some GPUs)
vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Value noise
float noise2D(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// Curl of a 2D scalar noise field -> divergence-free-ish flow
vec2 curlNoise(vec2 p) {
	float eps = 0.001;
	float n1 = noise2D(p + vec2(0.0, eps));
	float n2 = noise2D(p - vec2(0.0, eps));
	float n3 = noise2D(p + vec2(eps, 0.0));
	float n4 = noise2D(p - vec2(eps, 0.0));
	float dndx = (n3 - n4) / (2.0 * eps);
	float dndy = (n1 - n2) / (2.0 * eps);
	return vec2(dndy, -dndx);
}
