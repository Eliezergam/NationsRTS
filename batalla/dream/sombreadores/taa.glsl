// AA temporal de la batalla (Valeria), como el TAA de Unreal (Karis 2014) con
// la reconstrucción de TSR: cada cuadro se dibuja desplazado un subpíxel
// distinto (secuencia de Halton) y aquí se junta con la historia.
//
// 1. Reconstrucción: el color de este píxel sale de sus 3 x 3 vecinos pesados
//    por la distancia entre el centro del píxel y el punto que vio cada vecino
//    (el desplazamiento del cuadro se conoce): un filtro gaussiano estrecho.
// 2. Reproyección: con la profundidad más cercana de la cruz de vecinos (los
//    bordes de lo que está delante no dejan estela) se reconstruye el punto
//    del mundo y se proyecta con la cámara del cuadro anterior.
// 3. La historia se lee con Catmull-Rom (5 lecturas bilineales), que no
//    emborrona al moverse, y se recorta (clip, no clamp) a la caja de color de
//    los vecinos (media ± desviación en YCoCg): lo que ya no está, se va.
// 4. Se mezcla en un espacio con la curva reversible de Karis (c / (1 + luma)):
//    los píxeles muy brillantes no parpadean.
//
// Lo que se mueve por su cuenta: 3Dream escribe en `movilTex` (rgba16f)
// cuánto se movió el punto de cada píxel desde el cuadro anterior, en el
// mundo de 3Dream: los vectores de movimiento por objeto de Unreal. Los
// vehículos articulados (el lanzamisiles; batalla/dream/piezas_lote.lua) lo
// saben por la matriz anterior de cada pieza, y en ellos la historia se
// reproyecta como la del suelo: la chapa queda quieta. Lo que no sabe cuánto
// se movió (`mesh.movil`: tanques, soldados y misiles) escribe 10000 en rojo;
// donde lo hay, o lo había en la historia, pesa más el cuadro nuevo
// (`mezclaObjeto`), como la «AA reactiva» de Unreal. Además, la historia
// guarda en alfa la profundidad de cada píxel y, si la del punto
// reproyectado no cabe en el rango de profundidades de los 3 x 3 vecinos de
// ahora (movido lo que se movió la cámara), es otra superficie (un soldado
// que pasó, o el suelo que tapaba) y se usa el cuadro nuevo. Con el rango de
// los vecinos, la hierba fina (hoja y suelo alternando) no se descarta.
//
// El color llega y sale con la gamma de 3Dream (x^(1/2,2)), como lo espera
// batalla/dream/tono.lua.
uniform Image historia;
uniform Image profundidad;     // lineal = (z + a) * b, de 3Dream
uniform Image movilTex;        // movimiento del punto desde el cuadro anterior; 10000 en rojo: móvil sin vector
uniform vec2 texel;            // 1 / tamaño
uniform vec2 jitter;           // px del desplazamiento de este cuadro (x derecha, y abajo)
uniform vec2 profParams;       // a, b
uniform vec3 camPos;
uniform vec3 camDer;
uniform vec3 camArr;
uniform vec3 camFre;
uniform vec2 camTan;
uniform vec3 antPos;
uniform vec3 antDer;
uniform vec3 antArr;
uniform vec3 antFre;
uniform vec2 antTan;
uniform float mezcla;          // peso del cuadro nuevo con la historia quieta
uniform float mezclaMovil;     // peso del cuadro nuevo con mucho movimiento
uniform vec2 rampaMovil;       // px por cuadro en que se pasa de una mezcla a otra
uniform float reiniciar;       // 1: sin historia (corte de cámara)
uniform float exposicion;      // para la curva de Karis (aprox. la de tono.lua)
uniform float filtro;          // k del gaussiano exp(-k d^2) de la reconstrucción
uniform float caja;            // desviaciones de la caja de recorte
uniform float mezclaObjeto;    // peso del cuadro nuevo sobre lo que se mueve
uniform vec2 toleranciaProf;   // relativa y absoluta (unidades) del rango de profundidad

vec3 lineal(vec3 c) {
    return pow(max(c, vec3(0.0)), vec3(2.2));
}

