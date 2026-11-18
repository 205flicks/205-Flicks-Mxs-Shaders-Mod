/* Full-scene camera motion blur, exposure, tone mapping and color grading. */
uniform sampler2D u_src, u_depth, u_exposure, u_color;
uniform vec2 u_texel;
uniform float u_fx,u_fy,u_proj_a,u_proj_b;
uniform mat4 u_reproject;
uniform float u_motion;		/* blur per frame of movement, from the motion_blur setting */
uniform float u_dof, u_saturation, u_contrast, u_split_tone;	/* the settings, 1 at 100 */

/* Auto exposure aims for this average brightness, within limits so it never pumps hard. */
const float EXPOSURE_KEY = 0.42;
const float EXPOSURE_MIN = 0.75, EXPOSURE_MAX = 1.5;


const vec3 GRADE_SHADOWS = vec3(0.9, 1.0, 1.15), GRADE_HIGHLIGHTS = vec3(1.15, 1.0, 0.85);

/* Camera reprojection and a short, depth-weighted shutter gather. */
uniform int u_motion_samples;
uniform float u_motion_length,u_blur_near;
uniform vec2 u_projection_offset;

float view_distance(float depth)
{
    return u_proj_b/(depth*2.0-1.0+u_proj_a);
}

const int SAMPLES = 16;
const float DOF_APERTURE = 24.0;	/* blur in pixels at one unit of 1/distance */
const float DOF_MAX = 7.0;		/* pixels */
const float SHARP = 0.5;		/* pixels, below this a single sample will do */
const float SKY_DISTANCE = 2000.0;
float dof_distance(vec2 uv)
{
    float depth=texture(u_depth,uv).r;
    return depth>=1.0?SKY_DISTANCE:view_distance(depth);
}

float blur_radius(float z, float focus)
{
	return min(abs(1.0 / focus - 1.0 / z) * DOF_APERTURE * u_dof, DOF_MAX);
}

vec3 lens_depth_of_field(vec2 uv, float z, vec3 center)
{
	const float golden = 2.39996323;
	float focus = texture(u_exposure, vec2(0.5)).g;
	float radius = blur_radius(z, focus), weight = 0.0, noise;
	vec3 sum = vec3(0.0);
	int i;

	if (radius < SHARP)
		return center;

	noise = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
	for (i = 0; i < SAMPLES; i++) {
		float t = (float(i) + noise) / float(SAMPLES);
		float angle = float(i) * golden + noise * 6.2831853;
		vec2 disc = vec2(cos(angle), sin(angle)) * sqrt(t);
		vec2 at = uv + disc * radius * u_texel;
		float sample_z = dof_distance(at), w = 1.0;

		/* Something sharp in front only reaches here if it is blurred itself. */
		if (sample_z < z)
			w = clamp(blur_radius(sample_z, focus) / max(radius, 0.001), 0.0, 1.0);
		sum += texture(u_src, at).rgb * w;
		weight += w;
	}
	return weight > 0.0 ? sum / weight : center;
}

