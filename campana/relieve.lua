-- Relieve del mapa de campaña con niveles de detalle (Valeria): un árbol de
-- cuatro hijos sobre las alturas del DEM entero (~92 m entre muestras,
-- assets/mapa/caucaso_alturas_fino.bin de tools/mapa/caucaso.py).
--
-- Cada nodo es una malla de `lado` x `lado` cuadros que toma una muestra de
-- cada 2^nivel: nivel 0 a 92 m (el nodo mide ~6 km), 1 a 185 m, 2 a 370 m,
-- 3 a 740 m (la malla de antes)... hasta `nivelMax` (dos raíces). Cada cuadro, desde
-- las raíces, un nodo se divide en sus cuatro hijos si sus cuadros se verían
-- en pantalla más grandes que `umbral` píxeles a la distancia del ojo (a la
-- caja del nodo, con su altura mínima y máxima). Sin grietas entre nodos de
-- distinto nivel: cada nodo lleva un faldón vertical por el borde.
--
-- Las mallas se hacen al pedirlas, con un presupuesto de tiempo por cuadro
-- (`presupuesto`); mientras falta algún hijo se dibuja el padre. Las que
-- llevan `olvido` cuadros sin usarse se liberan si hay más de `maxNodos`.
-- No se recorta por la vista: 3Dream recorta cada malla con su esfera, y las
-- de fuera de la vista siguen proyectando sombra.
--
-- Unidades de 3Dream: 1 = 1 km, X al este, Z al sur, Y arriba, el centro del
-- mapa en el origen (campana/mapa3d.lua).

local ffi = require('ffi')

local Relieve = {}
Relieve.__index = Relieve

Relieve.lado = 64
Relieve.nivelMax = 7
-- Niveles por debajo del DEM (46 y 23 m): sus alturas son las del DEM
-- interpoladas más un ruido de cárcavas (`Relieve.rugosidad`).
Relieve.nivelMin = -2
-- Ruido de detalle: amplitud en metros reales (antes de la exageración) en
-- llano y por cada unidad de pendiente real, con su tope; y las octavas
-- (longitud de onda en muestras del DEM y peso).
Relieve.rugosidad = { llano = 2, pendiente = 40, maximo = 30 }
Relieve.octavas = { { 2, 0.45 }, { 1, 0.3 }, { 0.5, 0.17 }, { 0.25, 0.08 } }
Relieve.umbral = 8 -- px que puede medir en pantalla un cuadro de la malla
Relieve.presupuesto = 0.004 -- s por cuadro para hacer mallas
Relieve.maxNodos = 600
Relieve.olvido = 120 -- cuadros

local CARPETA = 'assets/mapa/'

--- Alturas mínima y máxima de cada nodo, por nivel (las del nivel 0 de las
-- muestras, bordes incluidos; las de arriba, de sus cuatro hijos).
local function calcularRangos(self)
    local lado = Relieve.lado
    local columnas, filas = self.columnas, self.filas
    local ancho = math.ceil((columnas - 1) / lado)
    local alto = math.ceil((filas - 1) / lado)
    local minimos = ffi.new('float[?]', ancho * alto)
    local maximos = ffi.new('float[?]', ancho * alto)
    local fuente = self.fuente
    for bz = 0, alto - 1 do
        for bx = 0, ancho - 1 do
            local menor = 65535
            local mayor = 0
            local ultimaFila = math.min((bz + 1) * lado, filas - 1)
            local ultimaColumna = math.min((bx + 1) * lado, columnas - 1)
            for fila = bz * lado, ultimaFila do
                local base = fila * columnas
                for columna = bx * lado, ultimaColumna do
                    local valor = fuente[base + columna]
                    if valor < menor then
                        menor = valor
                    end
                    if valor > mayor then
                        mayor = valor
                    end
                end
            end
            minimos[bz * ancho + bx] = (menor - self.desplazamiento) * self.escala
            maximos[bz * ancho + bx] = (mayor - self.desplazamiento) * self.escala
        end
    end
    local rangos = {}
    rangos[0] = { ancho = ancho, alto = alto, minimos = minimos, maximos = maximos }
    for nivel = 1, Relieve.nivelMax do
        local hijo = rangos[nivel - 1]
        local nivelAncho = math.ceil(hijo.ancho / 2)
        local nivelAlto = math.ceil(hijo.alto / 2)
        local nivelMinimos = ffi.new('float[?]', nivelAncho * nivelAlto, 1e9)
        local nivelMaximos = ffi.new('float[?]', nivelAncho * nivelAlto, -1e9)
        for z = 0, hijo.alto - 1 do
            for x = 0, hijo.ancho - 1 do
                local k = math.floor(z / 2) * nivelAncho + math.floor(x / 2)
                local h = z * hijo.ancho + x
                nivelMinimos[k] = math.min(nivelMinimos[k], hijo.minimos[h])
                nivelMaximos[k] = math.max(nivelMaximos[k], hijo.maximos[h])
            end
        end
        rangos[nivel] = { ancho = nivelAncho, alto = nivelAlto, minimos = nivelMinimos, maximos = nivelMaximos }
    end
    return rangos
