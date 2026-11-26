// Tabla BRDF del split-sum (x = N.V, y = rugosidad): escala y sesgo de F0
// para el especular del cielo, con el Smith de Schlick (k = alfa / 2).
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    float nv = max(tc.x, 1e-3);
    float r = tc.y;
    float alfa = r * r;
    vec3 v = vec3(sqrt(1.0 - nv * nv), 0.0, nv);
    vec3 n = vec3(0.0, 0.0, 1.0);
    float k = alfa * 0.5;
    float a = 0.0;
    float b = 0.0;
    const float MUESTRAS = 256.0;
    for (float i = 0.0; i < MUESTRAS; i += 1.0) {
        vec2 xi = vec2(i / MUESTRAS, radicalInverso(i));
        vec3 h = mitadGGX(xi, n, alfa);
        vec3 l = 2.0 * dot(v, h) * h - v;
        float nl = max(l.z, 0.0);
        float nh = max(h.z, 0.0);
        float vh = max(dot(v, h), 0.0);
        if (nl > 0.0) {
            float g = (nv / (nv * (1.0 - k) + k)) * (nl / (nl * (1.0 - k) + k));
            float gv = g * vh / max(nh * nv, 1e-5);
            float fc = pow(1.0 - vh, 5.0);
            a += (1.0 - fc) * gv;
            b += fc * gv;
        }
    }
    return vec4(a / MUESTRAS, b / MUESTRAS, 0.0, 1.0);
}