vec3 lens(vec2 uv)
{
    vec3 center=texture(u_src,uv).rgb;
    if (u_motion<=0.0) return center;

    float depth=texture(u_depth,uv).r;
    bool sky=depth>=1.0;
    float distance=sky?1.0:view_distance(depth);
    vec2 ndc=uv*2.0-1.0;
    vec3 ray=vec3((ndc+u_projection_offset)/vec2(u_fx,u_fy),-1.0);
    bool ground=!sky && texture(u_color,uv).a>=1.99;
    float start=ground?u_blur_near*0.38:u_blur_near;
    float end=ground?u_blur_near*1.52:u_blur_near*1.85;
    float outside=smoothstep(start,end,distance);
    if(!sky && outside<=0.0)return center;
    vec4 previous=u_reproject*vec4(ray*distance,sky?0.0:1.0);
    if (!(previous.w>0.0001)) return center;
    // Keep the 4% baseline and let length extend the streak before it reaches the cap.
    float lengthGain=sqrt(max(u_motion_length,0.005)/0.04);
    vec2 span=(ndc-previous.xy/previous.w)*(0.25*u_motion*lengthGain*(sky?1.0:outside));
    float pixels=length(span/u_texel);
    if (!(pixels>0.2)) return center;
    float limit=0.5*u_motion_length/u_texel.y;
    span*=min(1.0,limit/pixels);
    int samples=clamp(u_motion_samples,6,12);

    const vec3 luma=vec3(0.2126,0.7152,0.0722);
    float centerLight=dot(center,luma);
    vec3 sum=center;
    float total=1.0;
    for(int i=0;i<samples;i++) {
        float t=2.0*(float(i)+0.5)/float(samples)-1.0;
        vec2 at=clamp(uv+t*span,u_texel*0.5,1.0-u_texel*0.5);
        float tapDepth=texture(u_depth,at).r;
        if((tapDepth>=1.0)!=sky)continue;
        float tapDistance=sky?distance:view_distance(tapDepth);
        float delta=abs(tapDistance-distance)/max(distance,0.001);
        bool groundTap=ground && texture(u_color,at).a>=1.99;
        float tapStart=groundTap?start:u_blur_near;
        float cutoffWeight=sky?1.0:smoothstep(tapStart,groundTap?u_blur_near*0.76:tapStart*1.28,tapDistance);
        float coverage=(1.0-smoothstep(0.035,0.16,delta))*cutoffWeight;
        if(ground && !groundTap && tapDistance<u_blur_near*1.28)coverage=0.0;
        if(coverage<=0.0)continue;
        vec3 color=texture(u_src,at).rgb;
        float tapLight=dot(color,luma);
        float contrast=abs(tapLight-centerLight)/max(max(tapLight,centerLight),0.025);
        float stability=1.0-0.65*smoothstep(0.35,0.84,contrast);
        float weight=(1.0-0.65*t*t)*coverage*stability;
        sum+=color*weight;
        total+=weight;
    }
    return mix(center,sum/total,smoothstep(0.2,0.8,pixels)*(ground?sqrt(outside):1.0));
}

uniform int u_lighting_look;

vec3 lighting_grade(vec3 color)
{
    if(u_lighting_look==0)return color;
    float peak=max(color.r,max(color.g,color.b));
    float low=min(color.r,min(color.g,color.b));
    float chroma=smoothstep(0.045,0.22,peak-low);
    float highlights=1.0-smoothstep(0.64,0.94,low);
    vec3 tint=vec3(1.012,1.005,0.987);
    if(u_lighting_look==4||u_lighting_look==3)tint=vec3(1.075,1.025,0.915);
    else if(u_lighting_look==5||u_lighting_look==1){
        float luma=dot(color,vec3(0.2126,0.7152,0.0722));
        float sunlight=smoothstep(0.22,0.65,luma);
        tint=mix(vec3(0.91,1.015,1.10),vec3(1.065,1.019,0.94),sunlight);
        chroma=smoothstep(0.035,0.16,peak-low);
    }
    else if(u_lighting_look>=6)tint=vec3(0.95,0.994,1.055);
    return color*mix(vec3(1.0),tint,chroma*highlights);
}

vec3 grade(vec3 c)
{
	vec3 g = clamp(c, 0.0, 1.0);
	float l = dot(g, vec3(0.2126, 0.7152, 0.0722));

	g = mix(vec3(l), g, u_saturation);
	g = clamp(g, 0.0, 1.0);
	g = mix(g, g * g * (3.0 - 2.0 * g), u_contrast);
	g *= mix(vec3(1.0), mix(GRADE_SHADOWS, GRADE_HIGHLIGHTS, l), u_split_tone);
    return clamp(lighting_grade(g),0.0,1.0);
}

float exposure_scale()
{
	float k = EXPOSURE_KEY / exp(texture(u_exposure, vec2(0.5)).r);

	/* A night scene is meant to be dark, so exposure never lifts it. */
	return clamp(k, EXPOSURE_MIN, mix(EXPOSURE_MAX, 1.0, u_night));
}

/* The finished, gamma encoded picture at a point on the screen. */
vec3 lens_finish(vec2 uv)
{
	vec3 c;

	vec3 scene=lens(uv);
    if(u_dof>0.0)scene=lens_depth_of_field(uv,dof_distance(uv),scene);
	vec3 hdr=scene*exposure_scale();
	vec3 mapped=tonemap(hdr);
	float peak=max(hdr.r,max(hdr.g,hdr.b));
	float shoulder=smoothstep(0.85,3.5,peak);
	float luminance=dot(hdr,vec3(0.2126,0.7152,0.0722));
	vec3 preserved=hdr/max(peak,1e-5)*tonemap(vec3(peak));
	preserved=mix(preserved,tonemap(vec3(luminance)),0.18*shoulder);
	c=grade(to_gamma(mix(mapped,preserved,0.42*shoulder)));
	return c;
}
