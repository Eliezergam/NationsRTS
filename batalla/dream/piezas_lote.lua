-- Sombreador de vértices de 3DreamEngine para los vehículos articulados en
-- lotes (`piezasBatalla`, Valeria; batalla/dream/lote_articulado.lua).
--
-- Todas las piezas de un nivel de detalle con el mismo material van en una
-- sola malla, cada una en su pivote (sin mover): la w de `VertexPosition`
-- dice de qué pieza es cada vértice. Las matrices de las piezas de cada
-- vehículo están en `matricesPiezas` (rgba32f, batalla/dream/tabla_piezas.lua):
-- una fila por copia del lote (desde `filaPiezas`) y seis texeles por pieza,
-- con las columnas del giro en xyz y la posición en w, en ejes de 3Dream
-- (los mismos doce números que LoteUnidades.escribir): los tres primeros, de
-- este cuadro, y los otros tres, del anterior. Con ellos cada vértice escribe
-- cuánto se movió (`desplazaMovimiento`, lib/3DreamEngine) para el AA
-- temporal: así la historia del vehículo se reproyecta como la del suelo. Así un lote dibuja
-- todas las piezas de todos los camiones de ese nivel con una llamada; antes
-- era una llamada por pieza (y por pasada de sombra).
--
-- La pasada de sombras usa el mismo sombreador. Una pieza oculta (un misil
-- ya disparado) lleva la matriz a cero: sus triángulos quedan en un punto y
-- no se dibujan.

local sh = {}

sh.type = 'vertex'

function sh:buildDefines()
    return [[
#ifdef VERTEX
uniform highp sampler2D matricesPiezas;
uniform float filaPiezas;
#endif
]]
end

-- El vehículo destruido o averiado (`material.quemado`, lote_articulado.lua):
-- como el tanque averiado (escena.lua, cargarTanque), sin brillo. Su color
-- (0,18 / 0,15 / 0,13) ya multiplica la textura; aquí la rugosidad y el
-- metálico del material (1 y 0,05) mandan sobre los del mapa, que daba
-- reflejos del cielo en la chapa y dejaba ver el camuflaje como si estuviera
-- entero. Del mapa queda la oclusión.
function sh:getId(mat)
    if mat.quemado then
        return 1
    end
    return 0
end

function sh:buildPixel(mat)
    if not mat.quemado then
        return ''
    end
    return [[
    roughness = max(roughness, materialColor.y);
    metallic = min(metallic, materialColor.x);
    ]]
end

function sh:buildVertex()
    return [[
    int columnaPieza = int(VertexPosition.w + 0.5) * 6;
    int filaPieza = int(filaPiezas + 0.5) + love_InstanceID;
    vec4 piezaA = texelFetch(matricesPiezas, ivec2(columnaPieza, filaPieza), 0);
    vec4 piezaB = texelFetch(matricesPiezas, ivec2(columnaPieza + 1, filaPieza), 0);
    vec4 piezaC = texelFetch(matricesPiezas, ivec2(columnaPieza + 2, filaPieza), 0);
    mat3 giroPieza = mat3(piezaA.xyz, piezaB.xyz, piezaC.xyz);
    vertexPos = giroPieza * VertexPosition.xyz + vec3(piezaA.w, piezaB.w, piezaC.w);
    normalTransform = mat3(transform) * giroPieza;
    vertexPos = (transform * vec4(vertexPos, 1.0)).xyz;
#ifdef MOTION_MASK
    vec4 antesA = texelFetch(matricesPiezas, ivec2(columnaPieza + 3, filaPieza), 0);
    vec4 antesB = texelFetch(matricesPiezas, ivec2(columnaPieza + 4, filaPieza), 0);
    vec4 antesC = texelFetch(matricesPiezas, ivec2(columnaPieza + 5, filaPieza), 0);
    vec3 posicionAntes = mat3(antesA.xyz, antesB.xyz, antesC.xyz) * VertexPosition.xyz + vec3(antesA.w, antesB.w, antesC.w);
    desplazaMovimiento = vertexPos - (transform * vec4(posicionAntes, 1.0)).xyz;
#endif
    ]]
end

--- La tabla de matrices y la primera fila del lote.
function sh:perTask(shaderObject, task)
    local lote = task:getMesh()
    local textura = lote.matricesPiezas
    assert(textura, 'piezasBatalla: el lote no tiene matricesPiezas')
    if shaderObject.session.matricesPiezas ~= textura then
        shaderObject.session.matricesPiezas = textura
        shaderObject.shader:send('matricesPiezas', textura)
    end
    shaderObject.shader:send('filaPiezas', lote.filaPiezas or 0)
end

return sh
