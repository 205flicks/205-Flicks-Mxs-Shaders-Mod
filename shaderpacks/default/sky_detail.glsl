/* Camera rays sample a layered sky dome. No full-scene cloud ray march. */
float sky_hash(vec2 p)
{
    return weather_hash(p);
}

float sky_cloud_shape(vec2 p,float cover,out float broad)
{
    broad=weather_fbm(p);
    float billows=weather_fbm(p*2.37+vec2(2.1,4.3));
    float detail=weather_fbm(p*6.13+vec2(5.7,1.9));
    float fine=weather_fbm(p*15.7+vec2(1.3,6.7));
    float shape=broad*0.58+billows*0.26+detail*0.12+fine*0.04;
    float threshold=mix(0.64,0.32,cover);
    return smoothstep(threshold-0.045,threshold+0.14,shape);
}

vec4 sky_cloud_layer(vec3 dir,vec3 camera,vec3 light,float night,float rain,
                     float cover,float height,float scale,float offset)
{
    if(dir.y<-0.08)return vec4(0.0);
    // Curved horizon projection avoids the infinite stretch of a flat plane.
    float distance=max(height-camera.y,80.0)/max(dir.y+0.16,0.08);
    vec2 p=(camera.xz+dir.xz*distance+WIND*u_time*0.12)/scale+offset;
    float center;
    float density=sky_cloud_shape(p,cover,center);
    vec2 toward=light.xz*0.16;
    float neighbor=weather_fbm(p+toward);
    vec2 gradient=vec2(weather_fbm(p+vec2(0.035,0.0))-center,
                       weather_fbm(p+vec2(0.0,0.035))-center)/0.035;
    vec3 normal=normalize(vec3(-gradient.x,0.7,-gradient.y));
    float billowLight=max(dot(normal,light),0.0);
    float shade=clamp(0.28+0.42*billowLight+(center-neighbor)*2.6-density*0.16,0.10,0.95);
    float silver=pow(max(dot(dir,light),0.0),24.0)*(1.0-density)*0.32;
    vec3 day=mix(vec3(0.36,0.43,0.54),vec3(0.88,0.91,0.96),shade);
    vec3 storm=mix(vec3(0.045,0.055,0.075),vec3(0.24,0.27,0.32),shade);
    day=mix(day,storm,rain);
    vec3 moonlit=mix(vec3(0.003,0.005,0.009),vec3(0.026,0.033,0.049),shade);
    vec3 color=mix(day,moonlit,night)+mix(vec3(0.65,0.58,0.46),vec3(0.025),night)*silver;
    float horizon=smoothstep(-0.08,0.06,dir.y);
    float opacity=density*mix(0.87,0.98,rain)*horizon;
    return vec4(color,opacity);
}

vec3 sky_stars(vec3 dir,float layer)
{
    float longitude=atan(dir.z,dir.x)/(2.0*PI)+0.5;
    float columns=layer>0.5?1250.0:2048.0;
    vec2 p=vec2(longitude*columns,asin(clamp(dir.y,-1.0,1.0))*700.0*(layer>0.5?0.61:1.0));
    p+=vec2(0.37+layer*0.22,layer*137.0);
    vec2 cell=floor(p),f=fract(p)-0.5;
    cell.x=mod(cell.x,columns);
    vec2 gradientX=dFdx(p),gradientY=dFdy(p);
    gradientX.x=mod(gradientX.x+columns*0.5,columns)-columns*0.5;
    gradientY.x=mod(gradientY.x+columns*0.5,columns)-columns*0.5;
    float footprint=clamp(max(length(gradientX),length(gradientY)),0.015,4.0);
    float seed=sky_hash(cell+layer*27.0);
    if(seed<0.982)return vec3(0.0);
    vec2 center=(vec2(sky_hash(cell+3.2),sky_hash(cell+9.7))-0.5)*0.56;
    float radius=mix(0.045,0.14,sky_hash(cell+13.1));
    float distance=length(f-center);
    float sigma=max(radius*0.60,footprint*0.35);
    float star=exp(-distance*distance/max(2.0*sigma*sigma,0.0001));
    star*=min(1.0,radius*radius/max(sigma*sigma,0.0001));
    float bright=mix(0.25,5.0,pow(sky_hash(cell+21.0),5.0));
    vec3 color=mix(vec3(1.0,0.83,0.65),vec3(0.67,0.81,1.0),sky_hash(cell+29.3));
    return color*star*bright;
}

vec3 sky_galaxy(vec3 dir)
{
    vec3 axis=normalize(vec3(0.24,0.73,-0.64));
    float latitude=dot(dir,axis);
    float band=exp(-latitude*latitude*75.0);
    vec3 tangent=normalize(cross(axis,vec3(0.0,1.0,0.0)));
    vec3 across=cross(axis,tangent);
    vec2 patch=vec2(dot(dir,tangent),dot(dir,across))*5.0;
    vec2 gradientX=dFdx(patch)/NOISE_CELLS,gradientY=dFdy(patch)/NOISE_CELLS;
    if(band<0.002)return vec3(0.0);
    float clusters=textureGrad(u_weather_noise,(patch*1.7+vec2(2.4,5.1))/NOISE_CELLS,gradientX*1.7,gradientY*1.7).r;
    float lanes=textureGrad(u_weather_noise,patch*5.1/NOISE_CELLS,gradientX*5.1,gradientY*5.1).r*0.72+
                textureGrad(u_weather_noise,patch*17.3/NOISE_CELLS,gradientX*17.3,gradientY*17.3).r*0.28;
    float dust=smoothstep(0.36,0.68,lanes);
    return mix(vec3(0.006,0.009,0.017),vec3(0.025,0.022,0.031),clusters)
        *band*(0.35+1.1*clusters)*(1.0-0.72*dust);
}

