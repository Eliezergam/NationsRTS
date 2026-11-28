-- Escena de batalla en 3D (prototipo): al entrar en un combate del mapa se
-- genera el sitio real en 3D low-poly (batalla/suelo.lua) con las tropas que
-- de verdad llevan los dos bandos (batalla/tropas.lua), y se ve la pelea con
-- una cámara en perspectiva (batalla/camara.lua).
--
-- Lee el estado de la simulación al entrar y no lo cambia: pelea exactamente
-- lo que tiene cada bando (vehículos 1:1 con oleadas, infantería por
-- escuadras, munición de cada grupo) y, al salir, main.lua manda lo que pasó
-- unidad por unidad (`Tropas:resultado`) con `resolverBatalla`. Mientras se
-- está aquí, el mundo sigue más lento (hoy al 25 %) y la pelea va con su
-- propio reloj, que se pausa con P.
--
-- Al entrar desde el juego se abre antes la preparación (batalla/despliegue.lua,
-- `Escena:empezarPreparacion`): 2:00 con el combate en pausa, las zonas de
-- despliegue sobre el terreno y el botón «Listo».

local Simulacion = require('mundo.simulacion')
local Iso = require('mundo.iso')
local Tema = require('interfaz.tema')
local Suelo = require('batalla.suelo')
local Tropas = require('batalla.tropas')
local Camara = require('batalla.camara')
local Caminante = require('batalla.caminante')
local Control = require('batalla.control')
local Sombreado = require('batalla.sombreado')
local Carga = require('batalla.carga')
local Despliegue = require('batalla.despliegue')
local DespliegueVista = require('batalla.despliegue_vista')

local Escena = {}
Escena.__index = Escena

Escena.delanteObjetivo = 1000 -- px entre el objetivo y la primera fila del defensor
Escena.cercaParaEntrar = 30000 -- px: con B se entra en el combate más cercano a esta distancia

-- Búsqueda de combates ----------------------------------------------------------------------

--- Combate de un grupo, si está peleando: un ejército en misión de atacar ya
-- formado (desplegado a la salida o en su objetivo). Devuelve la descripción
-- que usa la escena, o nil.
function Escena.combateDeGrupo(mundo, gr)
    if gr.mision ~= 'atacar' then
        return nil
    end
    local sim = mundo.sim
    local fraccion = sim:fraccionPaso()
    local x, y, _, peleando = mundo:posicionVisible(gr, fraccion)
    -- Una ciudad o instalación, o una mina (depósito) atacada.
    local objetivo = sim:sitio(gr.objetivo) or sim.estado.depositos[gr.objetivo]
    if not (x and peleando and objetivo) then
        return nil
    end
    -- Dirección del ataque: del grupo al objetivo (o, si ya está encima, de
    -- su punto de salida al objetivo).
    local dx, dy = objetivo.x - x, objetivo.y - y
    if dx * dx + dy * dy < 3000 * 3000 then
        local origen = sim:sitio(gr.desde) or { x = gr.ruta[1], y = gr.ruta[2] }
        dx, dy = objetivo.x - origen.x, objetivo.y - origen.y
    end
    return Escena.describir(mundo, gr, objetivo, math.atan2(dy, dx))
end

--- Descripción de un combate que usa la escena: `fuerzas` (un grupo o un
-- sitio, con nación, tanques y lanzacohetes) ataca `objetivo` (un sitio)
-- llegando con rumbo `angulo`.
function Escena.describir(mundo, fuerzas, objetivo, angulo)
    local sim = mundo.sim
    local ca, sa = math.cos(angulo), math.sin(angulo)
    -- El centro, entre los dos bandos, delante del objetivo. La batalla es el
    -- mapa ampliado `escala` veces alrededor del centro (batalla/terreno_escalado.lua):
    -- el centro se pone a `atras` px de batalla del objetivo (atras / escala
    -- en el mapa), y así el sitio sale en su lugar real del mapa 2D, con su
    -- terreno, a `atras` px del centro (el dueño, 19-nov).
    local escala = tonumber(os.getenv('BATALLA_ESCALA') or '') or Suelo.escalaMundo
    local atras = Tropas.separacion + Escena.delanteObjetivo
    local cx, cy = objetivo.x - ca * atras / escala, objetivo.y - sa * atras / escala
    local esCiudad = sim.estado.ciudades[objetivo.id] ~= nil
    -- Mina: un depósito atacado o una instalación sobre un depósito.
    local deposito = sim.estado.depositos[objetivo.id]
        or (objetivo.deposito and sim.estado.depositos[objetivo.deposito])
    local tipoSitio = esCiudad and 'ciudad' or (deposito and 'mina' or objetivo.tipo)
    local nacionA, nacionD = sim:nacion(fuerzas.nacion), sim:nacion(objetivo.nacion)
    local fisica = esCiudad and mundo:ciudadFisica(objetivo.id)
    local esGrupo = sim.estado.grupos[fuerzas.id] == fuerzas
    return {
        grupo = esGrupo and fuerzas.id or nil,
        cx = cx,
        cy = cy,
        angulo = angulo,
        atacante = {
            nombre = nacionA and nacionA.nombre or '?',
            color = nacionA and nacionA.color or { 1, 1, 1 },
            tanques = fuerzas.tanques or 0,
            lanzacohetes = fuerzas.lanzacohetes or 0,
            tanquesPor = fuerzas.tanquesPor,
            lanzacohetesPor = fuerzas.lanzacohetesPor,
            soldados = fuerzas.soldados or 0,
            fuerza = esGrupo and Simulacion.vidaGrupo(fuerzas) or Simulacion.fuerzaDe(fuerzas),
        },
        defensor = {
            nombre = nacionD and nacionD.nombre or '?',
            color = nacionD and nacionD.color or { 1, 1, 1 },
            tanques = objetivo.tanques or 0,
            lanzacohetes = objetivo.lanzacohetes or 0,
            tanquesPor = objetivo.tanquesPor,
            lanzacohetesPor = objetivo.lanzacohetesPor,
            soldados = objetivo.soldados or 0,
            fuerza = Simulacion.fuerzaDe(objetivo),
        },
        sitio = {
            tipo = tipoSitio,
            -- Todas las ciudades del mapa son capitales (mundo/ciudades.lua).
            capital = esCiudad,
            deposito = deposito and deposito.tipo or nil,
            -- Del mapa a la batalla (ampliado alrededor del centro).
            x = cx + ((fisica and fisica.x or objetivo.x) - cx) * escala,
            y = cy + ((fisica and fisica.y or objetivo.y) - cy) * escala,
            z = fisica and fisica.altura or mundo.terreno:altura(objetivo.x, objetivo.y),
            color = nacionD and nacionD.color or { 1, 1, 1 },
            -- Dónde está en el mapa (los aviones que llegan: trafico_aereo.lua).
            mapaX = objetivo.x,
            mapaY = objetivo.y,
        },
    }
