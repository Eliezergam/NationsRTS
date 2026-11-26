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
local Disposicion = require('almacen.disposicion')
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
local UsoPC = require('almacen.pc.uso')

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
    -- Los ordenadores de los puestos se usan de verdad (E junto a uno).
    self.usoPC = UsoPC.nuevo(self)
    -- Lo que los robots escriben con print, a su depuración en los ordenadores.
    require('almacen.pc.depuracion').engancharPrint()
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
    -- ALMACEN_SEGUIR=1: la cámara sigue al robot desde el principio (como la
    -- tecla C), para las pruebas largas con capturas.
    if os.getenv('ALMACEN_SEGUIR') then
        self.siguiendo = true
    end
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
    -- Las cajas como se dejaron la última vez (almacen/disposicion.lua) y,
    -- al patio, solo lo que la nación tiene de más desde entonces.
    local cajas = Disposicion.leer(self.almacen, self.almacen:getSemilla())
    local puestas = Disposicion.poner(self, cajas, function(tipo, hueco)
        return GestorObjetos.crear(tipo, hueco.x, hueco.y, hueco.z, hueco.rumbo)
    end)
    local hay = {}
    for _, o in ipairs(puestas) do
        local recurso = datos[o:getTipo()].recurso
        hay[recurso] = (hay[recurso] or 0) + (o.cantidad or 0)
        self.suministros[#self.suministros + 1] = o
    end
    for _, tipo in ipairs(EscenaAlmacen.suministros) do
        local recurso = datos[tipo].recurso
        local falta = math.floor(r[recurso] or 0) - (hay[recurso] or 0)
        if falta < 0 then
            -- Lo gastó mientras no estabas: fuera cajas de ese recurso, las
            -- últimas primero, hasta que cuadre (más adelante, los robots las
            -- sacarán al muelle).
            for k = #self.suministros, 1, -1 do
                local o = self.suministros[k]
                if falta < 0 and datos[o:getTipo()].recurso == recurso then
                    if (o.cantidad or 0) <= -falta then
                        falta = falta + (o.cantidad or 0)
                        o:setSoltar()
                        GestorObjetos.quitar(o)
                        table.remove(self.suministros, k)
                    else
                        o.cantidad = o.cantidad + falta
                        falta = 0
                    end
                end
            end
            falta = 0
        end
        hay[recurso] = (hay[recurso] or 0) + falta
        self.porLlegar[tipo] = falta
    end
    print(string.format('ALMACEN %d cajas en su sitio de la última vez; llegan al patio: %s', #puestas, (function()
        local t = {}
        for _, tipo in ipairs(EscenaAlmacen.suministros) do
            t[#t + 1] = tipo .. '=' .. (self.porLlegar[tipo] or 0)
        end
        return table.concat(t, ' ')
    end)()))
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
    self.relojGuardar = (self.relojGuardar or 0) + dt
    if self.relojGuardar >= EscenaAlmacen.guardarCada then
        self.relojGuardar = 0
        self:guardarDisposicion()
    end
    local medir = os.getenv('ALMACEN_FPS') and love.timer.getTime
    local t0 = medir and medir()
    MundoRobot.cuadro()
    local tMundo = medir and medir()
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
    local dx, dz, dy = 0, 0, 0
    if not self.usoPC:getActivo() then
        dx, dz, dy = c:actualizar(dt, self.x, self.z, self.y, EscenaAlmacen.rapidez)
    end
    local L = LIMITES
    self.x = math.max(L[1], math.min(L[2], self.x + dx))
    self.y = math.max(L[3], math.min(L[4], self.y + dy))
    self.z = math.max(L[5], math.min(L[6], self.z + dz))
    local tS0 = medir and medir()
    self.sala:actualizar(dt)
    self.usoPC:actualizar(dt)
    local tS1 = medir and medir()
    local tR, tB, tF = 0, 0, 0
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
        local a = medir and medir()
        GestorRobots.actualizar(paso * rapido)
        local b = medir and medir()
        Blancos.actualizar(paso * rapido)
        local c2 = medir and medir()
        self.fabrica:actualizar(paso * rapido * (tonumber(os.getenv('FABRICA_RAPIDO')) or 1))
        if medir then
            local d2 = medir()
            tR, tB, tF = tR + b - a, tB + c2 - b, tF + d2 - c2
        end
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
    -- ALMACEN_PRUEBA_PC=1 (con ALMACEN_CAMARA delante del puesto 2): usa el
    -- ordenador como lo haría una persona, por los eventos de LÖVE (tecla E,
    -- doble clic en una hoja, el menú, la terminal escribiendo, Esc) y hace
    -- una foto en cada paso (pc_<n>.png en la carpeta de guardado).
    if os.getenv('ALMACEN_PRUEBA_PC') then
        self:pruebaPC(dt)
    end
    -- ALMACEN_FOTO='<s>,<archivo>': a los s segundos guarda una foto de la
    -- pantalla (en la carpeta de guardado) y cierra el juego. Para revisar
    -- de cerca lo que se pone en la nave (con ALMACEN_CAMARA).
    local foto = os.getenv('ALMACEN_FOTO')
    if foto and not self.fotoHecha then
        local segundos, archivo = foto:match('^([%d%.]+),(.+)$')
        self.relojFoto = (self.relojFoto or 0) + dt
        if segundos and self.relojFoto >= tonumber(segundos) then
            self.fotoHecha = true
            love.graphics.captureScreenshot(function(imagen)
                imagen:encode('png', archivo)
                love.event.quit()
            end)
        end
    end
    -- ALMACEN_FPS=1: apunta los FPS cada 10 s (para medir).
    if os.getenv('ALMACEN_FPS') then
        -- Tiempo de cada parte (ms por cuadro, media de los 10 s).
        local m = self.medidas or { n = 0, mundo = 0, sala = 0, robots = 0, blancos = 0, fabrica = 0 }
        self.medidas = m
        m.n = m.n + 1
        m.mundo = m.mundo + (tMundo - t0)
        m.sala = m.sala + (tS1 - tS0)
        m.robots, m.blancos, m.fabrica = m.robots + tR, m.blancos + tB, m.fabrica + tF
        self.relojFps = (self.relojFps or 0) + dt
        if self.relojFps > 10 then
            self.relojFps = 0
            local s = self.estadisticas or {}
            local k = 1000 / math.max(m.n, 1)
            print(string.format('ALMACEN FPS %d, %d llamadas de dibujo, %d cambios de shader | ms: mundo %.1f sala %.1f robots %.1f blancos %.1f fabrica %.1f dibujo %.1f | memoria %.0f MB | objetos %d',
                love.timer.getFPS(), s.drawcalls or 0, s.shaderswitches or 0, m.mundo * k, m.sala * k, m.robots * k, m.blancos * k, m.fabrica * k, (self.tDibujo or 0) * k,
                collectgarbage('count') / 1024, #GestorObjetos.getObjetos()))
            -- Las especializaciones que más tardan (robots/nucleo.lua).
            local Robot = require('robots.nucleo').Robot
            local lista = {}
            for clave, t in pairs(Robot.tiempos or {}) do
                lista[#lista + 1] = { clave, t * k }
            end
            table.sort(lista, function(a, b) return a[2] > b[2] end)
            local partes = {}
            for i = 1, math.min(6, #lista) do
                partes[i] = string.format('%s %.1f', lista[i][1], lista[i][2])
            end
            print('ALMACEN ms por especializacion: ' .. table.concat(partes, ', '))
            -- Lo que cada robot va acumulando (el dueño, 26-nov: «después de
            -- una hora se ponen torpes»): mapa, memoria y atascos.
            for _, r in ipairs(GestorRobots.getRobots()) do
                local l = r.datos.lidar
                local mapa = l and l.mapa
                local ocupadas = 0
                if mapa then
                    for i = 0, mapa.ancho * mapa.alto - 1 do
                        if mapa.celdas[i] > mapa.umbral then
                            ocupadas = ocupadas + 1
                        end
                    end
                end
                local function contar(t)
                    local n = 0
                    for _ in pairs(t or {}) do
                        n = n + 1
                    end
                    return n
                end
                local nav = r.datos.navegacion or {}
                print(string.format('ALMACEN robot %s en (%.1f, %.1f) | ocupadas %d cambios %d pendientes %d tocadas %d | lidar %d conocidos %d | atascos %d choques %d | %s',
                    tostring(r.tipo), r.x, r.y, ocupadas, mapa and mapa.cambios or 0,
                    mapa and #mapa.ultimosCambios or 0, mapa and contar(mapa.tocadas) or 0,
                    contar(l and l.objetos), contar(r.datos.mirada and r.datos.mirada.conocidos),
                    nav.atascos or 0, r.datos.fisica and r.datos.fisica.choques or 0,
                    tostring(r.getTarea and r:getTarea())))
            end
            Robot.tiempos = {}
            self.medidas = nil
            self.tDibujo = 0
        end
    end
    dream:update()
end

-- El guion de ALMACEN_PRUEBA_PC: { segundo, qué hace }.
function EscenaAlmacen:pruebaPC(dt)
    local Ordenador = require('almacen.pc.ordenador')
    self.relojPrueba = (self.relojPrueba or 0) + dt
    self.pasoPrueba = self.pasoPrueba or 1
    -- De px del escritorio del PC a px de la ventana (como lo encaja uso.lua).
    local function aVentana(x, y)
        local W, H = love.graphics.getDimensions()
        local s = math.min(W / Ordenador.ancho, H / Ordenador.alto)
        return (W - Ordenador.ancho * s) / 2 + x * s, (H - Ordenador.alto * s) / 2 + y * s
    end
    local function clic(x, y, veces)
        local wx, wy = aVentana(x, y)
        love.event.push('mousemoved', wx, wy, 0, 0, false)
        for k = 1, veces or 1 do
            love.event.push('mousepressed', wx, wy, 1, false, k)
            love.event.push('mousereleased', wx, wy, 1, false, k)
        end
    end
    local function tecla(t)
        love.event.push('keypressed', t, t, false)
    end
    local function escribir(texto)
        love.event.push('textinput', texto)
        tecla('return')
    end
    local fotos = 0
    local function foto()
        fotos = fotos + 1
        local n = self.pasoPrueba
        love.graphics.captureScreenshot('pc_' .. n .. '.png')
        print('PRUEBA PC foto pc_' .. n .. '.png')
    end
    -- Iconos del escritorio en columnas de 6: el k-ésimo en
    -- (74 + columna * 124, 24 + fila * 104 + 40); 8 = Muro (2.ª columna).
    -- Un paso con función en vez de segundo espera a que se cumpla (y los
    -- segundos siguientes cuentan desde ahí).
    local Muro = require('almacen.pc.muro')
    -- Un punto del área de la ventana del Muro, en px del escritorio.
    local function enMuro(x, y)
        for _, pc in ipairs(self.sala.ordenadores) do
            for _, v in ipairs(pc.datos.ventanas) do
                if v.programa == 'muro' then
                    return v.x + x, v.y + Ordenador.altoTitulo + y
                end
            end
        end
        return 0, 0
    end
    local function clicMuro(x, y)
        local a, b = enMuro(x, y)
        clic(a, b)
    end
    -- Filas de fuentes: x desde 612, y = 72 + (k - 1) * 36 (+16 al centro).
    local function fuente(k)
        clicMuro(700, 72 + (k - 1) * 36 + 16)
    end
    local guion = {
        { 4, function() tecla('e') end },
        { 5.5, function() clic(74 + 124, 24 + 104 + 40, 2) end }, -- Muro
        { 7, function() fuente(4) end }, -- las 4 grandes: robots
        { 7.5, function() clicMuro(24 + 470, 96 + 40) end }, -- arriba a la derecha
        { 8, function() fuente(5) end }, -- depuración
        { 8.5, function() clicMuro(24 + 470, 96 + 160) end }, -- abajo a la derecha
        { 9, function() fuente(9) end }, -- pantalla del puesto 4
        { 10, foto },
        { 10.5, function() print('PRUEBA MURO ' .. Muro.que('grande') .. ' ' .. Muro.que('arriba') .. ' ' .. Muro.que('abajo')) end },
        { 11, function() tecla('escape') end },
        { 13, foto },
        { 14, function() tecla('e') end },
        { 15, function() clicMuro(24 + 172 + 80, 40 + 19) end }, -- Todo el muro
        { 15.5, function() fuente(1) end }, -- el mapa en todo el muro
        { 16, foto },
        { 16.5, function() print('PRUEBA MURO todo=' .. tostring(Muro.estado.entero) .. ' ' .. Muro.estado.todo) end },
        { 17, function() tecla('escape') end },
        { 19, foto },
        { 19.5, function() love.event.quit() end },
    }
    local paso = guion[self.pasoPrueba]
    if not paso then
        return
    end
    local listo
    if type(paso[1]) == 'function' then
        listo = paso[1]()
        if listo then
            self.relojPrueba = 0
        end
    else
        listo = self.relojPrueba >= paso[1]
    end
    if listo then
        paso[2]()
        self.pasoPrueba = self.pasoPrueba + 1
    end
end

function EscenaAlmacen:prepararCamara()
    local rumbo, inclinacion = self.controlador:angulos()
    local h = math.cos(inclinacion)
    local ojo = dream.vec3(self.x, self.y, self.z)
    local mira = dream.vec3(self.x - math.cos(rumbo) * h, self.y - math.sin(inclinacion), self.z - math.sin(rumbo) * h)
    dream.camera:setTransform(dream:lookAt(ojo, mira):invert())
end

function EscenaAlmacen:dibujar()
    local tDibujo0 = os.getenv('ALMACEN_FPS') and love.timer.getTime()
    -- Dentro de un ordenador su pantalla lo tapa todo: la sala no se pinta.
    if self.usoPC:getTapaTodo() then
        love.graphics.clear(0, 0, 0, 1)
        self.usoPC:dibujar()
        return
    end
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
    -- En el vídeo de la sala (ALMACEN_VIDEO_SALA), sin paneles ni rótulos.
    local videoSala = EscenaAlmacen.grabacion and require('almacen.video_robot').sala
    if videoSala then
        return
    end
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
    if not self.usoPC:getActivo() then
        self:dibujarRotulo()
        self.menuFabrica:dibujar()
    end
    self.usoPC:dibujar()
    -- Las del cuadro (ALMACEN_FPS las enseña): antes de presentar, al final del dibujo.
    if os.getenv('ALMACEN_FPS') then
        self.estadisticas = love.graphics.getStats(self.estadisticas)
    end
    if tDibujo0 then
        self.tDibujo = (self.tDibujo or 0) + love.timer.getTime() - tDibujo0
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
    -- Usando un ordenador, las teclas son suyas (Esc sale de él, no del almacén).
    if self.usoPC:tecla(tecla) then
        return
    end
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
    if self.usoPC:raton('pulsar', x, y, boton) then
        return
    end
    if boton == 1 and self.menuFabrica:clic(x, y) then
        return
    end
    if boton == 2 then
        self.mirando = true
    end
end

function EscenaAlmacen:soltar(x, y, boton)
    if self.usoPC:raton('soltar', x, y, boton) then
        return
    end
    if boton == 2 then
        self.mirando = false
    end
end

function EscenaAlmacen:mover(x, y, dx, dy)
    if self.usoPC:raton('mover', x, y) then
        return
    end
    if self.mirando then
        self.controlador:mirar(dx, dy)
    end
end

function EscenaAlmacen:rueda(dy)
    if self.usoPC:getActivo() then
        return
    end
    self.controlador:empujar(dy * 1.5)
end

--- Texto escrito (love.textinput): para el ordenador que se usa.
function EscenaAlmacen:texto(t)
    self.usoPC:texto(t)
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

-- Cada cuánto se apunta dónde está cada caja (también al salir y al cerrar
-- el juego): si el juego se cierra de golpe, se pierde poco.
EscenaAlmacen.guardarCada = 30

--- Apunta dónde está cada caja ahora (almacen/disposicion.lua).
function EscenaAlmacen:guardarDisposicion()
    -- Con las cajas, lo de los ordenadores de la sala.
    if self.sala then
        self.sala:guardarOrdenadores()
    end
    if not (self.almacen and self.filas) then
        return
    end
    local cajas = Disposicion.tomar(self, GestorObjetos.getObjetos(), EscenaAlmacen.suministros)
    Disposicion.guardar(self.almacen, self.almacen:getSemilla(), cajas)
    print(string.format('ALMACEN guardadas %d cajas en su sitio', #cajas))
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
    self:guardarDisposicion()
    GestorRobots.vaciar()
    GestorObjetos.vaciar()
    if self.lienzo then
        self.lienzo:release()
        self.lienzo = nil
    end
end

return EscenaAlmacen
