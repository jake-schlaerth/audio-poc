// Fluid simulation step. Runs on a full-screen ColorRect inside a SubViewport.
// State is packed into one RGBA texture, ping-ponged between two SubViewports:
//   R = velocity.x  (encoded 0..1)
//   G = velocity.y  (encoded 0..1)
//   B = dye / density (0..1)
//   A = pressure    (encoded 0..1)
// Velocity and pressure are signed, so they are stored as x * 0.5 + 0.5 and
// decoded on read. That keeps the sim correct even on an 8-bit render target.
shader_type canvas_item;
render_mode blend_disabled, unshaded;

#include "res://fluid/noise.gdshaderinc"

uniform vec2  u_resolution;
uniform float u_time;
uniform float u_dt;

uniform sampler2D u_prev : repeat_enable, filter_linear;

uniform float u_viscosity   = 0.5;
uniform float u_vorticity    = 1.0;
uniform float u_dissipation  = 0.995;
uniform float u_force_radius  = 0.08;
uniform vec2  u_force_pos     = vec2(-1.0);   // x < 0 => inactive
uniform vec2  u_force_dir     = vec2(0.0);
uniform bool  u_reset         = false;

// Text sparks: a short-lived halo of tiny outward ember injections. Positions
// and velocities are in UV space; strength 0 means the slot is inactive.
const int MAX_SPARKS = 24;
uniform int   u_spark_count  = 0;
uniform float u_spark_radius = 0.012;
uniform vec2  u_spark_pos[MAX_SPARKS];
uniform vec2  u_spark_end[MAX_SPARKS];
uniform vec2  u_spark_vel[MAX_SPARKS];
uniform float u_spark_strength[MAX_SPARKS];

uniform sampler2D u_text_mask : filter_linear;
uniform float u_text_amount   = 0.0;
uniform float u_text_calm      = 0.0;
uniform float u_text_stir      = 0.0;
uniform float u_text_stir_scale = 6.0;
uniform float u_text_stir_speed = 0.35;
uniform float u_text_settle     = 0.0;

uniform vec2  u_blob_pos          = vec2(-1.0);   // x < 0 => inactive
uniform float u_blob_radius       = 0.0;
uniform float u_blob_aspect       = 1.0;
uniform float u_blob_dye          = 0.3;
uniform float u_blob_ceil         = 0.7;
uniform float u_blob_swirl        = 0.15;
uniform float u_blob_swirl_scale  = 9.0;
uniform float u_blob_swirl_speed  = 0.6;
uniform float u_blob_edge         = 0.015;
uniform float u_blob_pulse        = 0.0;

uniform vec2  u_blob2_pos         = vec2(-1.0);
uniform float u_blob2_radius      = 0.0;
uniform float u_blob2_pulse       = 0.0;

uniform float u_ambient_flow  = 0.0;
uniform float u_ambient_scale  = 3.0;
uniform float u_dye_diffuse   = 0.0;

vec4 decode(vec4 t) {
	return vec4(t.rg * 2.0 - 1.0, t.b, t.a * 2.0 - 1.0);
}

vec4 samp(vec2 uv) {
	return decode(texture(u_prev, uv));
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-7), 0.0, 1.0);
	return length(pa - ba * h);
}

void apply_blob(vec2 uv, vec2 bpos, float bradius, float bpulse, inout vec2 newVel, inout float dye) {
	if (bpos.x < 0.0 || bradius <= 0.0) { return; }
	vec2 bd = uv - bpos;
	bd.x *= u_blob_aspect;
	float d = length(bd);
	float m = 1.0 - smoothstep(bradius - u_blob_edge, bradius + u_blob_edge, d);
	if (m <= 0.0) { return; }

	vec2 turb = curlNoise(uv * u_blob_swirl_scale + u_time * u_blob_swirl_speed);
	turb += 0.6 * curlNoise(uv * (u_blob_swirl_scale * 2.3) - u_time * (u_blob_swirl_speed * 1.7));
	turb += 0.3 * curlNoise(uv * (u_blob_swirl_scale * 5.1) + u_time * (u_blob_swirl_speed * 2.6));
	newVel += turb * m * u_blob_swirl * (1.0 + bpulse * 3.5);

	float rim = smoothstep(bradius * 0.4, bradius + u_blob_edge, d);
	newVel -= normalize(bd + vec2(1e-5)) * rim * m * (0.018 + bpulse * 0.06);

	float ceil = clamp(u_blob_ceil + bpulse * 0.22, 0.0, 1.0);
	dye += m * u_blob_dye * (1.0 + bpulse * 0.5) * max(0.0, ceil - dye);
}

