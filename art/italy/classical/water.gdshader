shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.42, 0.70, 0.74, 0.88);
uniform vec4 deep_color : source_color = vec4(0.16, 0.38, 0.52, 0.94);
uniform float speed = 0.28;
uniform float foam = 0.35;

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 uv = world_xz * 0.42;
	float w1 = sin(uv.x * 11.0 + TIME * speed * 4.0);
	float w2 = sin(uv.y * 8.5 - TIME * speed * 2.6);
	float w3 = sin((uv.x + uv.y) * 6.5 + TIME * speed * 1.8);
	float waves = (w1 + w2 + w3) * 0.333;
	float crest = max(waves, 0.0);
	vec3 col = mix(deep_color.rgb, shallow_color.rgb, 0.45 + waves * 0.22);
	col += vec3(0.10, 0.12, 0.10) * crest * foam;
	ALBEDO = col;
	ROUGHNESS = clamp(0.16 - waves * 0.04, 0.05, 0.4);
	METALLIC = 0.06;
	ALPHA = mix(deep_color.a, shallow_color.a, 0.5 + crest * 0.1);
	EMISSION = col * 0.035;
}
