// Atmósfera física (Valeria): el modelo de Hillaire (2020), el mismo del Sky
// Atmosphere de Unreal, con sus valores por defecto (los de la referencia
// ue_ref/escena_info.json). Distancias en km; el centro del planeta en el
// origen y el eje Y hacia arriba, como en 3Dream.

const float PI = 3.14159265359;
const float RADIO_SUELO = 6360.0;
const float RADIO_CIMA = 6420.0; // 60 km de atmósfera, como en la referencia

const vec3 RAYLEIGH = vec3(5.802e-3, 13.558e-3, 33.1e-3);
const float ALTURA_RAYLEIGH = 8.0;
const float MIE_DISPERSION = 3.996e-3;
const float MIE_EXTINCION = 4.440e-3;
// Aerosoles: 1 = los de Unreal por defecto (aire muy limpio).
uniform float escalaMie;
const float ALTURA_MIE = 1.2;
const float MIE_G = 0.8;
const vec3 OZONO = vec3(0.650e-3, 1.881e-3, 0.085e-3);

struct Medio {
    vec3 rayleigh;
    float mie;
    vec3 extincion;
};

Medio medioEn(float altura) {
    float h = max(altura, 0.0);
    Medio m;
    float dr = exp(-h / ALTURA_RAYLEIGH);
    float dm = exp(-h / ALTURA_MIE);
    float oz = max(0.0, 1.0 - abs(h - 25.0) / 15.0);
    m.rayleigh = RAYLEIGH * dr;
    m.mie = MIE_DISPERSION * dm * escalaMie;
    m.extincion = m.rayleigh + MIE_EXTINCION * dm * escalaMie + OZONO * oz;
    return m;
}

// Distancia a la esfera de radio r (centro en el origen) desde o hacia d; la
// intersección positiva más cercana o -1.
float interseccion(vec3 o, vec3 d, float r) {
    float b = dot(o, d);
    float c = dot(o, o) - r * r;
    float disc = b * b - c;
    if (disc < 0.0) {
        return -1.0;
    }
    float s = sqrt(disc);
    float t0 = -b - s;
    float t1 = -b + s;
    if (t0 >= 0.0) {
        return t0;
    }
    if (t1 >= 0.0) {
        return t1;
    }
    return -1.0;
}

float faseRayleigh(float c) {
    return 3.0 / (16.0 * PI) * (1.0 + c * c);
}

// Cornette-Shanks, como Hillaire.
float faseMie(float c) {
    float g = MIE_G;
    float k = 3.0 / (8.0 * PI) * (1.0 - g * g) / (2.0 + g * g);
    return k * (1.0 + c * c) / pow(max(1.0 + g * g - 2.0 * g * c, 1e-4), 1.5);
}

// Tabla de transmitancia (Bruneton): altura y coseno del cenit <-> uv.
vec2 uvTransmitancia(float r, float mu) {
    float H = sqrt(RADIO_CIMA * RADIO_CIMA - RADIO_SUELO * RADIO_SUELO);
    float rho = sqrt(max(0.0, r * r - RADIO_SUELO * RADIO_SUELO));
    float disc = r * r * (mu * mu - 1.0) + RADIO_CIMA * RADIO_CIMA;
    float d = max(0.0, -r * mu + sqrt(max(disc, 0.0)));
    float dMin = RADIO_CIMA - r;
    float dMax = rho + H;
    return vec2((d - dMin) / (dMax - dMin), rho / H);
}

void transmitanciaDeUv(vec2 uv, out float r, out float mu) {
    float H = sqrt(RADIO_CIMA * RADIO_CIMA - RADIO_SUELO * RADIO_SUELO);
    float rho = H * uv.y;
    r = sqrt(rho * rho + RADIO_SUELO * RADIO_SUELO);
    float dMin = RADIO_CIMA - r;
    float dMax = rho + H;
    float d = dMin + uv.x * (dMax - dMin);
    mu = d == 0.0 ? 1.0 : (H * H - rho * rho - d * d) / (2.0 * r * d);
    mu = clamp(mu, -1.0, 1.0);
}

// Tabla de la vista del cielo (Hillaire): el cenit con más detalle junto al
// horizonte y el rumbo relativo al sol (0 hacia el sol) con más detalle
// cerca de él. `r` es el radio del ojo.
vec2 uvVista(float r, float cosCenit, float cosSol) {
    float vHorizonte = sqrt(max(r * r - RADIO_SUELO * RADIO_SUELO, 0.0));
    float beta = acos(clamp(vHorizonte / r, -1.0, 1.0));
    float horizonte = PI - beta;
    float angulo = acos(clamp(cosCenit, -1.0, 1.0));
    vec2 uv;
    if (angulo < horizonte) {
        float c = 1.0 - angulo / horizonte;
        uv.y = (1.0 - sqrt(max(c, 0.0))) * 0.5;
    } else {
        float c = (angulo - horizonte) / beta;
        uv.y = sqrt(clamp(c, 0.0, 1.0)) * 0.5 + 0.5;
    }
    uv.x = sqrt(clamp(-cosSol * 0.5 + 0.5, 0.0, 1.0));
    return uv;
}

void vistaDeUv(vec2 uv, float r, out float cosCenit, out float cosSol) {
    float vHorizonte = sqrt(max(r * r - RADIO_SUELO * RADIO_SUELO, 0.0));
    float beta = acos(clamp(vHorizonte / r, -1.0, 1.0));
    float horizonte = PI - beta;
    float angulo;
    if (uv.y < 0.5) {
        float c = 1.0 - 2.0 * uv.y;
        c = 1.0 - c * c;
        angulo = horizonte * c;
    } else {
        float c = uv.y * 2.0 - 1.0;
        angulo = horizonte + beta * c * c;
    }
    cosCenit = cos(angulo);
    float x = uv.x * uv.x;
    cosSol = -(x * 2.0 - 1.0);
}
