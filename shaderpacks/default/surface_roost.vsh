#version 150
uniform mat4 u_view,u_projection;
uniform vec4 u_position[72],u_velocity[72],u_tint[72];
uniform float u_now,u_height,u_amount;
out vec4 v_tint;
void main(){
 int i=gl_VertexID;
 vec4 p=u_position[i],v=u_velocity[i];
 float age=u_now-p.w, life=abs(v.w);
 vec3 center=p.xyz+v.xyz*age;
 float gravity=0.25;
 center.y-=0.5*gravity*age*age;
 vec4 eye=u_view*vec4(center,1);
 gl_Position=u_projection*eye;
 if(age<0.0||age>=life||center.y<p.y-0.12||eye.z>=-0.1||life<=0.0)
  gl_Position=vec4(2,2,2,1);
 float radius=0.40+age*1.12;
 gl_PointSize=clamp(u_height*radius/max(-eye.z,1.0),1.0,110.0);
 v_tint=vec4(u_tint[i].rgb,(1.0-smoothstep(0.0,max(life,0.01),age))*min(0.90,u_amount*0.17));
}
