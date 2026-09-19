shader_type canvas_item;
// 发色/瞳色运行时调色(仿 GraphicMaker 色相·彩度调整): 色相旋转 + 彩度缩放, 亮度不动。
// 黑描边/白高光饱和度≈0, 旋转与缩放均无可见影响, 无需阈值。
// 参数: hue_shift 为圈数(0..1 对应 0..360°), sat_scale 为彩度倍率(0..2, 1=原样)。

uniform float hue_shift : hint_range(0.0, 1.0) = 0.0;
uniform float sat_scale : hint_range(0.0, 2.0) = 1.0;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec4 col = texture(TEXTURE, UV);
	vec3 hsv = rgb2hsv(col.rgb);
	hsv.x = fract(hsv.x + hue_shift);
	hsv.y = clamp(hsv.y * sat_scale, 0.0, 1.0);
	COLOR = vec4(hsv2rgb(hsv), col.a);
}
