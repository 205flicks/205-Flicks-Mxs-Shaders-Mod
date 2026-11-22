#version 150

in vec2 interp_texcoord;
in vec2 interp_hcoord;
in vec3 interp_viewer;
in mat3 interp_modelview;
in float interp_snow_height;
uniform mat4 u_projection;

uniform sampler2D u_tex, u_nmap, u_smap, u_heights;
uniform float u_heights_dim_inv;
uniform float u_spacing;
uniform vec3 u_fog_color;
uniform float u_fog_density;
uniform vec3 u_light_position;
uniform vec4 u_ambient;
uniform vec3 u_diffuse;
uniform vec3 u_specular_color;
uniform float u_texscale;	/* set by the game for the vertex shader: texture per world unit */
uniform float u_baked_shadow;
uniform float u_205_terrain_occlusion,u_205_track_packed_on;
uniform sampler2D u_205_track_packed;

out vec4 f_fragcolor;

#include "common.glsl"
#include "snow_surface.glsl"
// Original 205 Flicks material functions; GGX / Smith / Schlick approximation.
// Environment is procedural sky radiance, not a reflection of hidden scenery.
vec3 flicks_fresnel(float vh,vec3 f0){return f0+(1.0-f0)*pow(1.0-clamp(vh,0.0,1.0),5.0);}
vec3 flicks_brdf(vec3 n,vec3 v,vec3 l,vec3 f0,float roughness)
{
    vec3 hv=v+l;
    vec3 h=hv*inversesqrt(max(dot(hv,hv),1e-8));
    float nv=max(dot(n,v),0.001),nl=max(dot(n,l),0.0),nh=max(dot(n,h),0.0),vh=max(dot(v,h),0.0);
    float a=max(roughness*roughness,0.025),a2=a*a;
    float denominator=nh*nh*(a2-1.0)+1.0;
    float d=a2/(PI*denominator*denominator+1e-6);
    float gv=2.0*nv/(nv+sqrt(a2+(1.0-a2)*nv*nv));
    float gl=2.0*nl/(nl+sqrt(a2+(1.0-a2)*nl*nl));
    return min(vec3(12.0),d*gv*gl*flicks_fresnel(vh,f0)/max(4.0*nv*nl,0.001));
}




float ground_height(float dx, float dz)
{
	return texture(u_heights, (interp_hcoord + 0.5 + vec2(dx, dz)) * u_heights_dim_inv).r;
}

/* Central differences half a height cell either side, with up as the y axis. */
vec3 ground_normal()
{
	return normalize(vec3(ground_height(-0.5, 0.0) - ground_height(0.5, 0.0), u_spacing,
			      ground_height(0.0, -0.5) - ground_height(0.0, 0.5)));
}

/* The normal map's axes follow world x and z, tilted to lie on the ground. */
vec3 tilt_to_ground(vec3 n)
{
	vec3 up = ground_normal();
	vec3 forward = normalize(vec3(0.0, -up.z, up.y));
	vec3 side = cross(up, forward);

	return side * n.x + up * n.y + forward * n.z;
}

/* Measure the walls of a rut in the terrain height texture. All offsets
   are in terrain cells, so the same part of the track gives the same result
   as the camera moves. */
float rut_height(vec2 offset)
{
    return textureLod(u_heights,(interp_hcoord+0.5+offset)*u_heights_dim_inv,0.0).r;
}

float rut_occlusion()
{
    float center=rut_height(vec2(0.0));
    vec4 rise=vec4(rut_height(vec2(-1.0,0.0)),rut_height(vec2(1.0,0.0)),
                   rut_height(vec2(0.0,-1.0)),rut_height(vec2(0.0,1.0)))-center;
    vec2 paired=min(rise.xz,rise.yw)/max(u_spacing,0.001);
    return smoothstep(0.045,0.47,max(paired.x,paired.y));
}

const vec2 TIRE_GROOVE_DEPTH=vec2(0.116,0.198);

float tire_depth(vec2 uv)
{
    return dot(textureLod(u_205_track_packed,uv,0.0).rg,TIRE_GROOVE_DEPTH);
}