end

--- Para probar la escena sin esperar a una guerra: un combate imaginado (la
-- simulación no lo tiene) entre la ciudad más cercana a (x, y) y la ciudad
-- de otra nación más cercana a ella. Nil si aún no se ven dos.
function Escena.combateProvocado(mundo, x, y)
    local sim = mundo.sim
    local ciudad = mundo:ciudadMasCercana(x, y)
    local desde = ciudad and sim:ciudad(ciudad.region)
    if not desde then
        return nil
    end
    local mejor, mejorD
    for _, otra in pairs(mundo.ciudadesVistas) do
        local datos = sim:ciudad(otra.region)
        if datos and datos.nacion ~= desde.nacion then
            local d = (datos.x - desde.x) ^ 2 + (datos.y - desde.y) ^ 2
            if not mejor or d < mejorD then
                mejor, mejorD = datos, d
            end
        end
    end
    if not mejor then
        return nil
    end
    local combate = Escena.describir(mundo, desde, mejor, math.atan2(mejor.y - desde.y, mejor.x - desde.x))
    combate.provocado = true
    return combate
end

--- El combate más cercano a (x, y) (a menos de `Escena.cercaParaEntrar`), o
-- nil. Sin punto, el primero (en orden fijo), mejor si ya está en su objetivo.
function Escena.buscarCombate(mundo, x, y)
    local mejor, mejorD
    local e = mundo.sim.estado
    for _, gid in ipairs(Simulacion.ordenadas(e.grupos)) do
        local gr = e.grupos[gid]
        local combate = Escena.combateDeGrupo(mundo, gr)
        if combate then
            local d
            if x then
                d = (combate.cx - x) ^ 2 + (combate.cy - y) ^ 2
            else
                d = gr.recorrido >= gr.largo and 0 or 1
            end
            if not mejor or d < mejorD then
                mejor, mejorD = combate, d
            end
        end
    end
    if mejor and x and mejorD > Escena.cercaParaEntrar ^ 2 then
        return nil
    end
    return mejor
end

-- Escena ---------------------------------------------------------------------------------------

--- Escena de batalla del `combate`. Con `combate.preparacion`, los bandos
-- forman más cerca (`Despliegue.separacion`, dentro de sus zonas) y se abre
-- la fase de preparación; sin ella, como siempre y ya en combate.
function Escena.nueva(mundo, combate)
    Carga.iniciar()
    local self = setmetatable({}, Escena)
    self.mundo = mundo
    self.combate = combate
    if combate.preparacion then
        combate.separacion = Despliegue.separacion
    end
    self.suelo = Suelo.nuevo(mundo, combate.cx, combate.cy, combate.sitio, {
        angulo = combate.angulo,
        separacion = combate.separacion or Tropas.separacion,
    }, Carga.mostrar)
    Carga.mostrar('Desplegando los ejércitos', 0.95, true)
    self.tropas = Tropas.nuevo(self.suelo, combate)
    self.camara = Camara.nueva(self.suelo, combate.cx, combate.cy)
    self.tropas:usarCamara(self.camara)
    self.control = Control.nuevo(self.tropas, self.camara)
    -- El jugador manda su bando; mirando (sin bando), el atacante.
    self.control:usarBando(combate.ladoJugador == 'defensor' and 2 or 1)
    Carga.mostrar('Preparando las rutas de las órdenes', 0.97, true)
    self.control.ordenes:rejilla()
    self:encuadrarOrganizacion()
    self.pausa = false
    if combate.preparacion then
        self:empezarPreparacion()
    end
    Carga.mostrar('Campo de batalla listo', 1, true)
    return self
end

-- Preparación ----------------------------------------------------------------------------------

--- Abre la fase de preparación (batalla/despliegue.lua): contador de
-- `segundos` (2:00 por defecto) con el combate en pausa y las zonas de
-- despliegue a la vista. La llama `Escena.nueva` con `combate.preparacion`;
-- sin ella, la escena empieza ya en combate (los arneses de batalla/pruebas_*
-- y las capturas de `--batalla`).
function Escena:empezarPreparacion(segundos)
    self.despliegue = Despliegue.nuevo(self.tropas, self.combate, self.control.propio, segundos)
    self.vistaDespliegue = DespliegueVista.nueva(self.despliegue, self.control, self.combate)
    -- El NPC ya está formado al entrar (batalla/tropas.lua): listo enseguida.
    self.despliegue:formarNpc()
    -- La cámara no sale de la zona propia ni ve la enemiga mientras dure.
    self.camara:usarRecinto(self.despliegue:recintoCamara())
    for indice, zona in ipairs(self.despliegue.zonas) do
        print(
            string.format(
                'DESPLIEGUE zona %d: %.0f m de fondo x %.0f m de ancho, de %.0f a %.0f m del centro',
                indice,
                (zona.dMax - zona.dMin) / 10,
                (zona.lMax - zona.lMin) / 10,
                math.min(math.abs(zona.dMin), math.abs(zona.dMax)) / 10,
                math.max(math.abs(zona.dMin), math.abs(zona.dMax)) / 10
            )
        )
    end
end

--- ¿Dura todavía la preparación (combate bloqueado)?
function Escena:enPreparacion()
    return self.despliegue ~= nil and not self.despliegue.terminada
end

--- El jugador pulsa «Listo». Si el rival también lo está, empieza el combate.
function Escena:pulsarListo()
    if not self:enPreparacion() then
        return
    end
    self.despliegue:marcarListo(self.control.propio)
    if self.despliegue:actualizar(0) then
        self:empezarCombate()
    end
end

--- Termina la preparación y habilita el combate: la pelea empieza a correr
-- desde su reloj a cero y las zonas se van.
function Escena:empezarCombate()
    if self.despliegue then
        self.despliegue:terminar()
    end
    -- La cámara se queda donde esté, ya sin recinto.
    if self.camara then
        self.camara:usarRecinto(nil)
    end
end

--- Encuadre de organización: una vista aérea baja sobre la formación del
-- jugador. Desde aquí la cámara queda libre para recorrer el terreno.
function Escena:encuadrarOrganizacion()
    -- Siguiendo a un robot (C), los encuadres no le quitan la cámara.
    if self.camara and self.camara.robot then
        return
    end
    local c = self.camara
    local combate = self.combate
    local sumaX = 0
    local sumaY = 0
    local cantidad = 0

    for _, unidad in ipairs(self.tropas.unidades) do
        if unidad.bando == 1 and unidad.tipo == 'tanque' and not unidad.muerto then
            sumaX = sumaX + unidad.x
            sumaY = sumaY + unidad.y
            cantidad = cantidad + 1
        end
    end

    if cantidad > 0 then
        c.x = sumaX / cantidad
        c.y = sumaY / cantidad
    else
        c.x = combate.cx
        c.y = combate.cy
    end

    local adelante = 250
    c.x = c.x + math.cos(combate.angulo) * adelante
    c.y = c.y + math.sin(combate.angulo) * adelante
    c.rumbo = combate.angulo + math.pi * 0.72
    c.inclinacion = math.rad(28)
    c.distancia = 2200
