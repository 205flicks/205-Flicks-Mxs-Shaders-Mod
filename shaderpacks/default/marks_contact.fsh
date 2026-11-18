#version 150
in vec2 v_uv;out vec4 f_color;
uniform sampler2D u_heightmap;
uniform vec2 u_extent;
uniform vec4 u_wheel0,u_wheel1;
uniform vec3 u_axis0,u_axis1,u_bottom0,u_bottom1;
uniform float u_tolerance,u_soil_scale;
uniform sampler2D u_soil;
uniform int u_sample_surface,u_packed_lines;
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
// Search the tire tread across its width, so a shoulder can contact a cambered rut.
vec4 packed_footprint(vec4 wheel,vec3 axis,float half_width)
{
    vec3 down=vec3(0,-1,0)+axis*axis.y;
    if(dot(down,down)<0.0001)down=vec3(1,0,0)-axis*axis.x;
    down=normalize(down);
    vec3 tangent=normalize(cross(axis,down));
    float best=1e20;
    vec3 footprint=wheel.xyz;
    vec3 centers[3];
    float gaps[3];
    for(int side=-1;side<=1;side++){
        float lateral=float(side)*half_width*0.72;
        float radius=wheel.w*(side==0?1.0:0.96);
        float ringBest=1e20, angle=0.0;
        vec3 ringPoint=wheel.xyz;
        for(int i=0;i<32;i++){
            float a=float(i)*0.19634954;
            vec3 pt=wheel.xyz+axis*lateral+radius*(down*cos(a)+tangent*sin(a));
            if(any(lessThan(pt.xz,vec2(0)))||any(greaterThanEqual(pt.xz,u_extent)))continue;
            float h=ground(pt.xz), gap=pt.y-h;
            if(gap<ringBest){ringBest=gap;angle=a;ringPoint=pt;}
            if(gap<best){best=gap;footprint=vec3(pt.x,h,pt.z);}
        }

        if(ringBest<1e19){
            float angularStep=0.09817477;
            for(int refine=0;refine<3;refine++){
                float next=angle;
                for(int direction=-1;direction<=1;direction+=2){
                    float a=angle+float(direction)*angularStep;
                    vec3 pt=wheel.xyz+axis*lateral+radius*(down*cos(a)+tangent*sin(a));
                    if(any(lessThan(pt.xz,vec2(0)))||any(greaterThanEqual(pt.xz,u_extent)))continue;
                    float h=ground(pt.xz),gap=pt.y-h;
                    if(gap<ringBest){ringBest=gap;next=a;ringPoint=pt;}
                    if(gap<best){best=gap;footprint=vec3(pt.x,h,pt.z);}
                }
                angle=next;
                angularStep*=0.5;
            }
        }
        int ring=side+1;
        gaps[ring]=ringBest;
        centers[ring]=ringPoint-axis*lateral;
    }
    if(best<1e19){
        // The shoulder can establish contact without moving the stamped line
        // sideways each time the lowest tread ring changes.
        vec3 center=vec3(0.0);
        float total=0.0;
        float blend=max(wheel.w*0.10,0.01);
        for(int ring=0;ring<3;ring++){
            float weight=(1.0-smoothstep(0.0,blend,gaps[ring]-best))*(ring==1?2.0:1.0);
            center+=centers[ring]*weight;
            total+=weight;
        }
        footprint.xz=clamp(center.xz/max(total,0.001),vec2(0.0),u_extent);
        footprint.y=ground(footprint.xz);
    }
    vec2 slope=slope_at(footprint.xz);
    return vec4(footprint,best*inversesqrt(1.0+dot(slope,slope)));
}
uniform float u_half_width0,u_half_width1;
void main(){
 bool rear=gl_FragCoord.y>1.0;
 vec4 wheel=rear?u_wheel1:u_wheel0;vec3 axis=normalize(rear?u_axis1:u_axis0);
 vec3 bottom=rear?u_bottom1:u_bottom0;
 if(gl_FragCoord.x>2.0){
    f_color=u_packed_lines!=0?packed_footprint(wheel,axis,rear?u_half_width1:u_half_width0):vec4(0,0,0,1e20);
    return;
 }
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