// Intersect a recessed tire surface, keeping the original terrain at the lip.
float tire_relief(vec2 uv,vec2 extent,vec3 viewRay,vec3 groundUp,float firstDepth)
{
    float incidence=-dot(viewRay,groundUp);
    if(incidence<=0.025)return 0.0;
    float maxTravel=min(0.90,dot(TIRE_GROOVE_DEPTH,vec2(1.0))/incidence);
    vec2 stepUV=viewRay.xz/extent;
    float prevTravel=0.0,prevGap=firstDepth;
    for(int i=1;i<=6;i++){
        float travel=float(i)*(maxTravel/6.0);
        float gap=tire_depth(uv+stepUV*travel)-travel*incidence;
        if(gap<=0.0){
            return mix(prevTravel,travel,prevGap/max(prevGap-gap,0.00001));
        }
        prevTravel=travel;
        prevGap=gap;
    }
    // Keep bounded relief when the ray ends inside the groove.
    return maxTravel;
}

const float WET_DARKEN = 0.6;		/* damp soil, all over */
const float PUDDLE_DARKEN = 0.45;	/* the bed under the water */
const float PUDDLE_SHINE = 600.0;

float snow_trench_surface(vec2 uv,float facing)
{
    vec2 cell=uv*vec2(textureSize(u_heights,0));
    float ground=textureLod(u_heights,uv+0.5*u_heights_dim_inv,0.0).r;
    vec2 wheels=textureLod(u_205_track_packed,uv,0.0).rg;
    float clear=smoothstep(0.08,0.56,max(wheels.r,wheels.g));
    float layer=u_snow_depth*snow_surface_cover(cell*u_spacing,facing)*(1.0-clear);
    return ground+layer-dot(wheels,TIRE_GROOVE_DEPTH);
}

float snow_trench_relief(vec3 origin,vec3 ray,vec2 uv,vec2 extent,float facing)
{
    float previous=origin.y-snow_trench_surface(uv,facing);
    if(previous<=0.001)return 0.0;
    float maximum=min(8.0,(u_snow_depth+0.32)/max(-ray.y,0.05));
    vec2 stepUV=ray.xz/extent;
    float priorTravel=0.0;
    for(int i=1;i<=10;i++){
        float travel=maximum*float(i)/10.0;
        float gap=origin.y+ray.y*travel-snow_trench_surface(uv+stepUV*travel,facing);
        if(gap<=0.0)return mix(priorTravel,travel,previous/max(previous-gap,0.0001));
        previous=gap;priorTravel=travel;
    }
    return 0.0;
}

