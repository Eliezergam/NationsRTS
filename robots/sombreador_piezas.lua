-- Shader de vértices de 3DreamEngine para los robots fundidos
-- (robots/union.lua): cada vértice lleva el número de su pieza
-- (`VertexPieza`) y se coloca con la matriz de esa pieza, que el juego
-- escribe cada cuadro. Es un esqueleto rígido (un hueso por pieza, peso 1),
-- como las mallas esqueléticas de Unreal o Unity: todo el robot en una
-- llamada por material en vez de una por pieza.
--
-- Se carga con `dream:newShader('robots.sombreador_piezas')`.

local sh = {}

sh.type = 'vertex'

-- Piezas como mucho por robot (cada una, una mat4 de uniformes: 256 son
-- 1024 vec4, dentro de lo que da cualquier tarjeta con OpenGL 3).
sh.maxPiezas = 256

function sh:buildDefines()
    return [[
        #ifdef VERTEX
        uniform mat4 piezasMatrices[]] .. self.maxPiezas .. [[];
        attribute float VertexPieza;
        #endif
    ]]
end

function sh:buildPixel()
    return ''
end

function sh:buildVertex()
    return [[
    mat4 piezaTransform = piezasMatrices[int(VertexPieza + 0.5)];
    vertexPos = (transform * (piezaTransform * vec4(vertexPos, 1.0))).xyz;
    normalTransform = normalTransform * mat3(piezaTransform);
    ]]
end

--- Las matrices del robot de esta malla (ByteData por filas), solo si
-- cambian respecto a la malla anterior con el mismo shader.
function sh:perTask(shaderObject, task)
    local malla = task:getMesh()
    local datos = malla.piezasDatos
    if datos and shaderObject.session.piezas ~= datos then
        shaderObject.session.piezas = datos
        -- Solo las del robot (no las 256): `piezasBytes`.
        shaderObject.shader:send('piezasMatrices', 'row', datos, 0, malla.piezasBytes)
    end
end

return sh
