// Tabla de dispersión múltiple (32 x 32) de Hillaire: lo que aportan todas
// las dispersiones de orden 2 o más, por altura y altura del sol, para una
// luz de iluminancia 1. Se integra en 64 direcciones de la esfera.
uniform Image transmitancia;
uniform vec3 albedoSuelo;

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    float muSol = tc.x * 2.0 - 1.0;
    float r = RADIO_SUELO + clamp(tc.y, 0.002, 0.999) * (RADIO_CIMA - RADIO_SUELO);
    vec3 o = vec3(0.0, r, 0.0);
    vec3 sol = vec3(sqrt(max(0.0, 1.0 - muSol * muSol)), muSol, 0.0);
    const float LADO = 8.0;
    const float PASOS = 20.0;
    const float FASE = 1.0 / (4.0 * PI);
    vec3 luz = vec3(0.0);
    vec3 multiple = vec3(0.0);
    for (float a = 0.0; a < LADO; a += 1.0) {
        for (float b = 0.0; b < LADO; b += 1.0) {
            float theta = 2.0 * PI * (a + 0.5) / LADO;
            float cosPhi = 1.0 - 2.0 * (b + 0.5) / LADO;
            float sinPhi = sqrt(max(0.0, 1.0 - cosPhi * cosPhi));
            vec3 d = vec3(cos(theta) * sinPhi, cosPhi, sin(theta) * sinPhi);
            float tSuelo = interseccion(o, d, RADIO_SUELO);
            float tCima = interseccion(o, d, RADIO_CIMA);
            float largo = tSuelo > 0.0 ? tSuelo : tCima;
            float dt = largo / PASOS;
            vec3 paso = vec3(1.0);
            vec3 l = vec3(0.0);
            vec3 f = vec3(0.0);
            for (float i = 0.0; i < PASOS; i += 1.0) {
                vec3 p = o + d * ((i + 0.3) * dt);
                float rp = length(p);
                Medio m = medioEn(rp - RADIO_SUELO);
                vec3 disp = m.rayleigh + vec3(m.mie);
                vec3 tr = exp(-m.extincion * dt);
                vec3 arriba = p / rp;
                float mu = dot(arriba, sol);
                vec3 alSol = Texel(transmitancia, uvTransmitancia(rp, mu)).rgb;
                float sombra = interseccion(p, sol, RADIO_SUELO) > 0.0 ? 0.0 : 1.0;
                vec3 s = alSol * sombra * disp * FASE;
                vec3 ext = max(m.extincion, vec3(1e-7));
                l += paso * (s - s * tr) / ext;
                f += paso * (disp - disp * tr) / ext;
                paso *= tr;
            }
            if (tSuelo > 0.0) {
                vec3 p = o + d * tSuelo;
                vec3 arriba = normalize(p);
                float mu = dot(arriba, sol);
                vec3 alSol = Texel(transmitancia, uvTransmitancia(RADIO_SUELO, mu)).rgb;
                l += paso * alSol * max(mu, 0.0) * albedoSuelo / PI;
            }
            luz += l;
            multiple += f;
        }
    }
    float n = LADO * LADO;
    luz /= n;
    multiple /= n;
    return vec4(luz / (1.0 - multiple), 1.0);
}
