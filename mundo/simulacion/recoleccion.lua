--- Recolección en yacimientos: mandar grupos a las minas, recolectar cada día y entregar.
--
-- Nada sale solo de un yacimiento: hay que mandar un grupo a recolectar
-- (`recolectar`). Va a la mina (fase 'ida'), recolecta cada día F1 sin pasar
-- de su carga (F2) ni de lo que queda (F3, F4) ('recolectando'), y vuelve
-- ('vuelta', misión 'regreso') al llenarse, al agotarse la mina, al perder una
-- batalla o al retirarlo. Entrega al llegar a su ciudad o su campamento. Cada
-- mina tiene una reserva finita (F5): agotada, se cierra (F6); a medias y sin
-- nadie, se recupera (F7). Solo se guardan las tocadas: `e.minas[id] = {
-- queda, agotadaHasta }` (sin entrada, está llena y abierta).
--
-- Módulo de `mundo/simulacion.lua`: `Recoleccion.instalar(Simulacion)` cuelga sus
-- funciones y `Simulacion.recoleccion` (las reglas) de la clase, así que la API
-- pública no cambia. La IA de los NPC que decide a quién mandar sigue en simulacion.lua.
-- Diseño en diseno/recoleccion-y-batallas.md. Solo datos y sin LÖVE.

local Ayudas = require('mundo.simulacion.ayudas')
local Armamento = require('mundo.simulacion.armamento')

local ordenadas = Ayudas.ordenadas
local esCiudad = Ayudas.esCiudad
local cargaDe = Ayudas.cargaDe
local prepararCombate = Ayudas.prepararCombate

local Recoleccion = {}

-- Se fija en `instalar`: la clase, para leer `Simulacion.recoleccion`, `Simulacion.nivel`...
local Simulacion

--- Reglas de la recolección (los números F1 a F12 del diseño).
Recoleccion.reglas = {
    -- F1: unidades al día por punto de trabajo. 26-nov (aviones): 0,03 -> 0,5,
    -- para que 15 robots llenen un avión (unas 77 t) en unos 10 días.
    kRitmo = 0.5,
    trabajo = { soldados = 1, lanzacohetes = 2 }, -- F1
    carga = { soldados = 0.3, lanzacohetes = 5 }, -- F2
    ventajaTerritorio = 1.25, -- F1: solo para los recolectores de la nación dueña de la celda
    reservaBase = { metal = 250, petroleo = 250, comida = 250, oro = 60 }, -- F5: × riqueza
    enfriamientoBase = 20, -- F6: días cerrada = enfriamientoBase + enfriamientoRiqueza × riqueza
    enfriamientoRiqueza = 10,
    regeneracion = 0.01, -- F7: parte de la reserva que recupera al día una mina a medias sin nadie
    mantenimientoCampamento = 0.5, -- petróleo al día de cada campamento terminado (3.3)
    avisoDias = 1, -- aviso de un ataque que llega en estos días o menos (3.8)
    -- IA de los NPC (3.10).
    diasReserva = 20, -- F9: reserva objetivo = consumo diario × diasReserva
    mediaConsumo = 0.1, -- peso del día en la media del consumo y de lo recolectado (unos 10 días)
    minimoGrupo = 10, -- el NPC no manda a recolectar a menos soldados
    umbralAtaque = 1.6, -- F12: ataca si poder propio ≥ poder recolectores × (umbralAtaque − agresividad)
    umbralRetirar = 0.8, -- retira si poder recolectores < poder atacante × (umbralRetirar + prudencia)
    reservaGuerra = 1.5, -- con una guerra abierta la guarnición mínima (F9 de ejercitos) se multiplica así
    diasLlamada = 3, -- con la capital atacada, llama a casa a los grupos que lleguen en estos días
}

--- Reserva de un yacimiento (F5): riqueza × reservaBase[tipo].
function Recoleccion.reservaMina(d)
    return d.riqueza * Simulacion.recoleccion.reservaBase[d.tipo]
