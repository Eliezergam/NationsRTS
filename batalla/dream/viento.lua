-- Shader de vértices de la vegetación de batalla (`vientoBatalla`): aplica
-- el tono de cada copia (`InstanceTono`, ver instancias_tono.lua) sobre el
-- color lineal del vértice y, con el viento encendido (Fase 3 de
-- PLAN-RENDER-UE.md, calidad media y alta), mece las hojas, la hierba y los
-- pinos desplazando sus vértices.
--
-- Viento: cada material con `material.viento` = { amplitud, alto, frecuencia,
-- aleteo } (en metros y radianes por segundo; los pone
-- batalla/dream/estilo/recursos.lua) se dobla en la dirección del viento de la
-- batalla (el de las partículas, batalla/efectos.lua) según la altura sobre
-- su base: nada al pie y `amplitud` a `alto` metros (curva cuadrática, como
-- un tallo). La fase sale de la posición de la copia: las ráfagas recorren el
-- campo en la dirección del viento y cada planta va un poco a su aire. Las
-- hojas y las puntas tiemblan además con `aleteo` (fase por vértice). Solo de
-- cerca: se apaga entre `Viento.hasta` m del ojo (más allá, el nivel de
-- detalle se encarga y no hay saltos al cambiar de pieza).
--
-- Los parámetros de cada material van como constantes en su propio
-- sombreador (`getId` distingue la clase): así la pasada de sombras, en la
-- que 3Dream no envía los uniforms de cada material, mueve la sombra igual
-- que la planta. El tiempo, la dirección y el ojo, en `perShader`.

local Viento = {}

Viento.type = 'vertex'

-- Lo enciende batalla/dream/escena.lua según la calidad (`materiales.viento`).
Viento.activo = false
Viento.tiempo = 0 -- s, lo avanza la escena
Viento.direccion = { 1, 0 } -- x y z de 3Dream (normalizada)
Viento.ojo = { 0, 0, 0 } -- posición de la cámara del jugador (unidades de 3Dream)
Viento.hasta = { 50, 80 } -- m: entero hasta el primero, nada desde el segundo
Viento.longitudRafaga = 18 -- m entre ráfagas a lo largo del viento

--- Clase de viento del material (0: sin viento): un sombreador por clase.
function Viento:getId(material)
    if not Viento.activo or not material.viento then
        return 0
    end
    return material.vientoClase or 1
end

function Viento:buildDefines(material)
    local conViento = Viento.activo and material and material.viento
    return [[
        #ifdef VERTEX
        #ifdef INSTANCING
        attribute vec3 InstanceTono;
        #endif
        ]] .. (conViento and [[
        uniform float vientoTiempo;
        uniform vec2 vientoDireccion;
        uniform vec3 vientoOjo;
        ]] or '') .. [[
        #endif
    ]]
end

local function flotante(valor)
    return string.format('%.5f', valor)
end

function Viento:buildVertex(material)
    local conViento = Viento.activo and material and material.viento
    local codigo = [[
        #ifdef INSTANCING
        VaryingColor.rgb *= InstanceTono;
        #endif
    ]]
    if conViento then
        local v = material.viento
        -- Metros a unidades de 3Dream (10 m).
        codigo = codigo
            .. [[
        #ifdef INSTANCING
        {
            const float amplitud = ]]
            .. flotante(v.amplitud * 0.1)
            .. [[;
            const float alto = ]]
            .. flotante(v.alto * 0.1)
            .. [[;
            const float frecuencia = ]]
            .. flotante(v.frecuencia)
            .. [[;
            const float aleteo = ]]
            .. flotante((v.aleteo or 0) * 0.1)
            .. [[;
            vec3 pie = InstancePosition;
            float distancia = length(pie - vientoOjo) * 10.0;
            float cerca = 1.0 - smoothstep(]]
            .. flotante(Viento.hasta[1])
            .. ', '
            .. flotante(Viento.hasta[2])
            .. [[, distancia);
            if (cerca > 0.0) {
                float altura = max(vertexPos.y - pie.y, 0.0) / alto;
                float curva = altura * altura;
                // Ráfagas que avanzan con el viento, y un poco de azar por planta.
                float fase = dot(pie.xz, vientoDireccion) * ]]
            .. flotante(2 * math.pi / (Viento.longitudRafaga * 0.1))
            .. [[ + fract(sin(dot(pie.xz, vec2(12.9898, 78.233))) * 43758.5453) * 1.3;
                float t = vientoTiempo * frecuencia - fase;
                float rafaga = 0.65 + 0.35 * sin(vientoTiempo * 0.31 - fase * 0.21);
                float vaiven = (0.35 + 0.65 * (0.6 * sin(t) + 0.4 * sin(t * 2.13 + 1.7))) * rafaga;
                vec3 desp = vec3(vientoDireccion.x, 0.0, vientoDireccion.y) * (amplitud * curva * vaiven);
                // Las hojas y las puntas tiemblan con su propia fase.
                float faseHoja = dot(vertexPos, vec3(31.7, 17.3, 23.9));
                desp += vec3(sin(vientoTiempo * 7.3 + faseHoja), 0.5 * sin(vientoTiempo * 9.1 + faseHoja * 1.3),
                    cos(vientoTiempo * 8.2 + faseHoja * 0.7)) * (aleteo * altura * rafaga);
                // La planta se dobla: lo que se aparta, baja un poco.
                desp.y -= amplitud * curva * vaiven * vaiven * 0.3;
                vertexPos += desp * cerca;
            }
        }
        #endif
        ]]
    end
    return codigo .. [[
        vertexPos = (transform * vec4(vertexPos, 1.0)).xyz;
    ]]
end

function Viento:perShader(objetoSombreador)
    if not Viento.activo then
        return
    end
    local sombreador = objetoSombreador.shader
    if sombreador:hasUniform('vientoTiempo') then
        sombreador:send('vientoTiempo', Viento.tiempo)
        sombreador:send('vientoDireccion', Viento.direccion)
        sombreador:send('vientoOjo', Viento.ojo)
    end
end

return Viento
