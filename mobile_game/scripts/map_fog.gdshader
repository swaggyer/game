shader_type canvas_item;
render_mode unshaded;
uniform sampler2D exploration : filter_linear, repeat_disable;
uniform vec4 fog_color : source_color = vec4(0.06,0.16,0.20,0.70);
void fragment(){
    vec2 d=vec2(1.0/17.0,1.0/12.0)*0.45;
    float v=texture(exploration,UV).r*0.28;
    v+=(texture(exploration,UV+vec2(d.x,0.0)).r+texture(exploration,UV-vec2(d.x,0.0)).r+texture(exploration,UV+vec2(0.0,d.y)).r+texture(exploration,UV-vec2(0.0,d.y)).r)*0.12;
    v+=(texture(exploration,UV+d).r+texture(exploration,UV-d).r+texture(exploration,UV+vec2(d.x,-d.y)).r+texture(exploration,UV+vec2(-d.x,d.y)).r)*0.06;
    float fog=1.0-smoothstep(0.12,0.80,v);
    COLOR=vec4(fog_color.rgb,fog*fog_color.a);
}
