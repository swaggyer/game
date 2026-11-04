shader_type canvas_item;
render_mode unshaded;
uniform vec4 deep_color : source_color = vec4(0.08,0.40,0.52,1.0);
uniform vec4 shallow_color : source_color = vec4(0.35,0.68,0.61,1.0);
uniform vec4 foam_color : source_color = vec4(0.85,0.95,0.80,1.0);
uniform float clock=0.0;
uniform int shape_kind=0;
uniform vec2 shape_size=vec2(800.0,500.0);
uniform float magical=0.0;
varying vec2 world_position;
varying vec4 vertex_tint;
float hash21(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453123);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);return mix(mix(hash21(i),hash21(i+vec2(1.,0.)),f.x),mix(hash21(i+vec2(0.,1.)),hash21(i+1.),f.x),f.y);}
void vertex(){world_position=(MODEL_MATRIX*vec4(VERTEX,0.,1.)).xy;vertex_tint=COLOR;}
void fragment(){
    vec2 p=world_position;
    vec2 q=(UV-0.5)*shape_size;
    float edge=shape_kind==0 ? (1.0-length((UV-0.5)*2.0))*min(shape_size.x,shape_size.y)*0.5 : min(shape_size.x*0.5-abs(q.x),shape_size.y*0.5-abs(q.y));
    if(shape_kind==2){edge+=50.0;}
    float ripples=noise(p*0.011+vec2(clock*0.015,-clock*0.019));
    float depth=smoothstep(2.0,115.0,edge+ripples*20.0);
    vec3 color=mix(shallow_color.rgb,deep_color.rgb,depth);
    color*=0.92+ripples*0.15;
    vec2 drift=vec2(sin(p.y*0.018+clock*0.8),cos(p.x*0.019-clock*0.6))*0.9;
    float c1=sin((p.x+drift.x*18.0)*0.061+sin(p.y*0.037+clock*0.4)*1.7);
    float c2=sin((p.y+drift.y*19.0)*0.074+sin(p.x*0.031-clock*0.3)*1.5);
    float caustic=pow(max(0.0,1.0-abs(c1+c2)*0.65),10.0);
    color+=shallow_color.rgb*caustic*0.105*(1.0-magical*0.5);
    float wave=sin(p.x*0.022+p.y*0.047+clock*0.95)+sin(p.x*0.013-p.y*0.035-clock*0.6);
    float glint=smoothstep(1.92,1.99,wave)*smoothstep(0.45,0.75,ripples);
    color+=vec3(0.75,0.88,0.66)*glint*0.40;
    float wash=2.5+sin(clock*1.3+p.x*0.018+p.y*0.021)*1.8;
    float foam=1.0-smoothstep(wash,wash+3.5,edge);
    color=mix(color,foam_color.rgb,foam*0.50);
    COLOR=vec4(color,vertex_tint.a);
}
