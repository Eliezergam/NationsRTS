-- Trabajo de prueba del robot grande: lleva un bidón de petróleo de un
-- sitio a otro de la fábrica y vuelta, para ver las orugas, los brazos y
-- las garras. Para cada viaje:
--   1. se pone con el bidón delante de la garra izquierda (a la distancia
--      cómoda) mirándolo, con la garra abierta;
--   2. baja la garra al punto de agarre del bidón (el `cuerpo`), cierra las
--      uñas y lo cuelga de la garra;
--   3. lo sube medio metro, va al otro sitio y lo baja hasta el suelo;
--   4. abre, recoge el brazo y retrocede.
-- La lista de sitios: `Acarreo.sitios` (x, y del almacén).

---@class Acarreo : Robot
local Acarreo = {}
local Robot = GestorRobots.Robot

Acarreo.sitios = { { -66.0, 0.0 }, { -55.5, 0.0 } } -- pasillo central de la fábrica, entre los puestos
Acarreo.lado = 'izq'
Acarreo.subir = 0.5 -- m que levanta lo que lleva
Acarreo.espera = 1.0 -- s entre viajes

local function tarea(self, texto)
    self.datos.acarreo.tarea = texto
end

local function esperar(condicion)
    while not condicion() do
        coroutine.yield()
    end
end

-- Dónde se pone el robot para que la garra quede en (x, y), viniendo de
-- donde está: x, y, rumbo.
local function sitioPara(self, x, y)
    local adelante, lado = self:getAlcanceGarra(Acarreo.lado)
    local rumbo = math.atan2(y - self.y, x - self.x)
    local c, s = math.cos(rumbo), math.sin(rumbo)
    return x - (c * adelante - s * lado), y - (s * adelante + c * lado), rumbo
end

local function viaje(self, bidon, destino)
    local lado = Acarreo.lado
    local p = bidon:getPuntosAgarre()[1]
    tarea(self, 'voy a por el ' .. bidon:getNombre())
    self:setGarra(lado, 1)
    self:setAlcanzar(lado, nil)
    local x, y, rumbo = sitioPara(self, p.x, p.y)
    self:setIrA(x, y, rumbo)
    esperar(function() return self:getHaLlegado() end)
    self:setMirarA(p.x, p.y, p.z)
    -- Bajar la garra abierta al punto de agarre y cerrar.
    tarea(self, 'lo cojo con la garra')
    self:setAlcanzar(lado, p.x, p.y, p.z)
    esperar(function() return self:getGarraLista(lado) end)
    if os.getenv('ACARREO_DEPURAR') then
        local gx, gy, gz = self:getPuntoGarra(lado)
        local b = self.datos.brazosPesado.Izq
        print(string.format('ACARREO garra en %.2f %.2f %.2f, punto %.2f %.2f %.2f, llega=%s pierna=%.2f h=%.2f c=%.2f m=%.2f robot %.2f %.2f %.2f',
            gx, gy, gz, p.x, p.y, p.z, tostring(b.llega), self.datos.brazosPesado.pierna, b.hombro, b.codo, b.munieca, self.x, self.y, self.rumbo))
    end
    self:setGarra(lado, 0)
    esperar(function() return self:getGarraLista(lado) end)
    self:setCogerConGarra(lado, bidon)
    local adelante = self:getAlcanceGarra(lado)
    self:setAlcanzarEnRobot(lado, adelante, p.z + Acarreo.subir)
    esperar(function() return self:getGarraLista(lado) end)
    if os.getenv('ACARREO_DEPURAR') then
        local gx, gy, gz = self:getPuntoGarra(lado)
        local bx, by, bz = bidon:getPosicion()
        print(string.format('ACARREO subido: garra %.2f %.2f %.2f, bidón %.2f %.2f %.2f', gx, gy, gz, bx, by, bz))
    end
    -- Llevarlo.
    tarea(self, 'lo llevo')
    self:setMirarA(destino[1], destino[2], p.z)
    x, y, rumbo = sitioPara(self, destino[1], destino[2])
    self:setIrA(x, y, rumbo)
    esperar(function() return self:getHaLlegado() end)
    -- Bajarlo al suelo y soltarlo.
    tarea(self, 'lo dejo')
    self:setAlcanzar(lado, destino[1], destino[2], p.z)
    esperar(function() return self:getGarraLista(lado) end)
    self:setGarra(lado, 1)
    esperar(function() return self:getGarraLista(lado) end)
    self:setSoltarDeGarra(lado)
    print(string.format('ROBOT GRANDE dejo el %s en %.1f, %.1f', bidon:getNombre(), destino[1], destino[2]))
    if os.getenv('ACARREO_DEPURAR') then
        local x, y, z = bidon:getPosicion()
        local izq, der = self:getRodadoOrugas()
        print(string.format('ACARREO bidón en el suelo en %.2f %.2f %.2f; orugas rodadas izq %.2f m, der %.2f m', x, y, z, izq, der))
    end
    self:setAlcanzar(lado, nil)
    self:setMirarA(nil)
    self:setRetroceder(1.0)
    esperar(function() return self:getHaLlegado() end)
end

function Acarreo:onLoad()
    local d = self.datos.acarreo
    d.reloj = 0
end

function Acarreo:onUpdate(dt)
    local d = self.datos.acarreo
    if not d.bidon then
        return
    end
    if not d.vuelta then
        d.vuelta = coroutine.create(function()
            local k = 1
            while true do
                k = k % #Acarreo.sitios + 1
                viaje(self, d.bidon, Acarreo.sitios[k])
                local hasta = d.reloj + Acarreo.espera
                esperar(function() return d.reloj >= hasta end)
            end
        end)
    end
    d.reloj = d.reloj + dt
    local bien, fallo = coroutine.resume(d.vuelta)
    if not bien then
        error(fallo)
    end
end

--- Le da el bidón con el que trabaja (está en el primer sitio).
function Robot:setBidonDeAcarreo(bidon)
    self.datos.acarreo.bidon = bidon
end

GestorRobots.registrarEspecializacion('acarreo', Acarreo)
return Acarreo
