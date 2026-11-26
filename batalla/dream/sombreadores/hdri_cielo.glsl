// El cielo de un panorama HDRI en el cubo de 3Dream (fondo, con su sol).
varying vec3 direccion;

#ifdef PIXEL
void effect() {
    vec3 d = normalize(direccion);
    vec3 l = textureLod(panorama, uvPanorama(d), 0.0).rgb * escalaPanorama;
    love_Canvases[0] = vec4(pow(max(l, vec3(0.0)), vec3(1.0 / 2.2)), 1.0);
    love_Canvases[1] = vec4(65504.0, 0.0, 0.0, 1.0);
    love_Canvases[2] = vec4(0.0, 0.0, 0.0, 1.0);
}
#endif

#ifdef VERTEX
uniform highp mat4 transformProj;

vec4 position(mat4 transform_projection, vec4 VertexPosition) {
    direccion = VertexPosition.xyz;
    return transformProj * vec4(VertexPosition.xyz, 1.0);
}
#endif
