shader_type canvas_item;
uniform vec2 part_size = vec2(1.0);
uniform float top_fade = 0.0;
uniform float bottom_round = 0.0;
uniform float tip_center_x = 0.5;
uniform float tip_radius_x = 0.3;
varying vec2 part_position;

void vertex() {
	part_position = VERTEX / part_size;
}

void fragment() {
	float mask = 1.0;
	if (top_fade > 0.0) {
		mask *= smoothstep(0.015, top_fade, part_position.y);
	}
	if (bottom_round > 0.0) {
		float center_y = 1.0 - bottom_round;
		if (part_position.y > center_y) {
			vec2 p = vec2((part_position.x - tip_center_x) / tip_radius_x,
				(part_position.y - center_y) / bottom_round);
			mask *= 1.0 - smoothstep(0.92, 1.0, length(p));
		}
	}
	COLOR.a *= mask;
}
