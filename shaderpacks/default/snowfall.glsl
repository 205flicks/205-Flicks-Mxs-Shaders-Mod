/* Small flakes with a periodic grid and a world-aligned overhead layer. */
float snowfall_plane(vec3 camera,vec3 dir,float sceneDistance,float pixelAngle,int axis,int layer)
{
    const float spacing=2.8;
    const float cellSize=0.62;
    float component=dir[axis];
    if(abs(component)<0.025)return 0.0;
    float fall=u_time*2.5;
    float offset=axis==1?fall:0.0;
    float base=floor((camera[axis]+offset)/spacing);
    float index=base+(component>0.0?float(layer+1):-float(layer));
    float distance=(index*spacing-offset-camera[axis])/component;
    if(distance<0.6 || distance>min(sceneDistance,34.0))return 0.0;

    vec3 hit=camera+dir*distance;
    vec2 position=axis==0?hit.zy:axis==1?hit.xz:hit.xy;
    if(axis!=1)position.y+=fall;
    position.x+=sin(u_time*0.31+index*1.7)*0.04;
    vec2 phase=fract(index*vec2(0.61803399,0.41421356)+
                     float(axis)*vec2(0.371,0.719)+vec2(0.17,0.43));
    vec2 p=position/cellSize+phase;
    vec2 cell=floor(p),f=fract(p);
    vec2 seed=cell+vec2(index*17.3,float(axis)*83.7);
    float random=weather_hash(seed);
    if(random>0.50*clamp(u_weather_amount,0.0,1.0))return 0.0;
    vec4 variation=fract(random*vec4(991.73,613.17,331.97,127.93));
    vec2 center=0.25+0.5*variation.xy;
    float radius=mix(0.011,0.019,variation.z);
    float separation=length((f-center)*cellSize);
    float aa=max(0.001,distance*pixelAngle/max(abs(component),0.25)*0.55);
    float coverage=1.0-smoothstep(max(0.0,radius-aa),radius+aa,separation);
    coverage*=radius*radius/(radius*radius+aa*aa*0.35);
    float fade=smoothstep(0.6,2.0,distance)*(1.0-smoothstep(18.0,34.0,distance));
    fade*=1.0-smoothstep(spacing*2.0,spacing*3.0,distance*abs(component));
    return coverage*fade*mix(0.65,1.0,variation.w);
}

float snowfall_ring(vec3 dir,float sceneDistance,float pixelAngle,int layer)
{
    const float radii[3]=float[3](3.2,8.0,17.0);
    const float columns[3]=float[3](32.0,80.0,172.0);
    float horizontal=max(length(dir.xz),0.08);
    float radius=radii[layer],count=columns[layer],distance=radius/horizontal;
    if(distance>min(sceneDistance,34.0))return 0.0;

    float longitude=atan(dir.z,dir.x)/(2.0*PI)+0.5;
    float cellWidth=2.0*PI*radius/count;
    float drift=sin(u_time*0.31+float(layer)*1.7)*0.04/cellWidth;
    // Use the rain-style camera-relative path so jumps cannot reverse fall.
    float height=dir.y/horizontal*radius+u_time*2.5;
    vec2 p=vec2(longitude*count+0.17+float(layer)*0.371+drift,
                height/0.62+float(layer)*13.37);
    vec2 cell=floor(p),f=fract(p);
    // Both sides of the longitude boundary use the identical cell seed.
    cell.x=mod(cell.x,count);
    float random=weather_hash(cell+float(layer)*vec2(53.7,97.3));
    if(random>0.50*clamp(u_weather_amount,0.0,1.0))return 0.0;
    vec4 variation=fract(random*vec4(991.73,613.17,331.97,127.93));
    vec2 center=0.25+0.5*variation.xy;
    float flakeRadius=mix(0.009,0.017,variation.z);
    float separation=length((f-center)*vec2(cellWidth,0.62));
    float aa=max(0.001,distance*pixelAngle*0.55/horizontal);
    float coverage=1.0-smoothstep(max(0.0,flakeRadius-aa),flakeRadius+aa,separation);
    coverage*=flakeRadius*flakeRadius/(flakeRadius*flakeRadius+aa*aa*0.35);
    float fade=1.0-smoothstep(20.0,34.0,distance);
    return coverage*fade*mix(0.65,1.0,variation.w);
}

vec3 snowfall(vec3 color,vec3 dir,float sceneDistance)
{
    if(u_weather_amount<=0.0)return color;
    float pixelAngle=max(length(dFdx(dir)),length(dFdy(dir)));
    float amount=0.0;
    for(int layer=0;layer<3;layer++)
        amount+=snowfall_ring(dir,sceneDistance,pixelAngle,layer);
    float horizontal=length(dir.xz);
    float pole=1.0-smoothstep(0.12,0.32,horizontal);
    if(pole>0.0){
        float overhead=snowfall_plane(vec3(0.0),dir,sceneDistance,pixelAngle,1,0);
        amount=mix(amount,overhead,pole);
    }
    float night=night_sky_amount(u_night);
    vec3 flake=mix(vec3(0.78,0.81,0.85),vec3(0.30,0.34,0.41),night);
    return mix(color,flake,min(amount*0.48,0.42));
}
