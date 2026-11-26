-- Humo del escape del camión de 4 misiles (Valeria): un humo suave al
-- ralentí, más seguido en marcha, y una bocanada oscura al arrancar y en
-- cada disparo. Solo mira: lee los camiones de `tropas` y emite partículas
-- 'humo' con los efectos de Camila (batalla/efectos.lua, con su propio azar:
-- no toca el de la batalla). Sale del punto `escapeSalidaHumo` del contrato
-- (batalla/articulacion_camion.lua) hacia +z del chasis.
--
-- Coste: solo los camiones a menos de `alcance` px del ojo, y unas pocas
-- partículas por segundo cada uno (las mueve la GPU).

local HumoEscape = {}
HumoEscape.__index = HumoEscape

HumoEscape.alcance = 2500 -- px (250 m) del ojo
HumoEscape.cadenciaRalenti = 0.45 -- s entre bocanadas al ralentí
HumoEscape.cadenciaMarcha = 0.18 -- s entre bocanadas en marcha
HumoEscape.velocidadMarcha = 20 -- px/s desde los que cuenta como en marcha

local GRIS_CLARO = { 0.62, 0.61, 0.59 }
local GRIS = { 0.4, 0.39, 0.38 }
local OSCURO = { 0.16, 0.15, 0.14 }

function HumoEscape.nuevo(efectos)
    local self = setmetatable({}, HumoEscape)
    self.efectos = efectos
    self.estado = setmetatable({}, { __mode = 'k' })
    return self
end

--- Una partícula de humo en (x, y, z) px que sube por (dx, dy, dz)
-- (unitario), de `tam` m, `vida` s y opacidad `alfa`.
function HumoEscape:soltar(x, y, z, dx, dy, dz, tam, vida, alfa, color0, color1)
    local e = self.efectos
    local p = e:nueva(x, y, z)
    local v = e:entre(1.2, 2.2)
    p.vx = dx * v + e:entre(-0.3, 0.3)
    p.vy = dy * v + e:entre(-0.3, 0.3)
    p.vz = dz * v
    p.vida = vida
    p.tam0, p.tam1 = tam * 0.35, tam * e:entre(1.6, 2.2)
    p.arrastre = 1.2
    p.subida = 0.5
    p.color0, p.color1 = color0, color1
    p.curva = 0.4
    p.alfa = alfa
    e:emitir('humo')
end

--- Un paso: `tropas` (sus camiones), el ojo en (ex, ey, ez) px.
function HumoEscape:actualizar(tropas, ex, ey, ez)
    local reloj = tropas.reloj or 0
    local alcance2 = HumoEscape.alcance * HumoEscape.alcance
    for _, u in ipairs(tropas.unidades) do
        local articulacion = u.lanzador and u.lanzador.articulacion
        if articulacion and not u.muerto and articulacion.escape then
            self:camion(u, articulacion, reloj, ex, ey, ez, alcance2)
        end
    end
end

function HumoEscape:camion(u, articulacion, reloj, ex, ey, ez, alcance2)
    local s = self.estado[u]
    if not s then
        s = { siguiente = reloj, cargados = articulacion:cargados(u), enMarcha = false }
        self.estado[u] = s
    end
    local x, y, z = articulacion:escapeEnMundo(u)
    if not x then
        return
    end
    local m = u.chasisVisual
    -- +z del chasis.
    local dx, dy, dz = m[3], m[7], m[11]
    local cargados = articulacion:cargados(u)
    local marcha = (u.velocidadRuedas or 0) > HumoEscape.velocidadMarcha
    local cerca = (x - ex) ^ 2 + (y - ey) ^ 2 + (z - ez) ^ 2 < alcance2
    if cerca then
        -- Bocanada al arrancar y en cada disparo (el motor tira).
        local bocanada = (marcha and not s.enMarcha) or cargados < s.cargados
        if bocanada then
            for _ = 1, 4 do
                self:soltar(x, y, z, dx, dy, dz, 1.1, 2.4, 0.55, OSCURO, GRIS)
            end
            s.siguiente = reloj + HumoEscape.cadenciaMarcha
        elseif reloj >= s.siguiente then
            if marcha then
                self:soltar(x, y, z, dx, dy, dz, 0.7, 1.8, 0.32, GRIS, GRIS_CLARO)
                s.siguiente = reloj + HumoEscape.cadenciaMarcha
            else
                self:soltar(x, y, z, dx, dy, dz, 0.45, 1.6, 0.2, GRIS_CLARO, GRIS_CLARO)
                s.siguiente = reloj + HumoEscape.cadenciaRalenti
            end
        end
    end
    s.enMarcha = marcha
    s.cargados = cargados
end
 
return HumoEscape
