shader_type canvas_item;
// ============================================================================
// NRCU FX overlay shader — layer build for the VS-screen effect lab.
//
// Architecture (the "umdenken"):
//   BASE  = the element untouched (base_mode 0)  or  the Obligate mono stamp
//           (base_mode 1, the classic look, kept for reference presets).
//   FX1 DITHER  [fx_dither]  ordered-dither overlay on the colour element
//   FX2 FRINGE  [fx_fringe]  the Obligate edge->trail->two-colour split,
//                            now on ANY base; colours fixed or auto-from-image
//   FX3 FLOW    [fx_flow]    the whisp driver motion (fringes move); off =
//                            frozen, static fringes
//   FX4 RGB     [fx_rgb]     classic channel shift
//
// The edge/wind/colour-signal core is a faithful port of the accepted
// Obligate dither_rgb.gdshader (which stays in shaders/ untouched).
// Every FX amount is a 0..1 uniform so the lab (and later the VS screen)
// can drive them with timing curves.
// ============================================================================

uniform sampler2D source_tex : filter_nearest, repeat_disable;
uniform vec2 tex_size = vec2(1280.0, 720.0);

// ---- base -------------------------------------------------------------
uniform float base_mode = 0.0;        // 0 = element untouched, 1 = mono stamp

// ---- layer amounts (driven by the lab's motion system) ----------------
uniform float fx_dither = 0.0;
uniform float fx_fringe = 0.0;
uniform float fx_flow = 1.0;
uniform float fx_rgb = 0.0;

// ---- layer 1 front end (stamp + dither overlay) -----------------------
uniform float threshold = 0.75;
uniform float black_point = 0.0;
uniform float white_point = 1.0;
uniform float gamma_corr = 1.35;
uniform float contrast = 1.6;
uniform float brightness = 0.0;
uniform float dither_mode = 1.0;
uniform float bayer_level = 2.0;
uniform float dither_pixel = 2.0;
uniform float dither_levels = 6.0;    // overlay quantization levels

// ---- fringe (layer 2) --------------------------------------------------
uniform float flow_strength = 12.0;
uniform float flow_center_x = 0.5;
uniform float flow_center_y = 0.5;
uniform float edge_threshold = 0.08;
uniform float wind_reach = 32.0;
uniform float wind_trail = 0.35;
uniform float wind_cutoff = 0.22;
uniform float split_separation = 0.85;
uniform float wind_displace = 1.0;
uniform float signal_gain = 1.35;
uniform float color_blur = 0.0;
uniform float signal_softness = 0.08;
uniform float signal_posterize = 0.0;
uniform float rgb_dither = 1.0;
uniform float rgb_gradient = 0.0;
uniform float rgb_gradient_balance = 0.0;
uniform float rgb_gradient_contrast = 1.0;
uniform vec4 fringe_color_a : source_color = vec4(0.0, 1.0, 0.0, 1.0);   // green
uniform vec4 fringe_color_b : source_color = vec4(1.0, 0.0, 1.0, 1.0);   // magenta
uniform float fringe_bleed = 0.6;     // how far fringes spill past the element alpha

// ---- driver (for FLOW) -------------------------------------------------
uniform float driver_mode = 0.0;
uniform float FIELD_STRENGTH = 0.42;
uniform float FIELD_SPEED = 0.55;
uniform float OUTWARDNESS = 0.55;
uniform float FIELD_BREAKUP = 0.85;
uniform float COORD_NUDGE = 0.18;
uniform float FIELD_SIZE = 1.0;
uniform vec2 FIELD_CENTER = vec2(1.25, 1.45);
uniform float LEGACY_SCALE = 5.0;
uniform float LEGACY_SPEED = 0.3;
uniform float LEGACY_RADIAL = 0.45;
uniform vec2 DRIVER_CENTER = vec2(1.5, 1.5);
uniform float DRIVER_SCALE = 1.0;
uniform float DRIVER_STRETCH = 0.0;
uniform float DRIVER_ANGLE = 0.0;
uniform float DRIVER_SPEED = 1.0;
uniform float DRIVER_DETAIL = 0.5;
uniform float DRIVER_FLOW = 0.5;

// ---- rgb shift (fx4) ---------------------------------------------------
uniform float rgb_shift_amount = 0.0;  // in source px
uniform float rgb_shift_angle = 0.0;   // degrees

// ---- time ---------------------------------------------------------------
uniform float fx_time = 0.0;           // the lab drives this (seconds)
uniform float temporal_hold = 0.0;

// =========== noise ===========
float rng(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453123);}
float noise_val(vec2 p){
	vec2 i=floor(p);vec2 f=fract(p);
	vec2 u=f*f*(3.0-2.0*f);
	return mix(mix(rng(i),rng(i+vec2(1,0)),u.x),mix(rng(i+vec2(0,1)),rng(i+vec2(1,1)),u.x),u.y);
}
float fbm(vec2 p){
	float v=0.0,a=1.0,f=1.0;
	for(int i=0;i<3;i++){v+=a*noise_val(p*f);f*=2.1;a*=0.5;}
	return v/1.75;
}
vec2 rotate_05(vec2 p){
	float c=cos(0.5);
	float s=sin(0.5);
	return vec2(c*p.x+s*p.y,-s*p.x+c*p.y);
}
float fbm_driver(vec2 p){
	float v=0.0;
	float a=0.5;
	vec2 shift=vec2(100.0);
	for(int i=0;i<5;i++){
		v+=a*noise_val(p);
		p=rotate_05(p)*2.0+shift;
		a*=0.5;
	}
	return v;
}
vec2 hash22(vec2 p){
	vec3 p3=fract(vec3(p.xyx)*vec3(0.1031,0.1030,0.0973));
	p3+=dot(p3,p3.yzx+33.33);
	return fract((p3.xx+p3.yz)*p3.zy);
}
vec3 hash33(vec3 p){
	float n=sin(dot(p,vec3(7.0,157.0,113.0)));
	return fract(vec3(2097152.0,262144.0,32768.0)*n)*2.0-1.0;
}
vec3 hash33_01(vec3 p){
	float n=sin(dot(p,vec3(7.0,157.0,113.0)));
	return fract(vec3(2097152.0,262144.0,32768.0)*n);
}

