#version 150

/* The scene in linear light, and it leaves that way: post_lens.fsh finishes it. */

in vec2 v_uv;
out vec4 f_color;

uniform sampler2D u_color, u_ao, u_depth, u_shafts;
uniform int u_205_shafts_on;
uniform vec2 u_shadow_projection_offset;
uniform float u_shadow_darkness;
uniform sampler2DShadow u_rider_shadow_map;
uniform int u_rider_shadow_on,u_shadow_debug;
uniform float u_proj_a, u_proj_b, u_fx, u_fy;
uniform float u_camera_height;	/* above the ground around the rider */
uniform float u_fog_amount;	/* the fog setting in mxs-shaders.ini, 1 at 100 */
uniform vec3 u_up, u_sun, u_fog_color;
uniform vec3 u_sky_sun;
uniform int u_sky_look;

#include "common.glsl"

uniform float u_ao_strength,u_contact_strength;
#define AO_STRENGTH (0.85*u_ao_strength)



/* Haze per game unit at ground level, thinning by e every FOG_HEIGHT units. */
const float FOG_DENSITY = 0.0002;
const float FOG_HEIGHT = 14.0;
const float SKY_DISTANCE = 900.0;	/* how much air a ray to the sky goes through */
const float FOG_MAX_BRIGHT = 0.85;	/* gamma encoded, near white would undo to a huge value */
const float FOG_MAX_DESCENT = 2.0;	/* in FOG_HEIGHTs, the air stops thickening below that */

const vec3 SUN_SCATTER = vec3(1.0, 0.82, 0.6);
const float FOG_SUN = 0.6;	/* how much the haze brightens toward the sun */
const float SHAFT_STRENGTH = 0.35;
const float SHAFT_AMBIENT = 0.12;	/* beams away from the sun, nearly invisible */

uniform float u_noise_reduction;
uniform int u_edge_smoothing;

vec3 filtered_neighbor(vec2 uv, vec3 center, float depth)
{
    vec3 color=texture(u_color,uv).rgb;
    float distance=u_proj_b/(texture(u_depth,uv).r*2.0-1.0+u_proj_a);
    float depthWeight=1.0-smoothstep(0.01,0.05,abs(distance-depth)/max(depth,0.001));
    float contrast=max(abs(color.r-center.r),max(abs(color.g-center.g),abs(color.b-center.b)));
    return mix(center,color,depthWeight*(1.0-smoothstep(0.025,0.16,contrast)));
}
vec3 reduce_noise(vec3 center, float depth)
{
    vec2 pixel=1.0/vec2(textureSize(u_color,0));
    vec3 sum=filtered_neighbor(v_uv+vec2(pixel.x,0),center,depth)
            +filtered_neighbor(v_uv-vec2(pixel.x,0),center,depth)
            +filtered_neighbor(v_uv+vec2(0,pixel.y),center,depth)
            +filtered_neighbor(v_uv-vec2(0,pixel.y),center,depth);
    return mix(center,sum*0.25,0.65*u_noise_reduction);
}
vec3 smooth_edges(vec3 center)
{
	const vec3 luma=vec3(0.2126,0.7152,0.0722);
	vec2 pixel=1.0/vec2(textureSize(u_color,0));
	float m=dot(center,luma);
	float nw=dot(texture(u_color,v_uv+pixel*vec2(-1, 1)).rgb,luma);
	float ne=dot(texture(u_color,v_uv+pixel*vec2( 1, 1)).rgb,luma);
	float sw=dot(texture(u_color,v_uv+pixel*vec2(-1,-1)).rgb,luma);
	float se=dot(texture(u_color,v_uv+pixel*vec2( 1,-1)).rgb,luma);
	float low=min(m,min(min(nw,ne),min(sw,se)));
	float high=max(m,max(max(nw,ne),max(sw,se)));
	float contrast=high-low;
	if(contrast<max(0.025,high*0.16))
		return center;
	vec2 axis=vec2(nw+ne-sw-se,sw+nw-se-ne);
	axis=clamp(axis/max(max(abs(axis.x),abs(axis.y)),0.0001),vec2(-1),vec2(1))*pixel;
	vec3 a=texture(u_color,v_uv-axis*0.5).rgb;
	vec3 b=texture(u_color,v_uv+axis*0.5).rgb;
	return mix(center,(a+b)*0.5,0.22);
}

