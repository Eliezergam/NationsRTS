// Especular prefiltrado por rugosidad (split-sum de Karis, como Unreal): cada
// nivel del cubo de reflejos es el cielo integrado con el lóbulo GGX de la
// rugosidad nivel / (niveles - 1), con N = V = R. Muestreo por importancia
// filtrado (el nivel de la fuente según la densidad de cada muestra).
uniform CubeImage fuente;
uniform float cara;
uniform float rugosidad;
uniform float ladoFuente;

const float MUESTRAS = 48.0;

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec3 n = dirCubo(cara, tc);
    if (rugosidad <= 0.0) {
        return vec4(codificar(textureLod(fuente, n, 0.0).rgb), 1.0);
    }
    float alfa = rugosidad * rugosidad;
    float a2 = alfa * alfa;
    float texel = 4.0 * 3.14159265359 / (6.0 * ladoFuente * ladoFuente);
    vec3 suma = vec3(0.0);
    float peso = 0.0;
    for (float i = 0.0; i < MUESTRAS; i += 1.0) {
        vec2 xi = vec2(i / MUESTRAS, radicalInverso(i));
        vec3 h = mitadGGX(xi, n, alfa);
        float nh = max(dot(n, h), 0.0);
        vec3 l = 2.0 * nh * h - n;
        float nl = dot(n, l);
        if (nl > 0.0) {
            float den = nh * nh * (a2 - 1.0) + 1.0;
            float D = a2 / (3.14159265359 * den * den);
            float pdf = D * 0.25;
            float muestra = 1.0 / (MUESTRAS * pdf + 1e-4);
            float nivel = max(0.5 * log2(muestra / texel) + 1.0, 0.0);
            suma += textureLod(fuente, l, nivel).rgb * nl;
            peso += nl;
        }
    }
    return vec4(codificar(suma / max(peso, 1e-4)), 1.0);
}
