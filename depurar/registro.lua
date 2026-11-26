-- Registro para el agente que mira el juego: escribe en JSONL (una línea JSON
-- por evento) lo que pasa en la simulación, para cruzarlo con las capturas y
-- con los errores. Lo lee `tools/analizar_registro.py`.
--
-- Está fuera de la simulación y no la cambia: solo lee su estado y envuelve
-- algunos métodos de la instancia que vigila (los envoltorios devuelven lo
-- mismo que el original). La partida guardada es idéntica con y sin registro.
-- No usa LÖVE: el juego le da la carpeta y el reloj; los arneses, lo suyo.
--
-- Cada línea lleva `t` (segundos reales desde que empezó), `dia`, `cuadro`,
-- `canal`, `tipo` y los datos. Canales de hoy: 'simulacion' y 'captura' (y
-- 'error', que siempre se escribe). Más adelante: cámara, física, rendimiento.

local Simulacion = require('mundo.simulacion')

local ordenadas = Simulacion.ordenadas

local Registro = {}
Registro.__index = Registro

Registro.maxBytes = 50 * 1024 * 1024 -- se corta el archivo al pasar de aquí
Registro.canalesPorDefecto = 'simulacion'
Registro.accionesEnError = 8 -- últimas acciones que se guardan con un error

-- JSON ---------------------------------------------------------------------------------

local codificar

-- Textos ya escritos (ids, claves, misiones): se repiten mucho y buscar en
-- ellos caracteres raros es lo más caro. Se vacía al pasar de `maxCache`.
local cacheTexto, enCache, maxCache = {}, 0, 20000

local function textoJson(s)
    local hecho = cacheTexto[s]
    if hecho then
        return hecho
    end
    if enCache >= maxCache then
        cacheTexto, enCache = {}, 0
    end
    enCache = enCache + 1
    if not s:find('[%c"\\]') then
        hecho = '"' .. s .. '"'
        cacheTexto[s] = hecho
        return hecho
    end
    s = s:gsub('[%c"\\]', function(c)
        if c == '"' then
            return '\\"'
        elseif c == '\\' then
            return '\\\\'
        elseif c == '\n' then
            return '\\n'
        elseif c == '\t' then
            return '\\t'
        end
        return string.format('\\u%04x', c:byte())
    end)
    return '"' .. s .. '"'
end

local function numeroJson(v)
    if v ~= v then
        return '"NaN"'
    elseif v == math.huge then
        return '"inf"'
    elseif v == -math.huge then
        return '"-inf"'
    elseif v == math.floor(v) and math.abs(v) < 1e15 then
        return string.format('%d', v)
    end
    return string.format('%.6g', v)
end