/* Rain greys the haze and thickens it, snow whitens it. Gamma encoded like the game's fog. */
const vec3 RAIN_FOG = vec3(0.55, 0.58, 0.62), SNOW_FOG = vec3(0.82, 0.85, 0.9);
const float RAIN_HAZE = 3.0, SNOW_HAZE = 4.0;	/* times the haze, at full strength */

const float STAR_GRID = 350.0;		/* cells per radian */
const float STAR_DENSITY = 0.004;	/* of the cells that hold a star */
const float STAR_BRIGHT = 2.0;
const vec3 MOON_DIR = normalize(vec3(-0.45, 0.5, -0.74));	/* world space, y up */
const float MOON_RADIUS = 0.016, MOON_BRIGHT = 4.0;

const float LIGHTNING_EVERY = 8.0;	/* seconds, each has one chance of a strike */
const float LIGHTNING_BRIGHT = 1.5;
const float LIGHTNING_TOP = 0.35;	/* how high the bolt reaches, as the sine of its angle */

const float RAIN_SPEED = 55.0, SNOW_SPEED = 3.0;	/* units per second */
const float RAIN_SLANT = 0.12;
const vec3 RAIN_LIGHT = vec3(0.12), SNOW_FLAKE = vec3(0.9);

vec3 weather_fog_color()
{
	if (u_weather == WEATHER_SNOW)
		return mix(u_fog_color, SNOW_FOG, u_weather_amount);
	return mix(u_fog_color, RAIN_FOG, weather_gloom() * 0.8);
}

float weather_haze()
{
	if (u_weather == WEATHER_SNOW)
		return mix(1.0, SNOW_HAZE, u_weather_amount);
	if (u_weather >= WEATHER_RAIN)
		return mix(1.0, RAIN_HAZE, u_weather_amount);
	return 1.0;
}

/* How bright the lightning is right now. slot says which strike it is. */
float lightning(out float slot)
{
	float t;

	slot = floor(u_time / LIGHTNING_EVERY);
	if ((u_weather != WEATHER_RAIN && u_weather != WEATHER_STORM) || u_weather_amount<=0.0 || weather_hash(vec2(slot, 1.7)) > 0.25 + 0.6 * u_weather_amount)
		return 0.0;
	t = u_time - slot * LIGHTNING_EVERY - weather_hash(vec2(slot, 4.3)) * (LIGHTNING_EVERY - 1.0);
	if (t < 0.0 || t > 1.0)
		return 0.0;
	/* A first flash, then a second one a moment later. */
	return exp(-t * 12.0) + step(0.15, t) * exp(-(t - 0.15) * 9.0) * 0.7;
}

/* The bolt, a jagged line down from the clouds at a bearing of its own. */
float lightning_bolt(vec3 dir, float slot)
{
	float bearing = weather_hash(vec2(slot, 8.1)) * 2.0 * PI, off, a;

	if (dir.y < 0.0 || dir.y > LIGHTNING_TOP)
		return 0.0;
	off = (weather_noise(vec2(dir.y * 18.0, slot)) - 0.5) * 0.12 + (weather_noise(vec2(dir.y * 70.0, slot + 3.0)) - 0.5) * 0.03;
	a = mod(atan(dir.z, dir.x) - bearing - off + PI, 2.0 * PI) - PI;
	return smoothstep(0.0045, 0.0015, abs(a)) + smoothstep(0.05, 0.0, abs(a)) * 0.15;
}

#include "sky_backdrop.glsl"
#include "sky_detail.glsl"

vec3 weather_sky(vec3 c,vec3 dir,float flash,float slot)
{
    return detailed_sky(c,dir,flash,slot);
}

#include "snowfall.glsl"