// =========== travelling whisp driver ===========
vec2 ripple_vector(vec2 uv,vec2 center,float time,float scale,float speed){
	vec2 to_pixel=uv-center;
	float d=length(to_pixel)+0.0001;
	vec2 dir=to_pixel/d;
	float phase=d*scale-time*speed;
	float wave=cos(phase);
	float falloff=exp(-d*1.05);
	return dir*wave*falloff;
}
float ripple_line(vec2 uv,vec2 center,float time,float scale,float speed){
	float d=distance(uv,center);
	float phase=d*scale-time*speed;
	float wave=sin(phase);
	float falloff=exp(-d*1.2);
	return wave*falloff;
}
vec4 travelling_whisp_core(vec2 st,float time){
	float size=max(FIELD_SIZE,0.0001);
	float ripple_scale=32.0/size;
	float speed=FIELD_SPEED;
	vec2 uv=st/3.0;
	vec2 center=FIELD_CENTER/3.0;

	vec2 breaker;
	breaker.x=fbm_driver(uv*mix(0.8,2.4,FIELD_BREAKUP)+vec2(time*0.025,3.1));
	breaker.y=fbm_driver(uv*mix(0.8,2.4,FIELD_BREAKUP)+vec2(8.7,-time*0.022));
	breaker=breaker*2.0-1.0;
	vec2 ripple_uv=uv+breaker*0.095;

	vec2 c0=center;
	vec2 c1=center+vec2(-0.54,-0.30)*size;
	vec2 c2=center+vec2(1.01,0.28)*size;

	vec2 push=vec2(0.0);
	float ring=0.0;
	push+=ripple_vector(ripple_uv,c0,time,ripple_scale,speed*3.05)*1.00;
	push+=ripple_vector(ripple_uv,c1,time,ripple_scale*0.75,speed*2.10)*0.45;
	push+=ripple_vector(ripple_uv,c2,time,ripple_scale*0.59,speed*1.55)*0.35;
	ring+=ripple_line(ripple_uv,c0,time,ripple_scale,speed*3.05)*1.00;
	ring+=ripple_line(ripple_uv,c1,time,ripple_scale*0.75,speed*2.10)*0.35;
	ring+=ripple_line(ripple_uv,c2,time,ripple_scale*0.59,speed*1.55)*0.25;

	float matter_mask=fbm_driver(uv*0.75+vec2(0.0,time*0.018));
	matter_mask=smoothstep(0.18,0.92,matter_mask);
	push*=matter_mask;
	ring*=matter_mask;

	vec2 base_uv=uv+push*0.052;
	vec2 q;
	q.x=fbm_driver(base_uv*2.0+ring*0.18);
	q.y=fbm_driver(base_uv*2.0+vec2(5.2,1.3)-ring*0.18);
	vec2 r;
	r.x=fbm_driver(base_uv*2.0+4.0*q+vec2(1.7,9.2)+ring*0.45);
	r.y=fbm_driver(base_uv*2.0+4.0*q+vec2(8.3,2.8)-ring*0.45);
	float f=fbm_driver(base_uv*2.0+q+r*1.65)+ring*0.055;
	f=smoothstep(0.18,0.92,f);

	vec2 smoke=normalize((q-vec2(0.5))+(r-vec2(0.5))*0.65+vec2(0.0001));
	vec2 field=mix(smoke,push*18.0,clamp(OUTWARDNESS,0.0,1.0));
	return vec4(field,f-0.5,ring);
}
vec2 travelling_whisp_field(vec2 st,float time){ return travelling_whisp_core(st,time).xy; }
float travelling_whisp_amount(vec2 st,float time){ return travelling_whisp_core(st,time).z; }

