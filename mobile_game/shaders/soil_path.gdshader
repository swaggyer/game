shader_type canvas_item;
render_mode unshaded;
uniform vec4 soil_shadow : source_color=vec4(0.53,0.42,0.25,1.);
uniform vec4 soil_light : source_color=vec4(0.78,0.67,0.43,1.);
uniform float clock=0.0;
uniform float worn_stone=0.0;
uniform int water_count=0;
uniform int land_count=0;
uniform int bridge_count=0;
uniform int polygon_count=0;
uniform vec4 water_shapes[4];
uniform float water_kinds[4];
uniform vec4 land_shapes[6];
uniform vec4 bridge_shapes[8];
uniform vec2 water_polygon[16];
varying vec2 world_position;
varying vec4 vertex_tint;
float hash21(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453123);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash21(i),hash21(i+vec2(1.,0.)),f.x),mix(hash21(i+vec2(0.,1.)),hash21(i+1.),f.x),f.y);}
void vertex(){world_position=(MODEL_MATRIX*vec4(VERTEX,0.,1.)).xy;vertex_tint=COLOR;}
float shape_inside(vec2 p,vec4 shape,float kind,float aa){
    vec2 q=abs(p-shape.xy);
    float d=kind<0.5 ? (length(q/max(shape.zw,vec2(0.1)))-1.0)*min(shape.z,shape.w) : max(q.x-shape.z,q.y-shape.w);
    return 1.0-smoothstep(-aa,aa,d);
}
float water_mask(vec2 p){
    float aa=max(length(fwidth(p)),0.8);
    float wet=0.0;
    for(int i=0;i<4;i++){
        if(i>=water_count){break;}
        float inside=shape_inside(p,water_shapes[i],water_kinds[i],aa);
        if(i==0 && land_count>0){
            float land=0.0;
            for(int j=0;j<6;j++){if(j>=land_count){break;}land=max(land,shape_inside(p,land_shapes[j],0.0,aa));}
            inside*=1.0-land;
        }
        wet=max(wet,inside);
    }
    if(polygon_count>2){
        bool inside=false;
        int j=polygon_count-1;
        for(int i=0;i<16;i++){
            if(i>=polygon_count){break;}
            vec2 a=water_polygon[i],b=water_polygon[j];
            if((a.y>p.y)!=(b.y>p.y) && p.x<(b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x){inside=!inside;}
            j=i;
        }
        if(inside){wet=1.0;}
    }
    for(int i=0;i<8;i++){if(i>=bridge_count){break;}wet*=1.0-shape_inside(p,bridge_shapes[i],1.0,aa);}
    return wet;
}
void fragment(){
    vec2 p=world_position;
    float n=noise(p*0.014)*0.7+noise(p*0.065)*0.3;
    float edge=abs(UV.y-0.5)*2.0;
    float irregular=noise(p*0.026)*0.11+noise(p*0.16)*0.025;
    float alpha=1.0-smoothstep(0.74,1.0,edge+irregular-0.04);
    vec3 color=mix(soil_shadow.rgb,soil_light.rgb,0.30+n*0.58);
    color*=1.0-smoothstep(0.45,0.98,edge)*0.08;
    vec2 pebble_cell=p*0.046;
    vec2 cell=floor(pebble_cell);
    vec2 jitter=vec2(hash21(cell),hash21(cell+32.1));
    float dist=length(fract(pebble_cell)-mix(vec2(0.18),vec2(0.82),jitter));
    float aa=max(fwidth(dist),0.01);
    float pebble=(1.0-smoothstep(0.04-aa,0.04+aa,dist))*step(0.74,hash21(cell+7.3));
    color=mix(color,mix(vec3(0.60,0.57,0.44),vec3(0.83,0.79,0.61),jitter.y),pebble*0.65);
    float cloud=noise(p*0.0018+vec2(clock*0.009,-clock*0.004));
    color*=1.0-smoothstep(0.5,0.76,cloud)*0.11;
    COLOR=vec4(color,alpha*vertex_tint.a*(1.0-water_mask(p)));
}
