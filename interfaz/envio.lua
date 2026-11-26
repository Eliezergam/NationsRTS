-- Envío: la elección sencilla de cuánto llevar a un ataque o a recolectar
-- (modo jugador). Un panel al centro con una fila por tropa (lanzacohetes
-- y soldados) con − y +, lo que hay en la ciudad, y los botones
-- «Atacar» (o «Declarar guerra y atacar», si no hay guerra con el dueño del
-- objetivo) y «Cancelar». Si la simulación no lo acepta, se queda abierto con
-- el motivo.
--
-- El objetivo puede ser un yacimiento (diseno/recoleccion-y-batallas.md):
--   - modo 'recolectar': manda un grupo a recolectar allí; muestra la carga
--     que cabe, lo que saca al día y cuánto tarda (ida, llenarse y vuelta);
--   - modo 'atacar' contra una mina: ataca a los recolectores ajenos; si hay
--     paz con alguno, la simulación declara la guerra al llegar.
--
--   - modo 'sacar' (radial de tu ciudad, «Ejército»): elige qué tropas salen
--     de la ciudad como un ejército parado en ella, listo para moverlo.
--
-- En todos los modos, la fila «Munición» elige los días de batalla que se
-- lleva (la dotación de su misión por defecto, diseno/economia.md F5) y dice
-- cuánto es de cada munición y lo que hay en el polvorín de la ciudad de
-- salida (`sim:polvorin`): lo que no hay, no se lleva.
--
-- Modelos (diseno/catalogo-armamento.md): bajo la fila de lanzacohetes,
-- una línea pequeña dice qué modelos salen («2 BM-21 · 1 Scud-B»).
-- Si no se elige nada, salen los mejores (los de más poder). Con más de un
-- modelo en la ciudad, «Elegir» abre una fila por modelo con − y +. El
-- comando lleva siempre `modelos` (modelo -> cantidad).
--
-- Solo lee la simulación; la orden la manda main.lua con un comando.

local Tema = require('interfaz.tema')
local Acero = require('interfaz.acero')
local Simulacion = require('mundo.simulacion')
local Estandartes = require('mundo.estandartes')

local Envio = {}
Envio.__index = Envio

local NOMBRE_CARGA = { metal = 'metal', petroleo = 'petróleo', comida = 'comida', oro = 'oro' }

local TROPAS = {
    { clave = 'lanzacohetes', nombre = 'Lanzacohetes', paso = 1, vehiculo = true },
    { clave = 'soldados', nombre = 'Soldados', paso = 10 },
}

--- Abre el envío desde la ciudad `desde` (datos de la simulación) contra
-- `objetivo` (una ciudad o una instalación de otra nación, o un yacimiento
-- de `sim:mina`; `nombre`, como se llama en el título, si no es
-- `objetivo.nombre`). `opciones` = { modo = 'atacar' (por defecto) o
-- 'recolectar', sim (para medir el camino a la mina), origenes (otros sitios
-- propios desde donde puede salir, `{ sitio, ... }`: con más de uno, ‹ y ›
-- cambian la salida) }. Un ataque empieza con la mitad de lo que hay; una
-- recolección, con la mitad de los soldados; sacar tropas, con nada.
function Envio.nuevo(desde, objetivo, nombre, opciones)
    local self = setmetatable({}, Envio)
    opciones = opciones or {}
    self.tropas = { TROPAS[1], TROPAS[2] }
    self.abiertos = {} -- tipo -> true: sus modelos, una fila por modelo
    self.objetivo = objetivo
    self.nombre = nombre or objetivo.nombre
    self.modo = opciones.modo or 'atacar'
    self.mina = objetivo.reserva ~= nil -- los de `sim:mina` llevan su reserva
    self.origenes = opciones.origenes or { desde }
    self.indiceOrigen = 1
    for k, s in ipairs(self.origenes) do
        if s == desde then
            self.indiceOrigen = k
        end
    end
    self:usarOrigen(desde)
    -- Días de batalla de munición que se lleva: la dotación de su misión (F5).
    local mision = ({ sacar = 'mover', recolectar = 'recolectar' })[self.modo] or 'atacar'
    self.dias = Simulacion.produccion.dotacion[mision] or 0
    if self.modo == 'sacar' then
        for clave in pairs(self.cantidades) do
            self.cantidades[clave] = 0
        end
    end
    if self.modo == 'recolectar' then
        self.cantidades.lanzacohetes = 0
        -- El camino se mide una vez al abrir (no en cada cuadro).
        local ruta = opciones.sim and opciones.sim:trazar(desde.x, desde.y, objetivo.x, objetivo.y)
        self.viaje = ruta and Simulacion.largoRuta(ruta) / Simulacion.velocidadEjercito or nil
    end
    self.zonas = {}
    self.motivo = nil
    return self
