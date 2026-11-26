-- Efectos de la batalla en 3DreamEngine (Camila): la `salida` de
-- `batalla/efectos.lua`. Todo va en la GPU con pocas llamadas de dibujo:
--
--   en 3Dream (antes de `dream:present`)
--     escombros  terrones, rocas, astillas y chapas 3D (tres mallas por
--                instancias, opacas, con la luz y la niebla del motor)
--     marcas     quemado del suelo (una malla, un anillo de marcas)
--     luces      destellos puntuales con tope; siempre las mismas luces (sin
--                brillo cuando no hay nada) para no recompilar sombreadores
--   en el pase de efectos (después de `dream:present`, ver efectos/comun.lua)
--     estelas    cinta continua de humo de los misiles
--     humo       humo, polvo, tierra, agua y hojas
--     fuego      bolas de fuego y fogonazos (emiten y suman luz)
--     chispas    trazos que siguen su velocidad
--     llamas     llamas de tobera y trazadores, rehechos cada cuadro
--
-- Las partículas nacen una vez y el sombreador calcula su movimiento con la
-- edad: la CPU solo escribe las nuevas. El tope de cada lote y el número de
-- partículas y luces van con la calidad (baja, media o alta).

local Efectos = require('batalla.efectos')
local Lote = require('batalla.dream.efectos.lote')
local Cinta = require('batalla.dream.efectos.cinta')
local Marcas = require('batalla.dream.efectos.marcas')
local Mallas = require('batalla.dream.efectos.mallas')
local Texturas = require('batalla.dream.efectos.texturas')
local Comun = require('batalla.dream.efectos.comun')
local Sombreadores = require('batalla.dream.efectos.sombreadores')
local Conversor = require('batalla.dream.conversor')
local Misiles = require('batalla.dream.efectos.misiles')

local EfectosDream = {}
EfectosDream.__index = EfectosDream

-- Copias como mucho de cada lote por calidad (el anillo cede la más vieja).
EfectosDream.capacidades = {
    baja = { humo = 4096, fuego = 1024, chispa = 1024, escombro = 512, tramos = 8192, llamas = 512 },
    media = { humo = 8192, fuego = 2048, chispa = 2048, escombro = 1024, tramos = 16384, llamas = 1024 },
    alta = { humo = 16384, fuego = 4096, chispa = 4096, escombro = 2048, tramos = 32768, llamas = 1024 },
}

-- Voltea la y de la proyección de 3Dream (hecha para sus lienzos) al dibujar
-- en la pantalla.
EfectosDream.voltear = -1

-- Luz de cielo que recibe el humo: el color de la niebla (el del horizonte)
-- por este factor.
EfectosDream.ambiente = 0.55

local registrados = false

local function registrar(dream)
    if registrados then
        return
    end
    dream:registerShader('batalla/dream/efectos/escombro_vertices', 'efectoEscombro')
    dream:registerShader('batalla/dream/efectos/escombro_pixel', 'efectoEscombroPixel')
    registrados = true
end

--- Calidad elegida por Valeria (batalla/dream/calidad.lua), si existe.
local function calidadActual()
    local ok, Calidad = pcall(require, 'batalla.dream.calidad')
    if ok and Calidad and Calidad.nombre then
        return Calidad.nombre
    end
    return 'alta'
end

