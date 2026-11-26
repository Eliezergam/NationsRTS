// Una cara del cubo del cielo para la luz ambiente (lineal): la atmósfera sin
// el disco del sol (su luz la pone la luz directa, como el SkyLight de Unreal)
// y, por debajo del horizonte, el suelo iluminado por el sol y el cielo, que
// se funde con el horizonte a lo lejos.
uniform float cara;
uniform Image irradianciaCielo; // 1 x 1: irradiancia del cielo en el suelo
uniform vec3 luzSuelo;          // iluminancia directa (sol y luna) en el suelo
uniform vec3 albedoSuelo;
uniform float refuerzo;         // más luz del cielo de noche (para jugar)

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec3 d = dirCubo(cara, tc) * vec3(1.0, 1.0, -1.0);
    vec3 l;
    if (d.y >= 0.0) {
        l = cieloEn(d);
    } else {
        vec3 e = luzSuelo + Texel(irradianciaCielo, vec2(0.5)).rgb;
        vec3 suelo = albedoSuelo / 3.14159265359 * e;
        vec3 horizonte = cieloEn(normalize(vec3(d.x, 0.002, d.z)));
        l = mix(suelo, horizonte, exp(d.y * 25.0));
    }
    return vec4(l * refuerzo, 1.0);
}
