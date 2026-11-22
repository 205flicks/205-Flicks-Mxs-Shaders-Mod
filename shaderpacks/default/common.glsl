
// 205 Flicks material and lighting controls. A zero active flag preserves upstream fallback.
uniform float u_205_active,u_205_roughness,u_205_normal,u_205_micro,u_205_stadium;
uniform float u_205_reflection,u_205_material,u_205_ambient,u_205_moon,u_205_stars;
float flicks_value(float value,float fallback){return u_205_active>0.5?value:fallback;}
/*
 Shared by the default pack. The game's lighting works directly on gamma
 encoded values; these helpers let us light in linear space and go back.
*/
const float EXPOSURE = 1.15;
const float PI = 3.14159265;

/* Linear space shrinks the game's ambient far more than its sun, so restore the balance. */
const float AMBIENT_BOOST = 3.2;
const float SUN_BOOST = 1.7;
const float SATURATION = 0.88;

uniform int u_weather;
const int WEATHER_CLEAR = 0, WEATHER_CLOUDY = 1, WEATHER_RAIN = 2, WEATHER_STORM = 3, WEATHER_SNOW = 4;

float night_sky_amount(float night)
{
    if(u_weather==WEATHER_RAIN || u_weather==WEATHER_SNOW)return 0.0;
    if(u_weather==WEATHER_STORM)return 1.0;
    return u_205_stadium>1.5?1.0:smoothstep(0.40,1.0,night);
}

/* Strip excess green from cyan sky/fog spill, preserving white and warm light.
   This is only used on atmospheric colors, never on rider or track albedo. */
vec3 sky_without_teal(vec3 color)
{
    float cyan=min(max(color.g-color.r,0.0),max(color.b-color.r,0.0));
    float greenLimit=mix(color.r,color.b,0.55);
    color.g-=min(max(color.g-greenLimit,0.0),cyan);
    return color;
}

vec3 night_sky_color(float elevation)
{
    return mix(vec3(0.008,0.013,0.023),vec3(0.0015,0.003,0.009),
               smoothstep(0.0,0.8,max(elevation,0.0)));
}

uniform float u_night;	/* the time of day setting, 1 at 100: the game's light isn't a sun */

/* At night the game's light is only a fill, the boost would make it read as daylight. */
float sun_boost()
{
	return SUN_BOOST * (1.0-smoothstep(0.45,1.0,u_night));
}

vec3 to_linear(vec3 c)
{
	return pow(max(c, vec3(0.0)), vec3(2.2));
}

// Indoor tracks can supply ambient light with little or no direct light.
vec3 track_direct_light(vec3 diffuse)
{
    vec3 light=to_linear(diffuse);
    if(u_205_stadium>1.5)return vec3(0.30,0.31,0.33);
    if(u_205_stadium>0.5)return max(light,vec3(0.13,0.12,0.10));
    float strength=max(light.r,max(light.g,light.b));
    return light+vec3(0.075)*(1.0-smoothstep(0.01,0.11,strength))*step(0.5,u_205_active);
}

vec3 to_gamma(vec3 c)
{
	return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2));
}

/* Squaring a tinted color exaggerates the tint, which turns full shade purple. */
vec3 sky_light(vec3 ambient)
{
	vec3 c = to_linear(ambient) * AMBIENT_BOOST * flicks_value(u_205_ambient,1.0);

	c=mix(vec3(dot(c,vec3(0.2126,0.7152,0.0722))),c,0.5);
    float night=smoothstep(0.45,1.0,u_night);
    return c*mix(1.0,0.14,night)+vec3(0.017,0.022,0.032)*max(u_205_moon,0.0)*night;
}

/* Narkowicz's fit of the ACES filmic curve. */
vec3 tonemap(vec3 c)
{
	/* The curve boosts saturation per channel, so take some out first. */
	c = mix(vec3(dot(c, vec3(0.2126, 0.7152, 0.0722))), c, SATURATION);
	c *= EXPOSURE * 0.6;
	return clamp((c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14), 0.0, 1.0);
}

