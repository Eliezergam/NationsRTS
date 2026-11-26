-- El almacén por dentro en 3D (diseno/almacen.md): un sitio aparte, sin
-- lugar en el mapa. Se entra con el botón «Almacén» de la barra del mapa y
-- se vuelve con Esc.
--
-- Modelo: assets/almacen/almacen.glb (tools/blender/almacen_interior.py
-- --glb), en metros y con y arriba. Luz como el ejemplo AlphaBlending de
-- 3DreamEngine (lib/3DreamEngine, examples/AlphaBlending): cada foco es una
-- luz puntual con sombra estática y suave (se calcula una vez), un sol entra
-- por los lucernarios con su sombra, y el cielo HDR, bajo, da la luz
-- ambiente. El motor usa las 16 luces más cercanas a la cámara.
--
-- Cámara: el control de vuelo de la batalla (batalla/controlador_camara.lua):
-- W A S D, Espacio sube, Ctrl baja, Shift x3, botón derecho para mirar,
-- rueda para avanzar.
--
-- Lo que se ve sale del almacén del jugador (almacen/almacen.lua): tantos
-- contenedores como misiles y el contador encima del portón del polvorín.
--
-- Sonido: un rumor industrial grave en bucle mientras se está dentro
-- (assets/sonidos/almacen/ambiente.ogg, CC0; ver LICENCIA.txt).
--
-- 3Dream es un motor compartido con la batalla: lo que se cambia al entrar
-- (cielo, niebla, oclusión, campo de visión) se devuelve al salir.

require('almacen.almacen')
local dream = require('lib.3DreamEngine')
local Escalado = require('batalla.dream.escalado')
local Controlador = require('batalla.controlador_camara')
local MenuFabrica = require('almacen.menu_fabrica')
local BibliotecaPbr = require('batalla.dream.biblioteca_pbr')
local SalaControl = require('almacen.sala')
local Fabrica = require('almacen.fabrica')
require('almacen.objetos.objetos')
require('almacen.robots.robot')
local MundoRobot = require('almacen.robots.mundo')
local Blancos = require('almacen.blancos')
local VistaSensores = require('almacen.robots.vista_sensores')

local EscenaAlmacen = {}
EscenaAlmacen.__index = EscenaAlmacen

local MODELO = 'assets/almacen/almacen'
local LUCES = 'assets/almacen/luces.lua'
local CIELO = 'assets/almacen/cielo.hdr'
local AMBIENTE = 'assets/sonidos/almacen/ambiente.ogg'

