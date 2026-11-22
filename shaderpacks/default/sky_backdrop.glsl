/* Shared low-cost sky background. Drawn before MSAA resolves scenery edges.
   Detailed clouds, stars and celestial disks remain in the final sky pass. */
bool replacement_sky_active(int look)
{
    return look!=0 || u_205_stadium>0.5 || u_weather!=WEATHER_CLEAR;
}

vec3 sky_sun_world(vec3 viewSun)
{
    vec3 sun=to_world_dir(viewSun);
    if(dot(sun,sun)<0.0001)sun=vec3(0.3,0.8,-0.52);
    sun=normalize(sun);
    return sun.y<0.0?-sun:sun;
}

vec3 day_sky_backdrop(vec3 dir,vec3 sun,int look)
{
    bool rainy=u_weather==WEATHER_RAIN||u_weather==WEATHER_STORM;
    bool snow=u_weather==WEATHER_SNOW;
    float rain=rainy?0.78+0.22*u_weather_amount:snow?0.85:0.0;
    float elevation=clamp(dir.y,0.0,1.0);
    float warm=look==4?1.0:1.0-smoothstep(0.10,0.52,sun.y);
    vec3 horizon=mix(vec3(0.48,0.67,0.88),vec3(0.81,0.43,0.22),warm);
    vec3 zenith=mix(vec3(0.085,0.25,0.53),vec3(0.16,0.23,0.43),warm);
    vec3 day=mix(horizon,zenith,pow(elevation,0.55));
    day=mix(day,mix(vec3(0.12,0.15,0.20),vec3(0.05,0.075,0.12),elevation),rain);
    return sky_without_teal(day);
}