/*
 Exactly undoes tonemap() and gamma, so something already finished, like the sky,
 can pass through the HDR buffer and come out as it went in. Very bright values
 are limited, the curve is nearly flat up there and they would become huge.
*/
vec3 scene_from_gamma(vec3 color)
{
	vec3 y = clamp(to_linear(color), vec3(0.0), vec3(0.97));
	vec3 a = 2.43 * y - 2.51, b = 0.59 * y - 0.03, c = 0.14 * y;
	vec3 x = (-b - sqrt(b * b - 4.0 * a * c)) / (2.0 * a) / (EXPOSURE * 0.6);
	float l = dot(x, vec3(0.2126, 0.7152, 0.0722));

	return max(vec3(l) + (x - vec3(l)) / SATURATION, vec3(0.0));
}

/* Normalized Blinn-Phong, so tight highlights get brighter instead of just smaller. */
float specular(vec3 n, vec3 viewer, vec3 light, float power)
{
	vec3 h = normalize(light - normalize(viewer));

	return (power + 8.0) / (8.0 * PI) * pow(max(dot(n, h), 0.0), power);
}

float fresnel(vec3 n, vec3 viewer, float f0)
{
	float c = 1.0 - max(dot(n, -normalize(viewer)), 0.0);

	return f0 + (1.0 - f0) * c * c * c * c * c;
}

/*
 Sun shadows from the map the mod renders. Takes the surface position in view
 space and returns 0 in full shadow, 1 in full sun.
*/
uniform sampler2DShadow u_shadow_map, u_shadow_near_map;
uniform mat4 u_shadow_matrix, u_shadow_near_matrix;
uniform int u_shadow_on;
uniform int u_shadow_pass;	/* set while the mod renders the map: only depth matters */

float shadow_lookup(sampler2DShadow map, vec3 c, float radius, float bias, float center_weight)
{
	/* Fixed offsets keep shadow coverage stable as the camera moves. */
	const vec2 disk[8] = vec2[8](
		vec2(-0.326, -0.406), vec2(-0.840, -0.074), vec2(-0.696, 0.457), vec2(-0.203, 0.621),
		vec2(0.962, -0.195), vec2(0.473, -0.480), vec2(0.519, 0.767), vec2(0.185, -0.893));
	float sum = 0.0;
	int first = center_weight > 0.0 ? 1 : 0;
	int i;

	for (i = first; i < 8; i++) {
		vec2 d = disk[i];

		sum += texture(map, vec3(c.xy + d * radius, c.z - bias));
	}
	float average = sum / float(8 - first);
	if (first == 0)
		return average;
	// Keep one center sample so a narrow caster is not averaged away.
	return mix(average, texture(map, vec3(c.xy, c.z - bias)), center_weight);
}

float shadow_lookup(sampler2DShadow map, vec3 c, float radius, float bias)
{
	/* Rotated per pixel so banding turns into fine noise. */
	const vec2 disk[8] = vec2[8](
		vec2(-0.326, -0.406), vec2(-0.840, -0.074), vec2(-0.696, 0.457), vec2(-0.203, 0.621),
		vec2(0.962, -0.195), vec2(0.473, -0.480), vec2(0.519, 0.767), vec2(0.185, -0.893));
	float angle, sum = 0.0;
	vec2 r;
	int i;

	angle = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453) * 2.0 * PI;
	r = vec2(cos(angle), sin(angle));
	for (i = 0; i < 8; i++) {
		vec2 d = vec2(disk[i].x * r.x - disk[i].y * r.y, disk[i].x * r.y + disk[i].y * r.x);

		sum += texture(map, vec3(c.xy + d * radius, c.z - bias));
	}
	return sum / 8.0;
}

vec3 shadow_coord(mat4 matrix, vec3 pos)
{
	return (matrix * vec4(pos, 1.0)).xyz * 0.5 + 0.5;
}/*
 The depth a sample is compared at has to clear how far its filter reaches across a surface
 tilted from the map, and how far the surface's own position may be off. Both put samples
 deeper than the surface they belong to, which reads as shadow.
*/
float shadow_depth_bias(float spread, vec3 map_z, vec3 n, float depth_per_meter)
{
	float tilt = max(abs(dot(n, map_z)), 0.25);

	return spread * sqrt(1.0 - tilt * tilt) / tilt * depth_per_meter;
}