--- `opciones.misil`: función que da el modelo del misil en 3Dream y la
-- escala de sus mallas (se dibujan los misiles en vuelo por instancias,
-- batalla/dream/efectos/misiles.lua); `opciones.calidad`: baja, media o alta.
function EfectosDream.nuevos(dream, conversor, tropas, suelo, opciones)
    registrar(dream)
    opciones = opciones or {}
    local self = setmetatable({}, EfectosDream)
    local calidad = opciones.calidad or calidadActual()
    if not EfectosDream.capacidades[calidad] then
        calidad = 'alta'
    end
    self.nombreCalidad = calidad
    local tope = EfectosDream.capacidades[calidad]
    self.dream = dream
    self.conversor = conversor
    self.tropas = tropas
    self.suelo = suelo
    self.texturas = Texturas.crear()
    local tx = self.texturas
    local particula = Sombreadores.particula()
    self.sombreadores = { particula = particula, estela = Sombreadores.estela() }

    self.lotes = {}
    local function lote(nombre, datos)
        datos.nombre = nombre
        local l = Lote.nuevo(dream, datos)
        self.lotes[nombre] = l
        return l
    end
    lote('humo', {
        capacidad = tope.humo,
        porCuadro = 4096,
        base = Lote.cuadro(),
        sombreador = particula,
        textura = tx.humo,
        parametros = { efectoAtlas = 2, efectoTurbulencia = 1, efectoSuave = 2.5, efectoAditivo = 0 },
    })
    lote('fuego', {
        capacidad = tope.fuego,
        porCuadro = 1024,
        base = Lote.cuadro(),
        sombreador = particula,
        textura = tx.fuego,
        parametros = { efectoAtlas = 2, efectoTurbulencia = 0.4, efectoSuave = 4, efectoAditivo = 0.85 },
    })
    lote('chispa', {
        capacidad = tope.chispa,
        porCuadro = 1024,
        base = Lote.cuadro(),
        sombreador = particula,
        textura = tx.chispa,
        parametros = { efectoEstirar = 0.018, efectoSuave = 8, efectoAditivo = 1 },
    })
    lote('llamas', {
        capacidad = tope.llamas,
        porCuadro = tope.llamas,
        base = Lote.cuadro(),
        sombreador = particula,
        textura = tx.chispa,
        dinamico = true,
        parametros = { efectoEstirar = 1, efectoFijo = 1, efectoSuave = 6, efectoAditivo = 1 },
    })
    local materialEscombro = dream:newMaterial('efectoEscombro')
    materialEscombro:setCullMode('none')
    for nombre, malla in pairs({ roca = Mallas.roca(), astilla = Mallas.astilla(), metal = Mallas.metal() }) do
        lote(nombre, {
            capacidad = tope.escombro,
            porCuadro = 512,
            base = malla,
            material = materialEscombro,
            vertices = 'efectoEscombro',
            pixeles = 'efectoEscombroPixel',
        })
    end
    self.lotesDream = { 'roca', 'astilla', 'metal' }
    -- Orden del pase de efectos: humo, después lo que suma luz.
    self.lotesEncima = { 'humo', 'fuego', 'chispa', 'llamas' }

    self.cinta = Cinta.nueva(dream, conversor, {
        cabezas = 256,
        tramos = tope.tramos,
        porCuadro = 2048,
        vida = Efectos.calidades[calidad].vidaEstela,
        sombreador = self.sombreadores.estela,
        textura = tx.estela,
        parametros = {
            estelaArrastre = 0.4,
            estelaSubida = 0.02,
            estelaViento = 1,
            estelaTesela = 18,
            efectoSuave = 2,
            efectoAditivo = 0,
        },
    })
    self.marcas = Marcas.nuevas(dream, conversor, suelo, {
        capacidad = Efectos.calidades[calidad].marcas,
        textura = tx.marca,
    })

    -- Luces de los destellos: siempre las mismas, apagadas si no hay nada.
    self.luces = {}
    for k = 1, Efectos.calidades[calidad].luces do
        local luz = dream:newLight('point', dream.vec3(0, -1000, 0), dream.vec3(1, 0.6, 0.3), 0)
        luz.name = 'destello' .. k
        luz.x, luz.y, luz.z = 0, -1000, 0
        self.luces[k] = { luz = luz, edad = 0, duracion = 0, brillo = 0, actual = 0 }
    end

    if opciones.misil then
        self.misiles = Misiles.nuevos(dream, conversor, opciones.misil, 256)
    end

    -- Partícula de trabajo en unidades de Dream (sin tablas por partícula).
    self.q = {}
    self.sim = Efectos.nuevos(tropas, suelo, self, calidad)
    self.reloj = tropas.reloj
    return self
end

-- Salida de batalla/efectos.lua ------------------------------------------------------------------

local ESCALA = Conversor.escala
local POR_METRO = 0.1 -- unidades de Dream por metro

