-- Sombreador de píxeles del follaje (`follajeEstilo`, de la prueba de estilo
-- de Camila, batalla/pruebas_estilo): como el `textured`
-- de 3Dream (albedo de la textura por el color del material), pero inclina
-- la normal hacia la cámara. Los planos de agujas y de hierba se ven muchas
-- veces de canto o por debajo; con su normal tal cual, el Fresnel rasante
-- los llenaba del reflejo del cielo y salían casi blancos.

local FollajeSombreador = {}

FollajeSombreador.type = 'pixel'
FollajeSombreador.meshFormat = 'textured'

-- Cuánto se inclina la normal hacia la cámara (0: nada, 1: de frente), si
-- el material no lleva su propio `haciaCamara` (las rocas usan menos).
FollajeSombreador.haciaCamara = 0

function FollajeSombreador:buildDefines()
    return [[
        #ifdef PIXEL
        uniform Image albedoTexture;
        uniform vec4 albedoColor;
        uniform vec2 materialColor;
        uniform float haciaCamara;
        #endif
    ]]
end

function FollajeSombreador:buildPixel()
    return [[
        vec4 c = gammaCorrectedTexel(albedoTexture, VaryingTexCoord.xy) * albedoColor;
        // Tono de cada copia (quemado, derribado; batalla/dream/viento.lua).
        albedo = c.rgb * VaryingColor.rgb;
        alpha = c.a;
        metallic = materialColor.x;
        roughness = materialColor.y;
        emission = vec3(0.0);
        // La normal de la tarjeta tal cual (hacia arriba en las matas), sin
        // darle la vuelta por la cara: 3Dream la invierte en las caras de
        // atrás y, con la luz del cielo física, la mata vista por detrás
        // tomaba la luz oscura del suelo.
        normal = normalize(mix(normalize(varyingNormal), -viewVec, haciaCamara));
    ]]
end

function FollajeSombreador:perMaterial(objetoSombreador, material)
    local sombreador = objetoSombreador.shader
    sombreador:send('albedoTexture', material.albedoTexture)
    sombreador:send('albedoColor', material.color)
    sombreador:send('materialColor', { material.metallic, material.roughness })
    if sombreador:hasUniform('haciaCamara') then
        sombreador:send('haciaCamara', material.haciaCamara or FollajeSombreador.haciaCamara)
    end
end

return FollajeSombreador
