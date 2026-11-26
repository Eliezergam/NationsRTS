-- Lote de partículas en la GPU (Camila): un anillo de copias de tamaño fijo
-- que se escriben una sola vez, al nacer, y se dibujan todas en una llamada
-- con instancias. El movimiento y el fundido los calcula el sombreador con
-- la edad (`particula_vertices.lua`, `escombro_vertices.lua`), así que cada
-- cuadro solo se suben las copias nuevas. Las copias muertas se pliegan en
-- el sombreador; si el anillo se llena, la más vieja deja su sitio.
--
-- Las copias nuevas de un cuadro se escriben en un búfer de paso y se suben
-- con `Mesh:setVertices` (dos veces si el anillo da la vuelta). Nada se crea
-- por cuadro. Un lote `dinamico` se vacía y se rellena entero cada cuadro
-- (llamas de tobera y trazadores).

local ffi = require('ffi')

pcall(
    ffi.cdef,
    [[
    typedef struct {
        float ax, ay, az, nace;
        float vx, vy, vz, vida;
        float tam0, tam1, giro0, giro;
        float arrastre, subida, suelo, viento;
        uint8_t r0, g0, b0, a0;
        uint8_t r1, g1, b1, a1;
        uint8_t variante, curva, estirar, semilla;
    } efectoCopia;
]]
)

local Lote = {}
Lote.__index = Lote

Lote.formato = {
    { 'ParticulaA', 'float', 4 },
    { 'ParticulaB', 'float', 4 },
    { 'ParticulaC', 'float', 4 },
    { 'ParticulaD', 'float', 4 },
    { 'ParticulaColor0', 'byte', 4 },
    { 'ParticulaColor1', 'byte', 4 },
    { 'ParticulaExtra', 'byte', 4 },
}

local TAMANO = ffi.sizeof('efectoCopia')
local ATRIBUTOS = {
    'ParticulaA',
    'ParticulaB',
    'ParticulaC',
    'ParticulaD',
    'ParticulaColor0',
    'ParticulaColor1',
    'ParticulaExtra',
}

local function byte(x)
    if x <= 0 then
        return 0
    end
    if x >= 1 then
        return 255
    end
    return math.floor(x * 255 + 0.5)
end

local function nuevoPaso(capacidad)
    local datos = love.data.newByteData(capacidad * TAMANO)
    return datos, ffi.cast('efectoCopia*', datos:getFFIPointer())
end

--- Cuadro de dos triángulos de -0,5 a 0,5 con sus UV: la base de los sprites.
function Lote.cuadro()
    local malla = love.graphics.newMesh({
        { 'VertexPosition', 'float', 2 },
        { 'VertexTexCoord', 'float', 2 },
    }, {
        { -0.5, -0.5, 0, 1 },
        { 0.5, -0.5, 1, 1 },
        { 0.5, 0.5, 1, 0 },
        { -0.5, 0.5, 0, 0 },
    }, 'triangles', 'static')
    malla:setVertexMap(1, 2, 3, 1, 3, 4)
    return malla
end

--- `opciones`: capacidad, porCuadro (copias nuevas por cuadro como mucho),
-- base (malla de LÖVE de cada copia), nombre y dinamico. Para el pase de
-- efectos: sombreador, textura y parametros (uniformes del lote). Para los
-- escombros de 3Dream: material, vertices y pixeles (nombres de los
-- sombreadores registrados en el motor).
function Lote.nuevo(dream, opciones)
    local self = setmetatable({}, Lote)
    self.dream = dream
    self.capacidad = opciones.capacidad
    self.porCuadro = math.min(opciones.porCuadro or 2048, self.capacidad)
    self.dinamico = opciones.dinamico
    -- 'dynamic': LÖVE sube solo las copias cambiadas ('stream' subiría todo
    -- el anillo en cada cuadro). El lote dinámico se rehace entero: 'stream'.
    local uso = opciones.dinamico and 'stream' or 'dynamic'
    self.instancias = love.graphics.newMesh(Lote.formato, self.capacidad, 'triangles', uso)
    -- Todo a cero: copias con vida 0, plegadas.
    self.instancias:setVertices(love.data.newByteData(self.capacidad * TAMANO), 1, self.capacidad)
    self.base = opciones.base
    for _, nombre in ipairs(ATRIBUTOS) do
        self.base:attachAttribute(nombre, self.instancias, 'perinstance')
    end
    self.pasoA, self.punteroA = nuevoPaso(self.porCuadro)
    self.pasoB, self.punteroB = nuevoPaso(self.porCuadro)
    self.cursor = 0 -- siguiente hueco del anillo (desde 0)
    self.inicio = 0 -- hueco de la primera copia nueva de este cuadro
    self.nuevas = 0
    self.escritas = 0 -- copias escritas en total (hasta la capacidad)
    self.cuenta = 0 -- copias que se dibujan
    self.emitidas = 0
    self.sombreador = opciones.sombreador
    if opciones.textura then
        self.base:setTexture(opciones.textura)
    end
    -- Parámetros del sombreador de este lote (estirar, atlas, turbulencia,
    -- fijo, suave, aditivo).
    -- Todos con valor: los uniformes se conservan de un dibujo al siguiente.
    self.parametros = {
        efectoEstirar = 0,
        efectoAtlas = 1,
        efectoTurbulencia = 0,
        efectoFijo = 0,
        efectoSuave = 2,
        efectoAditivo = 0,
    }
    for nombre, valor in pairs(opciones.parametros or {}) do
        self.parametros[nombre] = valor
    end
    if not opciones.material then
        return self
    end

    -- Escombros: van en 3Dream (opacos, con su luz y su niebla).
    local malla = dream:newMesh(opciones.material)
    malla.name = opciones.nombre or 'efecto'
    malla:setPixelShader(opciones.pixeles)
    malla:setVertexShader(opciones.vertices)
    malla:setShadowVisibility(false)
    malla.boundingSphere = dream:newBoundingSphere(dream.vec3(0, 0, 0), 0)
    local lote = self
    -- 3Dream pide la malla de LÖVE y cuántas copias dibujar.
    malla.getMesh = function(_, nombre)
        if nombre ~= nil and nombre ~= 'mesh' then
            return nil
        end
        if lote.cuenta == 0 then
            return nil
        end
        return lote.base, lote.cuenta
    end
    self.malla = malla
    return self
