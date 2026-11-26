// Tabla de transmitancia (256 x 64): la luz que llega de la cima de la
// atmósfera a cada altura y dirección.
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    float r, mu;
    transmitanciaDeUv(tc, r, mu);
    vec3 o = vec3(0.0, r, 0.0);
    vec3 d = vec3(sqrt(max(0.0, 1.0 - mu * mu)), mu, 0.0);
    float largo = interseccion(o, d, RADIO_CIMA);
    vec3 profundidad = vec3(0.0);
    const float PASOS = 40.0;
    float dt = largo / PASOS;
    for (float i = 0.0; i < PASOS; i += 1.0) {
        vec3 p = o + d * ((i + 0.5) * dt);
        profundidad += medioEn(length(p) - RADIO_SUELO).extincion * dt;
    }
    return vec4(exp(-profundidad), 1.0);
}