// =========== driver catalogue (modes 2-13) ===========
float voronoi2(vec2 p,float time){
	vec2 g=floor(p);
	vec2 f=fract(p);
	float d=1.0;
	for(int y=-1;y<=1;y++){
		for(int x=-1;x<=1;x++){
			vec2 cell=vec2(float(x),float(y));
			vec2 h=hash22(g+cell);
			vec2 jitter=0.5+mix(0.16,0.48,DRIVER_DETAIL)*sin(time*0.55+6.2831853*h);
			vec2 r=cell+jitter-f;
			d=min(d,dot(r,r));
		}
	}
	return 1.0-smoothstep(mix(0.08,0.012,DRIVER_DETAIL),mix(0.92,0.52,DRIVER_DETAIL),d);
}
float voronoi_layers(vec2 p,float time){
	float a=0.55;
	float v=0.0;
	float s=0.0;
	for(int i=0;i<4;i++){
		v+=voronoi2(p,time)*a;
		s+=a;
		p=rotate_05(p*mix(1.35,2.25,DRIVER_DETAIL)+vec2(3.7,1.9));
		time*=mix(1.12,1.72,DRIVER_DETAIL);
		a*=mix(0.42,0.68,DRIVER_DETAIL);
	}
	return v/max(s,0.001);
}
float combustible_voronoi(vec3 p){
	vec3 g=floor(p);
	p=fract(p);
	float d=1.0;
	for(int y=-1;y<=1;y++){
		for(int x=-1;x<=1;x++){
			vec3 b=vec3(float(x),float(y),-1.0);
			vec3 r=b-p+hash33_01(g+b);
			d=min(d,dot(r,r));
			b.z=0.0;
			r=b-p+hash33_01(g+b);
			d=min(d,dot(r,r));
			b.z=1.0;
			r=b-p+hash33_01(g+b);
			d=min(d,dot(r,r));
		}
	}
	return d;
}
float combustible_noise_layers(vec3 p,float time){
	vec3 t=vec3(0.0,0.0,p.z+time*0.45);
	float total=0.0;
	float sum=0.0;
	float amp=1.0;
	for(int i=0;i<5;i++){
		total+=combustible_voronoi(p+t)*amp;
		p*=2.0;
		t*=1.5;
		sum+=amp;
		amp*=0.5;
	}
	return total/max(sum,0.001);
}
float combustible_voronoi_amount(vec2 p,float time){
	float detail=clamp(DRIVER_DETAIL,0.0,1.0);
	vec2 uv=(p-vec2(1.5))*mix(0.42,1.25,detail);
	uv+=vec2(time*0.006,-time*0.0035)*smoothstep(0.35,1.0,detail);
	float z=0.35+time*mix(0.012,0.085,detail);
	float sample_scale=mix(0.72,1.85,detail);
	float blur=mix(0.16,0.025,detail);
	float c=combustible_noise_layers(vec3(uv,z)*sample_scale,time);
	c+=combustible_noise_layers(vec3(uv+vec2( blur,0.0),z)*sample_scale,time)*0.18;
	c+=combustible_noise_layers(vec3(uv+vec2(-blur,0.0),z)*sample_scale,time)*0.18;
	c+=combustible_noise_layers(vec3(uv+vec2(0.0, blur),z)*sample_scale,time)*0.18;
	c+=combustible_noise_layers(vec3(uv+vec2(0.0,-blur),z)*sample_scale,time)*0.18;
	c/=1.72;
	float soft=pow(clamp(c,0.0,1.0),mix(0.72,1.18,detail));
	float hard=smoothstep(0.22,0.70,c);
	return clamp(mix(soft,hard,smoothstep(0.72,1.0,detail)),0.0,1.0);
}
vec2 phasorish(vec2 position,vec2 direction,float phase_offset,float scale_variation){
	vec2 i=floor(position);
	vec2 f=fract(position);
	vec2 u=f*f*(3.0-2.0*f);
	vec2 n00=hash22(i+vec2(0.0,0.0));
	vec2 n10=hash22(i+vec2(1.0,0.0));
	vec2 n01=hash22(i+vec2(0.0,1.0));
	vec2 n11=hash22(i+vec2(1.0,1.0));
	vec2 d00=position-(i+vec2(0.0,0.0));
	vec2 d10=position-(i+vec2(1.0,0.0));
	vec2 d01=position-(i+vec2(0.0,1.0));
	vec2 d11=position-(i+vec2(1.0,1.0));
	float a00=dot(direction,d00)*(1.0+scale_variation*(2.0*n00.y-1.0))+n00.x*6.2831853+phase_offset;
	float a10=dot(direction,d10)*(1.0+scale_variation*(2.0*n10.y-1.0))+n10.x*6.2831853+phase_offset;
	float a01=dot(direction,d01)*(1.0+scale_variation*(2.0*n01.y-1.0))+n01.x*6.2831853+phase_offset;
	float a11=dot(direction,d11)*(1.0+scale_variation*(2.0*n11.y-1.0))+n11.x*6.2831853+phase_offset;
	vec2 c00=vec2(cos(a00),sin(a00));
	vec2 c10=vec2(cos(a10),sin(a10));
	vec2 c01=vec2(cos(a01),sin(a01));
	vec2 c11=vec2(cos(a11),sin(a11));
	return mix(mix(c00,c10,u.x),mix(c01,c11,u.x),u.y);
}
vec2 phasor_flow(vec2 p,float time){
	float n1=fbm_driver(p*0.38+vec2(time*0.06,-time*0.035));
	float n2=fbm_driver(p*0.61+vec2(-time*0.02,time*0.05));
	vec2 base=normalize(vec2(1.0,0.72)+vec2(n1-0.5,n2-0.5)*2.1);
	return normalize(mix(base,vec2(-base.y,base.x),DRIVER_FLOW*0.65));
}
float phasor_amount(vec2 p,float time){
	vec2 flow=phasor_flow(p,time);
	vec2 normal=vec2(-flow.y,flow.x);
	vec2 s0=phasorish(p*7.5+flow*time*0.55,normal*8.0,time*1.6,DRIVER_DETAIL);
	vec2 s1=phasorish(p*12.0-flow*time*0.28+vec2(31.7,12.4),normal*5.5,-time*1.1,DRIVER_DETAIL);
	float line=mix(s0.x,s1.x,0.35);
	return smoothstep(-0.45,0.45,line);
}
float tetra_noise(vec3 p){
	vec3 i=floor(p+dot(p,vec3(0.333333)));
	p-=i-dot(i,vec3(0.166666));
	vec3 i1=step(p.yzx,p);
	vec3 i2=max(i1,1.0-i1.zxy);
	i1=min(i1,1.0-i1.zxy);
	vec3 p1=p-i1+0.166666;
	vec3 p2=p-i2+0.333333;
	vec3 p3=p-0.5;
	vec4 v=max(0.5-vec4(dot(p,p),dot(p1,p1),dot(p2,p2),dot(p3,p3)),0.0);
	vec4 d=vec4(dot(p,hash33(i)),dot(p1,hash33(i+i1)),dot(p2,hash33(i+i2)),dot(p3,hash33(i+1.0)));
	return clamp(dot(d,v*v*v*8.0)*1.732+0.5,0.0,1.0);
}
float isoline_amount(vec2 p,float time,float source_drive){
	p+=vec2(-time*0.24,time*0.07);
	float n=tetra_noise(vec3(p*1.15,source_drive*1.8))*0.55;
	n*=tetra_noise(vec3(p*0.37+vec2(8.0,-4.0),time*0.08))*1.55;
	n=mix(n,dot(p,vec2(-0.66,1.0))*0.22+source_drive*0.42,0.55);
	float spacing=mix(0.055,0.018,DRIVER_DETAIL);
	float lines=abs(fract(n/spacing)-0.5)*2.0;
	return 1.0-smoothstep(0.18,0.74,lines);
}
float spiral_amount(vec2 p,float time){
	vec2 q=p-vec2(1.5);
	float r=length(q);
	float a=atan(q.x,q.y)+time*0.22;
	vec2 ring=vec2(cos(a),sin(a))*mix(14.0,42.0,DRIVER_DETAIL);
	float c=fbm_driver(ring+vec2(fbm_driver(q+time*0.18),-fbm_driver(q-time*0.12))*18.0);
	return smoothstep(0.30,0.42,c)*(1.0-smoothstep(2.4,4.2,r));
}
float curl_smoke_amount(vec2 p,float time){
	float detail=clamp(DRIVER_DETAIL,0.0,1.0);
	vec2 q=p;
	vec2 drift=vec2(time*0.11,-time*0.07);
	float n1=fbm_driver(q*mix(0.42,0.92,detail)+drift);
	float n2=fbm_driver(q*mix(0.68,1.65,detail)+vec2(-time*0.06,time*0.09)+vec2(7.2,-3.1));
	vec2 curl=vec2(n1-0.5,n2-0.5);
	q+=vec2(-curl.y,curl.x)*mix(1.2,3.8,detail);
	float smoke=fbm_driver(q*mix(0.55,1.45,detail)+curl*1.7+drift*0.55);
	return smoothstep(mix(0.24,0.36,detail),mix(0.78,0.62,detail),smoke);
}
float wavefront_amount(vec2 p,float time){
	float detail=clamp(DRIVER_DETAIL,0.0,1.0);
	vec2 dir=normalize(vec2(0.78,0.38)+vec2(DRIVER_FLOW-0.5,0.0));
	float warp=fbm_driver(p*mix(0.35,1.1,detail)+vec2(time*0.05,-time*0.03));
	float freq=mix(1.6,7.5,detail);
	float phase=dot(p,dir)*freq-time*mix(0.55,2.4,detail)+warp*mix(1.2,4.8,detail);
	float wave=0.5+0.5*sin(phase);
	return smoothstep(mix(0.18,0.35,detail),mix(0.82,0.65,detail),wave);
}
float cellular_wind_amount(vec2 p,float time){
	float detail=clamp(DRIVER_DETAIL,0.0,1.0);
	vec2 wind=normalize(vec2(1.0,0.22)+vec2(0.0,DRIVER_FLOW-0.5));
	vec2 q=p*vec2(mix(0.55,1.3,detail),mix(1.6,3.2,detail));
	q+=wind*time*mix(0.22,1.25,detail);
	q+=vec2(fbm_driver(p*0.42+time*0.03),fbm_driver(p*0.57-time*0.04))*mix(0.2,1.1,detail);
	float cells=voronoi2(q,time*mix(0.35,1.4,detail));
	float grain=fbm_driver(p*mix(0.45,1.7,detail)-wind*time*0.22);
	return clamp(mix(cells,grain,0.28),0.0,1.0);
}
float ridge_flow_amount(vec2 p,float time){
	float detail=clamp(DRIVER_DETAIL,0.0,1.0);
	vec2 q=p+vec2(time*0.12,-time*0.04);
	float n=fbm_driver(q*mix(0.55,1.8,detail));
	n+=fbm_driver((q+vec2(n,-n))*mix(1.0,3.4,detail)-time*0.05)*0.45;
	float ridge=1.0-abs(fract(n*mix(2.0,7.5,detail))-0.5)*2.0;
	return smoothstep(mix(0.18,0.34,detail),mix(0.86,0.62,detail),ridge);
}
float source_warp_amount(vec2 p,float time,float source_drive){
	float detail=clamp(DRIVER_DETAIL,0.0,1.0);
	float source=clamp(source_drive,0.0,1.0);
	vec2 q=p+(source-0.5)*mix(1.4,5.0,detail);
	q+=vec2(fbm_driver(p*0.8+time*0.08),fbm_driver(p*1.1-time*0.05))*mix(0.4,2.2,detail);
	float n=fbm_driver(q*mix(0.55,2.4,detail)+vec2(time*0.04,-time*0.06));
	return clamp(mix(n,source,0.35)+smoothstep(0.35,0.82,source)*mix(0.05,0.22,detail),0.0,1.0);
}
float datamosh_river_amount(vec2 p,float time){
	float detail=clamp(DRIVER_DETAIL,0.0,1.0);
	float block=mix(0.85,0.18,detail);
	vec2 q=floor((p+vec2(time*mix(0.15,0.75,detail),0.0))/block)*block;
	float row=floor(q.y/max(block,0.001));
	float lane=rng(vec2(row,floor(time*mix(0.45,1.8,detail))));
	q.x+=lane*mix(1.4,5.5,detail)+time*mix(0.25,1.1,detail);
	q.y+=floor(fbm_driver(q*0.37+time*0.08)*mix(2.0,9.0,detail))*block*0.35;
	float smear=fbm_driver(q*mix(0.75,2.2,detail)+vec2(row*0.07,time*0.05));
	float tear=step(mix(0.72,0.52,detail),fract((p.x+lane*2.1)*mix(2.2,8.5,detail)+time*0.4));
	return clamp(mix(smear,tear,0.22+detail*0.28),0.0,1.0);
}
float magnetic_field_amount(vec2 p,float time){
	float detail=clamp(DRIVER_DETAIL,0.0,1.0);
	vec2 a=vec2(sin(time*0.31),cos(time*0.23))*mix(0.55,1.35,detail);
	vec2 b=vec2(cos(time*0.19+2.1),sin(time*0.27-0.4))*mix(0.65,1.55,detail);
	vec2 q=p-vec2(1.5);
	vec2 pa=q-a;
	vec2 pb=q+b;
	float da=length(pa)+0.04;
	float db=length(pb)+0.04;
	float angle=atan(pa.y,pa.x)-atan(pb.y,pb.x);
	float field=sin(angle*mix(3.0,10.0,detail)+(1.0/da-1.0/db)*mix(0.9,2.8,detail)+time*mix(0.35,1.4,detail));
	float noise=fbm_driver(p*mix(0.35,1.2,detail)+time*0.04);
	return smoothstep(mix(-0.55,-0.18,detail),mix(0.75,0.38,detail),field+noise*0.45);
}
float liquid_scanner_amount(vec2 p,float time){
	float detail=clamp(DRIVER_DETAIL,0.0,1.0);
	vec2 dir=normalize(mix(vec2(0.0,1.0),normalize(vec2(0.82,0.36)),DRIVER_FLOW));
	float sweep=dot(p,dir)*mix(1.4,4.8,detail)-time*mix(0.45,1.9,detail);
	float wobble=fbm_driver(p*mix(0.45,1.7,detail)+vec2(time*0.07,-time*0.05));
	float band=abs(fract(sweep+wobble*mix(0.45,1.8,detail))-0.5)*2.0;
	float scanner=1.0-smoothstep(mix(0.28,0.08,detail),mix(0.72,0.22,detail),band);
	float liquid=fbm_driver((p+vec2(wobble,-wobble))*mix(0.75,2.4,detail)-dir*time*0.15);
	return clamp(scanner*mix(0.65,1.1,liquid)+liquid*mix(0.12,0.32,detail),0.0,1.0);
}
vec2 driver_shape_local(vec2 coord,vec2 center){
	vec2 q=coord-center;
	float a=radians(DRIVER_ANGLE);
	float cs=cos(a);
	float sn=sin(a);
	q=vec2(q.x*cs-q.y*sn,q.x*sn+q.y*cs);
	float stretch=clamp(DRIVER_STRETCH,-1.0,1.0);
	float aspect=pow(4.0,abs(stretch));
	if(stretch>=0.0)q.x*=aspect;
	else q.y*=aspect;
	q=vec2(q.x*cs+q.y*sn,-q.x*sn+q.y*cs);
	return q;
}
float generic_driver_amount(float mode,vec2 st,float time,float source_drive){
	float scale=max(DRIVER_SCALE,0.0001);
	float speed=max(DRIVER_SPEED,0.0);
	vec2 q=driver_shape_local(st,DRIVER_CENTER);
	vec2 p=q*scale+vec2(1.5);
	float t=time*speed;
	if(mode<2.5)return combustible_voronoi_amount(p,t*0.08);
	if(mode<3.5)return phasor_amount(p,t);
	if(mode<4.5)return isoline_amount(p,t,source_drive);
	if(mode<5.5)return spiral_amount(p,t);
	if(mode<6.5)return curl_smoke_amount(p,t);
	if(mode<7.5)return wavefront_amount(p,t);
	if(mode<8.5)return cellular_wind_amount(p,t);
	if(mode<9.5)return ridge_flow_amount(p,t);
	if(mode<10.5)return source_warp_amount(p,t,source_drive);
	if(mode<11.5)return datamosh_river_amount(p,t);
	if(mode<12.5)return magnetic_field_amount(p,t);
	return liquid_scanner_amount(p,t);
}
vec2 generic_driver_flow(float mode,vec2 st,float time,float source_drive){
	float scale=max(DRIVER_SCALE,0.0001);
	float e=clamp(0.018/max(scale,0.02),0.018,4.0);
	float cx1=generic_driver_amount(mode,st+vec2(e,0.0),time,source_drive);
	float cx0=generic_driver_amount(mode,st-vec2(e,0.0),time,source_drive);
	float cy1=generic_driver_amount(mode,st+vec2(0.0,e),time,source_drive);
	float cy0=generic_driver_amount(mode,st-vec2(0.0,e),time,source_drive);
	vec2 grad=vec2(cx1-cx0,cy1-cy0)/(2.0*e);
	if(length(grad)<0.00001){
		return normalize(vec2(1.0,0.35)+vec2(DRIVER_FLOW-0.5,0.25-DRIVER_FLOW)*0.35);
	}
	vec2 tangent=normalize(vec2(-grad.y,grad.x)+vec2(0.0001));
	vec2 downhill=normalize(-grad+vec2(0.0001));
	return normalize(mix(downhill,tangent,DRIVER_FLOW)+vec2(0.0001));
}