end

--- ¿Caben todos los vehículos en la pantalla con la cámara como está? `margen`
-- es la fracción de la pantalla que se usa (0,85: se deja un borde).
function Escena:caben(margen)
    local m = self.camara:matrices()
    for _, u in ipairs(self.tropas.unidades) do
        local x, y, z = u.x, u.y, u.z + 10
        local w = m[13] * x + m[14] * y + m[15] * z + m[16]
        if w <= 0 then
            return false
        end
        local px = (m[1] * x + m[2] * y + m[3] * z + m[4]) / w
        local py = (m[5] * x + m[6] * y + m[7] * z + m[8]) / w
        if math.abs(px) > margen or math.abs(py) > margen then
            return false
        end
    end
    return true
end

--- Encuadre por defecto: los dos bandos enteros en la pantalla, mirando de
-- lado al avance (el atacante a la izquierda) o, si la pantalla es estrecha,
-- algo en diagonal, lo que deje la cámara más cerca.
function Escena:encuadrarBandos(inclinacion)
    local c = self.camara
    local combate = self.combate
    local ca, sa = math.cos(combate.angulo), math.sin(combate.angulo)
    local minimo, maximo = math.huge, -math.huge
    for _, u in ipairs(self.tropas.unidades) do
        local d = (u.x - combate.cx) * ca + (u.y - combate.cy) * sa
        minimo, maximo = math.min(minimo, d), math.max(maximo, d)
    end
    if minimo > maximo then
        minimo, maximo = -Tropas.separacion, Tropas.separacion
    end
    local medio = (minimo + maximo) / 2
    c.x, c.y = combate.cx + ca * medio, combate.cy + sa * medio
    c.inclinacion = inclinacion or math.rad(32)
    local mejorRumbo, mejorDistancia
    for _, giro in ipairs({ 0, 0.4, 0.8, 1.2 }) do
        c.rumbo = combate.angulo + math.pi / 2 + giro
        c.distancia = 2000
        while c.distancia < Camara.maxDistancia and not self:caben(0.9) do
            c.distancia = c.distancia * 1.06
        end
        if not mejorDistancia or c.distancia < mejorDistancia * 0.9 then
            mejorRumbo, mejorDistancia = c.rumbo, c.distancia
        end
    end
    c.rumbo, c.distancia = mejorRumbo, math.min(Camara.maxDistancia, mejorDistancia)
end

