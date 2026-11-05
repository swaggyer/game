shader_type canvas_item;
render_mode unshaded;

uniform vec4 grass_shadow : source_color = vec4(0.30,0.46,0.23,1.0);
uniform vec4 grass_sun : source_color = vec4(0.55,0.68,0.34,1.0);
uniform vec4 warm_light : source_color = vec4(1.0,0.94,0.77,1.0);
uniform float clock = 0.0;
uniform float cloud_strength = 0.19;
varying vec2 world_position;
varying vec4 vertex_tint;

// Shared baked random lattice: hardware bilinear interpolation retains the
// original smooth cubic value noise, with no per-pixel sine-based hash.
uniform sampler2D noise_lattice : filter_linear, repeat_enable;
float hash21(vec2 p) { return texture(noise_lattice,(mod(p,256.0)+vec2(0.5))/256.0).r; }
float noise(vec2 p) {
    vec2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f);
    return texture(noise_lattice,(mod(i,256.0)+f+vec2(0.5))/256.0).r;
}
float fbm(vec2 p) {
    float n=noise(p)*0.55;
    p=mat2(vec2(1.62,1.18),vec2(-1.18,1.62))*p;
    n+=noise(p+13.6)*0.28;
    n+=noise(p*2.03-7.2)*0.17;
    return n;
}
void vertex(){ world_position=(MODEL_MATRIX*vec4(VERTEX,0.0,1.0)).xy; vertex_tint=COLOR; }
void fragment(){
    vec2 p=world_position;
    float meadow=fbm(p*0.0042);
    float paint=fbm(p*0.038+meadow*2.0);
    float hill_light=smoothstep(0.25,0.77,fbm(p*0.0028+vec2(-1.4,0.8)));
    vec3 color=mix(grass_shadow.rgb,grass_sun.rgb,smoothstep(0.14,0.86,meadow));
    color*=0.91+paint*0.17;
    color=mix(color,color*warm_light.rgb*1.18,hill_light*0.45);
    float clouds=fbm(p*0.00135+vec2(clock*0.009,-clock*0.004));
    color*=1.0-smoothstep(0.47,0.77,clouds)*cloud_strength;
    float blade=noise(vec2(p.x*0.37+p.y*0.17,p.y*0.13));
    color+=vec3(0.033,0.036,0.012)*(blade-0.5);
    COLOR=vec4(color,vertex_tint.a);
}
