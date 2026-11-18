#version 150

in vec3 interp_normal, interp_tangent, interp_viewer;
in vec2 interp_texcoord;
in vec3 flicks_dirt_position, flicks_dirt_normal;

uniform sampler2D u_tex, u_nmap, u_smap;
uniform vec3 u_fog_color;
uniform float u_fog_density;
uniform vec3 u_light_position;
uniform vec4 u_ambient;
uniform vec3 u_diffuse;
uniform float u_shininess;
uniform vec3 u_specular_color;
uniform vec3 u_view_up;
uniform vec2 u_205_roof_clip;
uniform float u_205_bike_materials;
uniform float u_205_rigid_rider,u_205_tire_coat;
uniform vec3 u_205_tire_soil,u_205_tire_center;
uniform float u_205_tire_radius,u_205_body_dirt;
uniform vec3 u_205_body_soil;
uniform sampler2DShadow u_static_shadow;
uniform int u_static_shadow_on;
uniform int u_nbones;	/* shared with the game's vertex shader, nonzero on skinned models */

out vec4 f_fragcolor;

#include "common.glsl"
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
vec3 flicks_environment(vec3 n,vec3 v,vec3 up,vec3 sky,float roughness)
{
    vec3 r=reflect(-v,n);
    float horizon=clamp(dot(r,up)*0.5+0.5,0.0,1.0);
    vec3 low=sky*vec3(0.35,0.30,0.24),high=sky*vec3(0.76,0.88,1.08);
    return mix(low,high,mix(horizon,0.65,roughness*0.6));
}


/*
 The shadow map is a frame old and a moving bike has already left it, so a
 skinned model can't shadow itself accurately. It ignores anything this close
 along the sun's direction, about a bike's length, but still darkens under trees
 and other riders.
*/
const float SKINNED_SELF_SHADOW_IGNORE = 2.2;

const float SUN_WRAP = 0.15;
const vec3 GROUND_BOUNCE = vec3(0.38, 0.32, 0.26);
const float SKY_SHEEN = 0.25;
const float SHADED_RIDER_AMBIENT = 0.8;
const float SOLID_ALPHA = 0.97;

// Filter the cutout mask before applying its opacity threshold. Color
// uses the same mip blend, weighted by each sample's opacity.
float filtered_leaf_alpha(vec2 uv, float alpha, float footprint, inout vec3 color)
{
    float fade = smoothstep(1.0, 3.0, footprint);
    if (fade <= 0.0)
        return alpha;

    float lod = log2(max(footprint, 1.0)) + 0.25;
    float level = floor(lod);
    vec4 fine = textureLod(u_tex, uv, level);
    vec4 coarse = textureLod(u_tex, uv, level + 1.0);
    float blend = fract(lod);
    float filtered = mix(fine.a, coarse.a, blend);
    if (filtered > 0.0001 && filtered < 0.999) {
        vec3 covered = mix(fine.rgb * fine.a, coarse.rgb * coarse.a, blend);
        color = mix(color, covered / filtered, fade);
    }
    return mix(alpha, filtered, fade);
}