end

--- Índices de un nodo (iguales en todos): la rejilla y el faldón, este por
-- las dos caras (no importa hacia dónde mire el borde).
local function crearIndices(lado)
    local porLado = lado + 1
    local rejilla = porLado * porLado
    local cantidad = lado * lado * 6 + 4 * lado * 12
    local datos = love.data.newByteData(cantidad * 4)
    local indices = ffi.cast('uint32_t*', datos:getFFIPointer())
    local n = 0
    local function triangulo(a, b, c)
        indices[n] = a
        indices[n + 1] = b
        indices[n + 2] = c
        n = n + 3
    end
    for j = 0, lado - 1 do
        for i = 0, lado - 1 do
            -- Vistos desde arriba, en sentido antihorario (como mapa3d.lua).
            local a = j * porLado + i
            local b = a + 1
            local c = a + porLado
            local d = c + 1
            triangulo(a, c, b)
            triangulo(b, c, d)
        end
    end
    -- Faldón: el borde recorrido en orden (norte, este, sur, oeste), cada
    -- vértice con su copia hundida a continuación de la rejilla.
    local borde = {}
    for i = 0, lado do
        borde[#borde + 1] = i
    end
    for j = 1, lado do
        borde[#borde + 1] = j * porLado + lado
    end
    for i = lado - 1, 0, -1 do
        borde[#borde + 1] = lado * porLado + i
    end
    for j = lado - 1, 0, -1 do
        borde[#borde + 1] = j * porLado
    end
    for k = 1, #borde - 1 do
        local a = borde[k]
        local b = borde[k + 1]
        local ah = rejilla + k - 1
        local bh = rejilla + k
        triangulo(a, ah, b)
        triangulo(b, ah, bh)
        triangulo(a, b, ah)
        triangulo(b, bh, ah)
    end
    return datos, borde
end

--- `material`: el del suelo (campana/sombreador_mapa.lua).
function Relieve.nuevo(dream, datos, material)
    local self = setmetatable({}, Relieve)
    self.dream = dream
    self.material = material
    self.columnas = datos.columnasFinas
    self.filas = datos.filasFinas
    self.ancho = datos.anchoMetros / 1000
    self.alto = datos.altoMetros / 1000
    self.pasoX = self.ancho / (self.columnas - 1)
    self.pasoZ = self.alto / (self.filas - 1)
    self.escala = datos.exageracion / 1000
    self.desplazamiento = datos.desplazamiento
    self.archivo = assert(love.filesystem.newFileData(CARPETA .. 'caucaso_alturas_fino.bin'))
    assert(
        self.archivo:getSize() == self.columnas * self.filas * 2,
        'caucaso_alturas_fino.bin no cuadra con caucaso.lua'
    )
    self.fuente = ffi.cast('const uint16_t*', self.archivo:getFFIPointer())
    self.rangos = calcularRangos(self)
    -- Nodos por lado en cada nivel (también los de debajo del DEM).
    self.conteos = {}
    for nivel = Relieve.nivelMin, Relieve.nivelMax do
        local cubre = Relieve.lado * 2 ^ nivel
        self.conteos[nivel] = {
            ancho = math.ceil((self.columnas - 1) / cubre),
            alto = math.ceil((self.filas - 1) / cubre),
        }
    end
    self.indices, self.borde = crearIndices(Relieve.lado)
    self.formato = dream.meshFormats[dream:getShader('mapaCampana').meshFormat]
    self.estructura = self.formato:getCStruct()
    self.nodos = {}
    self.cantidadNodos = 0
    self.cuadro = 0
    self.pedidos = {}
    self.lista = {}
    self.pendientes = 0
    local raiz = self.conteos[Relieve.nivelMax]
    for z = 0, raiz.alto - 1 do
        for x = 0, raiz.ancho - 1 do
            self:crearNodo(Relieve.nivelMax, x, z)
        end
    end
    return self
end

--- Altura de la muestra fina (columna, fila), en unidades de 3Dream.
function Relieve:muestra(columna, fila)
    columna = math.max(0, math.min(self.columnas - 1, columna))
    fila = math.max(0, math.min(self.filas - 1, fila))
    return (self.fuente[fila * self.columnas + columna] - self.desplazamiento) * self.escala
end

--- Altura del suelo (sin el mar) en el punto x, z del mapa.
function Relieve:altura(x, z)
    local u = (x + self.ancho / 2) / self.pasoX
    local v = (z + self.alto / 2) / self.pasoZ
    local columna = math.floor(u)
    local fila = math.floor(v)
    local fu = u - columna
    local fv = v - fila
    local arriba = self:muestra(columna, fila) * (1 - fu) + self:muestra(columna + 1, fila) * fu
    local abajo = self:muestra(columna, fila + 1) * (1 - fu) + self:muestra(columna + 1, fila + 1) * fu
    return arriba * (1 - fv) + abajo * fv
end

local band = bit.band
local bxor = bit.bxor
local rshift = bit.rshift
local tobit = bit.tobit

--- Producto de enteros de 32 bits (como el de C), exacto en dobles: el
-- ruido sale igual en todas las máquinas.
local function imul(a, b)
    local bajo = band(a, 0xffff)
    local alto = rshift(a, 16)
    return tobit(bajo * b + tobit(alto * b) * 65536)
end

--- Número de 0 a 1 de la celda entera (x, z).
local function azar(x, z)
    local h = imul(bxor(x, imul(z, 0x27d4eb2d)), 0x165667b1)
    h = bxor(h, rshift(h, 15))
    h = imul(h, 0x2c1b3c6d)
    h = bxor(h, rshift(h, 12))
    return band(h, 0xffffff) / 0xffffff
end

--- Ruido de valor suave en (x, z), de 0 a 1.
local function ruido(x, z)
    local ix = math.floor(x)
    local iz = math.floor(z)
    local fx = x - ix
    local fz = z - iz
    fx = fx * fx * (3 - 2 * fx)
    fz = fz * fz * (3 - 2 * fz)
    local a = azar(ix, iz)
    local b = azar(ix + 1, iz)
    local c = azar(ix, iz + 1)
    local d = azar(ix + 1, iz + 1)
    return (a + (b - a) * fx) * (1 - fz) + (c + (d - c) * fx) * fz
end

--- Cárcavas: ruido con crestas (1 - |2n - 1|) en varias octavas, de -0,5 a 0,5.
local function carcavas(x, z)
    local suma = 0
    for indice, octava in ipairs(Relieve.octavas) do
        local frecuencia = 1 / octava[1]
        local n = ruido(x * frecuencia + indice * 17.3, z * frecuencia - indice * 9.1)
        suma = suma + (0.5 - math.abs(2 * n - 1)) * octava[2]
    end
    return suma
end

--- Altura en un punto cualquiera (columna y fila con decimales): el DEM
-- interpolado y, con `conRuido`, las cárcavas según la pendiente.
function Relieve:alturaFina(columna, fila, conRuido)
    local c = math.floor(columna)
    local f = math.floor(fila)
    local fc = columna - c
    local ff = fila - f
    local a = self:muestra(c, f)
    local b = self:muestra(c + 1, f)
    local cc = self:muestra(c, f + 1)
    local d = self:muestra(c + 1, f + 1)
    local altura = (a + (b - a) * fc) * (1 - ff) + (cc + (d - cc) * fc) * ff
    if not conRuido then
        return altura
    end
    -- Pendiente real (sin exagerar) de la celda.
    local gx = ((b - a) + (d - cc)) * 0.5 / (self.pasoX * self.escala * 1000)
    local gz = ((cc - a) + (d - b)) * 0.5 / (self.pasoZ * self.escala * 1000)
    local pendiente = math.sqrt(gx * gx + gz * gz)
    local r = Relieve.rugosidad
    local amplitud = math.min(r.llano + r.pendiente * pendiente, r.maximo)
    return altura + carcavas(columna, fila) * amplitud * self.escala
end

local function clave(nivel, x, z)
    return nivel * 16777216 + z * 4096 + x
end

--- Malla del nodo (nivel, x, z), con sus vértices escritos a mano en el
-- formato del sombreador (sin pasar por los búferes de 3Dream).
function Relieve:crearNodo(nivel, x, z)
    local dream = self.dream
    local lado = Relieve.lado
    local porLado = lado + 1
    local paso = 2 ^ nivel
    local columna0 = x * lado * paso
    local fila0 = z * lado * paso
    local ultimaColumna = self.columnas - 1
    local ultimaFila = self.filas - 1
    local rejilla = porLado * porLado
    local cantidad = rejilla + #self.borde
    local datos = love.data.newByteData(ffi.sizeof(self.estructura) * cantidad)
    local vertices = ffi.cast(self.estructura .. '*', datos:getFFIPointer())
    local medioAncho = self.ancho / 2
    local medioAlto = self.alto / 2
    local pasoX = self.pasoX
    local pasoZ = self.pasoZ
    -- Alturas de la rejilla con un anillo más alrededor (para las normales).
    local conRuido = nivel < 0
    local anillo = porLado + 2
    local alturas = self.alturasRejilla
    if not alturas then
        alturas = ffi.new('float[?]', anillo * anillo)
        self.alturasRejilla = alturas
    end
    for j = -1, lado + 1 do
        local fila = math.max(0, math.min(fila0 + j * paso, ultimaFila))
        for i = -1, lado + 1 do
            local columna = math.max(0, math.min(columna0 + i * paso, ultimaColumna))
            local altura
            if conRuido then
                altura = self:alturaFina(columna, fila, true)
            else
                altura = self:muestra(columna, fila)
            end
            alturas[(j + 1) * anillo + i + 1] = altura
        end
    end
    for j = 0, lado do
        local fila = math.min(fila0 + j * paso, ultimaFila)
        for i = 0, lado do
            local columna = math.min(columna0 + i * paso, ultimaColumna)
            local v = vertices[j * porLado + i]
            local k = (j + 1) * anillo + i + 1
            v.VertexPositionX = columna * pasoX - medioAncho
            v.VertexPositionY = alturas[k]
            v.VertexPositionZ = fila * pasoZ - medioAlto
            v.VertexPositionW = 1
            v.VertexTexCoordX = columna / ultimaColumna
            v.VertexTexCoordY = fila / ultimaFila
            -- Normal de la malla a la escala del nodo (diferencias centradas).
            local pendienteX = (alturas[k + 1] - alturas[k - 1]) / (2 * paso * pasoX)
            local pendienteZ = (alturas[k + anillo] - alturas[k - anillo]) / (2 * paso * pasoZ)
            local largo = math.sqrt(pendienteX * pendienteX + 1 + pendienteZ * pendienteZ)
            v.VertexNormalX = -pendienteX / largo * 127.5 + 127.5
            v.VertexNormalY = 1 / largo * 127.5 + 127.5
            v.VertexNormalZ = -pendienteZ / largo * 127.5 + 127.5
            v.VertexNormalW = 0
            v.VertexTangentX = 255
            v.VertexTangentY = 127.5
            v.VertexTangentZ = 127.5
            v.VertexTangentW = 0
        end
    end
    -- Faldón: copia del borde hundida lo que puede separarse del vecino más
    -- fino (pendientes de hasta 2 con la exageración).
    local hundir = 0.2 + paso * pasoX * 1.5
    local tamanoVertice = ffi.sizeof(self.estructura)
    for k, indice in ipairs(self.borde) do
        local destino = rejilla + k - 1
        ffi.copy(vertices + destino, vertices + indice, tamanoVertice)
        vertices[destino].VertexPositionY = vertices[destino].VertexPositionY - hundir
    end
    -- Alturas mínima y máxima: las del nodo (o del nodo del DEM que lo
    -- contiene) más lo que pueda sumar el ruido.
    local nivelRango = math.max(nivel, 0)
    local rango = self.rangos[nivelRango]
    local divisor = 2 ^ (nivelRango - nivel)
    local k = math.floor(z / divisor) * rango.ancho + math.floor(x / divisor)
    local margen = conRuido and Relieve.rugosidad.maximo * self.escala or 0
    local minimo = rango.minimos[k] - hundir - margen
    local maximo = rango.maximos[k] + margen
    local x0 = columna0 * pasoX - medioAncho
    local x1 = math.min(columna0 + lado * paso, ultimaColumna) * pasoX - medioAncho
    local z0 = fila0 * pasoZ - medioAlto
    local z1 = math.min(fila0 + lado * paso, ultimaFila) * pasoZ - medioAlto
    local malla = dream:newMesh(self.material)
    malla:setPixelShader('mapaCampana')
    local mallaLove = love.graphics.newMesh(self.formato.vertexFormat, datos, 'triangles', 'static')
    mallaLove:setVertexMap(self.indices, 'uint32')
    datos:release()
    malla.mesh = mallaLove
    local centro = dream.vec3((x0 + x1) / 2, (minimo + maximo) / 2, (z0 + z1) / 2)
    local radio = math.sqrt((x1 - x0) ^ 2 + (maximo - minimo) ^ 2 + (z1 - z0) ^ 2) / 2
    malla.boundingSphere = dream:newBoundingSphere(centro, radio)
    local nodo = {
        malla = malla,
        usado = self.cuadro,
        caja = { x0, minimo, z0, x1, maximo, z1 },
    }
    self.nodos[clave(nivel, x, z)] = nodo
    self.cantidadNodos = self.cantidadNodos + 1
    return nodo
end

--- Distancia del ojo a la caja (x0, y0, z0, x1, y1, z1).
local function distanciaCaja(caja, ox, oy, oz)
    local dx = math.max(caja[1] - ox, 0, ox - caja[4])
    local dy = math.max(caja[2] - oy, 0, oy - caja[5])
    local dz = math.max(caja[3] - oz, 0, oz - caja[6])
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Relieve:visitar(nivel, x, z, nodo)
    nodo.usado = self.cuadro
    local ojo = self.ojo
    if nivel > Relieve.nivelMin then
        local tamano = 2 ^ nivel * self.pasoX
        local distancia = math.max(distanciaCaja(nodo.caja, ojo[1], ojo[2], ojo[3]), 1e-3)
        if tamano / distancia * self.factorPantalla > Relieve.umbral then
            local hijos = self.conteos[nivel - 1]
            local listos = true
            for dz = 0, 1 do
                for dx = 0, 1 do
                    local hx = x * 2 + dx
                    local hz = z * 2 + dz
                    if hx < hijos.ancho and hz < hijos.alto and not self.nodos[clave(nivel - 1, hx, hz)] then
                        listos = false
                        table.insert(self.pedidos, { nivel - 1, hx, hz, distancia })
                    end
                end
            end
            if listos then
                for dz = 0, 1 do
                    for dx = 0, 1 do
                        local hx = x * 2 + dx
                        local hz = z * 2 + dz
                        local hijo = self.nodos[clave(nivel - 1, hx, hz)]
                        if hijo then
                            self:visitar(nivel - 1, hx, hz, hijo)
                        end
                    end
                end
                return
            end
        end
    end
    self.lista[#self.lista + 1] = nodo.malla
end

--- Libera las mallas que llevan tiempo sin usarse, si hay demasiadas.
function Relieve:olvidar()
    if self.cantidadNodos <= Relieve.maxNodos then
        return
    end
    local limite = self.cuadro - Relieve.olvido
    for k, nodo in pairs(self.nodos) do
        if nodo.usado < limite and math.floor(k / 16777216) < Relieve.nivelMax then
            nodo.malla.mesh:release()
            self.nodos[k] = nil
            self.cantidadNodos = self.cantidadNodos - 1
        end
    end
end

--- Elige los nodos para el ojo (ox, oy, oz), con la pantalla de `alto`
-- píxeles y el campo de visión vertical `fov` (grados), y hace las mallas
-- que falten dentro del presupuesto (`sinLimite`: todas).
function Relieve:actualizar(ox, oy, oz, alto, fov, sinLimite)
    self.cuadro = self.cuadro + 1
    self.ojo = { ox, oy, oz }
    self.factorPantalla = alto / (2 * math.tan(math.rad(fov) / 2))
    local inicio = love.timer.getTime()
    local vueltas = 0
    repeat
        self.lista = {}
        self.pedidos = {}
        local raiz = self.conteos[Relieve.nivelMax]
        for z = 0, raiz.alto - 1 do
            for x = 0, raiz.ancho - 1 do
                self:visitar(Relieve.nivelMax, x, z, self.nodos[clave(Relieve.nivelMax, x, z)])
            end
        end
        table.sort(self.pedidos, function(a, b)
            return a[4] < b[4]
        end)
        for _, pedido in ipairs(self.pedidos) do
            if not sinLimite and love.timer.getTime() - inicio > Relieve.presupuesto then
                break
            end
            if not self.nodos[clave(pedido[1], pedido[2], pedido[3])] then
                self:crearNodo(pedido[1], pedido[2], pedido[3])
            end
        end
        vueltas = vueltas + 1
    until not sinLimite or #self.pedidos == 0 or vueltas > 20
    self.pendientes = 0
    for _, pedido in ipairs(self.pedidos) do
        if not self.nodos[clave(pedido[1], pedido[2], pedido[3])] then
            self.pendientes = self.pendientes + 1
        end
    end
    self:olvidar()
end

function Relieve:dibujar()
    for _, malla in ipairs(self.lista) do
        self.dream:draw(malla)
    end
end

return Relieve
