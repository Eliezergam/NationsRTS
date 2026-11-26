// Filtro de la GTAO: media de 4 x 4 texeles (lo que repite el ruido) pesada
// por lo que se parece la profundidad, para no mezclar el primer plano con el
// fondo. Se lee en el centro de cada texel (sin mezclar profundidades).
uniform vec2 texel;

vec4 effect(vec4 color, Image ao, vec2 tc, vec2 sc) {
    vec2 centro = Texel(ao, tc).rg;
    float d = centro.y;
    float k = 1.0 / max(d * 0.03, 1e-4);
    float suma = 0.0;
    float peso = 0.0;
    for (float y = -2.0; y < 2.0; y += 1.0) {
        for (float x = -2.0; x < 2.0; x += 1.0) {
            vec2 m = Texel(ao, tc + vec2(x, y) * texel).rg;
            float w = 1.0 / (1.0 + k * abs(m.y - d));
            suma += m.x * w;
            peso += w;
        }
    }
    return vec4(suma / peso, d, 0.0, 1.0);
}