/*
 pos_error is how far the surface's position is off, in game units, when it was rebuilt
 from a depth buffer rather than interpolated: 0 where the shader has the real thing.
*/
float sun_shadow_at(vec3 pos, vec3 n, float ignore_meters, float pos_error)
{
	float bias = 0.00002 + ignore_meters / 1600.0;
	float edge, spread, far_bias, near_radius, near_spread, inset, near_shadow = 1.0, far_shadow = 1.0;
	vec3 near_c, far_c, map_x, map_z, near_x;

	if (u_shadow_on == 0)
		return 1.0;

	/* Pushing along the normal keeps surfaces from shadowing themselves. */
	near_c = shadow_coord(u_shadow_near_matrix, pos + n * 0.025);
	far_c = shadow_coord(u_shadow_matrix, pos + n * 0.06);

	/* The matrices' rows hold each map's scale and the sun's direction. */
	map_x = vec3(u_shadow_matrix[0][0], u_shadow_matrix[1][0], u_shadow_matrix[2][0]);
	vec3 far_z=vec3(u_shadow_matrix[0][2],u_shadow_matrix[1][2],u_shadow_matrix[2][2]);
    float far_depth_scale=0.5*length(far_z);
    map_z=normalize(far_z);
	near_x = vec3(u_shadow_near_matrix[0][0], u_shadow_near_matrix[1][0], u_shadow_near_matrix[2][0]);

	/*
	 How far the wide map's filter reaches across the ground, and never less than this. What
	 the map is compared against is off by more than its texels say: the surface comes from
	 the depth buffer, and terrain can be filled for the map at a coarser mesh than the game
	 drew. Left to the texels alone, Ultra's bias fell under that and the track went to shade.
	*/
	spread = max(2.5 / float(textureSize(u_shadow_map, 0).x) * 2.0 / length(map_x), 0.75);
	far_bias=0.00002+ignore_meters*far_depth_scale+shadow_depth_bias(spread+pos_error,map_z,n,far_depth_scale);

	/*
	 Sharp map close by, fading to the wide one in the last few game units before its border.
	 The band is a fixed width rather than a share of the map, or a longer reach would spend
	 most of itself fading and look no sharper than the map it hands over to. Its filter
	 widens across the band to the wide map's spread in world units, and its bias grows to the
	 wide map's at the same rate: two maps meeting at different softnesses, or at shadows
	 pushed different distances from their casters, show the change as a square edge across
	 the ground, worst when riding at speed.
	*/
	inset = min(min(near_c.x, 1.0 - near_c.x), min(near_c.y, 1.0 - near_c.y)) * 2.0 / length(near_x);
	edge = 1.0 - smoothstep(2.0, 34.0, inset);
	if (edge < 1.0) {
		near_radius = mix(4.0 / float(textureSize(u_shadow_near_map, 0).x),
				  2.5 / float(textureSize(u_shadow_map, 0).x) * length(near_x) / length(map_x),
				  edge * edge);
		/*
		 Its own texels are what it is compared against as well, and a longer reach makes them
		 larger: without the tilt term the rider's surface counted as its own caster, and the
		 jersey wore the map's grid as flat squares.
		*/
		near_spread = near_radius * 2.0 / length(near_x);
		near_shadow = shadow_lookup(u_shadow_near_map, near_c, near_radius,
					    mix(bias,0.00002+(far_bias-0.00002)/(1600.0*far_depth_scale),edge*edge) +
                        shadow_depth_bias(near_spread+pos_error,map_z,n,1.0/1600.0));
	}
    // The distant map is anchored to the whole track. Its coverage has no fade.
    if(edge>0.0 && all(greaterThanEqual(far_c,vec3(0.0))) && all(lessThanEqual(far_c,vec3(1.0))))
        far_shadow=shadow_lookup(u_shadow_map,far_c,2.5/float(textureSize(u_shadow_map,0).x),far_bias);

	return mix(near_shadow, far_shadow, edge);
}