/* Keep the existing rain treatment; snow has its own periodic particle field. */
vec3 precipitation(vec3 c,vec3 dir,float dist,float flash)
{
    if(u_weather==WEATHER_SNOW)return snowfall(c,dir,dist);
    if(u_weather<WEATHER_RAIN || u_weather_amount<=0.0)return c;
    const float layer_dist[3]=float[3](3.0,7.0,16.0);
    const vec2 cell_size=vec2(0.3,2.0);
    float around=atan(dir.z,dir.x),rise=dir.y/max(length(dir.xz),0.05),amount=0.0;
    for(int i=0;i<3 && dist>layer_dist[i];i++){
        vec2 p=vec2(around,rise)*layer_dist[i];
        p.y+=u_time*RAIN_SPEED;
        p.x+=p.y*RAIN_SLANT;
        p.y+=float(i)*37.0;
        vec2 cell=floor(p/cell_size),f=fract(p/cell_size);
        if(weather_hash(cell+float(i)*13.0)>u_weather_amount*0.35)continue;
        float x=0.2+0.6*weather_hash(cell+2.7);
        float drop=smoothstep(0.06,0.0,abs(f.x-x))*smoothstep(0.0,0.15,f.y)*smoothstep(0.55,0.3,f.y);
        amount+=drop/(1.0+float(i)*0.6);
    }
    return c+RAIN_LIGHT*amount*(1.0+flash*4.0);
}

vec3 atmosphere(vec3 c)
{
	float depth = texture(u_depth, v_uv).r;
	vec2 ndc = v_uv * 2.0 - 1.0;
	vec3 ray = vec3(ndc.x / u_fx, ndc.y / u_fy, -1.0);
	float dist = SKY_DISTANCE * length(ray);
	vec3 dir = normalize(ray);
	vec2 shafts = u_205_shafts_on!=0 && u_night<1.0?texture(u_shafts, v_uv).rg:vec2(0.0);
	float climb, thinning, optical, sun, clouds = sun_through_clouds(u_sun);

	if (depth < 1.0)
		dist = u_proj_b / (depth * 2.0 - 1.0 + u_proj_a) * length(ray);

	/* Density falls with height, so this is its exact integral along the ray. */
	climb = max(dot(dir, normalize(u_up)) * dist / FOG_HEIGHT, -FOG_MAX_DESCENT);
	thinning = abs(climb) < 0.001 ? 1.0 : (1.0 - exp(-climb)) / climb;
	optical = FOG_DENSITY * u_fog_amount * weather_haze() * exp(-u_camera_height / FOG_HEIGHT) * dist * thinning;

	sun = pow(max(dot(dir, normalize(u_sun)), 0.0), 8.0) * (1.0 - u_night) * clouds;
    vec3 fog=scene_from_gamma(clamp(weather_fog_color(),0.0,FOG_MAX_BRIGHT));
    float night=night_sky_amount(u_night);
    vec3 haze=mix(vec3(dot(fog,vec3(0.2126,0.7152,0.0722)))+SUN_SCATTER*sun*FOG_SUN,
        night_sky_color(0.0),night);
    c=mix(haze,c,exp(-optical));
	return c + SUN_SCATTER * shafts.r * shafts.g * (SHAFT_AMBIENT + sun) * SHAFT_STRENGTH * (1.0 - u_night) * clouds;
}

/* Replaced skies can leave original sky color in resolved silhouette pixels. */
float sky_edge_protection()
{
    // The original Track Default/Clear sky does not get a replacement or cleanup.
    return replacement_sky_active(u_sky_look)?1.0:0.0;
}

vec3 clean_sky_edge(vec3 color,float depth,out bool skyBoundary)
{
    skyBoundary=false;
    float protection=sky_edge_protection();
    if(protection<0.15 || depth>=1.0)return color;
    ivec2 size=textureSize(u_depth,0);
    ivec2 at=clamp(ivec2(v_uv*vec2(size)),ivec2(0),size-1);
    const ivec2 offsets[8]=ivec2[8](ivec2(1,0),ivec2(-1,0),ivec2(0,1),ivec2(0,-1),
        ivec2(1,1),ivec2(-1,1),ivec2(1,-1),ivec2(-1,-1));
    for(int i=0;i<8;i++){
        ivec2 tap=clamp(at+offsets[i],ivec2(0),size-1);
        if(texelFetch(u_depth,tap,0).r>=1.0)skyBoundary=true;
    }
    if(!skyBoundary)return color;
    vec3 reference=vec3(0.0);
    float darkest=1e9;
    const vec3 luma=vec3(0.2126,0.7152,0.0722);
    for(int i=0;i<8;i++){
        ivec2 tap=clamp(at+offsets[i],ivec2(0),size-1);
        if(texelFetch(u_depth,tap,0).r<1.0){
            vec3 candidate=texelFetch(u_color,tap,0).rgb;
            float light=dot(candidate,luma);
            if(light<darkest){darkest=light;reference=candidate;}
        }
    }
    if(darkest==1e9)return color;
    float excess=dot(color-reference,luma);
    float chroma=max(color.b-reference.b,color.g-reference.g);
    float leak=max(smoothstep(0.012,0.045,excess),smoothstep(0.018,0.065,chroma));
    if(night_sky_amount(u_night)<0.15){
        // Use the night cleanup strength, retaining neutral white snow and gear.
        float peak=max(color.r,max(color.g,color.b)),low=min(color.r,min(color.g,color.b));
        float neutral=1.0-smoothstep(0.08,0.24,(peak-low)/max(peak,0.001));
        leak*=1.0-neutral;
    }
    return mix(color,min(color,reference+vec3(0.004)),protection*leak);
}

