uniform Image canvas_depth;

uniform Image canvas_bloom;
uniform Image canvas_ao;

uniform Image canvas_alpha;
uniform Image canvas_distortion;

uniform Image canvas_exposure;

// NationsRTS: oclusión solo en la luz ambiente y sombras de contacto del sol
// (batalla/dream/oclusion.lua). `canvas_ao` es de media resolución: rojo, la
// oclusión; verde, la profundidad lineal de su píxel, para escalarla sin halos.
#ifdef AO_SPLIT
uniform Image canvas_ambient;
uniform vec2 ao_texel;          // 1 / tamaño de canvas_ao
uniform vec2 ao_depthParams;    // a, b: profundidad lineal = (z + a) * b
#endif
#ifdef BOUNCE
// NationsRTS: luz rebotada de media resolución (batalla/dream/rebote.lua):
// rgb, lo que se añade a la luz del cielo (relativo a ella); a, profundidad.
uniform Image canvas_bounce;
uniform vec2 bounce_texel;      // 1 / tamaño de canvas_bounce
#endif
#ifdef CONTACT_SHADOWS
uniform vec3 contact_light;     // dirección hacia el sol, en el espacio de la vista
uniform vec2 contact_tan;       // tangentes de medio campo de visión (x, y)
uniform float contact_length;   // largo del rayo (unidades de 3Dream)
uniform float contact_thickness;
uniform float contact_steps;
uniform float contact_strength;
#endif

uniform vec3 viewPos;

uniform float exposure;

#ifdef FOG_ENABLED
varying vec3 viewVec;
uniform mat4 transformInverse;
// NationsRTS: el rayo de cada píxel sale de la base de la cámara (el
// `viewVec` del vértice se calculaba sin dividir por w y cambiaba de signo al
// dibujar en un lienzo). Su componente hacia delante vale 1, así que
// rayo * profundidad es el punto de la escena.
uniform vec3 view_right;
uniform vec3 view_up;
uniform vec3 view_forward;
uniform vec2 view_tan;
#endif

#ifdef AUTO_EXPOSURE_ENABLED
varying float eyeAdaption;
#endif

#ifdef FXAA_ENABLED
#define FXAA_REDUCE_MIN (1.0 / 128.0)
#define FXAA_REDUCE_MUL (1.0 / 8.0)
#define FXAA_SPAN_MAX (8.0)

//combined and modified code from https://github.com/mattdesl/glsl-fxaa
vec4 fxaa(Image tex, vec2 tc) {
	vec2 inverseVP = 1.0 / love_ScreenSize.xy;
	vec2 v_rgbNW = (tc + vec2(-1.0, -1.0) * inverseVP);
	vec2 v_rgbNE = (tc + vec2(1.0, -1.0) * inverseVP);
	vec2 v_rgbSW = (tc + vec2(-1.0, 1.0) * inverseVP);
	vec2 v_rgbSE = (tc + vec2(1.0, 1.0) * inverseVP);
	
	vec4 texColor = Texel(tex, tc);
	
	vec3 rgbNW = Texel(tex, v_rgbNW).xyz;
	vec3 rgbNE = Texel(tex, v_rgbNE).xyz;
	vec3 rgbSW = Texel(tex, v_rgbSW).xyz;
	vec3 rgbSE = Texel(tex, v_rgbSE).xyz;
	vec3 rgbM = texColor.xyz;
	
	vec3 luma = vec3(0.299, 0.587, 0.114);
	float lumaNW = dot(rgbNW, luma);
	float lumaNE = dot(rgbNE, luma);
	float lumaSW = dot(rgbSW, luma);
	float lumaSE = dot(rgbSE, luma);
	float lumaM  = dot(rgbM,  luma);
	
	float lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
	float lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));
	
	mediump vec2 dir;
	dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
	dir.y =  ((lumaNW + lumaSW) - (lumaNE + lumaSE));
	
	float dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) * (0.25 * FXAA_REDUCE_MUL), FXAA_REDUCE_MIN);
	
	float rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
	dir = min(vec2(FXAA_SPAN_MAX, FXAA_SPAN_MAX), max(vec2(-FXAA_SPAN_MAX, -FXAA_SPAN_MAX), dir * rcpDirMin)) * inverseVP;
	
	vec3 rgbA = 0.5 * (
		Texel(tex, tc + dir * (1.0 / 3.0 - 0.5)).xyz +
		Texel(tex, tc + dir * (2.0 / 3.0 - 0.5)).xyz);
	
	vec3 rgbB = rgbA * 0.5 + 0.25 * (
		Texel(tex, tc + dir * -0.5).xyz +
		Texel(tex, tc + dir * 0.5).xyz);
	
	float lumaB = dot(rgbB, luma);
	if ((lumaB < lumaMin) || (lumaB > lumaMax)) {
		return vec4(rgbA, texColor.a);
	} else {
		return vec4(rgbB, texColor.a);
	}
}
#endif