--- Añade a `buffer` el JSON de `v`. Una tabla con [1] es una lista; si no,
-- un objeto con las claves en orden (una vacía sale como lista).
local function meter(buffer, v, profundidad)
    local tipo = type(v)
    if tipo == 'number' then
        buffer[#buffer + 1] = numeroJson(v)
    elseif tipo == 'string' then
        buffer[#buffer + 1] = textoJson(v)
    elseif tipo == 'boolean' then
        buffer[#buffer + 1] = v and 'true' or 'false'
    elseif tipo ~= 'table' then
        buffer[#buffer + 1] = 'null'
    elseif profundidad > 6 then
        buffer[#buffer + 1] = '"..."'
    elseif v[1] ~= nil or next(v) == nil then
        buffer[#buffer + 1] = '['
        for k = 1, #v do
            if k > 1 then
                buffer[#buffer + 1] = ','
            end
            meter(buffer, v[k], profundidad + 1)
        end
        buffer[#buffer + 1] = ']'
    else
        local claves = {}
        for k in pairs(v) do
            claves[#claves + 1] = tostring(k)
        end
        table.sort(claves)
        buffer[#buffer + 1] = '{'
        for n, k in ipairs(claves) do
            local valor = v[k]
            if valor == nil then
                valor = v[tonumber(k)]
            end
            buffer[#buffer + 1] = (n > 1 and ',' or '') .. textoJson(k) .. ':'
            meter(buffer, valor, profundidad + 1)
        end
        buffer[#buffer + 1] = '}'
    end
end

codificar = function(v)
    local buffer = {}
    meter(buffer, v, 0)
    return table.concat(buffer)
end

--- Texto JSON de un valor (claves en orden fijo).
function Registro.json(v)
    return codificar(v)
end

-- Creación ------------------------------------------------------------------------------

--- Conjunto de canales de un texto 'simulacion,captura' (vacío: el de por defecto).
function Registro.canalesDe(texto)
    local out = {}
    for canal in string.gmatch(texto or Registro.canalesPorDefecto, '[^,%s]+') do
        out[canal] = true
    end
    if next(out) == nil then
        out[Registro.canalesPorDefecto] = true
    end
    return out
end

--- Canales pedidos con `--registro [canales]` en los argumentos, o nil si no
-- se pidió. Si no se dicen, 'simulacion'. La captura se marca siempre que
-- haya registro.
function Registro.canalesDeArgumentos(arg)
    for k, valor in ipairs(arg or {}) do
        if valor == '--registro' then
            local siguiente = arg[k + 1]
            if siguiente and not siguiente:match('^%-%-') and not tonumber(siguiente) then
                return Registro.canalesDe(siguiente)
            end
            return Registro.canalesDe(nil)
        end
    end
    return nil
end

--- Registro nuevo. `opciones`:
--   ruta       archivo de salida (los cortes se llaman ruta_2, ruta_3...), o
--   carpeta    carpeta donde crear `<fecha>_<semilla>.jsonl` (la carpeta ya existe)
--   semilla    para el nombre
--   canales    conjunto { simulacion = true, ... } (por defecto, 'simulacion')
--   reloj      función de segundos reales (por defecto, os.clock)
--   maxBytes   tamaño de corte
--   transitable(x, y)  opcional: si hay datos del terreno, marca los grupos
--              que están donde no se puede pisar (agua).
function Registro.nuevo(opciones)
    local self = setmetatable({}, Registro)
    local ruta = opciones.ruta
    if not ruta then
        local nombre = os.date('%Y%m%d_%H%M%S') .. '_' .. tostring(opciones.semilla or 0) .. '.jsonl'
        ruta = opciones.carpeta .. '/' .. nombre
    end
    self.base = ruta:gsub('%.jsonl$', '')
    self.canales = opciones.canales or Registro.canalesDe(nil)
    self.canales.captura = true
    self.reloj = opciones.reloj or os.clock
    self.inicio = self.reloj()
    self.maxBytes = opciones.maxBytes or Registro.maxBytes
    self.transitable = opciones.transitable
    self.numero = 1
    self.escritos = 0
    self.bytes = 0
    self.cuadros = 0
    self.acciones = {} -- últimas acciones (para los errores)
    self.batallas = {} -- id -> { grupos = gid -> { lado, nacion, entrada, salida }, sitio }
    self.vigiladas = setmetatable({}, { __mode = 'k' })
    self:abrir()
    return self
end

function Registro:rutaActual()
    if self.numero == 1 then
        return self.base .. '.jsonl'
    end
    return self.base .. '_' .. self.numero .. '.jsonl'
end

function Registro:abrir()
    local ruta = self:rutaActual()
    local archivo, err = io.open(ruta, 'w')
    if not archivo then
        error('registro: no se puede abrir ' .. ruta .. ': ' .. tostring(err))
    end
    archivo:setvbuf('full')
    self.archivo = archivo
    self.ruta = ruta
    self.bytes = 0
    self.rutas = self.rutas or {}
    self.rutas[#self.rutas + 1] = ruta
end

function Registro:activo(canal)
    return self.canales[canal] == true
end

--- Cuenta un cuadro (el juego lo llama una vez por love.update).
function Registro:cuadro()
    self.cuadros = self.cuadros + 1
end

function Registro:dia()
    return self.sim and self.sim.estado.dia or 0
end

--- Escribe una línea: `t`, `dia`, `cuadro`, `canal`, `tipo` y los datos.
function Registro:escribir(canal, tipo, datos)
    if canal ~= 'error' and not self.canales[canal] then
        return
    end
    local cabeza = string.format(
        '{"t":%s,"dia":%d,"cuadro":%d,"canal":%s,"tipo":%s',
        numeroJson(math.floor((self.reloj() - self.inicio) * 1000 + 0.5) / 1000),
        self:dia(),
        self.cuadros,
        textoJson(canal),
        textoJson(tipo)
    )
    local resto = datos and codificar(datos) or '{}'
    local linea
    if resto == '{}' or resto == '[]' then
        linea = cabeza .. '}\n'
    else
        linea = cabeza .. ',' .. resto:sub(2) .. '\n'
    end
    if self.bytes + #linea > self.maxBytes and self.bytes > 0 then
        self.archivo:close()
        self.numero = self.numero + 1
        self:abrir()
    end
    self.archivo:write(linea)
    self.bytes = self.bytes + #linea
    self.escritos = self.escritos + 1
end

function Registro:volcar()
    if self.archivo then
        self.archivo:flush()
    end
end

function Registro:cerrar()
    if self.archivo then
        self.archivo:close()
        self.archivo = nil
    end
end

-- Lecturas del estado (solo leen: nada de métodos que ordenen o limpien listas) ---------

local function tropasDe(t)
    return { t.soldados or 0, t.tanques or 0, t.lanzacohetes or 0 }
end

local function sumar(a, b)
    for k = 1, 3 do
        a[k] = a[k] + b[k]
    end
end

local function redondear(v, decimales)
    local m = 10 ^ (decimales or 1)
    return math.floor(v * m + 0.5) / m
end

--- Grupos que siguen en un bando de la batalla (sin tocar su lista).
local function gruposBando(e, b, lado)
    local out = {}
    for _, gid in ipairs(b.bandos[lado].grupos) do
        local g = e.grupos[gid]
        if g and g.batalla == b.id then
            out[#out + 1] = g
        end
    end
    return out
end

--- Sitio que defiende la batalla, si sigue siendo de quien era.
local function sitioBando(e, b)
    local d = b.bandos.defensor
    local s = d.sitio and (e.ciudades[d.sitio] or e.instalaciones[d.sitio])
    if s and s.nacion == d.nacionSitio then
        return s
    end
    return nil
end

local function fuerzaBando(e, b, lado)
    local total = { 0, 0, 0 }
    local naciones, grupos = {}, {}
    for _, g in ipairs(gruposBando(e, b, lado)) do
        sumar(total, tropasDe(g))
        naciones[g.nacion] = true
        grupos[#grupos + 1] = g.id
    end
    local out = { tropas = total, grupos = grupos }
    if lado == 'defensor' then
        local s = sitioBando(e, b)
        if s then
            naciones[s.nacion] = true
            out.sitio = { id = s.id, clase = s.tipo or 'ciudad', tropas = tropasDe(s), vida = s.vida or s.salud }
        end
    end
    out.naciones = ordenadas(naciones)
    return out
end

-- Acciones --------------------------------------------------------------------------------

local function resumenResultado(r)
    if type(r) == 'table' then
        return { tabla = true, id = r.id }
    end
    return r
end

function Registro:accion(c, r, motivo)
    local e = self.sim.estado
    local n = c.nacion and e.naciones[c.nacion]
    local parametros = {}
    for k, v in pairs(c) do
        if k ~= 'tipo' and k ~= 'nacion' then
            parametros[k] = v
        end
    end
    local ok = r ~= false and r ~= nil
    local datos = {
        quien = c.nacion,
        jugador = n and n.jugador and true or nil,
        accion = c.tipo,
        parametros = parametros,
        ok = ok,
        resultado = resumenResultado(r),
        motivo = not ok and (motivo or 'sinMotivo') or nil,
    }
    local l = self.acciones
    l[#l + 1] = { dia = e.dia, accion = c.tipo, quien = c.nacion, ok = ok, motivo = datos.motivo }
    if #l > Registro.accionesEnError then
        table.remove(l, 1)
    end
    self:escribir('simulacion', 'accion', datos)
    if not ok then
        return
    end
    if c.tipo == 'recolectar' then
        local g = e.grupos[r]
        self:escribir('simulacion', 'recoleccionSale', {
            nacion = c.nacion,
            grupo = r,
            desde = c.desde,
            yacimiento = c.yacimiento,
            tipoCarga = g and g.tipoCarga,
            tropas = g and tropasDe(g),
            capacidad = g and redondear(Simulacion.capacidad(g)),
        })
    elseif c.tipo == 'bandera' then
        self:escribir('simulacion', 'banderaPlantada', { nacion = c.nacion, id = r, x = c.x, y = c.y })
    elseif c.tipo == 'reparar' then
        local ciudad = e.ciudades[c.ciudad]
        self:escribir('simulacion', 'reparacion', {
            nacion = c.nacion,
            ciudad = c.ciudad,
            puntos = c.puntos,
            vida = ciudad and ciudad.vida,
        })
    end
end

-- Resumen diario ----------------------------------------------------------------------------

function Registro:resumenDia()
    local sim = self.sim
    local e = sim.estado
    local porNacion = {}
    local function de(nid)
        local r = porNacion[nid]
        if not r then
            r = {
                ciudades = 0,
                casa = { 0, 0, 0 },
                fuera = { 0, 0, 0 },
                banderas = 0,
                banderasEnObra = 0,
                campamentos = 0,
                bases = 0,
                recolectores = 0,
                carga = {},
                grupos = 0,
            }
            porNacion[nid] = r
        end
        return r
    end
    -- Solo se suman: el orden no importa y así no se ordena todo el mundo cada día.
    for _, c in pairs(e.ciudades) do
        local r = de(c.nacion)
        r.ciudades = r.ciudades + 1
        sumar(r.casa, tropasDe(c))
    end
    for _, i in pairs(e.instalaciones) do
        local r = de(i.nacion)
        sumar(r.casa, tropasDe(i))
        if i.tipo == 'bandera' then
            if (i.progreso or 1) >= 1 then
                r.banderas = r.banderas + 1
            else
                r.banderasEnObra = r.banderasEnObra + 1
            end
        elseif i.tipo == 'campamento' then
            r.campamentos = r.campamentos + 1
        elseif i.tipo == 'base' then
            r.bases = r.bases + 1
        end
    end
    local filas = {}
    for _, gid in ipairs(ordenadas(e.grupos)) do
        local g = e.grupos[gid]
        local r = de(g.nacion)
        r.grupos = r.grupos + 1
        sumar(r.fuera, tropasDe(g))
        if g.tipoCarga then
            r.recolectores = r.recolectores + 1
            local carga = type(g.carga) == 'number' and g.carga or 0
            r.carga[g.tipoCarga] = redondear((r.carga[g.tipoCarga] or 0) + carga)
        end
        local fila = {
            g.id,
            g.nacion,
            g.mision,
            g.fase or '',
            redondear(g.x, 0),
            redondear(g.y, 0),
            g.soldados or 0,
            g.tanques or 0,
            g.lanzacohetes or 0,
            type(g.carga) == 'number' and redondear(g.carga) or 0,
            g.batalla or 0,
            g.detenido and 1 or 0,
        }
        if self.transitable and not self.transitable(g.x, g.y) then
            fila[13] = 1
        end
        filas[#filas + 1] = fila
    end
    for _, nid in ipairs(ordenadas(e.naciones)) do
        local n = e.naciones[nid]
        local r = de(nid)
        if r.ciudades > 0 then
            local capital = e.ciudades[n.capital]
            local guerras = {}
            for _, clave in ipairs(ordenadas(e.guerras)) do
                local g = e.guerras[clave]
                if g.atacante == nid or g.defensor == nid then
                    guerras[#guerras + 1] = {
                        contra = g.atacante == nid and g.defensor or g.atacante,
                        ataca = g.atacante == nid,
                        fase = g.fase,
                        dias = g.dias,
                    }
                end
            end
            -- Con todas las demás naciones: las que siguen en su relación de
            -- partida no están en `n.relaciones` (sim:relacion la da igual).
            local peor, mejor, vPeor, vMejor
            for _, otra in ipairs(ordenadas(sim.estado.naciones)) do
                if otra ~= nid then
                    local v = sim:relacion(nid, otra)
                    if not peor or v < vPeor then
                        peor, vPeor = otra, v
                    end
                    if not mejor or v > vMejor then
                        mejor, vMejor = otra, v
                    end
                end
            end
            self.nombres = self.nombres or {}
            if not self.nombres[nid] then
                self.nombres[nid] = true
                self:escribir('simulacion', 'nacionNueva', {
                    nacion = nid,
                    nombre = n.nombre,
                    orden = n.orden,
                    capital = n.capital,
                })
            end
            self:escribir('simulacion', 'nacion', {
                nacion = nid,
                jugador = n.jugador and true or nil,
                guardado = {
                    metal = redondear(n.recursos.metal or 0),
                    petroleo = redondear(n.recursos.petroleo or 0),
                    dinero = redondear(n.tesoro or 0),
                },
                afuera = {
                    metal = redondear(n.afuera.metal or 0),
                    petroleo = redondear(n.afuera.petroleo or 0),
                    dinero = redondear(n.afuera.dinero or 0),
                },
                almacen = sim:almacen(nid),
                boveda = sim:boveda(nid),
                capital = n.capital,
                vidaCapital = capital and capital.vida,
                nivel = capital and capital.nivel or 1,
                ciudades = r.ciudades,
                casa = r.casa,
                fuera = r.fuera,
                grupos = r.grupos,
                territorio = sim:celdasDe(nid),
                banderas = r.banderas,
                banderasEnObra = r.banderasEnObra,
                campamentos = r.campamentos,
                bases = r.bases,
                recolectores = r.recolectores,
                carga = r.carga,
                guerras = guerras,
                peor = peor and { nacion = peor, relacion = redondear(vPeor) },
                mejor = mejor and { nacion = mejor, relacion = redondear(vMejor) },
                cansancio = redondear(n.cansancio, 2),
                sinCombustible = n.sinCombustible and true or nil,
            })
        end
    end
    self:escribir('simulacion', 'grupos', {
        columnas = {
            'id',
            'nacion',
            'mision',
            'fase',
            'x',
            'y',
            'soldados',
            'tanques',
            'lanzacohetes',
            'carga',
            'batalla',
            'detenido',
            'agua',
        },
        filas = filas,
    })
end

--- Cambios del día que no pasan por un método envuelto: guerras que empiezan,
-- cambian de fase o terminan, minas que se reabren y obras terminadas.
function Registro:cambiosDia()
    local e = self.sim.estado
    local antes = self.guerrasVistas
    local ahora = {}
    for _, clave in ipairs(ordenadas(e.guerras)) do
        local g = e.guerras[clave]
        ahora[clave] = g.fase
        if antes and not antes[clave] then
            self:escribir('simulacion', 'guerra', { atacante = g.atacante, defensor = g.defensor, fase = g.fase })
        elseif antes and antes[clave] ~= g.fase then
            self:escribir('simulacion', 'guerraFase', {
                atacante = g.atacante,
                defensor = g.defensor,
                antes = antes[clave],
                fase = g.fase,
            })
        end
    end
    if antes then
        for _, clave in ipairs(ordenadas(antes)) do
            if not ahora[clave] then
                local a, b = clave:match('^(.-)|(.*)$')
                self:escribir('simulacion', 'paz', { clave = clave, a = a, b = b })
            end
        end
    end
    self.guerrasVistas = ahora
    local cerradas = {}
    for _, id in ipairs(ordenadas(e.minas)) do
        if e.minas[id].agotadaHasta then
            cerradas[id] = true
        end
    end
    for _, id in ipairs(ordenadas(self.minasCerradas or {})) do
        if not cerradas[id] then
            self:escribir('simulacion', 'minaReabierta', { yacimiento = id })
        end
    end
    self.minasCerradas = cerradas
    local enObra, terminadas = {}, {}
    for id, i in pairs(e.instalaciones) do
        if (i.progreso or 1) < 1 then
            enObra[id] = true
        elseif self.enObra and self.enObra[id] then
            terminadas[#terminadas + 1] = id
        end
    end
    table.sort(terminadas)
    for _, id in ipairs(terminadas) do
        local i = e.instalaciones[id]
        self:escribir('simulacion', 'obraTerminada', {
            id = id,
            clase = i.tipo,
            nacion = i.nacion,
            x = redondear(i.x, 0),
            y = redondear(i.y, 0),
        })
    end
    self.enObra = enObra
end

-- Batallas ------------------------------------------------------------------------------------

function Registro:batalla(bid)
    local r = self.batallas[bid]
    if not r then
        r = { grupos = {} }
        self.batallas[bid] = r
    end
    return r
end

function Registro:grupoEntra(b, g, lado)
    local r = self:batalla(b.id)
    if not r.grupos[g.id] then
        r.grupos[g.id] = { lado = lado, nacion = g.nacion, entrada = tropasDe(g) }
    end
end

function Registro:grupoSale(b, g, como, tropas)
    local r = self.batallas[b.id]
    local gr = r and r.grupos[g.id]
    if gr and not gr.salida then
        gr.salida = tropas or tropasDe(g)
        gr.como = como
    end
end

function Registro:batallaEmpieza(b)
    local e = self.sim.estado
    local r = self:batalla(b.id)
    local defensor = fuerzaBando(e, b, 'defensor')
    r.sitio = defensor.sitio
    local datos = {
        batalla = b.id,
        lugar = b.lugar,
        x = redondear(b.x, 0),
        y = redondear(b.y, 0),
        atacante = fuerzaBando(e, b, 'atacante'),
        defensor = defensor,
    }
    self:escribir('simulacion', 'batallaEmpieza', datos)
    if defensor.sitio and defensor.sitio.clase == 'bandera' then
        self:escribir('simulacion', 'banderaAtacada', {
            bandera = defensor.sitio.id,
            nacion = b.bandos.defensor.nacionSitio,
            atacantes = datos.atacante.naciones,
            batalla = b.id,
        })
    end
end

function Registro:batallaTermina(b, ganador)
    local e = self.sim.estado
    local r = self:batalla(b.id)
    local bajas = { atacante = { 0, 0, 0 }, defensor = { 0, 0, 0 } }
    for _, gid in ipairs(ordenadas(r.grupos)) do
        local gr = r.grupos[gid]
        local g = e.grupos[gid]
        local salida = gr.salida or (g and tropasDe(g)) or gr.entrada
        for k = 1, 3 do
            bajas[gr.lado][k] = bajas[gr.lado][k] + gr.entrada[k] - salida[k]
        end
    end
    local defensor = fuerzaBando(e, b, 'defensor')
    if r.sitio and defensor.sitio then
        for k = 1, 3 do
            -- Si llegaron refuerzos al sitio, no cuentan como bajas negativas.
            bajas.defensor[k] = bajas.defensor[k] + math.max(0, r.sitio.tropas[k] - defensor.sitio.tropas[k])
        end
    end
    self:escribir('simulacion', 'batallaTermina', {
        batalla = b.id,
        lugar = b.lugar,
        dias = b.dias,
        ganador = ganador or 'nadie',
        atacante = fuerzaBando(e, b, 'atacante'),
        defensor = defensor,
        bajas = bajas,
        sitioAntes = r.sitio,
    })
    self.batallas[b.id] = nil
end

-- Vigilar una simulación -----------------------------------------------------------------------

--- Envuelve el método `nombre` de la instancia `sim`: `antes(sim, ...)` se
-- llama con los mismos argumentos y después el original, que devuelve lo de
-- siempre. Sin cierres por llamada, para no romper las trazas de LuaJIT.
local function envolver(sim, nombre, antes)
    local original = sim[nombre]
    sim[nombre] = function(s, ...)
        antes(s, ...)
        return original(s, ...)
    end
end

--- Empieza a vigilar `sim` (una vez por instancia): envuelve sus métodos.
function Registro:vigilar(sim)
    self.sim = sim
    if self.vigiladas[sim] then
        return
    end
    self.vigiladas[sim] = true
    self.guerrasVistas, self.minasCerradas, self.enObra, self.nombres = nil, nil, nil, nil
    self.batallas = {}
    self:escribir('simulacion', 'vigilar', {
        semilla = sim.estado.semilla,
        version = sim.estado.version,
        naciones = #ordenadas(sim.estado.naciones),
    })
    if not self.canales.simulacion then
        return
    end
    local registro = self
    -- Los que necesitan lo que pasó después, uno a uno (ninguno devuelve más de dos valores).
    local ejecutar = sim.ejecutar
    sim.ejecutar = function(s, c)
        local r, motivo = ejecutar(s, c)
        registro:accion(c, r, motivo)
        return r, motivo
    end
    -- Al acabar cada día (en el juego, el tiempo avanza por pasos de marcha).
    local terminarDia = sim.terminarDia
    sim.terminarDia = function(s)
        terminarDia(s)
        registro:cambiosDia()
        registro:resumenDia()
        registro:volcar()
    end
    local crearBatalla = sim.crearBatalla
    sim.crearBatalla = function(s, lugar, x, y, atacantes, defensores, sitioId)
        local b = crearBatalla(s, lugar, x, y, atacantes, defensores, sitioId)
        registro:batallaEmpieza(b)
        return b
    end
    local cerrarMina = sim.cerrarMina
    sim.cerrarMina = function(s, d, grupos)
        cerrarMina(s, d, grupos)
        registro:minaAgotada(d, grupos)
    end
    envolver(sim, 'noticia', function(_, texto)
        registro:escribir('simulacion', 'noticia', { texto = texto })
    end)
    envolver(sim, 'unirBatalla', function(_, b, g, lado)
        registro:grupoEntra(b, g, lado)
    end)
    envolver(sim, 'caerEnBatalla', function(_, b, g)
        registro:grupoSale(b, g, 'cae', { 0, 0, 0 })
    end)
    envolver(sim, 'retirarDeBatalla', function(_, b, g)
        registro:grupoSale(b, g, 'retirada')
    end)
    envolver(sim, 'cerrarBatalla', function(_, b, ganador)
        registro:batallaTermina(b, ganador)
    end)
    envolver(sim, 'destruirInstalacion', function(_, inst, por)
        registro:escribir('simulacion', inst.tipo == 'bandera' and 'banderaCae' or 'instalacionCae', {
            id = inst.id,
            clase = inst.tipo,
            nacion = inst.nacion,
            por = por,
            x = redondear(inst.x, 0),
            y = redondear(inst.y, 0),
        })
    end)
    envolver(sim, 'saquearCapital', function(_, c, g)
        local n = sim.estado.naciones[c.nacion]
        registro:escribir('simulacion', 'saqueo', {
            ciudad = c.id,
            nacion = c.nacion,
            por = g.nacion,
            grupo = g.id,
            botin = {
                metal = redondear(n.afuera.metal),
                petroleo = redondear(n.afuera.petroleo),
                dinero = redondear(n.afuera.dinero),
            },
        })
    end)
    envolver(sim, 'llegada', function(s, g)
        -- Llegada tras ganar un choque junto a su destino (`asaltarTrasChoque`).
        if s.trasChoque then
            registro:escribir('simulacion', 'asaltoTrasChoque', {
                grupo = g.id,
                nacion = g.nacion,
                objetivo = g.objetivo,
                tropas = tropasDe(g),
            })
        end
    end)
    envolver(sim, 'llegarAMina', function(_, g, d)
        registro:escribir('simulacion', g.mision == 'recolectar' and 'recoleccionLlega' or 'ataqueMina', {
            grupo = g.id,
            nacion = g.nacion,
            yacimiento = d.id,
            tropas = tropasDe(g),
        })
    end)
    envolver(sim, 'volver', function(_, g)
        if g.mision == 'recolectar' and g.tipoCarga then
            local carga = type(g.carga) == 'number' and g.carga or 0
            local capacidad = Simulacion.capacidad(g)
            registro:escribir('simulacion', 'recoleccionVuelve', {
                grupo = g.id,
                nacion = g.nacion,
                yacimiento = g.yacimiento,
                carga = redondear(carga),
                capacidad = redondear(capacidad),
                lleno = carga >= capacidad - 1e-6,
            })
        end
    end)
    envolver(sim, 'entregarCarga', function(_, g, casa)
        local carga = type(g.carga) == 'number' and g.carga or 0
        if carga > 0 and g.tipoCarga then
            registro:escribir('simulacion', 'recoleccionEntrega', {
                grupo = g.id,
                nacion = g.nacion,
                en = casa.id,
                tipoCarga = g.tipoCarga,
                carga = redondear(carga),
            })
        end
    end)
end

function Registro:minaAgotada(d, grupos)
    local ids = {}
    for k, g in ipairs(grupos) do
        ids[k] = g.id
    end
    local m = self.sim.estado.minas[d.id]
    self:escribir('simulacion', 'minaAgotada', {
        yacimiento = d.id,
        tipoCarga = d.tipo,
        riqueza = d.riqueza,
        cerradaHasta = m and m.agotadaHasta,
        grupos = ids,
    })
end

--- Para el juego: vigila la simulación viva si ha cambiado (partida nueva o cargada).
function Registro:seguir(sim)
    if sim and sim ~= self.sim then
        self:vigilar(sim)
    end
end

-- Errores y capturas -----------------------------------------------------------------------------

--- Guarda un error con su traza y un resumen del estado. Nunca lanza.
function Registro:error(mensaje, traza)
    pcall(function()
        local resumen
        local sim = self.sim
        if sim and sim.estado then
            local e = sim.estado
            local noticias = {}
            for k = 1, math.min(5, #(e.noticias or {})) do
                noticias[k] = e.noticias[k].texto
            end
            resumen = {
                dia = e.dia,
                semilla = e.semilla,
                naciones = #ordenadas(e.naciones),
                grupos = #ordenadas(e.grupos),
                batallas = #ordenadas(e.batallas),
                guerras = #ordenadas(e.guerras),
                noticias = noticias,
            }
        end
        self:escribir('error', 'error', {
            mensaje = tostring(mensaje),
            traza = traza,
            estado = resumen,
            acciones = self.acciones,
        })
        self:volcar()
    end)
end

--- Corre `fn` y, si falla, guarda el error antes de volver a lanzarlo (para los arneses).
function Registro:proteger(fn, ...)
    local resultado = {
        xpcall(fn, function(mensaje)
            self:error(mensaje, debug.traceback('', 2))
            return mensaje
        end, ...),
    }
    if not resultado[1] then
        error(resultado[2], 0)
    end
    return unpack(resultado, 2)
end

--- Marca de una captura: `datos` = { archivo, camara = { x, y, zoom }, modo }.
-- Devuelve la línea (sin `t`) para guardarla en un .json al lado de la imagen.
function Registro:captura(datos)
    local marca = {
        archivo = datos.archivo,
        dia = self:dia(),
        cuadro = self.cuadros,
        camara = datos.camara,
        modo = datos.modo or 'mapa',
        registro = self.ruta,
    }
    -- En la línea, el día y el cuadro ya van en la cabecera.
    self:escribir('captura', 'captura', {
        archivo = marca.archivo,
        camara = marca.camara,
        modo = marca.modo,
        registro = marca.registro,
    })
    self:volcar()
    return marca
end

return Registro
