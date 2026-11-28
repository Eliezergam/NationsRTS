-- Maquetas de las ciudades y las minas en el mapa 2D (el dueño, 27-nov:
-- «remodelar las maquetas del mapa 2D de las minas y las ciudades»; eligió
-- que sean una copia del sitio 3D, a tamaño real).
--
-- Cómo lo hace la industria: Bannerlord rehízo los iconos de su mapa de
-- campaña para que cada ciudad muestre la misma escena en la que se entra
-- (blog de TaleWorlds, «Campaign Map»). Aquí el mapa es una vista
-- isométrica 2D, así que cada sitio se hornea una vez en una imagen (lo que
-- hacen los motores con sus «impostores»: el modelo 3D dibujado desde el
-- ángulo fijo de la cámara) y se guarda en disco.
--
-- La geometría sale en un hilo (mundo/obrero_maqueta.lua,
-- mundo/maqueta_geometria.lua): el mismo plano de la batalla con cada
-- edificio en el nivel lejano del kit, las calles, el muro, la pista y la
-- plataforma. Aquí se dibuja con la proyección del mapa (Iso.vista: la de una
-- cámara ortográfica a 30° de elevación) y su luz (Terreno.luz): primero la
-- profundidad vista desde el sol (sombras), luego el sitio a `muestras` x
-- `muestras` píxeles por píxel, que se reducen para suavizar los bordes. El
-- suelo bajo el sitio no se dibuja: solo deja la sombra que recibe, y el
-- terreno del mapa se ve debajo. La imagen va con alfa premultiplicado.
--
--   local maquetas = Maquetas.nueva(semilla)
--   maquetas:actualizar()                      cada cuadro
--   local m = maquetas:de(sitio)               { imagen, meta } o nil (se pide)
--   Maquetas.dibujar(m, x, y)

local ffi = require('ffi')
local Iso = require('mundo.iso')
local Terreno = require('mundo.terreno')
local KitSitio = require('batalla.dream.kit_sitio')
require('mundo.maqueta_geometria') -- VerticeMaqueta

local Maquetas = {}
Maquetas.__index = Maquetas

Maquetas.escala = 0.32 -- px de la imagen por unidad de la vista (el zoom más cercano es 0,2)
Maquetas.muestras = 4 -- px al hornear por cada px de la imagen, en cada eje
Maquetas.ladoSombra = 2048 -- px del mapa de profundidad desde el sol
Maquetas.sesgoSombra = 1.2 -- m
Maquetas.fuerzaSombra = 0.42 -- lo que oscurece la sombra al terreno del mapa
Maquetas.pendientesMaximas = 2 -- geometrías pedidas al hilo a la vez
Maquetas.disco = os.getenv('MAQUETAS_DISCO') ~= '0'
Maquetas.raiz = 'maquetas-cache'

local FORMATO = {
    { 'VertexPosition', 'float', 3 },
    { 'Normal', 'float', 3 },
    { 'VertexTexCoord', 'float', 2 },
}

local COMUN_VERTICE = [[
attribute vec3 Normal;
uniform vec2 vistaMin;
uniform float escala;
uniform vec2 rangoProf;
uniform vec3 solU;
uniform vec3 solV;
uniform vec3 solW;
uniform vec4 solCaja;
uniform vec2 solProf;
varying vec3 vNormal;
varying vec3 vSol;

vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vec3 p = vertex_position.xyz;
    vec2 v = (vec2(p.x - p.y, (p.x + p.y) * 0.5 - p.z * 1.2247449) - vistaMin) * escala;
    float d = (p.x + p.y) * 0.6123724 + p.z * 0.5;
    vNormal = Normal;
    vSol = vec3(
        (dot(p, solU) - solCaja.x) / solCaja.z,
        (dot(p, solV) - solCaja.y) / solCaja.w,
        (dot(p, solW) - solProf.x) / (solProf.y - solProf.x)
    );
    vec4 r = transform_projection * vec4(v, 0.0, 1.0);
    // Lo más cerca de la cámara (mayor d), menor profundidad.
    r.z = 1.0 - 2.0 * (d - rangoProf.x) / (rangoProf.y - rangoProf.x);
    return r;
}
]]

