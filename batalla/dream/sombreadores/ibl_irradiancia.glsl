// Irradiancia difusa: para cada normal, la media del cielo pesada por el
// coseno (E / pi), con todos los texeles del nivel de 8 x 8 por cara de la
// fuente, cada uno con su ángulo sólido.
uniform CubeImage fuente;
uniform float cara;
uniform float nivel;
uniform float escala; // refuerzo de la luz difusa (de noche, para jugar)

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec3 n = dirCubo(cara, tc);
    const float LADO = 8.0;
    vec3 suma = vec3(0.0);
    float total = 0.0;
    for (float f = 0.0; f < 6.0; f += 1.0) {
        for (float y = 0.0; y < LADO; y += 1.0) {
            for (float x = 0.0; x < LADO; x += 1.0) {
                vec2 uv = (vec2(x, y) + 0.5) / LADO;
                vec2 st = uv * 2.0 - 1.0;
                float angulo = 4.0 / (LADO * LADO) / pow(1.0 + dot(st, st), 1.5);
                vec3 l = dirCubo(f, uv);
                float c = dot(n, l);
                total += angulo;
                if (c > 0.0) {
                    suma += textureLod(fuente, l, nivel).rgb * c * angulo;
                }
            }
        }
    }
    // E = suma; se guarda E / pi. (total ~ 4 pi: corrige el error de discretizar.)
    vec3 e = suma * (4.0 * 3.14159265359 / total);
    return vec4(codificar(e * escala / 3.14159265359), 1.0);
}
