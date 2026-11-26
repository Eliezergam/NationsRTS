-- Recorte de la cámara de batalla por esferas y planos normalizados.
-- 3Dream extrae los planos sin normalizar y compensa el radio con un factor
-- fijo: con FOV de 40° descarta objetos que todavía cruzan el borde visible.
-- Este adaptador solo cambia la cámara recibida, sin modificar la librería.

local Visibilidad = {}

--- Los seis planos de recorte en unidades de mundo. El término independiente
-- se normaliza junto con la normal para poder compararlo con un radio real.
function Visibilidad.actualizarPlanos(camara)
    local matriz = camara.transformProj
    local planos = {}
    for fila = 0, 2 do
        for _, signo in ipairs({ 1, -1 }) do
            local plano = {}
            for columna = 1, 4 do
                plano[columna] = matriz[12 + columna] + signo * matriz[fila * 4 + columna]
            end
            local longitud = math.sqrt(plano[1] ^ 2 + plano[2] ^ 2 + plano[3] ^ 2)
            -- Un plano degenerado no aporta un límite válido; omitirlo es
            -- conservador y también permite proyecciones con infinito lejano.
            if longitud > 1e-12 then
                for columna = 1, 4 do
                    plano[columna] = plano[columna] / longitud
                end
                planos[#planos + 1] = plano
            end
        end
    end
    camara.planes = planos
end

--- Mantiene la firma de Dream (posición, radio, identificador). La prueba
-- depende del volumen actual, no de una caché compartida entre copias.
function Visibilidad.enFrustum(camara, posicion, radio, _identificador)
    local margen = 0.0001 + math.max(0, radio) * 0.000001
    for _, plano in ipairs(camara.planes) do
        local distancia = plano[1] * posicion[1] + plano[2] * posicion[2] + plano[3] * posicion[3] + plano[4]
        if distancia + radio + margen < 0 then
            return false
        end
    end
    return true
end

--- Instala el recorte solo en esta cámara; conserva las cámaras del motor.
function Visibilidad.instalar(camara)
    camara.updateFrustumPlanes = Visibilidad.actualizarPlanos
    camara.inFrustum = Visibilidad.enFrustum
    return camara
end

return Visibilidad