float luma(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

// Curva reversible de Karis y paso a YCoCg.
vec3 aEspacio(vec3 gammaRGB) {
    vec3 c = lineal(gammaRGB) * exposicion;
    c = c / (1.0 + luma(c));
    return vec3(
        0.25 * c.r + 0.5 * c.g + 0.25 * c.b,
        0.5 * c.r - 0.5 * c.b,
        -0.25 * c.r + 0.5 * c.g - 0.25 * c.b
    );
}

vec3 deEspacio(vec3 y) {
    vec3 c = vec3(y.x + y.y - y.z, y.x + y.z, y.x - y.y - y.z);
    c = max(c, vec3(0.0));
    c = c / max(1.0 - luma(c), 1e-4);
    return pow(c / exposicion, vec3(1.0 / 2.2));
}

float distancia(vec2 uv) {
    return (Texel(profundidad, uv).r + profParams.x) * profParams.y;
}

float distanciaYMovil(vec2 uv, out float movil) {
    movil = Texel(movilTex, uv).r > 5000.0 ? 1.0 : 0.0;
    return distancia(uv);
}

// Cuánto se movió por su cuenta el punto de este píxel (cero si no se sabe).
vec3 movimientoPropio(vec2 uv) {
    vec3 d = Texel(movilTex, uv).rgb;
    return d.r > 5000.0 ? vec3(0.0) : d;
}

// Historia con Catmull-Rom en 5 lecturas bilineales (Jimenez, «Filmic SMAA»).
vec3 historiaCatmullRom(vec2 uv) {
    vec2 tam = 1.0 / texel;
    vec2 pos = uv * tam;
    vec2 centro = floor(pos - 0.5) + 0.5;
    vec2 f = pos - centro;
    vec2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
    vec2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
    vec2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
    vec2 w3 = f * f * (-0.5 + 0.5 * f);
    vec2 w12 = w1 + w2;
    vec2 desp12 = w2 / w12;
    vec2 tc0 = (centro - 1.0) * texel;
    vec2 tc3 = (centro + 2.0) * texel;
    vec2 tc12 = (centro + desp12) * texel;
    vec3 r = Texel(historia, vec2(tc12.x, tc0.y)).rgb * (w12.x * w0.y)
        + Texel(historia, vec2(tc0.x, tc12.y)).rgb * (w0.x * w12.y)
        + Texel(historia, vec2(tc12.x, tc12.y)).rgb * (w12.x * w12.y)
        + Texel(historia, vec2(tc3.x, tc12.y)).rgb * (w3.x * w12.y)
        + Texel(historia, vec2(tc12.x, tc3.y)).rgb * (w12.x * w3.y);
    float peso = w12.x * w0.y + w0.x * w12.y + w12.x * w12.y + w3.x * w12.y + w12.x * w3.y;
    return max(r / peso, vec3(0.0));
}

// Recorta `h` hacia el centro de la caja [mn, mx] (Playdead, «Temporal
// Reprojection Anti-Aliasing in INSIDE»).
vec3 recortar(vec3 h, vec3 mn, vec3 mx) {
    vec3 centro = 0.5 * (mx + mn);
    vec3 medio = 0.5 * (mx - mn) + 1e-5;
    vec3 v = h - centro;
    vec3 u = abs(v / medio);
    float m = max(u.x, max(u.y, u.z));
    if (m > 1.0) {
        return centro + v / m;
    }
    return h;
}

vec4 effect(vec4 color, Image actual, vec2 uv, vec2 sc) {
    // 1. Vecinos: reconstrucción, momentos de la caja y la profundidad más cercana.
    vec3 suma = vec3(0.0);
    float pesos = 0.0;
    vec3 m1 = vec3(0.0);
    vec3 m2 = vec3(0.0);
    vec3 mn = vec3(1e5);
    vec3 mx = vec3(-1e5);
    float cerca = 1e20;
    float lejos = 0.0;
    float centro = 0.0;
    float movil = 0.0;
    vec2 uvCerca = uv;
    for (float y = -1.0; y <= 1.0; y += 1.0) {
        for (float x = -1.0; x <= 1.0; x += 1.0) {
            vec2 o = vec2(x, y);
            vec2 t = uv + o * texel;
            vec3 c = aEspacio(Texel(actual, t).rgb);
            vec2 d = o - jitter;
            float w = exp(-filtro * dot(d, d));
            suma += c * w;
            pesos += w;
            m1 += c;
            m2 += c * c;
            mn = min(mn, c);
            mx = max(mx, c);
            float m;
            float z = distanciaYMovil(t, m);
            movil = max(movil, m);
            lejos = max(lejos, z);
            if (x == 0.0 && y == 0.0) {
                centro = z;
            }
            if (z < cerca) {
                cerca = z;
                uvCerca = t;
            }
        }
    }
    vec3 nuevo = suma / pesos;
    // Lo que se guarda en alfa: la profundidad, negativa sobre lo móvil.
    float guardar = movil > 0.5 ? -centro : centro;
    if (reiniciar > 0.5) {
        return vec4(deEspacio(nuevo), guardar);
    }
    m1 /= 9.0;
    m2 /= 9.0;
    vec3 sigma = sqrt(max(m2 - m1 * m1, vec3(0.0)));

    // 2. Reproyección con la cámara anterior (el punto que ve este píxel sin
    // el desplazamiento del cuadro).
    vec2 ndc = vec2((uvCerca.x - jitter.x * texel.x) * 2.0 - 1.0, 1.0 - (uvCerca.y - jitter.y * texel.y) * 2.0);
    vec3 rayo = camFre + camDer * (ndc.x * camTan.x) + camArr * (ndc.y * camTan.y);
    // Donde estaba ese punto en el cuadro anterior (si se movió por su cuenta).
    vec3 punto = camPos + rayo * cerca - movimientoPropio(uvCerca);
    vec3 v = punto - antPos;
    float z = dot(v, antFre);
    vec2 uvAnt = vec2(
        0.5 + 0.5 * dot(v, antDer) / (z * antTan.x),
        0.5 - 0.5 * dot(v, antArr) / (z * antTan.y)
    );
    // Movimiento del punto: de donde está sin desplazar (uvCerca - jitter)
    // a donde estaba; se aplica al centro de este píxel.
    uvAnt += uv - (uvCerca - jitter * texel);
    if (z <= 0.0 || uvAnt.x < 0.0 || uvAnt.y < 0.0 || uvAnt.x > 1.0 || uvAnt.y > 1.0) {
        return vec4(deEspacio(nuevo), guardar);
    }
    // Otra superficie (algo que se movió por su cuenta): sin historia.
    float alfaAnt = Texel(historia, uvAnt).a;
    float profAnt = abs(alfaAnt);
    bool movilAnt = alfaAnt < 0.0;
    float cambio = z - cerca;
    float margen = toleranciaProf.x * lejos + toleranciaProf.y;
    if (profAnt < cerca + cambio - margen || profAnt > lejos + cambio + margen) {
        return vec4(deEspacio(nuevo), guardar);
    }
    vec2 movimiento = (uvAnt - uv) / texel;
    float velocidad = length(movimiento);

    // 3. Historia recortada a la caja de los vecinos (más estrecha al moverse).
    vec3 h = aEspacio(historiaCatmullRom(uvAnt));
    float g = mix(caja, 1.0, clamp(velocidad, 0.0, 1.0));
    if (movil > 0.5) {
        g = 0.75;
    }
    vec3 cajaMn = max(mn, m1 - sigma * g);
    vec3 cajaMx = min(mx, m1 + sigma * g);
    h = recortar(h, cajaMn, cajaMx);

    // 4. Mezcla.
    // Al moverse rápido la historia se emborrona al remuestrearla cada cuadro:
    // pesa más el cuadro nuevo. Los paneos lentos siguen estables.
    float a = mix(mezcla, mezclaMovil, smoothstep(rampaMovil.x, rampaMovil.y, velocidad));
    if (movil > 0.5 || movilAnt) {
        a = max(a, mezclaObjeto);
    }
    vec3 r = mix(h, nuevo, a);
    return vec4(deEspacio(r), guardar);
}