local COMUN_PIXEL = [[
uniform Image sombra;
uniform vec2 texelSombra;
uniform float sesgo;
varying vec3 vNormal;
varying vec3 vSol;

// Parte del punto que ve el sol (0..1), con 3 x 3 muestras.
float iluminado() {
    float s = 0.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            float h = Texel(sombra, vSol.xy + vec2(float(i), float(j)) * texelSombra).r;
            s += vSol.z >= h - sesgo ? 1.0 : 0.0;
        }
    }
    return s / 9.0;
}
]]

-- Lo construido: albedo de su material, luz del cielo y del sol con sombra.
local SITIO = '#ifdef VERTEX\n' .. COMUN_VERTICE .. '#endif\n#ifdef PIXEL\n' .. COMUN_PIXEL .. [[
uniform vec3 luz;
uniform vec3 tono;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
    vec3 albedo = Texel(tex, uv).rgb * tono;
    vec3 n = normalize(vNormal);
    float ndl = max(dot(n, luz), 0.0);
    float cielo = 0.42 + 0.14 * n.z;
    float l = cielo + 0.62 * ndl * iluminado();
    return vec4(albedo * l, 1.0);
}
#endif
]]

-- El suelo bajo el sitio: transparente, salvo la sombra que recibe.
local SUELO = '#ifdef VERTEX\n' .. COMUN_VERTICE .. '#endif\n#ifdef PIXEL\n' .. COMUN_PIXEL .. [[
uniform float fuerza;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
    float a = (1.0 - iluminado()) * fuerza;
    return vec4(0.0, 0.0, 0.0, a);
}
#endif
]]

-- Profundidad vista desde el sol (mayor, más cerca del sol).
local SOMBRA = [[
#ifdef VERTEX
attribute vec3 Normal;
uniform vec3 solU;
uniform vec3 solV;
uniform vec3 solW;
uniform vec4 solCaja;
uniform vec2 solProf;
varying float vProf;

vec4 position(mat4 transform_projection, vec4 vertex_position) {
    vec3 p = vertex_position.xyz;
    vec2 uv = vec2((dot(p, solU) - solCaja.x) / solCaja.z, (dot(p, solV) - solCaja.y) / solCaja.w);
    vProf = (dot(p, solW) - solProf.x) / (solProf.y - solProf.x);
    return vec4(uv * 2.0 - 1.0, 1.0 - 2.0 * vProf, 1.0);
}
#endif
#ifdef PIXEL
varying float vProf;

vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
    return vec4(vProf, 0.0, 0.0, 1.0);
}
#endif
]]

local sombreadores
local texturas = {}

local function cargarSombreadores()
    if not sombreadores then
        sombreadores = {
            sitio = love.graphics.newShader(SITIO),
            suelo = love.graphics.newShader(SUELO),
            sombra = love.graphics.newShader(SOMBRA),
        }
    end
    return sombreadores
end

-- Materiales de la maqueta que no son del kit: los caminos de tierra de las
-- minas, con la textura del barro de los caminos de la batalla, teñida hacia
-- su tierra (batalla/color_terreno.lua).
Maquetas.propios = {
    caminoTierra = { ruta = 'assets/texturas/batalla/barro/512/albedo.jpg', tono = { 1.15, 0.95, 0.72 } },
}

--- Albedo y tono de un material del kit (los de la biblioteca de la casa,
-- assets/base/materiales; 'kitChapa#3', la chapa del color 3).
local function textura(nombre)
    local t = texturas[nombre]
    if t then
        return t
    end
    local raiz, k = nombre:match('^(.-)#(%d+)$')
    raiz = raiz or nombre
    k = tonumber(k)
    local imagen
    local propio = Maquetas.propios[raiz]
    if propio then
        imagen = love.graphics.newImage(propio.ruta, { mipmaps = true })
        imagen:setWrap('repeat', 'repeat')
        imagen:setFilter('linear', 'linear', 8)
        imagen:setMipmapFilter('linear')
        t = { imagen = imagen, tono = propio.tono }
        texturas[nombre] = t
        return t
    end
    if k and KitSitio.tonosChapa[k] then
        imagen = KitSitio.texturaChapa(k)
    else
        local base = KitSitio.materiales[raiz] or raiz
        local ruta = 'assets/base/materiales/' .. base .. '/albedo.jpg'
        if not love.filesystem.getInfo(ruta) then
            ruta = 'assets/base/materiales/' .. base .. '/albedo.png'
        end
        if not love.filesystem.getInfo(ruta) then
            ruta = 'assets/base/materiales/baseAcero/albedo.jpg'
        end
        imagen = love.graphics.newImage(ruta, { mipmaps = true })
        imagen:setWrap('repeat', 'repeat')
        imagen:setFilter('linear', 'linear', 8)
        imagen:setMipmapFilter('linear')
    end
    t = { imagen = imagen, tono = KitSitio.tonos[raiz] or { 1, 1, 1 } }
    texturas[nombre] = t
    return t
