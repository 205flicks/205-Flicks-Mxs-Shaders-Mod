#version 150

/* Environment reflection, added over the lit model by the game. */

in vec3 interp_normal, interp_tangent, interp_viewer;
in vec2 interp_texcoord;

uniform mat3 u_envmat;
uniform sampler2D u_tex, u_nmap;
uniform vec3 u_specular_color;

out vec4 f_fragcolor;

#include "common.glsl"

/* Painted plastic reflects weakly head on and strongly at grazing angles. */
const float BASE_REFLECTION = 0.45;

/* The environment texture is polar: the center looks up, the edge straight down. */
vec2 environment_coord(vec3 dir)
{
	return 0.5 + dir.xz / max(length(dir.xz),1e-5) * acos(clamp(dir.y,-1.0,1.0)) / (2.0 * PI);
}

void main()
{
	vec3 n, t, b, bumps;
	vec3 mirrored;

	n = normalize(interp_normal);
	t = normalize(interp_tangent - n * dot(n, interp_tangent));
	b = cross(n, t);
	bumps = texture(u_nmap, interp_texcoord).rgb * 2.0 - 1.0;
	n = normalize(t * bumps.x + b * bumps.y + n * bumps.z);

	mirrored = normalize(u_envmat * reflect(interp_viewer, n));
	vec4 environment=texture(u_tex,environment_coord(mirrored));
	vec3 response=environment.rgb*u_specular_color;
	if(u_hdr!=0)response=to_linear(environment.rgb)*u_specular_color;
	float edge=fresnel(n,interp_viewer,BASE_REFLECTION);
    float night=night_sky_amount(u_night);
    // Reflect the same subdued sky in authored water and glossy surfaces.
    float strength=clamp(dot(u_specular_color,vec3(0.2126,0.7152,0.0722)),0.0,1.0);
    vec3 sky=night_sky_color(mirrored.y)*strength;
    if(u_hdr==0)sky=to_gamma(tonemap(sky));
    f_fragcolor=vec4(mix(response,sky,night)*edge,environment.a);
}