void main()
{
	vec4 tex, s;
	vec3 n, t, up, light, albedo, lit, sky, ambient;
	float ndl, sun, power, alpha, hemi, shade, edge, coverage;
	mat3 m;

	tex = texture(u_tex, interp_texcoord);
	alpha = u_ambient.a * tex.a;
	if (u_shadow_pass != 0) {
        if(u_205_roof_clip.x>0.5 && to_world(interp_viewer).y>u_205_roof_clip.y &&
            abs(dot(normalize(interp_normal),normalize(u_view_up)))>0.38)
            discard;
        // Exclude translucent materials such as water and glass.
        if (u_ambient.a < SOLID_ALPHA)
            discard;
        if (u_nbones != 0) {
            if (alpha < SOLID_ALPHA)
                discard;
        } else {
            // The color pass accepts 75% alpha, but wide-map mip averaging
            // can erase thin leaves even at that threshold. Preserve the
            // texture's cutout coverage without turning its quad opaque.
            vec2 dimensions=vec2(textureSize(u_tex,0));
            float footprint=max(length(dFdx(interp_texcoord)*dimensions),
                                length(dFdy(interp_texcoord)*dimensions));
            if (alpha >= 0.75) {
                f_fragcolor = vec4(0.0);
                return;
            }
            if (footprint <= 1.0)
                discard;
            float silhouetteLod=clamp(log2(footprint)-0.75,0.0,2.5);
            float silhouette=textureLod(u_tex,interp_texcoord,silhouetteLod).a*u_ambient.a;
            float threshold=mix(0.75,0.56,smoothstep(1.0,6.0,footprint));
            if (max(alpha,silhouette) < threshold)
                discard;
        }
		f_fragcolor = vec4(0.0);
		return;
	}

	bool staticOpaque = u_nbones == 0 && u_205_rigid_rider < 0.5 && u_ambient.a >= SOLID_ALPHA;
	if (u_ambient.a >= SOLID_ALPHA) {
		// Retain the existing color filter with hard alpha coverage.
		if(staticOpaque && tex.g > tex.r*1.08 && tex.g > tex.b*1.12){
			vec2 dimensions=vec2(textureSize(u_tex,0));
			float footprint=max(length(dFdx(interp_texcoord)*dimensions),length(dFdy(interp_texcoord)*dimensions));
			filtered_leaf_alpha(interp_texcoord,alpha,footprint,tex.rgb);
		}
		coverage=step(0.75,alpha);
	} else {
		edge = clamp((alpha - 0.75) / max(fwidth(alpha), 0.0001) + 0.5, 0.0, 1.0);
		coverage = min(alpha, edge);
	}
	if (coverage <= 0.0)
		discard;

	// Coarse alpha identifies cutout textures even at the opaque interior
	// of a leaf. Only static models with an opaque material are candidates.
	bool cutout = false;
	if (staticOpaque) {
		ivec2 size = textureSize(u_tex, 0);
		float coarsest = log2(float(max(max(size.x, size.y), 1)));
		cutout = tex.a < SOLID_ALPHA ||
		         textureLod(u_tex, vec2(0.5), coarsest).a < SOLID_ALPHA;
	}

	light = normalize(u_light_position);

	vec3 geometricNormal = normalize(interp_normal);
	n = geometricNormal;
	t = normalize(interp_tangent - n * dot(n, interp_tangent));
	m = mat3(t, cross(n, t), n);
	vec3 mappedNormal = m * (texture(u_nmap, interp_texcoord).rgb * 2.0 - 1.0);
    float normalVariance = clamp(1.0-dot(mappedNormal,mappedNormal),0.0,1.0);
    n = normalize(mappedNormal);

	albedo = to_linear(tex.rgb);
    if(u_205_tire_coat>0.0){
        float radial=length(interp_viewer-u_205_tire_center)/max(u_205_tire_radius,0.001);
        float rubber=smoothstep(0.84,0.99,radial)*(1.0-smoothstep(1.12,1.30,radial))
                    *(1.0-smoothstep(0.30,0.65,max(tex.r,max(tex.g,tex.b))));
        vec2 dirtUV=interp_texcoord*vec2(83.0,109.0);
        float grain=0.72+0.28*sin(dirtUV.x)*sin(dirtUV.y);
        float detail=mix(grain,0.72,smoothstep(0.3,1.4,length(fwidth(dirtUV))));
        albedo=mix(albedo,to_linear(u_205_tire_soil),min(0.72,u_205_tire_coat*1.88*detail)*rubber);
    }

    if(u_205_body_dirt>0.0 && alpha>=SOLID_ALPHA){
        // UVs attach the dirt to the material through animation and camera changes.
        vec2 uv=interp_texcoord;
        float patch=0.5+0.5*sin(uv.x*57.0+3.0*sin(uv.y*29.0))*sin(uv.y*71.0);
        float detail=1.0-smoothstep(0.004,0.025,length(fwidth(uv)));
        float grain=mix(0.5,smoothstep(0.18,0.81,patch),detail);
        // JM coordinates are Y up and Z back. Bind-pose normals keep the mask on the mesh.
        vec3 localNormal=flicks_dirt_normal*inversesqrt(max(dot(flicks_dirt_normal,flicks_dirt_normal),0.0001));
        float front=smoothstep(0.08,0.85,-localNormal.z);
        float underside=smoothstep(0.18,0.86,-localNormal.y);
        float rear=smoothstep(0.0,0.60,localNormal.z);
        float exposure;
        if(u_nbones!=0){
            exposure=(0.13+0.82*front+0.19*underside)*(1.0-0.97*rear);
        }else{
            // Catch splash on the top of the front fender as well as underneath it.
            float forwardPart=smoothstep(0.12,1.05,-flicks_dirt_position.z);
            float frontFender=forwardPart*smoothstep(0.12,0.82,localNormal.y);
            exposure=(0.13+max(0.97*front,1.12*underside)+0.44*frontFender)
                     *(1.0-0.87*rear*(1.0-underside));
        }
        float amount=min(0.79,u_205_body_dirt*(0.12+0.28*grain)*exposure);
        amount*=1.0-smoothstep(0.0,0.15,u_205_tire_coat)*0.85;
        albedo=mix(albedo,to_linear(u_205_body_soil),amount);
    }

	/* Bright from the sky, darker and warmer from the ground, so round shapes read as round. */
	up = dot(u_view_up, u_view_up) > 0.5 ? u_view_up : vec3(0.0, 1.0, 0.0);
	hemi = dot(n, up) * 0.5 + 0.5;
	sky = sky_light(u_ambient.rgb);
	if (cutout) {
		float luma = dot(sky, vec3(0.2126, 0.7152, 0.0722));
		sky = mix(sky, vec3(luma), 0.35);
	}
	ambient = mix(sky * GROUND_BOUNCE, sky, hemi);

	bool movingModel=u_nbones!=0||u_205_rigid_rider>0.5;
	float skin=u_nbones!=0?smoothstep(0.025,0.13,tex.r-tex.b)*smoothstep(0.003,0.045,tex.r-tex.g)*smoothstep(0.025,0.12,tex.g):0.0;
	if(movingModel){
        vec3 coord=shadow_coord(u_shadow_matrix,interp_viewer+geometricNormal*0.10);
        shade=1.0;
        if(u_shadow_on!=0 && u_static_shadow_on!=0 && all(greaterThan(coord,vec3(0))) && all(lessThan(coord,vec3(1)))){
            float radius=3.0/float(textureSize(u_static_shadow,0).x);
            shade=mix(shadow_lookup(u_static_shadow,coord,radius,0.0007,0.0),1.0,u_night);
        }
    }else shade=sun_shadow(interp_viewer,geometricNormal,alpha<SOLID_ALPHA?SKINNED_SELF_SHADOW_IGNORE:0.0);
	if(movingModel)shade=mix(shade,1.0,0.18+0.24*skin);
	shade *= cloud_shadow(interp_viewer, light);
	ndl = max(dot(n, light), 0.0) * shade;

	/* A rider in shade gets no bounce from sunlit ground, keep them in step with it. */
	if (u_nbones != 0)
		ambient *= mix(SHADED_RIDER_AMBIENT, 1.0, shade);
	ambient += sky * (0.13*skin);

	/* Wrapping the sun past the edge softens the hard light-to-dark line. */
	sun = clamp((dot(n, light) + SUN_WRAP) / (1.0 + SUN_WRAP), 0.0, 1.0) * shade;

	ambient=ambient*(u_205_stadium>1.5?0.52:1.0)+stadium_fill(n);
	lit = albedo * (ambient + track_direct_light(u_diffuse) * sun * sun_boost());

	/*
	 The spec map is either a real map with the spec color set to the sun, or
	 white with the spec color set to the material, so multiplying covers both.
	*/
	s = texture(u_smap, interp_texcoord);
	power = s.a * 128.0 + 0.125;
	if (power >= 127.875)
		power = u_shininess;
	bool enhanced=u_205_bike_materials>0.5 && (u_nbones!=0||u_205_rigid_rider>0.5||u_205_tire_coat>0.0);
	if(enhanced && !cutout){
		vec3 spec=clamp(to_linear(s.rgb*u_specular_color),0.0,1.0);
		float gloss=max(spec.r,max(spec.g,spec.b));
		float rough=clamp(sqrt(2.0/max(power+2.0,2.0)+0.3*normalVariance)+length(fwidth(n))*0.25,0.12,0.94);
		rough=mix(max(rough,0.62),rough,smoothstep(0.04,0.38,gloss));
		float darkHardware=u_nbones==0?1.0-smoothstep(0.13,0.34,max(tex.r,max(tex.g,tex.b))):0.0;
        rough=max(rough,0.48*darkHardware);
        rough=mix(rough,max(rough,0.72),skin);
        float metal=smoothstep(0.46,0.9,gloss)*(1.0-rough)*(1.0-0.85*darkHardware)*(1.0-skin);
		vec3 f0=mix(vec3(0.028)+spec*0.045,clamp(albedo,0.04,0.8),metal);
		vec3 v=normalize(-interp_viewer);
		vec3 radiance=track_direct_light(u_diffuse)*ndl*sun_boost();
		vec3 base=lit;
        lit=albedo*(ambient+(1.0-metal)*(1.0-f0)*radiance);
		lit+=radiance*flicks_brdf(n,v,light,f0,rough)*flicks_value(u_205_material,1.0);
		lit+=sky*fresnel(n,interp_viewer,0.025+0.14*gloss)*(0.13+0.34*(1.0-rough))*hemi*(1.0-0.70*darkHardware);
        lit=mix(lit,base,0.78*skin);
	}
	if (!enhanced && ndl > 0.0 && !cutout)
		lit += to_linear(s.rgb * u_specular_color) * ndl * (1.0-smoothstep(0.45,1.0,u_night)) *
		       flicks_brdf(n,normalize(-interp_viewer),light,vec3(0.04),
                   clamp(sqrt(2.0/(power+2.0))+length(fwidth(n))*0.2,0.12,1.0)) *
                   flicks_value(u_205_material,1.0);

	/*
	 A faint sky reflection at grazing angles. Skinned models only: scenery
	 without a spec map gets a white default that would read as snow on trees.
	*/
	if (!enhanced && u_nbones != 0)
		lit += sky * s.rgb * to_linear(u_specular_color) * fresnel(n, interp_viewer, 0.02) * hemi * SKY_SHEEN;

	lit+=albedo*flicks_moon_diffuse(n);
	f_fragcolor = vec4(finish_color(lit, u_fog_color, u_fog_density), coverage);
}
