// Franja del horizonte para la niebla (64 x 1, lineal): el cielo entre 1 y 5
// grados de altura en cada rumbo (x = atan(z, x) / 2pi + 0,5, en el mundo).
uniform CubeImage fuente;

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    float phi = (tc.x - 0.5) * 2.0 * 3.14159265359;
    vec3 suma = vec3(0.0);
    for (float k = 0.0; k < 3.0; k += 1.0) {
        float e = radians(1.0 + 2.0 * k);
        vec3 d = vec3(cos(phi) * cos(e), sin(e), sin(phi) * cos(e));
        suma += textureLod(fuente, d * vec3(1.0, 1.0, -1.0), 2.0).rgb;
    }
    return vec4(suma / 3.0, 1.0);
}
