-- Nations RTS: un mundo procedural infinito en isométrico.
--
--   WASD / flechas   moverse          rueda        zoom
--   botón derecho    arrastrar        N            mundo nuevo (otra semilla)
--   C                ir a la ciudad más cercana
--   clic             ver una ciudad   T            mostrar u ocultar territorios
--   espacio          pausa            1 2 3 4      un día dura 60 s, 20 s, 5 s o 1 s
--   G                provocar una guerra entre la ciudad más cercana y su vecina
--   F5 / F9          guardar / cargar la partida (el mundo vivo; el físico sale de la semilla)
--   V                seguir con la cámara a un grupo en marcha (otra vez: el siguiente)
--   clic en una instalación o base: su panel (guarnición, fortificación, daños)
--   F3               capa técnica (semilla, trozos, FPS)   Esc   cerrar el pendón o salir
--   B                modo jugador: la lista de tus batallas en curso, con «Entrar»;
--                    observador: ver en 3D el combate más cercano (solo mirar).
--                    Esc vuelve al mapa (prototipo: batalla/escena.lua)
--   clic en un yacimiento: su pendón (lo que queda, quién recolecta y, en
--                    modo jugador, «Recolectar» o «Atacar a los recolectores»)
--   --dream          usa 3DreamEngine solo para renderizar la batalla 3D
--   --hora <f>       con --dream: la batalla a esa fracción del día (capturas)
--   --calidad <c>    con --dream: calidad del dibujo de la batalla, baja, media
--                    o alta (por defecto; batalla/dream/calidad.lua)
--   clic en un estandarte: el panel de ese ejército (líder, poder, composición)
--
-- `love . <semilla> --jugador` (modo jugador, para probar el combate 3D):
-- gobiernas la nación cuya capital está más cerca del origen, en guerra con
-- su vecina (comando `escenarioPrueba`). Para atacar se va al objetivo: con
-- un ejército elegido, clic en el sitio enemigo; sin él, el clic abre el menú
-- radial del sitio (interfaz/radial.lua) con «Atacar» (elige qué llevar y
-- desde dónde), «Explorar» e «Info». Un día antes de que llegue un
-- ataque contra lo tuyo sale un aviso; al empezar una batalla tuya, un pregón
-- con «Defender» y «Atacar» (si no eliges, no entras a la batalla y se
-- resuelve sola). Se puede entrar a mitad desde la lista de batallas (B).
-- En la batalla el mundo sigue, más lento; al salir, las bajas vuelven a la
-- simulación (`resolverBatalla`).
--
-- `love . <semilla> --batalla-vivo [x y]` abre el juego y
-- entra enseguida en un combate (uno real si ya hay alguno; si no, uno de
-- prueba entre la ciudad más cercana y su vecina extranjera). Con x/y genera la prueba en campo abierto
-- en esas coordenadas del mismo mundo (px, 10 px = 1 m). Esc vuelve al mapa.
--
-- Todo sale de la semilla: el terreno, las plantas (ninguna igual), las
-- ciudades (en sitios al azar, cada una distinta) y sus habitantes. El mundo se
-- va generando mientras exploras: ver mundo/mundo.lua.

-- Más memoria para el código que compila LuaJIT (Andrés): con la de serie
-- (512 KB, 1000 trazas) la simulación la llena, LuaJIT la vacía y recompila
-- una y otra vez, y un día cuesta el doble. No cambia ningún resultado.
if jit then
    jit.opt.start('maxmcode=8192', 'maxtrace=8000')
end

local Mundo = require('mundo.mundo')
local Simulacion = require('mundo.simulacion')
local Ayudas = require('mundo.simulacion.ayudas')
local Iso = require('mundo.iso')
local Escena = require('batalla.escena')
local Tema = require('interfaz.tema')
local Vida = require('interfaz.vida')
local BarraSuperior = require('interfaz.barrasuperior')
local Columna = require('interfaz.columna')
local Navegacion = require('interfaz.navegacion')
-- El almacén de cada nación para los scripts (global `Almacen`, almacen/almacen.lua).
require('almacen.almacen')
local PanelTropas = require('interfaz.tropas')
local Pendon = require('interfaz.pendon')
local Noticias = require('interfaz.noticias')
local Pregon = require('interfaz.pregon')
local Placa = require('interfaz.placa')
local Envio = require('interfaz.envio')
local Ficha = require('interfaz.ficha')
local Plantar = require('interfaz.plantar')
local ListaBatallas = require('interfaz.batallas')
local Galeria = require('interfaz.galeria')
local Perfil = require('interfaz.perfil')
local Opciones = require('interfaz.opciones')
local Arsenal = require('interfaz.arsenal')
local Ajustes = require('interfaz.ajustes')
local Ejercito = require('interfaz.ejercito')
local Acero = require('interfaz.acero')
local Radial = require('interfaz.radial')
local Explorar = require('interfaz.explorar')
local Fabrica = require('interfaz.fabrica')
local VentanaPoblacion = require('interfaz.poblacion')
local Inteligencia = require('interfaz.inteligencia')
local Choques = require('mundo.choques')
-- Registro para el agente (depurar/registro.lua, Andrés): `--registro [canales]`.
local Registro = require('depurar.registro')
-- La partida en un solo archivo, con autoguardado (partida/guardado.lua).
local Partida = require('partida.guardado')
local MemoriaAlmacen = require('almacen.memoria')
local registro