float sun_shadow(vec3 pos, vec3 n, float ignore_meters)
{
	return sun_shadow_at(pos, n, ignore_meters, 0.0);
}

/* sun_shadow for a surface rebuilt from a depth buffer, which is pos_error units out. */
float sun_shadow_depth(vec3 pos, vec3 n, float pos_error)
{
	return sun_shadow_at(pos, n, 0.0, pos_error);
}

/* One lookup is enough for the soft shapes of dust. */

float sun_shadow_fast(vec3 pos)
{
	vec3 c;

	if (u_shadow_on == 0)
		return 1.0;
	c = shadow_coord(u_shadow_matrix, pos);
	if (c.x <= 0.0 || c.x >= 1.0 || c.y <= 0.0 || c.y >= 1.0)
		return 1.0;
	return mix(texture(u_shadow_map, vec3(c.xy, c.z - 0.0001)), 1.0, u_night);
}

/*
 Fog is applied last on the gamma encoded result, as in the game's shaders, so
 distant terrain still blends into the unchanged sky.
*/
vec3 apply_fog(vec3 c, vec3 fog_color, float density);

/* In a race the frame is finished in post, anywhere else the shader does it itself. */
uniform int u_hdr;

vec3 finish_color(vec3 lit, vec3 fog_color, float density)
{
	if (u_hdr != 0)
		return apply_fog(lit, scene_from_gamma(fog_color), density);
	return apply_fog(to_gamma(tonemap(lit)), fog_color, density);
}

vec3 apply_fog(vec3 c, vec3 fog_color, float density)
{
	float z = gl_FragCoord.z / gl_FragCoord.w;

    float night=night_sky_amount(u_night);
    vec3 fixedFog=night_sky_color(0.0);
    if(u_hdr==0)fixedFog=to_gamma(tonemap(fixedFog));
    return mix(mix(sky_without_teal(fog_color),fixedFog,night),c,min(exp(-density*z),1.0));
}

/*
 Weather. u_world_from_view takes view space to the world, where y is up, so
 clouds, puddles and snow stay put on the track as the camera moves.
*/
uniform mat4 u_world_from_view;
uniform float u_time;		/* seconds, for drifting clouds and falling rain */

uniform float u_snow_depth;
uniform float u_weather_amount;	/* the Weather Strength setting, 1 at 100 */
uniform float u_wet;		/* 0 dry to 1 soaked, rain only */
uniform sampler2D u_weather_noise;	/* four octaves of tiling value noise, made by the mod */


const vec2 WIND = vec2(9.0, 4.0);	/* game units per second */
const float CLOUD_HEIGHT = 1200.0;
const float CLOUD_SIZE = 900.0;		/* across a typical cloud */
const float CLOUD_OPACITY = 0.85;	/* of the sun a thick cloud takes away */
const float PUDDLE_SIZE = 18.0;
const float SNOW_PATCH_SIZE = 40.0;
const vec3 SNOW_ALBEDO = vec3(0.8, 0.83, 0.88);
const float NOISE_CELLS = 8.0;	/* the noise texture's lowest octave cells across, match WEATHER_NOISE_CELLS */

