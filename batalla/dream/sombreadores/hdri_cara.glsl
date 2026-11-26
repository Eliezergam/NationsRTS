// Una cara del cubo de la luz del cielo desde el panorama: sin el sol (se
// recorta a `topePanorama`) y, por debajo del horizonte, el suelo iluminado.
uniform float cara;
uniform vec3 luzSuelo;
uniform vec3 cieloSuelo;   // irradiancia del cielo en el suelo (del panorama)
uniform vec3 albedoSuelo;

vec3 panoramaSinSol(vec3 d) {
    vec3 c = textureLod(panorama, uvPanorama(d), 3.0).rgb;
    float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
    c *= min(1.0, topePanorama / max(l, 1e-6));
    return c * escalaPanorama;
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec3 d = dirCubo(cara, tc) * vec3(1.0, 1.0, -1.0);
    vec3 l;
    if (d.y >= 0.0) {
        l = panoramaSinSol(d);
    } else {
        vec3 suelo = albedoSuelo / 3.14159265359 * (luzSuelo + cieloSuelo);
        vec3 horizonte = panoramaSinSol(normalize(vec3(d.x, 0.002, d.z)));
        l = mix(suelo, horizonte, exp(d.y * 25.0));
    }
    return vec4(l, 1.0);
}