end

--- Lo que queda en una mina, hasta qué día está cerrada (0 si abierta) y su reserva.
function Recoleccion:estadoMina(d)
    local m = self.estado.minas[d.id]
    local reserva = Simulacion.reservaMina(d)
    if not m then
        return reserva, 0, reserva
    end
    return m.queda, m.agotadaHasta or 0, reserva
end

--- ¿Está cerrada (agotada y enfriándose) la mina?
function Recoleccion:minaCerrada(d)
    local m = self.estado.minas[d.id]
    return m ~= nil and (m.agotadaHasta or 0) > self.estado.dia
end

--- Vuelve a la mina lo que no se llevó nadie (sin pasar de su reserva).
function Recoleccion:devolverAMina(d, cantidad)
    local e = self.estado
    local m = e.minas[d.id]
    if not m or cantidad <= 0 then
        return
    end
    m.queda = math.min(Simulacion.reservaMina(d), m.queda + cantidad)
end

--- Trabajo de un grupo (F1): lo sano que lleva.
function Recoleccion.trabajo(g)
    local t = Simulacion.recoleccion.trabajo
    return g.soldados * t.soldados + (g.lanzacohetes or 0) * t.lanzacohetes
end

--- Ritmo de recolección de un grupo en el yacimiento `d` (F1).
function Recoleccion:ritmoRecoleccion(g, d)
    local reglas = Simulacion.recoleccion
    local ventaja = self:duenoDeposito(d) == g.nacion and reglas.ventajaTerritorio or 1
    local minas = Simulacion.nivel(self:nivelCapital(g.nacion)).minas
    return reglas.kRitmo * Simulacion.trabajo(g) * minas * ventaja
end

--- ¿Puede salir de aquí (y entregar aquí) un grupo de recolección? Una
-- ciudad o un campamento terminado.
local function puestoDeAcopio(s)
    return esCiudad(s) or (s.tipo == 'campamento' and s.progreso >= 1)
end