local mundo
local camara = { x = 0, y = 0, zoom = 0.2 }
-- Límites del zoom del mapa 2D (el dueño, 2026-09-30): de 4 % a 13 %.
local ZOOM_MIN, ZOOM_MAX = 0.04, 0.13
-- Vista lejana (el dueño, 2026-09-30): por debajo del 7 % el mapa solo se mira
-- (sin órdenes, recolectar, atacar ni plantar); vuelve a poder usarse al
-- acercarse otra vez hasta el 10 %.
local ZOOM_ENTRA_LEJOS, ZOOM_SALE_LEJOS = 0.07, 0.10
local vistaLejana = false
-- Lo que se ve con el zoom más lejano se genera siempre por adelantado.
Mundo.zoomMinimo = ZOOM_MIN
-- Pantalla de carga al empezar un mundo: { inicio, fraccion } hasta que está
-- generado todo lo de alrededor de la cámara (`Mundo:cargar`).
local carga
-- Pantalla de inicio y salida del juego, en una sola tabla (main ya roza el
-- tope de 200 variables locales de Lua):
--   login       la pantalla de inicio (interfaz/login.lua); nil: ya se juega;
--   semilla     la de la partida que empieza «Invitado»;
--   fondo       el fondo del inicio, que es también el de la pantalla de carga;
--   dialogo     «¿Salir del juego?» (el dueño, 2026-10-01): Esc en el inicio y
--               la X de la ventana (`love.quit`), en el inicio y en la partida;
--   preguntar   solo se pregunta en el juego normal (no en capturas ni pruebas);
--   saliendo    deja pasar el cierre ya confirmado;
--   canales     los del registro de Andrés (`--registro`).
local inicio = {
    sombraCarga = nil, -- malla del oscurecido de abajo de la pantalla de carga
    Login = require('interfaz.login'),
    fondo = require('interfaz.fondoLogin').nuevo(),
    dialogo = require('interfaz.dialogoSalir').nuevo(),
    preguntar = false,
    saliendo = false,
}
-- Posición de la cámara en el cuadro anterior: su velocidad, para generar
-- por delante de ella.
local camaraAntes
local arrastre
local seleccionada
local VELOCIDADES = { 1 / 60, 1 / 20, 1 / 5, 1 } -- días por segundo: un día dura 60 s, 20 s, 5 s o 1 s
local pausa = false
local siguiendo -- id del grupo que sigue la cámara
local ejercito = Ejercito.nuevo() -- selección y órdenes de ejércitos (interfaz/ejercito.lua)
local instalacionVista -- id de la instalación cuyo panel se muestra
local minaVista -- id del yacimiento cuyo pendón se muestra
-- Interfaz «Acero» (interfaz/*.lua): barra de recursos arriba, columna de
-- acciones a la izquierda, navegación abajo al centro, panel de ciudad,
-- instalación o mina a la derecha, noticias abajo a la izquierda, placa de
-- lugar arriba al centro y avisos de lo grave a la derecha.
local barraSuperior = BarraSuperior.nuevo()
local columna = Columna.nuevo()
-- Casillas de capas del mapa estratégico, bajo la columna (zoom lejano).
local casillasCapas = require('interfaz.casillasCapas').nuevo()
local navegacion = Navegacion.nuevo()
local panelTropas = PanelTropas.nuevo() -- tarjetas de los grupos que están fuera (interfaz/tropas.lua)
local pendon = Pendon.nuevo()
local noticias = Noticias.nuevo()
local pregon = Pregon.nuevo()
local placa = Placa.nuevo()
local perfil = Perfil.nuevo() -- pantalla del perfil de la nación (interfaz/perfil.lua)
local opciones = Opciones.nuevo() -- pantalla de opciones (interfaz/opciones.lua)
local arsenal = Arsenal.nuevo() -- pantalla del arsenal (interfaz/arsenal.lua)
local cerradaAqui -- ciudad donde se está cuyo pendón se cerró (no se vuelve a abrir solo)
-- Menú radial de un sitio o una mina (modo jugador, interfaz/radial.lua) y
-- el panel de exploración que abre su «Explorar» (interfaz/explorar.lua).
local radial = Radial.nuevo()
local explorando
local focoCamara -- punto de la vista hacia el que se desliza la cámara (al abrir el radial)
local favoritas = {} -- id de sitio -> true: marcados con la estrella del radial (solo la vista)
local capaTecnica = false -- F3: semilla, trozos, plantas y FPS
-- Panel lateral de ciudad (interfaz/pendon.lua, `dibujarCiudad`): el dueño lo
-- quita (2026-09-30); al tocar una ciudad sale el menú radial con su tarjeta
-- de datos (diseno/referencias-warpath/radial_ciudad_propia.jpg). `true` lo
-- devuelve como era: se abre solo en la ciudad donde está la cámara y al
-- tocar la placa de lugar.
local PANEL_CIUDAD = false
-- `love . <semilla> --captura <cuadros> <archivo> [dx dy zoom]`: avanza, se mueve y guarda una imagen.
local captura
-- `--medir` (con `--captura`): tiempos de cada cuadro, de la generación del
-- mundo y huecos sin generar a la vista; se imprimen al tomar la foto.
local medicion
-- Escena de batalla en 3D abierta (nil: se ve el mapa). Mientras está abierta,
-- el mapa no se actualiza: al volver, todo sigue donde estaba.
local batalla
local batallaCaptura -- `--batalla`: { modo, cuadros, combate }
-- El almacén por dentro en 3D (almacen/escena.lua), o nil. Como la batalla:
-- mientras está abierto, sus teclas y su ratón; Esc vuelve al mapa.
local almacenVista
local AUTOGUARDADO = 300
local partidaLista = false
local relojAutoguardado = 0
local almacenAlEntrar -- `--almacen`: abre el juego dentro del almacén
local almacenVideo -- `--almacen-video [salida.mp4]`: almacen/video_robot.lua
local batallaVivo -- `--batalla-vivo`: { x, y, espera } hasta entrar en ella
-- Modo `--jugador`: { jugador, rival, capitalJugador, capitalRival } (ids) de
-- `escenarioPrueba`. Nil: se mira el mundo como observador.
local modoJugador = false
local galeria = false -- `--galeria`: en vez del juego, la pantalla de componentes (interfaz/galeria.lua)
local jugador
local envio -- panel para elegir cuánto llevar a un ataque (interfaz/envio.lua), o nil
-- Panel pequeño de encargo del radial de tu ciudad: crear soldados, producir
-- munición o reparar y taller (interfaz/fabrica.lua), o nil.
local fabrica
-- Ventana de la población de tu ciudad (interfaz/poblacion.lua), o nil.
local ventanaPoblacion
local plantando -- modo de colocación de una bandera (interfaz/plantar.lua), o nil
local panelFicha = Ficha.nuevo()
local fichaVista -- id del grupo cuyo panel de ficha se muestra
local redirigiendo -- id del grupo propio cuyo destino se elige en la ficha («Redirigir a…»)
local listaBatallas = ListaBatallas.nuevo()
local avisadosAtaque = {} -- id de grupo enemigo -> true (su aviso de ataque ya salió)
local avisadosMunicion = {} -- 'grupo:munición' -> true (su aviso de munición baja ya salió)
local preguntadas = {} -- id de batalla -> pregón «Defender / Atacar» (una vez)
-- Batalla de la simulación que se ve en 3D: { id, combate }. Al salir, sus
-- bajas vuelven con `resolverBatalla`.
local enEscena
local ESPERA_BATALLA = 6 -- segundos del pregón; si no se elige, la batalla se resuelve sola
local RITMO_BATALLA = 0.25 -- el mundo sigue a esta parte de su velocidad mientras se pelea (ritmoBatalla)
-- Definidas más abajo (junto a los clics), usadas antes en love.update.
local entrarEnBatalla, entrarEnBatallaSim, salirDeBatalla, mandarAtaque, vigilarBatallas
local botonesCiudad, botonesInstalacion, botonesMina, botonesFicha, abrirAtaque, nombreSitio
local accionRadial, opcionesRadial, objetivoRadial, trayectoExplorador
local filasEconomia, mandarComandos, abastecerGrupo, mandarArsenal, accionTropas

--- Modo jugador: registra las naciones de alrededor del origen y pide a la
-- simulación el escenario de prueba (tu nación y su rival, en guerra). La
-- cámara va a tu capital y las fichas se ven como las ve tu nación.
local function iniciarJugador()
    mundo:registrarNacionDe(0, 0)
    local r = mundo.sim:ejecutar({ tipo = 'escenarioPrueba' })
    if not r then
        mundo.sim:noticia('Modo jugador: no hay dos naciones vivas cerca', { 1, 0.7, 0.5 })
        return
    end
    jugador = r
    mundo.mira = r.jugador
    local c = mundo.sim:ciudad(r.capitalJugador)
    camara.x, camara.y = Iso.vista(c.x, c.y, mundo.terreno:altura(c.x, c.y))
end

--- Entra en el modo de plantar bandera (o sale, si ya estaba). Solo en modo jugador.
local function alternarPlantar()
    if plantando then
        plantando = nil
    elseif jugador and mundo.sim:nacion(jugador.jugador) then
        envio = nil
        plantando = Plantar.nuevo(jugador.jugador)
    end
end

--- Punto del suelo bajo el punto (sx, sy) de la pantalla.
local function sueloEnPantalla(sx, sy)
    local w, h = love.graphics.getDimensions()
    local vx = camara.x + (sx - w / 2) / camara.zoom
    local vy = camara.y + (sy - h / 2) / camara.zoom
    return Plantar.sueloBajo(mundo.terreno, vx, vy)
end

--- Nombre de la nación del jugador (nil si solo se mira): los pregones de
-- banderas solo salen si la nombran.
local function nombreJugador()
    local n = jugador and mundo.sim:nacion(jugador.jugador)
    return n and n.nombre or nil
end

local function empezar(semilla)
    mundo = Mundo.nuevo(semilla)
    -- Partida nueva: lo del almacén empieza vacío (si se carga una guardada,
    -- lo pone su sección) y no se autoguarda hasta que el mundo esté hecho.
    MemoriaAlmacen.cargar(nil)
    partidaLista = false
    relojAutoguardado = 0
    carga = { inicio = love.timer.getTime(), fraccion = 0 }
    camaraAntes = nil
    seleccionada = nil
    cerradaAqui = nil
    ejercito:reiniciar()
    jugador, envio, fichaVista, redirigiendo = nil, nil, nil, nil
    fabrica, ventanaPoblacion = nil, nil
    avisadosAtaque, preguntadas, enEscena, minaVista = {}, {}, nil, nil
    avisadosMunicion = {}
    plantando = nil
    listaBatallas.abierta = false
    radial:cerrar()
    explorando, focoCamara = nil, nil
    noticias.abierta, noticias.vista = false, nil
    pregon:reiniciar()
    local ciudad = mundo:ciudadInicial()
    if ciudad then
        camara.x, camara.y = Iso.vista(ciudad.x, ciudad.y, ciudad.altura)
    else
        camara.x, camara.y = 0, 0
    end
    if modoJugador then
        iniciarJugador()
    end
end

--- Rectángulo de la vista que ocupa la pantalla.
--- Provoca una guerra: la nación de la ciudad más cercana contra la nación
-- vecina más próxima (para ver cómo funciona sin esperar a que estalle sola).
--- Datos vivos de una ciudad dibujable (los de la simulación) y su nación.
local function datosDe(ciudad)
    local datos = ciudad and mundo.sim:ciudad(ciudad.region)
    return datos, datos and mundo.sim:nacion(datos.nacion)
end

local function provocarGuerra()
    local cx, cy = Iso.mundo(camara.x, camara.y)
    local ciudad = mundo:ciudadMasCercana(cx, cy)
    local datos, nacion = datosDe(ciudad)
    if not nacion then
        return
    end
    local mejor, mejorD
    for _, otra in pairs(mundo.ciudadesVistas) do
        local _, suya = datosDe(otra)
        if suya and suya ~= nacion then
            local d = (otra.x - datos.x) ^ 2 + (otra.y - datos.y) ^ 2
            if not mejor or d < mejorD then
                mejor, mejorD = suya, d
            end
        end
    end
    if mejor then
        -- La relación de las dos baja a -90 por el mismo camino que la diplomacia
        -- (las dos a la vez y dentro de -100 a 100).
        Ayudas.cambiarRelacion(mundo.sim, nacion.id, mejor.id, -90 - mundo.sim:relacion(nacion.id, mejor.id))
        -- Igual que lo haría un gobernante (o, más adelante, un jugador): un comando.
        mundo.sim:ejecutar({ tipo = 'declararGuerra', nacion = nacion.id, contra = mejor.id })
    end
end

-- Autoguardado (el dueño, 26-nov): cada `AUTOGUARDADO` s de juego, al salir
-- del almacén o de una batalla y al cerrar el juego; al abrirlo sigue la
-- partida guardada. Solo en el juego normal (el que abre en la pantalla de
-- inicio): las pruebas y las capturas no tocan la partida.
-- `partidaLista`: el mundo ya está cargado (y, al abrir, la partida
-- guardada puesta): antes no se guarda nada, para no pisar la partida con un
-- mundo a medio hacer.

--- Escribe la partida entera (el mundo vivo y lo del almacén). Devuelve
-- true, o false y el motivo.
local function escribirPartida()
    -- Lo del almacén abierto, al día (cajas, ordenadores, muro).
    if almacenVista and almacenVista.guardarDisposicion then
        almacenVista:guardarDisposicion()
    end
    local t0 = love.timer.getTime()
    local bien, motivo = Partida.guardar(mundo.sim)
    print(string.format('PARTIDA guardada día %s en %.0f ms%s', tostring(mundo.sim.estado.dia), (love.timer.getTime() - t0) * 1000, bien and '' or (': ' .. tostring(motivo))))
    relojAutoguardado = 0
    return bien, motivo
end

--- Autoguardado: solo en el juego normal y con la partida lista.
local function autoguardar()
    if inicio.preguntar and partidaLista and mundo and mundo.sim then
        escribirPartida()
    end
end

--- F5 o «Guardar» de las opciones.
local function guardarPartida()
    local bien, motivo = escribirPartida()
    if bien then
        mundo.sim:noticia('Partida guardada (F9 para cargarla)', { 0.7, 1, 0.7 })
    else
        mundo.sim:noticia('No se pudo guardar la partida: ' .. tostring(motivo), { 1, 0.7, 0.5 })
    end
end

local function cargarPartida()
    if not love.filesystem.getInfo(Partida.archivo) then
        mundo.sim:noticia('No hay partida guardada que cargar', { 1, 0.7, 0.5 })
        return
    end
    local sim, ponerSecciones = Partida.cargar(mundo:opcionesSimulacion())
    if not sim then
        mundo.sim:noticia('No se puede cargar la partida: ' .. tostring(ponerSecciones), { 1, 0.7, 0.5 })
        return
    end
    if sim.estado.semilla ~= mundo.semilla then
        empezar(sim.estado.semilla)
    end
    mundo:usarSimulacion(sim)
    ponerSecciones()
    pregon:reiniciar()
    print('PARTIDA cargada día ' .. tostring(sim.estado.dia))
    sim:noticia('Partida cargada: día ' .. sim.estado.dia, { 0.7, 1, 0.7 })
end

--- Sigue al siguiente ejército en marcha (o deja de seguir si no hay).
local function seguirEjercito()
    local ids = Simulacion.ordenadas(mundo.sim.estado.grupos)
    if #ids == 0 then
        siguiendo = nil
        return
    end
    local siguiente = ids[1]
    for k, id in ipairs(ids) do
        if id == siguiendo then
            siguiente = ids[k % #ids + 1]
        end
    end
    siguiendo = siguiente
end

local function vistaActual()
    local w, h = love.graphics.getDimensions()
    local vw, vh = w / camara.zoom, h / camara.zoom
    return { x = camara.x - vw / 2, y = camara.y - vh / 2, w = vw, h = vh }
end

--- Empieza la partida (la primera, desde la pantalla de inicio o directa) y,
-- con `--registro`, su registro.
function inicio.empezarPartida(semilla)
    empezar(semilla)
    -- Registro (Andrés): JSONL en <guardado>/registro/<fecha>_<semilla>.jsonl.
    if inicio.canales and not registro then
        love.filesystem.createDirectory('registro')
        registro = Registro.nuevo({
            carpeta = love.filesystem.getSaveDirectory() .. '/registro',
            semilla = semilla,
            canales = inicio.canales,
            reloj = love.timer.getTime,
        })
        registro:seguir(mundo.sim)
        print('REGISTRO', registro.ruta)
    end
end

--- Modo de captura de la pantalla de inicio (`--captura <cuadros> <archivo>
-- 0 0 - - login`), o nil.
function inicio.capturaDeLogin(argumentos)
    for k, valor in ipairs(argumentos) do
        if valor == '--captura' then
            local modo = argumentos[k + 7]
            if modo == 'login' or modo == 'loginPanel' or modo == 'loginSalir' then
                return modo
            end
        end
    end
    return nil
end

--- Capturas de la pantalla de inicio: `login`, tal como abre; `loginPanel`,
-- en uso (los dos campos escritos, el foco en la contraseña, «Recordarme»
-- marcado, el ratón sobre «ENTRAR» y el aviso de «Próximamente»);
-- `loginSalir`, la pregunta de Esc.
function inicio.prepararCapturaDeLogin(modo)
    if modo == 'loginPanel' then
        inicio.login.usuario:escribir('comandante@forja.es')
        inicio.login.clave:escribir('estandarte')
        inicio.login.foco = 'clave'
        inicio.login.recordar = true
        inicio.login.encimaFijo = 'entrar'
        inicio.login:proximamente()
    elseif modo == 'loginSalir' then
        inicio.atenderLogin(inicio.login:tecla('escape'))
    end
end

--- Abre la pregunta de salir (suelta antes el ratón de la batalla, si lo tiene).
function inicio.abrirPreguntaSalir()
    if batalla and batalla.foco then
        batalla:foco(false)
    end
    inicio.dialogo:abrir()
end

--- Sale del juego de verdad (ya confirmado).
function inicio.salirDelJuego()
    inicio.saliendo = true
    love.event.quit()
end

--- La pregunta de salir atiende la entrada mientras está abierta. Devuelve
-- true si la ha usado. `tipo`: 'pulsar', 'soltar', 'tecla' u 'otro'.
function inicio.atenderDialogoSalir(tipo, a, b, c)
    if not inicio.dialogo.abierto then
        return false
    end
    local accion
    if tipo == 'pulsar' then
        inicio.dialogo:pulsar(a, b, c)
    elseif tipo == 'soltar' then
        accion = inicio.dialogo:soltar(a, b, c)
    elseif tipo == 'tecla' then
        accion = inicio.dialogo:tecla(a)
    end
    if accion == 'salir' then
        inicio.salirDelJuego()
    end
    return true
end

--- «Invitado»: deja la pantalla de inicio y empieza la partida sin conexión.
function inicio.entrarComoInvitado()
    inicio.login:cerrar()
    inicio.login = nil
    -- Con una partida guardada, su mundo (se sigue al acabar de cargar).
    inicio.empezarPartida(Partida.semilla() or inicio.semilla)
end

--- Lo que pide la pantalla de inicio: entrar como invitado o salir del juego.
function inicio.atenderLogin(accion)
    if accion == 'invitado' then
        inicio.entrarComoInvitado()
    elseif accion == 'preguntarSalir' then
        inicio.abrirPreguntaSalir()
    end
end

function love.load(arg)
    love.graphics.setBackgroundColor(0.93, 0.66, 0.52)
    -- Que la pantalla no se apague mientras se juega o se mira (el dueño,
    -- 19-nov: el monitor se apagaba viendo patrullar al robot).
    love.window.setDisplaySleepEnabled(false)
    Tema.actualizar()
    -- Los scripts leen el almacén de la partida en curso y del jugador.
    Almacen.instalar(function()
        return mundo and mundo.sim
    end, function()
        return jugador and jugador.jugador
    end)
    -- Lo que va en la partida además del mundo vivo (partida/guardado.lua):
    -- lo del almacén 3D de cada nación y quién es el jugador.
    Partida.registrar('almacen', MemoriaAlmacen.guardar, MemoriaAlmacen.cargar)
    Partida.registrar('jugador', function()
        return jugador
    end, function(datos)
        if type(datos) == 'table' and datos.jugador and mundo.sim:nacion(datos.jugador) then
            jugador = datos
            mundo.mira = datos.jugador
        end
    end)
    -- Modo por defecto (NationsRTS, dueño 2026-09-29): --dream y --jugador
    -- siempre activos. Los agentes nuevos o sesiones sin acordarse de las
    -- flags ya no quedan en observador ni con el render básico de batalla.
    -- Las flags explícitas en la línea de comandos siguen funcionando.
    if not arg then
        arg = {}
    end
    local yaEsta = {}
    for _, v in ipairs(arg) do
        yaEsta[v] = true
    end
    if not yaEsta['--dream'] then
        arg[#arg + 1] = '--dream'
    end
    if not yaEsta['--jugador'] then
        arg[#arg + 1] = '--jugador'
    end
    local semilla = tonumber(arg[1]) or os.time() % 100000
    if yaEsta['--medir'] then
        medicion = { inicio = love.timer.getTime(), cuadros = {}, generar = {}, conHuecos = 0, maxHuecos = 0 }
        love.window.setVSync(0)
    end
    -- Ajustes del jugador (interfaz/ajustes.lua): antes de leer los
    -- argumentos, para que `--calidad` gane sobre el archivo.
    Ajustes.aplicar(Ajustes.cargar(), false)
    local tamDado
    for k, valor in ipairs(arg) do
        if valor == '--dream' then
            Escena = require('batalla.dream.escena')
        end
        if valor == '--hora' then
            -- `--hora <fracción del día>` (con --dream): la batalla se ve a esa
            -- hora en vez de la del reloj del mundo. 0 amanecer, 0,31 mediodía,
            -- 0,56 atardecer, 0,81 medianoche (batalla/dream/luz.lua).
            require('batalla.dream.escena').fraccionFija = tonumber(arg[k + 1])
        end
        if valor == '--calidad' then
            -- `--calidad <baja|media|alta>` (con --dream): distancias de detalle,
            -- sombras y oclusión de la batalla (batalla/dream/calidad.lua).
            local Calidad = require('batalla.dream.calidad')
            if not Calidad.elegir(arg[k + 1] or '') then
                print('CALIDAD desconocida: ' .. tostring(arg[k + 1]) .. ' (baja, media o alta)')
            end
        end
        if valor == '--jugador' then
            modoJugador = true
        end
        if valor == '--pestana' then
            -- `--pestana <resumen|ejercito|nacion|relaciones>`: la pestaña con
            -- la que se abre el panel de una ciudad (para las capturas).
            pendon.pestana = arg[k + 1] or 'resumen'
        end
        if valor == '--galeria' then
            galeria = true
        end
        if valor == '--arsenal' then
            -- `--arsenal <tarjeta> [categoría] [pestaña]` (con `--captura ...
            -- arsenal`): lo elegido al abrir el Arsenal ('scudb',
            -- 'soldados'...), su categoría ('terrestres', 'artilleria',
            -- 'infanteria', 'municion' o '-' para la suya) y la pestaña
            -- ('ficha', 'producir', 'comparar' o 'variantes').
            local sel, cat, pestana = arg[k + 1], arg[k + 2], arg[k + 3]
            if sel and sel:sub(1, 2) ~= '--' then
                arsenal.sel = sel
            end
            if cat and cat:sub(1, 2) ~= '--' then
                arsenal.cat = cat
                if pestana and pestana:sub(1, 2) ~= '--' then
                    arsenal.pestana = pestana
                end
            end
        end
        if valor == '--tope-mundo' then
            -- `--tope-mundo <MB>`: tope de memoria del mundo generado (para
            -- probar el descarte y la vuelta desde el disco).
            require('mundo.comarcas').tope = (tonumber(arg[k + 1]) or 1536) * 1048576
        end
        if valor == '--tam' then
            -- `--tam <ancho>x<alto>`: tamaño de la ventana (para las capturas de
            -- la interfaz a 1920x1080 y a 1280x720).
            local ancho, alto = (arg[k + 1] or ''):match('^(%d+)x(%d+)$')
            if ancho then
                tamDado = true
                love.window.setMode(tonumber(ancho), tonumber(alto), { resizable = true, msaa = 4, depth = 24 })
                Tema.actualizar()
            end
        end
        -- `--observador` está reservada por si en el futuro se quiere volver
        -- al modo de solo mirar (sin gobierno del jugador). Por ahora no se
        -- usa: --dream y --jugador se imponen siempre (love.load, líneas
        -- 270-271), así que ningún lanzamiento normal entra en observador.
        -- Las flags desconocidas no fallan, así que basta esta constancia.
    end
    -- Las capturas abren en una ventana fija; las de los robots
    -- (BATALLA_ROBOTS_FOTOS), con sus ajustes de siempre (pantalla completa):
    -- El dueño las mira en su monitor.
    if not tamDado and (not yaEsta['--captura'] or os.getenv('BATALLA_ROBOTS_FOTOS')) then
        Ajustes.aplicar(Ajustes.valores, true)
        Tema.actualizar()
    end
    inicio.semilla = semilla
    inicio.canales = Registro.canalesDeArgumentos(arg)
    -- El juego abre en la pantalla de inicio, salvo las pruebas y las capturas
    -- del juego (las de la pantalla de inicio la abren: `login`, `loginPanel`
    -- y `loginSalir`).
    almacenAlEntrar = yaEsta['--almacen'] or yaEsta['--almacen-video']
    if yaEsta['--seguir'] then
        require('almacen.escena').seguirAlEntrar = true
    end
    for k, valor in ipairs(arg or {}) do
        if valor == '--fabricar' then
            require('almacen.escena').fabricarAlEntrar = tonumber(arg[k + 1]) or 1
        end
    end
    if yaEsta['--almacen-video'] then
        local ruta = 'robot_almacen.mp4'
        for k, valor in ipairs(arg or {}) do
            if valor == '--almacen-video' and arg[k + 1] and arg[k + 1]:match('%.mp4$') then
                ruta = arg[k + 1]
            end
        end
        almacenVideo = require('almacen.video_robot').nuevo(ruta)
        local EscenaAlmacen = require('almacen.escena')
        EscenaAlmacen.grabacion = almacenVideo
        EscenaAlmacen.repetirEncargos = false
    end
    local modoLogin = inicio.capturaDeLogin(arg)
    local sinLogin = galeria
        or yaEsta['--jugador']
        or yaEsta['--batalla']
        or yaEsta['--batalla-vivo']
        or yaEsta['--test-ejercito']
        or yaEsta['--check-grupo']
        or yaEsta['--visual-grupo']
        or yaEsta['--visual-rts']
        or yaEsta['--almacen']
        or yaEsta['--almacen-video']
        or (yaEsta['--captura'] and not modoLogin)
    if sinLogin then
        inicio.empezarPartida(semilla)
    else
        inicio.login = inicio.Login.nuevo(yaEsta['--captura'], inicio.fondo)
        inicio.prepararCapturaDeLogin(modoLogin)
        inicio.preguntar = not yaEsta['--captura']
    end
    for k, valor in ipairs(arg or {}) do
        if valor == '--batalla' then
            -- Captura de la escena de batalla: busca (o provoca) un combate y
            -- entra en él. `--batalla <encuadre> <cuadros>`: encuadre 'normal',
            -- 'cerca', 'cohetes', 'adelantado' (un lanzacohetes del defensor
            -- puesto delante), 'lejos',
            -- 'preparacion' (la fase de preparación: zonas, contador y «Listo»),
            -- 'listo' (la preparación con «Listo» pulsado al segundo: el combate
            -- ya empezado), 'borde' (la preparación con la cámara empujada fuera
            -- de su zona: el recinto la deja en el borde; dice cuántos rivales se
            -- ven); el resto de encuadres se saltan la preparación,
            -- 'duracion' (corre la pelea deprisa hasta que termina y dice cuánto
            -- ha durado) o 'mapa' (el mismo sitio en el mapa); cuadros, los que
            -- corre la batalla antes de la foto (la foto espera, si hace falta,
            -- a que se vea lo que el encuadre quiere enseñar).
            batallaCaptura = {
                modo = arg[k + 1] or 'cerca',
                cuadros = tonumber(arg[k + 2]) or 240,
            }
            -- Sin vsync, para que los FPS de la captura digan lo que cuesta la escena.
            love.window.setVSync(0)
        end
        if valor == '--batalla-vivo' then
            batallaVivo = {
                x = tonumber(arg[k + 1]),
                y = tonumber(arg[k + 2]),
                espera = 0,
            }
        end
        if valor == '--captura' then
            -- En las capturas la interfaz no se anima (interfaz/vida.lua),
            -- salvo con `--vida`, para ver las animaciones a medias.
            Vida.quieta = not yaEsta['--vida']
            -- `--sinmapa`: el mapa sale como un fondo liso y solo se ve la
            -- interfaz (capturas para el diseñador).
            if mundo and yaEsta['--sinmapa'] then
                mundo.sinMapa = true
            end
            captura = {
                cuadros = tonumber(arg[k + 1]) or 120,
                archivo = arg[k + 2] or 'captura.png',
                modo = arg[k + 7], -- para la marca del registro (Andrés)
                dx = tonumber(arg[k + 3]) or 0,
                dy = tonumber(arg[k + 4]) or 0,
                zoom = tonumber(arg[k + 5]),
                velocidad = tonumber(arg[k + 6]),
                guerra = arg[k + 7] == 'guerra' or arg[k + 7] == 'guerrafija',
                seguir = arg[k + 7] == 'guerra',
                -- `idavuelta`: a mitad de los cuadros la cámara da la vuelta
                -- y regresa al punto de partida (lo ya visto no debe rehacerse).
                idaVuelta = arg[k + 7] == 'idavuelta' or nil,
                -- `campamento`: la cámara va al primer campamento terminado y
                -- la foto sale 90 cuadros después.
                campamento = arg[k + 7] == 'campamento' or nil,
                -- `retirada`: la cámara va al primer ejército que se retira, el
                -- día que se retira; `vuelta`, al primero que llega a casa en
                -- retirada; `recuperacion`, a la ciudad con más heridos en su
                -- cola, con su panel abierto. Al encontrarlo, el tiempo vuelve a
                -- ir a 1 día por minuto y la foto sale `retrasoFoto` cuadros después.
                retirada = arg[k + 7] == 'retirada' or nil,
                -- `avion`: la cámara va al primer avión de transporte que lleva
                -- un grupo, a mitad de viaje (mundo/simulacion/aviones.lua).
                avion = arg[k + 7] == 'avion' or nil,
                vuelta = arg[k + 7] == 'vuelta' or nil,
                recuperacion = (arg[k + 7] == 'recuperacion' or arg[k + 7] == 'acelerar') or nil,
                -- `acelerar`: como `recuperacion`, pero a los 20 cuadros hace clic
                -- en el primer botón de acelerar del panel (el mismo clic del ratón).
                acelerar = arg[k + 7] == 'acelerar' or nil,
                -- En `recuperacion`, el peso mínimo de la cola para la foto (el
                -- noveno valor; cada lanzacohetes pesa 400, un soldado 1).
                pesoMinimo = tonumber(arg[k + 8]) or 1,
                -- `asalto`: el día `cuando`, la capital con más lanzacohetes que
                -- tenga otra capital a tiro la ataca con todos ellos y media
                -- guarnición (el caso de los 10 lanzacohetes); la foto, de su
                -- panel, sale `retrasoFoto` días después.
                asalto = arg[k + 7] == 'asalto' or nil,
                -- `ataque`: la cámara va al primer ejército que combate en su objetivo.
                ataque = arg[k + 7] == 'ataque' or nil,
                -- `base`: la cámara va a la primera base terminada con al menos
                -- el noveno valor de lanzacohetes (1 si no se da) y abre su
                -- panel; la foto sale `retrasoFoto` cuadros después.
                base = arg[k + 7] == 'base' or nil,
                minLanzacohetes = tonumber(arg[k + 8]) or 1,
                -- Modo jugador (`--jugador`): `envio` abre el panel de envío
                -- el cuadro `cuando`; `atacar` manda ese cuadro el ataque a la
                -- capital rival (lo que propone el panel) y la cámara sigue a
                -- su estandarte; `ficha` abre el panel del primer estandarte a
                -- la vista; `pelea` manda el ataque y espera al pregón de
                -- combate (la foto, `retrasoFoto` cuadros después: con más de
                -- 6 s, ya dentro de la batalla).
                envio = arg[k + 7] == 'envio' or nil,
                -- `perfil`, `opciones` o `general` (opciones, subpantalla
                -- General): abren esa pantalla desde el primer cuadro.
                pantalla = ({
                    perfil = 'perfil',
                    perfilinfo = 'perfil',
                    opciones = 'opciones',
                    general = 'general',
                    resolucion = 'general',
                    creditos = 'creditos',
                    nueva = 'nueva',
                    arsenal = 'arsenal',
                })[arg[k + 7] or ''],
                -- `pendonpaz` / `pendonguerra`: abre el pendón de la ciudad
                -- ajena más cercana a tu capital de una nación con la que no
                -- estás (o sí estás) en guerra; `pendonbase`, el de la
                -- instalación ajena más cercana. `atacarotra`: en la de
                -- `pendonpaz` pulsa «Declarar guerra y atacar», manda el
                -- ataque propuesto y la cámara sigue a su estandarte;
                -- `enviopaz`, solo lo pulsa (el envío abierto).
                -- `pendonbandera`: el pendón de la bandera ajena más
                -- cercana; `atacarbandera`, además pulsa «Atacar» (el envío
                -- abierto contra ella).
                pendonAjeno = ({
                    pendonpaz = 1,
                    pendonguerra = 1,
                    pendonbase = 1,
                    atacarotra = 1,
                    enviopaz = 1,
                    pendonbandera = 1,
                    atacarbandera = 1,
                })[arg[k + 7] or ''] and arg[k + 7],
                -- `cruce`: como `atacar`, y la capital rival manda a la vez
                -- su ataque contra la tuya (dos estandartes que se cruzan).
                -- `choque`: como `cruce`, pero la foto sale `retrasoFoto`
                -- cuadros después del pregón de la batalla («Defender /
                -- Atacar»); `pelea`, lo mismo tras mandar el ataque.
                atacar = (
                    arg[k + 7] == 'atacar'
                    or arg[k + 7] == 'pelea'
                    or arg[k + 7] == 'cruce'
                    or arg[k + 7] == 'choque'
                ) or nil,
                cruce = arg[k + 7] == 'cruce' or nil,
                -- `tropas`: el cuadro `cuando` saca de tu capital varios grupos
                -- (uno parado, uno que ataca, uno con lanzacohetes y uno que
                -- recolecta) para ver el panel de tropas; `tropasradial` toca
                -- además la primera tarjeta (radial pequeño) y `tropastodos`
                -- pulsa «Seleccionar todos»; `tropasmuchas` saca además seis
                -- grupos pequeños (las tarjetas se desplazan); `tropasciudad`
                -- abre el radial de tu capital y pone cuatro avisos de prueba
                -- (para ver que no se pisan con el panel); `tropasregresar`
                -- pulsa «Seleccionar todos» y luego «Regresar». La foto,
                -- `retrasoFoto` cuadros después.
                tropas = ({
                    tropas = 1,
                    tropasradial = 1,
                    tropastodos = 1,
                    tropasmuchas = 1,
                    tropasciudad = 1,
                    tropasregresar = 1,
                })[arg[k + 7] or ''] and arg[k + 7],
                choque = arg[k + 7] == 'choque' or nil,
                pelea = arg[k + 7] == 'pelea' or nil,
                ficha = arg[k + 7] == 'ficha' or nil,
                -- Menú radial y noticias (modo jugador, el cuadro `cuando`):
                --   `radialrival`   el radial de la capital rival;
                --   `radialpropia`  el de tu capital;
                --   `radialmina`    el de la mina libre más cercana;
                --   `explorar`      pulsa «Explorar» en el de la capital rival;
                --   `radialinforme` manda exploradores a la capital rival y,
                --                   dos días después del informe, abre su radial;
                --   `exploradores`  igual, pero la foto es del explorador en
                --                   camino, entre las dos capitales;
                --   `sacar`         pulsa «Ejército» en el de tu capital (la
                --                   ventana de sacar tropas, con algo elegido);
                --   `formar`        además pulsa «Formar ejército» (queda elegido);
                --   `noticias`      abre la ventana de noticias;
                --   `pendonpropio`  el pendón de tu capital (pestaña de
                --                   `--pestana`, resumen si no se da);
                --   `pendonfondo`   el mismo, desplazado hasta abajo;
                --   `poblacion`     pulsa «Población» en el de tu capital.
                -- La foto sale `retrasoFoto` cuadros después.
                radial = ({
                    radialrival = 1,
                    radialpropia = 1,
                    radialmina = 1,
                    explorar = 1,
                    radialinforme = 1,
                    exploradores = 1,
                    sacar = 1,
                    formar = 1,
                    noticias = 1,
                    pendonpropio = 1,
                    pendonfondo = 1,
                    poblacion = 1,
                })[arg[k + 7] or ''] and arg[k + 7],
                -- `ejercito`: prueba con eventos sintéticos y fotos de la selección y las órdenes
                -- (build/escena_ejercito.lua); `economia`, la de producir, la
                -- munición, el Arsenal, abastecer y el taller
                -- (build/escena_economia.lua). Las fotos salen como `<archivo>_<paso>.png`.
                escena = ({ ejercito = 'build.escena_ejercito', economia = 'build.escena_economia' })[arg[k + 7] or ''],
                -- Territorio y capitales (modo jugador, el cuadro `cuando`):
                -- `plantar` / `plantarmal` abren el modo de plantar bandera
                -- con el punto fijo en un sitio válido (o demasiado lejos);
                -- `banderas` planta una junto a tu territorio y la mira;
                -- `banderaatacada`, además, el rival la ataca en cuanto se
                -- termina; `reparar`, el rival ataca tu capital y la foto
                -- sale cuando ha perdido vida, con su pendón abierto;
                -- `banderaajena`, la primera bandera de otra nación con la que
                -- no tienes frontera, con su pendón abierto. La
                -- foto sale `retrasoFoto` cuadros después (en `reparar`,
                -- después de encontrarlo) y no se entra en la batalla.
                territorio = ({
                    plantar = 1,
                    plantarmal = 1,
                    banderas = 1,
                    banderaatacada = 1,
                    reparar = 1,
                    banderaajena = 1,
                })[arg[k + 7] or ''] and arg[k + 7],
                -- Recolección y batallas (modo jugador, el cuadro `cuando`
                -- se abre el pendón de la mina abierta más cercana a tu
                -- capital y se pulsa «Recolectar»):
                --   `recolectar`  la foto del panel de recolectar;
                --   `mina`        manda el grupo y espera a que recolecte con
                --                 carga (la mina con su escudo y su pendón);
                --   `fichareco`   igual, con la ficha del grupo abierta;
                --   `redirigir`   igual, con la lista de «Redirigir a…»;
                --   `avisoataque` además, la capital rival ataca la mina: la
                --                 foto, al salir el aviso del ataque;
                --   `defender`    la foto, al salir el pregón «Defender /
                --                 Atacar»;
                --   `batallas`    la lista de batallas en curso abierta;
                --   `entrar`      pulsa «Entrar», pelea en 3D los cuadros del
                --                 undécimo valor (600 si no se da) y sale (las
                --                 bajas vuelven con `resolverBatalla`).
                -- La foto sale `retrasoFoto` cuadros después de encontrarlo.
                recoleccion = ({
                    recolectar = 1,
                    mina = 1,
                    fichareco = 1,
                    redirigir = 1,
                    avisoataque = 1,
                    defender = 1,
                    batallas = 1,
                    entrar = 1,
                })[arg[k + 7] or ''] and arg[k + 7],
                -- Día (cuadro) en que se lanza el ataque de prueba.
                cuando = tonumber(arg[k + 8]) or 100,
                retrasoFoto = tonumber(arg[k + 9]) or 0,
                -- En `entrar`, los cuadros de pelea en 3D antes de salir.
                pelea3d = tonumber(arg[k + 10]) or 600,
            }
            captura.limite = captura.cuadros
            if captura.velocidad and mundo then
                mundo.velocidad = captura.velocidad
            end
            if captura.zoom then
                camara.zoom = captura.zoom
            end
            if captura.pantalla == 'perfil' then
                perfil:abrir()
                if arg[k + 7] == 'perfilinfo' then
                    perfil.detalle = 'info'
                end
            elseif captura.pantalla == 'arsenal' then
                arsenal:abrir()
            elseif captura.pantalla then
                opciones:abrir()
                opciones.pantalla = captura.pantalla == 'opciones' and 'menu' or captura.pantalla
                if arg[k + 7] == 'resolucion' then
                    opciones.desplegado = 'resolucion'
                end
            end
        end
    end
    -- Test del modo ejército (NationsRTS, dueño 2026-09-29): corre la prueba
    -- y sale del juego. Se usa desde la línea de comandos.
    for _, v in ipairs(arg or {}) do
        if v == '--test-ejercito' then
            require('build.test-ejercito')(mundo, Simulacion, function()
                love.event.quit()
            end)
            return
        end
        if v == '--check-grupo' then
            require('build.check_grupo_nuevo')(mundo, Simulacion, function()
                love.event.quit()
            end)
            return
        end
        if v == '--visual-grupo' then
            -- Test visual (dueño 2026-09-29): arma un grupo, lo manda lejos,
            -- lo selecciona y deja love corriendo. No incluye cámara
            -- automática ni línea de estela: solo el punto dorado.
            ejercito:poner({ require('build.check_visual')(mundo, camara) })
            return
        end
        if v == '--visual-rts' then
            -- Test visual del modo RTS (2026-09-29): arma 3 grupos, los
            -- selecciona todos, los manda a un punto y deja love corriendo.
            require('build.check_rts')(mundo, camara)
            -- Lee la lista de grupos seleccionados del test y los pone en
            -- la selección principal del juego.
            if _G._rts_test_grupos then
                ejercito:poner(_G._rts_test_grupos)
            end
            return
        end
    end
end

--- Modo de captura `--batalla`: a los 60 cuadros provoca una guerra (por si no
-- hay ninguna) y, en cuanto hay un combate, entra en él (o, con 'mapa', pone la
-- cámara del mapa en el mismo sitio).
local function buscarBatallaParaCaptura()
    if captura.hecho == 60 then
        provocarGuerra()
    end
    local combate = Escena.buscarCombate(mundo)
    if not combate then
        if captura.hecho < captura.limite then
            captura.cuadros = math.max(captura.cuadros, 2)
        end
        return
    end
    batallaCaptura.combate = combate
    if batallaCaptura.modo == 'adelantado' then
        combate.defensor.adelantados = 1
    end
    captura.cuadros = batallaCaptura.cuadros
    if batallaCaptura.modo == 'mapa' then
        camara.x, camara.y = Escena.vistaDelCentro(mundo, combate)
        return
    end
    -- La preparación (2:00, combate en pausa, bandos en sus zonas) solo en
    -- los encuadres que la enseñan; los demás, como 'duracion', forman y
    -- miden la pelea desde el primer cuadro, igual que antes.
    local modo = batallaCaptura.modo
    combate.preparacion = modo == 'preparacion' or modo == 'listo' or modo == 'borde'
    -- `BATALLA_SITIO=montana` (el dueño, 19-nov: «cambia de lugar a ver»): el
    -- combate de prueba se muda al pie de las montañas del mapa más cercanas
    -- (base entre 12 y 25 m de mapa con un macizo de más de 50 a menos de
    -- 30 m de mapa), para ver la batalla con relieve.
    if os.getenv('BATALLA_SITIO') == 'montana' then
        local t = mundo.terreno
        local hecho = false
        for radio = 0, 300000, 400 do
            local n = math.max(1, math.floor(radio / 400))
            for k = 0, n - 1 do
                local a = k / n * 2 * math.pi
                local x, y = combate.cx + math.cos(a) * radio, combate.cy + math.sin(a) * radio
                local h = t:base(x, y)
                if h > 120 and h < 250 then
                    for j = 0, 7 do
                        local b = j / 8 * 2 * math.pi
                        if t:base(x + math.cos(b) * 300, y + math.sin(b) * 300) > 500 then
                            print(string.format('SITIO: combate movido a (%.0f, %.0f), %.0f px de lo de antes (base %.0f)', x, y, radio, h))
                            combate.cx, combate.cy = x, y
                            hecho = true
                            break
                        end
                    end
                end
                if hecho then
                    break
                end
            end
            if hecho then
                break
            end
        end
    end
    -- `BATALLA_LUGAR=nuestra|enemiga|oro|metal|petroleo` (pruebas): en vez de la
    -- ciudad atacada, el mismo grupo ataca su ciudad de origen (la nuestra) o
    -- la mina de ese tipo más cercana; el sitio sale en su lugar del mapa 2D
    -- (Escena.describir), armado con el kit (batalla/sitios/plano.lua).
    local lugar = os.getenv('BATALLA_LUGAR')
    if lugar and lugar ~= 'ciudad' then
        local sim = mundo.sim
        local gr = combate.grupo and sim.estado.grupos[combate.grupo]
        local objetivo
        if lugar == 'nuestra' then
            objetivo = gr and sim:sitio(gr.desde)
        elseif lugar == 'enemiga' then
            -- La capital de otra nación más cercana.
            local mejorD
            for _, c in pairs(sim.estado.ciudades) do
                if gr and c.nacion ~= gr.nacion then
                    local dd = (c.x - combate.cx) ^ 2 + (c.y - combate.cy) ^ 2
                    if not mejorD or dd < mejorD then
                        objetivo, mejorD = c, dd
                    end
                end
            end
        else
            local mejorD
            for _, d in pairs(sim.estado.depositos) do
                if d.tipo == lugar then
                    local dd = (d.x - combate.cx) ^ 2 + (d.y - combate.cy) ^ 2
                    if not mejorD or dd < mejorD then
                        objetivo, mejorD = d, dd
                    end
                end
            end
        end
        if gr and objetivo then
            local nuevo = Escena.describir(mundo, gr, objetivo, math.atan2(objetivo.y - combate.cy, objetivo.x - combate.cx))
            nuevo.preparacion, nuevo.forzado = combate.preparacion, combate.forzado
            nuevo.atacante, nuevo.defensor = combate.atacante, combate.defensor
            combate = nuevo
            batallaCaptura.combate = combate
        else
            print('BATALLA_LUGAR: no hay ' .. lugar .. ' para probar')
        end
    end
    print(string.format('LUGAR: centro %.0f,%.0f; sitio %s %s en %.0f,%.0f', combate.cx, combate.cy,
        tostring(combate.sitio and combate.sitio.tipo), tostring(combate.sitio and combate.sitio.deposito), combate.sitio and combate.sitio.x or 0, combate.sitio and combate.sitio.y or 0))
    batalla = Escena.nueva(mundo, combate)
    batalla:encuadrar(batallaCaptura.modo)
end

--- `--medir`: apunta el cuadro anterior y los huecos a la vista.
local function medirCuadro()
    local m = medicion
    if not m.listo then
        if mundo:huecos(vistaActual()) == 0 then
            m.listo = love.timer.getTime() - m.inicio
            m.cuadroListo = #m.cuadros
        end
        return
    end
    m.cuadros[#m.cuadros + 1] = love.timer.getDelta() * 1000
    m.generar[#m.generar + 1] = mundo.msGenerar or 0
    local huecos = mundo:huecos(vistaActual())
    if huecos > 0 then
        m.conHuecos = m.conHuecos + 1
        m.maxHuecos = math.max(m.maxHuecos, huecos)
    end
end

--- `--medir`: resumen al tomar la foto.
local function imprimirMedicion()
    local m = medicion
    local function resumen(lista)
        local orden = {}
        local suma = 0
        for k, v in ipairs(lista) do
            orden[k] = v
            suma = suma + v
        end
        table.sort(orden)
        local n = #orden
        if n == 0 then
            return 0, 0, 0
        end
        local peor = {}
        for k = n - math.max(1, math.floor(n / 100)) + 1, n do
            peor[#peor + 1] = orden[k]
        end
        local sumaPeor = 0
        for _, v in ipairs(peor) do
            sumaPeor = sumaPeor + v
        end
        return suma / n, sumaPeor / #peor, orden[n]
    end
    local media, peor, maximo = resumen(m.cuadros)
    local gMedia, gPeor, gMax = resumen(m.generar)
    print(string.format('MEDIR listo en %.2f s (%s cuadros)', m.listo or -1, tostring(m.cuadroListo)))
    print(
        string.format(
            'MEDIR cuadro: media %.2f ms, 1%% peor %.2f ms, max %.2f ms (%d cuadros)',
            media,
            peor,
            maximo,
            #m.cuadros
        )
    )
    print(string.format('MEDIR generar: media %.2f ms, 1%% peor %.2f ms, max %.2f ms', gMedia, gPeor, gMax))
    print(string.format('MEDIR cuadros con huecos a la vista %d (max %d trozos)', m.conHuecos, m.maxHuecos))
    local comarcas, listas = mundo.comarcas, 0
    local md = comarcas and comarcas.medidas
    if md and md.generadas > 0 then
        print(
            string.format(
                'MEDIR comarcas recibidas %d (%d del disco); en el hilo %.1f ms de media; subir %.2f ms de media',
                md.generadas,
                md.deDisco,
                md.msHilo / md.generadas,
                md.msSubir / md.generadas
            )
        )
    end
    for _, c in pairs(comarcas and comarcas.lista or {}) do
        if c.lista then
            listas = listas + 1
        end
    end
    local rss, pico
    local f = io.open('/proc/self/status', 'r')
    if f then
        local estado = f:read('*a') or ''
        rss, pico = tonumber(estado:match('VmRSS:%s*(%d+)')), tonumber(estado:match('VmHWM:%s*(%d+)'))
        f:close()
    end
    print(
        string.format(
            'MEDIR memoria del proceso %.0f MB (pico %.0f MB); disco de la semilla %.0f MB',
            (rss or 0) / 1024,
            (pico or 0) / 1024,
            (comarcas and comarcas.bytesDisco or 0) / 1048576
        )
    )
    print(
        string.format(
            'MEDIR memoria Lua %.0f MB, trozos %d, comarcas %d (%.0f MB de mallas y datos)',
            collectgarbage('count') / 1024,
            mundo.cuantos or 0,
            listas,
            (comarcas and comarcas.bytes or 0) / 1048576
        )
    )
end

--- Foto de la captura cuando se acaban sus cuadros.
local function tomarCapturaSiToca()
    if captura.cuadros == 0 then
        love.graphics.captureScreenshot(function(imagen)
            imagen:encode('png', captura.archivo)
            print('CAPTURA', love.filesystem.getSaveDirectory() .. '/' .. captura.archivo)
            -- Registro (Andrés): marca de la captura y un .json al lado con su día y cuadro.
            if registro then
                local marca = registro:captura({
                    archivo = captura.archivo,
                    camara = { x = camara.x, y = camara.y, zoom = camara.zoom },
                    modo = batalla and 'batalla' or captura.modo,
                })
                love.filesystem.write(captura.archivo:gsub('%.png$', '') .. '.json', Registro.json(marca) .. '\n')
            end
            print('FPS', love.timer.getFPS(), 'DIA', mundo and mundo.sim.estado.dia or '-')
            if medicion then
                imprimirMedicion()
            end
            if batalla then
                local t = batalla.tropas
                print(
                    string.format(
                        'BATALLA reloj %.1f s, fuera de combate %d y %d, reserva %d y %d, generado en %.2f s, %d triángulos',
                        t.reloj,
                        t.bajas[1],
                        t.bajas[2],
                        #t.bandos[1].cola,
                        #t.bandos[2].cola,
                        batalla.suelo.segundos,
                        batalla.suelo.triangulos + batalla.suelo.triangulosPlantas
                    )
                )
                if batalla:enPreparacion() then
                    local altura = batalla.camara:alturas()
                    print(
                        string.format(
                            'PREPARACION cámara a %.1f m del suelo, mirando %.1f° hacia abajo; rivales a la vista: %d',
                            altura,
                            math.deg(batalla.camara.inclinacion),
                            batalla:rivalesALaVista()
                        )
                    )
                end
            end
            love.event.quit(0)
        end)
    end
end

--- Modo de captura `asalto`: manda el ataque (un comando, como lo haría un
-- presidente) y deja la cámara y el panel en la ciudad que lo mandó.
function prepararAsaltoParaCaptura()
    local sim = mundo.sim
    local e = sim.estado
    if not captura.asaltoDesde and e.dia >= captura.cuando then
        local mejor, blanco
        for _, n in ipairs(sim:vivas()) do
            local c = e.ciudades[n.capital]
            if c and c.nacion == n.id and (not mejor or (c.lanzacohetes or 0) > (mejor.lanzacohetes or 0)) then
                for _, otra in ipairs(sim:vivas()) do
                    local oc = e.ciudades[otra.capital]
                    local cerca = oc and math.sqrt((oc.x - c.x) ^ 2 + (oc.y - c.y) ^ 2) < Simulacion.alcanceAtaque
                    if otra ~= n and oc and oc.nacion == otra.id and cerca then
                        mejor, blanco = c, oc
                    end
                end
            end
        end
        if mejor then
            sim:ejecutar({
                tipo = 'enviarGrupo',
                nacion = mejor.nacion,
                desde = mejor.id,
                mision = 'atacar',
                objetivo = blanco.id,
                soldados = math.floor(mejor.soldados * 0.5),
                lanzacohetes = mejor.lanzacohetes,
            })
            captura.asaltoDesde = mejor
            captura.asaltoDia = e.dia
            seleccionada = mundo:ciudadFisica(mejor.id)
        end
    end
    local c = captura.asaltoDesde
    if c then
        camara.x, camara.y = Iso.vista(c.x, c.y, mundo.terreno:altura(c.x, c.y))
        camara.zoom = captura.zoom or 0.5
    end
    if not captura.enFoto and c and e.dia >= captura.asaltoDia + captura.retrasoFoto then
        captura.enFoto = true
        mundo.velocidad = 1 / 60
        captura.cuadros = 30
    elseif not captura.enFoto and captura.hecho < captura.limite then
        captura.cuadros = math.max(captura.cuadros, 2)
    end
end

--- Modo de captura `base`: busca la primera base terminada con
-- lanzacohetes, pone la cámara en ella a velocidad normal y abre su panel.
function buscarBaseParaCaptura()
    local sim = mundo.sim
    local e = sim.estado
    for _, id in ipairs(Simulacion.ordenadas(e.instalaciones)) do
        local i = e.instalaciones[id]
        if
            not captura.enBase
            and i.tipo == 'base'
            and i.progreso >= 1
            and (i.lanzacohetes or 0) >= captura.minLanzacohetes
        then
            captura.enBase = i
        end
    end
    local b = captura.enBase
    if not b then
        if captura.hecho < captura.limite then
            captura.cuadros = math.max(captura.cuadros, 2)
        end
        return
    end
    mundo.velocidad = 1 / 60
    instalacionVista = b.id
    camara.x, camara.y = Iso.vista(b.x, b.y, mundo.terreno:altura(b.x, b.y))
    camara.zoom = captura.zoom or 0.9
    captura.cuadros = math.max(2, captura.retrasoFoto or 30)
end

--- Modos de captura `retirada`, `vuelta`, `recuperacion` y `ataque`: busca lo que hay que
-- fotografiar y, si lo encuentra, pone la cámara ahí y el tiempo a velocidad normal.
function buscarRetiradaParaCaptura()
    local e = mundo.sim.estado
    local visto
    if captura.recuperacion then
        local mayor = 0
        for _, id in ipairs(Simulacion.ordenadas(e.ciudades)) do
            local c = e.ciudades[id]
            local r = c.recuperando
            local fisica = mundo.ciudadesPorId[id]
            -- Mejor si hay lanzacohetes en la cola: se ven las tres filas.
            local peso = r and (r.soldados + r.lanzacohetes * 400) or 0
            if fisica and peso > mayor and peso >= captura.pesoMinimo then
                mayor, visto = peso, { x = c.x, y = c.y, ciudad = fisica }
            end
        end
    elseif captura.avion then
        for _, id in ipairs(Simulacion.ordenadas(e.vuelos or {})) do
            local v = e.vuelos[id]
            local gr = e.grupos[v.grupo]
            if not visto and v.fase == 'llevar' and gr and gr.largo > 0 and gr.recorrido / gr.largo > 0.3 then
                visto = { vuelo = v }
            end
        end
    else
        for _, gid in ipairs(Simulacion.ordenadas(e.grupos)) do
            local gr = e.grupos[gid]
            local combate = gr.mision == 'atacar' and gr.recorrido >= gr.largo
            if not visto and captura.ataque and combate then
                visto = { grupo = gr }
            end
            if not visto and gr.retirada and mundo:posicionVisible(gr, 0) then
                local primerDia = gr.recorrido < Simulacion.velocidadEjercito
                if (captura.retirada and primerDia) or (captura.vuelta and not primerDia) then
                    visto = { grupo = gr }
                end
            end
        end
    end
    if visto then
        captura.visto = visto
        seleccionada = visto.ciudad
        mundo.velocidad = 1 / 60
        camara.zoom = captura.zoom or 1.1
        captura.cuadros = math.max(2, captura.retrasoFoto or 30)
    elseif captura.hecho < captura.limite then
        -- Mientras no aparece, la foto espera (como mucho los cuadros pedidos).
        captura.cuadros = math.max(captura.cuadros, 2)
    end
end

--- Avanza el mundo (terreno a la vista, simulación y visuales) a `ritmo` de
-- su velocidad (1 si no se da); en pausa, parado.
local function actualizarMundo(dt, ritmo)
    local velocidadMundo = mundo.velocidad
    if pausa then
        mundo.velocidad = 0
    else
        mundo.velocidad = velocidadMundo * (ritmo or 1)
    end
    mundo.zoom = camara.zoom
    mundo.vista = vistaActual()
    -- Velocidad de la cámara (teclas, arrastre, inercia o captura), suavizada:
    -- el mundo se genera por delante de ella.
    local mov = mundo.movimiento or { vx = 0, vy = 0 }
    if camaraAntes and dt > 0 then
        local f = 1 - math.exp(-dt * 8)
        mov.vx = mov.vx + ((camara.x - camaraAntes.x) / dt - mov.vx) * f
        mov.vy = mov.vy + ((camara.y - camaraAntes.y) / dt - mov.vy) * f
    end
    camaraAntes = { x = camara.x, y = camara.y }
    mundo.movimiento = mov
    mundo:actualizar(dt, vistaActual())
    mundo.velocidad = velocidadMundo
end

--- Pantalla de carga: genera lo de alrededor de la cámara sin que pase el
-- tiempo de juego. Cuando está todo, prepara el primer cuadro (territorio,
-- sombreador y fuentes) detrás de la pantalla de carga, y entonces se ve el mapa.
local function actualizarCarga()
    mundo.zoom = camara.zoom
    mundo.vista = vistaActual()
    if carga.calentado then
        local segundos = love.timer.getTime() - carga.inicio
        print(string.format('MUNDO generado en %.2f s', segundos))
        if medicion then
            medicion.listo = love.timer.getTime() - medicion.inicio
            medicion.cuadroListo = 0
        end
        carga = nil
        -- Al abrir el juego normal: sigue la partida guardada (la misma
        -- semilla; `inicio.semillaGuardada` la eligió al empezar).
        if inicio.preguntar and not inicio.continuada then
            inicio.continuada = true
            if Partida.semilla() == mundo.semilla then
                cargarPartida()
            end
        end
        partidaLista = true
        return
    end
    carga.fraccion, carga.detalle = mundo:cargar(vistaActual())
    if carga.fraccion >= 1 then
        local velocidadMundo = mundo.velocidad
        mundo.velocidad = 0
        mundo:actualizar(0, vistaActual())
        mundo.velocidad = velocidadMundo
        carga.listo = mundo:territorioAlDia(vistaActual())
    end
end

--- Pantalla de carga: fondo oscuro, el título y una barra dorada.

local function dibujarCarga()
    local g = love.graphics
    local w, h = g.getDimensions()
    g.clear(0.07, 0.08, 0.06, 1)
    -- El mismo fondo que la pantalla de inicio, quieto, y abajo una sombra
    -- que va de nada a negro para que el texto se lea.
    inicio.fondo:dibujar(false)
    if not inicio.sombraCarga then
        inicio.sombraCarga = g.newMesh({
            { 0, 0, 0, 0, 0, 0, 0, 0 },
            { 1, 0, 1, 0, 0, 0, 0, 0 },
            { 1, 1, 1, 1, 0, 0, 0, 0.82 },
            { 0, 1, 0, 1, 0, 0, 0, 0.82 },
        }, 'fan', 'static')
    end
    g.setColor(1, 1, 1, 1)
    g.draw(inicio.sombraCarga, 0, math.floor(h * 0.55), 0, w, h - math.floor(h * 0.55))
    local base = 0.84
    local fuente = Tema.fuente('sc', 28)
    local fraccion = carga and carga.fraccion or 1
    local texto = string.format('Generando el mundo… %d %%', math.floor(fraccion * 100))
    g.setFont(fuente)
    Tema.color('textoHud')
    g.print(texto, math.floor((w - fuente:getWidth(texto)) / 2), math.floor(h * base - fuente:getHeight()))
    local d = carga and carga.detalle
    if d and d.total > 0 then
        local pequena = Tema.fuente('sans', 13)
        local linea = string.format(
            'Comarcas %s de %s · hasta las naciones vecinas (%.0f km a la redonda)',
            Tema.numero(d.hechas),
            Tema.numero(d.total),
            (d.radio or 0) / 10000
        )
        g.setFont(pequena)
        Tema.color('textoHudTenue')
        g.print(linea, math.floor((w - pequena:getWidth(linea)) / 2), math.floor(h * base + Tema.px(36)))
    end
    local bw, bh = math.floor(math.min(w * 0.4, Tema.px(720))), math.max(4, math.floor(Tema.px(10)))
    local bx, by = math.floor((w - bw) / 2), math.floor(h * base + Tema.px(16))
    Tema.color('olivaNegro')
    g.rectangle('fill', bx, by, bw, bh)
    Tema.color('amarillo')
    g.rectangle('fill', bx, by, math.floor(bw * fraccion), bh)
    Tema.color('lineaOliva')
    g.rectangle('line', bx + 0.5, by + 0.5, bw - 1, bh - 1)
    g.setColor(1, 1, 1, 1)
end

--- Sitio ajeno (ciudad o, con `instalacion`, instalación) más cercano a tu
-- capital; con `enGuerra` true/false, solo de naciones con las que estás (o
-- no) en guerra. Con `tipo`, solo instalaciones de ese tipo.
local function sitioAjenoCercano(enGuerra, instalacion, tipo)
    local sim = mundo.sim
    local capital = sim:ciudad(jugador.capitalJugador)
    local mejor, mejorD
    local lista = instalacion and sim.estado.instalaciones or sim.estado.ciudades
    for _, id in ipairs(Simulacion.ordenadas(lista)) do
        local s = lista[id]
        local guerra = s.nacion and sim:guerraEntre(jugador.jugador, s.nacion) ~= nil
        local delTipo = not tipo or s.tipo == tipo
        if s.nacion and s.nacion ~= jugador.jugador and (enGuerra == nil or guerra == enGuerra) and delTipo then
            local d = (s.x - capital.x) ^ 2 + (s.y - capital.y) ^ 2
            if not mejor or d < mejorD then
                mejor, mejorD = s, d
            end
        end
    end
    return mejor
end

--- Modo de captura `pendon*` / `atacarotra` (ver `--captura`).
local function capturaPendonAjeno()
    local modo = captura.pendonAjeno
    local s
    if modo == 'pendonguerra' then
        s = sitioAjenoCercano(true)
    elseif modo == 'pendonbase' then
        s = sitioAjenoCercano(nil, true)
    elseif modo == 'pendonbandera' or modo == 'atacarbandera' then
        s = sitioAjenoCercano(nil, true, 'bandera')
    else
        s = sitioAjenoCercano(false)
    end
    print('SITIO', s and s.id, s and nombreSitio(mundo.sim, s))
    if not s then
        return
    end
    siguiendo = nil
    camara.x, camara.y = Iso.vista(s.x, s.y, mundo.terreno:altura(s.x, s.y))
    if modo == 'pendonbase' or modo == 'pendonbandera' or modo == 'atacarbandera' then
        seleccionada, instalacionVista = nil, s.id
        if modo == 'atacarbandera' then
            -- «Atacar» del menú radial de la bandera (el envío abierto).
            radial:abrir({ tipo = 'sitio', id = s.id })
            print('BOTON', 'Atacar (radial)')
            accionRadial('atacar')
        end
        return
    end
    seleccionada, instalacionVista = mundo:ciudadFisica(s.id), nil
    if modo == 'atacarotra' or modo == 'enviopaz' then
        seleccionada = nil
        radial:abrir({ tipo = 'sitio', id = s.id })
        print('BOTON', 'Atacar (radial)')
        accionRadial('atacar')
    end
    if modo == 'atacarotra' then
        local gid = mandarAtaque()
        print('ATAQUE', gid, envio and envio.motivo or '')
        print('GUERRA', mundo.sim:guerraEntre(jugador.jugador, s.nacion) ~= nil)
        siguiendo = gid or nil
        captura.grupo = gid
    end
end

--- Punto junto a tu territorio para la captura: recorre rayos desde tu
-- capital, de fuera hacia dentro, y devuelve el más lejano donde se puede
-- plantar (con `lejos`, el primero que la simulación rechaza por lejano).
local function puntoBanderaParaCaptura(lejos)
    local sim = mundo.sim
    local capital = sim:ciudad(jugador.capitalJugador)
    local celda = Simulacion.celda
    for k = 0, 23 do
        local a = k / 24 * math.pi * 2
        local desde, hasta, paso = celda * 30, celda * 8, -celda / 4
        if lejos then
            desde, hasta, paso = hasta, desde, -paso
        end
        for d = desde, hasta, paso do
            local x, y = capital.x + math.cos(a) * d, capital.y + math.sin(a) * d
            local ok, motivo = sim:puedePlantarBandera(jugador.jugador, x, y)
            if (not lejos and ok) or (lejos and motivo == 'lejos') then
                return x, y
            end
        end
    end
    return nil
end

--- Modos de captura `plantar`, `plantarmal`, `banderas`, `banderaatacada`,
-- `reparar` y `banderaajena` (ver `--captura`).
local function capturaTerritorio()
    local sim = mundo.sim
    local modo = captura.territorio
    captura.sinBatalla = true
    if captura.hecho == captura.cuando then
        if modo == 'plantar' or modo == 'plantarmal' or modo == 'banderas' or modo == 'banderaatacada' then
            local x, y = puntoBanderaParaCaptura(modo == 'plantarmal')
            print('PUNTO', x, y)
            if not x then
                return
            end
            camara.x, camara.y = Iso.vista(x, y, mundo.terreno:altura(x, y))
            seleccionada, instalacionVista, cerradaAqui = nil, nil, nil
            plantando = Plantar.nuevo(jugador.jugador)
            plantando.fijo = true
            plantando:poner(sim, x, y)
            print('VALIDO', plantando.valido, plantando.motivo)
            if modo == 'banderas' or modo == 'banderaatacada' then
                captura.bandera = plantando:confirmar(sim)
                print('BANDERA', captura.bandera)
                plantando = nil
            end
        elseif modo == 'reparar' then
            local rival = sim:ciudad(jugador.capitalRival)
            captura.grupoRival = sim:ejecutar({
                tipo = 'enviarGrupo',
                nacion = rival.nacion,
                desde = rival.id,
                mision = 'atacar',
                objetivo = jugador.capitalJugador,
                soldados = rival.soldados,
                lanzacohetes = rival.lanzacohetes or 0,
            })
            print('ATAQUE RIVAL', captura.grupoRival)
        end
    end
    if captura.hecho < captura.cuando or captura.encontrado then
        return
    end
    -- Hasta encontrar lo que se busca, la foto espera.
    local encontrado
    if modo == 'banderaatacada' then
        local b = captura.bandera and sim:instalacion(captura.bandera)
        if b and b.progreso >= 1 and not captura.grupoRival then
            local rival = sim:ciudad(jugador.capitalRival)
            captura.grupoRival = sim:ejecutar({
                tipo = 'enviarGrupo',
                nacion = rival.nacion,
                desde = rival.id,
                mision = 'atacar',
                objetivo = b.id,
                soldados = math.floor(rival.soldados / 2),
            })
            print('ATAQUE A LA BANDERA', captura.grupoRival)
        end
        encontrado = b and (b.atacadaDia or -99) >= sim.estado.dia - 1 and b
    elseif modo == 'reparar' then
        local c = sim:ciudad(jugador.capitalJugador)
        encontrado = c and Simulacion.vidaSitio(c) < 100 and c
        if encontrado then
            seleccionada, instalacionVista = mundo:ciudadFisica(c.id), nil
        end
    elseif modo == 'banderaajena' then
        for _, id in ipairs(Simulacion.ordenadas(sim.estado.instalaciones)) do
            local i = sim.estado.instalaciones[id]
            if i.tipo == 'bandera' and i.nacion ~= jugador.jugador then
                local _, motivo = sim:puedeAtacar(jugador.jugador, id)
                if motivo == 'sinFrontera' then
                    encontrado = i
                    seleccionada, instalacionVista = nil, i.id
                    camara.x, camara.y = Iso.vista(i.x, i.y, mundo.terreno:altura(i.x, i.y))
                    break
                end
            end
        end
    else
        encontrado = true
    end
    if encontrado then
        captura.encontrado = true
        if encontrado ~= true then
            siguiendo = nil
            camara.x, camara.y = Iso.vista(encontrado.x, encontrado.y, mundo.terreno:altura(encontrado.x, encontrado.y))
        end
        print('ENCONTRADO', sim.estado.dia)
        captura.cuadros = math.max(2, captura.retrasoFoto or 2)
    elseif captura.hecho < captura.limite then
        captura.cuadros = math.max(captura.cuadros, 2)
    end
end

--- La mina abierta y libre más cercana a tu capital a la que se llega por
-- tierra (para las capturas de recolección), o nil.
local function minaParaCaptura()
    local sim = mundo.sim
    local c = sim:ciudad(jugador.capitalJugador)
    local r = 20000
    local mejor, mejorD
    for _, m in ipairs(sim:yacimientosEn(c.x - r, c.y - r, c.x + r, c.y + r)) do
        local d = (m.x - c.x) ^ 2 + (m.y - c.y) ^ 2
        if not m.cerrada and #m.recolectores == 0 and (not mejor or d < mejorD) then
            if sim:trazar(c.x, c.y, m.x, m.y) then
                mejor, mejorD = m, d
            end
        end
    end
    return mejor
end

--- Modos de captura de recolección y batallas (ver `--captura`).
function capturaRecoleccion()
    local sim = mundo.sim
    local modo = captura.recoleccion
    if captura.hecho == captura.cuando then
        local mina = minaParaCaptura()
        print('MINA', mina and mina.id, mina and mina.tipo)
        if not mina then
            return
        end
        captura.mina = mina.id
        siguiendo = nil
        seleccionada, instalacionVista, minaVista, cerradaAqui = nil, nil, mina.id, nil
        camara.x, camara.y = Iso.vista(mina.x, mina.y, mundo.terreno:altura(mina.x, mina.y))
        botonesMina(mina.id)[1].accion()
        envio.cantidades.soldados = math.min(150, envio:hay('soldados'))
        if modo == 'recolectar' then
            captura.encontrado = true
            captura.cuadros = math.max(2, captura.retrasoFoto)
            return
        end
        if modo ~= 'mina' and modo ~= 'fichareco' and modo ~= 'redirigir' then
            -- Con lanzacohetes carga más: sigue en la mina cuando llega el rival.
            envio.cantidades.lanzacohetes = math.min(6, envio:hay('lanzacohetes'))
        end
        captura.grupo = mandarAtaque()
        print('RECOLECTAR', captura.grupo, envio and envio.motivo or '')
        minaVista = nil
        mundo.velocidad = captura.velocidad or 1
    end
    if captura.hecho < captura.cuando or captura.encontrado or not captura.mina then
        return
    end
    local g = captura.grupo and sim.estado.grupos[captura.grupo]
    local m = sim:mina(captura.mina)
    camara.x, camara.y = Iso.vista(m.x, m.y, mundo.terreno:altura(m.x, m.y))
    local recolecta = g and g.fase == 'recolectando'
    local encontrado
    if modo == 'mina' or modo == 'fichareco' or modo == 'redirigir' then
        encontrado = recolecta and (g.carga or 0) > 0
        if encontrado and modo == 'mina' then
            minaVista = m.id
        elseif encontrado then
            fichaVista = g.id
            redirigiendo = modo == 'redirigir' and g.id or nil
        end
    else
        if recolecta and not captura.grupoRival then
            local rival = sim:ciudad(jugador.capitalRival)
            captura.grupoRival = sim:ejecutar({
                tipo = 'enviarGrupo',
                nacion = rival.nacion,
                desde = rival.id,
                mision = 'atacar',
                objetivo = m.id,
                soldados = math.floor(rival.soldados / 2),
                lanzacohetes = math.floor((rival.lanzacohetes or 0) / 2),
            })
            local gr = captura.grupoRival and sim.estado.grupos[captura.grupoRival]
            print('ATAQUE RIVAL A LA MINA', captura.grupoRival, gr and gr.largo / Simulacion.velocidadEjercito)
        end
        local pregonada = m.batalla and preguntadas[m.batalla]
        if modo == 'avisoataque' then
            encontrado = captura.grupoRival and avisadosAtaque[captura.grupoRival]
        elseif modo == 'defender' then
            encontrado = pregonada
        elseif modo == 'batallas' and pregonada then
            encontrado = true
            listaBatallas.abierta = true
        elseif modo == 'entrar' and pregonada then
            print('ENTRA', m.batalla, entrarEnBatallaSim(m.batalla))
            -- A 1 día por minuto, como en el juego: la pelea no dura días.
            mundo.velocidad = 1 / 60
            captura.encontrado = true
            return
        end
    end
    if encontrado then
        captura.encontrado = true
        print('ENCONTRADO', sim.estado.dia)
        captura.cuadros = math.max(2, captura.retrasoFoto)
    elseif captura.hecho < captura.limite then
        captura.cuadros = math.max(captura.cuadros, 2)
    end
end

--- Modos de captura del menú radial y las noticias (ver `--captura`).
local function capturaRadial()
    local sim = mundo.sim
    local modo = captura.radial
    local function abrirSobre(s)
        siguiendo = nil
        camara.x, camara.y = Iso.vista(s.x, s.y, mundo.terreno:altura(s.x, s.y))
        radial:abrir({ tipo = s.reserva and 'mina' or 'sitio', id = s.id })
        cerradaAqui = mundo:ciudadFisica(s.id)
    end
    if modo == 'pendonfondo' and captura.hecho > captura.cuando then
        -- Hasta abajo (el pendón lo recorta a su máximo al dibujarse).
        pendon.desplazamiento = math.huge
    end
    if captura.hecho == captura.cuando then
        if modo == 'noticias' then
            noticias:alternar(sim.estado.noticias)
        elseif modo == 'pendonpropio' or modo == 'pendonfondo' then
            local c = sim:ciudad(jugador.capitalJugador)
            siguiendo = nil
            camara.x, camara.y = Iso.vista(c.x, c.y, mundo.terreno:altura(c.x, c.y))
            seleccionada, instalacionVista = mundo:ciudadFisica(c.id), nil
        elseif modo == 'radialpropia' or modo == 'sacar' or modo == 'formar' or modo == 'poblacion' then
            abrirSobre(sim:ciudad(jugador.capitalJugador))
            if modo == 'poblacion' then
                accionRadial('poblacion')
            elseif modo ~= 'radialpropia' then
                accionRadial('sacar')
                envio.cantidades.soldados = math.min(120, envio:hay('soldados'))
            end
            if modo == 'formar' then
                print('FORMAR', mandarAtaque(), ejercito:cuantos())
            end
        elseif modo == 'radialmina' then
            local mina = minaParaCaptura()
            print('MINA', mina and mina.id)
            if mina then
                abrirSobre(sim:mina(mina.id))
            end
        elseif modo == 'radialinforme' or modo == 'exploradores' then
            mundo.velocidad = captura.velocidad or 1
        else
            abrirSobre(sim:ciudad(jugador.capitalRival))
            if modo == 'explorar' then
                accionRadial('explorar')
            end
        end
    end
    local explora = modo == 'radialinforme' or modo == 'exploradores'
    if not explora or captura.hecho < captura.cuando or captura.encontrado then
        if captura.hecho == captura.cuando then
            captura.encontrado = true
            captura.cuadros = math.max(2, captura.retrasoFoto)
        end
        return
    end
    local rival = sim:ciudad(jugador.capitalRival)
    if not captura.explorado then
        -- Como lo haría el jugador: en cuanto alcanza el dinero, salen.
        local ok, motivo = sim:ejecutar(Explorar.nuevo(sim, jugador.jugador, rival):comando())
        if ok or motivo ~= 'coste' then
            print('EXPLORAR', ok, motivo, sim.estado.dia)
            captura.explorado = sim.estado.dia
        end
    end
    if modo == 'exploradores' then
        -- La cámara sigue al primer explorador en camino.
        local e = sim.exploradoresEnCamino and sim:exploradoresEnCamino(jugador.jugador)[1]
        local mx, my
        if e then
            mx, my = trayectoExplorador(sim, e)
        end
        siguiendo = nil
        if mx then
            camara.x, camara.y = Iso.vista(mx, my, math.max(0, mundo.terreno:altura(mx, my)))
        end
        if captura.explorado and sim.estado.dia >= captura.explorado + 1 then
            captura.encontrado = true
            mundo.velocidad = 1 / 60
            captura.cuadros = math.max(2, captura.retrasoFoto)
        elseif captura.hecho < captura.limite then
            captura.cuadros = math.max(captura.cuadros, 2)
        end
        return
    end
    local inf = sim.informe and sim:informe(jugador.jugador, rival.id)
    if inf and sim.estado.dia >= inf.dia + 2 then
        print('INFORME', inf.dia, inf.poder, sim.estado.dia)
        captura.encontrado = true
        mundo.velocidad = 1 / 60
        abrirSobre(rival)
        captura.cuadros = math.max(2, captura.retrasoFoto)
    elseif captura.hecho < captura.limite then
        captura.cuadros = math.max(captura.cuadros, 2)
    end
end

--- Modo de captura `tropas` (ver `--captura`): con comandos, como lo haría
-- el jugador, saca varios grupos de su capital; luego toca una tarjeta o el ✓
-- del panel de tropas, como un clic.
local function capturaTropas()
    local sim = mundo.sim
    local c = sim:ciudad(jugador.capitalJugador)
    if captura.hecho == captura.cuando and c then
        local nid = jugador.jugador
        local function sacar(mision, objetivo, soldados, lanzacohetes)
            return sim:ejecutar({
                tipo = 'enviarGrupo',
                nacion = nid,
                desde = c.id,
                mision = mision,
                objetivo = objetivo,
                soldados = soldados,
                lanzacohetes = lanzacohetes,
            })
        end
        print('TROPAS parado', sacar('mover', c.id, 40, 0))
        print('TROPAS ataque', sacar('atacar', jugador.capitalRival, 100, 0))
        print('TROPAS cohetes', sacar('mover', c.id, 20, math.min(2, c.lanzacohetes or 0)))
        if captura.tropas == 'tropasmuchas' then
            for _ = 1, 6 do
                print('TROPAS pequeño', sacar('mover', c.id, 10, 0))
            end
        end
        local mina = minaParaCaptura()
        if mina then
            print(
                'TROPAS recolecta',
                sim:ejecutar({
                    tipo = 'recolectar',
                    nacion = nid,
                    desde = c.id,
                    yacimiento = mina.id,
                    soldados = 60,
                    lanzacohetes = 0,
                })
            )
        end
        siguiendo = nil
        camara.x, camara.y = Iso.vista(c.x, c.y, mundo.terreno:altura(c.x, c.y))
        camara.zoom = captura.zoom or 0.45
        captura.cuadros = math.max(2, captura.retrasoFoto)
    elseif captura.hecho == captura.cuando + 4 and captura.tropas == 'tropasciudad' and c then
        abrirRadial({ tipo = 'sitio', id = c.id }, c.x, c.y)
        for k = 1, 4 do
            pregon:avisar('Aviso de prueba ' .. k, 'Para ver que no pisa el panel de tropas', 'Ir', nil, 60)
        end
    elseif
        captura.hecho == captura.cuando + 4
        or (captura.hecho == captura.cuando + 8 and captura.tropas == 'tropasregresar')
    then
        -- El clic, sobre la zona del panel ya dibujado.
        local segundo = captura.hecho == captura.cuando + 8
        for _, z in ipairs(panelTropas.zonas) do
            local quiere = (captura.tropas == 'tropasradial' and z.accion.tipo == 'elegir')
                or (captura.tropas == 'tropastodos' and z.accion.tipo == 'todos')
                or (captura.tropas == 'tropasregresar' and z.accion.tipo == (segundo and 'regresar' or 'todos'))
            if quiere then
                local a = panelTropas:pulsar(z.x + 2, z.y + 2)
                if type(a) == 'table' then
                    accionTropas(a)
                end
                break
            end
        end
    end
end

--- Modos de captura del jugador: abre el envío, manda el ataque o abre el
-- panel de una ficha el cuadro `cuando`.
local function capturaJugador()
    if captura.territorio and jugador then
        capturaTerritorio()
    end
    if captura.radial and jugador then
        capturaRadial()
    end
    if captura.hecho ~= captura.cuando then
        return
    end
    local sim = mundo.sim
    if jugador and captura.pendonAjeno then
        capturaPendonAjeno()
    end
    if jugador and (captura.envio or captura.atacar) then
        envio = Envio.nuevo(sim:ciudad(jugador.capitalJugador), sim:ciudad(jugador.capitalRival))
    end
    if jugador and captura.atacar then
        local gid = mandarAtaque()
        print('ATAQUE', gid, envio and envio.motivo or '')
        siguiendo = gid or nil
        captura.grupo = gid
        if captura.cruce or captura.choque then
            local rival = sim:ciudad(jugador.capitalRival)
            local suyo = sim:ejecutar({
                tipo = 'enviarGrupo',
                nacion = rival.nacion,
                desde = rival.id,
                mision = 'atacar',
                objetivo = jugador.capitalJugador,
                soldados = math.floor(rival.soldados / 2),
                lanzacohetes = math.floor((rival.lanzacohetes or 0) / 2),
            })
            print('ATAQUE RIVAL', suyo)
            captura.grupoRival = suyo or nil
        end
    end
    if captura.ficha and mundo.fichas and mundo.fichas[1] then
        fichaVista = mundo.fichas[1].grupo.id
    end
end

--- `ejercito` o `economia`: un paso de la escena de prueba (build/escena_*.lua).
local escenaCorrutina
local function escenaEjercito()
    if not escenaCorrutina then
        local paso = require(captura.escena)
        escenaCorrutina = coroutine.create(paso)
    end
    if coroutine.status(escenaCorrutina) == 'suspended' then
        local ok, err = coroutine.resume(escenaCorrutina, {
            mundo = mundo,
            camara = camara,
            jugador = jugador,
            ejercito = ejercito,
            captura = captura,
            radial = radial,
            arsenal = arsenal,
            pregon = pregon,
            panelFicha = panelFicha,
            -- Lo que cambia de un cuadro a otro (los paneles abiertos).
            estado = function()
                return { fabrica = fabrica, envio = envio, fichaVista = fichaVista }
            end,
        })
        if not ok then
            print('ESCENA ERROR', err)
            captura.cuadros = 2
        end
    end
end

function love.update(dt)
    if inicio.login then
        inicio.login:actualizar()
        if captura then
            captura.cuadros = captura.cuadros - 1
            tomarCapturaSiToca()
        end
        return
    end
    if carga and not galeria then
        actualizarCarga()
        return
    end
    relojAutoguardado = relojAutoguardado + dt
    if relojAutoguardado >= AUTOGUARDADO then
        autoguardar()
        relojAutoguardado = 0
    end
    if medicion and captura then
        medirCuadro()
        if not medicion.listo then
            -- Hasta que la vista está entera, ni la cámara ni la captura avanzan.
            actualizarMundo(1 / 60)
            return
        end
    end
    ejercito:actualizar(captura and 1 / 60 or dt, mundo, jugador)
    -- Registro (Andrés): sigue la simulación viva y cuenta el cuadro.
    if registro then
        registro:seguir(mundo.sim)
        registro:cuadro()
    end
    if almacenVista then
        almacenVista:actualizar(dt)
        -- El almacén es otro sitio: el mundo sigue a su ritmo.
        actualizarMundo(dt)
        pregon:actualizar(dt, mundo.sim.estado.noticias, nombreJugador())
        return
    end
    if batalla then
        if not captura then
            batalla:actualizar(dt)
            if enEscena and batalla.fin and batalla.fin.cerrar then
                -- La pelea terminó sola (retirada o un bando fuera de combate).
                salirDeBatalla()
                return
            end
            -- El mundo no se para mientras se pelea: sigue, más lento.
            actualizarMundo(dt, RITMO_BATALLA)
            pregon:actualizar(dt, mundo.sim.estado.noticias, nombreJugador())
            return
        end
        if captura.pelea or captura.recoleccion then
            -- Modo jugador en captura: la batalla va con el mundo a su ritmo.
            actualizarMundo(1 / 60, RITMO_BATALLA)
            pregon:actualizar(1 / 60, mundo.sim.estado.noticias, nombreJugador())
        end
        if captura.recoleccion == 'entrar' and enEscena then
            -- `entrar`: `pelea3d` cuadros de pelea y se sale; la foto, del mapa.
            captura.enPelea = (captura.enPelea or 0) + 1
            captura.cuadros = math.max(captura.cuadros, 2)
            if captura.enPelea >= captura.pelea3d then
                salirDeBatalla()
                captura.cuadros = math.max(2, captura.retrasoFoto)
                return
            end
        end
        -- En las capturas la pelea va a 60 cuadros por segundo de pelea,
        -- vaya la máquina a los FPS que vaya; en 'duracion', 20 veces más deprisa.
        local b = batallaCaptura
        local pasos = b and b.modo == 'duracion' and 20 or 1
        -- Vídeo de los robots (batalla/robots/video.lua): 1/30 s por cuadro.
        if os.getenv('BATALLA_ROBOTS_VIDEO') then
            pasos = 2
        end
        -- Con las pruebas de robots en su pantalla (BATALLA_ROBOTS_FOTOS), a
        -- velocidad real: el tiempo de verdad de cada cuadro (sin vsync la
        -- máquina va a más de 100 FPS y 1/60 por cuadro iba acelerado).
        local paso = 1 / 60
        if os.getenv('BATALLA_ROBOTS_FOTOS') and not os.getenv('BATALLA_ROBOTS_VIDEO') then
            paso = math.min(dt, 1 / 20)
        end
        for _ = 1, pasos do
            batalla:actualizar(paso)
        end
        -- 'listo': al segundo de preparación se pulsa «Listo» (el NPC ya lo está).
        local d = batalla.despliegue
        if b and b.modo == 'listo' and batalla:enPreparacion() and d.duracion - d.restante >= 1 then
            batalla:pulsarListo()
        end
        if enEscena and batalla.fin and batalla.fin.cerrar then
            salirDeBatalla()
            captura.cuadros = math.max(2, captura.retrasoFoto or 2)
            return
        end
        captura.cuadros = captura.cuadros - 1
        captura.hecho = (captura.hecho or 0) + 1
        -- Espera (como mucho 90 s de pelea, o 15 min en 'duracion') al momento que se quiere ver.
        if b then
            local espera = not batalla:listaParaFoto(b.modo)
            local limite = b.modo == 'duracion' and 900 or 90
            if captura.cuadros == 0 and espera and batalla.tropas.reloj < limite then
                captura.cuadros = 1
            end
        end
        tomarCapturaSiToca()
        return
    end
    local velocidad = 700 / camara.zoom
    local dx, dy = 0, 0
    if love.keyboard.isDown('a', 'left') then
        dx = dx - 1
    end
    if love.keyboard.isDown('d', 'right') then
        dx = dx + 1
    end
    if love.keyboard.isDown('w', 'up') then
        dy = dy - 1
    end
    if love.keyboard.isDown('s', 'down') then
        dy = dy + 1
    end
    -- Cámara suave (el dueño, 2026-09-30): las teclas aceleran y frenan en vez
    -- de arrancar en seco, el arrastre deja una inercia corta al soltar y la
    -- rueda acerca en unas décimas de segundo.
    local tecla = dx ~= 0 or dy ~= 0
    local suave = 1 - math.exp(-dt * (tecla and 6 or 3))
    camara.vx = (camara.vx or 0) + (dx * velocidad - (camara.vx or 0)) * suave
    camara.vy = (camara.vy or 0) + (dy * velocidad - (camara.vy or 0)) * suave
    if arrastre then
        camara.vx, camara.vy = 0, 0
    end
    camara.x = camara.x + camara.vx * dt
    camara.y = camara.y + camara.vy * dt
    -- Fuera de los límites (otro código pone el zoom a mano), se vuelve a ellos.
    if not captura and (camara.zoom < ZOOM_MIN or camara.zoom > ZOOM_MAX) then
        camara.zoomObjetivo = math.max(ZOOM_MIN, math.min(ZOOM_MAX, camara.zoomObjetivo or camara.zoom))
    end
    if camara.zoom < ZOOM_ENTRA_LEJOS and not vistaLejana then
        vistaLejana = true
        radial:cerrar()
        plantando = nil
    elseif camara.zoom >= ZOOM_SALE_LEJOS - 1e-4 then
        vistaLejana = false
    end
    if camara.zoomObjetivo then
        local fz = 1 - math.exp(-dt * 7)
        camara.zoom = camara.zoom + (camara.zoomObjetivo - camara.zoom) * fz
        if math.abs(camara.zoomObjetivo - camara.zoom) < camara.zoom * 0.001 then
            camara.zoom, camara.zoomObjetivo = camara.zoomObjetivo, nil
        end
    end
    -- Deslizamiento hacia el sitio del menú radial (lo corta mover la cámara).
    if focoCamara and (tecla or arrastre) then
        focoCamara = nil
    elseif focoCamara then
        local f = 1 - math.exp(-(captura and 1 / 60 or dt) * 10)
        camara.x = camara.x + (focoCamara.x - camara.x) * f
        camara.y = camara.y + (focoCamara.y - camara.y) * f
        if math.abs(focoCamara.x - camara.x) + math.abs(focoCamara.y - camara.y) < 1 then
            focoCamara = nil
        end
    end
    -- Modo ejército: la cámara no persigue al grupo seleccionado. Solo
    -- WASD la mueve.
    if captura then
        -- Recorrido automático para la captura: se mueve como si explorara.
        dt = 1 / 60
        if captura.idaVuelta and captura.hecho == math.floor(captura.limite / 2) then
            captura.dx, captura.dy = -captura.dx, -captura.dy
        end
        camara.x = camara.x + captura.dx * dt
        camara.y = camara.y + captura.dy * dt
        captura.cuadros = captura.cuadros - 1
        captura.hecho = (captura.hecho or 0) + 1
        if captura.guerra and captura.hecho == 90 then
            provocarGuerra()
        end
        if captura.campamento and not captura.enCampamento then
            local e = mundo.sim.estado
            for _, id in ipairs(Simulacion.ordenadas(e.instalaciones)) do
                local i = e.instalaciones[id]
                if i.tipo == 'campamento' and i.progreso >= 1 then
                    captura.enCampamento = i
                    captura.cuadros = 90
                    break
                end
            end
        end
        if captura.enCampamento then
            local i = captura.enCampamento
            camara.x, camara.y = Iso.vista(i.x, i.y, mundo.terreno:altura(i.x, i.y))
        end
        if captura.asalto then
            prepararAsaltoParaCaptura()
        end
        if captura.acelerar and captura.visto and not captura.clic then
            captura.esperaClic = (captura.esperaClic or 0) + 1
            -- La cola entera, con un botón por tropa, está en la pestaña Ejército.
            pendon.pestana = 'ejercito'
            local b = pendon:primerBoton()
            if b and captura.esperaClic >= 20 then
                captura.clic = true
                love.mousepressed(b.x + b.w / 2, b.y + b.h / 2, 1)
            end
        end
        if captura.base and not captura.enBase then
            buscarBaseParaCaptura()
        end
        local buscaGrupo = captura.retirada or captura.vuelta or captura.recuperacion or captura.ataque or captura.avion
        if buscaGrupo and not captura.visto then
            buscarRetiradaParaCaptura()
        end
        if captura.visto then
            local x, y = captura.visto.x, captura.visto.y
            if captura.visto.grupo then
                local f = mundo.sim:fraccionPaso()
                x, y = mundo:posicionVisible(captura.visto.grupo, f)
            elseif captura.visto.vuelo then
                x, y = mundo:posicionVuelo(captura.visto.vuelo, mundo.sim:fraccionPaso())
            end
            if x then
                camara.x, camara.y = Iso.vista(x, y, mundo.terreno:altura(x, y))
            end
        end
        if captura.seguir and not siguiendo and next(mundo.sim.estado.grupos) then
            seguirEjercito()
            camara.zoom = 1.1
        end
        if batallaCaptura and not batallaCaptura.combate then
            buscarBatallaParaCaptura()
        end
        capturaJugador()
        if captura.tropas and jugador then
            capturaTropas()
        end
        if captura.escena and jugador then
            escenaEjercito()
        end
        -- `cruce`: la foto, cuando los dos estandartes están a menos de 350 m.
        local rival = captura.grupoRival and mundo.sim.estado.grupos[captura.grupoRival]
        local nuestro = captura.grupo and mundo.sim.estado.grupos[captura.grupo]
        if captura.cruce and rival and nuestro and not captura.cruzados then
            local f = mundo.sim:fraccionPaso()
            local ax, ay = mundo:posicionFicha(nuestro, f)
            local bx, by = mundo:posicionFicha(rival, f)
            -- La cámara, entre los dos.
            siguiendo = nil
            local mx, my = (ax + bx) / 2, (ay + by) / 2
            camara.x, camara.y = Iso.vista(mx, my, mundo.terreno:altura(mx, my))
            if (ax - bx) ^ 2 + (ay - by) ^ 2 < 3500 * 3500 then
                -- Con el panel de la ficha rival: su composición no se ve.
                captura.cruzados, captura.cuadros = true, 2
                fichaVista = captura.grupoRival
            end
        end
        -- `choque` y `pelea`: la foto, `retrasoFoto` cuadros después del
        -- pregón de la batalla de tu grupo.
        local nuestroGrupo = captura.grupo and mundo.sim.estado.grupos[captura.grupo]
        local pregonada = nuestroGrupo and nuestroGrupo.batalla and preguntadas[nuestroGrupo.batalla]
        if (captura.choque or captura.pelea) and not captura.avisada and pregonada then
            captura.avisada = true
            captura.cuadros = math.max(2, captura.retrasoFoto)
            siguiendo = nil
            local b = mundo.sim:estadoBatalla(nuestroGrupo.batalla)
            if b and captura.choque then
                camara.x, camara.y = Iso.vista(b.x, b.y, mundo.terreno:altura(b.x, b.y))
            end
        elseif (captura.choque or captura.pelea) and not captura.avisada and captura.hecho < captura.limite then
            captura.cuadros = math.max(captura.cuadros, 2)
        end
        if captura.recoleccion and jugador then
            capturaRecoleccion()
        end
        tomarCapturaSiToca()
    end
    actualizarMundo(dt)
    if batallaVivo then
        buscarBatallaEnVivo(dt)
    end
    pregon:actualizar(dt, mundo.sim.estado.noticias, nombreJugador())
    vigilarBatallas()
    if plantando and not plantando.fijo then
        plantando:poner(mundo.sim, sueloEnPantalla(love.mouse.getPosition()))
    end

    -- Cámara pegada al ejército que se sigue (hasta que llega o cae).
    local ej = siguiendo and mundo.sim.estado.grupos[siguiendo]
    if ej then
        local f = mundo.sim:fraccionPaso()
        local x, y = mundo:posicionFicha(ej, f)
        if x then
            camara.x, camara.y = Iso.vista(x, y, mundo.terreno:altura(x, y))
        end
    elseif siguiendo then
        siguiendo = nil
    end
end

--- Cielo de atardecer: degradado de arriba abajo.
local function dibujarCielo()
    local w, h = love.graphics.getDimensions()
    local malla = love.graphics.newMesh({
        { 0, 0, 0, 0, 0.98, 0.62, 0.5, 1 },
        { w, 0, 0, 0, 0.98, 0.62, 0.5, 1 },
        { w, h, 0, 0, 0.95, 0.78, 0.62, 1 },
        { 0, h, 0, 0, 0.95, 0.78, 0.62, 1 },
    }, 'fan', 'static')
    love.graphics.draw(malla)
end

--- Capa técnica (F3): semilla, trozos, plantas, ciudades descubiertas y FPS,
-- en letra pequeña bajo el travesaño a la izquierda.
local function dibujarCapaTecnica()
    local g = love.graphics
    local descubiertas = 0
    for _ in pairs(mundo.ciudadesVistas) do
        descubiertas = descubiertas + 1
    end
    local lineas = {
        string.format('Semilla %d · N mundo nuevo · F9 cargar', mundo.semilla),
        string.format(
            'Comarcas %d MB · %d hilos · plantas %d · generando %d',
            math.floor(mundo.comarcas.bytes / 1048576),
            #mundo.comarcas.hilos,
            mundo.plantas,
            mundo.pendientes or 0
        ),
        string.format('Ciudades descubiertas %d · FPS %d', descubiertas, love.timer.getFPS()),
    }
    local fuente = Tema.fuente('sans', 12)
    local relleno = Tema.px(8)
    local ancho = 0
    for _, l in ipairs(lineas) do
        ancho = math.max(ancho, fuente:getWidth(l))
    end
    local x, y = Columna.ancho() + Tema.px(8), BarraSuperior.alto() + Tema.px(8)
    local alto = #lineas * fuente:getHeight() + relleno * 2
    Tema.color('olivaNegro', 0.8)
    g.rectangle('fill', x, y, ancho + relleno * 2, alto, 2, 2)
    g.setFont(fuente)
    Tema.color('textoHudTenue')
    for k, l in ipairs(lineas) do
        g.print(l, x + relleno, y + relleno + (k - 1) * fuente:getHeight())
    end
end

--- Ciudad cuyo pendón se muestra: la elegida con un clic o, si no hay, en la
-- que se está (salvo que se haya cerrado su pendón estando en ella).
local function ciudadMostrada(ciudad, distancia)
    if seleccionada then
        return seleccionada
    end
    if ciudad and distancia < ciudad.radio and ciudad ~= cerradaAqui then
        return ciudad
    end
    return nil
end

--- Cuántos ejércitos de la nación `nid` están en una batalla (para la
-- insignia del botón de ejércitos).
local function ejercitosEnBatalla(sim, nid)
    local cuenta = 0
    for _, g in pairs(sim.estado.grupos) do
        if g.nacion == nid and g.batalla and Simulacion.esEjercito(g) then
            cuenta = cuenta + 1
        end
    end
    return cuenta
end

--- Borde izquierdo del pendón abierto (o del borde de la pantalla, con el
-- margen de 16): lo que queda libre a su derecha se ocupa con listas y avisos.
local function derechaPendon()
    if pendon.rect then
        return pendon.rect.x - Tema.px(8)
    end
    return nil
end

--- Hasta dónde llega por la derecha la columna de avisos: antes del pendón y
-- de la lista de batallas, si están abiertos.
local function derechaLibre()
    local derecha = derechaPendon()
    local lista = listaBatallas.rect
    if lista then
        derecha = math.min(derecha or math.huge, lista.x - Tema.px(8))
    end
    return derecha
end

--- Cuadros por segundo, arriba a la derecha bajo la barra (Opciones > General).
local function dibujarFps()
    if not Ajustes.mostrarFps then
        return
    end
    local fuente = Acero.fuente('cuerpo', 16)
    local texto = love.timer.getFPS() .. ' FPS'
    local x = love.graphics.getWidth() - fuente:getWidth(texto) - Tema.px(16)
    Acero.textoContorno(fuente, texto, x, BarraSuperior.alto() + Tema.px(4), 'textoHud')
end

--- Medidor de zoom (el dueño, 2026-09-30): barra vertical en el borde derecho,
-- de alejado (abajo) a cerca (arriba) en escala logarítmica, con el
-- porcentaje encima.
local function dibujarMedidorZoom()
    local g = love.graphics
    local px = Tema.px
    local w, h = g.getDimensions()
    local alto = math.floor(h * 0.25)
    local ancho = px(10)
    local x = w - px(28)
    local y = math.floor((h - alto) / 2)
    -- Con el pendón abierto a la derecha, el medidor va a su izquierda para no
    -- pisar sus cifras.
    local r = pendon.rect
    if r and x + ancho > r.x and y < r.y + r.h and y + alto > r.y then
        x = r.x - px(28)
    end
    local parte = math.log(camara.zoom / ZOOM_MIN) / math.log(ZOOM_MAX / ZOOM_MIN)
    parte = math.max(0, math.min(1, parte))
    Tema.color('olivaNegro', 0.75)
    g.rectangle('fill', x, y, ancho, alto, ancho / 2)
    local lleno = math.floor(alto * parte)
    Tema.color('amarillo', 0.9)
    g.rectangle('fill', x, y + alto - lleno, ancho, lleno, ancho / 2)
    Tema.color('textoHud')
    g.circle('fill', x + ancho / 2, y + alto - lleno, ancho * 0.9)
    local fuente = Acero.fuente('cuerpo', 15)
    local texto = math.floor(camara.zoom * 100 + 0.5) .. ' %'
    Acero.textoContorno(
        fuente,
        texto,
        x + ancho / 2 - fuente:getWidth(texto) / 2,
        y - fuente:getHeight() - px(6),
        'textoHud'
    )
end

--- Punto del mundo de un objetivo de exploración (sitio o grupo), o nil.
local function puntoObjetivo(sim, id)
    local s = sim:sitio(id)
    if s then
        return s.x, s.y
    end
    local gr = sim.estado.grupos[id]
    if gr then
        return mundo:posicionFicha(gr, sim:fraccionPaso())
    end
    return nil
end

--- Dónde va un explorador de `sim:exploradoresEnCamino`: su punto de ahora y
-- el de su objetivo (del mundo). Acepta el punto dado (`x`, `y`) o lo
-- calcula entre la salida y la llegada con el reloj del juego.
function trayectoExplorador(sim, e)
    local tx, ty = e.hastaX, e.hastaY
    if not tx then
        tx, ty = puntoObjetivo(sim, e.objetivo)
    end
    local x, y = e.x, e.y
    if not x then
        local ox, oy = e.desdeX, e.desdeY
        if not ox then
            local desde = e.desde and sim:sitio(e.desde)
            ox, oy = desde and desde.x, desde and desde.y
        end
        -- Sale al empezar `salioDia` y llega al final de `llegaDia`.
        local salida, llegada = e.salioDia, e.llegaDia and e.llegaDia + 1
        if ox and tx and salida and llegada and llegada > salida then
            local ahora = sim:ahora()
            local f = math.max(0, math.min(1, (ahora - salida) / (llegada - salida)))
            x, y = ox + (tx - ox) * f, oy + (ty - oy) * f
        else
            x, y = ox, oy
        end
    end
    return x, y, tx, ty
end

--- Tus exploradores en camino: un icono pequeño con la lupa y su trayecto
-- punteado hasta el objetivo (en pantalla, sobre el mapa).
local function dibujarExploradores()
    local sim = mundo.sim
    if not (jugador and sim.exploradoresEnCamino) then
        return
    end
    local lista = sim:exploradoresEnCamino(jugador.jugador) or {}
    if #lista == 0 then
        return
    end
    local g = love.graphics
    local w, h = g.getDimensions()
    local function pantalla(x, y)
        local vx, vy = Iso.vista(x, y, math.max(0, mundo.terreno:altura(x, y)))
        return (vx - camara.x) * camara.zoom + w / 2, (vy - camara.y) * camara.zoom + h / 2
    end
    local radio = Tema.px(13)
    for _, e in ipairs(lista) do
        local x, y, tx, ty = trayectoExplorador(sim, e)
        if x and tx then
            local ax, ay = pantalla(x, y)
            local bx, by = pantalla(tx, ty)
            -- Trayecto punteado, en tramos de 10 px con huecos de 7.
            local largo = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
            local trazo, hueco = Tema.px(10), Tema.px(7)
            g.setLineWidth(math.max(1.5, Tema.px(2)))
            Tema.color('amarillo', 0.85)
            local d = radio
            while d < largo do
                local d1 = math.min(largo, d + trazo)
                g.line(
                    ax + (bx - ax) * d / largo,
                    ay + (by - ay) * d / largo,
                    ax + (bx - ax) * d1 / largo,
                    ay + (by - ay) * d1 / largo
                )
                d = d1 + hueco
            end
            g.setLineWidth(1)
            local enVista = ax > -radio and ax < w + radio and ay > -radio and ay < h + radio
            if enVista then
                Tema.color('olivaNegro', 0.9)
                g.circle('fill', ax, ay, radio)
                Tema.color('amarillo')
                g.setLineWidth(math.max(1, Tema.px(1.5)))
                g.circle('line', ax, ay, radio)
                g.setLineWidth(1)
                local lado = math.floor(radio * 1.3)
                Acero.icono('busqueda', ax - lado / 2, ay - lado / 2, lado, 'textoHud')
            end
        end
    end
end

local function dibujarJuego()
    local g = love.graphics
    if galeria then
        Galeria.dibujar()
        return
    end
    if batalla then
        batalla:dibujar()
        local escenaDream = (batalla.robotsAsalto or batalla.robotsCamion) and require('batalla.dream.escena')
        if escenaDream and escenaDream.videoRobots then
            escenaDream.videoRobots:cuadro(batalla)
        end
        if escenaDream and escenaDream.medirRobots then
            escenaDream.medirRobots:cuadro(batalla)
        end
        return
    end
    if carga and not carga.listo then
        dibujarCarga()
        return
    end
    local w, h = g.getDimensions()
    dibujarCielo()

    g.push()
    g.translate(w / 2, h / 2)
    g.scale(camara.zoom)
    g.translate(-camara.x, -camara.y)
    mundo.camara = camara
    mundo.antesDeFichas = function()
        ejercito:dibujarDebajo(mundo, camara)
    end
    mundo.sinNombre = radial.objetivo and radial.objetivo.tipo == 'sitio' and radial.objetivo.id or nil
    mundo:dibujar()
    if mundo.sinMapa then
        g.clear(0.16, 0.17, 0.18)
    end
    local suyaPlantar = plantando and mundo.sim:nacion(plantando.nacion)
    if suyaPlantar then
        plantando:dibujarMundo(mundo, camara.zoom, mundo.semilla, suyaPlantar.color)
    end
    g.pop()
    -- Marcas del modo ejército: resplandor, círculo de acción, caminos,
    -- toques y cuadro de selección (en pantalla, sobre el mundo).
    ejercito:dibujarMapa(mundo, camara)
    dibujarExploradores()
    -- Menú radial del sitio tocado, sobre el mapa y bajo la interfaz.
    local opcionesMenu = radial:abierto() and opcionesRadial()
    if opcionesMenu then
        local s = objetivoRadial()
        local vx, vy = Iso.vista(s.x, s.y, math.max(0, mundo.terreno:altura(s.x, s.y)))
        radial:dibujar((vx - camara.x) * camara.zoom + w / 2, (vy - camara.y) * camara.zoom + h / 2, opcionesMenu)
    elseif radial:abierto() then
        radial:cerrar()
    end

    -- Interfaz. De abajo arriba: noticias y placa, travesaño, pendón (su barra
    -- cuelga sobre la del travesaño), pregón y, encima de todo, las ayudas.
    Tema.actualizar()
    local cx, cy = Iso.mundo(camara.x, camara.y)
    local ciudad, distancia = mundo:ciudadMasCercana(cx, cy)
    local contexto = {
        sim = mundo.sim,
        semilla = mundo.semilla,
        pausa = pausa,
        velocidad = mundo.velocidad,
        velocidades = VELOCIDADES,
        territorio = mundo.mostrarTerritorio,
        plantando = plantando ~= nil,
        jugador = jugador ~= nil,
        nacion = jugador and jugador.jugador or nil,
        batallas = jugador and #mundo.sim:batallasEnCurso(jugador.jugador) or 0,
        batallasAbiertas = listaBatallas.abierta,
        noticiasAbiertas = noticias.abierta,
        noticiasNuevas = noticias:nuevas(mundo.sim.estado.noticias),
        perfilAbierto = perfil.abierto,
        opcionesAbiertas = opciones.abierta,
        arsenalAbierto = arsenal.abierto,
        limiteDerecha = pendon.rect and pendon.rect.x - Tema.px(8) or nil,
        ataques = jugador and #mundo.sim:avisosAtaque(jugador.jugador) or 0,
        ejercitos = jugador and ejercitosEnBatalla(mundo.sim, jugador.jugador) or 0,
    }
    local fr = fichaVista and panelFicha.rect
    noticias:dibujar(
        mundo.sim.estado.noticias,
        false,
        fr and (fr.y + fr.h + Tema.px(8)) or nil,
        fr and (fr.x + fr.w + Tema.px(8)) or nil
    )
    local mostrada = seleccionada
    if PANEL_CIUDAD then
        mostrada = ciudadMostrada(ciudad, distancia)
    end
    -- La placa se oculta si el pendón abierto es el de esa misma ciudad.
    if ciudad and ejercito:cuantos() == 0 and (instalacionVista or minaVista or mostrada ~= ciudad) then
        placa:dibujar(mundo.sim, ciudad, distancia, BarraSuperior.alto())
    else
        placa:ocultar()
    end
    barraSuperior:dibujar(contexto)
    columna:dibujar(contexto, BarraSuperior.alto())
    -- En el mapa estratégico (mundo/capas.lua), las casillas de capas.
    local lejos = mundo.pesosCapas and mundo.pesosCapas.lejos or 0
    if lejos > 0 and columna.rect then
        local estado = {
            territorio = mundo.mostrarTerritorio,
            ejercitos = mundo.capas.ejercitos,
            yacimientos = mundo.capas.yacimientos,
            batallas = mundo.capas.batallas,
        }
        casillasCapas:dibujar(columna.rect.x + Tema.px(6), columna.rect.y + columna.rect.h + Tema.px(28), estado, lejos)
        if lejos < 0.5 then
            casillasCapas:ocultar()
        end
    else
        casillasCapas:ocultar()
    end
    -- Si la instalación del pendón abierto ya no existe (destruida), se olvida.
    if instalacionVista and not mundo.sim:instalacion(instalacionVista) then
        instalacionVista = nil
    end
    if radial:abierto() then
        pendon:ocultar()
    elseif instalacionVista then
        -- Los paneles entran deslizándose con fundido (interfaz/vida.lua).
        Vida.entrar('pendon:i' .. tostring(instalacionVista), Tema.px(36), 0)
        pendon:dibujarInstalacion(
            mundo.sim,
            instalacionVista,
            nil,
            botonesInstalacion(instalacionVista),
            jugador and jugador.jugador
        )
        Vida.fin()
    elseif minaVista then
        Vida.entrar('pendon:m' .. tostring(minaVista), Tema.px(36), 0)
        pendon:dibujarYacimiento(mundo.sim, minaVista, nil, botonesMina(minaVista), jugador and jugador.jugador)
        Vida.fin()
    elseif mostrada then
        local datos = mundo.sim:ciudad(mostrada.region)
        local propia = jugador and datos and datos.nacion == jugador.jugador
        Vida.entrar('pendon:c' .. tostring(mostrada.region), Tema.px(36), 0)
        pendon:dibujarCiudad(mundo.sim, mostrada, nil, botonesCiudad(mostrada), propia, jugador and jugador.jugador)
        Vida.fin()
    else
        pendon:ocultar()
    end
    if capaTecnica then
        dibujarCapaTecnica()
    end
    if fichaVista then
        local arriba = BarraSuperior.alto() + Tema.px(capaTecnica and 84 or 16)
        local botones, aviso = botonesFicha(fichaVista)
        Vida.entrar('ficha:' .. tostring(fichaVista), -Tema.px(36), 0)
        local sigue = panelFicha:dibujar(mundo.sim, fichaVista, mundo.mira, mundo.semilla, arriba, botones, aviso)
        Vida.fin()
        if not sigue then
            fichaVista, redirigiendo = nil, nil
        end
    else
        panelFicha.rect = nil
    end
    -- Navegación de abajo; sobre ella, el panel del ejército elegido
    -- (tarjetas y órdenes) y, a la derecha, el panel de tropas.
    navegacion:dibujar(contexto)
    dibujarMedidorZoom()
    if vistaLejana then
        local fuente = Acero.fuente('cuerpo', 18)
        local texto = 'Vista lejana: acércate al 10 % para dar órdenes'
        local tw = fuente:getWidth(texto)
        local tx = math.floor((love.graphics.getWidth() - tw) / 2)
        local ty = love.graphics.getHeight() - Navegacion.alto() - fuente:getHeight() - Tema.px(12)
        Acero.textoContorno(fuente, texto, tx, ty, 'textoHud')
    end
    -- El panel de tropas se oculta mientras el radial de un sitio está
    -- abierto (como el pendón): su tarjeta usa ese sitio.
    if jugador and not radial:abierto() then
        local elegidos = {}
        for _, gid in ipairs(ejercito.ids) do
            elegidos[gid] = true
        end
        panelTropas:dibujar({
            sim = mundo.sim,
            nacion = jugador.jugador,
            elegidos = elegidos,
            derecha = pendon.rect and (pendon.rect.x - Tema.px(8)) or (w - Tema.px(16)),
            abajo = h - Navegacion.alto() - Tema.px(6),
        })
    else
        panelTropas.rect = nil
    end
    -- El panel del ejército se centra en el hueco libre: a la derecha de las
    -- noticias o de la ficha abierta (la que llegue más lejos) y a la
    -- izquierda del pendón y del panel de tropas.
    local izquierda = noticias
    local fr2 = fichaVista and panelFicha.rect
    if fr2 and (not noticias.rect or fr2.x + fr2.w > noticias.rect.x + noticias.rect.w) then
        izquierda = panelFicha
    end
    local derechaEjercito = pendon
    if panelTropas.rect then
        local limite = panelTropas.rect.x
        if pendon.rect then
            limite = math.min(limite, pendon.rect.x)
        end
        derechaEjercito = { rect = { x = limite } }
    end
    ejercito:dibujarPanel(mundo, jugador, izquierda, derechaEjercito, Navegacion.alto())
    if jugador then
        if listaBatallas.abierta then
            Vida.entrar('batallas', Tema.px(36), 0)
        end
        listaBatallas:dibujar(mundo.sim, jugador.jugador, BarraSuperior.alto() + Tema.px(16), derechaPendon())
        if listaBatallas.abierta then
            Vida.fin()
        end
    end
    -- Los avisos bajan hasta el panel de tropas si caen encima de él.
    local abajoPregon
    local t = panelTropas.rect
    local derechaAvisos = derechaLibre() or (w - Tema.px(16))
    if t and derechaAvisos > t.x then
        abajoPregon = t.y - Tema.px(8)
    end
    pregon:dibujar(BarraSuperior.alto() + Tema.px(16), derechaLibre(), abajoPregon)
    if envio then
        -- Modal: el mapa y los paneles se oscurecen bajo el envío.
        g.setColor(0, 0, 0, 0.55 * Vida.progreso('fondoModal:' .. tostring(envio)))
        g.rectangle('fill', 0, 0, w, h)
        Vida.entrar('modal:' .. tostring(envio), 0, Tema.px(30))
        envio:dibujar(mundo.sim)
        Vida.fin()
    elseif explorando then
        g.setColor(0, 0, 0, 0.55 * Vida.progreso('fondoModal:' .. tostring(explorando)))
        g.rectangle('fill', 0, 0, w, h)
        Vida.entrar('modal:' .. tostring(explorando), 0, Tema.px(30))
        explorando:dibujar(mundo.sim)
        Vida.fin()
    elseif fabrica then
        g.setColor(0, 0, 0, 0.55 * Vida.progreso('fondoModal:' .. tostring(fabrica)))
        g.rectangle('fill', 0, 0, w, h)
        Vida.entrar('modal:' .. tostring(fabrica), 0, Tema.px(30))
        local sigue = fabrica:dibujar(mundo.sim)
        Vida.fin()
        if not sigue then
            fabrica = nil
        end
    elseif ventanaPoblacion then
        g.setColor(0, 0, 0, 0.55 * Vida.progreso('fondoModal:' .. tostring(ventanaPoblacion)))
        g.rectangle('fill', 0, 0, w, h)
        Vida.entrar('modal:' .. tostring(ventanaPoblacion), 0, Tema.px(30))
        local sigue = ventanaPoblacion:dibujar(mundo.sim)
        Vida.fin()
        if not sigue then
            ventanaPoblacion = nil
        end
    end
    if suyaPlantar and plantando.x then
        -- La etiqueta va junto al ratón; en las capturas, junto al punto fijo.
        local sx, sy = love.mouse.getPosition()
        if plantando.fijo then
            local vx, vy =
                Iso.vista(plantando.x, plantando.y, math.max(0, mundo.terreno:altura(plantando.x, plantando.y)))
            sx, sy = (vx - camara.x) * camara.zoom + w / 2, (vy - camara.y) * camara.zoom + h / 2
        end
        plantando:dibujarPantalla(sx, sy, suyaPlantar)
    end
    -- El perfil y las opciones son pantallas completas: tapan el mapa y sus ayudas.
    if perfil.abierto or opciones.abierta or arsenal.abierto then
        local pantalla = { sim = mundo.sim, semilla = mundo.semilla, nacion = jugador and jugador.jugador or nil }
        -- Las pantallas completas entran con un fundido corto (interfaz/vida.lua).
        local cual = (perfil.abierto and 'perfil')
            or (opciones.abierta and ('opciones:' .. opciones.pantalla))
            or 'arsenal'
        Vida.entrar('pantalla:' .. cual, 0, Tema.px(14))
        perfil:dibujar(pantalla)
        opciones:dibujar(pantalla)
        arsenal:dibujar(pantalla)
        Vida.fin()
        perfil:dibujarAyuda()
        opciones:dibujarAyuda()
        arsenal:dibujarAyuda()
        dibujarFps()
        return
    end
    ejercito:dibujarAyuda()
    panelTropas:dibujarAyuda()
    radial:dibujarAyuda()
    pendon:dibujarAyuda()
    noticias:dibujarAyuda()
    barraSuperior:dibujarAyuda()
    columna:dibujarAyuda()
    navegacion:dibujarAyuda()
    dibujarFps()
end

-- Transición entre pantallas (el dueño, 2026-09-30: «una milésima de
-- suavidad al ir a cada pantalla»): al abrir o cerrar una pantalla o ventana,
-- la nueva aparece desde un velo oscuro que se desvanece en 0,18 s.
local transicion = { firma = nil, desde = -1 }
local DURACION_TRANSICION = 0.18

local function firmaPantalla()
    return table.concat({
        tostring(galeria ~= nil),
        tostring(inicio.login ~= nil),
        tostring(batalla ~= nil),
        tostring(perfil.abierto),
        tostring(opciones.abierta),
        tostring(opciones.pantalla),
        tostring(arsenal.abierto),
        tostring(envio ~= nil),
        tostring(explorando ~= nil),
        tostring(fabrica ~= nil),
        tostring(ventanaPoblacion ~= nil),
    }, ' ')
end

function love.draw()
    if inicio.login then
        inicio.login:dibujar()
    elseif almacenVista then
        almacenVista:dibujar()
    else
        dibujarJuego()
    end
    inicio.dialogo:dibujar()
    if carga and carga.listo then
        -- El primer dibujo del mapa (el más caro) queda debajo de la pantalla de carga.
        dibujarCarga()
        carga.calentado = true
    end
    local firma = firmaPantalla()
    local ahora = love.timer.getTime()
    if transicion.firma and firma ~= transicion.firma then
        transicion.desde = ahora
    end
    transicion.firma = firma
    local t = (ahora - transicion.desde) / DURACION_TRANSICION
    if t < 1 then
        local g = love.graphics
        g.setColor(0.04, 0.05, 0.04, 0.5 * (1 - t) * (1 - t))
        g.rectangle('fill', 0, 0, g.getDimensions())
        g.setColor(1, 1, 1, 1)
    end
    if almacenVideo and almacenVista then
        almacenVideo:cuadro(almacenVista)
    end
    -- `--almacen`: en cuanto la partida está lista, entra como el botón.
    if almacenAlEntrar and not carga and jugador then
        almacenAlEntrar = nil
        -- Partida de prueba del almacén: recursos para fabricar varios misiles
        -- (cada uno, 200 de dinero, 10 de metal y 10 de petróleo).
        local sim, n = mundo and mundo.sim, nil
        n = sim and sim.estado.naciones[jugador.jugador]
        if n then
            sim:ingresar(n, 'dinero', 2000)
            sim:ingresar(n, 'metal', 100)
            sim:ingresar(n, 'petroleo', 100)
        end
        love.keypressed('almacen')
    end
end

function love.wheelmoved(_, dy)
    if inicio.login or inicio.dialogo.abierto then
        return
    end
    if almacenVista then
        almacenVista:rueda(dy)
        return
    end
    if batalla then
        batalla:rueda(dy)
        return
    end
    if opciones.abierta or perfil.abierto or arsenal.abierto then
        opciones:rueda(dy)
        return
    end
    local mx, my = love.mouse.getPosition()
    -- Con el ratón sobre el pendón y contenido que no cabe, la rueda lo
    -- desplaza; en cualquier otro sitio, hace zoom.
    if pendon:rueda(mx, my, dy) or listaBatallas:rueda(mx, my, dy) or panelTropas:rueda(mx, my, dy) then
        return
    end
    camara.zoomObjetivo = math.max(ZOOM_MIN, math.min(ZOOM_MAX, (camara.zoomObjetivo or camara.zoom) * (1.15 ^ dy)))
end

--- Cierra el pendón que se muestra (botón de cerrar o Esc). Si era el de la
-- ciudad donde se está, no se vuelve a abrir hasta salir de ella.
local function cerrarPendon()
    if not seleccionada and not instalacionVista and not minaVista then
        local cx, cy = Iso.mundo(camara.x, camara.y)
        cerradaAqui = mundo:ciudadMasCercana(cx, cy)
    end
    seleccionada, instalacionVista, minaVista = nil, nil, nil
end

--- Clic en una relación del pendón: la cámara va a la capital de esa nación
-- (si se ha descubierto) y se abre su pendón.
local function irANacion(id)
    local nacion = mundo.sim:nacion(id)
    local capital = nacion and mundo.ciudadesPorId[nacion.capital]
    if capital then
        siguiendo = nil
        camara.x, camara.y = Iso.vista(capital.x, capital.y, capital.altura)
        seleccionada, instalacionVista, minaVista = capital, nil, nil
    end
end

--- Entra en la escena de batalla de un combate (nil: no hace nada). Sin
-- `enEscena`, solo se mira (observador o prueba): al salir no cambia nada.
function entrarEnBatalla(combate)
    if combate then
        arrastre = nil
        envio, explorando = nil, nil
        radial:cerrar()
        listaBatallas.abierta = false
        -- Preparación (diseno/batalla-despliegue-y-movimiento.md): 2:00 con
        -- el combate en pausa, también al volver a una batalla ya empezada.
        -- Las capturas que corren la pelea (`pelea3d`) entran ya en combate.
        combate.preparacion = not captura
        batalla = Escena.nueva(mundo, combate)
        if combate.preparacion then
            -- Vista alta detrás de su zona, mirando al enemigo (el dueño); al
            -- empezar el combate la cámara se queda donde esté.
            batalla:encuadrar('preparacion')
        else
            -- El mismo encuadre que el visor de pruebas de la batalla: la cámara
            -- junto a los robots, no a varios km donde se ven como puntos.
            batalla:encuadrar('cerca')
        end
    end
end

--- Entra en 3D en la batalla `bid` de la simulación (modo jugador): el
-- comando `entrarBatalla` la congela y da su estado; la escena se arma con lo
-- sano de ese momento. Devuelve true si entró.
function entrarEnBatallaSim(bid)
    local sim = mundo.sim
    local estado = jugador and sim:ejecutar({ tipo = 'entrarBatalla', nacion = jugador.jugador, batalla = bid })
    if not estado then
        return false
    end
    local p = preguntadas[bid]
    if p then
        p.usado = true
        pregon:quitar(p)
    end
    local combate = Choques.deBatalla(mundo, estado, Escena.describir, jugador.jugador)
    entrarEnBatalla(combate)
    enEscena = { id = bid, combate = combate }
    return true
end

--- Sale de la escena 3D. Si era una batalla de la simulación, lo que pasó
-- en ella vuelve unidad por unidad con `resolverBatalla` (muertos, heridos,
-- averiados con su daño y munición gastada por grupo); si la simulación no
-- lo acepta (o la batalla ya no existe), se sigue sin ver (`noDefender`).
function salirDeBatalla()
    local sim = mundo.sim
    if enEscena and batalla and jugador then
        local estado = sim:estadoBatalla(enEscena.id)
        if estado then
            local resultado = Choques.resultadoDeEscena(batalla.tropas, mundo.semilla, enEscena.id)
            -- Si la pelea terminó con una retirada, ese bando se va y pierde.
            local retira = batalla.fin and batalla.fin.retira or nil
            local hecho, aplicado = sim:ejecutar({
                tipo = 'resolverBatalla',
                batalla = enEscena.id,
                resultado = resultado,
                retira = retira,
            })
            local function resumen(lado)
                local a = type(aplicado) == 'table' and aplicado[lado]
                if not a then
                    return lado .. ' -'
                end
                return string.format(
                    '%s muertos %d heridos %d, averiados %d lanzacohetes, gasta %d balas %d misiles',
                    lado,
                    a.muertos,
                    a.heridos,
                    a.averiados.lanzacohetes,
                    a.municion.balas,
                    a.municion.misiles
                )
            end
            print(
                'RESUELTA',
                enEscena.id,
                hecho,
                'retira ' .. tostring(retira),
                resumen('atacante'),
                resumen('defensor')
            )
            if not hecho then
                sim:ejecutar({ tipo = 'noDefender', nacion = jugador.jugador, batalla = enEscena.id })
            end
        else
            print('RESUELTA', enEscena.id, 'ya estaba cerrada')
        end
    end
    enEscena = nil
    batalla = nil
    -- Lo que dejó la batalla, guardado (partida/guardado.lua).
    autoguardar()
end

--- Nombre de un sitio de la simulación: el de la ciudad o, si es una
-- instalación, «una base militar de <nación>» (o la que sea).
function nombreSitio(sim, s)
    if not s then
        return '?'
    end
    if s.nombre then
        return s.nombre
    end
    local n = sim:nacion(s.nacion)
    return Simulacion.nombreInstalacion(sim, s) .. (n and (' de ' .. n.nombre) or '')
end

--- Tu ciudad más cercana a (x, y): de ahí sale un ataque (hoy, tu capital).
local function ciudadPropiaCercana(x, y)
    local mejor, mejorD
    for _, c in ipairs(mundo.sim:ciudadesDe(jugador.jugador)) do
        local d = (c.x - x) ^ 2 + (c.y - y) ^ 2
        if not mejor or d < mejorD then
            mejor, mejorD = c, d
        end
    end
    return mejor
end

--- Tu ciudad o campamento terminado más cercano a (x, y): de ahí sale un
-- grupo a recolectar (y ahí entrega).
local function puestoPropioCercano(x, y)
    local mejor, mejorD
    for _, s in ipairs(mundo.sim:sitiosDe(jugador.jugador)) do
        if Simulacion.puestoDeAcopio(s) then
            local d = (s.x - x) ^ 2 + (s.y - y) ^ 2
            if not mejor or d < mejorD then
                mejor, mejorD = s, d
            end
        end
    end
    return mejor
end

--- Nombre de una mina para los títulos: «la mina de metal», «el campo petrolífero».
local function nombreMina(mina)
    local r = Simulacion.recursos[mina.tipo]
    local articulo = r and (r.articulo == 'una' and 'la ' or 'el ') or ''
    return articulo .. (r and r.nombre or 'mina')
end

--- «del complejo agrícola», «de la mina de metal».
local function deMina(mina)
    local nombre = nombreMina(mina)
    if nombre:sub(1, 3) == 'el ' then
        return 'del ' .. nombre:sub(4)
    end
    return 'de ' .. nombre
end

--- Botones del pendón de un yacimiento en modo jugador: «Recolectar» (desde
-- tu ciudad o campamento más cercano; abre el envío en modo recolectar) y,
-- si recolecta otra nación, «Atacar a los recolectores» (en paz, la
-- simulación declara la guerra al llegar).
function botonesMina(id)
    local sim = mundo.sim
    local mina = jugador and sim:mina(id)
    if not mina then
        return nil
    end
    local botones = {}
    local desde = puestoPropioCercano(mina.x, mina.y)
    botones[#botones + 1] = {
        texto = mina.cerrada and string.format('Cerrada · %d días', mina.diasCerrada) or 'Recolectar',
        tipo = 'principal',
        activo = desde ~= nil and not mina.cerrada,
        accion = function()
            envio = Envio.nuevo(desde, mina, nombreMina(mina), { modo = 'recolectar', sim = sim })
        end,
    }
    local ajenos, enPaz = 0, false
    for _, r in ipairs(mina.recolectores) do
        if r.nacion ~= jugador.jugador then
            ajenos = ajenos + 1
            enPaz = enPaz or not sim:guerraEntre(jugador.jugador, r.nacion)
        end
    end
    if ajenos > 0 then
        local salida = ciudadPropiaCercana(mina.x, mina.y)
        botones[#botones + 1] = {
            texto = enPaz and 'Atacar a los recolectores · guerra' or 'Atacar a los recolectores',
            tipo = 'peligro',
            activo = salida ~= nil,
            accion = function()
                envio = Envio.nuevo(salida, mina, 'los recolectores ' .. deMina(mina))
            end,
        }
    end
    return botones
end

--- Destinos para «Redirigir a…» un grupo propio: tus batallas en curso (a
-- las que no pertenece ya) y tus ciudades, campamentos y bases terminados,
-- los más cercanos primero (como mucho 6 sitios).
local function destinosRedirigir(gr)
    local sim = mundo.sim
    local botones = {}
    for _, b in ipairs(sim:batallasEnCurso(jugador.jugador)) do
        if b.id ~= gr.batalla then
            botones[#botones + 1] = {
                texto = 'Batalla: ' .. b.nombre,
                tipo = 'peligro',
                accion = 'destinoBatalla:' .. b.id,
            }
        end
    end
    local sitios = {}
    for _, s in ipairs(sim:sitiosDe(jugador.jugador)) do
        local terminado = sim.estado.ciudades[s.id]
            or ((s.tipo == 'campamento' or s.tipo == 'base') and s.progreso >= 1)
        if terminado then
            sitios[#sitios + 1] = { sitio = s, d = (s.x - gr.x) ^ 2 + (s.y - gr.y) ^ 2 }
        end
    end
    table.sort(sitios, function(a, b)
        if a.d ~= b.d then
            return a.d < b.d
        end
        return a.sitio.id < b.sitio.id
    end)
    for k = 1, math.min(6, #sitios) do
        local s = sitios[k].sitio
        botones[#botones + 1] = { texto = nombreSitio(sim, s), tipo = 'secundario', accion = 'destino:' .. s.id }
    end
    botones[#botones + 1] = { texto = 'Cancelar', tipo = 'secundario', accion = 'cancelarRedirigir' }
    return botones
end

--- Botones de la ficha de un grupo (y el aviso que va encima), modo jugador:
--   - tuyo en una batalla: «Entrar en la batalla»;
--   - tuyo fuera de casa: «Retirar» y «Redirigir a…» (eligiendo, la lista de destinos);
--   - recolectores ajenos en su mina: «Atacar a los recolectores», con el
--     aviso de que declara la guerra si hay paz.
function botonesFicha(gid)
    local sim = mundo.sim
    local gr = sim.estado.grupos[gid]
    if not (jugador and gr) then
        return nil
    end
    if gr.nacion == jugador.jugador then
        -- Convoyes de munición y remolques: no se desvían (solo se retira un convoy).
        if gr.mision == 'abasto' then
            return { { texto = 'Retirar', tipo = 'secundario', accion = 'retirar' } },
                'Va a su ejército y vuelve solo: no se puede desviar'
        elseif gr.remolque then
            return nil, 'Vuelve remolcado al taller: no se puede atacar ni desviar'
        end
        if redirigiendo == gid then
            return destinosRedirigir(gr), 'Elige adónde va (conserva la carga)'
        end
        local botones = {}
        if gr.batalla then
            local puede = false
            for _, b in ipairs(sim:batallasEnCurso(jugador.jugador)) do
                puede = puede or (b.id == gr.batalla and b.puedeEntrar)
            end
            botones[#botones + 1] =
                { texto = 'Entrar en la batalla', tipo = 'peligro', activo = puede, accion = 'entrar:' .. gr.batalla }
        end
        local fuera = gr.mision ~= 'regreso' and gr.mision ~= 'entrega' and gr.mision ~= 'construir'
        if fuera then
            botones[#botones + 1] = { texto = 'Retirar', tipo = 'secundario', accion = 'retirar' }
        end
        if gr.mision ~= 'entrega' and gr.mision ~= 'construir' then
            botones[#botones + 1] = { texto = 'Redirigir a…', tipo = 'secundario', accion = 'redirigir' }
        end
        -- Munición: «Abastecer» manda un convoy desde tu ciudad más cercana
        -- con lo que le falta hasta la dotación de ataque (F5).
        local tropa = (gr.soldados or 0) + (gr.lanzacohetes or 0)
        if tropa > 0 and fuera then
            local puede, motivo = abastecerGrupo(gr.id, false)
            botones[#botones + 1] = {
                texto = puede and 'Abastecer · munición' or motivo,
                tipo = 'principal',
                activo = puede == true,
                accion = 'abastecer',
            }
        end
        local avisos = {}
        local m = sim:municionGrupo(gr.id)
        if m then
            local sin = {}
            for _, par in ipairs({
                { 'lanzacohetes', 'Lanzacohetes sin misiles' },
                { 'soldados', 'Soldados sin balas' },
            }) do
                if m.sin[par[1]] then
                    sin[#sin + 1] = par[2]
                end
            end
            if #sin > 0 then
                avisos[#avisos + 1] = table.concat(sin, ' · ') .. ': no disparan'
            end
        end
        local aviso = gr.batalla and fuera and 'Retirar o redirigir en batalla es retirarse'
        if aviso and gr.tipoCarga then
            aviso = aviso .. ': pierde la carga'
        end
        avisos[#avisos + 1] = aviso or nil
        return botones, #avisos > 0 and table.concat(avisos, '. ') or nil
    end
    -- Ajeno: su poder solo se sabe con un informe (interfaz/inteligencia.lua).
    local explorar = { texto = 'Explorar', tipo = 'secundario', accion = 'explorar' }
    if gr.mision == 'recolectar' and gr.fase == 'recolectando' and gr.yacimiento then
        local enPaz = not sim:guerraEntre(jugador.jugador, gr.nacion)
        local n = sim:nacion(gr.nacion)
        local aviso = enPaz and ('Estás en paz con ' .. (n and n.nombre or '?') .. ': atacar les declara la guerra')
        return {
            { texto = 'Atacar a los recolectores', tipo = 'peligro', accion = 'atacarRecolectores' },
            explorar,
        },
            aviso or nil
    end
    return { explorar }
end

--- Sitios propios desde donde puede salir un ataque contra (x, y): tus
-- ciudades y bases o campamentos terminados con tropa, del más cercano al
-- más lejano.
local function origenesAtaque(x, y)
    local lista = {}
    for _, o in ipairs(Explorar.origenes(mundo.sim, jugador.jugador, x, y)) do
        local s = o.sitio
        if (s.soldados or 0) + (s.lanzacohetes or 0) > 0 then
            lista[#lista + 1] = s
        end
    end
    return lista
end

--- Abre el envío contra `objetivo` (sitio de otra nación, datos de la
-- simulación) desde tu sitio con tropa más cercano; con ‹ › se elige otro.
-- La guerra, si hace falta, se declara al mandar (ver `mandarAtaque`).
-- Devuelve false y el motivo si no se puede.
function abrirAtaque(objetivo)
    local sim = mundo.sim
    if not jugador or not objetivo or objetivo.nacion == jugador.jugador then
        return false, 'Ya es tuyo'
    end
    local puede, motivo = sim:puedeAtacar(jugador.jugador, objetivo.id)
    if not puede and motivo == 'sinFrontera' then
        return false, 'No tienes frontera con ellos'
    end
    local origenes = origenesAtaque(objetivo.x, objetivo.y)
    if #origenes == 0 then
        return false, 'No tienes tropas en ningún sitio'
    end
    envio = Envio.nuevo(origenes[1], objetivo, nombreSitio(sim, objetivo), { origenes = origenes })
    return true
end

--- Botones de órdenes del pendón de una instalación: ninguno (para atacar se
-- va al objetivo: menú radial o ejército elegido).
function botonesInstalacion()
    return nil
end

--- Botones de órdenes del pendón de una ciudad en modo jugador: en tu
-- capital, plantar bandera. Atacar no está aquí: se va al objetivo (menú
-- radial o ejército elegido).
function botonesCiudad(ciudad)
    if not jugador or not ciudad or ciudad.region ~= jugador.capitalJugador then
        return nil
    end
    local desde = mundo.sim:ciudad(jugador.capitalJugador)
    if not (desde and desde.nacion == jugador.jugador) then
        return nil
    end
    return {
        {
            texto = plantando and 'Cancelar la bandera' or 'Plantar bandera · P',
            tipo = 'principal',
            activo = true,
            accion = alternarPlantar,
        },
    }
end

-- Menú radial -------------------------------------------------------------------------------

--- Objetivo del radial abierto: el sitio (o la mina) de la simulación, o nil
-- si ya no existe.
function objetivoRadial()
    local o = radial.objetivo
    if not o then
        return nil
    end
    if o.tipo == 'mina' then
        return mundo.sim:mina(o.id)
    end
    return mundo.sim:sitio(o.id)
end

--- «Capital», «Ciudad», «Base militar», «Bandera»…
local function tipoSitio(sim, s)
    if sim.estado.ciudades[s.id] then
        local n = sim:nacion(s.nacion)
        return n and n.capital == s.id and 'Capital' or 'Ciudad'
    end
    local nombre = (Simulacion.nombreInstalacion(sim, s):gsub('^una? ', ''))
    return nombre:sub(1, 1):upper() .. nombre:sub(2)
end

--- Relación con la nación `nid`: texto y color.
local function relacionCon(sim, nid)
    local guerra = sim:guerraEntre(jugador.jugador, nid)
    if guerra and guerra.fase == 'calma' then
        return 'Alto el fuego', 'amarillo'
    elseif guerra then
        return 'En guerra', 'rojoTexto'
    end
    local n = sim:nacion(jugador.jugador)
    local valor = n and sim:nacion(nid) and math.floor(sim:relacion(n.id, nid)) or 0
    return string.format('En paz · %s%d', valor > 0 and '+' or '', valor), valor < 0 and 'amarillo' or 'verde'
end

--- «250 sold. · 2 lanzac.».
local function textoTropas(t)
    t = t or {}
    return string.format('%s sold. · %s lanzac.', Tema.numero(t.soldados or 0), Tema.numero(t.lanzacohetes or 0))
end

--- Defensas de un informe: una cifra o { lanzacohetes = 3, baterias = 1, … }.
local function textoDefensas(d)
    if type(d) == 'number' then
        return Tema.numero(d)
    end
    if type(d) ~= 'table' then
        return nil
    end
    local partes = {}
    for _, clave in ipairs(Simulacion.ordenadas(d)) do
        if type(d[clave]) == 'number' and d[clave] > 0 then
            partes[#partes + 1] = Tema.numero(d[clave]) .. ' ' .. clave
        end
    end
    return #partes > 0 and table.concat(partes, ' · ') or 'ninguna'
end

--- Exploradores tuyos que van hacia `objetivo` (id): días que les faltan, o nil.
local function exploradoresHacia(sim, objetivo)
    if not sim.exploradoresEnCamino then
        return nil
    end
    local mejor
    for _, e in ipairs(sim:exploradoresEnCamino(jugador.jugador) or {}) do
        if e.objetivo == objetivo then
            local dias = e.llegaDia and math.max(0, e.llegaDia - sim.estado.dia) or 0
            mejor = math.min(mejor or math.huge, dias)
        end
    end
    return mejor
end

--- Puntos de vida que tu nación puede reparar ahora en la ciudad `c` (lo
-- que falta hasta 100 o lo que alcanza a pagar) y su coste.
local function reparacionPosible(c)
    local n = mundo.sim:nacion(c.nacion)
    local falta = math.floor(Simulacion.vidaCiudad.maxima - Simulacion.vidaSitio(c) - (c.reparacion or 0))
    if not n or falta < 1 then
        return 0
    end
    local porPunto = Simulacion.costeReparacion(1)
    local puntos = falta
    for _, recurso in ipairs({ 'metal', 'petroleo', 'dinero' }) do
        if porPunto[recurso] > 0 then
            puntos = math.min(puntos, math.floor(Simulacion.disponible(n, recurso) / porPunto[recurso]))
        end
    end
    return math.max(0, puntos), falta
end

--- «X:3817 Y:2734»: las coordenadas del sitio en metros (10 px = 1 m).
local function coordenadas(x, y)
    return string.format('X:%d Y:%d', math.floor(x / 10), math.floor(y / 10))
end

--- «1 240 · hace 3 días» (valor de un informe) o «Desconocido · Explorar».
local function filaDeInforme(sim, etiqueta, valor, inf)
    if not inf then
        return { etiqueta, Inteligencia.textoDesconocido, color = 'textoHudTenue' }
    end
    local texto = Tema.numero(Simulacion.poderRedondeado(valor or 0)) .. ' · ' .. Inteligencia.hace(sim, inf.dia)
    return { etiqueta, texto, icono = 'poder' }
end

--- Filas de la tarjeta del radial de tu ciudad (economía cerrada): cada
-- tropa con su tope (lo de la ciudad, también fuera o en fábrica, contra el
-- tope de su nivel), el polvorín, lo que está en fábrica y el taller.
function filasEconomia(sim, c, filas)
    local inv = sim:inventarioCiudad(c.id)
    for _, par in ipairs({ { 'soldados', 'Soldados' }, { 'lanzacohetes', 'Lanzacohetes' } }) do
        local tope = sim:topeCiudad(c, par[1])
        filas[#filas + 1] = {
            par[2] .. ' (tope)',
            string.format('%s / %s', Tema.numero(inv[par[1]]), Tema.numero(tope)),
            color = inv[par[1]] >= tope and 'rojoTexto' or nil,
        }
    end
    local p = sim:polvorin(c.id) or {}
    filas[#filas + 1] = {
        'Balas · misiles',
        string.format('%s · %s', Tema.numero(p.balas or 0), Tema.numero(p.misiles or 0)),
    }
    local enFabrica = {}
    for _, par in ipairs({ { 'soldados', 'sold.' }, { 'lanzacohetes', 'lanzac.' } }) do
        if inv.fabrica[par[1]] > 0 then
            enFabrica[#enFabrica + 1] = Tema.numero(inv.fabrica[par[1]]) .. ' ' .. par[2]
        end
    end
    local lotes = #((sim:colaFabrica(c.id) or {}).municion or {})
    if lotes > 0 then
        enFabrica[#enFabrica + 1] = lotes == 1 and '1 munición' or (lotes .. ' municiones')
    end
    if #enFabrica > 0 then
        filas[#filas + 1] = { 'En fábrica', table.concat(enFabrica, ' · '), color = 'amarillo' }
    end
    local taller = Fabrica.textoTaller(c)
    if taller then
        filas[#filas + 1] = { 'En el taller', taller, color = 'amarillo' }
    end
end

--- Botones y tarjeta de datos del radial de un sitio (ciudad o instalación),
-- como en diseno/referencias-warpath/radial_ciudad_propia.jpg: la tarjeta
-- lleva Comandante, Poder, Poder terrestre, Alianza y Vida; lo ajeno, el
-- poder solo con informe de exploradores (y su relación, distancia y, si hay
-- informe, sus tropas). Botones: tuyo, «Reparar» (si hace falta),
-- «Arsenal», «Regresar» y «Base»; ajeno, «Atacar», «Regresar» y «Explorar».
local function opcionesSitio(sim, s)
    local nid = jugador.jugador
    local n = sim:nacion(s.nacion)
    local propio = s.nacion == nid
    local esCiudad = sim.estado.ciudades[s.id] ~= nil
    local nombre = s.nombre or tipoSitio(sim, s)
    local titulo = tipoSitio(sim, s)
    if esCiudad then
        titulo = string.format('%s nv. %d', titulo, s.nivel or 1)
    end
    local o = {
        nombre = nombre,
        nivel = esCiudad and (s.nivel or 1) or nil,
        colorNombre = propio and 'verdeNombre' or 'rojoTexto',
        titulo = titulo,
        coordenadas = coordenadas(s.x, s.y) .. (propio and '' or (' · ' .. (n and n.nombre or '?'))),
        favorito = favoritas[s.id] == true,
        filas = {},
        botones = {},
    }
    local filas = o.filas
    filas[#filas + 1] = { 'Comandante', n and n.gobernante and n.gobernante.nombre or '?' }
    -- Poder terrestre: sus tropas (soldados y lanzacohetes). Poder:
    -- con lo que defiende el sitio (tropas, baterías y el efecto de su vida o
    -- su fortificación), la misma cuenta que usa la simulación con un informe.
    if propio then
        local foto = {
            tipo = esCiudad and 'ciudad' or s.tipo,
            poder = Simulacion.poderSitio(s),
            defensas = { baterias = s.baterias or 0, fortificacion = s.fortificacion or 0 },
            vida = Simulacion.vidaSitio(s),
        }
        local defensa = Simulacion.defensaInforme and Simulacion.defensaInforme(foto) or foto.poder
        filas[#filas + 1] = { 'Poder', Tema.numero(Simulacion.poderRedondeado(defensa)), icono = 'poder' }
        filas[#filas + 1] = { 'Poder terrestre', Tema.numero(Simulacion.poderRedondeado(foto.poder)), icono = 'poder' }
    else
        local inf = Inteligencia.informe(sim, nid, s.id)
        local fuerza = inf and (Simulacion.defensaInforme and Simulacion.defensaInforme(inf) or inf.poder)
        filas[#filas + 1] = filaDeInforme(sim, 'Poder', fuerza, inf)
        filas[#filas + 1] = filaDeInforme(sim, 'Poder terrestre', inf and inf.poder, inf)
        if inf then
            filas[#filas + 1] = { 'Tropas', textoTropas(inf.tropas) }
        end
    end
    filas[#filas + 1] = { 'Alianza', 'Ninguna' }
    -- La vida de lo ajeno también es secreta: la del último informe, o desconocida.
    local etiquetaVida = esCiudad and 'Vida de la ciudad' or 'Vida'
    local infVida = not propio and Inteligencia.informe(sim, nid, s.id)
    if propio then
        local vida = Simulacion.vidaSitio(s)
        filas[#filas + 1] = { etiquetaVida, string.format('%d / 100', math.floor(vida + 0.5)) }
    elseif infVida then
        filas[#filas + 1] = {
            etiquetaVida,
            string.format(
                '%d / 100 · %s',
                math.floor(Inteligencia.vidaInforme(infVida) + 0.5),
                Inteligencia.hace(sim, infVida.dia)
            ),
        }
    else
        filas[#filas + 1] = { etiquetaVida, Inteligencia.textoDesconocido, color = 'textoHudTenue' }
    end
    if not propio then
        local relacion, colorRelacion = relacionCon(sim, s.nacion)
        filas[#filas + 1] = { 'Relación', relacion, color = colorRelacion }
        local cerca = Explorar.origenes(sim, nid, s.x, s.y)[1]
        filas[#filas + 1] = { 'Distancia', cerca and Explorar.textoDistancia(cerca.d) or '—' }
        local enCamino = exploradoresHacia(sim, s.id)
        if enCamino then
            filas[#filas + 1] = {
                'Exploradores',
                enCamino == 0 and 'llegan hoy'
                    or string.format('llegan en %d %s', enCamino, enCamino == 1 and 'día' or 'días'),
                color = 'amarillo',
            }
        end
    end
    local botones = o.botones
    local regresar = { clave = 'regresar', icono = 'retirar', etiqueta = 'Regresar', ayuda = 'Cerrar el menú' }
    if propio and esCiudad then
        -- Población real (diseno/poblacion.md) y cuántos soldados más caben
        -- por los aptos de 18 a 49 años; el desglose, en el pendón.
        local reclutables = math.max(0, Simulacion.maximoSoldados(s, sim:inventarioCiudad(s.id)))
        filas[#filas + 1] = {
            'Población (reclutables)',
            string.format('%s (%s)', Tema.numero(s.poblacion or 0), Tema.numero(reclutables)),
        }
        filasEconomia(sim, s, filas)
        local tropa = (s.soldados or 0) + (s.lanzacohetes or 0)
        botones[#botones + 1] = {
            clave = 'sacar',
            icono = 'ejercito',
            etiqueta = 'Ejército',
            activo = tropa > 0,
            ayuda = tropa > 0 and 'Sacar tropas de la ciudad como un ejército' or 'No hay tropas en la ciudad',
        }
        botones[#botones + 1] = {
            clave = 'soldados',
            icono = 'refuerzo',
            etiqueta = 'Crear soldados',
            ayuda = 'Reclutar soldados en esta ciudad: cuántos, coste y días',
        }
        botones[#botones + 1] = {
            clave = 'municion',
            icono = 'suministros',
            etiqueta = 'Producir munición',
            ayuda = 'Balas y misiles para el polvorín de la ciudad',
        }
        botones[#botones + 1] = {
            clave = 'poblacion',
            icono = 'alianza',
            etiqueta = 'Población',
            ayuda = 'Tu gente por edades, soldados, vivienda y nacimientos del año',
        }
        botones[#botones + 1] = {
            clave = 'arsenal',
            icono = 'unidades',
            etiqueta = 'Arsenal',
            ayuda = 'Arsenal: producir lanzacohetes, y la cola de fábrica (U)',
        }
        botones[#botones + 1] = regresar
        botones[#botones + 1] = {
            clave = 'base',
            icono = 'construir',
            etiqueta = 'Base',
            ayuda = 'Entrar en la ciudad (en construcción)',
            destacado = true,
        }
        -- Reparar la vida de la ciudad y el taller, en un solo botón (y su panel).
        local puntos, falta = reparacionPosible(s)
        local taller = Fabrica.textoTaller(s)
        if (falta and falta >= 1) or taller then
            local partes = {}
            if falta and falta >= 1 then
                partes[#partes + 1] = puntos >= 1
                        and string.format(
                            'Reparar +%d · %s dinero',
                            puntos,
                            Tema.numero(Simulacion.costeReparacion(puntos).dinero)
                        )
                    or 'No alcanza para reparar la ciudad'
            end
            if taller then
                partes[#partes + 1] = 'En el taller: ' .. taller
            end
            botones[#botones + 1] = {
                clave = 'taller',
                icono = 'reparar',
                etiqueta = 'Reparar',
                ayuda = table.concat(partes, '\n'),
            }
        end
        return o
    end
    if propio then
        botones[#botones + 1] = { clave = 'info', icono = 'misiones', etiqueta = 'Info', ayuda = 'Panel del sitio' }
        botones[#botones + 1] = regresar
        o.centro = 2
        return o
    end
    local puede, motivo = sim:puedeAtacar(nid, s.id)
    local sinFrontera = not puede and motivo == 'sinFrontera'
    local enGuerra = sim:guerraEntre(nid, s.nacion) ~= nil
    local ayudaAtacar = enGuerra and 'Elegir tropas y atacar'
        or ('Declara la guerra a ' .. (n and n.nombre or '?') .. ' y ataca')
    if sinFrontera then
        ayudaAtacar = 'No tienes frontera con ellos'
    end
    botones[#botones + 1] = {
        clave = 'atacar',
        icono = 'atacar',
        etiqueta = 'Atacar',
        activo = not sinFrontera and #origenesAtaque(s.x, s.y) > 0,
        ayuda = ayudaAtacar,
    }
    botones[#botones + 1] = regresar
    o.centro = 2
    local yaVa = sim.explorandoA and sim:explorandoA(nid, s.id)
    botones[#botones + 1] = {
        clave = 'explorar',
        icono = 'busqueda',
        etiqueta = 'Explorar',
        activo = not yaVa,
        ayuda = yaVa and 'Ya van tus exploradores' or 'Mandar exploradores: su poder, sus tropas y sus defensas',
    }
    if not esCiudad then
        botones[#botones + 1] = { clave = 'info', icono = 'misiones', etiqueta = 'Info', ayuda = 'Panel del sitio' }
    end
    return o
end

--- Botones y ficha de datos del radial de una mina.
local function opcionesMina(sim, m)
    local r = Simulacion.recursos[m.tipo]
    local nombre = r and (r.nombre:sub(1, 1):upper() .. r.nombre:sub(2)) or 'Mina'
    local duena = m.dueno and sim:nacion(m.dueno)
    local o = {
        nombre = nombre,
        colorNombre = 'amarillo',
        titulo = nombre,
        coordenadas = coordenadas(m.x, m.y)
            .. ' · '
            .. (duena and ('tierra de ' .. duena.nombre) or 'tierra de nadie'),
        filas = {},
        botones = {},
    }
    local filas = o.filas
    filas[#filas + 1] = {
        'Queda',
        m.cerrada and string.format('cerrada · %d días', m.diasCerrada)
            or (Tema.numero(m.queda) .. ' de ' .. Tema.numero(m.reserva)),
    }
    filas[#filas + 1] = { 'Riqueza', Tema.numero(m.riqueza), color = 'amarillo' }
    local ajenos, nombres = 0, {}
    for _, rec in ipairs(m.recolectores) do
        local n = sim:nacion(rec.nacion)
        nombres[#nombres + 1] = rec.nacion == jugador.jugador and 'tú' or (n and n.nombre or '?')
        if rec.nacion ~= jugador.jugador then
            ajenos = ajenos + 1
        end
    end
    filas[#filas + 1] = { 'Recolectan', #nombres > 0 and table.concat(nombres, ', ') or 'nadie' }
    local desde = puestoPropioCercano(m.x, m.y)
    if desde then
        filas[#filas + 1] = {
            'Distancia',
            Explorar.textoDistancia(math.sqrt((desde.x - m.x) ^ 2 + (desde.y - m.y) ^ 2)),
        }
    end
    o.botones[#o.botones + 1] = {
        clave = 'recolectar',
        icono = 'recolectar',
        etiqueta = 'Recolectar',
        activo = desde ~= nil and not m.cerrada,
        ayuda = m.cerrada and 'Cerrada: agotada' or 'Mandar un grupo a recolectar',
    }
    o.botones[#o.botones + 1] =
        { clave = 'regresar', icono = 'retirar', etiqueta = 'Regresar', ayuda = 'Cerrar el menú' }
    o.centro = #o.botones
    if ajenos > 0 then
        o.botones[#o.botones + 1] = {
            clave = 'atacarMina',
            icono = 'atacar',
            etiqueta = 'Atacar',
            activo = #origenesAtaque(m.x, m.y) > 0,
            ayuda = 'Atacar a los recolectores (en paz, declara la guerra al llegar)',
        }
    end
    if not duena then
        o.botones[#o.botones + 1] =
            { clave = 'plantar', icono = 'bandera', etiqueta = 'Plantar', ayuda = 'Plantar una bandera cerca (P)' }
    end
    o.botones[#o.botones + 1] = { clave = 'info', icono = 'misiones', etiqueta = 'Info', ayuda = 'Panel de la mina' }
    return o
end

--- Opciones del radial abierto (nil si su objetivo ya no existe).
function opcionesRadial()
    local s = objetivoRadial()
    if not (s and jugador) then
        return nil
    end
    if radial.objetivo.tipo == 'mina' then
        return opcionesMina(mundo.sim, s)
    end
    local o = opcionesSitio(mundo.sim, s)
    -- La tarjeta, si va a la derecha, no se mete bajo los avisos.
    local bajo = 0
    for _, z in ipairs(pregon.zonas or {}) do
        bajo = math.max(bajo, z.y + z.h)
    end
    o.libreDesde = bajo > 0 and (bajo + Tema.px(8)) or nil
    -- Y no se mete bajo la barra de botones de abajo (el panel de tropas se
    -- oculta mientras el radial está abierto).
    o.barraAbajo = navegacion.rect
    return o
end

--- Entra en la ciudad por dentro (modo «Base»): aún no existe (Lucía lo
-- está diseñando); por ahora, un aviso breve.
local function abrirBase(ciudad)
    ejercito:avisar('Base de ' .. (ciudad.nombre or 'la ciudad') .. ': en construcción')
end

--- Abre el panel de exploración contra `objetivo` = { id, x, y, nombre }.
local function abrirExplorar(objetivo)
    explorando = Explorar.nuevo(mundo.sim, jugador.jugador, objetivo)
end

--- Aplica el botón `clave` del radial abierto.
function accionRadial(clave)
    local sim = mundo.sim
    local s = objetivoRadial()
    local o = radial.objetivo
    if not (s and o and jugador) then
        radial:cerrar()
        return
    end
    if clave == 'favorito' then
        -- Marca de la vista (no se guarda ni cambia la simulación).
        favoritas[s.id] = not favoritas[s.id] or nil
        return
    end
    radial:cerrar()
    if clave == 'regresar' then
        seleccionada, instalacionVista, minaVista = nil, nil, nil
    elseif clave == 'base' then
        abrirBase(s)
    elseif clave == 'info' or clave == 'tropas' then
        if o.tipo == 'mina' then
            seleccionada, instalacionVista, minaVista = nil, nil, s.id
        elseif sim.estado.ciudades[s.id] then
            seleccionada, instalacionVista, minaVista = mundo:ciudadFisica(s.id), nil, nil
            pendon.pestana = clave == 'tropas' and 'ejercito' or 'resumen'
        else
            seleccionada, instalacionVista, minaVista = nil, s.id, nil
        end
        cerradaAqui = nil
    elseif clave == 'atacar' then
        local ok, motivo = abrirAtaque(s)
        if not ok then
            ejercito:avisar(motivo)
        end
    elseif clave == 'explorar' then
        abrirExplorar({ id = s.id, x = s.x, y = s.y, nombre = nombreSitio(sim, s) })
    elseif clave == 'taller' or clave == 'soldados' or clave == 'municion' then
        fabrica = Fabrica.nuevo(sim, s, clave)
    elseif clave == 'poblacion' then
        ventanaPoblacion = VentanaPoblacion.nuevo(s)
    elseif clave == 'sacar' then
        envio = Envio.nuevo(s, s, s.nombre, { modo = 'sacar', sim = sim })
    elseif clave == 'arsenal' then
        arsenal:abrir(s.id)
    elseif clave == 'recolectar' then
        local desde = puestoPropioCercano(s.x, s.y)
        if desde and not s.cerrada then
            envio = Envio.nuevo(desde, s, nombreMina(s), { modo = 'recolectar', sim = sim })
        end
    elseif clave == 'atacarMina' then
        local origenes = origenesAtaque(s.x, s.y)
        if origenes[1] then
            envio = Envio.nuevo(origenes[1], s, 'los recolectores ' .. deMina(s), { origenes = origenes })
        end
    elseif clave == 'plantar' then
        if not plantando then
            alternarPlantar()
        end
    end
end

--- Manda a la simulación los comandos del panel de encargo abierto (uno por
-- munición, o el de «Reparar» o «Sacar ya» del taller). Si uno no sale, el
-- panel se queda abierto con el motivo; si salen, se cierra con un aviso (el
-- del taller sigue abierto). Devuelve si salieron todos.
function mandarComandos(comandos)
    local sim = mundo.sim
    local hecho = fabrica:textoHecho(sim)
    for _, c in ipairs(comandos) do
        local ok, motivo = sim:ejecutar(c)
        print('ENCARGO', c.tipo, c.tropa or '', c.cantidad or c.puntos or '', tostring(ok), tostring(motivo or ''))
        if not ok then
            if c.tipo == 'producir' then
                fabrica.motivo = Fabrica.textoMotivo(sim, c.nacion, c.ciudad, c.tropa, c.cantidad, motivo)
            elseif motivo == 'coste' then
                fabrica.motivo = 'No alcanza para pagarlo'
            else
                fabrica.motivo = 'No se puede ahora (' .. tostring(motivo) .. ')'
            end
            return false
        end
    end
    if fabrica.modo == 'taller' then
        local c = comandos[1]
        local ciudad = sim.estado.ciudades[c.ciudad]
        if c.tipo == 'reparar' then
            ejercito:avisar(string.format('Reparando %s: +%d de vida', ciudad and ciudad.nombre or '', c.puntos))
        else
            ejercito:avisar('Sale del taller de ' .. (ciudad and ciudad.nombre or 'la ciudad'))
        end
    else
        ejercito:avisar(hecho)
        fabrica = nil
    end
    return true
end

--- Hace regresar los grupos `ids` (en orden de id): vuelven andando a su
-- ciudad. Con todos los de la nación que no pelean, un `regresarTodos`; si
-- no, uno por grupo: `regresarGrupo` o, si esta simulación aún no lo tiene
-- (Andrés lo está programando con las banderas del borde), `retirar`, que
-- hace lo mismo. Avisa en el panel de tropas de cuántos vuelven.
local function regresarGrupos(ids)
    local sim = mundo.sim
    local nid = jugador.jugador
    table.sort(ids)
    local libres = 0
    for _, g in ipairs(PanelTropas.grupos(sim, nid)) do
        if not g.batalla then
            libres = libres + 1
        end
    end
    local vuelven, noPueden = 0, 0
    if Simulacion.regresarTodos and #ids > 0 and #ids == libres then
        local hecho, cuenta = sim:ejecutar({ tipo = 'regresarTodos', nacion = nid })
        if hecho and type(cuenta) == 'table' then
            vuelven, noPueden = cuenta.vuelven or 0, cuenta.noPueden or 0
        end
    else
        local tipo = Simulacion.regresarTodos and 'regresarGrupo' or 'retirar'
        for _, gid in ipairs(ids) do
            if sim:ejecutar({ tipo = tipo, nacion = nid, grupo = gid }) then
                vuelven = vuelven + 1
            else
                noPueden = noPueden + 1
            end
        end
    end
    local texto = vuelven == 1 and '1 grupo regresa' or (Tema.numero(vuelven) .. ' grupos regresan')
    if vuelven == 0 then
        texto = 'No pueden regresar'
    elseif noPueden > 0 then
        texto = texto .. ' · ' .. Tema.numero(noPueden) .. ' no pueden'
    end
    panelTropas:avisar(texto)
end

--- Lo que pide el panel de tropas (interfaz/tropas.lua).
function accionTropas(a)
    local sim = mundo.sim
    local nid = jugador.jugador
    if a.tipo == 'elegir' then
        -- Elige ese grupo en el mapa y centra la cámara en él.
        ejercito:poner({ a.gid })
        fichaVista, redirigiendo, siguiendo = nil, nil, nil
        radial:cerrar()
        local gr = sim.estado.grupos[a.gid]
        if gr then
            local x, y = mundo:posicionFicha(gr, sim:fraccionPaso())
            x, y = x or gr.x, y or gr.y
            camara.x, camara.y = Iso.vista(x, y, math.max(0, mundo.terreno:altura(x, y)))
        end
    elseif a.tipo == 'todos' then
        local ids = panelTropas:idsFiltro(sim, nid)
        local todos = #ids > 0
        for _, gid in ipairs(ids) do
            if not ejercito:tiene(gid) then
                todos = false
            end
        end
        if todos then
            ejercito:limpiar()
        else
            ejercito:poner(ids)
        end
    elseif a.tipo == 'regresar' then
        local elegidos = {}
        for _, gid in ipairs(ejercito.ids) do
            elegidos[gid] = true
        end
        regresarGrupos((panelTropas:idsRegresar(sim, nid, elegidos)))
    elseif a.tipo == 'regresarUno' then
        regresarGrupos({ a.gid })
    end
end

--- Manda los comandos del Arsenal («Producir» o «Cancelar» una orden) y le
-- dice cómo fue.
function mandarArsenal(comandos)
    local sim = mundo.sim
    for _, c in ipairs(comandos) do
        local ok, motivo = sim:ejecutar(c)
        print('ARSENAL', c.tipo, c.tropa or c.orden, c.cantidad or '', tostring(ok), tostring(motivo or ''))
        local ciudad = sim.estado.ciudades[c.ciudad]
        local nombre = ciudad and ciudad.nombre or 'la ciudad'
        if c.tipo == 'producir' and ok then
            local nombres = Fabrica.NOMBRES[c.tropa]
            local que = Simulacion.esMunicion(c.tropa)
                    and (Fabrica.plural(c.cantidad, 'lote', 'lotes') .. ' de ' .. nombres[2])
                or Fabrica.nombreEncargo(c.tropa, c.cantidad, c.modelo)
            arsenal:resultado(
                true,
                string.format(
                    'Encargado en %s: %s · %s',
                    nombre,
                    que,
                    Fabrica.textoDias(Simulacion.diasProduccion(c.tropa, c.cantidad, c.modelo))
                )
            )
        elseif c.tipo == 'producir' then
            arsenal:resultado(
                false,
                Fabrica.textoMotivo(sim, c.nacion, c.ciudad, c.tropa, c.cantidad, motivo, c.modelo)
            )
        elseif ok then
            arsenal:resultado(true, 'Orden cancelada en ' .. nombre .. ': vuelve la mitad de lo pagado')
        else
            arsenal:resultado(false, 'No se pudo cancelar (' .. tostring(motivo) .. ')')
        end
    end
end

--- Texto de por qué la simulación no mandó a los exploradores.
local function textoMotivoExplorar(motivo)
    local textos = {
        coste = 'No alcanza para pagar la exploración',
        origen = 'Ese sitio no es tuyo',
        objetivo = 'El objetivo ya no existe',
        destino = 'El objetivo ya no existe',
        sinCamino = 'No hay camino hasta allí',
        propio = 'Es tuyo: no hace falta explorarlo',
        enCamino = 'Ya van tus exploradores hacia allí',
        nacion = 'Tu nación no puede mandar exploradores',
        tipoDesconocido = 'La simulación aún no manda exploradores',
    }
    return textos[motivo] or ('No salen: ' .. tostring(motivo or 'motivo desconocido'))
end

--- Manda a los exploradores del panel abierto (comando `explorar`).
local function mandarExploradores()
    local ok, motivo = mundo.sim:ejecutar(explorando:comando())
    if ok then
        ejercito:avisar('Exploradores en camino a ' .. (explorando.objetivo.nombre or 'su objetivo'))
        explorando = nil
    else
        explorando.motivo = textoMotivoExplorar(motivo)
    end
end

--- Manda lo elegido en el envío (un ataque o una recolección): si hace
-- falta guerra con el dueño del objetivo, primero la declara (comando
-- `declararGuerra`). Si la simulación no lo acepta, el envío se queda
-- abierto con el motivo.
function mandarAtaque()
    local sim = mundo.sim
    local previo = envio:motivoPrevio(sim)
    if previo then
        envio.motivo = previo
        return false
    end
    if envio:haceFaltaGuerra(sim) then
        local declarada = sim:ejecutar({
            tipo = 'declararGuerra',
            nacion = envio.desde.nacion,
            contra = envio.objetivo.nacion,
        })
        if not declarada then
            envio.motivo = 'La simulación no acepta la declaración de guerra'
            return false
        end
    end
    local gid = sim:ejecutar(envio:comando())
    if gid then
        if envio.modo == 'sacar' then
            -- El ejército nuevo queda elegido: clic en el mapa para moverlo.
            ejercito:poner({ gid })
            ejercito:avisar('Ejército formado: toca el mapa para moverlo')
        end
        envio = nil
        fichaVista = gid
        return gid
    end
    local motivo = envio:motivoPrevio(sim)
    if not motivo and envio.modo == 'sacar' then
        motivo = 'La simulación no acepta formar el ejército'
    elseif not motivo and envio.modo == 'recolectar' then
        motivo = 'La simulación no acepta la orden de recolectar'
    elseif not motivo then
        local n = sim:nacion(envio.desde.nacion)
        if #sim:lideresDe(n.id) > 0 then
            motivo = 'No sale: no hay camino por tierra o ningún líder está libre'
        else
            motivo = 'La simulación no acepta el ataque'
        end
    end
    envio.motivo = motivo
    return false
end

--- Lugar de un aviso de ataque, para el texto: el sitio o «tus recolectores de …».
local function lugarDeAviso(sim, objetivo)
    if objetivo.tipo == 'sitio' then
        return nombreSitio(sim, sim:sitio(objetivo.id))
    end
    local mina = sim:mina(objetivo.id)
    return 'tus recolectores ' .. (mina and deMina(mina) or 'de una mina')
end

--- Modo jugador (diseno/recoleccion-y-batallas.md, 3.8):
--   - un día antes de que llegue un ataque contra algo tuyo (`avisosAtaque`),
--     un aviso con «Ir» (una vez por grupo);
--   - al empezar una batalla tuya, un pregón con «Defender» y «No defender»
--     (o «Atacar» y «Que se resuelva» si el atacante eres tú); si no se
--     elige en `ESPERA_BATALLA` segundos (o se descarta), no se entra
--     (`noDefender`) y se resuelve sola. Luego se puede entrar a mitad
--     desde la lista de batallas.
function vigilarBatallas()
    if not jugador then
        return
    end
    local sim = mundo.sim
    for _, a in ipairs(sim:avisosAtaque(jugador.jugador)) do
        if not avisadosAtaque[a.grupo] then
            avisadosAtaque[a.grupo] = true
            local n = sim:nacion(a.nacion)
            pregon:avisar(
                'Ataque en camino: llega en ' .. a.dias .. (a.dias == 1 and ' día' or ' días'),
                string.format(
                    'El ejército de %s va hacia %s · poder %s',
                    n and n.nombre or '?',
                    lugarDeAviso(sim, a.objetivo),
                    -- El poder de lo ajeno, solo con informe (interfaz/inteligencia.lua).
                    (Inteligencia.textoPoder(sim, jugador.jugador, a.grupo, a.nacion, a.poder))
                ),
                'Ir',
                string.format('irxy:%d,%d', math.floor(a.x), math.floor(a.y))
            )
        end
    end
    -- Munición baja (menos de `umbralAbasto` días) de un ejército tuyo en
    -- batalla: una tarjeta con «Abastecer», una vez por grupo y munición.
    local bajas = {}
    for _, a in ipairs(sim:avisosMunicion(jugador.jugador)) do
        local sin = a.dias <= 0
        local clave = a.grupo .. ':' .. a.falta .. (sin and ':sin' or '')
        bajas[clave] = true
        if not avisadosMunicion[clave] then
            avisadosMunicion[clave] = true
            local tropa = ({ balas = 'Soldados', misiles = 'Lanzacohetes' })[a.falta]
            pregon:avisar(
                sin and string.format('%s sin %s', tropa, a.falta) or ('Munición baja: ' .. a.falta),
                sin and 'No disparan' or string.format('Quedan %s días de batalla', Fabrica.decimal(a.dias)),
                'Abastecer',
                'abastecer:' .. a.grupo
            )
        end
    end
    for clave in pairs(avisadosMunicion) do
        if not bajas[clave] then
            avisadosMunicion[clave] = nil
        end
    end
    local vivas = {}
    for _, b in ipairs(sim:batallasEnCurso(jugador.jugador)) do
        vivas[b.id] = true
        if not preguntadas[b.id] and not b.decidido and not b.enEscena then
            local defiende = b.lado == 'defensor'
            local titulo = '¡Tu ejército entra en batalla!'
            if defiende and b.lugar.tipo == 'mina' then
                titulo = '¡Atacan a tus recolectores!'
            elseif defiende then
                titulo = '¡Atacan ' .. b.nombre .. '!'
            end
            local tuyo = defiende and b.defensor.poder or b.atacante.poder
            local suyo = Inteligencia.poderRival(sim, jugador.jugador, b, defiende and 'atacante' or 'defensor')
            local detalle = string.format('Poder %s contra el tuyo %s · %s', suyo, Tema.numero(tuyo), b.nombre)
            local p = pregon:preguntar(titulo, detalle, {
                {
                    texto = defiende and 'Defender' or 'Atacar',
                    tipo = 'principal',
                    accion = 'defender:' .. b.id,
                },
                {
                    texto = defiende and 'No defender' or 'Que se resuelva',
                    tipo = 'secundario',
                    accion = 'sola:' .. b.id,
                },
            }, ESPERA_BATALLA)
            p.batalla = b.id
            preguntadas[b.id] = p
        end
    end
    for _, bid in ipairs(Simulacion.ordenadas(preguntadas)) do
        local p = preguntadas[bid]
        if not vivas[bid] then
            -- Acabó (o ya no peleas en ella): el pregón sobra.
            if not p.usado then
                p.usado = true
                pregon:quitar(p)
            end
        elseif not p.usado and not p.elegido and (p.terminado or p.descartado) then
            -- Sin respuesta: por defecto, no se defiende en 3D.
            p.usado = true
            sim:ejecutar({ tipo = 'noDefender', nacion = jugador.jugador, batalla = bid })
        end
    end
end

--- ¿Se puede mandar un convoy de munición al grupo propio `gid`? Sale de tu
-- ciudad más cercana con lo que le falta hasta `dotacion.atacar` días de
-- batalla (lo que haya en su polvorín). Con `mandar`, lo manda (comando
-- `abastecer`). Devuelve true (o el id del convoy) o false y el texto del motivo.
function abastecerGrupo(gid, mandar)
    local sim = mundo.sim
    local gr = sim.estado.grupos[gid]
    if not (gr and jugador and gr.nacion == jugador.jugador) then
        return false, 'El ejército ya no existe'
    end
    if sim:convoyHacia(gr.nacion, gid) then
        return false, 'Convoy de munición en camino'
    end
    local c = ciudadPropiaCercana(gr.x, gr.y)
    if not c then
        return false, 'Sin ciudad que lo abastezca'
    end
    local quiere = Simulacion.dotacion(gr, Simulacion.produccion.dotacion.atacar)
    local hay = sim:polvorin(c.id) or {}
    local pedido, alguno, falta = {}, false, false
    for _, m in ipairs(Simulacion.MUNICIONES) do
        local necesita = math.max(0, math.floor(quiere[m] - (gr.municion and gr.municion[m] or 0)))
        falta = falta or necesita > 0
        pedido[m] = math.min(necesita, math.floor(hay[m] or 0))
        alguno = alguno or pedido[m] > 0
    end
    if not falta then
        return false, 'Munición completa'
    elseif not alguno then
        return false, 'Polvorín de ' .. c.nombre .. ' vacío'
    end
    if not mandar then
        return true
    end
    local id, motivo = sim:ejecutar({
        tipo = 'abastecer',
        nacion = gr.nacion,
        desde = c.id,
        grupo = gid,
        balas = pedido.balas,
        misiles = pedido.misiles,
    })
    print('ABASTECER', gid, tostring(id), tostring(motivo or ''), pedido.balas, pedido.misiles)
    if id then
        ejercito:avisar('Sale de ' .. c.nombre .. ' un convoy de munición')
        return id
    end
    ejercito:avisar('No sale el convoy (' .. tostring(motivo) .. ')')
    return false, tostring(motivo)
end

--- Acción de un botón de la ficha de un grupo (ver `botonesFicha`).
function pulsarFicha(accion)
    local sim = mundo.sim
    local gr = fichaVista and sim.estado.grupos[fichaVista]
    local texto = tostring(accion)
    local destino = texto:match('^destino:(.+)$')
    local destinoBatalla = tonumber(texto:match('^destinoBatalla:(%d+)$'))
    local entrar = tonumber(texto:match('^entrar:(%d+)$'))
    if accion == 'cerrar' then
        fichaVista, redirigiendo = nil, nil
    elseif not (gr and jugador) then
        return
    elseif entrar then
        entrarEnBatallaSim(entrar)
    elseif accion == 'retirar' then
        sim:ejecutar({ tipo = 'retirar', nacion = jugador.jugador, grupo = gr.id })
    elseif accion == 'abastecer' then
        abastecerGrupo(gr.id, true)
    elseif accion == 'redirigir' then
        redirigiendo = gr.id
    elseif accion == 'cancelarRedirigir' then
        redirigiendo = nil
    elseif destino or destinoBatalla then
        sim:ejecutar({
            tipo = 'redirigir',
            nacion = jugador.jugador,
            grupo = gr.id,
            destino = destinoBatalla or destino,
        })
        redirigiendo = nil
    elseif accion == 'explorar' then
        local x, y = mundo:posicionFicha(gr, sim:fraccionPaso())
        local n = sim:nacion(gr.nacion)
        explorando = Explorar.nuevo(sim, jugador.jugador, {
            id = gr.id,
            x = x or gr.x,
            y = y or gr.y,
            nombre = 'el ejército de ' .. (n and n.nombre or '?'),
        })
    elseif accion == 'atacarRecolectores' then
        local mina = gr.yacimiento and sim:mina(gr.yacimiento)
        local salida = mina and ciudadPropiaCercana(mina.x, mina.y)
        if salida then
            envio = Envio.nuevo(salida, mina, 'los recolectores ' .. deMina(mina))
        end
    end
end

--- Clic sobre la interfaz: devuelve true si lo usó (y no pasa al mapa).
local function pulsarInterfaz(x, y, boton)
    -- El perfil y las opciones son pantallas completas: el clic es suyo.
    if perfil.abierto or opciones.abierta or arsenal.abierto then
        if boton ~= 1 then
            return true
        end
        if arsenal.abierto then
            local pedido = arsenal:pulsar(x, y)
            if pedido == 'cerrar' then
                arsenal:cerrar()
            elseif type(pedido) == 'table' then
                mandarArsenal(pedido.comandos)
            end
        elseif perfil.abierto then
            local pedido = perfil:pulsar(x, y)
            if pedido == 'cerrar' then
                perfil:cerrar()
            elseif pedido == 'opciones' then
                perfil:cerrar()
                opciones:abrir()
            elseif pedido == 'territorio' then
                perfil:cerrar()
                mundo.mostrarTerritorio = not mundo.mostrarTerritorio
            end
        else
            local pedido = opciones:pulsar(x, y)
            if pedido == 'cerrar' then
                opciones:cerrar()
            elseif pedido == 'perfil' then
                opciones:cerrar()
                perfil:abrir()
            elseif pedido == 'guardar' then
                guardarPartida()
            elseif pedido == 'cargar' then
                cargarPartida()
            elseif pedido == 'nueva' then
                opciones:cerrar()
                empezar(love.math.random(1, 99999))
            end
        end
        return true
    end
    -- El envío es modal: mientras está abierto, el clic es suyo.
    if envio then
        local r = boton == 1 and envio:pulsar(x, y)
        if r == 'atacar' then
            mandarAtaque()
        elseif r == 'cancelar' then
            envio = nil
        end
        return true
    end
    -- El panel de encargo (crear soldados, munición, taller) también es modal.
    if fabrica then
        local r = boton == 1 and fabrica:pulsar(x, y)
        if type(r) == 'table' then
            mandarComandos(r.comandos)
        elseif r == 'cancelar' then
            fabrica = nil
        end
        return true
    end
    -- La ventana de la población también es modal (solo se lee y se cierra).
    if ventanaPoblacion then
        if boton == 1 and ventanaPoblacion:pulsar(x, y) == 'cerrar' then
            ventanaPoblacion = nil
        end
        return true
    end
    -- El panel de explorar también es modal.
    if explorando then
        local r = boton == 1 and explorando:pulsar(x, y)
        if r == 'enviar' then
            mandarExploradores()
        elseif r == 'cancelar' then
            explorando = nil
        end
        return true
    end
    local pregonado = pregon:pulsar(x, y, boton)
    if pregonado then
        local texto = tostring(pregonado)
        local defender = tonumber(texto:match('^defender:(%d+)$'))
        local sola = tonumber(texto:match('^sola:(%d+)$'))
        local irA = texto:match('^ir:(.+)$')
        local abastecer = tonumber(texto:match('^abastecer:(%d+)$'))
        local px, py = texto:match('^irxy:(-?%d+),(-?%d+)$')
        local sitio = irA and mundo.sim:instalacion(irA)
        if abastecer then
            abastecerGrupo(abastecer, true)
            fichaVista, redirigiendo = mundo.sim.estado.grupos[abastecer] and abastecer or nil, nil
        elseif sitio then
            siguiendo = nil
            camara.x, camara.y = Iso.vista(sitio.x, sitio.y, mundo.terreno:altura(sitio.x, sitio.y))
            seleccionada, instalacionVista, minaVista = nil, sitio.id, nil
        elseif px then
            siguiendo = nil
            px, py = tonumber(px), tonumber(py)
            camara.x, camara.y = Iso.vista(px, py, mundo.terreno:altura(px, py))
        elseif irA then
            return true
        elseif defender then
            if preguntadas[defender] then
                preguntadas[defender].usado = true
            end
            if not entrarEnBatallaSim(defender) then
                mundo.sim:ejecutar({ tipo = 'noDefender', nacion = jugador.jugador, batalla = defender })
            end
        elseif sola then
            if preguntadas[sola] then
                preguntadas[sola].usado = true
            end
            mundo.sim:ejecutar({ tipo = 'noDefender', nacion = jugador.jugador, batalla = sola })
        elseif pregonado ~= 'nada' then
            love.keypressed(pregonado)
        end
        return true
    end
    if boton ~= 1 then
        return false
    end
    if barraSuperior:encima(x, y) then
        local tecla = barraSuperior:pulsar(x, y)
        if tecla then
            love.keypressed(tecla)
        end
        return true
    end
    local capa = casillasCapas:pulsar(x, y)
    if capa == 'territorio' then
        -- Lo mismo que la tecla T y el botón Territorio.
        mundo.mostrarTerritorio = not mundo.mostrarTerritorio
        return true
    elseif capa then
        mundo.capas[capa] = not mundo.capas[capa]
        return true
    end
    local teclaBarra = columna:pulsar(x, y) or navegacion:pulsar(x, y)
    if teclaBarra then
        love.keypressed(teclaBarra)
        return true
    end
    if columna:encima(x, y) or navegacion:encima(x, y) then
        return true
    end
    local deLista = listaBatallas:pulsar(x, y)
    if deLista then
        if deLista.tipo == 'entrar' then
            entrarEnBatallaSim(deLista.batalla)
        elseif deLista.tipo == 'ir' then
            siguiendo = nil
            camara.x, camara.y = Iso.vista(deLista.x, deLista.y, mundo.terreno:altura(deLista.x, deLista.y))
        elseif deLista.tipo == 'cerrar' then
            listaBatallas.abierta = false
        end
        return true
    end
    if ejercito:pulsarPanel(mundo, jugador, x, y) then
        return true
    end
    local deTropas = jugador and panelTropas:pulsar(x, y)
    if deTropas then
        if deTropas ~= 'nada' then
            accionTropas(deTropas)
        end
        return true
    end
    -- Las noticias se dibujan encima del radial: su clic va antes.
    if noticias:pulsar(x, y) then
        return true
    end
    -- Menú radial: sus botones y su ficha; fuera de ellos se cierra y el
    -- clic sigue (puede abrir otro).
    local deRadial = radial:pulsar(x, y)
    if deRadial then
        if deRadial ~= 'nada' then
            accionRadial(deRadial)
        end
        return true
    elseif radial:abierto() then
        radial:cerrar()
    end
    local deFicha = panelFicha:pulsar(x, y)
    if deFicha then
        pulsarFicha(deFicha)
        return true
    end
    local accion = pendon:pulsar(x, y)
    if accion then
        if accion.tipo == 'cerrar' then
            cerrarPendon()
        elseif accion.tipo == 'nacion' then
            irANacion(accion.id)
        end
        -- El pendón acaba de armar un grupo desde la pestaña Ejército
        -- (dueño 2026-09-29): lo dejamos seleccionado para que el jugador
        -- lo mueva con click derecho en el mapa.
        if pendon.grupoArmadoReciente then
            ejercito:poner({ pendon.grupoArmadoReciente })
            fichaVista, redirigiendo = pendon.grupoArmadoReciente, nil
            pendon.grupoArmadoReciente = nil
        end
        return true
    end
    local lugar = placa:pulsar(x, y)
    if lugar then
        if jugador and not PANEL_CIUDAD then
            -- Sin panel de ciudad: la placa abre el menú radial de la ciudad.
            radial:abrir({ tipo = 'sitio', id = lugar.region })
            cerradaAqui = lugar
        else
            seleccionada, instalacionVista, minaVista, cerradaAqui = lugar, nil, nil, nil
        end
        return true
    end
    return false
end

--- Combate de prueba cuando no hay ninguna ciudad de otra nación a la vista (la
-- cámara arranca pegada a una capital): la ciudad más cercana a (x, y) contra
-- la capital extranjera más cercana a ella, en toda la simulación. Nil si aún
-- no hay dos naciones.
function combateProvocadoLejano(x, y)
    local sim = mundo.sim
    local ciudad = mundo:ciudadMasCercana(x, y)
    local desde = ciudad and sim:ciudad(ciudad.region)
    if not desde then
        return nil
    end
    local mejor, mejorD
    for _, id in ipairs(Simulacion.ordenadas(sim.estado.ciudades)) do
        local datos = sim.estado.ciudades[id]
        if datos.nacion ~= desde.nacion then
            local dx, dy = datos.x - desde.x, datos.y - desde.y
            local d = dx * dx + dy * dy
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

--- `--batalla-vivo`: en cuanto se ven ciudades, entra en el combate real más
-- cercano o, si no hay ninguno, en uno de prueba (ver Escena.combateProvocado).
function buscarBatallaEnVivo(dt)
    local b = batallaVivo
    b.espera = b.espera + dt
    if b.espera < 0.5 then
        return
    end
    local cx, cy = Iso.mundo(camara.x, camara.y)
    local combate = Escena.buscarCombate(mundo, cx, cy)
        or Escena.combateProvocado(mundo, cx, cy)
        or combateProvocadoLejano(cx, cy)
    if combate then
        batallaVivo = nil
        if b.x and b.y then
            combate.cx = b.x
            combate.cy = b.y
            combate.sitio = nil
            combate.grupo = nil
            combate.provocado = true
        end
        entrarEnBatalla(combate)
    end
end

--- Abre el menú radial sobre `objetivo` (en el punto x, y del mundo): cierra
-- los paneles de sitio y, si el objetivo queda muy al borde, la cámara se
-- desliza hasta él para que el arco quepa en pantalla.
function abrirRadial(objetivo, x, y)
    seleccionada, instalacionVista, minaVista = nil, nil, nil
    radial:abrir(objetivo)
    local ciudad = objetivo.tipo == 'sitio' and mundo:ciudadFisica(objetivo.id)
    if ciudad then
        cerradaAqui = ciudad
    end
    local w, h = love.graphics.getDimensions()
    local vx, vy = Iso.vista(x, y, math.max(0, mundo.terreno:altura(x, y)))
    local sx, sy = (vx - camara.x) * camara.zoom + w / 2, (vy - camara.y) * camara.zoom + h / 2
    local margenX, margenY = Tema.px(300), Tema.px(260)
    -- El arco de botones baja hasta ~310 px de diseño bajo el objetivo: con
    -- la barra de navegación debajo, el objetivo no puede quedar más abajo.
    local bajoMaximo = h - Navegacion.alto() - Tema.px(310)
    if sx < margenX or sx > w - margenX or sy < BarraSuperior.alto() + Tema.px(80) or sy > h - margenY then
        focoCamara = { x = vx, y = vy }
    end
    if sy > bajoMaximo then
        -- La cámara baja lo justo para que el objetivo suba hasta `bajoMaximo`.
        local destinoY = (focoCamara and h / 2 or sy)
        local cy = focoCamara and vy or camara.y
        if destinoY > bajoMaximo then
            cy = cy + (destinoY - bajoMaximo) / camara.zoom
        end
        focoCamara = { x = focoCamara and focoCamara.x or camara.x, y = cy }
    end
end

function love.mousepressed(x, y, boton)
    if inicio.atenderDialogoSalir('pulsar', x, y, boton) then
        return
    end
    if inicio.login then
        inicio.atenderLogin(inicio.login:pulsar(x, y, boton))
        return
    end
    if almacenVista then
        almacenVista:pulsar(x, y, boton)
        return
    end
    if batalla then
        batalla:pulsar(x, y, boton)
        return
    end
    if pulsarInterfaz(x, y, boton) then
        return
    end
    -- Plantando una bandera: el clic izquierdo planta y el derecho cancela.
    if plantando and boton == 1 then
        if not plantando.fijo then
            plantando:poner(mundo.sim, sueloEnPantalla(x, y))
        end
        if plantando:confirmar(mundo.sim) then
            plantando = nil
        end
        return
    elseif plantando and boton == 2 then
        plantando = nil
        return
    end
    local w, h = love.graphics.getDimensions()
    local vx = camara.x + (x - w / 2) / camara.zoom
    local vy = camara.y + (y - h / 2) / camara.zoom
    local suma = love.keyboard.isDown('lshift', 'rshift', 'lctrl', 'rctrl')
    -- Botón derecho o central: arrastra la cámara; si se suelta sin haberla
    -- movido, manda la selección a ese punto (ver `love.mousereleased`).
    if boton == 2 or boton == 3 then
        arrastre = { x = x, y = y, x0 = x, y0 = y, boton = boton }
        return
    elseif boton ~= 1 then
        return
    end
    -- Vista lejana: el clic izquierdo solo arrastra la cámara.
    if vistaLejana then
        arrastre = { x = x, y = y, x0 = x, y0 = y, boton = boton }
        return
    end
    -- Botón izquierdo: elegir fichas propias (clic, doble clic, Mayús+clic).
    local gesto = ejercito:pulsar(mundo, camara, jugador, x, y, suma)
    if gesto == 'ficha' then
        fichaVista = ejercito:cuantos() == 1 and ejercito:primero() or nil
        redirigiendo = nil
        return
    end
    local gid = mundo:fichaEn(vx, vy)
    if gid then
        -- Ficha de un grupo ajeno: muestra su ficha (sin elegirla).
        fichaVista, redirigiendo = gid, nil
        return
    end
    if gesto == 'orden' then
        -- Con una selección, el clic se resuelve al soltar: mandarla allí o,
        -- si se arrastró, elegir lo que quede dentro del cuadro.
        return
    end
    -- Sin selección, jugando: el clic abre el menú radial de lo que haya
    -- debajo (sitio o mina); arrastrar dibuja el cuadro de selección.
    if jugador and not suma then
        fichaVista, redirigiendo = nil, nil
        local destino = Ejercito.destinoEn(mundo, vx, vy)
        if destino.tipo == 'mina' then
            abrirRadial({ tipo = 'mina', id = destino.id }, destino.x, destino.y)
        elseif destino.tipo == 'sitio' then
            abrirRadial({ tipo = 'sitio', id = destino.sitio.id }, destino.x, destino.y)
        end
        return
    end
    -- Observador: el clic abre el pendón de lo que haya debajo (mina,
    -- instalación o ciudad).
    if not suma then
        seleccionada, instalacionVista, minaVista = nil, nil, nil
    end
    fichaVista, redirigiendo = nil, nil
    local mina = mundo:minaEn(vx, vy)
    if mina then
        minaVista, cerradaAqui = mina, nil
    end
    for _, id in ipairs(Simulacion.ordenadas(mundo.sim.estado.instalaciones)) do
        local i = mundo.sim.estado.instalaciones[id]
        local ix, iy = Iso.vista(i.x, i.y, mundo.terreno:altura(i.x, i.y))
        if (vx - ix) ^ 2 + ((vy - iy) * 2) ^ 2 < 170 * 170 then
            instalacionVista = id
        end
    end
    for _, ciudad in pairs(mundo.ciudadesVistas) do
        local cx, cy = Iso.vista(ciudad.x, ciudad.y, ciudad.altura)
        local dx, dy = (vx - cx), (vy - cy) * 2
        if dx * dx + dy * dy < (ciudad.radio * 1.3) ^ 2 then
            seleccionada = ciudad
        end
    end
    if seleccionada or instalacionVista then
        cerradaAqui = nil
    end
end

function love.mousemoved(x, y, dx, dy)
    if inicio.login or inicio.dialogo.abierto then
        return
    end
    if almacenVista then
        almacenVista:mover(x, y, dx, dy)
        return
    end
    if batalla then
        batalla:mover(x, y, dx, dy)
        return
    end
    if opciones.abierta or perfil.abierto or arsenal.abierto then
        opciones:mover(x)
        arsenal:mover(x)
        return
    end
    ejercito:mover(x, y)
    if arrastre then
        camara.x = camara.x - (x - arrastre.x) / camara.zoom
        camara.y = camara.y - (y - arrastre.y) / camara.zoom
        -- Velocidad del arrastre (para la inercia al soltar), suavizada.
        local ahora = love.timer.getTime()
        local paso = math.max(1 / 240, ahora - (arrastre.t or ahora - 1 / 60))
        local vx, vy = -(x - arrastre.x) / camara.zoom / paso, -(y - arrastre.y) / camara.zoom / paso
        arrastre.vx = (arrastre.vx or 0) * 0.5 + vx * 0.5
        arrastre.vy = (arrastre.vy or 0) * 0.5 + vy * 0.5
        arrastre.t = ahora
        arrastre.x, arrastre.y = x, y
    end
end

--- Suelta del botón. El izquierdo termina el cuadro de selección o, si fue un
-- clic sin arrastre con una selección, la manda a ese punto; el derecho, si no
-- movió la cámara, también.
function love.mousereleased(x, y, boton)
    if inicio.atenderDialogoSalir('soltar', x, y, boton) then
        return
    end
    if inicio.login then
        inicio.atenderLogin(inicio.login:soltar(x, y, boton))
        return
    end
    local suelto = arrastre
    arrastre = nil
    -- Inercia: si se soltó en movimiento (el último arrastre hace menos de
    -- 0,08 s), la cámara sigue un poco y frena sola.
    if suelto and suelto.t and love.timer.getTime() - suelto.t < 0.08 then
        camara.vx, camara.vy = suelto.vx or 0, suelto.vy or 0
    end
    opciones:soltar()
    arsenal:soltar()
    if almacenVista then
        almacenVista:soltar(x, y, boton)
        return
    end
    if batalla then
        batalla:soltar(x, y, boton)
        return
    end
    if boton == 1 then
        local gesto = ejercito:soltar(mundo, camara, jugador, x, y)
        if gesto == 'caja' then
            radial:cerrar()
        end
        if gesto == 'caja' or gesto == 'orden' then
            fichaVista = ejercito:cuantos() == 1 and ejercito:primero() or nil
            redirigiendo = nil
        end
    elseif suelto and boton == 2 and suelto.boton == 2 and jugador and ejercito:cuantos() > 0 then
        -- Clic derecho sin arrastrar: quita la selección (el dueño, 2026-09-30).
        if
            math.abs(x - suelto.x0) <= Ejercito.umbralArrastre
            and math.abs(y - suelto.y0) <= Ejercito.umbralArrastre
        then
            ejercito:limpiar()
            fichaVista, redirigiendo = nil, nil
        end
    end
end

--- Libera la captura del ratón de batalla al cambiar de ventana.
function love.focus(enfocada)
    if almacenVista then
        almacenVista:foco(enfocada)
    end
    if batalla then
        batalla:foco(enfocada)
    end
end

--- Texto escrito: los campos de la pantalla de inicio y el buscador del arsenal.
function love.textinput(texto)
    if inicio.dialogo.abierto then
        return
    end
    if inicio.login then
        inicio.login:texto(texto)
        return
    end
    if almacenVista then
        almacenVista:texto(texto)
        return
    end
    arsenal:texto(texto)
end

function love.keypressed(tecla)
    if inicio.atenderDialogoSalir('tecla', tecla) then
        return
    end
    if inicio.login then
        inicio.atenderLogin(inicio.login:tecla(tecla))
        return
    end
    if almacenVista then
        -- En el almacén, las teclas son suyas; Esc vuelve al mapa.
        if almacenVista:tecla(tecla) == 'salir' then
            almacenVista:cerrar()
            almacenVista = nil
            autoguardar()
        end
        return
    end
    if batalla then
        -- En la batalla, las teclas son suyas; Esc vuelve al mapa tal como estaba.
        if batalla:tecla(tecla) == 'salir' then
            salirDeBatalla()
        end
        return
    end
    -- El perfil y las opciones son pantallas completas: Esc vuelve atrás y el
    -- resto de teclas no llega al mapa.
    if arsenal.abierto then
        arsenal:tecla(tecla)
        return
    end
    if perfil.abierto or opciones.abierta then
        if tecla == 'escape' then
            if opciones.abierta then
                opciones:atras()
            else
                perfil:cerrar()
            end
        end
        return
    end
    if tecla == 'perfil' then
        perfil:abrir()
        return
    elseif tecla == 'opciones' then
        opciones:abrir()
        return
    elseif (tecla == 'arsenal' or tecla == 'u') and jugador then
        arsenal:abrir()
        return
    elseif tecla == 'almacen' and jugador then
        -- El almacén por dentro (almacen/escena.lua): un sitio aparte.
        local escena, motivo = require('almacen.escena').nueva(Almacen.getDelJugador())
        if escena then
            radial:cerrar()
            almacenVista = escena
        else
            ejercito:avisar('Almacén: ' .. tostring(motivo))
            -- También a la vista sin un grupo elegido (el aviso del panel del
            -- ejército solo sale con el panel abierto).
            pregon:avisar('Almacén', (tostring(motivo):gsub('^%l', string.upper)), 'Cerrar', 'nada', 6)
        end
        return
    end
    local cerrable = envio
        or fabrica
        or ventanaPoblacion
        or explorando
        or radial:abierto()
        or noticias.abierta
        or fichaVista
    if tecla == 'escape' and (cerrable or plantando or listaBatallas.abierta or ejercito:cuantos() > 0) then
        -- Esc cancela primero la bandera, luego cierra el envío (o el panel
        -- de explorar), el menú radial, las noticias, la lista de batallas,
        -- el panel de la ficha y, al final, deselecciona el grupo que el
        -- jugador eligió para mover (dueño 2026-09-29).
        if plantando then
            plantando = nil
        elseif envio then
            envio = nil
        elseif fabrica then
            fabrica = nil
        elseif ventanaPoblacion then
            ventanaPoblacion = nil
        elseif explorando then
            explorando = nil
        elseif radial:abierto() then
            radial:cerrar()
        elseif noticias.abierta then
            noticias.abierta = false
        elseif listaBatallas.abierta then
            listaBatallas.abierta = false
        elseif fichaVista then
            fichaVista, redirigiendo = nil, nil
        else
            ejercito:limpiar()
        end
        return
    end
    if tecla == 'b' and jugador then
        listaBatallas.abierta = not listaBatallas.abierta
    elseif tecla == 'b' then
        -- Observador: mirar en 3D el combate más cercano (no cambia la simulación).
        local cx, cy = Iso.mundo(camara.x, camara.y)
        entrarEnBatalla(Escena.buscarCombate(mundo, cx, cy))
    elseif tecla == 'p' then
        if not vistaLejana then
            alternarPlantar()
        end
    elseif tecla == 'n' then
        empezar(love.math.random(1, 99999))
    elseif tecla == 'v' then
        seguirEjercito()
    elseif tecla == 'f1' then
        -- Centra la cámara en la primera tropa propia visible (modo RTS,
        -- 2026-09-29). Equivalente al 'go to army' de Warcraft.
        for _, gid in ipairs(Simulacion.ordenadas(mundo.sim.estado.grupos)) do
            local g = mundo.sim.estado.grupos[gid]
            if jugador and g.nacion == jugador.jugador and g.soldados + (g.lanzacohetes or 0) > 0 then
                local vx, vy = Iso.vista(g.x, g.y, mundo.terreno:altura(g.x, g.y))
                camara.x = vx
                camara.y = vy
                break
            end
        end
    elseif (tecla == 'a' and love.keyboard.isDown('lctrl', 'rctrl')) or tecla == 'todas' then
        -- Ctrl+A o el botón de ejércitos: elegir TODAS las fichas propias.
        if not vistaLejana then
            ejercito:todas(mundo, jugador)
        end
    elseif tecla == 'noticias' then
        noticias:alternar(mundo.sim.estado.noticias)
    elseif tecla == 'f5' then
        guardarPartida()
    elseif tecla == 'f9' then
        cargarPartida()
    elseif tecla == 'g' then
        provocarGuerra()
    elseif tecla == 't' then
        mundo.mostrarTerritorio = not mundo.mostrarTerritorio
    elseif tecla == 'space' then
        pausa = not pausa
    elseif tonumber(tecla) and VELOCIDADES[tonumber(tecla)] then
        mundo.velocidad = VELOCIDADES[tonumber(tecla)]
        pausa = false
    elseif tecla == 'x' then
        -- Ir a donde fue el último ataque.
        local aviso = mundo.avisos and mundo.avisos[1]
        if aviso then
            camara.x, camara.y = Iso.vista(aviso.x, aviso.y, mundo.terreno:altura(aviso.x, aviso.y))
        end
    elseif tecla == 'c' then
        local cx, cy = Iso.mundo(camara.x, camara.y)
        local ciudad = mundo:ciudadMasCercana(cx, cy)
        if ciudad then
            camara.x, camara.y = Iso.vista(ciudad.x, ciudad.y, ciudad.altura)
        end
    elseif tecla == 'f3' then
        capaTecnica = not capaTecnica
    elseif tecla == 'escape' then
        -- Esc cierra el pendón abierto; si no hay ninguno, sale.
        local cx, cy = Iso.mundo(camara.x, camara.y)
        local abierto = seleccionada or instalacionVista or minaVista or ciudadMostrada(mundo:ciudadMasCercana(cx, cy))
        if pendon.rect and abierto then
            cerrarPendon()
        else
            love.event.quit()
        end
    end
end

--- La X de la ventana (o cualquier cierre): en el juego normal, antes se
-- pregunta. Devolver true cancela el cierre.
function love.quit()
    if inicio.saliendo or not inicio.preguntar then
        -- Lo que han aprendido los robots (robots/conocimiento.lua).
        require('robots.conocimiento').guardarTodas()
        -- La partida entera, con lo del almacén (partida/guardado.lua).
        autoguardar()
        return false
    end
    if not inicio.dialogo.abierto then
        inicio.abrirPreguntaSalir()
    end
    return true
end

-- Registro (Andrés): guarda el error con su traza y un resumen del estado, y
-- después lo muestra como siempre (el manejador de LÖVE de antes).
local manejarError = love.errorhandler or love.errhand
function love.errorhandler(mensaje)
    if registro then
        registro:error(mensaje, debug.traceback('', 2))
    end
    return manejarError(mensaje)
end

-- `PERFIL_LUA=<segundos>`: perfil del hilo de Lua en el juego real (depurar/perfil_lua.lua).
if os.getenv('PERFIL_LUA') then
    require('depurar.perfil_lua').empezar(tonumber(os.getenv('PERFIL_LUA')) or 20)
end