void main()
{
#ifdef FLICKS_SNOW_DEPTH_WRITE
    gl_FragDepth=gl_FragCoord.z;
#endif
	vec4 nmap, s;
	vec3 n, up, light, albedo, lit, ambient, world;
	vec2 uv;
	float ndl, len, power, water, snow;

	if (u_shadow_pass != 0) {
		f_fragcolor = vec4(0.0);
		return;
	}

	light = normalize(u_light_position);
	world = to_world(interp_viewer);
	uv = interp_texcoord;
    vec3 shadedPosition=interp_viewer;
    vec2 terrainCells=vec2(textureSize(u_heights,0));
    vec2 groundUV=interp_hcoord/terrainCells;
    vec2 dx=dFdx(interp_texcoord),dy=dFdy(interp_texcoord);
    float grooveDepth=u_205_track_packed_on>0.5 ? tire_depth(groundUV) : 0.0;
    bool deepSnow=u_weather==WEATHER_SNOW && u_snow_depth>0.0;
    if(grooveDepth>0.004){
        vec2 extent=max(terrainCells*u_spacing,vec2(0.1));
        vec3 viewRay=normalize(interp_viewer);
        vec3 worldRay=normalize(transpose(interp_modelview)*viewRay);
        float travel=deepSnow?snow_trench_relief(world,worldRay,groundUV,extent,ground_normal().y):
                             tire_relief(groundUV,extent,worldRay,ground_normal(),grooveDepth);
        if(travel>0.0){
            shadedPosition+=viewRay*travel;
            if(deepSnow){
                groundUV+=worldRay.xz*travel/extent;
                uv+=worldRay.xz*travel*u_texscale;
                world+=worldRay*travel;
                vec4 clip=u_projection*vec4(shadedPosition,1.0);
#ifdef FLICKS_SNOW_DEPTH_WRITE
                if(abs(clip.w)>0.0001)gl_FragDepth=clamp(clip.z/clip.w*0.5+0.5,0.0,1.0);
#endif
            }
        }
    }
	/* Green holds a terrain shading term, the normal's y is rebuilt from x and z. */
	nmap = textureGrad(u_nmap, uv, dFdx(interp_texcoord), dFdy(interp_texcoord));
	len = mix(1.0,nmap.y,u_baked_shadow);
	n = nmap.rgb * 2.0 - 1.0;
	n.y = sqrt(max(1.0 - n.z * n.z - n.x * n.x, 0.0));
    float normalStrength=flicks_value(u_205_normal,1.0);
    n.xz*=normalStrength;
    n.y=max(0.001,mix(1.0,n.y,clamp(normalStrength,0.0,1.0)));
    n=normalize(n);
    // Procedural micro slopes are attenuated by their pixel footprint.
    vec2 phase=interp_texcoord*max(u_texscale,0.0001)*18.0;
    vec2 footprint=fwidth(phase);
    float micro=flicks_value(u_205_micro,0.0)*exp(-dot(footprint,footprint)*2.0);
    n.xz+=vec2(sin(phase.x+sin(phase.y)),cos(phase.y+sin(phase.x)))*0.06*micro;
    n = normalize(interp_modelview * tilt_to_ground(normalize(n)));
	up = normalize(interp_modelview[1]);

	vec3 surface = textureGrad(u_tex, uv, dx, dy).rgb;
	vec2 texSize = vec2(textureSize(u_tex, 0));
	float texelFootprint = max(length(dx * texSize), length(dy * texSize));
	// Stabilize minified green ground detail while retaining the close texture.
	float grassFilter = smoothstep(0.015, 0.07, surface.g - max(surface.r, surface.b));
	float minified = smoothstep(1.0, 3.0, texelFootprint);
	if (grassFilter * minified > 0.0)
		surface = mix(surface, textureGrad(u_tex, uv, dx * 1.7, dy * 1.7).rgb, grassFilter * minified);
	albedo = to_linear(surface);
    float groove=0.0;
    if(grooveDepth>0.0){
        vec2 channels=texture(u_205_track_packed,groundUV).rg;
        float depth=dot(TIRE_GROOVE_DEPTH,channels);
        vec2 texel=1.0/vec2(textureSize(u_205_track_packed,0));
        vec2 tX=vec2(texel.x*1.20,0.0), tY=vec2(0.0,texel.y*1.20);
        float left=dot(texture(u_205_track_packed,groundUV-tX).rg,TIRE_GROOVE_DEPTH);
        float right=dot(texture(u_205_track_packed,groundUV+tX).rg,TIRE_GROOVE_DEPTH);
        float behind=dot(texture(u_205_track_packed,groundUV-tY).rg,TIRE_GROOVE_DEPTH);
        float ahead=dot(texture(u_205_track_packed,groundUV+tY).rg,TIRE_GROOVE_DEPTH);
        vec2 gridStep=vec2(textureSize(u_heights,0))*u_spacing*texel;
        vec2 profile=vec2(right-left,ahead-behind)/max(2.4*gridStep,vec2(0.03));
        // Sloped groove shoulders catch light while the floor stays compressed.
        n=normalize(n+interp_modelview*vec3(profile.x,0.0,profile.y)*0.76);
        groove=clamp(max(channels.r*0.78,channels.g),0.0,1.0);
        float floorShade=smoothstep(0.015,0.18,depth);
        albedo*=1.0-0.17*groove-0.12*floorShade;
    }

	/* Snow and standing water both lie flat over the detail underneath. */
    snow=snow_cover(world,dot(n,up))*(1.0-snow_track_clear(groundUV));
    if(deepSnow && u_205_track_packed_on>0.5 && grooveDepth>0.0){
        vec2 texel=1.0/vec2(textureSize(u_205_track_packed,0));
        float facing=ground_normal().y;
        float left=snow_surface_displacement((groundUV-vec2(texel.x,0.0))*terrainCells,facing);
        float right=snow_surface_displacement((groundUV+vec2(texel.x,0.0))*terrainCells,facing);
        float back=snow_surface_displacement((groundUV-vec2(0.0,texel.y))*terrainCells,facing);
        float ahead=snow_surface_displacement((groundUV+vec2(0.0,texel.y))*terrainCells,facing);
        vec2 step=terrainCells*u_spacing*texel;
        vec2 slope=vec2(left-right,back-ahead)/max(2.0*step,vec2(0.03));
        n=normalize(n+interp_modelview*vec3(slope.x,0.0,slope.y));
    }
	water = u_wet > 0.0 ? puddle(world, ground_normal().y) * (1.0 - snow) : 0.0;	/* dry ground skips the height reads */
	albedo *= mix(1.0, WET_DARKEN, u_wet * (1.0 - snow)) * mix(1.0, PUDDLE_DARKEN, water);
	albedo = mix(albedo, SNOW_ALBEDO, snow);
	n = normalize(mix(n, up, max(water, snow * 0.7)));

	ndl = max(dot(n, light), 0.0) * sun_shadow(shadedPosition, n, 0.0) * cloud_shadow(shadedPosition, light);

	/* Sky light falls off on surfaces facing away from the sky. */
	ambient = sky_light(u_ambient.rgb) * (0.65 + 0.35 * dot(n, up)) * (u_205_stadium>1.5?0.52:1.0) + stadium_fill(n);

	lit = albedo * (ambient + track_direct_light(u_diffuse) * ndl * len * sun_boost());

	s = textureGrad(u_smap, uv, dFdx(interp_texcoord), dFdy(interp_texcoord));

    // Soil gets a dielectric, rough specular lobe. Green vegetation is restrained.
    vec3 v=normalize(-shadedPosition);
    float grass=clamp((albedo.g-max(albedo.r,albedo.b))*5.0,0.0,1.0);
    float rough=flicks_value(u_205_roughness,0.65);
    rough=mix(rough,0.92,grass);
    rough=mix(rough,max(0.16,rough*0.45),u_wet*(1.0-snow));
    rough=mix(rough,max(0.19,rough*0.65),groove*(1.0-snow));
    float variance=dot(dFdx(n),dFdx(n))+dot(dFdy(n),dFdy(n));
    rough=clamp(sqrt(rough*rough+min(variance*0.35,0.35)),0.15,1.0);
    vec3 f0=vec3(mix(0.035,0.045,u_wet));
    float material=flicks_value(u_205_material,1.0);
    vec3 sunRadiance=track_direct_light(u_diffuse)*sun_boost();
    vec3 spec=flicks_brdf(n,v,light,f0,rough);
    float soilResponse=0.15*(1.0-0.75*grass)*(1.0-snow);
    lit+=spec*sunRadiance*ndl*len*soilResponse*material;


	/* Water mirrors the sky, most at a glancing look, and the sun as a sharp glint. */
	if (water > 0.0) {
		float f = fresnel(up, interp_viewer, 0.02) * water;

		lit = mix(lit, sky_reflection(u_fog_color), f);
		lit += track_direct_light(u_diffuse) * (1.0-smoothstep(0.45,1.0,u_night)) * ndl * specular(up, interp_viewer, light, PUDDLE_SHINE) * f;
	}

	lit+=albedo*flicks_moon_diffuse(n);
    bool heightfieldShade=u_hdr!=0 && u_ambient.a>=0.999 && u_205_terrain_occlusion>=0.0;
    if(heightfieldShade && u_205_terrain_occlusion>0.0)
        lit*=1.0-u_205_terrain_occlusion*rut_occlusion();
    // Alpha identifies opaque terrain for the AO and contact composite.
    f_fragcolor=vec4(finish_color(lit,u_fog_color,u_fog_density),
                    heightfieldShade ? 2.0 : u_ambient.a);
}
