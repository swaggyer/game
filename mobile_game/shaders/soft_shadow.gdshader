shader_type canvas_item;
render_mode unshaded;
uniform vec4 shadow_color : source_color=vec4(0.12,0.22,0.15,0.29);
void fragment(){
    float d=length((UV-0.5)*2.0);
    float alpha=(1.0-smoothstep(0.08,1.0,d));
    alpha*=alpha;
    COLOR=vec4(shadow_color.rgb,shadow_color.a*alpha);
}
