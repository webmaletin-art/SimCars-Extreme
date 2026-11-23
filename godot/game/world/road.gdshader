// Cinta del camino: textura + tinte por vértice, y AGUJEROS donde hay baches (la malla de cada bache dibuja el hueco real debajo).
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec4 holes[40]; // x, z, radio, -
uniform int n_holes = 0;

varying vec3 wp;
varying vec4 vc;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vc = COLOR;
}

void fragment() {
	for (int i = 0; i < n_holes; i++) {
		vec2 d = wp.xz - holes[i].xy;
		if (dot(d, d) < holes[i].z * holes[i].z) {
			discard;
		}
	}
	ALBEDO = texture(tex, UV).rgb * vc.rgb * tint;
	ROUGHNESS = 0.95;
}