void fragment() {
	if (u_reset) {
		// encoded zero state: vel = 0, dye = 0, pressure = 0
		COLOR = vec4(0.5, 0.5, 0.0, 0.5);
	} else {
		vec2 texel = 1.0 / u_resolution;
		vec2 uv = UV;

		vec4 C = samp(uv);
		vec4 L = samp(uv + vec2(-texel.x, 0.0));
		vec4 R = samp(uv + vec2( texel.x, 0.0));
		vec4 T = samp(uv + vec2(0.0,  texel.y));
		vec4 B = samp(uv + vec2(0.0, -texel.y));

		vec2 vel = C.rg;

		// Semi-Lagrangian advection: trace back along the velocity field.
		float rdx = min(u_resolution.x, u_resolution.y);
		vec2 prevUV = uv - vel * u_dt / rdx;
		vec4 advected = samp(prevUV);

		// Diffusion (one Jacobi iteration).
		float alpha = 1.0 / (u_viscosity * u_dt);
		float rBeta = 1.0 / (4.0 + alpha);
		vec2 diffusedVel = (L.rg + R.rg + T.rg + B.rg + alpha * advected.rg) * rBeta;

		// Divergence + single-pass pressure Jacobi.
		float div = 0.5 * ((R.r - L.r) + (T.g - B.g));
		float pressure = (L.a + R.a + T.a + B.a - div) * 0.25;

		// Project velocity to be (approximately) divergence-free.
		vec2 gradP = 0.5 * vec2(R.a - L.a, T.a - B.a);
		vec2 newVel = diffusedVel - gradP;

		// Vorticity confinement (faithful to the source shader).
		float vL = (samp(uv + vec2(-texel.x,  texel.y)).g - samp(uv + vec2(-texel.x, -texel.y)).g) * 0.5
				 - (samp(uv + vec2(0.0,  texel.y)).r - samp(uv + vec2(0.0, -texel.y)).r) * 0.5;
		float vR = (samp(uv + vec2( texel.x,  texel.y)).g - samp(uv + vec2( texel.x, -texel.y)).g) * 0.5
				 - (samp(uv + vec2(0.0,  texel.y)).r - samp(uv + vec2(0.0, -texel.y)).r) * 0.5;
		float vort = (samp(uv + vec2(0.0,  texel.y)).r - samp(uv + vec2(0.0, -texel.y)).r)
				   - (samp(uv + vec2( texel.x, 0.0)).g - samp(uv + vec2(-texel.x, 0.0)).g);
		vec2 vortForce = u_vorticity * vec2(abs(vR) - abs(vL), abs(vR) - abs(vL));
		vortForce = length(vortForce) > 0.0 ? normalize(vortForce) * vort * vec2(1.0, -1.0) : vec2(0.0);
		newVel += vortForce * 0.0005;

		if (u_ambient_flow > 0.0) {
			vec2 cn = curlNoise(uv * u_ambient_scale + u_time * 0.05);
			newVel += cn * u_ambient_flow;
		}

		// Damping so energy cannot accumulate without bound.
		newVel *= 0.999;

		// Dye advects with the flow and slowly fades.
		float dyeAvg = (L.b + R.b + T.b + B.b) * 0.25;
		float dye = mix(advected.b, dyeAvg, u_dye_diffuse) * u_dissipation;

		// External force / dye injection (mouse drag).
		if (u_force_pos.x >= 0.0) {
			float dist = length(uv - u_force_pos);
			float influence = exp(-dist * dist / (u_force_radius * u_force_radius));
			newVel += u_force_dir * influence * 0.5;
			dye += influence * 0.3;
		}

		// Text sparks: sum the halo of tiny ember injections.
		float spark_r2 = u_spark_radius * u_spark_radius;
		for (int i = 0; i < MAX_SPARKS; i++) {
			if (i >= u_spark_count) { break; }
			float s = u_spark_strength[i];
			if (s <= 0.0) { continue; }
			float sd = seg_dist(uv, u_spark_pos[i], u_spark_end[i]);
			float influence = exp(-(sd * sd) / spark_r2) * s;
			newVel += u_spark_vel[i] * influence;
			dye += influence * 0.5;
		}

		if (u_text_amount > 0.0 || u_text_calm > 0.0 || u_text_stir > 0.0) {
			float m = texture(u_text_mask, uv).r;
			dye += m * u_text_amount;
			newVel = mix(newVel, vec2(0.0), clamp(m * u_text_calm, 0.0, 1.0));

			float md = m;
			md = max(md, texture(u_text_mask, uv + vec2(texel.x * 3.0, 0.0)).r);
			md = max(md, texture(u_text_mask, uv - vec2(texel.x * 3.0, 0.0)).r);
			md = max(md, texture(u_text_mask, uv + vec2(0.0, texel.y * 3.0)).r);
			md = max(md, texture(u_text_mask, uv - vec2(0.0, texel.y * 3.0)).r);
			vec2 swirl = curlNoise(uv * u_text_stir_scale + u_time * u_text_stir_speed);
			newVel += swirl * md * u_text_stir;
		}

		newVel *= mix(1.0, 0.9, u_text_settle);

		apply_blob(uv, u_blob_pos, u_blob_radius, u_blob_pulse, newVel, dye);
		apply_blob(uv, u_blob2_pos, u_blob2_radius, u_blob2_pulse, newVel, dye);

		newVel = clamp(newVel, vec2(-1.0), vec2(1.0));
		pressure = clamp(pressure, -1.0, 1.0);
		dye = clamp(dye, 0.0, 1.0);

		COLOR = vec4(newVel * 0.5 + 0.5, dye, pressure * 0.5 + 0.5);
	}
}
