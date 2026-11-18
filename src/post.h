#pragma once

typedef unsigned int GLenum, GLuint, GLbitfield;
typedef int GLint, GLsizei;
typedef unsigned char GLboolean;
typedef char GLchar;

#define SHADOW_UNIT 8	/* and the next one, kept bound during a race */

/* What post_run needs from the frame, and the game state it has to put back. */
typedef struct {
	GLuint scene_fbo,local_shadow_tex;
	const float *local_shadow_matrix;
	int w, h;
	const float *projection;
	const float *sun_view;
	const float *view_up;		/* world up in view space */
	const float *fog_color;		/* the game's, gamma encoded */
	const float *shadow_matrix;	/* view space to wide shadow map, NULL without one */
	float camera_height;		/* above the ground around the rider */
	float fog_amount;		/* the fog setting, 1 is the pack's default */
	float moon,stars;
	int light_look,preset_color;
	float ao_amount,contact_amount;
	float contact_rider[3];
	int contact_rider_valid;
	int ao_quality,ao_samples;
	float dof, saturation, contrast, split_tone;	/* the same for these */
	float bloom;
	int edge_smoothing;
	float noise_reduction;
	float sun_moved;		/* 1 when the player moved the sun */
	const float *world_from_view;	/* this frame's camera, for weather fixed to the track */
	float time;			/* seconds, for weather that moves */
	int weather;			/* as common.glsl's WEATHER_ constants */
	float weather_amount, wet;
	float night;			/* the time of day setting, 1 has nothing from the sun */
	unsigned frame;
	int motion_samples, motion_tagged;
	float motion_length, motion_radius, motion_center[3];
	const float *motion_reproject;
	float motion;			/* blur per frame of movement */
	GLuint program, vao;
	GLenum active_unit, blend_src, blend_dst;
	GLint viewport[4];
} post_state;

void post_init(PROC (WINAPI *get_proc)(LPCSTR));
void post_run(const post_state *s);
void post_reload(void);
BOOL post_ready(void);
void post_context_lost(void);
