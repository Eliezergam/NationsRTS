#ifdef PIXEL
uniform float fog_density;
uniform float fog_scatter;
uniform vec3 fog_color;
uniform vec3 fog_sun;
uniform vec3 fog_sunColor;
uniform float fog_max;
uniform float fog_min;
// NationsRTS: distancia sin niebla delante del ojo (setFogStart).
uniform float fog_start;
// NationsRTS: huecos que abren los disparos y explosiones (dream.fog_holes):
// xyz el centro en el mundo, w el radio; fog_holesStrength, cuánto aire
// limpian (0 = nada, 1 = todo dentro de la esfera).
#define FOG_HOLES 8
uniform vec4 fog_holes[FOG_HOLES];
uniform float fog_holesStrength[FOG_HOLES];

// Parte del tramo a..b que va dentro de los huecos, pesada por su fuerza.
float fogHoles(vec3 a, vec3 b) {
	vec3 d = b - a;
	float largo = length(d);
	if (largo < 1e-4) {
		return 0.0;
	}
	d /= largo;
	float limpio = 0.0;
	for (int i = 0; i < FOG_HOLES; i++) {
		float s = fog_holesStrength[i];
		if (s <= 0.0) {
			continue;
		}
		vec3 oc = a - fog_holes[i].xyz;
		float r = fog_holes[i].w;
		float pb = dot(oc, d);
		float c = dot(oc, oc) - r * r;
		float disc = pb * pb - c;
		if (disc <= 0.0) {
			continue;
		}
		float h = sqrt(disc);
		float t0 = clamp(-pb - h, 0.0, largo);
		float t1 = clamp(-pb + h, 0.0, largo);
		// La cuerda pesa más cuanto más cerca del centro pasa (borde suave).
		// disc = r² - (distancia del centro a la recta)².
		float centro = clamp(disc / (r * r), 0.0, 1.0);
		limpio += s * (t1 - t0) * (0.4 + 0.6 * centro);
	}
	return clamp(limpio / largo, 0.0, 1.0);
}
#ifdef FOG_SKY
// NationsRTS: color de la niebla = el del cielo justo encima del horizonte en
// el rumbo de la mirada (dream:setFogSky; franja de rumbos de 0 a 2 pi).
uniform Image fog_sky;
#endif

vec4 getFog(float depth, vec3 viewVec, vec3 viewPos) {
	// NationsRTS: solo cuenta el tramo más allá de fog_start.
	float fog_part = max(depth - fog_start, 0.0) / max(depth, 0.0001);
	float fog_clear = fogHoles(viewPos, viewPos + viewVec * depth);
	if (fog_max > fog_min) {
		vec3 vec = viewVec * depth;
		vec3 stepVec = vec / vec.y;

		//ray
		vec3 pos_near = viewPos;
		vec3 pos_far = viewPos + vec;

		//find entry/exit heights
		float height_near = clamp(pos_near.y, fog_min, fog_max);
		float height_far = clamp(pos_far.y, fog_min, fog_max);

		//find points
		pos_near += stepVec * (height_near - pos_near.y);
		pos_far += stepVec * (height_far - pos_far.y);

		//get average density
		float heightDiff = fog_max - fog_min;
		float nearDensity = 1.0 - (height_near - fog_min) / heightDiff;
		float farDensity = 1.0 - (height_far - fog_min) / heightDiff;
		depth = distance(pos_far, pos_near) * (farDensity + nearDensity) * 0.5;
	}

	depth *= fog_part * (1.0 - fog_clear);

	//finish fog
	float fog = 1.0 - exp(-depth * fog_density);
#ifdef FOG_SKY
	vec3 rumbo = normalize(viewVec);
	float u = atan(rumbo.z, rumbo.x) * 0.15915494 + 0.5;
	return vec4(Texel(fog_sky, vec2(u, 0.5)).rgb, fog);
#endif
	if (fog_scatter > 0.0) {
		float fog_sunStrength = max(dot(fog_sun, normalize(viewVec)), 0.0);
		vec3 fogColor = fog_color + fog_sunColor * pow(fog_sunStrength, 8.0) * fog_scatter;
		return vec4(fogColor, fog);
	} else {
		return vec4(fog_color, fog);
	}
}
#endif