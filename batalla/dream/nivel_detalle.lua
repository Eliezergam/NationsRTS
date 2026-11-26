-- Niveles de detalle de las unidades de la batalla 3D (Valeria): qué nivel
-- de assets/modelos3d/lod.lua (Camila) toca a cada vehículo y el fundido
-- corto al cambiar.
--
-- Elección: por el tamaño en pantalla. `fraccion` es el diámetro de la
-- esfera envolvente del modelo (2 * radio) partido por el alto visible a su
-- distancia con el campo vertical de la cámara; cada nivel vale mientras la
-- fracción no baje de su `pantalla`. Para pasar a un nivel más sencillo hace
-- falta bajar `histeresis` por debajo del umbral (no parpadea en el borde).
--
-- Fundido: al cambiar, el nivel nuevo aparece por tramado (material con
-- `setDither` y alfa en `pasos`) durante `duracion` s mientras el anterior
-- sigue entero; al acabar se quita el anterior. Así nunca hay un hueco a
-- media transición. Va con el reloj real: es dibujo, no guerra, y en pausa
-- la cámara se sigue moviendo.

local NivelDetalle = {}

NivelDetalle.duracion = 0.25 -- s de fundido
NivelDetalle.histeresis = 0.8
NivelDetalle.pasos = { 0.25, 0.5, 0.75 } -- alfas del tramado durante el fundido
NivelDetalle.campo = math.rad(40)

local indice

--- El índice de niveles de Camila (o uno vacío si no está).
function NivelDetalle.indice()
    if not indice then
        local ok, datos = pcall(require, 'assets.modelos3d.lod')
        indice = ok and type(datos) == 'table' and datos or { modelos = {} }
    end
    return indice
end

--- Niveles del modelo de `archivo` (ruta sin extensión): la lista del índice
-- o, si no está, uno solo con ese archivo.
function NivelDetalle.niveles(archivo)
    local clave = archivo:match('([^/]+)$')
    local entrada = NivelDetalle.indice().modelos[clave]
    if entrada and entrada.niveles and #entrada.niveles > 0 then
        return entrada.niveles, entrada.radio or 5
    end
    return { { archivo = archivo, pantalla = 0 } }, 5
end

--- Fracción del alto de la pantalla que ocupa una esfera de `radio` m a
-- `distancia` px (10 px = 1 m).
function NivelDetalle.fraccion(radio, distancia)
    local d = math.max(distancia / 10, 0.1)
    return radio / (d * math.tan(NivelDetalle.campo / 2))
end

--- Nivel (índice en `niveles`) para la fracción `fraccion`, partiendo de
-- `actual` (o nil).
function NivelDetalle.elegir(niveles, fraccion, actual)
    local n = #niveles
    for k = 1, #niveles do
        if fraccion >= (niveles[k].pantalla or 0) then
            n = k
            break
        end
    end
    if actual and n > actual and fraccion >= (niveles[actual].pantalla or 0) * NivelDetalle.histeresis then
        n = actual
    end
    return n
end

--- Avanza el estado `e` de una unidad ({ nivel, anterior, inicio, paso }) con
-- el nivel deseado `deseado` en el instante `ahora` (s). Mientras dura un
-- fundido no empieza otro.
function NivelDetalle.actualizar(e, deseado, ahora)
    if not e.nivel then
        e.nivel = deseado
        return e
    end
    if e.anterior then
        local f = (ahora - e.inicio) / NivelDetalle.duracion
        if f >= 1 then
            e.anterior, e.paso = nil, nil
        else
            e.paso = math.min(#NivelDetalle.pasos, math.floor(f * #NivelDetalle.pasos) + 1)
            return e
        end
    end
    if deseado ~= e.nivel then
        e.anterior, e.nivel, e.inicio, e.paso = e.nivel, deseado, ahora, 1
    end
    return e
end

return NivelDetalle
