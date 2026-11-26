-- Recorte de los emisores de sombra por cascada. 3Dream pinta las tres
-- cascadas del sol con todos los emisores (su cámara de sombra no recorta):
-- un pino a 100 m se dibuja también en la cascada de 13 m. Aquí cada copia
-- se clasifica por la cascada más pequeña cuyo cuadrado (en el espacio de la
-- luz, como la proyección ortográfica de jobs/sunShadow.lua) la contiene, y
-- los lotes de sombra las guardan en ese orden (lote_rapido.lua). Antes de
-- pintar cada cascada se deja a cada lote solo el principio que le toca.
--
-- No se cambia la librería: se envuelve `dream.render` al instalarlo, una
-- sola vez por partida (`SombraCascadas.unico`): cada batalla nueva reutiliza
-- el mismo envoltorio con su sol y sus lotes.
-- (De la prueba de estrés de Camila, batalla/pruebas_estilo/sombra_cascadas.lua.)

local SombraCascadas = {}
SombraCascadas.__index = SombraCascadas

local unico

--- El recorte de cascadas de la partida, con el sol `sol` y sin lotes.
function SombraCascadas.unico(dream, sol)
    if not unico then
        unico = SombraCascadas.nuevo(dream, sol)
        return unico
    end
    unico.sol = sol
    unico.lotes = {}
    unico.centros = nil
    unico.listo = false
    return unico
end

function SombraCascadas.nuevo(dream, sol)
    local self = setmetatable({}, SombraCascadas)
    self.dream = dream
    self.sol = sol
    self.lotes = {}
    self.radios = { 1, 2, 3 }
    self.activo = true
    self.ocultos = {}
    self:instalar()
    return self
end

--- Añade lotes de sombra (con `porCascada`).
function SombraCascadas:registrar(lotes)
    for _, l in ipairs(lotes) do
        if l.porCascada then
            self.lotes[#self.lotes + 1] = l
        end
    end
end

--- Base de la luz y radios (m) de las cascadas para este cuadro. `ojo` es
-- la posición de la cámara en metros.
function SombraCascadas:actualizar(ojo)
    local sombra = self.sol.shadow
    if not sombra then
        return
    end
    local d = self.sol.direction
    -- Ejes del cuadrado de la cámara de sombra: lookAt con arriba = Y.
    local nx, ny, nz = d.x, d.y, d.z
    local ex, ey, ez = -nz, 0, nx
    local largo = math.sqrt(ex * ex + ey * ey + ez * ez)
    ex, ey, ez = ex / largo, ey / largo, ez / largo
    self.ex, self.ey, self.ez = ex, ey, ez
    self.ux = ny * ez - nz * ey
    self.uy = nz * ex - nx * ez
    self.uz = nx * ey - ny * ex
    -- Centro de cada cascada: 3Dream solo mueve su cámara de sombra cuando
    -- la cámara se aleja un paso, así que se usa la suya si ya existe.
    self.centros = self.centros or { {}, {}, {} }
    local medio = sombra.cascadeDistance / 2 * 10
    for c = 1, 3 do
        self.radios[c] = medio * sombra.cascadeFactor ^ (c - 1)
        local centro = self.centros[c]
        local camara = sombra.cams and sombra.cams[c]
        if camara and camara.position then
            centro[1], centro[2], centro[3] = camara.position.x * 10, camara.position.y * 10, camara.position.z * 10
        else
            centro[1], centro[2], centro[3] = ojo.x, ojo.y, ojo.z
        end
    end
    self.listo = true
end

--- Cascada más pequeña que contiene la esfera (m); 3 si ninguna.
function SombraCascadas:clase(x, y, z, radio)
    if not self.listo then
        return 3
    end
    for c = 1, 2 do
        local centro = self.centros[c]
        local dx, dy, dz = x - centro[1], y - centro[2], z - centro[3]
        local a = math.abs(dx * self.ex + dy * self.ey + dz * self.ez)
        local b = math.abs(dx * self.ux + dy * self.uy + dz * self.uz)
        if math.max(a, b) - radio < self.radios[c] then
            return c
        end
    end
    return 3
end

--- Índice de la cascada de una cámara de sombra, o nil.
function SombraCascadas:cascada(camara)
    local sombra = self.sol.shadow
    if not sombra or not sombra.cams then
        return nil
    end
    for c = 1, 3 do
        if sombra.cams[c] == camara then
            return c
        end
    end
    return nil
end

function SombraCascadas:instalar()
    local dream = self.dream
    local original = dream.render
    local este = self
    dream.render = function(libreria, camara, lienzos, dinamico, esSombra, listaNegra)
        local cascada = esSombra and este.activo and este:cascada(camara)
        if not cascada then
            return original(libreria, camara, lienzos, dinamico, esSombra, listaNegra)
        end
        local ocultos = este.ocultos
        for k in pairs(ocultos) do
            ocultos[k] = nil
        end
        if listaNegra then
            for k, v in pairs(listaNegra) do
                ocultos[k] = v
            end
        end
        for _, l in ipairs(este.lotes) do
            local n = l.cortes[cascada]
            l.malla.instancesCount = n
            if n == 0 then
                ocultos[l.malla] = true
            end
        end
        if este.depurar then
            local total = 0
            for _, l in ipairs(este.lotes) do
                total = total + l.cortes[cascada]
            end
            este.depurar[cascada] = total
        end
        original(libreria, camara, lienzos, dinamico, esSombra, ocultos)
        for _, l in ipairs(este.lotes) do
            l.malla.instancesCount = l.cantidad
        end
    end
end

return SombraCascadas
