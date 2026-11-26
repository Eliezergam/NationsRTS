// El cielo de la batalla (en el cubo de 3Dream alrededor del ojo): la
// atmósfera, el disco del sol con su oscurecimiento al borde y las estrellas.
varying vec3 direccion;
varying vec3 direccionEstrellas;

#ifdef PIXEL
uniform Image transmitancia;
uniform vec3 discoSol;        // radiancia del disco en la cima (iluminancia / ángulo sólido)
uniform float cosRadioSol;
uniform CubeImage estrellas;
uniform float fuerzaEstrellas;

void effect() {
    vec3 d = normalize(direccion);
    vec3 l = cieloEn(d);
    float c = dot(d, solDir);
    if (c > cosRadioSol && d.y > -0.02) {
        float borde = sqrt(max(0.0, 1.0 - c * c) / max(1.0 - cosRadioSol * cosRadioSol, 1e-9));
        float mu = sqrt(max(0.0, 1.0 - borde * borde));
        vec3 t = Texel(transmitancia, uvTransmitancia(radioOjo, d.y)).rgb;
        // Oscurecimiento al borde (ley de Neckel simplificada).
        // Tras las nubes, el disco del sol apenas se adivina.
        l += discoSol * t * (0.4 + 0.6 * pow(mu, 0.6)) * (1.0 - 0.97 * cubierto);
    }
    vec3 col = pow(max(l, vec3(0.0)), vec3(1.0 / 2.2));
    if (fuerzaEstrellas > 0.0 && d.y > 0.0) {
        vec3 e = Texel(estrellas, direccionEstrellas.xzy).rgb;
        col += (vec3(1.0) - exp(-e * fuerzaEstrellas)) * smoothstep(0.0, 0.15, d.y);
    }
    love_Canvases[0] = vec4(col, 1.0);
    love_Canvases[1] = vec4(65504.0, 0.0, 0.0, 1.0);
    love_Canvases[2] = vec4(0.0, 0.0, 0.0, 1.0);
}
#endif

#ifdef VERTEX
uniform highp mat4 transformProj;
uniform mat3 giroEstrellas;

vec4 position(mat4 transform_projection, vec4 VertexPosition) {
    direccion = VertexPosition.xyz;
    direccionEstrellas = giroEstrellas * VertexPosition.xyz;
    return transformProj * vec4(VertexPosition.xyz, 1.0);
}
#endif