// =========== multi-size Bayer (original tables) ===========
float bayer2(vec2 p){ivec2 q=ivec2(mod(p,2.0));
	if(q.x==0&&q.y==0)return 0.0/4.0;if(q.x==1&&q.y==0)return 2.0/4.0;
	if(q.x==0&&q.y==1)return 3.0/4.0;return 1.0/4.0;}
float bayer4(vec2 p){ivec2 q=ivec2(mod(p,4.0));
	if(q.x==0&&q.y==0)return 0.0/16.0; if(q.x==1&&q.y==0)return 8.0/16.0;
	if(q.x==2&&q.y==0)return 2.0/16.0; if(q.x==3&&q.y==0)return 10.0/16.0;
	if(q.x==0&&q.y==1)return 12.0/16.0;if(q.x==1&&q.y==1)return 4.0/16.0;
	if(q.x==2&&q.y==1)return 14.0/16.0;if(q.x==3&&q.y==1)return 6.0/16.0;
	if(q.x==0&&q.y==2)return 3.0/16.0; if(q.x==1&&q.y==2)return 11.0/16.0;
	if(q.x==2&&q.y==2)return 1.0/16.0; if(q.x==3&&q.y==2)return 9.0/16.0;
	if(q.x==0&&q.y==3)return 15.0/16.0;if(q.x==1&&q.y==3)return 7.0/16.0;
	if(q.x==2&&q.y==3)return 13.0/16.0;return 5.0/16.0;}