--- Grupos que recolectan ahora en la mina `id` (en orden de id).
function Recoleccion:recolectoresEn(id)
    local out = {}
    for _, g in ipairs(self:gruposConMision('recolectar')) do
        if g.fase == 'recolectando' and g.yacimiento == id then
            out[#out + 1] = g
        end
    end
    return out
end

--- Manda un grupo a recolectar al yacimiento `yacimientoId` desde una ciudad o
-- un campamento propio (3.1). La misma orden para un NPC y para un jugador.
-- Se lleva munición del polvorín (`municion`: tabla, días o nil para
-- `dotacion.recolectar`; ver municion.lua). Sin combustible no salen
-- vehículos. `modelos` (modelo -> cantidad) elige qué modelos salen; sin él,
-- en proporción a lo que hay. Devuelve el id del grupo o false (la mina no
-- existe o está cerrada, el sitio no es suyo, no hay camino o no sale nadie).
function Recoleccion:recolectar(nid, desdeId, yacimientoId, soldados, lanzacohetes, municion, modelos)
    local e = self.estado
    local n = e.naciones[nid]
    local desde = self:sitio(desdeId)
    local d = e.depositos[yacimientoId]
    if not (n and desde and d) or desde.nacion ~= nid or not puestoDeAcopio(desde) then
        return false, 'origen'
    end
    if self:minaCerrada(d) then
        return false, 'minaCerrada'
    end
    local pide = type(modelos) == 'table' and modelos or nil
    if pide then
        lanzacohetes = lanzacohetes or Armamento.pedidas(pide, 'lanzacohetes')
    end
    soldados = math.max(0, math.min(desde.soldados or 0, math.floor(soldados or 0)))
    local llevan = math.max(0, math.min(desde.lanzacohetes or 0, math.floor(lanzacohetes or 0)))
    if n.sinCombustible then
        llevan = 0
    end
    if soldados + llevan < 1 then
        return false, 'sinTropas'
    end
    local ruta = self:trazar(desde.x, desde.y, d.x, d.y)
    if not ruta then
        return false, 'sinCamino'
    end
    desde.soldados = desde.soldados - soldados
    desde.lanzacohetes = desde.lanzacohetes or 0
    local lanzacohetesPor = Armamento.sacar(desde, 'lanzacohetes', llevan, pide)
    local gid = e.siguienteGrupo
    e.siguienteGrupo = gid + 1
    local g = {
        id = gid,
        nacion = nid,
        mision = 'recolectar',
        fase = 'ida',
        desde = desde.id,
        origen = desde.id,
        yacimiento = d.id,
        carga = 0,
        tipoCarga = d.tipo,
        destinoX = d.x,
        destinoY = d.y,
        x = desde.x,
        y = desde.y,
        antesX = desde.x,
        antesY = desde.y,
        ruta = ruta,
        largo = Simulacion.largoRuta(ruta),
        recorrido = 0,
        antesRecorrido = 0,
        soldados = soldados,
        lanzacohetes = 0,
    }
    Armamento.meterPor(g, 'lanzacohetes', lanzacohetesPor)
    prepararCombate(self, g)
    e.grupos[gid] = g
    self:dotar(g, desde, municion)
    return gid
end

--- Capacidad de carga de un grupo (F2): lo sano que lleva.
function Recoleccion.capacidad(g)
    -- Desde los aviones (26-nov): lo que cabe en sus aviones (1 unidad = 1 t).
    return Simulacion.Aviones.capacidadCarga(g)
end

--- Entrega la carga de un grupo que llega a `casa` (3.1.8): metal y petróleo
-- al almacén, oro como dinero (× precioOro), comida al granero de la ciudad
-- (la de `casa` o, si es un campamento, la propia más cercana) hasta su tope.
function Recoleccion:entregarCarga(g, casa)
    local carga = cargaDe(g)
    if carga <= 0 or not g.tipoCarga then
        return
    end
    local n = self.estado.naciones[g.nacion]
    local tipo = g.tipoCarga
    if tipo == 'comida' then
        local c = esCiudad(casa) and casa or self:ciudadDuena(g.nacion, casa.x, casa.y)
        if c then
            c.comida = math.min(Simulacion.granero(c), (c.comida or 0) + carga)
        end
    elseif tipo == 'oro' then
        self:ingresar(n, 'dinero', carga * Simulacion.yacimientos.precioOro)
    else
        self:ingresar(n, tipo, carga)
    end
    if n.recolectado then
        n.recolectado[tipo] = (n.recolectado[tipo] or 0) + carga * Simulacion.recoleccion.mediaConsumo
    end
    g.carga = 0
end

--- Cierra una mina agotada (F6) y manda a casa a los que estaban en ella.
function Recoleccion:cerrarMina(d, grupos)
    local e = self.estado
    local reglas = Simulacion.recoleccion
    e.minas[d.id] =
        { queda = 0, agotadaHasta = e.dia + reglas.enfriamientoBase + reglas.enfriamientoRiqueza * d.riqueza }
    local avisa = false
    for _, g in ipairs(grupos) do
        avisa = avisa or (e.naciones[g.nacion] and e.naciones[g.nacion].jugador) or false
        self:volver(g)
    end
    if avisa then
        self:noticia(
            string.format(
                'Se agota %s %s: cerrada %d días',
                Simulacion.recursos[d.tipo].articulo,
                Simulacion.recursos[d.tipo].nombre,
                e.minas[d.id].agotadaHasta - e.dia
            ),
            { 0.85, 0.8, 0.6 }
        )
    end
end

--- Un día de recolección, después de mover a todos y de las batallas: cada
-- grupo que está en su mina recolecta F3 (repartido con F4 si no llega para
-- todos) y vuelve si se llena o si la agota. Después, las minas a medias sin
-- nadie se recuperan (F7) y las cerradas cuyo plazo acabó vuelven llenas.
function Recoleccion:recolectarDia()
    local e = self.estado
    local reglas = Simulacion.recoleccion
    local porMina, ids = {}, {}
    for _, g in ipairs(self:gruposOrdenados()) do
        if g.mision == 'recolectar' and g.fase == 'recolectando' and not g.batalla then
            local grupos = porMina[g.yacimiento]
            if not grupos then
                grupos = {}
                porMina[g.yacimiento] = grupos
                ids[#ids + 1] = g.yacimiento
            end
            grupos[#grupos + 1] = g
        end
    end
    table.sort(ids)
    local tocadas = {}
    for _, id in ipairs(ordenadas(e.batallas)) do
        local b = e.batallas[id]
        if b.lugar.tipo == 'mina' then
            tocadas[b.lugar.id] = true
        end
    end
    for _, id in ipairs(ids) do
        local d = e.depositos[id]
        local grupos = porMina[id]
        if not d or self:minaCerrada(d) then
            for _, g in ipairs(grupos) do
                self:volver(g)
            end
        elseif not tocadas[id] then
            tocadas[id] = true
            local queda = self:estadoMina(d)
            local ritmos, suma = {}, 0
            for k, g in ipairs(grupos) do
                ritmos[k] = self:ritmoRecoleccion(g, d)
                suma = suma + ritmos[k]
            end
            -- F4: si no llega para todos, se reparte por trabajo; el sobrante
            -- de redondeo, al de id menor.
            local partes = {}
            if suma > queda then
                local resto = queda
                for k = #grupos, 2, -1 do
                    partes[k] = queda * ritmos[k] / suma
                    resto = resto - partes[k]
                end
                partes[1] = resto
            else
                partes = ritmos
            end
            local total = 0
            for k, g in ipairs(grupos) do
                local capacidad = Simulacion.capacidad(g)
                g.carga = math.min(cargaDe(g), capacidad)
                local hoy = math.max(0, math.min(ritmos[k], capacidad - g.carga, partes[k]))
                g.carga = g.carga + hoy
                total = total + hoy
            end
            queda = queda - total
            if queda <= 1e-9 then
                self:cerrarMina(d, grupos)
            else
                local m = e.minas[id] or {}
                m.queda = queda
                e.minas[id] = m
                for k, g in ipairs(grupos) do
                    -- Lleno, o sin nada sano que recolecte: a casa.
                    if g.carga >= Simulacion.capacidad(g) - 1e-9 or ritmos[k] <= 0 then
                        -- Lleno: a entregar y, con su avión, otra vez aquí.
                        if ritmos[k] > 0 then
                            g.ciclo = id
                        end
                        self:volver(g)
                    end
                end
            end
        end
    end
    for _, id in ipairs(ordenadas(e.minas)) do
        local m = e.minas[id]
        local d = e.depositos[id]
        if not d then
            e.minas[id] = nil
        elseif m.agotadaHasta then
            if m.agotadaHasta <= e.dia then
                e.minas[id] = nil
            end
        elseif not tocadas[id] then
            local reserva = Simulacion.reservaMina(d)
            m.queda = m.queda + reglas.regeneracion * reserva
            if m.queda >= reserva then
                e.minas[id] = nil
            end
        end
    end
end

Recoleccion.puestoDeAcopio = puestoDeAcopio

local publicas = {
    'reservaMina',
    'estadoMina',
    'minaCerrada',
    'devolverAMina',
    'trabajo',
    'ritmoRecoleccion',
    'recolectoresEn',
    'recolectar',
    'capacidad',
    'entregarCarga',
    'cerrarMina',
    'recolectarDia',
}

--- Cuelga de la clase Simulacion las funciones de recolección y sus reglas (`Simulacion.recoleccion`).
function Recoleccion.instalar(clase)
    Simulacion = clase
    clase.recoleccion = Recoleccion.reglas
    clase.puestoDeAcopio = Recoleccion.puestoDeAcopio
    for _, nombre in ipairs(publicas) do
        clase[nombre] = Recoleccion[nombre]
    end
end

return Recoleccion
