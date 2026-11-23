// Vegetación en cruz (papercraft): sprite con borde recortado, sin luz propia, que se mece con el viento.
// La copa se mueve más que el pie (UV.y = 0 arriba, 1 abajo). INSTANCE_CUSTOM.x = sacudón extra (un golpe del auto), decae solo en el script.
shader_type spatial;

global uniform vec3 car_pos;
uniform float push_k = 1.0; // cuánto se aparta con el auto (árboles: 0)
uniform float push_r = 2.6;
render_mode unshaded, cull_disabled, depth_prepass_alpha;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float wind : hint_range(0.0, 2.0) = 0.6;
uniform float speed = 1.6;
uniform float amp = 0.05;
uniform vec3 tint : source_color = vec3(1.0);
uniform float alpha_cut = 0.45;
uniform float fade_start = 90.0;
uniform float fade_end = 140.0;

varying float v_fade;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float h = pow(clamp(1.0 - UV.y, 0.0, 1.0), 1.7);
	float ph = origin.x * 0.31 + origin.z * 0.23;
	float gust = sin(TIME * speed + ph) * 0.7 + sin(TIME * speed * 2.3 + ph * 1.7) * 0.3;
	float k = INSTANCE_CUSTOM.x;
	VERTEX.x += (gust * wind * amp + sin(TIME * 14.0 + ph) * k * 0.08) * h * 2.0;
	VERTEX.z += (cos(TIME * speed * 0.8 + ph) * wind * amp * 0.5 + cos(TIME * 11.0 + ph) * k * 0.05) * h * 2.0;
	// el auto aparta el pasto, las flores y las matas a su paso (se doblan hacia afuera y se agachan)
	if (push_k > 0.0) {
		vec3 wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec2 rel = wpos.xz - car_pos.xz;
		float dist = length(rel);
		float pk = smoothstep(push_r, 0.3, dist) * h * push_k;
		vec2 dn = rel / max(dist, 0.05);
		vec3 loc = transpose(mat3(MODEL_MATRIX)) * vec3(dn.x, 0.0, dn.y);
		VERTEX.xz += loc.xz * pk * 0.9;
		VERTEX.y -= pk * 0.25;
	}
	v_fade = 1.0;
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	if (t.a < alpha_cut) {
		discard;
	}
	ALBEDO = t.rgb * tint;
	ALPHA = 1.0;
}
