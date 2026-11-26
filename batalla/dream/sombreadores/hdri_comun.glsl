// Panorama HDRI (equirectangular, fila 0 = cénit) girado `giro` radianes.
uniform Image panorama;
uniform float giro;
uniform float escalaPanorama;
uniform float topePanorama; // lo que pasa de aquí es el sol (lo pone la luz directa)

vec2 uvPanorama(vec3 d) {
    float phi = atan(d.z, d.x) - giro;
    return vec2(fract(phi * 0.15915494 + 0.5), acos(clamp(d.y, -1.0, 1.0)) * 0.31830989);
}
