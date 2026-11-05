shader_type canvas_item;
render_mode unshaded;
uniform bool wooden=true;
uniform bool horizontal=true;
uniform vec2 deck_size=vec2(600.0,180.0);
uniform vec4 wood_light:source_color=vec4(0.64,0.43,0.22,1.);
varying vec4 vertex_tint;
// Shared baked random lattice: hardware bilinear interpolation retains the
// original smooth cubic value noise, with no per-pixel sine-based hash.
uniform sampler2D noise_lattice : filter_linear, repeat_enable;
float hash21(vec2 p) { return texture(noise_lattice,(mod(p,256.0)+vec2(0.5))/256.0).r; }
float noise(vec2 p) {
    vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
    return texture(noise_lattice,(mod(i,256.0)+f+vec2(0.5))/256.0).r;
}
void vertex(){vertex_tint=COLOR;}
void fragment(){
    vec2 q=UV*deck_size;
    if(!horizontal){q=q.yx;}
    vec3 color;
    if(wooden){
        float board=floor(q.x/28.0);
        float seam=1.0-smoothstep(0.02,0.09,abs(fract(q.x/28.0)-0.5)*2.0);
        float bevel=smoothstep(0.0,0.09,fract(q.x/28.0))*(1.0-smoothstep(0.91,1.0,fract(q.x/28.0)));
        float grain=noise(vec2(q.x*0.18,q.y*0.014))*0.14+sin(q.y*0.31+noise(vec2(q.x*0.12,q.y*0.021))*9.0)*0.025;
        color=wood_light.rgb*(0.83+hash21(vec2(board,8.0))*0.22+grain);
        color*=0.55+bevel*0.45;
    }else{
        float row=floor(q.y/45.0);
        vec2 block=vec2(q.x/85.0+mod(row,2.0)*0.5,q.y/45.0);
        vec2 f=fract(block);
        float bevel=smoothstep(0.0,0.035,min(min(f.x,1.-f.x),min(f.y,1.-f.y)));
        float variation=hash21(floor(block));
        color=mix(vec3(0.52,0.58,0.48),vec3(0.77,0.80,0.65),variation*0.55+0.25)*mix(0.63,1.0,bevel);
        color+=noise(q*0.14)*0.035;
    }
    COLOR=vec4(color,vertex_tint.a);
}
