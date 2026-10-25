shader_type canvas_item;
uniform vec2 tile_origin;
uniform float pixel_size=1.0;
varying vec2 map_position;
void vertex() { map_position=VERTEX+tile_origin; }
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void fragment() {
 float broad=noise(map_position/220.0);
 float detail=(noise(map_position/12.0)-0.5)*(1.0-smoothstep(2.0,12.0,pixel_size));
 vec3 color=mix(vec3(.29,.39,.30),vec3(.40,.47,.34),broad);
 COLOR=vec4(color+detail*.012,1.0);
}
