// Oclusión ambiental de horizontes (GTAO, Jimenez 2016; la de XeGTAO y la de
// Unreal), a media resolución. Por píxel, `cortes` planos alrededor de la
// vista; en cada uno, el horizonte más alto a cada lado dentro de `radio` y la
// integral del coseno visible con la normal proyectada. Salida: rojo = luz
// del cielo visible (1 = nada la tapa); verde = profundidad lineal del píxel.
uniform Image profundidad;     // la de 3Dream, a resolución completa
uniform vec2 tamCompleto;
uniform vec2 tanVista;         // tangentes de medio campo (x, y)
uniform vec2 profParams;       // lineal = (z + a) * b
uniform float radio;           // unidades de 3Dream
uniform float radioMaxPx;
uniform float cortes;
uniform float pasos;
uniform float potencia;
uniform float distanciaMax;

const float PI = 3.14159265359;

float lineal(vec2 uv) {
    return (Texel(profundidad, uv).r + profParams.x) * profParams.y;
}

vec3 posVista(vec2 uv) {
    float d = lineal(uv);
    return vec3((uv.x * 2.0 - 1.0) * tanVista.x * d, (1.0 - uv.y * 2.0) * tanVista.y * d, -d);
}

float acosRapido(float x) {
    float a = abs(x);
    float r = (-0.156583 * a + PI * 0.5) * sqrt(max(1.0 - a, 0.0));
    return x >= 0.0 ? r : PI - r;
}

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec3 p = posVista(tc);
    float d = -p.z;
    if (d <= 0.0 || d > distanciaMax) {
        return vec4(1.0, d, 0.0, 1.0);
    }
    vec2 px = 1.0 / tamCompleto;
    vec3 pr = posVista(tc + vec2(px.x, 0.0));
    vec3 pl = posVista(tc - vec2(px.x, 0.0));
    vec3 pd = posVista(tc + vec2(0.0, px.y));
    vec3 pu = posVista(tc - vec2(0.0, px.y));
    vec3 dx = abs(pr.z - p.z) < abs(p.z - pl.z) ? pr - p : p - pl;
    vec3 dy = abs(pd.z - p.z) < abs(p.z - pu.z) ? pd - p : p - pu;
    vec3 n = normalize(cross(dx, dy));
    vec3 v = normalize(-p);
    if (dot(n, v) < 0.0) {
        n = -n;
    }
    // Ruido de 4 x 4 (se quita con el filtro de 4 x 4): giro de los cortes y
    // desplazamiento de los pasos.
    vec2 celda = mod(floor(sc), 4.0);
    float ruidoA = (celda.x + celda.y * 4.0 + 0.5) / 16.0;
    float ruidoB = fract(52.9829189 * fract(dot(sc, vec2(0.06711056, 0.00583715))));
    float radioPx = min(radio * tamCompleto.y * 0.5 / (d * tanVista.y), radioMaxPx);
    if (radioPx < 1.0) {
        return vec4(1.0, d, 0.0, 1.0);
    }
    float rangoCaida = 0.615 * radio;
    float caidaMul = -1.0 / rangoCaida;
    float caidaSuma = (radio - rangoCaida) / rangoCaida + 1.0;
    float visible = 0.0;
    for (float c = 0.0; c < cortes; c += 1.0) {
        float phi = (c + ruidoA) / cortes * PI;
        vec2 omega = vec2(cos(phi), sin(phi));
        vec3 dir = vec3(omega.x, -omega.y, 0.0);
        vec3 orto = dir - dot(dir, v) * v;
        vec3 eje = normalize(cross(orto, v));
        vec3 nProy = n - eje * dot(n, eje);
        float largoN = length(nProy);
        float cosN = clamp(dot(nProy, v) / max(largoN, 1e-5), 0.0, 1.0);
        float ang = sign(dot(orto, nProy)) * acosRapido(cosN);
        float bajo0 = cos(ang + PI * 0.5);
        float bajo1 = cos(ang - PI * 0.5);
        float h0 = bajo0;
        float h1 = bajo1;
        for (float k = 0.0; k < pasos; k += 1.0) {
            float s = (k + ruidoB) / pasos;
            s = s * s;
            vec2 desp = omega * max(s * radioPx, k + 1.0) * px;
            vec3 a = posVista(tc + desp) - p;
            vec3 b = posVista(tc - desp) - p;
            float la = length(a);
            float lb = length(b);
            float ca = dot(a, v) / max(la, 1e-5);
            float cb = dot(b, v) / max(lb, 1e-5);
            ca = mix(bajo0, ca, clamp(la * caidaMul + caidaSuma, 0.0, 1.0));
            cb = mix(bajo1, cb, clamp(lb * caidaMul + caidaSuma, 0.0, 1.0));
            h0 = max(h0, ca);
            h1 = max(h1, cb);
        }
        float a0 = -acosRapido(h1);
        float a1 = acosRapido(h0);
        a0 = ang + clamp(a0 - ang, -PI * 0.5, PI * 0.5);
        a1 = ang + clamp(a1 - ang, -PI * 0.5, PI * 0.5);
        float arco0 = (cosN + 2.0 * a0 * sin(ang) - cos(2.0 * a0 - ang)) * 0.25;
        float arco1 = (cosN + 2.0 * a1 * sin(ang) - cos(2.0 * a1 - ang)) * 0.25;
        visible += largoN * (arco0 + arco1);
    }
    visible = clamp(visible / cortes, 0.0, 1.0);
    // Se apaga a lo lejos (sin escalón).
    visible = mix(visible, 1.0, smoothstep(distanciaMax * 0.7, distanciaMax, d));
    return vec4(pow(visible, potencia), d, 0.0, 1.0);
}