function EfectosDream:particula(clase, p)
    local lote = self.lotes[clase]
    if not lote then
        return
    end
    local q = self.q
    q.x, q.y, q.z = self.conversor:punto(p.x, p.y, p.z)
    q.vx, q.vy, q.vz = p.vx * POR_METRO, p.vz * POR_METRO, p.vy * POR_METRO
    q.nace = self.tropas.reloj + (p.retraso or 0)
    q.vida = p.vida
    q.tam0, q.tam1 = p.tam0 * POR_METRO, p.tam1 * POR_METRO
    q.giro0, q.giro = p.giro0, p.giro
    q.arrastre = p.arrastre
    q.subida = p.subida * POR_METRO
    q.suelo = p.suelo and p.suelo * ESCALA or -100000
    q.viento = p.viento
    q.color0, q.color1 = p.color0, p.color1
    q.alfa = p.alfa
    q.emision = p.emision
    q.curva = p.curva
    q.estirar = p.estirar
    q.variante = p.variante
    q.semilla = p.semilla
    lote:emitir(q)
end

function EfectosDream:tramoEstela(e, a, b)
    self.cinta:tramo(e, a, b)
end

function EfectosDream:cabezaEstela(e, a, b)
    self.cinta:cabeza(e, a, b)
end

function EfectosDream:soltarCabeza(e)
    self.cinta:soltar(e)
end

--- Sprite de un cuadro: la cabeza en (x, y, z) y la cola hacia (dx, dy, dz).
function EfectosDream:llama(l)
    local q = self.q
    q.x, q.y, q.z = self.conversor:punto(l.x, l.y, l.z)
    -- El trazo mide su ancho más la velocidad (hacia la cabeza) proyectada.
    local largo = l.largo * POR_METRO
    q.vx, q.vy, q.vz = -l.dx * largo, -l.dz * largo, -l.dy * largo
    q.nace = self.tropas.reloj
    q.vida = 1
    q.tam0, q.tam1 = l.ancho * POR_METRO, l.ancho * POR_METRO
    q.giro0, q.giro = 0, 0
    q.arrastre, q.subida, q.suelo, q.viento = 1, 0, -100000, 0
    q.color0, q.color1 = l.color0, l.color0
    q.alfa = l.alfa
    q.emision = l.emision
    q.curva = 1
    q.estirar = 0.25
    q.variante = 0
    q.semilla = 0
    self.lotes.llamas:emitir(q)
end

--- Destello de luz en (x, y, z) px. Con `debil` solo usa una luz libre.
-- Huecos en la neblina (el dueño, 17-nov: «si con los disparos se dispersa un
-- poco quedaría más pro»). Cada fogonazo o explosión empuja el aire: abre una
-- esfera limpia que crece en `crecer` s y se vuelve a llenar en `duracion` s.
-- Radio en metros: base + porBrillo * brillo de su destello (un cañonazo,
-- brillo 20, unos 16 m; una explosión grande, 60, unos 36 m).
EfectosDream.huecos = { cantidad = 8, base = 6, porBrillo = 0.5, crecer = 0.8, duracion = 9, fuerza = 0.9 }