float bayer8(vec2 p){ivec2 q=ivec2(mod(p,8.0));
	if(q.y==0){if(q.x==0)return 0.0/64.0; if(q.x==1)return 32.0/64.0;
	if(q.x==2)return 8.0/64.0; if(q.x==3)return 40.0/64.0;
	if(q.x==4)return 2.0/64.0; if(q.x==5)return 34.0/64.0;
	if(q.x==6)return 10.0/64.0;return 42.0/64.0;}
	if(q.y==1){if(q.x==0)return 48.0/64.0;if(q.x==1)return 16.0/64.0;
	if(q.x==2)return 56.0/64.0;if(q.x==3)return 24.0/64.0;
	if(q.x==4)return 50.0/64.0;if(q.x==5)return 18.0/64.0;
	if(q.x==6)return 58.0/64.0;return 26.0/64.0;}
	if(q.y==2){if(q.x==0)return 12.0/64.0;if(q.x==1)return 44.0/64.0;
	if(q.x==2)return 4.0/64.0; if(q.x==3)return 36.0/64.0;
	if(q.x==4)return 14.0/64.0;if(q.x==5)return 46.0/64.0;
	if(q.x==6)return 6.0/64.0; return 38.0/64.0;}
	if(q.y==3){if(q.x==0)return 60.0/64.0;if(q.x==1)return 28.0/64.0;
	if(q.x==2)return 52.0/64.0;if(q.x==3)return 20.0/64.0;
	if(q.x==4)return 62.0/64.0;if(q.x==5)return 30.0/64.0;
	if(q.x==6)return 54.0/64.0;return 22.0/64.0;}
	if(q.y==4){if(q.x==0)return 3.0/64.0; if(q.x==1)return 35.0/64.0;
	if(q.x==2)return 11.0/64.0;if(q.x==3)return 43.0/64.0;
	if(q.x==4)return 1.0/64.0; if(q.x==5)return 33.0/64.0;
	if(q.x==6)return 9.0/64.0; return 41.0/64.0;}
	if(q.y==5){if(q.x==0)return 51.0/64.0;if(q.x==1)return 19.0/64.0;
	if(q.x==2)return 59.0/64.0;if(q.x==3)return 27.0/64.0;
	if(q.x==4)return 49.0/64.0;if(q.x==5)return 17.0/64.0;
	if(q.x==6)return 57.0/64.0;return 25.0/64.0;}
	if(q.y==6){if(q.x==0)return 15.0/64.0;if(q.x==1)return 47.0/64.0;
	if(q.x==2)return 7.0/64.0; if(q.x==3)return 39.0/64.0;
	if(q.x==4)return 13.0/64.0;if(q.x==5)return 45.0/64.0;
	if(q.x==6)return 5.0/64.0; return 37.0/64.0;}
	{if(q.x==0)return 63.0/64.0;if(q.x==1)return 31.0/64.0;
	if(q.x==2)return 55.0/64.0;if(q.x==3)return 23.0/64.0;
	if(q.x==4)return 61.0/64.0;if(q.x==5)return 29.0/64.0;
	if(q.x==6)return 53.0/64.0;return 21.0/64.0;}}