-- Luz que llega al suelo bajo cada foco (la de la lámpara del ejemplo a
-- su distancia): el brillo de cada luz sale de su altura, porque la luz
-- puntual del motor cae como 1 / (d + 1)².
EscenaAlmacen.luzSuelo = 4.5
EscenaAlmacen.luzAnexo = 0.5 -- las campanas del anexo, sin sombra
EscenaAlmacen.cieloAmbiente = 0.25
EscenaAlmacen.conoFuera = 65 -- grados del eje al borde de la luz de las lámparas
EscenaAlmacen.conoDentro = 40 -- hasta aquí, luz llena
EscenaAlmacen.brilloSol = 6
-- Luz rebotada (el motor no la calcula): un cubo de luz ambiente para todo
-- el modelo. Lo que mira abajo (techos) recibe la del suelo; lo que mira
-- arriba, la del techo; los lados, la de las paredes.
EscenaAlmacen.reboteAbajo = 0.32
EscenaAlmacen.reboteLados = 0.2
EscenaAlmacen.reboteArriba = 0.1
-- Rapidez de crucero de la cámara (m/s) y su campo de visión (grados).
EscenaAlmacen.rapidez = 6
EscenaAlmacen.fov = 65
-- Volumen del rumor de la nave (0..1; el general de Ajustes va encima).
EscenaAlmacen.volumenAmbiente = 0.6
-- Dónde empieza el robot (x, y del almacén en metros y rumbo): en la nave,
-- junto a los portones del patio y del anexo. Trabaja solo
-- (almacen/robots/especializaciones/almacenaje.lua).
EscenaAlmacen.robotInicio = { 27.0, 0.5, 0 }
-- El panel de sensores y el mapa muestran el robot con el que se trabaja
-- (el dueño, 18-nov: ahora el soldado): 'soldado' o 'pequeno'.
EscenaAlmacen.robotDelPanel = 'soldado'
EscenaAlmacen.soldadoInicio = { -40.0, 23.6, 0 } -- el soldado, en la reserva detrás de la calle principal
EscenaAlmacen.luzFogonazo = 6 -- brillo de la luz del fogonazo
EscenaAlmacen.pesadoInicio = { -60.5, 0.0, 0 } -- el robot grande, en la fábrica de misiles mirando al portón
-- Anexo de suministros: una fila de cinco racks del robot por cosa, bajo sus
-- carteles (tools/blender/almacen_interior.py, FILAS_ANEXO): nombre, y de la
-- fila y rumbo de los racks (el robot se pone del lado contrario).
EscenaAlmacen.filas = {
    { 'dinero', -2.4, math.pi / 2 },
    { 'municion', -8.6, -math.pi / 2 },
    { 'comida', -9.4, math.pi / 2 },
    { 'metalPetroleo', -14.45, -math.pi / 2 }, -- contra el muro sur: METAL 1-3 y PETRÓLEO 1-2
}
EscenaAlmacen.filaX = { 36.0, 41.6, 47.2, 52.8, 58.4 }
-- Patio de descarga: las mesas donde llega todo, en cuadrícula (x, y, rumbo:
-- el robot se acerca por el oeste).
-- Depósito del misil (x, y, rumbo: el frente mira al sur, al pasillo).
EscenaAlmacen.deposito = { -60.2, 13.9, math.pi / 2 }
EscenaAlmacen.descarga = {}
for _, y in ipairs({ 3.0, 8.0, 13.0, 18.0 }) do
    for _, x in ipairs({ 40.0, 46.0, 52.0, 58.0 }) do
        EscenaAlmacen.descarga[#EscenaAlmacen.descarga + 1] = { x, y, 0 }
    end
end
EscenaAlmacen.repetirEncargos = true -- (ya no se usa: el robot trabaja solo)
-- Cámara siguiendo al robot al entrar (tecla C la pone y la quita).
EscenaAlmacen.seguirAlEntrar = false
-- `--fabricar <n>` (main.lua): al entrar ya hay un pedido de n misiles (los
-- que alcancen y quepan; como pedirlos en la mesa con E).
EscenaAlmacen.fabricarAlEntrar = nil

-- Dentro de la nave (ejes de 3Dream: x, y arriba, z = -y de Blender).
local LIMITES = { -74.5, 63.5, 0.4, 11.0, -31.5, 41.5 } -- con el anexo, el patio, la calle principal y el muelle (z = -y)
-- Al entrar: en el pasillo central de los racks, mirando al polvorín.
local INICIO = { x = -14, y = 1.8, z = 0, rumbo = 0, inclinacion = -0.12 }

local modelo -- { objeto }, una vez
-- Huecos del polvorín, sitio de la mesa de encajado y de la pila de cajas
-- vacías (tools/blender/almacen_interior.py --glb).
local POLVORIN = 'assets/almacen/polvorin.lua'
local cielo
local ambiente -- la fuente del sonido, una vez

local function cargarModelo()
    if modelo then
        return modelo
    end
    if not dream.materialLibrary.baseHormigon then
        BibliotecaPbr.cargar(dream, 'assets/base/materiales')
    end
    if not dream.materialLibrary.unidadCamion4 then
        BibliotecaPbr.cargar(dream, 'assets/modelos3d/materiales')
    end
    -- Los robots con sus texturas reales (tools/texturas_robots.py): chapa,
    -- acero y goma con su rugosidad y su relieve, no colores lisos.
    if not dream.materialLibrary.robotBlanco then
        BibliotecaPbr.cargar(dream, 'assets/almacen/materiales_robot')
    end
    local objeto = dream:loadObject(MODELO, { decodeBlenderNames = false })
    -- Por si alguna malla llega sin UV (el motor las necesita para las
    -- tangentes): UV de su posición, como la batalla.
    for _, pieza in pairs(objeto.objects) do
        for _, malla in pairs(pieza.meshes or {}) do
            if not malla.texCoords then
                local cantidad = malla.vertices:getSize()
                local uvs = dream:newBuffer('vec2', 'float', cantidad)
                for k = 1, cantidad do
                    local v = malla.vertices:get(k)
                    local uv = uvs.buffer[k - 1]
                    uv.x = v.x + v.z * 0.37
                    uv.y = v.y + v.z * 0.23
                end
                malla.texCoords = uvs
            end
        end
    end
    -- Caras del cubo: +x, -x, +y (arriba), -y (abajo), +z, -z. La normal
    -- que mira abajo toma la cara -y.
    local caras = {}
    for k = 1, 6 do
        local v = (k == 3) and EscenaAlmacen.reboteArriba or ((k == 4) and EscenaAlmacen.reboteAbajo or EscenaAlmacen.reboteLados)
        local datos = love.image.newImageData(4, 4)
        datos:mapPixel(function()
            return v * 1.05, v, v * 0.9, 1
        end)
        caras[k] = datos
    end
    local rebote = dream:newReflection(love.graphics.newCubeImage(caras, { mipmaps = true }))
    for _, pieza in pairs(objeto.objects) do
        pieza.reflection = rebote
    end
    modelo = { objeto = objeto }
    return modelo
end

--- Luces de los focos y el sol, con sus sombras como en el ejemplo.
local function crearLuces(objeto)
    local luces = {}
    for _, l in ipairs(love.filesystem.load(LUCES)()) do
        local x, y, z = l[1], l[2], l[3]
        local brillo = EscenaAlmacen.luzSuelo * (y + 1) ^ 2
        -- Las del anexo (x > 30, campanas bajas) y las de la calle principal
        -- (y > 15.5 del almacén: z < -15.5 aquí) van sin sombra: con la
        -- sombra estática se quedaban a oscuras.
        local anexo = x > 30 or z < -15.5
        if anexo then
            brillo = EscenaAlmacen.luzSuelo * 70 * EscenaAlmacen.luzAnexo
        end
        local luz = dream:newLight('point', dream.vec3(x, y, z), dream.vec3(l[5], l[6], l[7]), brillo)
        -- Campana industrial: la luz sale hacia abajo en un cono (unos 120°
        -- llenos y se apaga hacia los 130°), no en todas direcciones; deja
        -- un círculo de luz en el suelo y penumbra entre lámparas.
        luz:setSpot(0, -1, 0, EscenaAlmacen.conoFuera, EscenaAlmacen.conoDentro)
        if not anexo then
            local sombra = luz:addNewShadow()
            sombra:setStatic(true)
            sombra:setSmooth(true)
        end
        luces[#luces + 1] = luz
    end
    -- Sol de media tarde que entra por los lucernarios: ellos no le hacen sombra.
    local sol = dream:newLight('sun')
    sol:setDirection(-0.45, 0.8, 0.35)
    sol:setColor(1.0, 0.92, 0.8)
    sol:setBrightness(EscenaAlmacen.brilloSol)
    -- Dinámica y centrada en la cámara (17-nov): con la estática los robots y
    -- las cajas no hacían sombra al sol en el patio.
    local sombraSol = sol:addNewShadow()
    sombraSol:setStatic(false)
    sombraSol:setResolution(2048)
    sombraSol:setCascadeDistance(30)
    local fuera = {}
    local lucernarios = objeto.objects.lucernarios
    for _, malla in pairs(lucernarios and lucernarios.meshes or {}) do
        fuera[malla] = true
    end
    sol.blacklist = fuera
    luces[#luces + 1] = sol
    return luces
end

--- Abre el almacén. `almacen`: el objeto Almacen que se enseña (el del
-- jugador). Devuelve la escena, o nil y el motivo.
function EscenaAlmacen.nueva(almacen)
    if not almacen then
        return nil, 'sin almacén (solo se mira el mundo)'
    end
    -- La copia pública del código va sin el edificio (lleva cajas de un pack
    -- de pago): se avisa en pantalla y no se entra.
    if not love.filesystem.getInfo(MODELO .. '.glb', 'file') then
        print('Almacén: falta ' .. MODELO .. '.glb')
        return nil, 'falta su modelo 3D'
    end
    local self = setmetatable({}, EscenaAlmacen)
    self.almacen = almacen
    -- Lo de la batalla, para devolverlo al salir.
    self.antes = {
        sky = { dream:getSky() },
        fog = { dream:getFog() },
        ao = { dream:getAO() },
        fov = dream.camera.fov,
        near = dream.camera.near,
        far = dream.camera.far,
        refracciones = dream.canvases:getRefractions(),
    }
    cielo = cielo or love.graphics.newImage(CIELO)
    dream:setSky(cielo, EscenaAlmacen.cieloAmbiente)
    dream:setFog()
    -- Sin refracción: el vidrio plano no la necesita (índice 1, sala.lua) y
    -- con ella la pasada de transparencias no dibujaba las sombras de
    -- contacto (17-nov). Para líquidos o vidrios curvos, activarla aquí.
    dream.canvases:setRefractions(false)
    dream:init()
    dream.camera:setFov(EscenaAlmacen.fov)
    dream.camera:setNear(0.05)
    dream.camera:setFar(200)
    local m = cargarModelo()
    self.objeto = m.objeto
    self.celdas = {}
    for nombre, o in pairs(m.objeto.objects) do
        if nombre:sub(1, 8) == 'estatico' then
            self.celdas[#self.celdas + 1] = o
        end
    end
    -- Las cajas de misil son objetos sueltos con la malla del almacén.
    local polvorin = love.filesystem.load(POLVORIN)()
    self.polvorin = polvorin
    GestorObjetos.setMallaExterna('contenedorMisil', m.objeto.objects.plantillaCaja, m.objeto.objects.plantillaCajaTapa, polvorin.bisagra)
    self.luces = crearLuces(m.objeto)
    self.controlador = Controlador.nuevo()
    self.controlador:orientar(INICIO.rumbo, INICIO.inclinacion)
    self.x, self.y, self.z = INICIO.x, INICIO.y, INICIO.z
    -- ALMACEN_CAMARA='x,y,z,mx,my,mz' (ejes del almacén): empieza ahí mirando
    -- al segundo punto (para capturas de comprobación).
    local c = os.getenv('ALMACEN_CAMARA')
    if c then
        local v = {}
        for n in c:gmatch('[^,]+') do
            v[#v + 1] = tonumber(n)
        end
        if #v == 6 then
            self.x, self.y, self.z = v[1], v[3], -v[2]
            local dx, dy = v[4] - v[1], v[5] - v[2]
            self.controlador:orientar(math.atan2(dy, -dx), math.atan2(v[3] - v[6], math.sqrt(dx * dx + dy * dy)))
        end
    end
    self.mirando = false
    self:prepararPantalla()
    -- Sala de control: sus pantallas con los datos de la partida.
    self.sala = SalaControl.nueva(m.objeto, almacen)
    self:crearObjetos()
    -- La línea de montaje y la grúa de la fábrica (almacen/fabrica.lua).
    self.fabrica = Fabrica.nueva(m.objeto, self.carriles, self.polvorin.abierta)
    -- Cada misil gasta lo que el robot pequeño lleva al depósito del misil.
    self.fabrica:setDeposito(self.deposito, function(coste)
        local a = self.almacen:getRecursos()
        local bien, motivo = self.almacen:setPagar(coste)
        local r = self.almacen:getRecursos()
        print(string.format('PARTIDA paga un misil: dinero %.0f → %.0f, metal %.0f → %.0f, petróleo %.0f → %.0f', a.dinero, r.dinero, a.metal, r.metal, a.petroleo, r.petroleo))
        return bien, motivo
    end)
    -- Junto a la mesa del puesto 1, E abre el menú: pedir misiles o parar.
    self.menuFabrica = MenuFabrica.nuevo(self, self.fabrica.datos.mesaMenu)
    -- El robot de ruedas con brazos (almacen/robots/), con sus encargos.
    GestorRobots.vaciar()
    -- Las siglas de la nación en el pecho de los robots.
    local siglas, color = almacen:getSiglas()
    require('almacen.robots.especializaciones.siglas').nacion = siglas and { texto = siglas, color = color } or nil
    print('SIGLAS ' .. tostring(siglas))
    self.robot = GestorRobots.crear('robotAlmacen', EscenaAlmacen.robotInicio[1], EscenaAlmacen.robotInicio[2], EscenaAlmacen.robotInicio[3])
    -- El pequeño, además de guardar lo del patio, lleva al depósito del
    -- misil lo que le falta a la fábrica (almacenaje.lua).
    self.robot:setAbastecer({
        deposito = self.deposito,
        faltan = function()
            return self.fabrica:getFaltaEnDeposito()
        end,
    })
    self.robotPesado = GestorRobots.crear('robotPesado', EscenaAlmacen.pesadoInicio[1], EscenaAlmacen.pesadoInicio[2], EscenaAlmacen.pesadoInicio[3])
    -- Su trabajo: las cajas de misil de las mesas de encajado al polvorín
    -- (almacen/robots/especializaciones/encajado.lua).
    self.robotPesado:setTrabajoEncajado({
        carriles = self.carriles,
        muelle = self.polvorin.muelle,
        huecoLibre = function(pasillo)
            for k, h in ipairs(self.polvorin.huecos) do
                if not self.cajasPolvorin[k] and (h[2] > 0) == (pasillo > 0) then
                    return k, h
                end
            end
        end,
        guardar = function(k, caja)
            caja.sinRayos = true
            self.cajasPolvorin[k] = caja
            -- Ya es un misil de la partida (se puede llevar a la batalla).
            self.almacen:setAgregarMisiles(1)
            self:mirarMisiles()
        end,
        reponerVacia = function(carril)
            -- PROVISIONAL: hasta que las traigan los camiones al muelle.
            local v = carril.vacias
            carril.cajaVacia = GestorObjetos.crear('contenedorMisil', v[1], v[2], v[3], v[4])
            print('ALMACEN provisional: una caja vacía nueva en ' .. v[1] .. ', ' .. v[2])
        end,
    })
    -- La grúa no baja un misil a una mesa con el robot grande al lado.
    self.fabrica:setRobotCerca(function(x, y)
        local r = self.robotPesado
        return math.abs(r.x - x) < 5 and math.abs(r.y - y) < 6
    end)
    -- Bloques enemigos de práctica (almacen/blancos.lua) y el robot soldado,
    -- entrenando en la reserva: explora y les dispara cuando los ve.
    Blancos.crear()
    self.soldado = GestorRobots.crear('robotSoldado', EscenaAlmacen.soldadoInicio[1], EscenaAlmacen.soldadoInicio[2], EscenaAlmacen.soldadoInicio[3])
    if EscenaAlmacen.grabacion and EscenaAlmacen.grabacion.soldado then
        self.robotSeguido = self.soldado
    end
    self.sensores = VistaSensores.nueva()
    self.siguiendo = EscenaAlmacen.seguirAlEntrar
    if EscenaAlmacen.fabricarAlEntrar then
        local n = math.min(EscenaAlmacen.fabricarAlEntrar, self.menuFabrica:maximo())
        if n > 0 then
            self.fabrica:setPedir(n)
        end
        local r = self.almacen:getRecursos()
        print(string.format('FABRICA pedido al entrar: %d misiles (pedía %d; hay dinero %d, metal %d, petróleo %d)', n, EscenaAlmacen.fabricarAlEntrar, r.dinero or 0, r.metal or 0, r.petroleo or 0))
    end
    self:sonarAmbiente()
    return self
end

--- Muebles y objetos que manejan los robots (almacen/objetos/objetos.lua),
-- con las cajas de misil (para el robot grande).
function EscenaAlmacen:crearObjetos()
    GestorObjetos.vaciar()
    -- Estanterías del anexo, por filas, y mesas del patio de descarga.
    self.filas = {}
    for _, f in ipairs(EscenaAlmacen.filas) do
        local fila = {}
        for k, x in ipairs(EscenaAlmacen.filaX) do
            fila[k] = GestorObjetos.crear('rackRobot', x, f[2], 0, f[3])
        end
        self.filas[f[1]] = fila
    end
    self.mesasDescarga = {}
    for k, d in ipairs(EscenaAlmacen.descarga) do
        self.mesasDescarga[k] = GestorObjetos.crear('mesaRecepcion', d[1], d[2], 0, d[3])
    end
    -- Depósito del misil en la fábrica, contra la pared norte entre dos
    -- puestos (entre la estantería y el banco): el robot deja ahí el dinero y el petróleo de cada misil.
    local dp = EscenaAlmacen.deposito
    self.deposito = GestorObjetos.crear('depositoMisil', dp[1], dp[2], 0, dp[3])
    self:llenarDescarga()
    -- Cajas de misil: en cada carril (pasillo del polvorín), una vacía y
    -- abierta en su mesa de encajado y otra esperando en su sitio de vacías;
    -- en el polvorín, una llena por misil (mirarMisiles).
    self.carriles = {}
    for k, c in ipairs(self.polvorin.carriles) do
        local m, v = c.mesa, c.vacias
        local carril = { pasillo = c.pasillo, mesa = m, vacias = v }
        carril.caja = GestorObjetos.crear('contenedorMisil', m[1], m[2], m[3], m[4])
        carril.caja:setTapa(self.polvorin.abierta)
        carril.cajaVacia = GestorObjetos.crear('contenedorMisil', v[1], v[2], v[3], v[4])
        self.carriles[k] = carril
    end
    self.cajasPolvorin = {}
end

-- Qué llega al patio de descarga por cada recurso de la nación: el tipo de
-- caja (assets/almacen/objetos_datos.lua: `recurso` y `cantidad` por caja).
-- El metal llega en cajas de 10 lingotes y el petróleo en garrafas de 10
-- (2026-11-17: los bidones pesaban demasiado para el robot pequeño).
EscenaAlmacen.suministros = { 'pacaDinero', 'cajaMetal', 'garrafaPetroleo', 'cajaComida', 'cajaObuses' }

-- Lo que lleva cada caja de `tipo` (las garrafas dicen su capacidad).
local function porCaja(datos)
    return datos.capacidad or datos.cantidad
end

--- Lo que tiene la nación ahora llega al patio de descarga por tandas, como
-- camiones: cada caja lleva `cantidad` del recurso (la última, lo que
-- sobre). La primera tanda llena las mesas repartiendo entre los recursos
-- (una de cada, por turnos) y, cuando el robot deja sitio, llega la
-- siguiente (EscenaAlmacen:llegarTanda). Lo que queda por llegar está en
-- `self.porLlegar`.
function EscenaAlmacen:llenarDescarga()
    self.suministros, self.sinSitio, self.porLlegar = {}, {}, {}
    local r = self.almacen and self.almacen.getRecursos and self.almacen:getRecursos()
    if not r then
        return
    end
    -- Para probar con más dinero del que tiene la partida: ALMACEN_DINERO=12000.
    if os.getenv('ALMACEN_DINERO') then
        r.dinero = tonumber(os.getenv('ALMACEN_DINERO')) or r.dinero
    end
    print(string.format('RECURSOS dinero=%.0f metal=%.0f petroleo=%.0f comida=%.0f obuses=%.0f', r.dinero, r.metal, r.petroleo, r.comida, r.obuses))
    local datos = love.filesystem.load('assets/almacen/objetos_datos.lua')()
    self.datosSuministros = datos
    for _, tipo in ipairs(EscenaAlmacen.suministros) do
        self.porLlegar[tipo] = math.floor(r[datos[tipo].recurso] or 0)
    end
    self:llegarTanda()
end

-- Cada cuánto mira si cabe otra tanda y cuántos huecos libres hacen falta
-- (un camión no viene a traer una caja).
EscenaAlmacen.tandaCada = 4
EscenaAlmacen.tandaMinima = 6

--- Pone en los huecos libres de las mesas del patio lo que queda por
-- llegar, por turnos entre los recursos. Devuelve cuántas cajas han llegado.
function EscenaAlmacen:llegarTanda()
    local libres = {}
    for _, mesa in ipairs(self.mesasDescarga) do
        for _, h in ipairs(mesa:getHuecos()) do
            if not h.ocupado then
                libres[#libres + 1] = { mesa, h.numero }
            end
        end
    end
    local llegan, siguiente = 0, 1
    while siguiente <= #libres do
        local alguna = false
        for _, tipo in ipairs(EscenaAlmacen.suministros) do
            local queda = self.porLlegar[tipo] or 0
            local h = libres[siguiente]
            if queda > 0 and h then
                local cantidad = math.min(porCaja(self.datosSuministros[tipo]), queda)
                self.porLlegar[tipo] = queda - cantidad
                siguiente = siguiente + 1
                local hueco = h[1]:getHueco(h[2])
                local o = GestorObjetos.crear(tipo, hueco.x, hueco.y, hueco.z, hueco.rumbo)
                o:setApoyar(h[1], h[2])
                o.cantidad = cantidad
                self.suministros[#self.suministros + 1] = o
                llegan, alguna = llegan + 1, true
            end
        end
        if not alguna then
            break
        end
    end
    if llegan > 0 then
        local partes = {}
        for _, tipo in ipairs(EscenaAlmacen.suministros) do
            partes[#partes + 1] = string.format('%s %d', tipo, self.porLlegar[tipo] or 0)
        end
        print(string.format('DESCARGA llega una tanda: %d cajas (quedan por llegar: %s)', llegan, table.concat(partes, ', ')))
    end
    return llegan
end

-- ¿Queda algo por llegar?
function EscenaAlmacen:getPorLlegar()
    for _, n in pairs(self.porLlegar or {}) do
        if n > 0 then
            return true
        end
    end
    return false
end

--- Empieza el rumor de la nave, en bucle.
function EscenaAlmacen:sonarAmbiente()
    if not ambiente then
        ambiente = love.audio.newSource(AMBIENTE, 'static')
        ambiente:setLooping(true)
    end
    ambiente:setVolume(EscenaAlmacen.volumenAmbiente)
    ambiente:play()
    self.sonido = ambiente
end

-- Contador -----------------------------------------------------------------

--- La pantalla del contador: un lienzo que se pinta cuando cambian los
-- misiles y hace de textura (y de luz) de la malla `pantallaContador`.
function EscenaAlmacen:prepararPantalla()
    self.lienzo = love.graphics.newCanvas(768, 360)
    self.letraTitulo = love.graphics.newFont(64)
    self.letraValor = love.graphics.newFont(132)
    local material = dream:newMaterial('pantallaContadorVivo')
    material:setColor(0.02, 0.02, 0.02, 1)
    material:setRoughness(0.3)
    material:setMetallic(0)
    material:setEmissionTexture(self.lienzo)
    material:setEmissionFactor(2.5, 2.5, 2.5)
    local pantalla = self.objeto.objects.pantallaContador
    for _, malla in pairs(pantalla and pantalla.meshes or {}) do
        malla:setMaterial(material)
    end
    self.misilesVistos = nil
end

function EscenaAlmacen:pintarPantalla(misiles, capacidad)
    local g = love.graphics
    g.push('all')
    g.origin()
    g.setCanvas(self.lienzo)
    g.clear(0, 0, 0, 1)
    local w, h = self.lienzo:getDimensions()
    local color = misiles == 0 and { 1, 0.25, 0.15 } or { 0.25, 1, 0.4 }
    g.setColor(color)
    g.setFont(self.letraTitulo)
    g.printf('MISILES', 0, 40, w, 'center')
    g.setFont(self.letraValor)
    g.printf(misiles .. ' / ' .. capacidad, 0, 150, w, 'center')
    g.pop()
end

--- Si cambiaron los misiles: el contador y las sombras (aparecen o se van
-- contenedores).
function EscenaAlmacen:mirarMisiles()
    -- Los de la partida (los que guarda el robot grande se suman a ella).
    local misiles = self.almacen:getMisiles()
    if misiles == self.misilesVistos then
        return
    end
    self:pintarPantalla(misiles, self.almacen:getCapacidad())
    -- Una caja llena por misil en los huecos del polvorín, en orden. (Las
    -- del polvorín no las miran los rayos de los robots: son muchas y no
    -- cambian; las que se mueven, sí.)
    local cajas = self.cajasPolvorin
    local huecos = self.polvorin.huecos
    local n = 0
    for k = 1, #huecos do
        if cajas[k] then
            n = n + 1
        end
    end
    for k, h in ipairs(huecos) do
        if n >= math.min(misiles, #huecos) then
            break
        end
        if not cajas[k] then
            local caja = GestorObjetos.crear('contenedorMisil', h[1], h[2], h[3], h[4])
            caja:setLleno(true)
            caja.sinRayos = true
            cajas[k] = caja
            n = n + 1
        end
    end
    for k = #huecos, 1, -1 do
        if n <= misiles then
            break
        end
        if cajas[k] then
            GestorObjetos.quitar(cajas[k])
            cajas[k] = nil
            n = n - 1
        end
    end
    if self.misilesVistos then
        for _, luz in ipairs(self.luces) do
            if luz.shadow then
                luz.shadow:refresh()
            end
        end
    end
    self.misilesVistos = misiles
end

-- Bucle ----------------------------------------------------------------------

function EscenaAlmacen:actualizar(dt)
    MundoRobot.cuadro()
    -- Tandas del patio: cuando el robot ha dejado sitio, llega otro camión.
    self.relojTanda = (self.relojTanda or 0) + dt
    if self.relojTanda > EscenaAlmacen.tandaCada and self.mesasDescarga and self:getPorLlegar() then
        self.relojTanda = 0
        local libres = 0
        for _, mesa in ipairs(self.mesasDescarga) do
            for _, h in ipairs(mesa:getHuecos()) do
                libres = libres + (h.ocupado and 0 or 1)
            end
        end
        if libres >= EscenaAlmacen.tandaMinima then
            self:llegarTanda()
        end
    end
    local c = self.controlador
    local dx, dz, dy = c:actualizar(dt, self.x, self.z, self.y, EscenaAlmacen.rapidez)
    local L = LIMITES
    self.x = math.max(L[1], math.min(L[2], self.x + dx))
    self.y = math.max(L[3], math.min(L[4], self.y + dy))
    self.z = math.max(L[5], math.min(L[6], self.z + dz))
    self.sala:actualizar(dt)
    -- Grabando (almacen/video_robot.lua): pasos fijos y, en los viajes, más
    -- rápido.
    local pasos, paso = 1, dt
    if EscenaAlmacen.grabacion then
        pasos, paso = EscenaAlmacen.grabacion:pasos(self)
    end
    for _ = 1, pasos do
        -- ALMACEN_RAPIDO=N: robots y fábrica N veces más deprisa; FABRICA_RAPIDO=N,
        -- solo la línea de montaje (pruebas).
        local rapido = tonumber(os.getenv('ALMACEN_RAPIDO')) or 1
        GestorRobots.actualizar(paso * rapido)
        Blancos.actualizar(paso * rapido)
        self.fabrica:actualizar(paso * rapido * (tonumber(os.getenv('FABRICA_RAPIDO')) or 1))
    end
    if os.getenv('ROBOT_DEPURAR') then
        self.relojDepurar = (self.relojDepurar or 0) + dt
        if self.relojDepurar > 2 then
            self.relojDepurar = 0
            local r = self.robot
            local x, y = r:getPosicion()
            local o = r.datos.exploracion and r.datos.exploracion.objetivo
            print(string.format('DEPURAR agachado=%.2f x=%.2f y=%.2f rumbo=%.2f v=%.2f nav=%s ruta=%d delante=%.2f explorando=%s apartando=%.2f de=%s tarea=%s', r:getAgachado(), x, y, r:getRumbo(), r:getVelocidad(), tostring(r:getNavegando()), #r:getRuta(), r:getDistanciaDelante(0.7), tostring(r.getExplorando and r:getExplorando()), r:getApartando(), tostring(r:getApartandoDe()), r:getTarea()))
        end
    end
    if os.getenv('ALMACEN_SEGUIR_PESADO') then
        -- Pruebas: la cámara sigue al robot grande desde atrás a un lado, a
        -- 5 m de alto, suave.
        local r = self.robotPesado
        local a = (r.getFrente and r:getFrente() or r.rumbo) + 2.5
        local cx, cy, cz = r.x + 7.5 * math.cos(a), r.y + 7.5 * math.sin(a), 5.2
        local k = math.min(1, dt * 1.2)
        local x, y = self.x + (cx - self.x) * k, -self.z + (cy + self.z) * k
        self.x, self.y, self.z = x, self.y + (cz - self.y) * k, -y
        local dx, dy = r.x - x, r.y - y
        self.controlador:orientar(math.atan2(dy, -dx), math.atan2(self.y - 1.8, math.sqrt(dx * dx + dy * dy)))
    elseif EscenaAlmacen.grabacion then
        EscenaAlmacen.grabacion:camara(self)
    elseif self.siguiendo then
        -- La misma cámara que el vídeo: detrás al viajar, de cerca al trabajar.
        self.camaraSeguir = self.camaraSeguir or require('almacen.video_robot').nuevo()
        self.camaraSeguir:camara(self)
    end
    -- ALMACEN_SOLDADO=<s1,s2,...>: la cámara sigue al soldado y hace una foto
    -- (almacen_soldado_<n>.png en la carpeta de guardado) en esos segundos;
    -- tras la última, cierra el juego. Para comprobar su movimiento.
    local fotos = os.getenv('ALMACEN_SOLDADO')
    if fotos then
        self.siguiendo, self.robotSeguido = true, self.soldado
        self.relojFotos = (self.relojFotos or 0) + dt
        self.fotosHechas = self.fotosHechas or 0
        local tiempos = {}
        for n in fotos:gmatch('[^,]+') do
            tiempos[#tiempos + 1] = tonumber(n)
        end
        local siguiente = tiempos[self.fotosHechas + 1]
        if siguiente and self.relojFotos >= siguiente then
            self.fotosHechas = self.fotosHechas + 1
            local n, s = self.fotosHechas, self.soldado
            local p = s.datos.piernasSoldado
            print(string.format('SOLDADO foto %d: x=%.2f y=%.2f rumbo=%.2f v=%.2f giro=%.2f bajar=%.3f cabeceo=%.1f° inclinacion=%.1f°', n, s.x, s.y, s.rumbo, s.velocidad, s.giro, p.bajar, math.deg(p.cabeceo), math.deg(p.inclinacion)))
            love.graphics.captureScreenshot(function(imagen)
                imagen:encode('png', 'almacen_soldado_' .. n .. '.png')
                if n == #tiempos then
                    love.event.quit()
                end
            end)
        end
    end
    -- ALMACEN_FPS=1: apunta los FPS cada 10 s (para medir).
    if os.getenv('ALMACEN_FPS') then
        self.relojFps = (self.relojFps or 0) + dt
        if self.relojFps > 10 then
            self.relojFps = 0
            local s = self.estadisticas or {}
            print(string.format('ALMACEN FPS %d, %d llamadas de dibujo, %d cambios de shader', love.timer.getFPS(), s.drawcalls or 0, s.shaderswitches or 0))
        end
    end
    dream:update()
end

function EscenaAlmacen:prepararCamara()
    local rumbo, inclinacion = self.controlador:angulos()
    local h = math.cos(inclinacion)
    local ojo = dream.vec3(self.x, self.y, self.z)
    local mira = dream.vec3(self.x - math.cos(rumbo) * h, self.y - math.sin(inclinacion), self.z - math.sin(rumbo) * h)
    dream.camera:setTransform(dream:lookAt(ojo, mira):invert())
end

function EscenaAlmacen:dibujar()
    self:mirarMisiles()
    self:prepararCamara()
    dream:prepare()
    for _, luz in ipairs(self.luces) do
        dream:addLight(luz)
    end
    -- Fogonazos (metralleta del soldado, torreta): una luz que parpadea en
    -- la boca de cada arma que dispara.
    self.lamparasFogonazo = self.lamparasFogonazo or {}
    for _, r in ipairs(GestorRobots.getRobots()) do
        local fx, fy, fz, fuerza
        if r.getFogonazo then
            fx, fy, fz, fuerza = r:getFogonazo()
        end
        if fx then
            local luz = self.lamparasFogonazo[r]
            if not luz then
                luz = dream:newLight('point', dream.vec3(0, 0, 0), dream.vec3(1.0, 0.72, 0.38), 1)
                self.lamparasFogonazo[r] = luz
            end
            luz:setPosition(fx, fz, -fy)
            luz:setBrightness(EscenaAlmacen.luzFogonazo * fuerza * (0.7 + 0.6 * love.math.random()))
            dream:addLight(luz)
        end
    end
    local objetos = self.objeto.objects
    -- El edificio va en celdas (tools/blender/almacen_interior.py
    -- `partirEnCeldas`): el motor descarta las que la cámara no ve.
    for _, celda in ipairs(self.celdas) do
        dream:draw(celda)
    end
    dream:draw(objetos.lucernarios)
    dream:draw(objetos.pantallaContador)
    self.sala:dibujar()
    GestorObjetos.dibujar()
    self.fabrica:dibujar()
    GestorRobots.dibujar()
    -- A menos resolución y subido con FSR 1, como la batalla (batalla/dream/escalado.lua).
    Escalado.presentar(dream)
    -- El panel de sensores y el mapa: del robot con el que se trabaja.
    local delPanel = self:getRobotDelPanel()
    self.sensores:dibujar(delPanel)
    -- Los disparos del soldado (siempre a la vista, con o sin sensores).
    for _, r in ipairs(GestorRobots.getRobots()) do
        self.sensores:dibujarDisparos(r)
    end
    -- Los rayos de los ojos de los demás robots.
    for _, r in ipairs(GestorRobots.getRobots()) do
        if r ~= delPanel then
            self.sensores:dibujarOjosDe(r)
        end
    end
    self:dibujarRotulo()
    self.menuFabrica:dibujar()
    -- Las del cuadro (ALMACEN_FPS las enseña): antes de presentar, al final del dibujo.
    if os.getenv('ALMACEN_FPS') then
        self.estadisticas = love.graphics.getStats(self.estadisticas)
    end
end

--- El robot del panel de sensores (EscenaAlmacen.robotDelPanel): el que
-- sigue la cámara o, si no, aquel con el que se trabaja ahora.
function EscenaAlmacen:getRobotDelPanel()
    if self.siguiendo and self.robotSeguido then
        return self.robotSeguido
    end
    return EscenaAlmacen.robotDelPanel == 'soldado' and self.soldado or self.robot
end

function EscenaAlmacen:dibujarRotulo()
    local g = love.graphics
    g.push('all')
    g.origin()
    local w, h = g.getDimensions()
    g.setColor(0, 0, 0, 0.55)
    g.rectangle('fill', 12, 12, 330, 64, 6, 6)
    g.setColor(1, 1, 1, 1)
    g.print('ALMACÉN', 24, 20)
    g.print('Misiles: ' .. (self.misilesVistos or 0) .. ' / ' .. self.almacen:getCapacidad(), 24, 44)
    local ayuda = 'W A S D mover · Espacio / Ctrl subir y bajar · botón derecho mirar · Shift rápido · R sensores del robot · O rayos de los ojos · C seguir al robot · V seguir al soldado · Esc volver al mapa'
    local fuente = g.getFont()
    local ancho = fuente:getWidth(ayuda) + 24
    g.setColor(0, 0, 0, 0.55)
    g.rectangle('fill', (w - ancho) / 2, h - 40, ancho, 28, 6, 6)
    g.setColor(1, 1, 1, 0.9)
    g.print(ayuda, (w - ancho) / 2 + 12, h - 34)
    g.pop()
end

-- Entrada --------------------------------------------------------------------

--- Devuelve 'salir' con Esc.
function EscenaAlmacen:tecla(tecla)
    -- El menú de la fábrica (E junto a la mesa; con él abierto, Esc solo lo cierra).
    if self.menuFabrica:tecla(tecla) then
        return
    end
    if tecla == 'escape' then
        return 'salir'
    end
    -- O: enseña u oculta los rayos de los ojos (el robot ve igual).
    if tecla == 'o' then
        VistaSensores.verOjos = not VistaSensores.verOjos
    end
    -- R: enseña u oculta lo que ven los sensores del robot.
    if tecla == 'r' then
        self.sensores.visible = not self.sensores.visible
    end
    -- C: la cámara sigue al robot (otra vez: vuelve a ser libre).
    if tecla == 'c' then
        self.siguiendo = not self.siguiendo
        self.camaraSeguir = nil
        self.robotSeguido = nil
    end
    -- V: la cámara sigue al soldado que entrena (otra vez: vuelve a ser libre).
    if tecla == 'v' then
        local antes = self.siguiendo and self.robotSeguido
        self.siguiendo = not antes
        self.robotSeguido = not antes and self.soldado or nil
        self.camaraSeguir = nil
    end
end

function EscenaAlmacen:pulsar(x, y, boton)
    if boton == 1 and self.menuFabrica:clic(x, y) then
        return
    end
    if boton == 2 then
        self.mirando = true
    end
end

function EscenaAlmacen:soltar(_, _, boton)
    if boton == 2 then
        self.mirando = false
    end
end

function EscenaAlmacen:mover(_, _, dx, dy)
    if self.mirando then
        self.controlador:mirar(dx, dy)
    end
end

function EscenaAlmacen:rueda(dy)
    self.controlador:empujar(dy * 1.5)
end

function EscenaAlmacen:foco(enfocada)
    if not enfocada then
        self.mirando = false
        self.controlador:detener()
    end
end

function EscenaAlmacen:redimensionar()
    dream:init()
end

--- Devuelve el motor como lo tenía la batalla.
function EscenaAlmacen:cerrar()
    local a = self.antes
    dream:setSky(a.sky[1], a.sky[2])
    if a.fog[1] then
        dream:setFog(a.fog[2], a.fog[3], a.fog[4])
    else
        dream:setFog()
    end
    if a.ao[1] then
        dream:setAO(a.ao[2], a.ao[3])
    end
    dream.camera:setFov(a.fov or 40)
    dream.camera:setNear(a.near or 0.1)
    dream.camera:setFar(a.far or 900)
    dream.canvases:setRefractions(a.refracciones or false)
    dream:init()
    if ambiente then
        ambiente:stop()
    end
    self.sala:cerrar()
    GestorRobots.vaciar()
    GestorObjetos.vaciar()
    if self.lienzo then
        self.lienzo:release()
        self.lienzo = nil
    end
end

return EscenaAlmacen
