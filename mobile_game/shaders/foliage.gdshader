shader_type canvas_item;
render_mode unshaded;
uniform float clock=0.0;
varying vec4 vertex_tint;
void vertex(){
    vec2 p=(MODEL_MATRIX*vec4(VERTEX,0.,1.)).xy;
    VERTEX.x+=sin(clock*1.35+p.x*0.011+p.y*0.009)*pow(1.0-UV.y,2.0)*3.5;
    vertex_tint=COLOR;
}
void fragment(){COLOR=texture(TEXTURE,UV)*vertex_tint;}