float get_bayer(vec2 p){
	int lvl=int(bayer_level);
	if(lvl<=1)return bayer2(p);
	if(lvl==2)return bayer4(p);
	if(lvl==3)return bayer8(p);
	float size=16.0;
	if(lvl>=5)size=32.0;
	vec2 q=mod(floor(p),size);
	float v=0.0;
	float weight=size*size*0.25;
	for(int i=0;i<5;i++){
		if(weight<1.0)break;
		float qx=mod(q.x,2.0);
		float qy=mod(q.y,2.0);
		float code=0.0;
		if(qx<0.5&&qy<0.5)code=0.0;
		else if(qx>0.5&&qy<0.5)code=2.0;
		else if(qx<0.5&&qy>0.5)code=3.0;
		else code=1.0;
		v+=code*weight;
		q=floor(q*0.5);
		weight*=0.25;
	}
	return v/(size*size);
}

// =========== source helpers ===========
float raw_luma(vec2 uv){
	return dot(texture(source_tex,clamp(uv,vec2(0.0),vec2(1.0))).rgb,vec3(0.299,0.587,0.114));
}
float raw_alpha(vec2 uv){
	return texture(source_tex,clamp(uv,vec2(0.0),vec2(1.0))).a;
}
float edge_source(vec2 uv,vec2 texel){
	float xl=raw_luma(uv-vec2(texel.x,0.0));
	float xr=raw_luma(uv+vec2(texel.x,0.0));
	float yu=raw_luma(uv-vec2(0.0,texel.y));
	float yd=raw_luma(uv+vec2(0.0,texel.y));
	float a=raw_alpha(uv);
	float ax=raw_alpha(uv+vec2(texel.x,0.0));
	float ay=raw_alpha(uv+vec2(0.0,texel.y));
	float ga=abs(ax-a)+abs(ay-a);
	return max(abs(xr-xl)+abs(yd-yu), ga*1.2);
}
float edge_mask(vec2 uv,vec2 texel){
	float edge=edge_source(uv,texel);
	return smoothstep(edge_threshold,edge_threshold*3.0,edge);
}
vec2 pixelate_uv(vec2 uv,float size,vec2 tex_dim){
	if(size<=0.5)return uv;
	vec2 px=floor(uv*tex_dim/size)*size+(size*0.5);
	return clamp(px/tex_dim,vec2(0.0),vec2(1.0));
}
float prepared_luma(vec2 uv){
	vec2 sample_uv=dither_pixel>0.5?pixelate_uv(uv,dither_pixel,tex_size):uv;
	float luma=raw_luma(sample_uv);
	float lv=(luma-black_point)/max(white_point-black_point,0.001);
	lv=clamp(lv,0.0,1.0);
	lv=pow(lv,1.0/max(gamma_corr,0.01));
	lv=(lv-0.5)*contrast+0.5+brightness;
	return clamp(lv,0.0,1.0);
}
float dither_at(vec2 uv){
	float block=max(dither_pixel,1.0);
	vec2 cell=floor(clamp(uv,vec2(0.0),vec2(1.0))*tex_size/block);
	if(dither_mode<1.5){ return get_bayer(cell); }
	if(dither_mode<2.5){
		float r=rng(cell);
		float n=(r+rng(cell+vec2(19.7,41.3))+rng(cell+vec2(-31.1,7.9)))/3.0;
		return clamp(r*1.35-n*0.35,0.0,1.0);
	}
	if(dither_mode<3.5){ return rng(cell); }
	if(dither_mode<4.5){
		float checker=mod(cell.x+cell.y,2.0);
		return mix(0.25,0.75,checker);
	}
	return get_bayer(cell);
}
float thresholded_luma(vec2 uv){
	float lv=prepared_luma(uv);
	float mode=dither_mode;
	if(mode<0.5){ return step(threshold,lv); }
	if(mode<4.5){ return step(threshold,lv+dither_at(uv)-0.5); }
	float block=max(dither_pixel,1.0);
	vec2 cell_uv=pixelate_uv(uv,block,tex_size);
	vec2 px=clamp(uv,vec2(0.0),vec2(1.0))*tex_size;
	vec2 cell_origin=floor(px/block)*block;
	vec2 local=(px-cell_origin)/block-vec2(0.5);
	float dist=length(local);
	float radius=mix(0.12,0.72,1.0-prepared_luma(cell_uv));
	float dot_v=1.0-step(radius,dist);
	return 1.0-dot_v;
}

