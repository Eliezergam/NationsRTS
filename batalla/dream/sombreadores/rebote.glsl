// Luz rebotada de pantalla (Valeria; Fase 2 de PLAN-RENDER-UE.md), un rebote
// como el de Lumen a corta distancia: el costado al sol de un tanque aclara y
// tiñe la sombra que tiene al lado, y la hierba iluminada, el suelo de junto.
//
// Es la misma integral de horizontes que la GTAO (gtao.glsl), a media
// resolución: en cada corte, los pasos avanzan desde el píxel y, cada vez que
// un punto sube el horizonte, tapa una franja del cielo y en su lugar llega su
// propia luz (el color de la escena en ese punto, que ya lleva el sol, el
// cielo y lo que emita). La franja pesa lo que el coseno de la normal en ella,
// como la oclusión, así que la suma es la irradiancia rebotada E / pi.
//
// Rebotes múltiples (como Lumen): la luz de cada punto se lee de la imagen
// del cuadro anterior (`historia`, la del AA temporal, que ya lleva su
// rebote), reproyectada con la cámara anterior como en taa.glsl. Si su
// profundidad no es la del punto (estaba tapado, o es algo que se mueve por
// su cuenta) o cae fuera, se usa la escena de este cuadro (un rebote).
//
// Salida: rgb = (E / pi rebotada) / (E / pi del cielo para esta normal), es
// decir, cuánto hay que añadir a la luz del cielo del píxel (la imagen final
// la multiplica por su luz ambiente, que ya es albedo * cielo: queda
// albedo * E / pi). Alfa: profundidad lineal, para escalarla sin halos.
uniform Image profundidad;     // la de 3Dream, a resolución completa
uniform Image color;           // la escena antes de la imagen final (gamma 2,2)
uniform samplerCube irradiancia; // E / pi del cielo por normal (gamma 2,2; ibl.lua)
uniform vec2 tamCompleto;
uniform vec2 tanVista;
uniform vec2 profParams;
uniform vec3 vistaDer;         // ejes de la cámara en el mundo de 3Dream
uniform vec3 vistaArr;
uniform vec3 vistaFre;
uniform float radio;           // unidades de 3Dream
uniform float radioMaxPx;
uniform float cortes;
uniform float pasos;
uniform float distanciaMax;
uniform float intensidad;
uniform float topeRelativo;
uniform Image historia;        // el cuadro anterior (gamma 2,2; alfa = profundidad, negativa si es móvil)
uniform float usarHistoria;    // 1: rebotes múltiples
uniform vec3 camPos;           // posición de la cámara de ahora (mundo de 3Dream)
uniform vec3 antPos;           // base de la cámara del cuadro anterior
uniform vec3 antDer;
uniform vec3 antArr;
uniform vec3 antFre;
uniform vec2 antTan;
uniform vec2 toleranciaProf;   // relativa y absoluta (unidades de 3Dream)

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

// Parte del coseno visible entre el eje del corte y el ángulo `a` (la de
// la GTAO): la franja entre dos horizontes es la diferencia.
float arco(float a, float ang, float cosN) {
    return (cosN + 2.0 * a * sin(ang) - cos(2.0 * a - ang)) * 0.25;
}

// Luz que sale del punto `q` (posición en la vista) que se ve en `uv`.
vec3 luzEn(vec2 uv, vec3 q) {
    if (usarHistoria > 0.5) {
        vec3 punto = camPos + vistaDer * q.x + vistaArr * q.y - vistaFre * q.z;
        vec3 v = punto - antPos;
        float z = dot(v, antFre);
        vec2 uvAnt = vec2(
            0.5 + 0.5 * dot(v, antDer) / (z * antTan.x),
            0.5 - 0.5 * dot(v, antArr) / (z * antTan.y)
        );
        if (z > 0.0 && uvAnt.x > 0.0 && uvAnt.y > 0.0 && uvAnt.x < 1.0 && uvAnt.y < 1.0) {
            vec4 h = Texel(historia, uvAnt);
            if (h.a > 0.0 && abs(h.a - z) < toleranciaProf.x * z + toleranciaProf.y) {
                return pow(max(h.rgb, vec3(0.0)), vec3(2.2));
            }
        }
    }
    return pow(max(Texel(color, uv).rgb, vec3(0.0)), vec3(2.2));
}

