shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.45, 0.78, 0.74, 1.0);
uniform vec4 deep_color : source_color = vec4(0.08, 0.32, 0.42, 1.0);
uniform vec4 foam_color : source_color = vec4(0.93, 0.90, 0.78, 1.0);
uniform float speed = 0.22;
uniform float foam = 0.35;

varying vec2 world_xz;

float ripple(vec2 p) {
	float a = sin(p.x * 9.0 + TIME * speed * 3.2);
	float b = sin(p.y * 7.2 - TIME * speed * 2.4);
	float c = sin((p.x + p.y) * 5.4 + TIME * speed * 1.6);
	float d = sin((p.x - p.y * 0.8) * 14.0 - TIME * speed * 4.0);
	return a * 0.36 + b * 0.30 + c * 0.22 + d * 0.12;
}

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	if (VERTEX.y >= 0.0) {
		VERTEX.y += ripple(world_xz) * 0.012;
	}
}

void fragment() {
	vec2 uv = world_xz;
	float h = ripple(uv);
	float hx = ripple(uv + vec2(0.04, 0.0)) - h;
	float hz = ripple(uv + vec2(0.0, 0.04)) - h;
	vec3 world_n = normalize(vec3(-hx * 5.5, 1.0, -hz * 5.5));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);

	float depth = clamp(0.55 + h * 0.28, 0.0, 1.0);
	vec3 col = mix(deep_color.rgb, shallow_color.rgb, depth);

	float caustic = sin(uv.x * 18.0 + TIME * speed * 2.0) * sin(uv.y * 15.0 - TIME * speed * 1.5);
	caustic = caustic * caustic;
	col = mix(col, shallow_color.rgb * vec3(1.12, 1.16, 1.05), caustic * 0.22);

	float crest = smoothstep(0.35, 0.9, h);
	col = mix(col, foam_color.rgb, crest * foam * 0.55);

	ALBEDO = col;
	ROUGHNESS = clamp(0.22 - crest * 0.14, 0.06, 0.45);
	METALLIC = 0.02;
	SPECULAR = 0.55;
	ALPHA = 1.0;
}