// =========== layer 2: edge signal -> wind trail -> two-colour split ===========
float blurred_edge(vec2 uv,vec2 texel){
	vec2 r1=texel*2.0;
	vec2 r2=texel*5.0;
	vec2 r3=texel*9.0;
	float e=0.0;
	e+=edge_mask(uv,texel)*0.16;
	e+=edge_mask(uv+vec2( r1.x,0.0),texel)*0.07;
	e+=edge_mask(uv+vec2(-r1.x,0.0),texel)*0.07;
	e+=edge_mask(uv+vec2(0.0, r1.y),texel)*0.07;
	e+=edge_mask(uv+vec2(0.0,-r1.y),texel)*0.07;
	e+=edge_mask(uv+vec2( r2.x, r2.y),texel)*0.065;
	e+=edge_mask(uv+vec2(-r2.x, r2.y),texel)*0.065;
	e+=edge_mask(uv+vec2( r2.x,-r2.y),texel)*0.065;
	e+=edge_mask(uv+vec2(-r2.x,-r2.y),texel)*0.065;
	e+=edge_mask(uv+vec2( r3.x,0.0),texel)*0.05;
	e+=edge_mask(uv+vec2(-r3.x,0.0),texel)*0.05;
	e+=edge_mask(uv+vec2(0.0, r3.y),texel)*0.05;
	e+=edge_mask(uv+vec2(0.0,-r3.y),texel)*0.05;
	return clamp(e,0.0,1.0);
}
float wind_edge(vec2 uv,vec2 texel,vec2 wind_dir,float reach_px){
	vec2 wind=normalize(wind_dir);
	float local=blurred_edge(uv,texel)*0.72;
	float trail=0.0;
	trail+=blurred_edge(uv-wind*texel*reach_px*0.25,texel)*0.34;
	trail+=blurred_edge(uv-wind*texel*reach_px*0.50,texel)*0.27;
	trail+=blurred_edge(uv-wind*texel*reach_px*0.78,texel)*0.20;
	trail+=blurred_edge(uv-wind*texel*reach_px*1.10,texel)*0.14;
	float e=clamp(local+trail*wind_trail,0.0,1.0);
	return smoothstep(wind_cutoff,1.0,e);
}
float color_signal(vec2 uv,vec2 texel,vec2 wind_dir,float reach_px){
	float center=wind_edge(uv,texel,wind_dir,reach_px);
	if(color_blur<=0.01)return center;
	vec2 axis=normalize(wind_dir+vec2(0.0001));
	vec2 side=vec2(-axis.y,axis.x);
	vec2 blur_step=texel*color_blur;
	float blurred=center*0.40;
	blurred+=wind_edge(uv+axis*blur_step,texel,wind_dir,reach_px)*0.15;
	blurred+=wind_edge(uv-axis*blur_step,texel,wind_dir,reach_px)*0.15;
	blurred+=wind_edge(uv+side*blur_step,texel,wind_dir,reach_px)*0.15;
	blurred+=wind_edge(uv-side*blur_step,texel,wind_dir,reach_px)*0.15;
	float mix_amount=clamp(color_blur/160.0,0.0,1.0);
	return clamp(mix(center,blurred,mix_amount)*mix(1.0,1.18,mix_amount),0.0,1.0);
}
float posterize_signal(float v){
	if(signal_posterize<1.5)return v;
	float levels=max(signal_posterize,2.0);
	return floor(clamp(v,0.0,1.0)*levels+0.5)/levels;
}
vec3 rgb_to_hsv(vec3 c){
	vec4 K=vec4(0.0,-1.0/3.0,2.0/3.0,-1.0);
	vec4 p=mix(vec4(c.bg,K.wz),vec4(c.gb,K.xy),step(c.b,c.g));
	vec4 q=mix(vec4(p.xyw,c.r),vec4(c.r,p.yzx),step(p.x,c.r));
	float d=q.x-min(q.w,q.y);
	float e=0.000001;
	return vec3(abs(q.z+(q.w-q.y)/(6.0*d+e)),d/(q.x+e),q.x);
}
vec3 hsv_to_rgb(vec3 c){
	vec3 p=abs(fract(c.xxx+vec3(0.0,2.0/3.0,1.0/3.0))*6.0-3.0);
	return c.z*mix(vec3(1.0),clamp(p-1.0,0.0,1.0),c.y);
}
vec3 hue_gradient(vec3 a,vec3 b,float t){
	vec3 ah=rgb_to_hsv(a);
	vec3 bh=rgb_to_hsv(b);
	float dh=bh.x-ah.x;
	if(abs(dh)>0.5){
		if(dh>0.0)ah.x+=1.0;
		else bh.x+=1.0;
	}
	vec3 h=mix(ah,bh,clamp(t,0.0,1.0));
	h.x=fract(h.x);
	return hsv_to_rgb(h);
}

