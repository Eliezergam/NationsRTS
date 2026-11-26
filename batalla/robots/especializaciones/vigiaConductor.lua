-- Lo que mira y hace con los brazos el conductor del camión de misiles
-- (el dueño, 18-nov), con la lógica de mirar de los soldados
-- (batalla/robots/mirada.lua):
--   * Conduciendo o esperando: agarrado a las palancas, lee el panorama
--     barriendo a un lado y a otro, como el soldado.
--   * El camión se para a disparar (rampa subiendo): suelta las palancas,
--     gira un poco el torso y mira el misil que va a salir.
--   * Sale el misil: lo sigue con la mirada (cabeza y ojos, también hacia
--     arriba) y alterna: mira al frente un momento y vuelve al misil.
--   * Rampa abajo y sin misiles en el aire: vuelve a las palancas.
--
-- Lee el estado del camión (camion.datos.rampaMisiles) y el misil en vuelo
-- (el de batalla/tropas.lua, Tropas.posicionMisil).

local Nucleo = require('robots.nucleo')
local Mirada = require('batalla.robots.mirada')
local Tropas = require('batalla.tropas')

local VigiaConductor = {}

VigiaConductor.torsoMisil = math.rad(45) -- «voltee el torso un poco»
VigiaConductor.verMisil = { 1.2, 2.0 } -- s mirando el misil
VigiaConductor.verFrente = { 0.45, 0.9 } -- s mirando al frente entre medias
VigiaConductor.soltarEn = 0.6 -- s en soltar o agarrar las palancas
-- Brazos y dedos al soltar (rad de más sobre la pose de las palancas): los
-- hombros bajan los brazos, las manos quedan sobre las piernas y los dedos
-- (cerrados en la pose) se aflojan, medio cerrados.
VigiaConductor.hombro = 0.4
VigiaConductor.codo = -0.15
VigiaConductor.dedos = { -0.12, -0.4, -0.3 }
VigiaConductor.recogerTras = 1.0 -- s sin misil en el aire antes de volver a las palancas

local PX_POR_M = 10

local function azar(r)
    return r[1] + love.math.random() * (r[2] - r[1])
end

function VigiaConductor.prerequisitos(self)
    return self:getTienePieza('cabeza') and self:getTienePieza('torso')
end

function VigiaConductor.onLoad(self)
    local d = self.datos.vigiaConductor
    d.reloj, d.soltar, d.fase, d.cambio, d.sinMisil = 0, 0, 'misil', 0, math.huge
    d.dedos = {}
    for _, s in ipairs({ 'Der', 'Izq' }) do
        for _, letra in ipairs({ 'A', 'B', 'C' }) do
            for i = 1, 3 do
                local p = self.piezas['dedo' .. letra .. i .. s]
                if p then
                    d.dedos[#d.dedos + 1] = { pieza = p, giro = VigiaConductor.dedos[i] }
                end
            end
        end
    end
end

--- El misil en vuelo del camión (en m, marco de los robots), si lo hay.
local function misilEnVuelo(v)
    local r = v.datos.rampaMisiles
    local m = r and r.ultimo
    local t = v.tropas
    if not m or not t or not m.duracion then
        return nil
    end
    local f = ((t.relojVista or t.reloj) - m.inicio) / m.duracion
    if f < 0 or f >= 1 then
        return nil
    end
    local x, y, z = Tropas.posicionMisil(m, f)
    return x / PX_POR_M, -y / PX_POR_M, z / PX_POR_M
end

--- El siguiente misil de la rampa (su punta), para mirarlo antes de salir.
local function misilEnRampa(v)
    local r = v.datos.rampaMisiles
    if not r or r.cargados <= 0 then
        return nil
    end
    local p = r.misiles[#r.misiles - r.cargados + 1]
    local m = p and p:getMatriz()
    if not m then
        return nil
    end
    return p:getPunto(4, 0, 0)
end

function VigiaConductor.onUpdate(self, dt)
    local d = self.datos.vigiaConductor
    local v = self.vehiculo
    d.reloj = d.reloj + dt
    if not v then
        return
    end
    local rampa = v.datos.rampaMisiles
    local estado = rampa and rampa.estado or 'recogido'
    local cabeza = self:getPieza('cabeza')
    local ox, oy, oz = cabeza:getPunto(0.08, 0, 0.12)
    local mx, my, mz = misilEnVuelo(v)
    if mx then
        d.sinMisil = 0
    else
        d.sinMisil = d.sinMisil + dt
    end
    local desplegado = estado == 'subiendo' or estado == 'fuego'
    local atento = desplegado or d.sinMisil < VigiaConductor.recogerTras
    -- Suelta las palancas para mirar; las vuelve a coger al acabar.
    local quiereSoltar = atento and estado ~= 'apoyando' and estado ~= 'recogido' and 1 or 0
    if estado == 'recogiendo' or estado == 'recogido' then
        quiereSoltar = (d.sinMisil < VigiaConductor.recogerTras) and 1 or 0
    end
    local paso = dt / VigiaConductor.soltarEn
    d.soltar = d.soltar < quiereSoltar and math.min(quiereSoltar, d.soltar + paso) or math.max(quiereSoltar, d.soltar - paso)
    local mirarA, arriba, torso
    if mx then
        -- En vuelo: el misil, con ojeadas al frente de vez en cuando.
        d.cambio = d.cambio - dt
        if d.cambio <= 0 then
            d.fase = d.fase == 'misil' and 'frente' or 'misil'
            d.cambio = azar(d.fase == 'misil' and VigiaConductor.verMisil or VigiaConductor.verFrente)
        end
        if d.fase == 'misil' then
            mirarA, arriba = Mirada.hacia(ox, oy, oz, mx, my, mz)
        else
            mirarA, arriba = self.rumbo, 0
        end
        torso = VigiaConductor.torsoMisil * (((mirarA - self.rumbo + math.pi) % (2 * math.pi) - math.pi) > 0 and 1 or -1)
    elseif desplegado then
        -- Esperando que salga: el misil de la rampa.
        local px, py, pz = misilEnRampa(v)
        if px then
            mirarA, arriba = Mirada.hacia(ox, oy, oz, px, py, pz)
            torso = VigiaConductor.torsoMisil * (((mirarA - self.rumbo + math.pi) % (2 * math.pi) - math.pi) > 0 and 1 or -1)
        end
        d.fase, d.cambio = 'misil', azar(VigiaConductor.verMisil)
    end
    if not mirarA then
        -- Conduciendo o esperando: lee el panorama, como el soldado.
        mirarA, arriba, torso = Mirada.barrido(self.rumbo, d.reloj), 0, 0
    end
    -- El torso solo gira con las manos sueltas.
    Mirada.girar(d, self.rumbo, mirarA, torso * d.soltar, dt, arriba)
end

function VigiaConductor.onPose(self)
    local d = self.datos.vigiaConductor
    Mirada.poner(self, d)
    local s = d.soltar * d.soltar * (3 - 2 * d.soltar)
    for _, lado in ipairs({ 'Der', 'Izq' }) do
        self:getPieza('hombro' .. lado):setGiro('y', VigiaConductor.hombro * s, 'soltar')
        self:getPieza('codo' .. lado):setGiro('y', VigiaConductor.codo * s, 'soltar')
    end
    for _, dedo in ipairs(d.dedos) do
        dedo.pieza:setGiro('y', dedo.giro * s, 'soltar')
    end
end

Nucleo.registrarEspecializacion('vigiaConductor', VigiaConductor)
return VigiaConductor