end

--- Sale desde `desde`: lo propuesto vuelve a ser la mitad de lo que hay (de
-- los mejores modelos).
function Envio:usarOrigen(desde)
    self.desde = desde
    self.elegidos = {} -- tipo -> { modelo -> cantidad } si se eligió a mano
    self.cantidades = {
        lanzacohetes = math.floor(self:hay('lanzacohetes') / 2),
        soldados = math.floor(desde.soldados / 2),
    }
    self.motivo = nil
end

--- Lo que hay en la ciudad de cada tropa (los lanzacohetes, en sus
-- plataformas y en su parque: salen primero los del parque).
function Envio:hay(clave)
    if clave == 'lanzacohetes' then
        return (self.desde.lanzacohetes or 0) + (self.desde.parque or 0)
    end
    return self.desde[clave] or 0
end

--- Modelos de `tipo` que hay en la salida, del de más poder al de menos (a
-- igual poder, en orden de catálogo): { { modelo, nombre, hay }, ... }.
function Envio:modelosDisponibles(tipo)
    local cuantos = {}
    local campos = tipo == 'lanzacohetes' and { 'lanzacohetes', 'parque' } or { tipo }
    for _, campo in ipairs(campos) do
        for _, d in ipairs(Simulacion.desglose(self.desde, campo)) do
            cuantos[d.modelo] = (cuantos[d.modelo] or 0) + d.cantidad
        end
    end
    local out = {}
    for k, id in ipairs(Simulacion.Armamento.modelos(tipo)) do
        if (cuantos[id] or 0) > 0 then
            local ficha = Simulacion.fichaModelo(id)
            out[#out + 1] =
                { modelo = id, nombre = ficha.nombre, hay = cuantos[id], poder = ficha.juego.poder, orden = k }
        end
    end
    table.sort(out, function(a, b)
        if a.poder ~= b.poder then
            return a.poder > b.poder
        end
        return a.orden < b.orden
    end)
    return out
end

--- Qué modelos de `tipo` salen con lo elegido: los que se eligieron a mano
-- o, si no, los mejores. Tabla modelo -> cantidad.
function Envio:reparto(tipo)
    local out = {}
    local elegidos = self.elegidos[tipo]
    local quedan = self.cantidades[tipo] or 0
    for _, d in ipairs(self:modelosDisponibles(tipo)) do
        local k = math.min(d.hay, quedan)
        if elegidos then
            k = math.min(d.hay, elegidos[d.modelo] or 0)
        end
        if k > 0 then
            out[d.modelo] = k
            quedan = quedan - k
        end
    end
    return out
end

--- Cambia en `paso` los de `modelo` elegidos a mano (y el total de su tipo).
function Envio:cambiarModelo(tipo, modelo, paso)
    local elegidos = self.elegidos[tipo] or self:reparto(tipo)
    local hay = 0
    for _, d in ipairs(self:modelosDisponibles(tipo)) do
        if d.modelo == modelo then
            hay = d.hay
        end
    end
    elegidos[modelo] = math.max(0, math.min(hay, (elegidos[modelo] or 0) + paso))
    self.elegidos[tipo] = elegidos
    local total = 0
    for _, k in pairs(elegidos) do
        total = total + k
    end
    self.cantidades[tipo] = total
end

--- Lo elegido como unidades para las cuentas de la simulación: { soldados,
-- lanzacohetes, lanzacohetesPor }.
function Envio:unidades()
    local c = self.cantidades
    return {
        soldados = c.soldados,
        lanzacohetes = c.lanzacohetes,
        lanzacohetesPor = self:reparto('lanzacohetes'),
    }
end

--- `modelos` del comando (modelo -> cantidad).
function Envio:modelosComando()
    local out = {}
    for m, k in pairs(self:reparto('lanzacohetes')) do
        out[m] = k
    end
    return out
end

--- «2 BM-21 · 1 Scud-B»: lo que sale de `tipo` (vacío si nada).
function Envio:textoModelos(tipo)
    local partes = {}
    local reparto = self:reparto(tipo)
    for _, d in ipairs(self:modelosDisponibles(tipo)) do
        if reparto[d.modelo] then
            partes[#partes + 1] = Tema.numero(reparto[d.modelo]) .. ' ' .. d.nombre
        end
    end
    return table.concat(partes, ' · ')
end

--- Unidades elegidas, de todas las tropas.
function Envio:total()
    local total = 0
    for _, t in ipairs(self.tropas) do
        total = total + self.cantidades[t.clave]
    end
    return total
end

--- Munición que se llevaría con lo elegido: { quiere = { balas, misiles }
-- (los días elegidos), lleva = (recortado al polvorín), hay = (el
-- polvorín de la ciudad de salida) }.
function Envio:municion(sim)
    local quiere = Simulacion.dotacion(self:unidades(), self.dias)
    local hay = sim:polvorin(self.desde.id) or { balas = 0, misiles = 0 }
    local lleva = {}
    for _, m in ipairs(Simulacion.MUNICIONES) do
        lleva[m] = math.max(0, math.min(hay[m] or 0, math.floor(quiere[m])))
    end
    return { quiere = quiere, lleva = lleva, hay = hay }
end

--- ¿Hay que declarar la guerra al dueño del objetivo antes de atacar? En
-- una mina no: la simulación la declara al llegar (decisión 3 del dueño).
function Envio:haceFaltaGuerra(sim)
    if self.mina or self.modo == 'sacar' then
        return false
    end
    return sim:guerraEntre(self.desde.nacion, self.objetivo.nacion) == nil
end

--- Naciones que recolectan en la mina del objetivo, sin la tuya.
function Envio:recolectoresAjenos(sim)
    local mina = sim:mina(self.objetivo.id)
    local out = {}
    for _, r in ipairs(mina and mina.recolectores or {}) do
        if r.nacion ~= self.desde.nacion then
            out[#out + 1] = r.nacion
        end
    end
    return out
end

--- ¿Atacar la mina declara la guerra a alguien (recolectores en paz contigo)?
function Envio:declaraGuerraEnMina(sim)
    for _, nid in ipairs(self:recolectoresAjenos(sim)) do
        if not sim:guerraEntre(self.desde.nacion, nid) then
            return true
        end
    end
    return false
end

--- Estimación de una recolección con lo elegido: { capacidad, ritmo (al
-- día), viaje (días de ida), llenar (días en la mina), total (días hasta
-- volver) }. Las mismas fórmulas que la simulación (F1 y F2); el +25 % solo
-- si la tierra de la mina es tuya.
function Envio:estimacion(sim)
    local reglas = Simulacion.recoleccion
    local grupo = self:unidades()
    local capacidad = Simulacion.capacidad(grupo)
    local mina = sim:mina(self.objetivo.id)
    local ventaja = mina and mina.dueno == self.desde.nacion and reglas.ventajaTerritorio or 1
    local minas = Simulacion.nivel(sim:nivelCapital(self.desde.nacion)).minas
    local ritmo = reglas.kRitmo * Simulacion.trabajo(grupo) * minas * ventaja
    local cabe = math.min(capacidad, mina and mina.queda or capacidad)
    local llenar = ritmo > 0 and cabe / ritmo or 0
    local viaje = self.viaje or 0
    return {
        capacidad = capacidad,
        ritmo = ritmo,
        viaje = viaje,
        llenar = llenar,
        total = viaje * 2 + llenar,
        bonus = ventaja > 1,
    }
end

--- Por qué no se puede atacar al dueño del objetivo (sitio que ya no existe o
-- ya es tuyo, alto el fuego o tregua vigentes), o nil.
function Envio:motivoDiplomatico(sim)
    if self.modo == 'sacar' then
        return nil
    end
    if self.mina then
        local mina = sim:mina(self.objetivo.id)
        if not mina then
            return 'La mina ya no existe'
        end
        if self.modo == 'recolectar' then
            if mina.cerrada then
                return string.format('La mina está cerrada: abre en %d días', mina.diasCerrada)
            end
            if not self.viaje then
                return 'No hay camino por tierra hasta la mina'
            end
            return nil
        end
        if #self:recolectoresAjenos(sim) == 0 then
            return 'No hay recolectores ajenos en la mina'
        end
        return nil
    end
    local objetivo = sim:sitio(self.objetivo.id)
    if not objetivo then
        return 'El objetivo ya no existe'
    end
    if objetivo.nacion == self.desde.nacion then
        return 'Ya es tuyo'
    end
    local otra = sim:nacion(objetivo.nacion)
    local guerra = sim:guerraEntre(self.desde.nacion, objetivo.nacion)
    local dia = sim.estado.dia
    if guerra and guerra.fase == 'calma' and (guerra.faseHasta or 0) > dia then
        return string.format('Alto el fuego con %s hasta el día %d', otra.nombre, guerra.faseHasta)
    end
    local suya = sim:nacion(self.desde.nacion)
    local tregua = suya and suya.treguas and suya.treguas[objetivo.nacion]
    if not guerra and tregua and tregua > dia then
        return string.format('Tregua con %s hasta el día %d', otra.nombre, tregua)
    end
    -- Una bandera solo se ataca si tu territorio toca el suyo.
    local puede, motivo = sim:puedeAtacar(self.desde.nacion, objetivo.id)
    if not puede and motivo == 'sinFrontera' then
        return 'No tienes frontera con ellos'
    end
    return nil
end

--- Por qué no saldría el ataque, o nil si puede salir (lo mismo que mira la
-- simulación, para decirlo antes de mandar).
function Envio:motivoPrevio(sim)
    local diplomatico = self:motivoDiplomatico(sim)
    if diplomatico then
        return diplomatico
    end
    if self:total() < 1 then
        return 'Elige al menos una unidad'
    end
    local n = sim:nacion(self.desde.nacion)
    if n and n.sinCombustible and self.cantidades.lanzacohetes > 0 then
        return 'Sin petróleo no salen lanzacohetes'
    end
    return nil
end

--- Dibuja el panel en el centro de la pantalla.
function Envio:dibujar(sim)
    -- Gris caqui claro con texto negro, como los demás paneles.
    Tema.modoClaro = true
    local ok, fallo = pcall(self.dibujarClaro, self, sim)
    Tema.modoClaro = false
    if not ok then
        error(fallo, 0)
    end
end

function Envio:dibujarClaro(sim)
    local g = love.graphics
    local w, h = g.getDimensions()
    self.zonas = {}
    -- Lo que hay puede haber cambiado (bajas, recuperación): se recorta.
    for _, t in ipairs(self.tropas) do
        self.cantidades[t.clave] = math.max(0, math.min(self.cantidades[t.clave], self:hay(t.clave)))
    end
    local texto = Acero.fuente('cuerpo')
    local negrita = Acero.fuente('cifra')
    local relleno = Tema.px(16)
    local ancho = Tema.px(Tema.compacta() and 480 or 560)
    local fila = Tema.px(48)
    local cabecera = Tema.px(50)
    local recolecta = self.modo == 'recolectar'
    local info = recolecta and (texto:getHeight() + Tema.px(4)) * 3 + Tema.px(8) or 0
    -- Bajo cada fila de vehículos, la línea de sus modelos y, abierta, una
    -- fila por modelo.
    local lineaModelos = Tema.px(28)
    local filaModelo = Tema.px(38)
    local extra = 0
    for _, t in ipairs(self.tropas) do
        if t.vehiculo and self:hay(t.clave) > 0 then
            extra = extra + lineaModelos
            if self.abiertos[t.clave] then
                extra = extra + #self:modelosDisponibles(t.clave) * filaModelo
            end
        end
    end
    local alto = cabecera
        + relleno
        + texto:getHeight()
        + Tema.px(10)
        + (#self.tropas + 1) * fila
        + extra
        + (texto:getHeight() + Tema.px(4)) * 3
        + Tema.px(10)
        + info
        + texto:getHeight() * 2
        + Tema.px(12)
        + Tema.px(44)
        + relleno
    local x, y = math.floor((w - ancho) / 2), math.floor((h - alto) / 2)
    self.rect = { x = x, y = y, w = ancho, h = alto }
    local sacar = self.modo == 'sacar'
    local encabezado = (recolecta and 'Recolectar en ' or 'Atacar a ') .. self.nombre
    if sacar then
        encabezado = 'Sacar tropas de ' .. self.nombre
    end
    local _, _, _, _, cierre = Acero.panel(x, y, ancho, alto, { titulo = encabezado, cerrar = true })
    if cierre then
        self.zonas[#self.zonas + 1] =
            { x = cierre.x, y = cierre.y, w = cierre.w, h = cierre.h, accion = { tipo = 'cancelar' } }
    end
    local n = sim:nacion(self.desde.nacion)
    if n then
        Tema.color(n.color)
        g.rectangle('fill', x + Tema.px(12), y + cabecera + Tema.px(3), ancho - Tema.px(24), Tema.px(3))
    end
    local cx, cy = x + relleno + Tema.px(4), y + cabecera + relleno
    local cw = ancho - relleno * 2 - Tema.px(8)
    g.setFont(texto)
    Tema.color('textoHudTenue')
    local desdeNombre = self.desde.nombre or Simulacion.nombreInstalacion(sim, self.desde)
    local anchoFlechas = 0
    if #self.origenes > 1 then
        -- ‹ › a la derecha: cambia el sitio de salida.
        local lado = Tema.px(30)
        anchoFlechas = lado * 2 + Tema.px(12)
        local fy = cy + math.floor((texto:getHeight() - lado) / 2)
        local ax = cx + cw - lado * 2 - Tema.px(6)
        Tema.boton({ texto = '‹', tipo = 'oscuro' }, ax, fy, lado, lado, true)
        Tema.boton({ texto = '›', tipo = 'oscuro' }, ax + lado + Tema.px(6), fy, lado, lado, true)
        self.zonas[#self.zonas + 1] = { x = ax, y = fy, w = lado, h = lado, accion = { tipo = 'origen', paso = -1 } }
        self.zonas[#self.zonas + 1] =
            { x = ax + lado + Tema.px(6), y = fy, w = lado, h = lado, accion = { tipo = 'origen', paso = 1 } }
    end
    g.setFont(texto)
    Tema.color('textoHudTenue')
    local intro = 'Desde ' .. desdeNombre .. ': elige cuánto llevar'
    if self.modo == 'sacar' then
        intro = 'Elige qué sale de ' .. desdeNombre .. ' como ejército'
    end
    g.print(Tema.cortar(texto, intro, cw - anchoFlechas), cx, cy)
    cy = cy + texto:getHeight() + Tema.px(10)
    local lado = Tema.px(40)
    for _, t in ipairs(self.tropas) do
        local cantidad = self.cantidades[t.clave]
        local hay = self:hay(t.clave)
        local my = cy + math.floor((fila - lado) / 2)
        g.setFont(texto)
        Tema.color('textoHud')
        g.print(t.nombre, cx, cy + math.floor((fila - texto:getHeight()) / 2))
        -- − cantidad + y «de N».
        local deTexto = 'de ' .. Tema.numero(hay)
        local anchoDe = texto:getWidth('de 0 000')
        local bx = cx + cw - anchoDe - Tema.px(12) - lado * 2 - Tema.px(80)
        local menos = { texto = '−', tipo = 'oscuro', activo = cantidad > 0 }
        local mas = { texto = '+', tipo = 'oscuro', activo = cantidad < hay }
        Tema.boton(menos, bx, my, lado, lado, true)
        self.zonas[#self.zonas + 1] = {
            x = bx,
            y = my,
            w = lado,
            h = lado,
            accion = { tipo = 'cambiar', clave = t.clave, paso = -t.paso },
        }
        g.setFont(negrita)
        Tema.color('textoHud')
        g.printf(
            Tema.numero(cantidad),
            bx + lado,
            cy + math.floor((fila - negrita:getHeight()) / 2),
            Tema.px(80),
            'center'
        )
        local mx = bx + lado + Tema.px(80)
        Tema.boton(mas, mx, my, lado, lado, true)
        self.zonas[#self.zonas + 1] = {
            x = mx,
            y = my,
            w = lado,
            h = lado,
            accion = { tipo = 'cambiar', clave = t.clave, paso = t.paso },
        }
        g.setFont(texto)
        Tema.color('textoHudTenue')
        g.print(deTexto, cx + cw - anchoDe, cy + math.floor((fila - texto:getHeight()) / 2))
        cy = cy + fila
        if t.vehiculo and hay > 0 then
            cy = self:dibujarModelos(t.clave, cx, cy, cw, lineaModelos, filaModelo)
        end
    end
    cy = self:dibujarMunicion(sim, cx, cy, cw, fila, lado)
    cy = cy + Tema.px(10)
    if recolecta then
        -- Lo que cabe, lo que saca al día y cuánto tarda (F1 y F2).
        local e = self:estimacion(sim)
        local lineas = {
            {
                'Carga',
                Estandartes.cifraCarga(e.capacidad) .. ' de ' .. (NOMBRE_CARGA[self.objetivo.tipo] or ''),
            },
            {
                'Recolecta al día',
                (string.format('%.2f', e.ritmo):gsub('%.', ',')) .. (e.bonus and ' · +25 % tu tierra' or ''),
            },
            {
                'Tiempo estimado',
                string.format(
                    '%d días (ida %d, llenar %d, vuelta %d)',
                    math.ceil(e.viaje) * 2 + math.ceil(e.llenar),
                    math.ceil(e.viaje),
                    math.ceil(e.llenar),
                    math.ceil(e.viaje)
                ),
            },
        }
        for _, l in ipairs(lineas) do
            g.setFont(texto)
            Tema.color('textoHudTenue')
            g.print(l[1], cx, cy)
            g.setFont(negrita)
            Tema.color('textoHud')
            local valor = Tema.cortar(negrita, l[2], cw - texto:getWidth(l[1]) - Tema.px(10))
            g.print(valor, cx + cw - negrita:getWidth(valor), cy - Tema.px(1))
            cy = cy + texto:getHeight() + Tema.px(4)
        end
        cy = cy + Tema.px(8)
    end
    -- Motivo (si el último intento falló o si ya se sabe que no saldría).
    local motivo = self.motivo or self:motivoPrevio(sim)
    if motivo then
        g.setFont(texto)
        Tema.color('rojoTexto')
        g.printf(motivo, cx, cy, cw, 'left')
    end
    cy = cy + texto:getHeight() * 2 + Tema.px(12)
    local textoAtacar = self:haceFaltaGuerra(sim) and 'Declarar guerra y atacar' or 'Atacar'
    if sacar then
        textoAtacar = 'Formar ejército'
    elseif recolecta then
        textoAtacar = 'Recolectar'
    elseif self.mina and self:declaraGuerraEnMina(sim) then
        textoAtacar = 'Atacar (declara la guerra)'
    end
    local atacar = {
        texto = textoAtacar,
        tipo = (recolecta or sacar or textoAtacar == 'Atacar') and 'principal' or 'peligro',
        activo = self:motivoPrevio(sim) == nil,
    }
    local cancelar = { texto = 'Cancelar', tipo = 'secundario' }
    local anchoA = math.max(Tema.px(140), Tema.anchoBoton(atacar))
    local anchoC = math.max(Tema.px(120), Tema.anchoBoton(cancelar))
    local bh = Tema.px(44)
    local ax = cx + cw - anchoA
    local ccx = ax - Tema.px(8) - anchoC
    Tema.boton(cancelar, ccx, cy, anchoC, bh)
    Tema.boton(atacar, ax, cy, anchoA, bh)
    self.zonas[#self.zonas + 1] = { x = ccx, y = cy, w = anchoC, h = bh, accion = { tipo = 'cancelar' } }
    if atacar.activo then
        self.zonas[#self.zonas + 1] = { x = ax, y = cy, w = anchoA, h = bh, accion = { tipo = 'atacar' } }
    end
    self.botonAtacar = { x = ax, y = cy, w = anchoA, h = bh }
end

--- Línea pequeña con los modelos de `tipo` que salen y «Elegir» (con más
-- de un modelo) y, si se abrió, una fila por modelo con − y +. Devuelve la
-- `y` siguiente.
function Envio:dibujarModelos(tipo, cx, cy, cw, alto, filaModelo)
    local g = love.graphics
    local chica = Acero.fuente('etiqueta', 14)
    local disponibles = self:modelosDisponibles(tipo)
    local botonW = 0
    if #disponibles > 1 then
        local boton = { texto = self.abiertos[tipo] and 'Listo' or 'Elegir', tipo = 'secundario' }
        botonW = math.max(Tema.px(84), Tema.anchoBoton(boton, true))
        local by = cy + Tema.px(1)
        Tema.boton(boton, cx + cw - botonW, by, botonW, alto - Tema.px(4), true)
        self.zonas[#self.zonas + 1] = {
            x = cx + cw - botonW,
            y = by,
            w = botonW,
            h = alto - Tema.px(4),
            accion = { tipo = 'abrir', clave = tipo },
        }
    end
    local lista = self:textoModelos(tipo)
    if lista == '' then
        lista = 'no sale ninguno'
    end
    lista = (self.elegidos[tipo] and 'Salen ' or 'Salen los mejores: ') .. lista
    g.setFont(chica)
    Tema.color('textoHudTenue')
    local libre = cw - botonW - Tema.px(10) - Tema.px(12)
    g.print(Tema.cortar(chica, lista, libre), cx + Tema.px(12), cy + math.floor((alto - chica:getHeight()) / 2))
    cy = cy + alto
    if not self.abiertos[tipo] then
        return cy
    end
    local texto = Acero.fuente('cuerpo')
    local negrita = Acero.fuente('cifra')
    local lado = Tema.px(32)
    local reparto = self:reparto(tipo)
    for _, d in ipairs(disponibles) do
        local cantidad = reparto[d.modelo] or 0
        local my = cy + math.floor((filaModelo - lado) / 2)
        g.setFont(texto)
        Tema.color('textoHud')
        g.print(d.nombre, cx + Tema.px(12), cy + math.floor((filaModelo - texto:getHeight()) / 2))
        local anchoDe = texto:getWidth('de 0 000')
        local bx = cx + cw - anchoDe - Tema.px(12) - Tema.px(40) * 2 - Tema.px(80) + (Tema.px(40) - lado)
        Tema.boton({ texto = '−', tipo = 'oscuro', activo = cantidad > 0 }, bx, my, lado, lado, true)
        self.zonas[#self.zonas + 1] = {
            x = bx,
            y = my,
            w = lado,
            h = lado,
            accion = { tipo = 'modelo', clave = tipo, modelo = d.modelo, paso = -1 },
        }
        g.setFont(negrita)
        Tema.color('textoHud')
        g.printf(
            Tema.numero(cantidad),
            bx + lado,
            cy + math.floor((filaModelo - negrita:getHeight()) / 2),
            Tema.px(80),
            'center'
        )
        local mx = bx + lado + Tema.px(80)
        Tema.boton({ texto = '+', tipo = 'oscuro', activo = cantidad < d.hay }, mx, my, lado, lado, true)
        self.zonas[#self.zonas + 1] = {
            x = mx,
            y = my,
            w = lado,
            h = lado,
            accion = { tipo = 'modelo', clave = tipo, modelo = d.modelo, paso = 1 },
        }
        g.setFont(texto)
        Tema.color('textoHudTenue')
        g.print('de ' .. Tema.numero(d.hay), cx + cw - anchoDe, cy + math.floor((filaModelo - texto:getHeight()) / 2))
        cy = cy + filaModelo
    end
    return cy
end

--- Fila «Munición» (días de batalla, con − y +) y, debajo, cuánto es de
-- cada una y lo que hay en el polvorín. Devuelve la `y` siguiente.
function Envio:dibujarMunicion(sim, cx, cy, cw, fila, lado)
    local g = love.graphics
    local texto = Acero.fuente('cuerpo')
    local negrita = Acero.fuente('cifra')
    g.setFont(texto)
    Tema.color('textoHud')
    g.print('Munición', cx, cy + math.floor((fila - texto:getHeight()) / 2))
    local anchoDe = texto:getWidth('de 0 000')
    local bx = cx + cw - anchoDe - Tema.px(12) - lado * 2 - Tema.px(80)
    local my = cy + math.floor((fila - lado) / 2)
    Tema.boton({ texto = '−', tipo = 'oscuro', activo = self.dias > 0 }, bx, my, lado, lado, true)
    self.zonas[#self.zonas + 1] = { x = bx, y = my, w = lado, h = lado, accion = { tipo = 'dias', paso = -1 } }
    g.setFont(negrita)
    Tema.color('textoHud')
    g.printf(tostring(self.dias), bx + lado, cy + math.floor((fila - negrita:getHeight()) / 2), Tema.px(80), 'center')
    local mx = bx + lado + Tema.px(80)
    Tema.boton({ texto = '+', tipo = 'oscuro', activo = self.dias < 15 }, mx, my, lado, lado, true)
    self.zonas[#self.zonas + 1] = { x = mx, y = my, w = lado, h = lado, accion = { tipo = 'dias', paso = 1 } }
    g.setFont(texto)
    Tema.color('textoHudTenue')
    g.print(self.dias == 1 and 'día' or 'días', cx + cw - anchoDe, cy + math.floor((fila - texto:getHeight()) / 2))
    cy = cy + fila
    -- Lo que es, y lo que hay en el polvorín (en rojo lo que no alcanza).
    local m = self:municion(sim)
    local partes, faltan = {}, {}
    local nombres = { balas = 'balas', misiles = 'misiles' }
    for _, tipo in ipairs(Simulacion.MUNICIONES) do
        if m.quiere[tipo] > 0 then
            partes[#partes + 1] = Tema.numero(m.lleva[tipo]) .. ' ' .. nombres[tipo]
            if m.lleva[tipo] < math.floor(m.quiere[tipo]) then
                faltan[#faltan + 1] = nombres[tipo]
            end
        end
    end
    local lleva = #partes > 0 and ('Lleva ' .. table.concat(partes, ' · ')) or 'Sin tropas no lleva munición'
    if self.dias == 0 and self:total() > 0 then
        lleva = 'Sale sin munición: no podrá disparar'
    end
    g.setFont(texto)
    Tema.color(self.dias == 0 and self:total() > 0 and 'rojoTexto' or 'textoHud')
    g.print(Tema.cortar(texto, lleva, cw), cx, cy)
    cy = cy + texto:getHeight() + Tema.px(4)
    local hay = string.format(
        'Polvorín de la ciudad: %s balas · %s misiles',
        Tema.numero(m.hay.balas or 0),
        Tema.numero(m.hay.misiles or 0)
    )
    Tema.color('textoHudTenue')
    g.print(Tema.cortar(texto, hay, cw), cx, cy)
    cy = cy + texto:getHeight() + Tema.px(4)
    if #faltan > 0 then
        Tema.color('rojoTexto')
        local corto = string.format(
            'No hay para %d %s de %s: lleva lo que hay',
            self.dias,
            self.dias == 1 and 'día' or 'días',
            table.concat(faltan, ' ni de ')
        )
        g.print(Tema.cortar(texto, corto, cw), cx, cy)
    end
    return cy + texto:getHeight() + Tema.px(4)
end

--- Clic. Devuelve nil si cayó fuera del panel; si no, 'atacar', 'cancelar'
-- o 'nada' (los − y + se aplican aquí).
function Envio:pulsar(x, y)
    local r = self.rect
    if not (r and Tema.dentro(x, y, r.x, r.y, r.w, r.h)) then
        return nil
    end
    for _, z in ipairs(self.zonas) do
        if Tema.dentro(x, y, z.x, z.y, z.w, z.h) then
            local a = z.accion
            if a.tipo == 'origen' then
                local n = #self.origenes
                self.indiceOrigen = (self.indiceOrigen - 1 + a.paso) % n + 1
                self:usarOrigen(self.origenes[self.indiceOrigen])
                return 'nada'
            end
            if a.tipo == 'dias' then
                self.dias = math.max(0, math.min(15, self.dias + a.paso))
                return 'nada'
            end
            if a.tipo == 'cambiar' then
                local elegidos = self.elegidos[a.clave]
                if elegidos then
                    -- Elegidos a mano: + suma uno del mejor que quede; − quita
                    -- uno del peor que salga.
                    local lista = self:modelosDisponibles(a.clave)
                    local desde, hasta, paso = 1, #lista, 1
                    if a.paso < 0 then
                        desde, hasta, paso = #lista, 1, -1
                    end
                    for k = desde, hasta, paso do
                        local d = lista[k]
                        local tiene = elegidos[d.modelo] or 0
                        if (a.paso > 0 and tiene < d.hay) or (a.paso < 0 and tiene > 0) then
                            self:cambiarModelo(a.clave, d.modelo, a.paso > 0 and 1 or -1)
                            break
                        end
                    end
                else
                    local nueva = self.cantidades[a.clave] + a.paso
                    self.cantidades[a.clave] = math.max(0, math.min(self:hay(a.clave), nueva))
                end
                self.motivo = nil
                return 'nada'
            end
            if a.tipo == 'abrir' then
                -- Uno abierto a la vez: los dos no caben a 1280 x 720.
                local abrir = not self.abiertos[a.clave]
                self.abiertos = {}
                self.abiertos[a.clave] = abrir or nil
                return 'nada'
            end
            if a.tipo == 'modelo' then
                self:cambiarModelo(a.clave, a.modelo, a.paso)
                self.motivo = nil
                return 'nada'
            end
            return a.tipo
        end
    end
    return 'nada'
end

--- El comando con lo elegido: `recolectar` o `enviarGrupo` (atacar).
function Envio:comando()
    if self.modo == 'sacar' then
        -- Un ejército parado en su ciudad: sale «hacia» ella misma.
        return {
            tipo = 'enviarGrupo',
            nacion = self.desde.nacion,
            desde = self.desde.id,
            mision = 'mover',
            objetivo = self.desde.id,
            soldados = self.cantidades.soldados,
            lanzacohetes = self.cantidades.lanzacohetes,
            modelos = self:modelosComando(),
            municion = self.dias,
        }
    end
    if self.modo == 'recolectar' then
        return {
            tipo = 'recolectar',
            nacion = self.desde.nacion,
            desde = self.desde.id,
            yacimiento = self.objetivo.id,
            soldados = self.cantidades.soldados,
            lanzacohetes = self.cantidades.lanzacohetes,
            modelos = self:modelosComando(),
            municion = self.dias,
        }
    end
    return {
        tipo = 'enviarGrupo',
        nacion = self.desde.nacion,
        desde = self.desde.id,
        mision = 'atacar',
        objetivo = self.objetivo.id,
        soldados = self.cantidades.soldados,
        lanzacohetes = self.cantidades.lanzacohetes,
        modelos = self:modelosComando(),
        municion = self.dias,
    }
end

return Envio
