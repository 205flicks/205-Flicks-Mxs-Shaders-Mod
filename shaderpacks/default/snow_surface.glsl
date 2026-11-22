/* Shared visual snow surface for the terrain vertex and fragment stages. */
vec3 snow_ground_normal(vec2 cell)
{
    float left=textureLod(u_heights,(cell+vec2(0.0,0.5))*u_heights_dim_inv,0.0).r;
    float right=textureLod(u_heights,(cell+vec2(1.0,0.5))*u_heights_dim_inv,0.0).r;
    float back=textureLod(u_heights,(cell+vec2(0.5,0.0))*u_heights_dim_inv,0.0).r;
    float ahead=textureLod(u_heights,(cell+vec2(0.5,1.0))*u_heights_dim_inv,0.0).r;
    return normalize(vec3(left-right,max(u_spacing,0.001),back-ahead));
}

float snow_track_clear(vec2 uv)
{
    if(u_205_track_packed_on<0.5)return 0.0;
    vec2 wheels=textureLod(u_205_track_packed,uv,0.0).rg;
    return smoothstep(0.08,0.56,max(wheels.r,wheels.g));
}

float snow_surface_cover(vec2 xz,float facing)
{
    if(u_weather!=4)return 0.0;
    float level=0.85-0.8*u_weather_amount;
    float noise=textureLod(u_weather_noise,xz/(40.0*8.0),0.0).r;
    return smoothstep(0.3,0.7,facing)*smoothstep(level-0.1,level+0.1,noise);
}

float snow_surface_displacement(vec2 cell,float facing)
{
    if(u_weather!=4 || u_snow_depth<=0.0)return 0.0;
    return u_snow_depth*snow_surface_cover(cell*u_spacing,facing)
        *(1.0-snow_track_clear(cell*u_heights_dim_inv));
}