end

-- Ejes de la vista desde el sol: W hacia el sol, U y V en su plano.
local function ejesSol()
    local w = Terreno.luz
    local ux, uy, uz = -w[2], w[1], 0
    local l = math.sqrt(ux * ux + uy * uy)
    ux, uy = ux / l, uy / l
    local vx, vy, vz = w[2] * uz - w[3] * uy, w[3] * ux - w[1] * uz, w[1] * uy - w[2] * ux
    return { ux, uy, uz }, { vx, vy, vz }, { w[1], w[2], w[3] }
end

--- Huella del código que hace las maquetas: si cambia, lo guardado ya no vale.
local version
local function versionMaquetas()
    if version then
        return version
    end
    local partes = {}
    for _, archivo in ipairs({
        'mundo/maquetas.lua',
        'mundo/maqueta_geometria.lua',
        'mundo/terreno.lua',
        'mundo/llano.lua',
        'mundo/ruido.lua',
        'batalla/sitios/plano.lua',
        'batalla/sitios/calles.lua',
        'batalla/sitios/suelo_sitio.lua',
        'batalla/dream/kit_sitio.lua',
        'batalla/dream/calles_malla.lua',
        'batalla/dream/pista_avion.lua',
        'batalla/dream/plataforma_avion.lua',
        'batalla/suelo.lua',
    }) do
        partes[#partes + 1] = love.filesystem.read(archivo) or archivo
    end
    version = love.data.encode('string', 'hex', love.data.hash('md5', table.concat(partes))):sub(1, 12)
    return version
end

-- Un hilo para todos los mundos; cada uno reconoce lo suyo por `dueno`.
local hilo
local siguiente = 0

function Maquetas.nueva(semilla)
    local self = setmetatable({}, Maquetas)
    self.semilla = semilla
    siguiente = siguiente + 1
    self.id = siguiente
    self.lista = {} -- clave -> { imagen, meta } | 'pedida' | false (no se pudo)
    self.cola = {} -- claves por pedir, con su sitio
    self.pendientes = 0
    self.pedidos = love.thread.getChannel('maquetas.pedidos')
    self.hechos = love.thread.getChannel('maquetas.hechos')
    if not hilo then
        local ok, h = pcall(love.thread.newThread, 'mundo/obrero_maqueta.lua')
        if ok then
            hilo = h
            hilo:start()
        else
            print('MAQUETAS sin hilo: ' .. tostring(h))
        end
    end
    self.hilo = hilo
    if Maquetas.disco then
        local carpeta = Maquetas.raiz .. '/' .. versionMaquetas() .. '/' .. tostring(semilla)
        if love.filesystem.createDirectory(carpeta) then
            self.carpeta = carpeta
            self.pedidos:push({ limpiar = Maquetas.raiz, version = versionMaquetas() })
        end
    end
    return self
end

--- Clave de un sitio: su clase y su punto del mapa.
local function clave(sitio)
    local clase = sitio.tipo == 'ciudad' and 'ciudad' or ('mina_' .. tostring(sitio.deposito or 'oro'))
    return string.format('%s_%d_%d', clase, math.floor(sitio.x + 0.5), math.floor(sitio.y + 0.5))
end

--- La maqueta lista de `sitio` = { tipo, capital, deposito, x, y }, o nil
-- mientras se hace (la primera vez la pide, del disco o al hilo).
-- Zoom semántico (el dueño, 28-nov: «de cerca más detalle y de lejos se va
-- simplificando, como en Warpath»): por debajo de `zoomDetalle` no hay
-- maqueta (la ciudad pinta su torre y la mina su icono) y no se hornea lo
-- que no se ve; de `zoomDetalle` a `zoomPleno` la maqueta aparece fundida.
Maquetas.zoomDetalle = 0.09
Maquetas.zoomPleno = 0.12
Maquetas.alfa = 1 -- el fundido de ahora (lo pone `Maquetas:ponerZoom`)

--- El zoom del mapa de este cuadro.
function Maquetas:ponerZoom(zoom)
    self.zoom = zoom
    local t = (zoom - Maquetas.zoomDetalle) / (Maquetas.zoomPleno - Maquetas.zoomDetalle)
    Maquetas.alfa = math.max(0, math.min(1, t))
end

function Maquetas:de(sitio)
    if self.zoom and self.zoom < Maquetas.zoomDetalle then
        return nil
    end
    local k = clave(sitio)
    local m = self.lista[k]
    if m == nil then
        if self:leer(k) then
            return self.lista[k]
        end
        self.lista[k] = 'pedida'
        self.cola[#self.cola + 1] = { clave = k, sitio = { tipo = sitio.tipo, capital = sitio.capital, deposito = sitio.deposito, x = sitio.x, y = sitio.y } }
        return nil
    end
    if type(m) == 'table' then
        return m
    end
    return nil
end

--- Lee la maqueta `k` del disco, si está.
function Maquetas:leer(k)
    if not self.carpeta then
        return false
    end
    local ruta = self.carpeta .. '/' .. k
    if not (love.filesystem.getInfo(ruta .. '.png') and love.filesystem.getInfo(ruta .. '.lua')) then
        return false
    end
    local ok, meta = pcall(function()
        return love.filesystem.load(ruta .. '.lua')()
    end)
    if not ok or type(meta) ~= 'table' then
        return false
    end
    local okImagen, imagen = pcall(love.graphics.newImage, ruta .. '.png', { mipmaps = true })
    if not okImagen then
        return false
    end
    imagen:setFilter('linear', 'linear')
    imagen:setMipmapFilter('linear')
    self.lista[k] = { imagen = imagen, meta = meta }
    return true
end

--- Cada cuadro: pide al hilo lo que falta (pocas a la vez) y hornea como
-- mucho una geometría que haya llegado.
function Maquetas:actualizar()
    if self.hilo and not self.avisado and self.hilo:getError() then
        self.avisado = true
        print('MAQUETAS el hilo falló: ' .. self.hilo:getError())
    end
    while self.pendientes < Maquetas.pendientesMaximas and #self.cola > 0 do
        local p = table.remove(self.cola, 1)
        self.pedidos:push({ dueno = self.id, semilla = self.semilla, clave = p.clave, sitio = p.sitio })
        self.pendientes = self.pendientes + 1
    end
    local r = self.hechos:pop()
    if r and r.dueno ~= self.id then
        -- De un mundo que ya no está.
        for _, mat in ipairs(r.materiales or {}) do
            mat.datos:release()
        end
        r = nil
    end
    if r then
        self.pendientes = self.pendientes - 1
        if r.error then
            print('MAQUETA ' .. tostring(r.clave) .. ': ' .. r.error)
            self.lista[r.clave] = false
        else
            local inicio = love.timer.getTime()
            local ok, m = pcall(Maquetas.hornear, self, r)
            if ok and m then
                self.lista[r.clave] = m
                print(string.format('MAQUETA %s: %d piezas, %d edificios, %d vértices; geometría %.0f ms, horno %.0f ms, %d x %d px',
                    r.clave, r.piezas or 0, r.edificios or 0, r.vertices or 0, r.ms or 0, (love.timer.getTime() - inicio) * 1000,
                    m.imagen:getWidth(), m.imagen:getHeight()))
            else
                print('MAQUETA ' .. tostring(r.clave) .. ' no se pudo hornear: ' .. tostring(m))
                self.lista[r.clave] = false
            end
            for _, mat in ipairs(r.materiales) do
                mat.datos:release()
            end
            if r.suelo then
                r.suelo.datos:release()
                r.suelo.indices:release()
            end
        end
    end
end

local function enviar(shader, nombre, valor)
    if shader:hasUniform(nombre) then
        shader:send(nombre, valor)
    end
end

--- Dibuja la geometría `r` del hilo en una imagen: { imagen, meta }.
function Maquetas:hornear(r)
    local g = love.graphics
    local s = cargarSombreadores()
    local caja = r.caja
    local escala = Maquetas.escala
    local muestras = Maquetas.muestras
    -- Tamaño de la imagen (con un px de margen) y de la de horneado.
    local ancho = math.ceil((caja.vx1 - caja.vx0) * escala) + 2
    local alto = math.ceil((caja.vy1 - caja.vy0) * escala) + 2
    local tope = g.getSystemLimits().texturesize
    muestras = math.max(1, math.min(muestras, math.floor(tope / math.max(ancho, alto))))
    local vistaMin = { caja.vx0 - 1 / escala, caja.vy0 - 1 / escala }
    -- Vista desde el sol: la caja de todo en sus ejes.
    local U, V, W = ejesSol()
    local u0, u1, v0, v1, w0, w1 = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
    for _, x in ipairs({ caja.x0, caja.x1 }) do
        for _, y in ipairs({ caja.y0, caja.y1 }) do
            for _, z in ipairs({ caja.z0, caja.z1 }) do
                local u = x * U[1] + y * U[2] + z * U[3]
                local v = x * V[1] + y * V[2] + z * V[3]
                local w = x * W[1] + y * W[2] + z * W[3]
                u0, u1 = math.min(u0, u), math.max(u1, u)
                v0, v1 = math.min(v0, v), math.max(v1, v)
                w0, w1 = math.min(w0, w), math.max(w1, w)
            end
        end
    end
    w0, w1 = w0 - 5, w1 + 5
    local solCaja = { u0, v0, u1 - u0, v1 - v0 }
    local solProf = { w0, w1 }
    -- Mallas (una por material) y el suelo.
    local mallas = {}
    for _, mat in ipairs(r.materiales) do
        local malla = g.newMesh(FORMATO, mat.datos, 'triangles', 'static')
        local t = textura(mat.nombre)
        malla:setTexture(t.imagen)
        mallas[#mallas + 1] = { malla = malla, tono = t.tono }
    end
    local suelo
    if r.suelo then
        suelo = g.newMesh(FORMATO, r.suelo.datos, 'triangles', 'static')
        suelo:setVertexMap(r.suelo.indices, 'uint32')
    end
    local formatoSombra = g.getCanvasFormats().r32f and 'r32f' or 'rgba16f'
    local lienzoSombra = g.newCanvas(Maquetas.ladoSombra, Maquetas.ladoSombra, { format = formatoSombra })
    lienzoSombra:setFilter('nearest', 'nearest')
    local lienzo = g.newCanvas(ancho * muestras, alto * muestras, { mipmaps = 'manual' })
    local final = g.newCanvas(ancho, alto)
    g.push('all')
    g.reset()
    -- 1. Profundidad desde el sol (solo lo construido: el suelo no tapa).
    g.setCanvas({ lienzoSombra, depth = true })
    g.clear(0, 0, 0, 1, false, true)
    g.setDepthMode('less', true)
    g.setShader(s.sombra)
    enviar(s.sombra, 'solU', U)
    enviar(s.sombra, 'solV', V)
    enviar(s.sombra, 'solW', W)
    enviar(s.sombra, 'solCaja', solCaja)
    enviar(s.sombra, 'solProf', solProf)
    for _, m in ipairs(mallas) do
        g.draw(m.malla)
    end
    -- 2. El sitio a `muestras` px por px: el suelo (solo su sombra) y encima lo
    -- construido, con profundidad.
    g.setCanvas({ lienzo, depth = true })
    g.clear(0, 0, 0, 0, false, true)
    local rangoProf = { caja.d0 - 5, caja.d1 + 5 }
    for _, sh in ipairs({ s.sitio, s.suelo }) do
        enviar(sh, 'vistaMin', vistaMin)
        enviar(sh, 'escala', escala * muestras)
        enviar(sh, 'rangoProf', rangoProf)
        enviar(sh, 'solU', U)
        enviar(sh, 'solV', V)
        enviar(sh, 'solW', W)
        enviar(sh, 'solCaja', solCaja)
        enviar(sh, 'solProf', solProf)
        enviar(sh, 'sombra', lienzoSombra)
        enviar(sh, 'texelSombra', { 1 / Maquetas.ladoSombra, 1 / Maquetas.ladoSombra })
        enviar(sh, 'sesgo', Maquetas.sesgoSombra / (w1 - w0))
    end
    enviar(s.sitio, 'luz', Terreno.luz)
    enviar(s.suelo, 'fuerza', Maquetas.fuerzaSombra)
    if suelo then
        g.setDepthMode('always', false)
        g.setBlendMode('alpha', 'premultiplied')
        g.setShader(s.suelo)
        g.draw(suelo)
    end
    g.setDepthMode('less', true)
    g.setBlendMode('replace', 'premultiplied')
    g.setShader(s.sitio)
    for _, m in ipairs(mallas) do
        s.sitio:send('tono', m.tono)
        g.draw(m.malla)
    end
    -- 3. Reducida: cada px de la imagen, la media de sus muestras (mipmaps).
    g.setShader()
    g.setDepthMode()
    g.setCanvas(final)
    g.clear(0, 0, 0, 0)
    lienzo:generateMipmaps()
    lienzo:setFilter('linear', 'linear')
    lienzo:setMipmapFilter('linear')
    g.setBlendMode('replace', 'premultiplied')
    g.setColor(1, 1, 1, 1)
    g.draw(lienzo, 0, 0, 0, 1 / muestras)
    g.pop()
    local datos = final:newImageData()
    local imagen = g.newImage(datos, { mipmaps = true })
    imagen:setFilter('linear', 'linear')
    imagen:setMipmapFilter('linear')
    for _, m in ipairs(mallas) do
        m.malla:release()
    end
    if suelo then
        suelo:release()
    end
    lienzoSombra:release()
    lienzo:release()
    final:release()
    local meta = {
        vx0 = vistaMin[1],
        vy0 = vistaMin[2],
        escala = escala,
        pista = r.pista,
        recinto = r.recinto,
        chimeneas = r.chimeneas,
    }
    if self.carpeta then
        self.pedidos:push({ guardar = self.carpeta .. '/' .. r.clave, imagen = datos, meta = Maquetas.serializar(meta) })
    else
        datos:release()
    end
    return { imagen = imagen, meta = meta }
end

--- Tabla plana (números, cadenas y tablas de ellos) a código Lua.
function Maquetas.serializar(t)
    local function valor(v)
        if type(v) == 'table' then
            local partes = {}
            for k, x in pairs(v) do
                local llave = type(k) == 'number' and ('[' .. k .. ']') or ('[' .. string.format('%q', k) .. ']')
                partes[#partes + 1] = llave .. ' = ' .. valor(x)
            end
            return '{ ' .. table.concat(partes, ', ') .. ' }'
        elseif type(v) == 'string' then
            return string.format('%q', v)
        end
        return string.format('%.17g', v)
    end
    return 'return ' .. valor(t) .. '\n'
end

-- Humo de las chimeneas en el mapa (mundo/ondear.lua): `fuerza` cuando no
-- se dice otra (las ciudades; las minas, según si alguien recolecta).
Maquetas.humoCiudad = 0.6

--- Dibuja la maqueta `m` del sitio en (x, y) del mapa (en la vista), con el
-- humo de sus chimeneas (`fuerza` de 0 a 1; sin ella, la de la ciudad).
function Maquetas.dibujar(m, x, y, fuerza)
    local g = love.graphics
    local vx, vy = Iso.vista(x, y, 0)
    local meta = m.meta
    local a = Maquetas.alfa
    g.setBlendMode('alpha', 'premultiplied')
    g.setColor(a, a, a, a)
    g.draw(m.imagen, vx + meta.vx0, vy + meta.vy0, 0, 1 / meta.escala)
    g.setBlendMode('alpha')
    local Ondear = require('mundo.ondear')
    for k, c in ipairs(meta.chimeneas or {}) do
        local cx, cy = x + c[1], y + c[2]
        Ondear.columna(cx, cy, c[3], Ondear.fase(cx, cy) + k, fuerza or Maquetas.humoCiudad, a)
    end
    g.setColor(1, 1, 1, 1)
end

return Maquetas