#ifdef PIXEL
#ifdef AO_SPLIT
float linearDepth(float z) {
	return (z + ao_depthParams.x) * ao_depthParams.y;
}

// Oclusión de media resolución escalada con los cuatro vecinos, pesados por
// cuánto se parece su profundidad a la de este píxel (sin halo en los bordes).
float upsampleAO(vec2 tc, float d) {
	vec2 st = tc / ao_texel - 0.5;
	vec2 i = floor(st);
	vec2 f = st - i;
	vec2 base = (i + 0.5) * ao_texel;
	vec2 a = Texel(canvas_ao, base).rg;
	vec2 b = Texel(canvas_ao, base + vec2(ao_texel.x, 0.0)).rg;
	vec2 c = Texel(canvas_ao, base + vec2(0.0, ao_texel.y)).rg;
	vec2 e = Texel(canvas_ao, base + ao_texel).rg;
	float k = 1.0 / max(d * 0.02, 1e-4);
	vec4 w = vec4((1.0 - f.x) * (1.0 - f.y), f.x * (1.0 - f.y), (1.0 - f.x) * f.y, f.x * f.y);
	w *= 1.0 / (1.0 + k * abs(vec4(a.y, b.y, c.y, e.y) - d));
	float sum = w.x + w.y + w.z + w.w;
	if (sum < 1e-5) {
		return 1.0;
	}
	return dot(w, vec4(a.x, b.x, c.x, e.x)) / sum;
}
#endif

#ifdef BOUNCE
// Como upsampleAO, para el rebote.
vec3 upsampleBounce(vec2 tc, float d) {
	vec2 st = tc / bounce_texel - 0.5;
	vec2 i = floor(st);
	vec2 f = st - i;
	vec2 base = (i + 0.5) * bounce_texel;
	vec4 a = Texel(canvas_bounce, base);
	vec4 b = Texel(canvas_bounce, base + vec2(bounce_texel.x, 0.0));
	vec4 c = Texel(canvas_bounce, base + vec2(0.0, bounce_texel.y));
	vec4 e = Texel(canvas_bounce, base + bounce_texel);
	float k = 1.0 / max(d * 0.02, 1e-4);
	vec4 w = vec4((1.0 - f.x) * (1.0 - f.y), f.x * (1.0 - f.y), (1.0 - f.x) * f.y, f.x * f.y);
	w *= 1.0 / (1.0 + k * abs(vec4(a.a, b.a, c.a, e.a) - d));
	float sum = w.x + w.y + w.z + w.w;
	if (sum < 1e-5) {
		return vec3(0.0);
	}
	return (a.rgb * w.x + b.rgb * w.y + c.rgb * w.z + e.rgb * w.w) / sum;
}
#endif

#ifdef CONTACT_SHADOWS
vec3 viewPosition(vec2 uv, float d) {
	return vec3((uv.x * 2.0 - 1.0) * contact_tan.x * d, (1.0 - uv.y * 2.0) * contact_tan.y * d, -d);
}

// Sombra de contacto: un rayo corto hacia el sol en la profundidad de la
// pantalla. Si pasa por detrás de algo (más cerca de la cámara que el rayo,
// pero no más que `contact_thickness`), el píxel no ve el sol.
float contactShadow(vec2 tc, float d, vec2 sc) {
	if (d <= 0.0 || d > 60.0) {
		return 1.0;
	}
	vec3 p = viewPosition(tc, d);
	float ruido = fract(52.9829189 * fract(dot(sc, vec2(0.06711056, 0.00583715))));
	float paso = contact_length / contact_steps;
	// El rayo arranca un poco separado de la superficie, como el sesgo de la sombra.
	p += contact_light * paso * (0.5 + ruido);
	float sombra = 0.0;
	// Dos pasos seguidos tapados: las hojas de hierba (finas) no cuentan; un
	// vehículo o una roca, sí. Sin esto la hierba salía punteada.
	float seguidos = 0.0;
	for (float k = 0.0; k < contact_steps; k += 1.0) {
		vec3 q = p + contact_light * (paso * k);
		if (q.z >= -0.01) {
			break;
		}
		vec2 uv = vec2(q.x / (-q.z * contact_tan.x), q.y / (-q.z * contact_tan.y));
		uv = vec2(uv.x * 0.5 + 0.5, 0.5 - uv.y * 0.5);
		if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
			break;
		}
		float escena = linearDepth(Texel(canvas_depth, uv).r);
		float delante = -q.z - escena;
		if (delante > 0.002 * -q.z && delante < contact_thickness) {
			seguidos += 1.0;
			if (seguidos >= 2.0) {
				sombra = 1.0 - k / contact_steps;
				break;
			}
		} else {
			seguidos = 0.0;
		}
	}
	return 1.0 - sombra * contact_strength;
}
#endif