--- Encuadres: 'normal' (organización aérea baja del atacante), 'tanques' (los
-- dos bandos, más bajo, para ver los trazadores), 'cerca' (un tanque del
-- atacante de cerca), 'cohetes' (vista baja detrás del atacante, para ver los arcos),
-- 'adelantado' (el lanzacohetes adelantado del defensor), 'lejos' (el área
-- entera desde arriba) y 'preparacion' o 'listo' (las zonas de despliegue).
function Escena:encuadrar(modo)
    -- Siguiendo a un robot (C), los encuadres no le quitan la cámara.
    if self.camara and self.camara.robot then
        return
    end
    local c = self.camara
    self.seguirMisil = false
    -- Un encuadre es un corte: sin inercia, y la altura se fija de nuevo.
    c:detener()
    c.objetivoZ = nil
    self:encuadrarOrganizacion()
    if modo == 'tanques' then
        self:encuadrarBandos(math.rad(22))
    elseif modo == 'cerca' then
        -- Un tanque del atacante; sin tanques, un lanzacohetes; si no, lo que haya.
        local elegido
        local rango = { tanque = 3, lanzacohetes = 2 }
        for _, u in ipairs(self.tropas.unidades) do
            if u.bando == 1 and (not elegido or (rango[u.tipo] or 1) > (rango[elegido.tipo] or 1)) then
                elegido = u
            end
        end
        if elegido then
            c.x, c.y = elegido.x, elegido.y
        end
        c.distancia = 650
        c.inclinacion = math.rad(28)
        c.rumbo = self.combate.angulo + math.pi * 0.72
        if elegido and elegido.tipo == 'lanzacohetes' then
            -- La inspección cercana también sirve en pruebas sin tanques.
            c.objetivoZ = elegido.z + 48
            c.distancia = 420
            c.inclinacion = math.rad(17)
            c.rumbo = elegido.rumbo + 0.9
        end
    elseif modo == 'cohetes' then
        -- Vista de la demostración: retirada y baja, con el horizonte y las
        -- salvas delante, según la referencia elegida por el dueño.
        local sumaX = 0
        local sumaY = 0
        local cantidad = 0
        for _, unidad in ipairs(self.tropas.unidades) do
            if unidad.bando == 1 and unidad.tipo == 'lanzacohetes' and not unidad.muerto then
                sumaX = sumaX + unidad.x
                sumaY = sumaY + unidad.y
                cantidad = cantidad + 1
            end
        end
        if cantidad > 0 then
            local delante = 700
            c.x = sumaX / cantidad + math.cos(self.combate.angulo) * delante
            c.y = sumaY / cantidad + math.sin(self.combate.angulo) * delante
        end
        c.rumbo = self.combate.angulo + math.pi + 0.2
        c.inclinacion = math.rad(4)
        c.distancia = 5000
        local alturaVista = c:alturaObjetivo() + 480
        c.objetivoZ = alturaVista - math.sin(c.inclinacion) * c.distancia
        local derechaX, derechaY = c:ejes()
        c.x = c.x - derechaX * 300
        c.y = c.y - derechaY * 300
    elseif modo == 'adelantado' then
        local u = self.tropas:adelantado()
        if u then
            c.x, c.y = u.x, u.y
        end
        c.distancia = 4200
        c.inclinacion = math.rad(26)
        c.rumbo = self.combate.angulo + math.pi * 0.62
    elseif modo == 'lejos' then
        c.x, c.y = self.combate.cx, self.combate.cy
        c.distancia = 34000
        c.inclinacion = math.rad(60)
    elseif modo == 'preparacion' or modo == 'listo' then
        self:encuadrarDespliegue()
    elseif modo == 'borde' then
        self:encuadrarBorde()
    elseif modo == 'sitio' then
        -- Entrar a una ciudad o una mina desde el mapa (el dueño, 26-nov):
        -- la cámara libre de siempre (27-nov: nada de entrar a pie) sobre el
        -- aeródromo de ese sitio. Cada sitio genera su plano con su pista
        -- (Plano:ponerPista), así que vale para todos: encima del borde norte
        -- de la plataforma, mirando a las plazas y a la pista (al sur).
        local plano = self.suelo.plano
        local pista = plano and plano.pista
        if pista then
            local P = require('batalla.sitios.plano').aerodromo.plataforma
            local co, si = math.cos(pista.rumbo), math.sin(pista.rumbo)
            local l = P.hasta - 8
            c.x = pista.x + si * l * 10
            c.y = pista.y - co * l * 10
            c.rumbo = math.atan2(-co, si) -- adelante (-cos, -sin) = hacia el sur
        else
            local sitio = self.combate.sitio
            if sitio then
                c.x, c.y = sitio.x, sitio.y
            end
            c.rumbo = self.combate.angulo
        end
        c.distancia = 2500
        c.inclinacion = math.rad(35)
        -- `SITIO_CAMARA=adelante,derecha,distancia,inclinacion,giro` (m y
        -- grados, desde donde se aparece y hacia donde se mira al entrar):
        -- para revisar de cerca lo generado.
        local fijada = os.getenv('SITIO_CAMARA')
        if fijada then
            local v = {}
            for n in fijada:gmatch('[^,]+') do
                v[#v + 1] = tonumber(n)
            end
            local fx, fy = -math.cos(c.rumbo), -math.sin(c.rumbo)
            local adelante, derecha = (v[1] or 0) * 10, (v[2] or 0) * 10
            c.x = c.x + fx * adelante - fy * derecha
            c.y = c.y + fy * adelante + fx * derecha
            c.distancia = (v[3] or 60) * 10
            c.inclinacion = math.rad(v[4] or 25)
            c.rumbo = c.rumbo + math.rad(v[5] or 0)
        end
    end
end

--- Encuadre de la preparación (vista de comandante, como en Bannerlord): la
-- mira en el centro de la primera línea del jugador (tanques; los
-- lanzacohetes van detrás) y el ojo a unos 75 m de altura, detrás y algo al
-- lado, mirando hacia el enemigo.
function Escena:encuadrarDespliegue()
    -- Siguiendo a un robot (C), los encuadres no le quitan la cámara.
    if self.camara and self.camara.robot then
        return
    end
    local c = self.camara
    local combate = self.combate
    local propio = self.control.propio
    local haciaEnemigo = propio == 1 and combate.angulo or combate.angulo + math.pi
    local sumaX = 0
    local sumaY = 0
    local cantidad = 0
    for _, u in ipairs(self.tropas.unidades) do
        if u.bando == propio and not u.muerto and u.tipo ~= 'lanzacohetes' then
            sumaX = sumaX + u.x
            sumaY = sumaY + u.y
            cantidad = cantidad + 1
        end
    end
    if cantidad > 0 then
        -- 60 m por delante del centro: desde 75 m de altura la formación
        -- queda en el medio de la pantalla y no al fondo.
        c.x = sumaX / cantidad + math.cos(haciaEnemigo) * 600
        c.y = sumaY / cantidad + math.sin(haciaEnemigo) * 600
    else
        local d = (propio == 1 and -1 or 1) * 6500
        c.x = combate.cx + math.cos(combate.angulo) * d
        c.y = combate.cy + math.sin(combate.angulo) * d
    end
    c.rumbo = haciaEnemigo + math.pi - 0.3
    c.inclinacion = math.rad(35)
    c.distancia = 1300
    -- El techo del recinto se mide sobre el suelo bajo el ojo: si allí el
    -- suelo (o el agua) está más bajo que la formación, se acerca la cámara
    -- para no bajar la mira por debajo del suelo (se vería más cerca de lo
    -- que se quiere).
    if self.despliegue then
        local ex, ey = c:ojoPlano()
        local libre = c:superficie(ex, ey) + Despliegue.alturaCamara - c:superficie(c.x, c.y) - 20
        local alto = math.sin(c.inclinacion) * c.distancia
        if alto > libre then
            c.distancia = math.max(Camara.minDistancia, libre / math.sin(c.inclinacion))
        end
    end
end

--- Encuadre de prueba del recinto de la preparación: pide el ojo 300 m
-- dentro de la franja neutral, a 250 m de altura y mirando casi al
-- horizonte hacia el enemigo. Con el recinto, queda en el borde delantero
-- de la zona, a la altura máxima y con la inclinación mínima.
function Escena:encuadrarBorde()
    -- Siguiendo a un robot (C), los encuadres no le quitan la cámara.
    if self.camara and self.camara.robot then
        return
    end
    local c = self.camara
    local combate = self.combate
    local propio = self.control.propio
    local signo = propio == 1 and -1 or 1
    local haciaEnemigo = propio == 1 and combate.angulo or combate.angulo + math.pi
    c.inclinacion = math.rad(8)
    c.distancia = 2500 / math.sin(c.inclinacion)
    c.rumbo = haciaEnemigo + math.pi
    local ojo = signo * (Despliegue.mitadNeutral - 3000)
    local delante = math.cos(c.inclinacion) * c.distancia
    local d = ojo - signo * delante
    c.x = combate.cx + math.cos(combate.angulo) * d
    c.y = combate.cy + math.sin(combate.angulo) * d
end

--- Unidades del rival dentro de la pantalla con la cámara de ahora (sin
-- contar lo que tapa el terreno): para comprobar el recinto.
function Escena:rivalesALaVista()
    local m = self.camara:matrices()
    local w, h = love.graphics.getDimensions()
    local cuenta = 0
    for _, u in ipairs(self.tropas.unidades) do
        if u.bando ~= self.control.propio and not u.muerto and self:aPantalla(m, u.x, u.y, u.z + 10, w, h) then
            cuenta = cuenta + 1
        end
    end
    return cuenta
end

--- Para las capturas: ¿se ve ya lo que el encuadre quiere enseñar? 'cerca',
-- un tanque cerca de la cámara que acaba de disparar; 'tanques', trazadores
-- de más de 1 km a medio camino; 'cohetes', misiles en lo alto de su vuelo;
-- 'adelantado', el lanzacohetes adelantado recién averiado; 'duracion', la
-- pelea terminada (un bando sin nada en pie o nadie con munición); 'listo',
-- el combate ya empezado tras la preparación.
function Escena:listaParaFoto(modo)
    local t = self.tropas
    if modo == 'cerca' then
        return t:disparoCerca(self.camara.x, self.camara.y, 500)
    elseif modo == 'tanques' then
        return t:trazadoresLejanos(10000) >= 4
    elseif modo == 'cohetes' then
        return t:misilesAltos() >= 12
    elseif modo == 'adelantado' then
        local u = t:adelantado()
        return u ~= nil and u.muerto and t.reloj - u.caida > 0.25
    elseif modo == 'duracion' then
        return t:terminada()
    elseif modo == 'listo' then
        -- Tras pulsar «Listo»: el combate ya corre y se ven los primeros disparos.
        return not self:enPreparacion() and t.reloj >= 6
    end
    return true
end

function Escena:actualizar(dt)
    if self.camara:actualizar(dt) then
        self.seguirMisil = false
    end
    if self:enPreparacion() then
        -- Preparación: la pelea no corre (nadie dispara, recibe daño ni
        -- avanza); solo el contador, que también para con la pausa.
        if not self.pausa and self.despliegue:actualizar(dt) then
            self:empezarCombate()
        end
        -- Los misiles del camión de robot conductor sí vuelan.
        if not self.pausa and self.tropas.efectosSueltos then
            self.tropas:actualizarEfectos(math.min(dt, 0.05))
        end
    elseif not self.pausa then
        self.tropas:actualizar(math.min(dt, 0.05))
        self:vigilarFin()
    end
    if self.caminante and self.fin and self.fin.cerrar then
        -- Se vuelve al mapa: el ratón no puede quedarse capturado.
        self:salirPie()
    end
    if self.seguirMisil then
        local elegido
        local distanciaCentro = math.huge
        for _, misil in ipairs(self.tropas.misiles) do
            local t = (self.tropas.reloj - misil.inicio) / misil.duracion
            local distancia = math.abs(t - 0.55)
            if t > 0.08 and t < 0.95 and distancia < distanciaCentro then
                elegido = misil
                distanciaCentro = distancia
            end
        end
        if elegido then
            local t = (self.tropas.reloj - elegido.inicio) / elegido.duracion
            local x, y, z = Tropas.posicionMisil(elegido, t)
            self.camara:seguir(x, y, z, dt)
        end
    end
    self.control:actualizar()
end

--- La pelea termina sola (decisión del dueño): la primera vez que
-- `Tropas:fin` da un final se fija en `self.fin` ({ pierde, retira, motivo,
-- desde }) y `Tropas.cierre` s de pelea después se marca `fin.cerrar`: main.lua
-- vuelve al mapa y manda el resultado (con `retira`).
function Escena:vigilarFin()
    -- La guardia de una mina no termina sola: se mira hasta salir con Esc.
    if self.guardia then
        return
    end
    local t = self.tropas
    if not self.fin then
        local f = t:fin()
        if f then
            f.desde = t.reloj
            self.fin = f
        end
    end
    if self.fin and t.reloj - self.fin.desde >= Tropas.cierre then
        self.fin.cerrar = true
    end
end

local MOTIVO_FIN = {
    municion = 'se retira: sin munición con la que dañar al rival',
    alcance = 'se retira: no alcanza al rival',
    fuera = 'queda fuera de combate',
}

--- Aviso del final en el centro de la pantalla.
function Escena:dibujarFin()
    local f = self.fin
    if not f then
        return
    end
    local g = love.graphics
    local w, h = g.getDimensions()
    local c = self.combate
    local pierde = f.pierde == 1 and c.atacante or c.defensor
    local gana = f.pierde == 1 and c.defensor or c.atacante
    local titulo = pierde.nombre .. ' ' .. MOTIVO_FIN[f.motivo]
    local resta = math.max(0, math.ceil(Tropas.cierre - (self.tropas.reloj - f.desde)))
    local detalle =
        string.format('Gana %s · la batalla termina · vuelta al mapa en %d s (Esc, ya)', gana.nombre, resta)
    local grande = Tema.fuente('sans', 20)
    local chica = Tema.fuente('sans', 13)
    local relleno = Tema.px(14)
    local ancho = math.max(grande:getWidth(titulo), chica:getWidth(detalle)) + relleno * 2
    local alto = grande:getHeight() + chica:getHeight() + relleno * 2 + Tema.px(4)
    local x = math.floor((w - ancho) / 2)
    local y = math.floor(h * 0.3)
    Tema.color('olivaNegro', 0.9)
    g.rectangle('fill', x, y, ancho, alto, 3, 3)
    Tema.color('amarillo', 0.95)
    g.setLineWidth(2)
    g.rectangle('line', x + 1, y + 1, ancho - 2, alto - 2, 3, 3)
    g.setLineWidth(1)
    g.setFont(grande)
    Tema.color('amarillo')
    g.print(titulo, math.floor((w - grande:getWidth(titulo)) / 2), y + relleno)
    g.setFont(chica)
    Tema.color('textoHud')
    g.print(detalle, math.floor((w - chica:getWidth(detalle)) / 2), y + relleno + grande:getHeight() + Tema.px(4))
    g.setColor(1, 1, 1, 1)
end

--- Fondo: el color de la niebla y, por encima del horizonte (si se ve), el
-- cielo de atardecer del mapa, que se aclara hasta la niebla en el horizonte.
local function dibujarCielo(camara)
    local g = love.graphics
    local w, h = g.getDimensions()
    local niebla = Sombreado.colorNiebla
    g.clear(niebla[1], niebla[2], niebla[3], 1)
    -- Altura en pantalla de lo que está a nivel del ojo, muy lejos.
    local inclinacion = camara.inclinacionVista or camara.inclinacion
    local horizonte = h / 2 * (1 - math.tan(inclinacion) / math.tan(Camara.campo / 2))
    if horizonte <= 0 then
        return
    end
    local malla = love.graphics.newMesh({
        { 0, 0, 0, 0, 0.93, 0.6, 0.52, 1 },
        { w, 0, 0, 0, 0.93, 0.6, 0.52, 1 },
        { w, horizonte, 0, 0, niebla[1], niebla[2], niebla[3], 1 },
        { 0, horizonte, 0, 0, niebla[1], niebla[2], niebla[3], 1 },
    }, 'fan', 'static')
    g.setColor(1, 1, 1, 1)
    g.draw(malla)
    malla:release()
end

local identidad = { 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1 }
local colorCampoAbierto = { 1, 1, 1 }

--- Color de nación para el edificio atacado. En campo abierto no hay `sitio`: el
-- suelo y las plantas usan sus propios colores, así que el color neutro basta.
function Escena:colorSitio()
    local sitio = self.combate.sitio
    return sitio and sitio.color or colorCampoAbierto
end

function Escena:dibujar()
    local g = love.graphics
    dibujarCielo(self.camara)
    local shader = Sombreado.shader()
    local vistaProyeccion, ex, ey, ez = self.camara:matrices()
    g.push('all')
    g.clear(false, false, true)
    g.setShader(shader)
    shader:send('vistaProyeccion', 'row', vistaProyeccion)
    shader:send('camara', { ex, ey, ez })
    -- La niebla empieza algo antes del punto al que se mira y es suave: a 2-3
    -- km aún se lee la escena. En el borde del área se lo come todo.
    local cerca = math.max(2000, self.camara.distancia * 0.8)
    shader:send('niebla', { cerca, cerca + 70000 })
    shader:send('area', { self.suelo.cx, self.suelo.cy, Suelo.lado / 2 })
    shader:send('modelo', 'row', identidad)
    shader:send('colorNacion', self:colorSitio())
    g.setDepthMode('lequal', true)
    g.setColor(1, 1, 1, 1)
    local s = self.suelo
    shader:send('luzMapa', 1)
    g.draw(s.mallaTerreno)
    if s.mallaPlantas then
        g.draw(s.mallaPlantas)
    end
    if s.mallaEdificio then
        g.draw(s.mallaEdificio)
    end
    shader:send('luzMapa', 0)
    self.tropas:dibujarUnidades(shader)
    -- Lo translúcido: agua y efectos, sin escribir profundidad.
    g.setDepthMode('lequal', false)
    shader:send('modelo', 'row', identidad)
    if s.mallaAgua then
        shader:send('luzMapa', 1)
        g.setColor(1, 1, 1, 0.82)
        g.draw(s.mallaAgua)
        shader:send('luzMapa', 0)
    end
    self.tropas:dibujarEfectos(shader, ex, ey, ez)
    g.pop()
    self:dibujarZonas()
    self.control:dibujar()
    self:dibujarAvisos()
    self:dibujarRotulo()
    self:dibujarPanelDespliegue()
end

--- Zonas de despliegue sobre el terreno (durante la preparación y su fundido).
function Escena:dibujarZonas()
    -- Sin zonas cuando no hay despliegue que hacer (la guardia de una mina).
    if self.vistaDespliegue and not self.sinZonas then
        self.vistaDespliegue:dibujarZonas()
    end
end

--- Panel de la preparación con el contador y el botón «Listo».
function Escena:dibujarPanelDespliegue()
    if self.vistaDespliegue and not self.guardia then
        self.vistaDespliegue:dibujarPanel()
    end
end

-- Aviso de cada munición que falta (diseno/economia.md, §3.6.6).
local AVISO_SIN = { balas = 'Sin balas', obuses = 'Sin obuses', misiles = 'Sin misiles' }

--- Tramos de texto de un bando para el rótulo: quién es y su munición. Cada
-- línea es una lista de { texto, color } (color: nombre de la paleta o
-- tabla). (Los tanques y el lanzacohetes viejo ya no salen: 19-nov.)
local function lineasBando(titulo, bando, municion, ajeno)
    local fuerzas = string.format('%s  %s', titulo, bando.nombre)
    local tramos = { { '      Munición: ', 'textoHudTenue' } }
    if ajeno then
        -- Lo ajeno no se sabe sin informe (decisión del dueño).
        tramos[#tramos + 1] = { 'sin informe', 'textoHudTenue' }
    elseif municion.limitada then
        local partes = {}
        for _, m in ipairs({ 'balas', 'obuses', 'misiles' }) do
            partes[#partes + 1] = Tema.numero(math.max(0, municion.lleva[m] - municion.gastado[m])) .. ' ' .. m
        end
        tramos[#tramos + 1] = { table.concat(partes, ' · '), 'textoHud' }
    else
        tramos[#tramos + 1] = { 'sin límite (combate de prueba)', 'textoHudTenue' }
    end
    return { { { fuerzas, bando.color } }, tramos }
end

--- Rótulo arriba a la izquierda: quién pelea, qué queda, la munición de cada
-- bando y los controles.
-- Nombre de cada yacimiento para el rótulo de la visita.
local NOMBRE_MINA = { oro = 'Mina de oro', metal = 'Mina de metal', petroleo = 'Pozo de petróleo', comida = 'Granja' }

--- Rótulo de la visita a una ciudad o una mina: su nombre, la altura de la
-- cámara y los controles de la cámara libre.
function Escena:dibujarRotuloVisita(alturaSuperficie)
    local c = self.combate
    local sitio = c.sitio or {}
    local nombre
    if sitio.deposito then
        nombre = NOMBRE_MINA[sitio.deposito] or 'Mina'
    else
        nombre = c.defensor and c.defensor.nombre or 'Ciudad'
    end
    local lineas = {
        { { nombre, 'amarillo' } },
        { { string.format('De visita · el mundo sigue al 25 %% · cámara a %.0f m del suelo · FPS %d', alturaSuperficie, love.timer.getFPS()), 'textoHudTenue' } },
        { { 'W/S hacia donde miras · A/D a los lados · rueda avanzar/retroceder · Espacio subir · Ctrl bajar · Shift x3', 'textoHudTenue' } },
        { { 'Derecho (mantener) mirar · V a pie · Esc vuelve al mapa', 'textoHudTenue' } },
    }
    self:dibujarLineasRotulo(lineas)
end

function Escena:dibujarRotulo()
    local g = love.graphics
    local c = self.combate
    local t = self.tropas
    local s = self.suelo
    local alturaSuperficie, altitudMar = self.camara:alturas()
    local function tenue(texto)
        return { { texto, 'textoHudTenue' } }
    end
    -- De visita (entrar a mirar desde el mapa) no hay pelea: el nombre del
    -- sitio, sin bandos ni marcador (27-nov: salía «Ataca · Defiende ?»).
    if c.visita then
        self:dibujarRotuloVisita(alturaSuperficie)
        return
    end
    local lineas = {
        tenue(
            'Batalla 3D · el mundo sigue al 25 %'
                .. (c.forzado and ' · unidades forzadas para la prueba' or '')
                .. (c.provocado and ' · combate de prueba (no está en la simulación)' or '')
                .. (Escena.enPreparacion(self) and ' · PREPARACIÓN: combate en pausa' or '')
                .. (self.pausa and ' · PAUSA' or '')
        ),
    }
    for k, lado in ipairs({ 'atacante', 'defensor' }) do
        local ajeno = c.ladoJugador ~= nil and c.ladoJugador ~= lado
        for _, l in ipairs(lineasBando(k == 1 and 'Ataca' or 'Defiende', c[lado], t:municionBando(k), ajeno)) do
            lineas[#lineas + 1] = l
        end
    end
    if self.fin then
        local pierde = self.fin.pierde == 1 and c.atacante or c.defensor
        lineas[#lineas + 1] = { { pierde.nombre .. ' ' .. MOTIVO_FIN[self.fin.motivo], 'amarillo' } }
    end
    lineas[#lineas + 1] = tenue(
        string.format(
            'Terreno procedural · semilla %d · centro X %.0f m / Y %.0f m · rutas de avance %d',
            self.mundo.semilla,
            c.cx / 10,
            c.cy / 10,
            #(s.pasillos or {})
        )
    )
    lineas[#lineas + 1] = tenue(
        string.format(
            'Pelea %d:%02d · fuera de combate %d y %d · %d triángulos · %d plantas · generado en %.2f s · FPS %d',
            math.floor(t.reloj / 60),
            math.floor(t.reloj % 60),
            t.bajas[1],
            t.bajas[2],
            s.triangulos + s.triangulosPlantas,
            s.plantas,
            s.segundos,
            love.timer.getFPS()
        )
    )
    lineas[#lineas + 1] = tenue(
        string.format(
            'Cámara · Altitud: %.1f m sobre el mar · Altura sobre suelo/agua: %.1f m',
            altitudMar,
            alturaSuperficie
        )
    )
    if self.caminante then
        lineas[#lineas + 1] = tenue(
            'A PIE · ratón mira · W/S/A/D caminar · Shift correr · Espacio saltar · V o Esc vuelve a la vista RTS'
        )
        lineas[#lineas + 1] = tenue('H mantener posición · P pausa')
    else
        lineas[#lineas + 1] = tenue(
            'Clic elige · Mayús+clic suma/quita · arrastrar: cuadro · doble clic: su tipo'
        )
        lineas[#lineas + 1] = tenue(
            'Derecho corto: mover al punto o atacar al enemigo · H mantener posición · Derecho (mantener) mirar · Esc limpia o vuelve · P pausa'
        )
        lineas[#lineas + 1] = tenue(
            'W/S hacia donde miras · A/D a los lados · rueda avanzar/retroceder · Espacio subir · Ctrl bajar · Shift x3 · V a pie'
        )
    end
    self:dibujarLineasRotulo(lineas)
    self:dibujarFin()
end

--- El recuadro del rótulo, arriba a la izquierda: `lineas` es una lista de
-- líneas y cada línea, de tramos { texto, color del tema }.
function Escena:dibujarLineasRotulo(lineas)
    local g = love.graphics
    local fuente = Tema.fuente('sans', 12)
    local relleno = Tema.px(8)
    local ancho = 0
    for _, l in ipairs(lineas) do
        local w = 0
        for _, tramo in ipairs(l) do
            w = w + fuente:getWidth(tramo[1])
        end
        ancho = math.max(ancho, w)
    end
    local x, y = Tema.px(16), Tema.px(16)
    local alto = #lineas * fuente:getHeight() + relleno * 2
    Tema.color('olivaNegro', 0.82)
    g.rectangle('fill', x, y, ancho + relleno * 2, alto, 2, 2)
    Tema.color('lineaOliva', 0.9)
    g.rectangle('line', x + 0.5, y + 0.5, ancho + relleno * 2 - 1, alto - 1, 2, 2)
    g.setFont(fuente)
    for k, l in ipairs(lineas) do
        local px = x + relleno
        for _, tramo in ipairs(l) do
            Tema.color(tramo[2])
            g.print(tramo[1], px, y + relleno + (k - 1) * fuente:getHeight())
            px = px + fuente:getWidth(tramo[1])
        end
    end
    g.setColor(1, 1, 1, 1)
    self.altoRotulo = y + alto
end

--- Punto de pantalla de (x, y, z) con la cámara de la escena, o nil si
-- queda detrás o fuera.
function Escena:aPantalla(m, x, y, z, w, h)
    local q = m[13] * x + m[14] * y + m[15] * z + m[16]
    if q <= 0 then
        return nil
    end
    local nx = (m[1] * x + m[2] * y + m[3] * z + m[4]) / q
    local ny = (m[5] * x + m[6] * y + m[7] * z + m[8]) / q
    if math.abs(nx) > 1 or math.abs(ny) > 1 then
        return nil
    end
    return (nx + 1) / 2 * w, (1 - ny) / 2 * h
end

--- Avisos sobre las unidades (§3.6.6): encima de cada unidad en pie sin
-- munición, una marca roja y, si cabe sin pisar otro letrero ni el rótulo,
-- «Sin obuses» (o lo que le falte). Los más cercanos a la cámara primero.
-- Jugando una nación, solo sobre las suyas (lo ajeno, sin informe).
function Escena:dibujarAvisos()
    local g = love.graphics
    local w, h = g.getDimensions()
    local m, ex, ey, ez = self.camara:matrices()
    local ladoJugador = self.combate.ladoJugador
    local propio = ladoJugador == 'atacante' and 1 or (ladoJugador == 'defensor' and 2 or nil)
    local lista = {}
    for _, u in ipairs(self.tropas.unidades) do
        if not u.muerto and (not propio or u.bando == propio) and Tropas.sinMunicion(u) then
            local alto = 60
            local sx, sy = self:aPantalla(m, u.x, u.y, u.z + alto, w, h)
            if sx then
                local d = (u.x - ex) ^ 2 + (u.y - ey) ^ 2 + (u.z - ez) ^ 2
                lista[#lista + 1] = { u = u, x = sx, y = sy, d = d }
            end
        end
    end
    if #lista == 0 then
        return
    end
    table.sort(lista, function(a, b)
        return a.d < b.d
    end)
    local fuente = Tema.fuente('sans', 11, 11)
    local ocupados = { { x = 0, y = 0, w = w, h = self.altoRotulo or 0 } }
    local function libre(r)
        for _, o in ipairs(ocupados) do
            if r.x < o.x + o.w and o.x < r.x + r.w and r.y < o.y + o.h and o.y < r.y + r.h then
                return false
            end
        end
        return true
    end
    g.setFont(fuente)
    local lado = Tema.px(5)
    for _, a in ipairs(lista) do
        -- Marca: un rombo rojo con borde oscuro.
        Tema.color('rojo', 0.95)
        g.polygon('fill', a.x, a.y - lado, a.x + lado, a.y, a.x, a.y + lado, a.x - lado, a.y)
        Tema.color('olivaNegro', 0.9)
        g.polygon('line', a.x, a.y - lado, a.x + lado, a.y, a.x, a.y + lado, a.x - lado, a.y)
        local texto = AVISO_SIN[Tropas.gastoDisparo(a.u)]
        local tw, th = fuente:getWidth(texto) + Tema.px(8), fuente:getHeight() + Tema.px(2)
        local r = { x = a.x - tw / 2, y = a.y - lado - th - Tema.px(2), w = tw, h = th }
        if libre(r) then
            ocupados[#ocupados + 1] = r
            Tema.color('olivaNegro', 0.8)
            g.rectangle('fill', r.x, r.y, r.w, r.h, 2, 2)
            Tema.color('rojoTexto')
            g.print(texto, math.floor(r.x + Tema.px(4)), math.floor(r.y + Tema.px(1)))
        end
    end
    g.setColor(1, 1, 1, 1)
end

--- Primera persona (batalla/caminante.lua): se baja a pie a donde mira la
-- cámara RTS, con su mismo rumbo. El ratón queda capturado para mirar.
function Escena:entrarPie()
    self:liberarRaton()
    self.control:cuadro(nil)
    self.seguirMisil = false
    local c = self.camara
    self.caminante = Caminante.nuevo(self.suelo, self.tropas, c, c.x, c.y, c.rumbo)
    c:usarCaminante(self.caminante)
    love.mouse.setRelativeMode(true)
end

--- Vuelve a la vista RTS tal como estaba al bajar y suelta el ratón.
function Escena:salirPie()
    self.caminante = nil
    self.camara:usarCaminante(nil)
    love.mouse.setRelativeMode(false)
end

--- Tecla pulsada. Devuelve 'salir' con Esc (main.lua vuelve al mapa).
function Escena:tecla(tecla)
    -- C en el viaje del avión (AVION_DEMO, tools/demo_avion.sh): suelta la
    -- vista del robot junto a la pista y deja la cámara libre (botón derecho
    -- mira, W/S/A/D se mueve) para revisar el sitio; otra vez C, vuelve.
    if tecla == 'c' and os.getenv('AVION_DEMO') then
        local c = self.camara
        c.libreDemo = not c.libreDemo
        c.ojoFijo = nil
        c:usarRobot(nil)
        return nil
    end
    -- C: cámara siguiendo al robot (batalla/robots) o libre.
    if tecla == 'c' and self.robotSeguible and not self.caminante then
        self.camara:usarRobot(not self.camara.robot and self.robotSeguible or nil)
        return nil
    end
    if tecla == 'v' then
        if self.caminante then
            self:salirPie()
        else
            self:entrarPie()
        end
        return nil
    end
    if self.caminante then
        -- A pie, Esc sube a la vista RTS y Espacio salta; el resto de
        -- atajos (pausa, elegir por tipo, mantener) siguen como siempre.
        if tecla == 'escape' then
            self:salirPie()
            return nil
        elseif tecla == 'space' then
            self.caminante:saltar()
            return nil
        end
    end
    if tecla == 'escape' then
        if self.arrastre and self.arrastre.girar then
            self:liberarRaton()
            return nil
        end
        if self.control.cuenta > 0 then
            self.control:vaciar()
            return nil
        end
        return 'salir'
    elseif tecla == 'p' then
        self.pausa = not self.pausa
    elseif tecla == 't' or tecla == 'l' then
        -- Todos los tanques o lanzacohetes (con Mayús, se suman).
        local tipo = ({ t = 'tanque', l = 'lanzacohetes' })[tecla]
        self.control:todasDeTipo(tipo, love.keyboard.isDown('lshift', 'rshift'))
    elseif tecla == 'h' and not Escena.enPreparacion(self) then
        self.control:mantener()
    end
end

--- Captura relativa mientras se mantiene el botón derecho: el borde de la
-- pantalla no interrumpe la rotación en primera persona.
function Escena:pulsar(x, y, boton)
    if self.caminante then
        -- A pie no hay puntero: los clics de elegir y ordenar no aplican.
        return
    end
    if self.arrastre and self.arrastre.girar then
        return
    end
    if boton == 1 and self.vistaDespliegue and self.vistaDespliegue:sobreListo(x, y) then
        self:pulsarListo()
        return
    end
    self.arrastre = {
        x = x,
        y = y,
        inicioX = x,
        inicioY = y,
        totalX = 0,
        totalY = 0,
        boton = boton,
        girar = boton == 2,
        movido = false,
    }
    if boton == 2 then
        self.arrastre.relativoAnterior = love.mouse.getRelativeMode()
        love.mouse.setRelativeMode(true)
    end
end

--- Devuelve el cursor al modo anterior y cancela el arrastre activo.
function Escena:liberarRaton()
    local arrastre = self.arrastre
    self.arrastre = nil
    if arrastre and arrastre.girar then
        love.mouse.setRelativeMode(arrastre.relativoAnterior)
        if not arrastre.relativoAnterior then
            love.mouse.setPosition(arrastre.inicioX, arrastre.inicioY)
        end
    end
end

--- Alt-tab cancela el gesto para no dejar el cursor capturado al volver.
function Escena:foco(enfocada)
    if self.caminante then
        -- Fuera de la ventana el ratón queda libre; al volver, se captura.
        love.mouse.setRelativeMode(enfocada)
    end
    if not enfocada then
        self:liberarRaton()
        self.camara:detener()
    end
end

--- Usa los deltas reales de LÖVE aunque el cursor no cambie de coordenadas.
function Escena:mover(x, y, dx, dy)
    if self.caminante then
        self.camara:arrastrar(dx or 0, dy or 0, true)
        return
    end
    local a = self.arrastre
    if a then
        dx = dx or x - a.x
        dy = dy or y - a.y
        a.totalX = a.totalX + dx
        a.totalY = a.totalY + dy
        if a.totalX * a.totalX + a.totalY * a.totalY > 6 * 6 then
            a.movido = true
        end
        if a.girar then
            self.camara:arrastrar(dx, dy, true)
            self.seguirMisil = false
        elseif a.boton == 1 and a.movido then
            -- Arrastrar con el izquierdo: cuadro de selección.
            self.control:cuadro(a.inicioX, a.inicioY, x, y)
        end
        a.x, a.y = x, y
    end
end

--- Suelta un botón. Izquierdo: clic = elegir (Mayús suma o quita; doble clic,
-- las de su tipo a la vista); arrastre = cuadro. Derecho sin arrastrar: orden
-- (mover al terreno o atacar al enemigo bajo el ratón); arrastrado era mirar.
function Escena:soltar(x, y, boton)
    local a = self.arrastre
    if not a or a.boton ~= boton then
        return
    end
    self:liberarRaton()
    if a.girar then
        -- El suavizado deja parte del giro para los cuadros siguientes; al
        -- soltar el botón se consume ya, para que la mirada no siga sola.
        self.camara:terminarGiro()
    end
    local sumar = love.keyboard.isDown('lshift', 'rshift')
    if boton == 1 and a.movido then
        self.control:elegirCaja(a.inicioX, a.inicioY, x or a.x, y or a.y, sumar)
    elseif boton == 1 then
        self.control:click(x or a.inicioX, y or a.inicioY, sumar)
    elseif boton == 2 and not a.movido and not self:enPreparacion() then
        -- En la preparación no hay órdenes (la colocación llega en el paso 2).
        self.control:ordenar(a.inicioX, a.inicioY)
    end
end

--- La rueda desplaza físicamente al observador, manteniendo la lente fija.
function Escena:rueda(dy)
    self.seguirMisil = false
    self.camara:avanzar(dy)
end

--- Punto de la vista del mapa (isométrica) en el centro de la batalla: para
-- comparar el mismo sitio en el mapa.
function Escena.vistaDelCentro(mundo, combate)
    local x, y = combate.cx, combate.cy
    return Iso.vista(x, y, math.max(0, mundo.terreno:altura(x, y)))
end

return Escena