void main()
{
	vec4 scene=texture(u_color,v_uv);
    vec3 c=scene.rgb;
	vec2 occlusion = vec2(1.0);
    if(u_ao_strength>0.0||u_contact_strength>0.0)occlusion=pow(texture(u_ao,v_uv).rg,vec2(2.2));
	float depth = texture(u_depth, v_uv).r, slot, flash = lightning(slot);
	vec2 ndc = v_uv * 2.0 - 1.0;
	vec3 ray = vec3(ndc.x / u_fx, ndc.y / u_fy, -1.0);
	vec3 dir = normalize(to_world_dir(ray));
	float dist = depth < 1.0 ? u_proj_b / (depth * 2.0 - 1.0 + u_proj_a) * length(ray) : 1e6;

	bool skyBoundary;
    if (u_noise_reduction > 0.0 && depth < 1.0)
        c = reduce_noise(c,u_proj_b/(depth*2.0-1.0+u_proj_a));
    if (u_edge_smoothing != 0)
        c = smooth_edges(c);
	c=clean_sky_edge(c,depth,skyBoundary);
    if (depth >= 1.0 || scene.a < 1.99) {
        c *= pow(max(occlusion.r,0.001),AO_STRENGTH);
        c *= mix(1.0,occlusion.g,clamp(u_contact_strength,0.0,1.0));
    }
    if(u_shadow_debug!=0 && (u_shadow_on==0 || (u_shadow_debug==2 && u_rider_shadow_on==0))){
        f_color=vec4(0.70,0.01,0.53,1.0);
        return;
    }
    if(depth<1.0 && u_shadow_on!=0){
        vec3 shadowRay=vec3((ndc+u_shadow_projection_offset)/vec2(u_fx,u_fy),-1.0);
        vec3 vpos=shadowRay*(u_proj_b/(depth*2.0-1.0+u_proj_a));
        vec3 n=normalize(cross(dFdx(vpos),dFdy(vpos)));
        if(dot(n,vpos)>0.0)n=-n;
        float lost=2.0*dist*dist/u_proj_b*(1.0/8388608.0);
        float sceneLight=sun_shadow_depth(vpos,n,lost);
        float rider=0.0;
        if(u_shadow_debug==2 && u_rider_shadow_on!=0){
            vec3 rc=shadow_coord(u_shadow_near_matrix,vpos+n*0.04);
            float edge=min(min(rc.x,1.0-rc.x),min(rc.y,1.0-rc.y));
            if(edge>0.0 && rc.z>0.0 && rc.z<1.0){
                float radius=1.6/float(textureSize(u_rider_shadow_map,0).x);
                float bias=0.00009+lost/1600.0;
                float receiver=0.0;
                for(int i=0;i<4;i++){
                    vec2 tap=vec2(i%2,i/2)*2.0-1.0;
                    receiver+=texture(u_rider_shadow_map,vec3(rc.xy+tap*radius,rc.z-bias));
                }
                rider=(1.0-receiver*0.25)*smoothstep(0.0,0.10,edge);
            }
        }
        if(u_shadow_debug!=0){
            float visibility=u_shadow_debug==1?sceneLight:1.0-rider;
            f_color=vec4(vec3(mix(0.025,0.70,visibility)),1.0);
            return;
        }
        c*=mix(1.0-u_shadow_darkness,1.0,sceneLight);
    }
    if (depth >= 1.0)
        c = weather_sky(c, dir, flash, slot);
	c = atmosphere(c);
	c = precipitation(c, dir, dist, flash);
	c *= 1.0 + flash * LIGHTNING_BRIGHT;


	f_color = vec4(c, 1.0);
}
