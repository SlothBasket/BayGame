shader_type canvas_item;
uniform bool chart = false;
uniform float cells = 64.0;
void fragment() {
    vec2 q = UV*cells+vec2(1.0);
    vec2 i = floor(q);
    vec2 f = fract(q);
    vec4 zs = vec4(texture(TEXTURE,(i+vec2(0.5,0.5))/(cells+3.0)).r,
                   texture(TEXTURE,(i+vec2(1.5,0.5))/(cells+3.0)).r,
                   texture(TEXTURE,(i+vec2(0.5,1.5))/(cells+3.0)).r,
                   texture(TEXTURE,(i+vec2(1.5,1.5))/(cells+3.0)).r);
    vec4 weights=vec4((1.0-f.x)*(1.0-f.y),f.x*(1.0-f.y),(1.0-f.x)*f.y,f.x*f.y);
    bool valid = !any(bvec4(zs.x>9000.0 && weights.x>0.000001,
                           zs.y>9000.0 && weights.y>0.000001,
                           zs.z>9000.0 && weights.z>0.000001,
                           zs.w>9000.0 && weights.w>0.000001));
    float z = valid ? dot(zs,weights) : 10000.0;
    float depth = max(-z,0.0);
    vec3 shallow = vec3(0.16,0.48,0.46);
    vec3 deep = vec3(0.025,0.15,0.24);
    vec3 color = mix(shallow,deep,clamp(depth/15.0,0.0,1.0));
    if (z>9000.0) color=vec3(0.075,0.14,0.17);
    if (chart && z<0.0 && z>-9000.0) {
        float edge=abs(fract(depth/(5.0/3.280839895)+0.5)-0.5)*(5.0/3.280839895);
        float width=max(fwidth(depth),0.015);
        color=mix(vec3(0.35,0.65,0.65),color,smoothstep(0.0,width,edge));
    }
    COLOR=vec4(color,1.0);
}
