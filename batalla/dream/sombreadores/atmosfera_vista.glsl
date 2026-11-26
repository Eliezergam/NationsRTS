// Tabla de la vista del cielo (192 x 108): la radiancia que llega al ojo
// desde cada dirección, sumando el sol y la luna (siempre opuesta al sol),
// ya multiplicada por sus iluminancias. Se rehace cuando el sol se mueve.
uniform Image transmitancia;
uniform Image multiple;
uniform float radioOjo;
uniform float muSol;
uniform vec3 luzSol;   // iluminancia del sol en la cima de la atmósfera
uniform vec3 luzLuna;  // iluminancia de la luna en la cima (para el cielo)

vec3 dispersionDe(vec3 p, float rp, Medio m, vec3 luzDir, vec3 dir, vec3 iluminancia) {
    vec3 arriba = p / rp;
    float mu = dot(arriba, luzDir);
    vec3 alLuz = Texel(transmitancia, uvTransmitancia(rp, mu)).rgb;
    float sombra = interseccion(p, luzDir, RADIO_SUELO) > 0.0 ? 0.0 : 1.0;
    float c = dot(dir, luzDir);
    vec3 simple = alLuz * sombra * (m.rayleigh * faseRayleigh(c) + m.mie * faseMie(c));
    vec2 uvm = vec2(mu * 0.5 + 0.5, clamp((rp - RADIO_SUELO) / (RADIO_CIMA - RADIO_SUELO), 0.0, 1.0));
    vec3 varias = Texel(multiple, uvm).rgb * (m.rayleigh + vec3(m.mie));
    return (simple + varias) * iluminancia;
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    float cosCenit, cosRel;
    vistaDeUv(tc, radioOjo, cosCenit, cosRel);
    float senCenit = sqrt(max(0.0, 1.0 - cosCenit * cosCenit));
    vec3 d = vec3(senCenit * cosRel, cosCenit, senCenit * sqrt(max(0.0, 1.0 - cosRel * cosRel)));
    vec3 sol = vec3(sqrt(max(0.0, 1.0 - muSol * muSol)), muSol, 0.0);
    vec3 luna = -sol;
    vec3 o = vec3(0.0, radioOjo, 0.0);
    float tSuelo = interseccion(o, d, RADIO_SUELO);
    float tCima = interseccion(o, d, RADIO_CIMA);
    float largo = tSuelo > 0.0 ? tSuelo : tCima;
    if (largo <= 0.0) {
        return vec4(0.0, 0.0, 0.0, 1.0);
    }
    const float PASOS = 32.0;
    vec3 paso = vec3(1.0);
    vec3 l = vec3(0.0);
    float t0 = 0.0;
    for (float i = 0.0; i < PASOS; i += 1.0) {
        // Pasos más cortos cerca del ojo (la densidad cae con la altura).
        float t1 = largo * ((i + 1.0) / PASOS) * ((i + 1.0) / PASOS);
        float dt = t1 - t0;
        vec3 p = o + d * (t0 + dt * 0.3);
        t0 = t1;
        float rp = length(p);
        Medio m = medioEn(rp - RADIO_SUELO);
        vec3 tr = exp(-m.extincion * dt);
        vec3 s = dispersionDe(p, rp, m, sol, d, luzSol) + dispersionDe(p, rp, m, luna, d, luzLuna);
        vec3 ext = max(m.extincion, vec3(1e-7));
        l += paso * (s - s * tr) / ext;
        paso *= tr;
    }
    return vec4(l, 1.0);
}