vec4 effect(vec4 _, Image canvas_color, vec2 tc, vec2 sc) {
	//distortion
	vec2 tcd = tc;
#ifdef REFRACTIONS_ENABLED
	vec2 distortion = Texel(canvas_distortion, tc).xy;
	tcd = tc + distortion;
	
	//border fade
#ifdef DISTORTION_MARGIN
	float marginFactor = DISTORTION_MARGIN;
	float fadeX = min(tcd.x * marginFactor, (1.0 - tcd.x) * marginFactor);
	float fadeY = min(tcd.y * marginFactor, (1.0 - tcd.y) * marginFactor);
	float fade = clamp(min(fadeX, fadeY), 0.0, 1.0);
	tcd = mix(tc, tcd, fade);
#endif
#endif
	
	//color
#ifdef FXAA_ENABLED
	vec4 color = fxaa(canvas_color, tcd);
#else
	vec4 color = Texel(canvas_color, tcd);
#endif
#ifdef GAMMA_CORRECTION
	color.rgb = pow(color.rgb, vec3(2.2));
#endif
	
	//ao
#ifdef AO_ENABLED
#ifdef AO_SPLIT
	{
		// NationsRTS: color = ambiente * oclusión + (sol y demás) * contacto.
		float dLin = linearDepth(Texel(canvas_depth, tcd).r);
		float ao = upsampleAO(tcd, dLin);
		vec3 amb = Texel(canvas_ambient, tcd).rgb;
#ifdef GAMMA_CORRECTION
		amb = pow(amb, vec3(2.2));
#endif
		vec3 direct = max(color.rgb - amb, vec3(0.0));
		float contact = 1.0;
#ifdef CONTACT_SHADOWS
		contact = contactShadow(tcd, dLin, sc);
#endif
		color.rgb = amb * ao + direct * contact;
#ifdef BOUNCE
		color.rgb += amb * upsampleBounce(tcd, dLin);
#endif
	}
#else
	float ao = Texel(canvas_ao, tcd).r;
	color.rgb *= ao;
#endif
#endif
	
	// NationsRTS: la niebla empaña lo opaco antes de poner encima lo
	// transparente, que ya trae la suya (paso alfa con FOG_ENABLED, shader.lua).
	// El resplandor se empaña igual que antes (con la niebla de lo opaco).
#ifdef FOG_ENABLED
	float depth = Texel(canvas_depth, tcd).r;
	vec3 rayo = view_forward + view_right * ((tcd.x * 2.0 - 1.0) * view_tan.x) + view_up * ((1.0 - tcd.y * 2.0) * view_tan.y);
	vec4 fogColor = getFog(depth, rayo, viewPos);
	color.rgb = mix(color.rgb, fogColor.rgb, fogColor.a);
#endif
	
	//simple alpha
#ifdef REFRACTIONS_ENABLED
#ifdef FXAA_ENABLED
	vec4 ca = fxaa(canvas_alpha, tc);
#else
	vec4 ca = Texel(canvas_alpha, tc);
#endif
#ifdef GAMMA_CORRECTION
	ca.rgb = pow(ca.rgb, vec3(2.2));
#endif
	
	color.rgb = color.rgb * (1.0 - ca.a) + ca.rgb;
	color.a = color.a * (1.0 - ca.a) + ca.a;
#endif
	
	//bloom
#ifdef BLOOM_ENABLED
	vec3 bloom = Texel(canvas_bloom, tcd).rgb;
#ifdef FOG_ENABLED
	bloom *= 1.0 - fogColor.a;
#endif
	color.rgb += bloom;
#endif
	
	//eye adaption
#ifdef AUTO_EXPOSURE_ENABLED
	color.rgb *= eyeAdaption;
#endif
	
	//exposure
#ifdef EXPOSURE_ENABLED
	color.rgb = vec3(1.0) - exp(-color.rgb * exposure);
#endif
	
#ifdef GAMMA_CORRECTION
	color.rgb = pow(color.rgb, vec3(1.0 / 2.2));
#endif
	
	return color;
}
#endif

#ifdef VERTEX
	vec4 position(mat4 transform_projection, vec4 VertexPosition) {
#ifdef AUTO_EXPOSURE_ENABLED
		eyeAdaption = Texel(canvas_exposure, vec2(0.5, 0.5)).r;
#endif
		vec4 pos = transform_projection * VertexPosition;
#ifdef FOG_ENABLED
		viewVec = (transformInverse * vec4(pos.x, - pos.y, 1.0, 1.0)).xyz;
#endif
		return pos;
	}
#endif