/* Full-scene camera motion blur, exposure, tone mapping and color grading. */
uniform sampler2D u_src, u_depth, u_exposure;
uniform vec2 u_texel;
uniform float u_fx,u_fy,u_proj_a,u_proj_b;
uniform vec2 u_projection_offset;
uniform mat4 u_reproject;
uniform float u_motion;		/* blur per frame of movement, from the motion_blur setting */
uniform float u_dof, u_saturation, u_contrast, u_split_tone;	/* the settings, 1 at 100 */
uniform vec3 u_sun, u_up;	/* in view space */
uniform float u_sun_moved;	/* 1 when the player moved the sun, which brings its colours with it */

/* Auto exposure aims for this average brightness, within limits so it never pumps hard. */
const float EXPOSURE_KEY = 0.42;
const float EXPOSURE_MIN = 0.75, EXPOSURE_MAX = 1.5;


const vec3 GRADE_SHADOWS = vec3(0.9, 1.0, 1.15), GRADE_HIGHLIGHTS = vec3(1.15, 1.0, 0.85);

/* A low sun lights warm and leaves the shade to a blue sky. */
const vec3 LOW_SUN_LIGHT = vec3(1.2, 0.94, 0.7), LOW_SUN_SHADE = vec3(0.82, 0.9, 1.12);
const float LOW_SUN_START = 0.6, LOW_SUN_FULL = 0.08;	/* sine of the sun's height */

/* Under heavy cloud colours go cool and dull. */
const vec3 GLOOM_TINT = vec3(0.93, 0.97, 1.05);
const float GLOOM_DESATURATE = 0.3;

/* Camera reprojection and a short, depth-weighted shutter gather. */
uniform int u_motion_samples;
uniform float u_motion_length,u_motion_radius;
uniform vec3 u_motion_center;

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
    float outside=1.0;
    if (!sky && u_motion_radius>0.0) {
        float fromRider=length(ray*distance-u_motion_center);
        outside=smoothstep(u_motion_radius*0.72,u_motion_radius,fromRider);
        if(outside<=0.0)return center;
    }
    vec4 previous=u_reproject*vec4(ray*distance,sky?0.0:1.0);
    if (!(previous.w>0.0001)) return center;
    // Keep the 4% baseline and let length extend the streak before it reaches the cap.
    float lengthGain=sqrt(max(u_motion_length,0.005)/0.04);
    vec2 span=(ndc-previous.xy/previous.w)*(0.25*u_motion*lengthGain*outside);
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
        float delta=sky?0.0:abs(view_distance(tapDepth)-distance)/max(distance,0.001);
        float coverage=1.0-smoothstep(0.035,0.16,delta);
        if(coverage<=0.0)continue;
        vec3 color=texture(u_src,at).rgb;
        float tapLight=dot(color,luma);
        float contrast=abs(tapLight-centerLight)/max(max(tapLight,centerLight),0.025);
        float stability=1.0-0.65*smoothstep(0.35,0.84,contrast);
        float weight=(1.0-0.65*t*t)*coverage*stability;
        sum+=color*weight;
        total+=weight;
    }
    return mix(center,sum/total,smoothstep(0.2,0.8,pixels));
}

/* How far into golden hour the sun is, only when the player chose its height. */
float low_sun()
{
	float height = dot(normalize(u_sun), normalize(u_up));

	return (1.0 - smoothstep(LOW_SUN_FULL, LOW_SUN_START, height)) * u_sun_moved * (1.0 - u_night);
}

uniform int u_205_look,u_205_preset_color;
vec3 grade(vec3 c)
{
	vec3 g = clamp(c, 0.0, 1.0);
	float l = dot(g, vec3(0.2126, 0.7152, 0.0722));

	g = mix(vec3(l), g, u_saturation * (1.0 - GLOOM_DESATURATE * weather_gloom()));
	g *= mix(vec3(1.0), GLOOM_TINT, weather_gloom());
	g = clamp(g, 0.0, 1.0);
	g = mix(g, g * g * (3.0 - 2.0 * g), u_contrast);
	g *= mix(vec3(1.0), mix(GRADE_SHADOWS, GRADE_HIGHLIGHTS, l), u_split_tone);
	g*=mix(vec3(1.0),mix(LOW_SUN_SHADE,LOW_SUN_LIGHT,l),low_sun());
    if(u_205_preset_color!=0&&u_205_look>0){
        vec3 shadow=vec3(1),highlight=vec3(1);float sat=1.0,brightness=1.0;
        if(u_205_look==1){shadow=vec3(0.91,0.98,1.07);highlight=vec3(1.045,1.01,0.95);sat=0.98;}
        if(u_205_look==2){highlight=vec3(1.01,1.01,1.0);sat=1.02;}
        if(u_205_look==3){shadow=vec3(0.90,0.96,1.05);highlight=vec3(1.12,1.015,0.86);sat=1.04;}
        if(u_205_look==4){shadow=vec3(0.87,0.92,1.07);highlight=vec3(1.12,0.96,0.86);sat=1.02;}
        if(u_205_look==5){shadow=vec3(0.97,1.0,1.025);sat=0.93;}
        if(u_205_look==6){shadow=vec3(0.84,0.92,1.06);highlight=vec3(0.87,0.95,1.07);sat=0.82;brightness=0.95;}
        if(u_205_look==7){shadow=vec3(0.85,0.94,1.08);highlight=vec3(0.94,1.0,1.08);sat=0.88;brightness=1.04;}
        float lum=dot(g,vec3(0.2126,0.7152,0.0722));
        g=mix(vec3(lum),g,sat)*mix(shadow,highlight,smoothstep(0.1,0.85,lum))*brightness;
    }
    return clamp(g,0.0,1.0);
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