// =========== main ===========
vec2 UVd(vec2 uv){
	return dither_pixel>0.5?pixelate_uv(uv,dither_pixel,tex_size):uv;
}
void fragment(){
	vec2 texel=1.0/tex_size;
	vec2 UVc=clamp(UV,vec2(0.0),vec2(1.0));
	vec4 src=texture(source_tex,UVc);
	float src_alpha=src.a;

	// ---- base ----
	vec3 col;
	if(base_mode<0.5){
		col=src.rgb;
	}else{
		col=vec3(thresholded_luma(UV));
	}

	// ---- fx4: classic rgb shift (before the structural fx) ----
	if(fx_rgb>0.001){
		vec2 rgb_dir=vec2(cos(radians(rgb_shift_angle)),sin(radians(rgb_shift_angle)));
		vec2 off=rgb_dir*texel*max(rgb_shift_amount,0.0);
		vec3 shifted=col;
		shifted.r=texture(source_tex,clamp(UV+off,vec2(0.0),vec2(1.0))).r;
		shifted.b=texture(source_tex,clamp(UV-off,vec2(0.0),vec2(1.0))).b;
		col=mix(col,shifted,clamp(fx_rgb,0.0,1.0));
	}

	// ---- fx1: dither overlay on the colour element ----
	if(base_mode<0.5 && fx_dither>0.001){
		float lv=prepared_luma(UV);
		float lev=max(dither_levels,2.0);
		float d=dither_at(UV);
		float dl=clamp(floor(lv*lev+(d-0.5))/lev,0.0,1.0);
		float lum=max(raw_luma(UV),1e-4);
		vec3 dithered=col*(mix(1.0,dl/lum,1.0));
		float m=clamp(fx_dither,0.0,1.0)*clamp(src_alpha*4.0+0.25,0.0,1.0);
		col=mix(col,clamp(dithered,vec3(0.0),vec3(1.0)),m);
	}

	// ---- fx2/fx3: fringe layer (edge -> trail -> two-colour split) ----
	vec3 overlay_color=vec3(0.0);
	float show=0.0;
	if(fx_fringe>0.001){
		float driver_time=fx_time;
		if(temporal_hold>0.01){
			float fps=max(temporal_hold,1.0);
			driver_time=floor(fx_time*fps)/fps;
		}
		float flow_on=step(0.5,fx_flow);
		// when flow is off: frozen driver, no shimmer modulation, no offset
		float eff_time=(flow_on>0.5)?driver_time:0.0;
		vec2 center=vec2(flow_center_x,flow_center_y);
		vec2 radial=UVc-center;
		float radial_len=max(length(radial),0.0001);
		radial/=radial_len;

		vec2 grid_uv=UVd(UV);
		vec2 st=grid_uv*3.0;
		vec2 field_flow=travelling_whisp_field(st,eff_time);
		float field_amount=travelling_whisp_amount(st,eff_time);
		float driver_energy=smoothstep(0.015,0.18,abs(field_amount)*FIELD_STRENGTH);
		float outwardness=OUTWARDNESS;
		vec2 whispy=normalize(field_flow+radial*0.0001+vec2(0.0001));
		float shimmer=smoothstep(-0.12,0.16,field_amount);

		vec2 field_offset=(field_flow*FIELD_STRENGTH*COORD_NUDGE)/3.0;
		if(driver_mode>0.5&&driver_mode<1.5){
			vec2 legacy_uv=(grid_uv-DRIVER_CENTER/3.0+vec2(0.5))*LEGACY_SCALE+vec2(eff_time*LEGACY_SPEED,-eff_time*LEGACY_SPEED*0.73);
			float n1=fbm(legacy_uv);
			float n2=fbm(legacy_uv*1.71+vec2(9.2,-3.4));
			field_flow=vec2(n1-0.5,n2-0.5);
			field_amount=fbm(legacy_uv*2.4+eff_time*LEGACY_SPEED*0.37)-0.5;
			driver_energy=smoothstep(0.04,0.42,abs(field_amount));
			whispy=normalize(field_flow+radial*LEGACY_RADIAL+vec2(0.0001));
			shimmer=smoothstep(-0.22,0.22,field_amount);
			field_offset=field_flow*FIELD_STRENGTH*COORD_NUDGE*0.02;
			outwardness=clamp(LEGACY_RADIAL,0.0,1.0);
		}
		else if(driver_mode>1.5){
			float source_drive=prepared_luma(grid_uv);
			field_amount=generic_driver_amount(driver_mode,st,eff_time,source_drive)-0.5;
			field_flow=generic_driver_flow(driver_mode,st,eff_time,source_drive);
			driver_energy=smoothstep(0.02,0.38,abs(field_amount)*mix(1.0,2.0,DRIVER_DETAIL));
			whispy=normalize(field_flow+radial*(1.0-DRIVER_FLOW)*0.45+vec2(0.0001));
			shimmer=smoothstep(-0.30,0.30,field_amount);
			field_offset=field_flow*FIELD_STRENGTH*COORD_NUDGE*0.026;
			outwardness=clamp(1.0-DRIVER_FLOW,0.0,1.0);
		}
		if(flow_on<0.5){
			shimmer=1.0;
			driver_energy=1.0;
			field_offset=vec2(0.0);
		}
		field_offset*=wind_displace;
		vec2 displaced_uv=grid_uv+field_offset+whispy*(flow_strength*wind_displace*mix(0.18,0.72,driver_energy))*texel*flow_on;
		vec2 split_axis=normalize(whispy+vec2(-radial.y,radial.x)*(1.0-outwardness)*0.35);
		vec2 split_offset=split_axis*(flow_strength*split_separation)*texel;
		vec2 wind_dir=normalize(whispy*0.65+split_axis*0.35);
		float reach=max(wind_reach,0.0);

		float green_signal=color_signal(displaced_uv+split_offset,texel,wind_dir,reach)*mix(0.35,1.0,shimmer)*mix(0.35,1.0,driver_energy);
		float magenta_signal=color_signal(displaced_uv-split_offset,texel,wind_dir,reach)*mix(1.0,0.55,shimmer)*mix(0.35,1.0,driver_energy);
		green_signal=clamp(green_signal*signal_gain,0.0,1.0);
		magenta_signal=clamp(magenta_signal*signal_gain,0.0,1.0);
		green_signal=posterize_signal(green_signal);
		magenta_signal=posterize_signal(magenta_signal);

		float bayer_cell=dither_at(grid_uv);
		float soft=signal_softness;
		float green_threshold=1.0-clamp(green_signal*rgb_dither,0.0,1.0);
		float magenta_threshold=1.0-clamp(magenta_signal*rgb_dither,0.0,1.0);
		float green_on=smoothstep(green_threshold-soft,green_threshold+soft,bayer_cell);
		float magenta_on=smoothstep(magenta_threshold-soft,magenta_threshold+soft,bayer_cell);
		show=max(green_on,magenta_on);
		float choose_green=step(magenta_signal,green_signal);
		float balance_t=green_signal/max(green_signal+magenta_signal,0.001);
		float gradient_t=clamp(mix(balance_t,shimmer,0.55),0.0,1.0);
		gradient_t=clamp((gradient_t-0.5)*rgb_gradient_contrast+0.5+rgb_gradient_balance*0.5,0.0,1.0);
		vec3 two_color=mix(fringe_color_b.rgb,fringe_color_a.rgb,choose_green);
		vec3 gradient_color=hue_gradient(fringe_color_b.rgb,fringe_color_a.rgb,gradient_t);
		overlay_color=mix(two_color,gradient_color,rgb_gradient);
		show*=clamp(fx_fringe,0.0,1.0);
	}

	// ---- composite ----
	float fringe_alpha=show*clamp(fringe_bleed,0.0,1.0);
	if(base_mode<0.5){
		COLOR=vec4(col,max(src_alpha,fringe_alpha));
	}else{
		COLOR=vec4(col,1.0);
	}
	COLOR.rgb=mix(COLOR.rgb,overlay_color,clamp(show,0.0,1.0));
}
