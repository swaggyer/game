shader_type canvas_item;
render_mode unshaded;
uniform float clock=0.0;
varying vec2 world_position;
varying vec4 vertex_tint;
void vertex(){world_position=(MODEL_MATRIX*vec4(VERTEX,0.,1.)).xy;vertex_tint=COLOR;}
void fragment(){
    float broken=0.45+0.55*sin(world_position.x*0.036+sin(world_position.y*0.027)*3.0+clock*0.9);
    COLOR=vec4(vertex_tint.rgb,vertex_tint.a*smoothstep(0.0,0.85,broken));
}