vec3 sky_moon(vec3 dir)
{
    float radius=0.014;
    vec3 tangent=normalize(cross(vec3(0.0,1.0,0.0),MOON_DIR));
    vec3 bitangent=cross(MOON_DIR,tangent);
    vec2 disk=vec2(dot(dir,tangent),dot(dir,bitangent))/radius;
    float r=length(disk);
    float angle=length(dir-MOON_DIR);
    float halo=0.018*exp(-angle/0.045);
    float aa=max(length(fwidth(dir))/radius,0.015);
    if(r>1.1||dot(dir,MOON_DIR)<0.0)return vec3(0.74,0.82,1.0)*halo;
    float mask=1.0-smoothstep(1.0-aa,1.0+aa,r);
    vec3 sphere=vec3(disk,sqrt(max(0.0,1.0-dot(disk,disk))));
    float light=0.18+0.82*max(dot(sphere,normalize(vec3(-0.35,0.24,0.91))),0.0);
    float maria=0.65*weather_noise(disk*2.2+vec2(4.1,2.7))+0.35*weather_noise(disk*5.7+vec2(7.3,1.9));
    vec2 craterUV=disk*9.0,cell=floor(craterUV),f=fract(craterUV)-0.5;
    vec2 craterCenter=(vec2(sky_hash(cell),sky_hash(cell+2.0))-0.5)*0.4;
    float crater=exp(-pow((length(f-craterCenter)-0.16)*22.0,2.0));
    float textureValue=clamp(0.57+0.62*maria+0.08*crater,0.45,1.0);
    return vec3(0.91,0.94,1.0)*textureValue*light*mask*1.9+vec3(0.74,0.82,1.0)*halo;
}

vec3 detailed_sky(vec3 original,vec3 dir,float flash,float slot)
{
    if(!replacement_sky_active(u_sky_look))return original;
    bool rainy=u_weather==WEATHER_RAIN||u_weather==WEATHER_STORM;
    bool snow=u_weather==WEATHER_SNOW;
    float night=night_sky_amount(u_night);
    float rain=rainy?0.78+0.22*u_weather_amount:snow?0.85:0.0;
    vec3 skySun=dot(u_sky_sun,u_sky_sun)>0.0001?u_sky_sun:u_sun;
    if(dot(skySun,skySun)<0.0001)skySun=vec3(0.3,0.8,-0.52);
    vec3 sun=sky_sun_world(skySun);
    vec3 celestial=night>0.5?MOON_DIR:sun;
    float elevation=clamp(dir.y,0.0,1.0);
    float warm=(u_sky_look==4?1.0:1.0-smoothstep(0.10,0.52,sun.y))*(1.0-night);
    vec3 day=day_sky_backdrop(dir,sun,u_sky_look);
    vec3 color=mix(day,night_sky_color(dir.y),night);
    float above=smoothstep(-0.015,0.08,dir.y);

    if(night>0.0){
        vec3 stars=sky_stars(dir,0.0)+sky_stars(dir,1.0)*0.55;
        color+=(stars*max(u_205_stars,0.0)*1.8+sky_galaxy(dir)*2.0)*night*above;
        color+=sky_moon(dir)*max(u_205_moon,0.0)*night*above;
    }
    if(night<1.0){
        float angle=length(dir-sun),radius=0.00465;
        float aa=max(length(fwidth(dir)),0.00012);
        float disk=1.0-smoothstep(radius-aa,radius+aa,angle);
        float limb=sqrt(max(0.0,1.0-pow(min(angle/radius,1.0),2.0)));
        vec3 sunColor=mix(vec3(1.0,0.94,0.79),vec3(1.0,0.48,0.16),warm);
        color+=sunColor*((0.72+0.28*limb)*disk*12.0+exp(-angle*27.0)*0.28)
            *(1.0-night)*(1.0-rain*0.95)*above;
    }

    float cover=u_weather==WEATHER_CLOUDY?0.65+0.25*u_weather_amount:
                rainy?0.72+0.20*u_weather_amount:snow?0.91:mix(0.34,0.16,night);
    vec3 camera=to_world(vec3(0.0));
    vec4 high=sky_cloud_layer(dir,camera,celestial,night,rain,cover*0.8,1850.0,1050.0,3.8);
    vec4 low=sky_cloud_layer(dir,camera,celestial,night,rain,cover,1050.0,620.0,0.0);
    color=mix(color,high.rgb,high.a*0.62);
    color=mix(color,low.rgb,low.a);
    // A soft cloud flash surrounds the visible bolt during either rain mode.
    if(flash>0.0 && rainy){
        color+=vec3(0.50,0.62,0.85)*flash*(0.12+0.25*low.a);
        color+=vec3(0.8,0.87,1.0)*lightning_bolt(dir,slot)*flash*14.0;
    }
    return max(mix(sky_without_teal(color),color,night),vec3(0.0));
}
