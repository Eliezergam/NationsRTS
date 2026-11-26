// Dirección de un texel de la cara `cara` (0 a 5: +X, -X, +Y, -Y, +Z, -Z) de
// un cubo de OpenGL, con uv de 0 a 1 (v = 0 en la primera fila). 3Dream lee
// sus cubos con la z cambiada de signo: la dirección del mundo es
// `dirCubo(...) * vec3(1.0, 1.0, -1.0)`.
vec3 dirCubo(float cara, vec2 uv) {
    float s = uv.x * 2.0 - 1.0;
    float t = uv.y * 2.0 - 1.0;
    vec3 d;
    if (cara < 0.5) {
        d = vec3(1.0, -t, -s);
    } else if (cara < 1.5) {
        d = vec3(-1.0, -t, s);
    } else if (cara < 2.5) {
        d = vec3(s, 1.0, t);
    } else if (cara < 3.5) {
        d = vec3(s, -1.0, -t);
    } else if (cara < 4.5) {
        d = vec3(s, -t, 1.0);
    } else {
        d = vec3(-s, -t, -1.0);
    }
    return normalize(d);
}

// Codificación de 3Dream para sus cubos de reflejos (la lectura hace ^2,2).
vec3 codificar(vec3 c) {
    return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2));
}

vec3 decodificar(vec3 c) {
    return pow(max(c, vec3(0.0)), vec3(2.2));
}

float radicalInverso(float i) {
    float r = 0.0;
    float f = 0.5;
    float n = i;
    for (int k = 0; k < 10; k++) {
        r += mod(n, 2.0) * f;
        n = floor(n * 0.5);
        f *= 0.5;
    }
    return r;
}

// Media del lóbulo GGX alrededor de n (alfa = rugosidad^2), muestreo por importancia.
vec3 mitadGGX(vec2 xi, vec3 n, float alfa) {
    float phi = 2.0 * 3.14159265359 * xi.x;
    float cosT = sqrt((1.0 - xi.y) / (1.0 + (alfa * alfa - 1.0) * xi.y));
    float senT = sqrt(max(0.0, 1.0 - cosT * cosT));
    vec3 h = vec3(cos(phi) * senT, sin(phi) * senT, cosT);
    vec3 arriba = abs(n.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
    vec3 tx = normalize(cross(arriba, n));
    vec3 ty = cross(n, tx);
    return normalize(tx * h.x + ty * h.y + n * h.z);
}
