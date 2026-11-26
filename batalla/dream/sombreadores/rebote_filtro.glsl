// Filtro de la luz rebotada (rebote.glsl): media de 4 x 4 texeles (lo que
// repite el ruido) pesada por lo que se parece la profundidad, como el de la
// GTAO (gtao_filtro.glsl). Alfa: profundidad lineal.
uniform vec2 texel;

vec4 effect(vec4 color, Image rebote, vec2 tc, vec2 sc) {
    vec4 centro = Texel(rebote, tc);
    float d = centro.a;
    float k = 1.0 / max(d * 0.03, 1e-4);
    vec3 suma = vec3(0.0);
    float peso = 0.0;
    for (float y = -2.0; y < 2.0; y += 1.0) {
        for (float x = -2.0; x < 2.0; x += 1.0) {
            vec4 m = Texel(rebote, tc + vec2(x, y) * texel);
            float w = 1.0 / (1.0 + k * abs(m.a - d));
            suma += m.rgb * w;
            peso += w;
        }
    }
    return vec4(suma / peso, d);
}
