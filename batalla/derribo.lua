-- Derribo (Valeria): los vehículos tumban los árboles jóvenes, los abedules
-- finos y los arbustos al pasar; los árboles grandes (robles, pinos altos) y
-- las rocas los siguen frenando en la física.
--
-- Los árboles están en Box2D (batalla/fisica.lua, `crearArboles`): cada
-- fixture lleva su planta como dato. Un `preSolve` propio, encadenado al de
-- la extensión de 3Dream, desactiva el contacto con un árbol derribable y lo
-- apunta; tras el paso del mundo (fuera del bloqueo de Box2D) el árbol cae
-- con `Suelo:derribarArbol` en la dirección del avance, sale de la física y
-- el vehículo pierde algo de velocidad. Los arbustos no están en la física:
-- se tumban por proximidad al casco.

local Derribo = {}
Derribo.__index = Derribo

Derribo.troncoMaximo = 3 -- px (30 cm): tronco más grueso que aún se tumba
Derribo.altoMaximo = 125 -- px (12,5 m): copa más alta que aún se tumba
Derribo.frenazo = 0.7 -- parte de la velocidad que conserva el vehículo al tumbar uno
Derribo.radioArbusto = { tanque = 45, lanzacohetes = 60 } -- px del casco que pisa arbustos

--- ¿Se tumba la planta `p` al chocar un vehículo? Los arbustos siempre; los
-- árboles, si son finos y no muy altos; las rocas, nunca.
function Derribo.derribable(p)
    if p.roca or p.caido or not p.copia then
        return false
    end
    if p.arbusto then
        return true
    end
    return (p.radio or math.huge) <= Derribo.troncoMaximo and (p.alto or math.huge) <= Derribo.altoMaximo
end

--- Encadena el preSolve al mundo Box2D de `fisica`. `unidadDe` es la tabla
-- cuerpo -> unidad de los vehículos.
function Derribo.nuevo(fisica, unidadDe)
    local self = setmetatable({}, Derribo)
    self.fisica = fisica
    self.suelo = fisica.suelo
    self.unidadDe = unidadDe
    self.pendientes = {}
    self.derribados = 0
    local mundo = fisica.mundo:getWorld()
    local empezar, terminar, preSolveExtension, postSolve = mundo:getCallbacks()
    mundo:setCallbacks(empezar, terminar, function(a, b, contacto)
        if preSolveExtension then
            preSolveExtension(a, b, contacto)
        end
        self:preSolve(a, b, contacto)
    end, postSolve)
    return self
end

--- Contacto vehículo-árbol derribable: no frena y se apunta para después del paso.
function Derribo:preSolve(a, b, contacto)
    local planta, cuerpo
    local datosA, datosB = a:getUserData(), b:getUserData()
    if type(datosB) == 'table' and datosB.copia then
        planta, cuerpo = datosB, a:getBody()
    elseif type(datosA) == 'table' and datosA.copia then
        planta, cuerpo = datosA, b:getBody()
    end
    if not planta then
        return
    end
    local unidad = self.unidadDe[cuerpo]
    if not unidad or not Derribo.derribable(planta) then
        return
    end
    contacto:setEnabled(false)
    self.pendientes[#self.pendientes + 1] = { planta = planta, unidad = unidad }
end

--- Tumba la planta `p` hacia el avance de `unidad` y le resta velocidad.
function Derribo:tumbar(p, unidad)
    local dx, dy = p.x - unidad.x, p.y - unidad.y
    local colision = unidad.colision
    if colision and not colision:getBody():isDestroyed() then
        local cuerpo = colision:getBody()
        local vx, vz = cuerpo:getLinearVelocity()
        if vx * vx + vz * vz > 1e-6 then
            dx, dy = vx, vz
        end
        cuerpo:setLinearVelocity(vx * Derribo.frenazo, vz * Derribo.frenazo)
    end
    if self.suelo:derribarArbol(p, dx, dy) then
        self.derribados = self.derribados + 1
    end
end

--- Tras `mundo:update`: tumba los árboles apuntados y los arbustos bajo los cascos.
function Derribo:actualizar()
    for _, d in ipairs(self.pendientes) do
        self:tumbar(d.planta, d.unidad)
    end
    self.pendientes = {}
    local s = self.suelo
    local c = s.celdaPlantas
    for _, u in ipairs(self.fisica.unidades) do
        local radio = Derribo.radioArbusto[u.tipo]
        if radio and not u.muerto and u.colision and u.movimientoFisico then
            local i0, j0 = math.floor((u.x - radio) / c), math.floor((u.y - radio) / c)
            local i1, j1 = math.floor((u.x + radio) / c), math.floor((u.y + radio) / c)
            for j = j0, j1 do
                for i = i0, i1 do
                    for _, p in ipairs(s.celdasPlantas[i * 131072 + j] or {}) do
                        if p.arbusto and not p.caido and (p.x - u.x) ^ 2 + (p.y - u.y) ^ 2 < radio * radio then
                            self:tumbar(p, u)
                        end
                    end
                end
            end
        end
    end
end

return Derribo
