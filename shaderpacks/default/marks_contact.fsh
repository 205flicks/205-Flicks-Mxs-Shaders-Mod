#version 150
in vec2 v_uv;out vec4 f_color;
uniform sampler2D u_heightmap;
uniform vec2 u_extent;
uniform vec4 u_wheel0,u_wheel1;
uniform vec3 u_axis0,u_axis1,u_bottom0,u_bottom1;
uniform float u_tolerance,u_soil_scale;
uniform sampler2D u_soil;
uniform int u_sample_surface;
float ground(vec2 p){return textureLod(u_heightmap,p/u_extent+0.5/vec2(textureSize(u_heightmap,0)),0.0).r;}
vec2 slope_at(vec2 p)
{
    vec2 cell=u_extent/vec2(textureSize(u_heightmap,0));
    return vec2(ground(p+vec2(cell.x,0))-ground(p-vec2(cell.x,0)),
                ground(p+vec2(0,cell.y))-ground(p-vec2(0,cell.y)))/(2.0*cell);
}
// Read the visible terrain material's base color at the wheel contact.
vec4 sample_coating(vec3 bottom)
{
    if(u_sample_surface==0 || u_soil_scale<=0.0) return vec4(0);
    vec3 c=textureLod(u_soil,bottom.xz*u_soil_scale,0.0).rgb;
    float warmth=c.r-c.b;
    // Accept muted soil, tan sand, and dark earth. Retain the last coating
    // when the contact is on grass, a saturated marking, or near-white.
    if(c.r<0.045 || c.r>0.95 || warmth<0.012 ||
       c.g<c.b-0.018 || c.g>c.r+0.008 ||
       c.r-c.g>0.62*warmth+0.022 || c.b>0.82)
        return vec4(0);
    return vec4(c,1);
}
void main(){
 bool rear=gl_FragCoord.y>1.0;
 vec4 wheel=rear?u_wheel1:u_wheel0;vec3 axis=normalize(rear?u_axis1:u_axis0);
 vec3 bottom=rear?u_bottom1:u_bottom0;
 // Keep the original footprint whenever it already passes its contact test.
 // Repair on both cross slopes and uphill/downhill surfaces.
 f_color=vec4(bottom,1e20);
 vec2 old_slope=slope_at(bottom.xz);
 if(any(lessThan(bottom.xz,vec2(0)))||any(greaterThanEqual(bottom.xz,u_extent)))return;
 float normalY=inversesqrt(1.0+dot(old_slope,old_slope));
 float initial=(bottom.y-ground(bottom.xz))*normalY;
 if(abs(initial)<=wheel.w*u_tolerance && abs(bottom.y-ground(bottom.xz))<=wheel.w*u_tolerance){
  f_color=gl_FragCoord.x>1.0?sample_coating(bottom):vec4(bottom,initial);
  return;
 }
 float old_gap=bottom.y-ground(bottom.xz);
 if(abs(old_gap)<=wheel.w*u_tolerance){
  f_color=gl_FragCoord.x>1.0?sample_coating(bottom):vec4(bottom,old_gap*inversesqrt(1.0+dot(old_slope,old_slope)));
  return;
 }
 vec3 down=vec3(0,-1,0)-axis*dot(axis,vec3(0,-1,0));
 if(dot(down,down)<1e-6)down=cross(axis,vec3(1,0,0));
 down=normalize(down);vec3 side=normalize(cross(axis,down));
 float angle=0.0,best=1e30,step=6.28318530718/64.0;
 for(int i=0;i<64;i++){
  float a=float(i)*step;vec3 p=wheel.xyz+wheel.w*(down*cos(a)+side*sin(a));
  float gap=p.y-ground(p.xz);if(gap<best){best=gap;angle=a;}
 }
 for(int i=0;i<7;i++){
  step*=0.5;float chosen=angle;
  for(int j=-1;j<=1;j+=2){float a=angle+float(j)*step;vec3 p=wheel.xyz+wheel.w*(down*cos(a)+side*sin(a));
   float gap=p.y-ground(p.xz);if(gap<best){best=gap;chosen=a;}}
  angle=chosen;
 }
 vec3 p=wheel.xyz+wheel.w*(down*cos(angle)+side*sin(angle));
 vec2 slope=slope_at(p.xz);
 float h=ground(p.xz),gap=(p.y-h)*inversesqrt(1.0+dot(slope,slope));
 if(any(lessThan(p.xz,vec2(0)))||any(greaterThanEqual(p.xz,u_extent)))gap=1e20;
 f_color=gl_FragCoord.x>1.0?sample_coating(vec3(p.x,h,p.z)):vec4(p.x,h,p.z,gap);
}