vec4 effect(vec4 _c, Image tex, vec2 tc, vec2 sc) {
    vec3 p = posVista(tc);
    float d = -p.z;
    if (d <= 0.0 || d > distanciaMax) {
        return vec4(0.0, 0.0, 0.0, d);
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
    // El mismo ruido de 4 x 4 que la GTAO (lo quita el filtro de 4 x 4).
    vec2 celda = mod(floor(sc), 4.0);
    float ruidoA = (celda.x + celda.y * 4.0 + 0.5) / 16.0;
    float ruidoB = fract(52.9829189 * fract(dot(sc, vec2(0.06711056, 0.00583715))));
    float radioPx = min(radio * tamCompleto.y * 0.5 / (d * tanVista.y), radioMaxPx);
    if (radioPx < 1.0) {
        return vec4(0.0, 0.0, 0.0, d);
    }
    float rangoCaida = 0.615 * radio;
    float caidaMul = -1.0 / rangoCaida;
    float caidaSuma = (radio - rangoCaida) / rangoCaida + 1.0;
    vec3 suma = vec3(0.0);
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
        float h0 = cos(ang + PI * 0.5);
        float h1 = cos(ang - PI * 0.5);
        // Ángulos de los horizontes: lado 0 positivo, lado 1 negativo.
        float a0 = ang + PI * 0.5;
        float a1 = ang - PI * 0.5;
        vec3 corte = vec3(0.0);
        for (float k = 0.0; k < pasos; k += 1.0) {
            float s = (k + ruidoB) / pasos;
            s = s * s;
            vec2 desp = omega * max(s * radioPx, k + 1.0) * px;
            vec2 uvA = tc + desp;
            vec2 uvB = tc - desp;
            vec3 a = posVista(uvA) - p;
            vec3 b = posVista(uvB) - p;
            float la = length(a);
            float lb = length(b);
            float pesoA = clamp(la * caidaMul + caidaSuma, 0.0, 1.0);
            float pesoB = clamp(lb * caidaMul + caidaSuma, 0.0, 1.0);
            float ca = dot(a, v) / max(la, 1e-5);
            float cb = dot(b, v) / max(lb, 1e-5);
            if (pesoA > 0.0 && ca > h0) {
                float nuevo = clamp(acosRapido(ca), ang - PI * 0.5, ang + PI * 0.5);
                corte += luzEn(uvA, a + p) * (pesoA * max(arco(a0, ang, cosN) - arco(nuevo, ang, cosN), 0.0));
                h0 = ca;
                a0 = nuevo;
            }
            if (pesoB > 0.0 && cb > h1) {
                float nuevo = clamp(-acosRapido(cb), ang - PI * 0.5, ang + PI * 0.5);
                corte += luzEn(uvB, b + p) * (pesoB * max(arco(a1, ang, cosN) - arco(nuevo, ang, cosN), 0.0));
                h1 = cb;
                a1 = nuevo;
            }
        }
        suma += corte * largoN;
    }
    vec3 rebote = suma / cortes * intensidad;
    // La luz del cielo que recibe esta normal (en el mundo, como el PBR).
    vec3 nMundo = vistaDer * n.x + vistaArr * n.y - vistaFre * n.z;
    vec3 cielo = pow(max(textureLod(irradiancia, nMundo * vec3(1.0, 1.0, -1.0), 0.0).rgb, vec3(0.0)), vec3(2.2));
    vec3 relativo = min(rebote / max(cielo, vec3(1e-4)), vec3(topeRelativo));
    // Se apaga a lo lejos (sin escalón).
    relativo *= 1.0 - smoothstep(distanciaMax * 0.7, distanciaMax, d);
    return vec4(relativo, d);
}
