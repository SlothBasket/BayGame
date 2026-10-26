shader_type canvas_item;
uniform bool chart = false;
uniform float overlay_opacity = 0.55;
uniform bool provenance_view = false;
uniform sampler2D provenance_texture : filter_nearest;
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
    // Styling uses available neighbors and a soft teal default. This never
    // enters DepthService, navigation decisions, or numeric soundings.
    vec4 known = vec4(zs.x<9000.0?1.0:0.0,zs.y<9000.0?1.0:0.0,zs.z<9000.0?1.0:0.0,zs.w<9000.0?1.0:0.0);
    float coverage = dot(known,weights);
    vec4 safe_z = min(zs,vec4(0.0));
    float neighbor_depth = max(-dot(safe_z*known,weights)/max(coverage,0.00001),0.0);
    float visual_depth = mix(2.0,neighbor_depth,smoothstep(0.0,1.0,coverage));
    vec3 shallow = vec3(0.16,0.48,0.46);
    vec3 deep = vec3(0.045,0.24,0.33);
    vec3 color = mix(shallow,deep,clamp(visual_depth/18.0,0.0,1.0));
    if (chart && valid && neighbor_depth>0.0) {
        float interval=5.0/3.280839895;
        float edge=abs(fract(neighbor_depth/interval+0.5)-0.5)*interval;
        float width=max(fwidth(neighbor_depth),0.025);
        color=mix(vec3(0.49,0.72,0.69),color,smoothstep(0.0,width,edge));
    }
    if (provenance_view) {
        float kind=texture(provenance_texture,(q+vec2(.5))/(cells+3.0)).r*255.0/64.0;
        color=kind<.5 ? vec3(.62,.17,.32) : (kind>2.5 ? vec3(.92,.64,.14) : vec3(.15,.62,.85));
    }
    COLOR=vec4(color,provenance_view ? 1.0 : overlay_opacity);
}