function EfectosDream:abrirHueco(dx, dy, dz, brillo)
    local H = EfectosDream.huecos
    self.listaHuecos = self.listaHuecos or {}
    local lista = self.listaHuecos
    local elegido
    if #lista < H.cantidad then
        elegido = {}
        lista[#lista + 1] = elegido
    else
        -- El más viejo deja su sitio.
        for _, h in ipairs(lista) do
            if not elegido or h.edad > elegido.edad then
                elegido = h
            end
        end
    end
    elegido.x, elegido.y, elegido.z = dx, dy, dz
    elegido.radio = (H.base + H.porBrillo * brillo) * POR_METRO
    elegido.edad = 0
end

function EfectosDream:actualizarHuecos(dt)
    local H = EfectosDream.huecos
    local centros, fuerzas = {}, {}
    for i = 1, H.cantidad do
        local h = self.listaHuecos and self.listaHuecos[i]
        local fuerza, radio = 0, 0
        if h then
            h.edad = h.edad + dt
            if h.edad < H.duracion then
                local abrir = math.min(1, h.edad / H.crecer)
                local cerrar = 1 - h.edad / H.duracion
                fuerza = H.fuerza * cerrar * cerrar
                -- Crece rápido (como una onda) y sigue abriéndose despacio.
                radio = h.radio * (0.35 + 0.65 * (1 - (1 - abrir) ^ 2)) * (1 + 0.25 * h.edad / H.duracion)
            end
        end
        centros[i] = { h and h.x or 0, h and h.y or 0, h and h.z or 0, radio }
        fuerzas[i] = fuerza
    end
    self.dream.fog_holes = centros
    self.dream.fog_holesStrength = fuerzas
end

function EfectosDream:luz(x, y, z, r, g, b, brillo, duracion, debil)
    -- Los fogonazos débiles (las ametralladoras) no mueven la neblina.
    if not debil and brillo >= 10 then
        local hx, hy, hz = self.conversor:punto(x, y, z)
        self:abrirHueco(hx, hy, hz, brillo)
    end
    local elegida
    local menor = math.huge
    for _, l in ipairs(self.luces) do
        if l.actual < menor then
            elegida, menor = l, l.actual
        end
    end
    if not elegida or (debil and menor > 0) or menor > brillo then
        return
    end
    local luz = elegida.luz
    local dx, dy, dz = self.conversor:punto(x, y, z)
    luz.position = self.dream.vec3(dx, dy, dz)
    luz.x, luz.y, luz.z = dx, dy, dz
    luz.color = self.dream.vec3(r, g, b)
    elegida.edad = 0
    elegida.duracion = duracion
    elegida.brillo = brillo
    elegida.actual = brillo
end

function EfectosDream:marca(x, y, _, radio, giro)
    self.marcas:anadir(x, y, radio, giro)
end

-- Cuadro --------------------------------------------------------------------------------------------

--- Después de `tropas:actualizar`: estelas, restos, llamas y luces.
function EfectosDream:actualizar()
    local reloj = self.tropas.reloj
    local dt = reloj - self.reloj
    self.reloj = reloj
    self.lotes.llamas:vaciar()
    self.sim:actualizar()
    self:actualizarHuecos(dt)
    for _, l in ipairs(self.luces) do
        l.edad = l.edad + dt
        if l.edad < l.duracion then
            local f = l.edad / l.duracion
            -- Parpadeo leve mientras dura.
            l.actual = l.brillo * (1 - f) * (1 - f) * (0.85 + 0.15 * math.sin(l.edad * 60))
        else
            l.actual = 0
        end
    end
end

--- Antes de `dream:present`: sube lo nuevo a la GPU, pide a 3Dream los
-- misiles, los escombros y las marcas y enciende los destellos.
function EfectosDream:dibujar()
    local dream = self.dream
    if self.misiles then
        self.misiles:dibujar(self.tropas)
    end
    Comun.tiempo = self.tropas.reloj
    local viento = self.sim.viento
    Comun.viento[1], Comun.viento[2], Comun.viento[3] = viento[1] * POR_METRO, 0, viento[2] * POR_METRO
    for _, l in pairs(self.lotes) do
        l:subir()
    end
    self.cinta:subir()
    for _, nombre in ipairs(self.lotesDream) do
        self.lotes[nombre]:dibujar()
    end
    local t = dream.camera.transform
    self.marcas:dibujar(t[4], t[8], t[12])
    for _, l in ipairs(self.luces) do
        l.luz.brightness = l.actual
        dream:addLight(l.luz)
    end
end

--- Luz del sol, la luna, el cielo, la niebla y los destellos para el pase
-- de efectos: lo mismo que acaba de usar 3Dream en este cuadro.
function EfectosDream:prepararLuz()
    local dream = self.dream
    local sol, luna = Comun.solColor, Comun.lunaColor
    sol[1], sol[2], sol[3] = 0, 0, 0
    luna[1], luna[2], luna[3] = 0, 0, 0
    local mejor = -1
    for _, luz in ipairs(dream.lighting) do
        if luz.typ == 'sun' and luz.brightness > 0 then
            local c, b = luz.color, luz.brightness
            if b > mejor then
                -- El más brillante da la dirección del brillo de la niebla.
                if mejor > 0 then
                    luna[1], luna[2], luna[3] = luna[1] + sol[1], luna[2] + sol[2], luna[3] + sol[3]
                end
                mejor = b
                sol[1], sol[2], sol[3] = c[1] * b, c[2] * b, c[3] * b
                local d = luz.direction
                Comun.solDireccion[1], Comun.solDireccion[2], Comun.solDireccion[3] = d[1], d[2], d[3]
            else
                luna[1], luna[2], luna[3] = luna[1] + c[1] * b, luna[2] + c[2] * b, luna[3] + c[3] * b
            end
        end
    end
    local niebla = Comun.niebla
    local color = dream.fog_color or { 0.7, 0.75, 0.8 }
    local nc = Comun.nieblaColor
    nc[1], nc[2], nc[3] = color[1], color[2], color[3]
    niebla[1] = dream.fog_enabled and dream.fog_density or 0
    niebla[2], niebla[3] = dream.fog_min or 0, dream.fog_max or 0
    niebla[4] = dream.fog_scatter or 0
    local a = Comun.ambiente
    local k = EfectosDream.ambiente
    a[1], a[2], a[3] = nc[1] * k, nc[2] * k, nc[3] * k
    local n = 0
    for _, l in ipairs(self.luces) do
        if l.actual > 0 and n < Comun.maxLuces then
            n = n + 1
            local luz = l.luz
            local pos, col = Comun.lucesPosicion[n], Comun.lucesColor[n]
            pos[1], pos[2], pos[3] = luz.x, luz.y, luz.z
            col[1], col[2], col[3] = luz.color[1] * l.actual, luz.color[2] * l.actual, luz.color[3] * l.actual
        end
    end
    Comun.luces = n
    if os.getenv('EFECTOS_DEPURAR') and not self.depurado then
        self.depurado = true
        print('LUZ sol', sol[1], sol[2], sol[3], 'luna', luna[1], luna[2], luna[3], 'amb', a[1], a[2], a[3])
        print('NIEBLA', niebla[1], niebla[2], niebla[3], niebla[4], nc[1], nc[2], nc[3])
    end
end

--- Después de `dream:present`: estelas, humo, fuego, chispas y llamas sobre
-- la imagen de la escena, probados contra su profundidad.
function EfectosDream:dibujarEncima()
    local dream = self.dream
    local camara = dream.camera
    local t = camara.transform
    Comun.proyeccion = camara.transformProj
    Comun.profundidad = dream.canvases.depth
    Comun.voltear = EfectosDream.voltear
    local d, u, o = Comun.derecha, Comun.arriba, Comun.ojo
    d[1], d[2], d[3] = t[1], t[5], t[9]
    u[1], u[2], u[3] = t[2], t[6], t[10]
    o[1], o[2], o[3] = t[4], t[8], t[12]
    local _, alto = love.graphics.getDimensions()
    Comun.pixel = 2 * math.tan(math.rad(camara:getFov() or 40) / 2) / alto
    self:prepararLuz()
    for _, sombreador in pairs(self.sombreadores) do
        Comun.enviarCuadro(sombreador)
    end

    love.graphics.push('all')
    love.graphics.setBlendMode('alpha', 'premultiplied')
    love.graphics.setDepthMode()
    love.graphics.setMeshCullMode('none')
    love.graphics.setColor(1, 1, 1, 1)
    self.cinta:dibujar()
    local solo = os.getenv('EFECTOS_SOLO')
    for _, nombre in ipairs(self.lotesEncima) do
        if not solo or solo == nombre then
            self.lotes[nombre]:dibujar()
        end
    end
    love.graphics.pop()
end

--- Cuántas partículas se han emitido (para el rótulo y las pruebas).
function EfectosDream:emitidas()
    local total = 0
    for _, l in pairs(self.lotes) do
        total = total + l.emitidas
    end
    return total
end

return EfectosDream