end

--- Escribe una copia con los datos de la tabla `p` (ver `efectos.lua`); en
-- unidades de Dream y segundos. Devuelve false si el cuadro ya va lleno.
function Lote:emitir(p)
    local n = self.nuevas
    if n >= self.porCuadro then
        return false
    end
    local c = self.punteroA[n]
    c.ax, c.ay, c.az, c.nace = p.x, p.y, p.z, p.nace
    c.vx, c.vy, c.vz, c.vida = p.vx, p.vy, p.vz, p.vida
    c.tam0, c.tam1, c.giro0, c.giro = p.tam0, p.tam1, p.giro0, p.giro
    c.arrastre, c.subida, c.suelo, c.viento = p.arrastre, p.subida, p.suelo, p.viento
    local c0, c1 = p.color0, p.color1
    c.r0, c.g0, c.b0, c.a0 = byte(c0[1]), byte(c0[2]), byte(c0[3]), byte(p.alfa)
    c.r1, c.g1, c.b1, c.a1 = byte(c1[1]), byte(c1[2]), byte(c1[3]), byte(p.emision)
    c.variante, c.curva, c.estirar, c.semilla = p.variante, byte(p.curva), byte(p.estirar), p.semilla
    self.nuevas = n + 1
    self.emitidas = self.emitidas + 1
    return true
end

--- Lote dinámico: empieza el cuadro vacío.
function Lote:vaciar()
    self.nuevas = 0
    self.sucio = true
end

--- Sube las copias nuevas del cuadro a la GPU.
function Lote:subir()
    local n = self.nuevas
    if self.dinamico then
        if self.sucio then
            if n > 0 then
                self.instancias:setVertices(self.pasoA, 1, n)
            end
            self.cuenta = n
            self.sucio = false
        end
        return
    end
    if n == 0 then
        return
    end
    local capacidad = self.capacidad
    local inicio = self.cursor
    local primera = math.min(n, capacidad - inicio)
    self.instancias:setVertices(self.pasoA, inicio + 1, primera)
    if primera < n then
        -- El anillo da la vuelta: el resto va al principio.
        ffi.copy(self.punteroB, self.punteroA + primera, (n - primera) * TAMANO)
        self.instancias:setVertices(self.pasoB, 1, n - primera)
    end
    self.cursor = (inicio + n) % capacidad
    self.escritas = math.min(capacidad, self.escritas + n)
    self.cuenta = self.escritas
    self.nuevas = 0
end

--- Dibuja el lote: con su sombreador en el pase de efectos o, si es de
-- 3Dream, pidiéndoselo al motor (antes de `dream:present`).
function Lote:dibujar()
    if self.cuenta == 0 then
        return
    end
    if self.malla then
        self.dream:draw(self.malla)
        return
    end
    local sombreador = self.sombreador
    love.graphics.setShader(sombreador)
    for nombre, valor in pairs(self.parametros) do
        if sombreador:hasUniform(nombre) then
            sombreador:send(nombre, valor)
        end
    end
    love.graphics.drawInstanced(self.base, self.cuenta)
end

return Lote
