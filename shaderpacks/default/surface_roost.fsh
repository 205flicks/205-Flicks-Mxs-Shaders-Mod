#version 150
in vec4 v_tint;
flat in float v_kind;
out vec4 f_color;
void main(){
 vec2 q=gl_PointCoord*2.0-1.0;
 float r=dot(q,q);
 if(r>=1.0)discard;
 float edge=1.0-smoothstep(0.08,1.0,r);
 float mottling=0.77+0.23*sin(q.x*9.0+q.y*6.0)*sin(q.y*11.0-q.x*5.0);
 vec3 c=v_tint.rgb;
 f_color=vec4(c,edge*v_tint.a*(v_kind<0.5?mottling:1.0));
}
