-- Shader de vértices de las orugas de los tanques (`orugaBatalla`, módulo de
-- 3DreamEngine de tipo 'vertex' como su wind.lua, registrado por la escena).
--
-- Cada copia del lote de una oruga lleva `InstanceOruga` (vec2, por copia;
-- lo escribe batalla/dream/lote_unidades.lua):
--   x  desplazamiento de la oruga en eslabones (0 a 1, batalla/orugas.lua).
--      Se suma a la u: la tesela de un eslabón se repite a lo largo de la
--      oruga (repeat). La u crece hacia delante por abajo y hacia atrás por
--      arriba: al sumar, los eslabones de abajo van hacia atrás respecto al
--      casco y los de arriba hacia delante, como en marcha.
--   y  difuso, de 0 a 1: contra el efecto estroboscópico. A 6 m/s y 60 fps
--      la oruga avanza 0,73 eslabones por cuadro: más de medio eslabón por
--      cuadro y el dibujo parece ir hacia atrás o quedarse quieto. Con el
--      difuso, el color, el metálico, la rugosidad, la oclusión y la normal
--      van hacia su media a lo largo de un eslabón (ocho muestras en la u: lo
--      que haría un desenfoque de movimiento largo). Solo a lo largo: lo que
--      cambia de un borde a otro de la oruga (en la v) se queda.
--
-- La pasada de sombras usa el mismo sombreador: la geometría no se mueve,
-- solo la u, así que la sombra es la de siempre. Sin instancias (por
-- ejemplo en la vitrina, que no lo usa), sin desplazamiento.

local Oruga = {}

Oruga.type = 'vertex'

function Oruga:getId()
    return 0
end

function Oruga:buildFlags()
    return ''
end

function Oruga:buildDefines()
    return [[
        varying float orugaDifuso;
        #ifdef VERTEX
        #ifdef INSTANCING
        attribute vec2 InstanceOruga;
        #endif
        #endif
    ]]
end

function Oruga:buildVertex()
    return [[
        #ifdef INSTANCING
        VaryingTexCoord.x += InstanceOruga.x;
        orugaDifuso = InstanceOruga.y;
        #else
        orugaDifuso = 0.0;
        #endif
        vertexPos = (transform * vec4(vertexPos, 1.0)).xyz;
    ]]
end

function Oruga:buildPixel()
    return [[
        #ifndef IS_SHADOW
        if (orugaDifuso > 0.001) {
            vec2 uvOruga = VaryingTexCoord.xy;
            vec3 albedoMedio = vec3(0.0);
            #ifdef MATERIAL_TEXTURE
            vec3 materialMedio = vec3(0.0);
            #endif
            #ifdef NORMAL_TEXTURE
            vec3 normalMedio = vec3(0.0);
            #endif
            for (int k = 0; k < 8; k++) {
                vec2 uvMuestra = vec2(uvOruga.x + float(k) * 0.125, uvOruga.y);
                albedoMedio += gammaCorrectedTexel(albedoTexture, uvMuestra).rgb;
                #ifdef MATERIAL_TEXTURE
                materialMedio += Texel(materialTexture, uvMuestra).xyz;
                #endif
                #ifdef NORMAL_TEXTURE
                normalMedio += Texel(normalTexture, uvMuestra).xyz;
                #endif
            }
            albedo = mix(albedo, albedoMedio * 0.125 * albedoColor.rgb, orugaDifuso);
            #ifdef MATERIAL_TEXTURE
            materialMedio *= 0.125;
            metallic = mix(metallic, materialMedio.x * materialColor.x, orugaDifuso);
            roughness = mix(roughness, materialMedio.y * materialColor.y, orugaDifuso);
            ao = mix(ao, materialMedio.z, orugaDifuso);
            #endif
            #ifdef NORMAL_TEXTURE
            normalMedio = normalMedio * 0.25 - vec3(1.0);
            normal = normalize(mix(normal, normalize(TBN * normalMedio), orugaDifuso));
            #endif
        }
        #endif
    ]]
end

function Oruga:perShader() end

function Oruga:perMaterial() end

function Oruga:perTask() end

return Oruga
