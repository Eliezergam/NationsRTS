-- Sombreador de vértices de los escombros (Camila): trozos de tierra y roca,
-- astillas y chapas que saltan en los impactos. Mallas 3D pequeñas por
-- instancias, con la misma caída de `comun.lua`; giran sobre un eje que sale
-- de su semilla, cada vez más despacio, y se paran en el suelo. Al final de
-- su vida se hunden (encogen) en vez de desaparecer de golpe.
--
-- Atributos por copia: los de `particula_vertices.lua` (ParticulaA-D,
-- ParticulaColor0 y ParticulaExtra); ParticulaC.x es el tamaño (m / 10) y
-- ParticulaC.w la velocidad de giro.

local Comun = require('batalla.dream.efectos.comun')

local Sombreador = {}

Sombreador.type = 'vertex'

function Sombreador:buildDefines()
    return [[
        varying vec4 vEfecto;
        #ifdef VERTEX
        attribute vec4 ParticulaA;
        attribute vec4 ParticulaB;
        attribute vec4 ParticulaC;
        attribute vec4 ParticulaD;
        attribute vec4 ParticulaColor0;
        attribute vec4 ParticulaColor1;
        attribute vec4 ParticulaExtra;
        ]] .. Comun.uniformesDream .. Comun.movimiento .. [[
        mat3 efectoGiro(vec3 eje, float angulo) {
            float c = cos(angulo);
            float s = sin(angulo);
            float t = 1.0 - c;
            return mat3(
                t * eje.x * eje.x + c, t * eje.x * eje.y + s * eje.z, t * eje.x * eje.z - s * eje.y,
                t * eje.x * eje.y - s * eje.z, t * eje.y * eje.y + c, t * eje.y * eje.z + s * eje.x,
                t * eje.x * eje.z + s * eje.y, t * eje.y * eje.z - s * eje.x, t * eje.z * eje.z + c
            );
        }
        #endif
    ]]
end

function Sombreador:buildVertex()
    return [[
        float e = efectoTiempo - ParticulaA.w;
        float vida = max(ParticulaB.w, 0.0001);
        float f = e / vida;
        if (e < 0.0 || f >= 1.0) {
            vertexPos = vec3(0.0, -100000.0, 0.0);
            VaryingColor = vec4(0.0);
            vEfecto = vec4(0.0);
        } else {
            vec3 v;
            vec3 p = efectoMover(ParticulaA.xyz, ParticulaB.xyz, e, ParticulaD.x, ParticulaD.y, ParticulaD.w, ParticulaD.z, v);
            float semilla = ParticulaExtra.w * 255.0;
            vec3 eje = normalize(vec3(sin(semilla * 12.9), cos(semilla * 78.2), sin(semilla * 37.7) + 0.3));
            float angulo = ParticulaC.z + ParticulaC.w * (1.0 - exp(-1.2 * e)) / 1.2;
            mat3 giro = efectoGiro(eje, angulo);
            float tam = ParticulaC.x * (1.0 - smoothstep(0.82, 1.0, f));
            // Apoyado: medio tamaño por encima del suelo.
            p.y = max(p.y, ParticulaD.z + tam * 0.3);
            vertexPos = p + giro * (VertexPosition.xyz * tam);
            normalTransform = giro;
            VaryingColor = vec4(pow(ParticulaColor0.rgb, vec3(2.2)), 1.0);
            vEfecto = vec4(0.0, 0.0, ParticulaExtra.z, 0.0);
        }
        // La transformación del lote es la identidad; se aplica igual que el
        // sombreador de vértices de 3Dream (y así el motor la encuentra).
        vertexPos = (transform * vec4(vertexPos, 1.0)).xyz;
    ]]
end

function Sombreador:perTask(objeto)
    Comun.enviarDream(objeto)
end

return Sombreador
