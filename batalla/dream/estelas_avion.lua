-- Estelas de condensación de las puntas de las alas del avión de carga.
--
-- Cómo pasa de verdad: cada punta de ala deja un torbellino; cuando el ala
-- sustenta mucho (despegue, aproximación con flaps, giros cerrados) la
-- presión dentro del torbellino baja tanto que el vapor del aire se condensa
-- y se ve un hilo blanco que nace en la punta, se abre en un par de segundos
-- y se disuelve. Por eso aquí la intensidad sale del coeficiente de
-- sustentación que calcula vueloAvion.lua (`d.cl`): a la de crucero (~0,7)
-- no hay estela; con flaps en la final (~1,7) se ve entera.
--
-- Se dibujan con la cinta de vapor de batalla/dream/efectos.lua (sombreador
-- `vapor`): tramos fijos cada pocos metros y una cabeza que llega hasta la
-- punta del ala en cada cuadro.

local EstelasAvion = {}
EstelasAvion.__index = EstelasAvion

-- Puntas del ala en ejes del avión (metros; x al morro, y a la izquierda,
-- z arriba): borde de salida de la punta (tools/blender/avion_carga.py,
-- ALA_PUNTA_Y y la última sección de ALA).
EstelasAvion.puntas = { { -15.1, 36.0, 7.25 }, { -15.1, -36.0, 7.25 } }
EstelasAvion.clSin = 0.75 -- sin estela por debajo de este CL
EstelasAvion.clLlena = 1.45 -- estela entera desde este CL
EstelasAvion.paso = 6 -- m entre tramos fijos
EstelasAvion.velocidadMinima = 30 -- m/s

local PX = 10 -- px del juego por metro

function EstelasAvion.nuevas()
    local self = setmetatable({}, EstelasAvion)
    self.estelas = {}
    for k = 1, #EstelasAvion.puntas do
        self.estelas[k] = { semilla = k * 1.7, escala = 0, ultimo = nil }
    end
    return self
end

local function intensidadDe(d)
    if d.enTierra or not d.cl or d.fase == 'fuera' then
        return 0
    end
    local V = math.sqrt(d.vx * d.vx + d.vy * d.vy + d.vz * d.vz)
    if V < EstelasAvion.velocidadMinima then
        return 0
    end
    local i = (d.cl - EstelasAvion.clSin) / (EstelasAvion.clLlena - EstelasAvion.clSin)
    return math.max(0, math.min(1, i))
end

local function soltar(cinta, e)
    if e.ultimo then
        cinta:soltar(e)
    end
    e.ultimo = nil
end

--- Un cuadro: `avion` es el robot avionCarga, `efectos` el EfectosDream y
-- `reloj` el de las tropas (el mismo que usa el sombreador).
function EstelasAvion:actualizar(avion, efectos, reloj)
    local cinta = efectos and efectos.cintaVapor
    if not cinta then
        return
    end
    local d = avion and avion.datos.vueloAvion
    local m = d and d.matriz
    local intensidad = (m and m[1] and not avion.guardado) and intensidadDe(d) or 0
    for k, e in ipairs(self.estelas) do
        if intensidad <= 0 then
            soltar(cinta, e)
        else
            local p = EstelasAvion.puntas[k]
            local x = m[1] * p[1] + m[2] * p[2] + m[3] * p[3] + m[4]
            local y = m[5] * p[1] + m[6] * p[2] + m[7] * p[3] + m[8]
            local z = m[9] * p[1] + m[10] * p[2] + m[11] * p[3] + m[12]
            -- Al juego: px, con la y al revés (como las luces de la bodega).
            local actual = {
                x = x * PX,
                y = -y * PX,
                z = z * PX,
                nace = reloj,
            }
            local u = e.ultimo
            if not u then
                actual.recorrido = 0
                actual.tx, actual.ty, actual.tz = m[1], -m[5], m[9]
                e.ultimo = actual
                e.escala = intensidad
            else
                local dx, dy, dz = actual.x - u.x, actual.y - u.y, actual.z - u.z
                local largo = math.sqrt(dx * dx + dy * dy + dz * dz)
                if largo > 0 then
                    actual.tx, actual.ty, actual.tz = dx / largo, dy / largo, dz / largo
                else
                    actual.tx, actual.ty, actual.tz = u.tx, u.ty, u.tz
                end
                actual.recorrido = u.recorrido + largo / PX
                -- La intensidad del tramo es la de su punto nuevo (cinta:punto
                -- la toma de e.escala para los dos extremos).
                e.escala = intensidad
                if largo / PX >= EstelasAvion.paso then
                    cinta:tramo(e, u, actual)
                    cinta:cabeza(e, actual, actual)
                    e.ultimo = actual
                else
                    cinta:cabeza(e, u, actual)
                end
            end
        end
    end
end

return EstelasAvion
