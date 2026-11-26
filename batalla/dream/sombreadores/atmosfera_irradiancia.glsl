// Irradiancia del cielo sobre el suelo horizontal (1 x 1, lineal): la
// radiancia de la tabla integrada en el hemisferio de arriba por el coseno.
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    const float NT = 16.0;
    const float NP = 32.0;
    vec3 e = vec3(0.0);
    float dt = 0.5 * PI / NT;
    float dp = 2.0 * PI / NP;
    for (float i = 0.0; i < NT; i += 1.0) {
        float t = (i + 0.5) * dt;
        for (float j = 0.0; j < NP; j += 1.0) {
            float p = (j + 0.5) * dp;
            vec3 d = vec3(sin(t) * cos(p), cos(t), sin(t) * sin(p));
            e += cieloEn(d) * cos(t) * sin(t) * dt * dp;
        }
    }
    return vec4(e, 1.0);
}
