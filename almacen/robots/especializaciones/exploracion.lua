-- Exploración por fronteras (como los robots reales con su lidar): mientras
-- haya partes de la nave que su mapa no conoce, va al borde entre lo
-- conocido libre y lo desconocido más cercano (una «frontera») por donde
-- pueda pasar, mira y elige la siguiente. Cuando ya no quedan fronteras
-- alcanzables, ha terminado (y el transporte empieza sus encargos).
--
-- Órdenes que añade al robot:
--   robot:setExplorar(si)        empieza (true) o deja (false) de explorar
--   robot:getExplorando()        true mientras explora
--   robot:getFronteras()         cuántas zonas de frontera le quedan

---@class Exploracion : Robot
local Exploracion = {}
local Robot = GestorRobots.Robot

Exploracion.minimoFrontera = 6 -- casillas de frontera para que una zona cuente
Exploracion.zona = 1.0 -- m: las fronteras se juntan en zonas de este lado
Exploracion.alcanceVisto = 2.0 -- m: al llegar a menos de esto de la zona, ya la ha visto

function Exploracion:onLoad()
    local d = self.datos.exploracion
    d.activa = true
    d.descartadas = {}
    d.fronteras = 0
end

-- Zonas de frontera del mapa: { x, y, n }, de la más cercana a la más lejana.
local function zonasDeFrontera(self)
    local mapa = self:getMapa()
    local W, H = mapa.ancho, mapa.alto
    local celdas, visto = mapa.celdas, mapa.visto
    local zonas = {}
    local paso = math.floor(Exploracion.zona / mapa.resolucion)
    for cy = 1, H - 2 do
        for cx = 1, W - 2 do
            local i = cy * W + cx
            if visto[i] ~= 0 and celdas[i] < -0.2 then
                if visto[i - 1] == 0 or visto[i + 1] == 0 or visto[i - W] == 0 or visto[i + W] == 0 then
                    local clave = math.floor(cx / paso) .. ',' .. math.floor(cy / paso)
                    local z = zonas[clave]
                    if not z then
                        z = { sx = 0, sy = 0, n = 0, clave = clave }
                        zonas[clave] = z
                    end
                    z.sx, z.sy, z.n = z.sx + cx, z.sy + cy, z.n + 1
                end
            end
        end
    end
    local lista = {}
    for clave, z in pairs(zonas) do
        if z.n >= Exploracion.minimoFrontera and not self.datos.exploracion.descartadas[clave] then
            local x = mapa.x0 + (z.sx / z.n + 0.5) * mapa.resolucion
            local y = mapa.y0 + (z.sy / z.n + 0.5) * mapa.resolucion
            lista[#lista + 1] = { x = x, y = y, n = z.n, clave = clave, d = math.sqrt((x - self.x) ^ 2 + (y - self.y) ^ 2) }
        end
    end
    table.sort(lista, function(a, b)
        return a.d < b.d
    end)
    return lista
end

local function texto(self, t)
    if self.datos.transporte then
        self.datos.transporte.tarea = t
    end
end

function Exploracion:onUpdate()
    local d = self.datos.exploracion
    if not d.activa then
        return
    end
    if d.objetivo then
        -- Va hacia una zona: cuando la tiene cerca (ya la ve) o no hay
        -- camino, elige otra.
        local o = d.objetivo
        local cerca = (o.x - self.x) ^ 2 + (o.y - self.y) ^ 2 < Exploracion.alcanceVisto ^ 2
        if self:getSinCamino() then
            print(string.format('ROBOT dejo la zona %s (no llego)', o.clave))
            d.descartadas[o.clave] = true
            d.objetivo = nil
            self:setParar()
        elseif cerca or not self:getNavegando() then
            -- Ya ha ido (o lo ha intentado): esa zona no se repite.
            d.descartadas[o.clave] = true
            d.objetivo = nil
        end
        return
    end
    local zonas = zonasDeFrontera(self)
    d.fronteras = #zonas
    local mapa = self:getMapa()
    for _, z in ipairs(zonas) do
        -- Un sitio donde quepa el robot cerca de la frontera (hacia él).
        local ok = false
        local gx, gy = z.x, z.y
        for _, t in ipairs({ 0, 0.25, 0.5, 0.75 }) do
            gx, gy = z.x + (self.x - z.x) * t, z.y + (self.y - z.y) * t
            if not mapa:getBloqueado(gx, gy) then
                ok = true
                break
            end
        end
        -- La propia frontera tiene que estar donde cabe el robot (no en el
        -- hueco entre un pilar y la pared).
        ok = ok and not mapa:getBloqueado(z.x, z.y)
        if ok and z.d > 0.6 then
            d.objetivo = { x = gx, y = gy, clave = z.clave }
            texto(self, string.format('explorando: me quedan %d zonas sin ver', #zonas))
            self:setNavegarA(gx, gy)
            return
        end
        d.descartadas[z.clave] = true
    end
    -- Nada más que ver.
    d.activa = false
    texto(self, 'he visto todo el almacén')
    print('ROBOT exploración terminada')
end

function Robot:setExplorar(si)
    local d = self.datos.exploracion
    d.activa = si ~= false
    d.objetivo = nil
    d.descartadas = {}
end

function Robot:getExplorando()
    return self.datos.exploracion and self.datos.exploracion.activa == true
end

function Robot:getFronteras()
    return self.datos.exploracion.fronteras
end

GestorRobots.registrarEspecializacion('exploracion', Exploracion)
return Exploracion
