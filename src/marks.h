#pragma once
typedef struct {float bottom[3],radius,width;unsigned id;float center[3],axis[3];int geometric;} mark_wheel;
typedef struct {mark_wheel wheels[2];int valid;GLuint heights;int height_w,height_h;float spacing,time;int contact;float interval;GLuint surface;float texscale,wet;int surface_enabled;} marks_frame;
void marks_submit(const marks_frame *frame);
void marks_select_rider(unsigned rider);
void marks_clear(void);
void surface_clear(void);
float surface_coat(int wheel,float soil[3]);
void surface_draw(const float *view,const float *projection,float now,GLboolean depth_write,int flags,float amount);
void marks_lost(void);