float weather_hash(vec2 p)
{
	vec3 q = fract(p.xyx * vec3(0.1031, 0.1030, 0.0973));

	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float weather_noise(vec2 p)
{
	vec2 i = floor(p), f = fract(p), u = f * f * (3.0 - 2.0 * f);

	return mix(mix(weather_hash(i), weather_hash(i + vec2(1.0, 0.0)), u.x),
		   mix(weather_hash(i + vec2(0.0, 1.0)), weather_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

/* Four octaves from 0 to 1, p in lowest octave cells. One read, the mod built the sum once. */
float weather_fbm(vec2 p)
{
	return texture(u_weather_noise, p / NOISE_CELLS).r;
}

vec3 to_world(vec3 view_pos)
{
	return (u_world_from_view * vec4(view_pos, 1.0)).xyz;
}

vec3 to_world_dir(vec3 view_dir)
{
    return mat3(u_world_from_view) * view_dir;
}

vec3 stadium_fill(vec3 view_normal)
{
    if(u_205_stadium<1.5)return vec3(0.0);
    vec3 n=normalize(to_world_dir(view_normal));
    float a=max(dot(n,vec3(-0.76,0.54,0.36)),0.0);
    float b=max(dot(n,vec3(0.12,0.53,0.84)),0.0);
    float c=max(dot(n,vec3(0.66,0.54,0.52)),0.0);
    return vec3(0.105,0.111,0.120)*(0.30+0.80*a+0.70*b+0.45*c);
}

// Single moon direction shared by the sky and the directional shadow pass.
vec3 flicks_moon_diffuse(vec3 normal)
{
    vec3 direction=transpose(mat3(u_world_from_view))*normalize(vec3(-0.45,0.5,-0.74));
    float ndl=max(dot(normalize(normal),direction),0.0);
    float phase=smoothstep(0.53,1.0,u_night);
    return vec3(0.66,0.70,0.78)*max(u_205_moon,0.0)*phase*ndl;
}
/* How much of the sky the clouds cover. */
float cloud_cover()
{
	if (u_weather == WEATHER_CLEAR)
		return 0.0;
	if (u_weather == WEATHER_CLOUDY)
		return 0.25 + 0.45 * u_weather_amount;
	return 0.75 + 0.25 * u_weather_amount;
}

/* How thick the cloud is at a point of its layer, 0 in clear sky. */
float cloud_density(vec2 layer)
{
	float cover = cloud_cover();

	if (cover <= 0.0)
		return 0.0;
	return smoothstep(1.0 - cover, 1.0 - cover + 0.25, weather_fbm((layer + WIND * u_time) / CLOUD_SIZE));
}

/* The sun's world direction, pointing up whichever way the game's vector runs. */
vec3 sun_world(vec3 view_sun)
{
	vec3 sun = normalize(to_world_dir(view_sun));

	return sun.y < 0.0 ? -sun : sun;
}

/* The sunlight a point gets through the clouds between it and the sun. */
float cloud_shadow(vec3 view_pos, vec3 view_sun)
{
	vec3 p, sun;

	if (u_weather == WEATHER_CLEAR)
		return 1.0;
	p = to_world(view_pos);
	sun = sun_world(view_sun);
	return 1.0 - cloud_density(p.xz + sun.xz / max(sun.y, 0.1) * (CLOUD_HEIGHT - p.y)) * CLOUD_OPACITY;
}

/* The same for the sun itself, seen from the camera. */
float sun_through_clouds(vec3 view_sun)
{
	return cloud_shadow(vec3(0.0), view_sun);
}

/* How grey and dull the day is, 0 under a clear or broken sky. */
float weather_gloom()
{
	return u_weather >= WEATHER_RAIN ? 0.5 + 0.5 * u_weather_amount : 0.0;
}

/* Water on flat ground, in patches fixed to the track. flatness is the ground normal's height. */
float puddle(vec3 world, float flatness)
{
	float level = 0.78 - 0.28 * u_wet;

	if (u_wet <= 0.0)
		return 0.0;
	return smoothstep(0.9, 0.97, flatness) * smoothstep(level, level + 0.04, weather_fbm(world.xz / PUDDLE_SIZE));
}

/* Snow lying on whatever faces up, from patches to full cover as the strength rises. */
float snow_cover(vec3 world, float facing)
{
	float level = 0.85 - 0.8 * u_weather_amount;

	if (u_weather != WEATHER_SNOW)
		return 0.0;
	return smoothstep(0.3, 0.7, facing) * smoothstep(level - 0.1, level + 0.1, weather_fbm(world.xz / SNOW_PATCH_SIZE));
}

/* The sky a puddle mirrors, close to the horizon's colour. */
vec3 sky_reflection(vec3 fog_color)
{
    vec3 day=u_hdr!=0?scene_from_gamma(fog_color):to_linear(fog_color);
    // Rain water reflects a dark overcast sky, not the track's often-white fog.
    if(u_weather==WEATHER_RAIN)day=vec3(0.10,0.12,0.15);
    return mix(day,night_sky_color(0.05)*mix(0.5,1.0,clamp(u_205_moon,0.0,1.0)),night_sky_amount(u_night));
}
