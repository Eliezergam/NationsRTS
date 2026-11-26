// Radiancia del cielo en una dirección del mundo, leída de la tabla de la
// vista (ya con el sol y la luna).
uniform Image vistaCielo;
uniform vec3 solDir;
uniform float radioOjo;
// Cielo cubierto (NationsRTS, 17-nov: campo de batalla hostil, apagado): 0 el
// cielo físico; 1, todo gris plomizo. `oscurecerCubierto`: cuánto pierde de
// luz al cubrirse del todo.
uniform float cubierto;
uniform vec3 colorCubierto;
uniform float oscurecerCubierto;

vec3 cieloEn(vec3 d) {
    vec2 h = d.xz;
    vec2 s = solDir.xz;
    float lh = length(h);
    float ls = length(s);
    float cosRel = (lh > 1e-5 && ls > 1e-5) ? dot(h, s) / (lh * ls) : 1.0;
    vec3 c = Texel(vistaCielo, uvVista(radioOjo, d.y, cosRel)).rgb;
    float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
    // Las nubes reparten la luz: menos diferencia entre el horizonte y lo alto.
    vec3 plomo = colorCubierto * luma * (1.0 - oscurecerCubierto);
    return mix(c, plomo, cubierto);
}
