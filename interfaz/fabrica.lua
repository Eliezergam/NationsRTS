-- Fábrica: el panel pequeño de encargo que abre el radial de tu ciudad
-- (decisión del dueño: en el 2D solo «Crear soldados» y «Producir
-- munición»; lo demás, desde el Arsenal). Un panel claro al centro, como el
-- envío, en tres modos:
--   - 'soldados': cantidad con − y +, «Máx», el tope de la ciudad, el coste,
--     los días y «Producir» (orden `producir`);
--   - 'municion': un lote por fila (balas y misiles) con lo que hay
--     en el polvorín, el coste de todo y «Producir» (una orden por tipo);
--   - 'taller': la vida de la ciudad con «Reparar» y lo que está en el
--     taller (heridos y vehículos averiados) con su plazo y «Sacar ya»
--     (`acelerarRecuperacion`), con lo que cuesta.
--
-- También da los textos que comparte con el Arsenal: el motivo de un
-- rechazo de `sim:puedeProducir` (también los del catálogo de armamento:
-- `era` y `modelo`), el nombre de un encargo por modelo y el coste con los
-- iconos de los recursos.
--
-- Solo lee la simulación: `pulsar` devuelve la lista de comandos y main.lua
-- los manda con `Simulacion:ejecutar`.

local Tema = require('interfaz.tema')
local Acero = require('interfaz.acero')
local Simulacion = require('mundo.simulacion')

local Fabrica = {}
Fabrica.__index = Fabrica

-- Nombres de lo que se produce: { singular, plural } en minúscula.
Fabrica.NOMBRES = {
    soldados = { 'soldado', 'soldados' },
    lanzacohetes = { 'lanzacohetes', 'lanzacohetes' },
    balas = { 'bala', 'balas' },
    misiles = { 'misil', 'misiles' },
}

-- Iconos del kit para cada cosa que se produce (la munición, con el de la
-- tropa que la dispara).
Fabrica.ICONOS = {
    soldados = 'soldado',
    lanzacohetes = 'lanzacohetes',
    balas = 'soldado',
    misiles = 'lanzacohetes',
}

local MUNICIONES = { 'balas', 'misiles' }
local TROPAS = { 'soldados', 'lanzacohetes' }
local RECURSOS = { 'dinero', 'metal', 'petroleo' }
local NOMBRE_RECURSO = { dinero = 'dinero', metal = 'metal', petroleo = 'petróleo' }

--- «1 unidad», «3 lanzacohetes», «2 lotes».
local function plural(n, uno, varios)
    return Tema.numero(n) .. ' ' .. (n == 1 and uno or varios)
end
Fabrica.plural = plural

--- «1 día», «4 días».
function Fabrica.textoDias(dias)
    dias = math.max(0, math.ceil(dias or 0))
    return plural(dias, 'día', 'días')
end

--- Número con coma decimal y hasta un decimal (2,5).
local function decimal(v)
    if v == math.huge then
        return '—'
    end
    if math.abs(v - math.floor(v + 0.5)) < 0.05 then
        return Tema.numero(math.floor(v + 0.5))
    end
    return (string.format('%.1f', v):gsub('%.', ','))
end
Fabrica.decimal = decimal

--- Nombre de la tecnología `id` (la de su fila; las de era, del archivo de
-- datos del catálogo).
function Fabrica.nombreTecnologia(id)
    for _, t in ipairs(Simulacion.tecnologias) do
        if t.id == id then
            return t.nombre
        end
    end
    return Simulacion.nombreModelo(id)
end

--- Lo que desbloquea el modelo `modelo`: «era 3: control de tiro digital».
function Fabrica.requisito(modelo)
    local ficha = Simulacion.fichaModelo(modelo)
    if not ficha or not ficha.tecnologia then
        return nil
    end
    local nombre = Fabrica.nombreTecnologia(ficha.tecnologia)
    if ficha.era > 1 then
        return string.format('era %d: %s', ficha.era, nombre)
    end
    return nombre
end

--- «3 BM-21» (con modelo) o «3 lanzacohetes» (sin él).
function Fabrica.nombreEncargo(tropa, cantidad, modelo)
    if modelo then
        return Tema.numero(cantidad) .. ' ' .. Simulacion.nombreModelo(modelo)
    end
    local nombres = Fabrica.NOMBRES[tropa] or { tostring(tropa), tostring(tropa) }
    return plural(cantidad, nombres[1], nombres[2])
end

--- Texto de por qué `sim:puedeProducir` no deja encargar `cantidad` de
-- `tropa` (del `modelo`, si es un vehículo) en la ciudad `cid` de `nid`.
function Fabrica.textoMotivo(sim, nid, cid, tropa, cantidad, motivo, modelo)
    local c = sim.estado.ciudades[cid]
    local n = sim:nacion(nid)
    local nombre = Fabrica.NOMBRES[tropa] and Fabrica.NOMBRES[tropa][2] or tostring(tropa)
    if motivo == 'noEsSuya' then
        return 'La ciudad no es tuya'
    elseif motivo == 'tropa' then
        return 'Eso no se puede producir'
    elseif motivo == 'impago' then
        return 'Hoy no alcanzó para los sueldos: no se puede encargar nada hasta pagarlos'
    elseif motivo == 'sitiada' then
        return 'La ciudad está sitiada: no fabrica unidades (la munición, sí)'
    elseif motivo == 'era' then
        local requisito = modelo and Fabrica.requisito(modelo)
        if requisito then
            return string.format('%s requiere la %s', Simulacion.nombreModelo(modelo), requisito)
        end
        return 'Ese modelo es de una era que tu nación aún no tiene'
    elseif motivo == 'modelo' then
        return string.format('Ese modelo no es de %s', nombre)
    elseif motivo == 'cantidad' then
        return 'Elige cuántos'
    elseif motivo == 'tope' and c then
        local inv = sim:inventarioCiudad(cid)
        return string.format(
            'Tope de %s en %s: %s de %s (nivel %d). Sube la ciudad de nivel para tener más',
            nombre,
            c.nombre or 'la ciudad',
            Tema.numero(inv[tropa] or 0),
            Tema.numero(sim:topeCiudad(c, tropa)),
            c.nivel or 1
        )
    elseif motivo == 'poblacion' then
        return 'No quedan civiles para reclutar: el 80 % de la ciudad tiene que trabajar'
    elseif motivo == 'dinero' or motivo == 'metal' or motivo == 'petroleo' then
        local coste = Simulacion.costeProduccion(tropa, math.max(1, cantidad or 1), modelo)
        return string.format(
            'No alcanza el %s: cuesta %s y tienes %s',
            NOMBRE_RECURSO[motivo],
            Tema.numero(coste[motivo]),
            Tema.numero(n and math.floor(Simulacion.disponible(n, motivo)) or 0)
        )
    end
    return 'No se puede: ' .. tostring(motivo or 'motivo desconocido')
end

--- Ancho del coste dibujado con `dibujarCoste`.
function Fabrica.anchoCoste(coste, fuente)
    local lado = math.floor(fuente:getHeight() * 0.9)
    local ancho = 0
    for _, r in ipairs(RECURSOS) do
        if (coste[r] or 0) > 0 then
            ancho = ancho + lado + Tema.px(4) + fuente:getWidth(Tema.numero(coste[r])) + Tema.px(12)
        end
    end
    if ancho == 0 then
        return fuente:getWidth('gratis')
    end
    return ancho - Tema.px(12)
end

--- Dibuja un coste { dinero, metal, petroleo } como «[icono] 30 [icono] 3…»
-- desde (x, y). Los recursos que no alcanzan (`falta[recurso]`) van en rojo.
function Fabrica.dibujarCoste(coste, x, y, fuente, falta)
    local g = love.graphics
    local lado = math.floor(fuente:getHeight() * 0.9)
    local cursor = x
    local alguno = false
    g.setFont(fuente)
    for _, r in ipairs(RECURSOS) do
        if (coste[r] or 0) > 0 then
            alguno = true
            Tema.iconoRecurso(r, cursor, y + math.floor((fuente:getHeight() - lado) / 2), lado)
            cursor = cursor + lado + Tema.px(4)
            local texto = Tema.numero(coste[r])
            Tema.color(falta and falta[r] and 'rojoTexto' or 'textoHud')
            g.print(texto, cursor, y)
            cursor = cursor + fuente:getWidth(texto) + Tema.px(12)
        end
    end
    if not alguno then
        Tema.color('textoHudTenue')
        g.print('gratis', x, y)
    end
end

--- Recursos de `coste` que la nación `n` no tiene: { dinero = true, … }.
function Fabrica.falta(n, coste)
    local out = {}
    for _, r in ipairs(RECURSOS) do
        if n and Simulacion.disponible(n, r) < (coste[r] or 0) then
            out[r] = true
        end
    end
    return out
end

--- Coste de reparar la vida de la ciudad `c`: puntos que se pueden pagar ya
-- (hasta 100), lo que falta y su coste.
function Fabrica.reparacionVida(n, c)
    local falta = math.floor(Simulacion.vidaCiudad.maxima - Simulacion.vidaSitio(c) - (c.reparacion or 0))
    if not n or falta < 1 then
        return 0, math.max(0, falta)
    end
    local porPunto = Simulacion.costeReparacion(1)
    local puntos = falta
    for _, r in ipairs({ 'metal', 'petroleo', 'dinero' }) do
        if porPunto[r] > 0 then
            puntos = math.min(puntos, math.floor(Simulacion.disponible(n, r) / porPunto[r]))
        end
    end
    return math.max(0, puntos), falta
end

--- ¿Hay algo en el taller de la ciudad `c` (heridos o vehículos)?
function Fabrica.hayTaller(c)
    local r = c and c.recuperando
    return r ~= nil and (r.soldados or 0) + (r.lanzacohetes or 0) > 0
end

--- «1 lanzac. · 30 heridos» de lo que hay en el taller, o nil.
function Fabrica.textoTaller(c)
    if not Fabrica.hayTaller(c) then
        return nil
    end
    local r = c.recuperando
    local partes = {}
    if (r.lanzacohetes or 0) > 0 then
        partes[#partes + 1] = Tema.numero(r.lanzacohetes) .. ' lanzac.'
    end
    if (r.soldados or 0) > 0 then
        partes[#partes + 1] = Tema.numero(r.soldados) .. ' heridos'
    end
    return table.concat(partes, ' · ')
end

-- Panel ------------------------------------------------------------------------------------------

--- Abre el panel sobre la ciudad `ciudad` (datos de la simulación) en el
-- `modo` 'soldados', 'municion' o 'taller'.
function Fabrica.nuevo(sim, ciudad, modo)
    local self = setmetatable({}, Fabrica)
    self.ciudad = ciudad.id
    self.nacion = ciudad.nacion
    self.modo = modo
    self.cantidades = { soldados = 0, balas = 0, misiles = 0 }
    if modo == 'soldados' then
        local maximo = sim:maximoProducible(ciudad.nacion, ciudad.id, 'soldados')
        local tanda = Simulacion.produccion.tanda.soldados
        self.cantidades.soldados = maximo > 0 and math.min(tanda, maximo) or tanda
    elseif modo == 'municion' then
        -- Un lote de cada munición que dispara lo que hay en la ciudad.
        for _, m in ipairs(MUNICIONES) do
            local tropa = Simulacion.produccion.municion[m].tropa
            local inv = sim:inventarioCiudad(ciudad.id)
            self.cantidades[m] = (inv[tropa] or 0) > 0 and 1 or 0
        end
    end
    self.zonas = {}
    self.motivo = nil
    return self
end

--- Lo que se encarga ahora: { { tropa, cantidad } } (sin las filas a 0).
function Fabrica:pedidos()
    local out = {}
    local lista = self.modo == 'soldados' and { 'soldados' } or MUNICIONES
    for _, t in ipairs(lista) do
        if self.cantidades[t] > 0 then
            out[#out + 1] = { tropa = t, cantidad = self.cantidades[t] }
        end
    end
    return out
end

--- Coste total de lo elegido.
function Fabrica:coste()
    local total = { dinero = 0, metal = 0, petroleo = 0 }
    for _, p in ipairs(self:pedidos()) do
        local c = Simulacion.costeProduccion(p.tropa, p.cantidad)
        for _, r in ipairs(RECURSOS) do
            total[r] = total[r] + c[r]
        end
    end
    return total
end

--- Por qué no saldría el encargo (texto), o nil.
function Fabrica:motivoPrevio(sim)
    local pedidos = self:pedidos()
    if self.modo == 'taller' then
        return nil
    end
    if #pedidos == 0 then
        return self.modo == 'soldados' and 'Elige cuántos' or 'Elige al menos un lote'
    end
    for _, p in ipairs(pedidos) do
        local ok, motivo = sim:puedeProducir(self.nacion, self.ciudad, p.tropa, p.cantidad)
        if not ok then
            return Fabrica.textoMotivo(sim, self.nacion, self.ciudad, p.tropa, p.cantidad, motivo)
        end
    end
    -- Juntos pueden pasar del dinero aunque cada uno quepa solo.
    local n = sim:nacion(self.nacion)
    local coste = self:coste()
    for _, r in ipairs(RECURSOS) do
        if Simulacion.disponible(n, r) < coste[r] then
            return string.format(
                'No alcanza el %s: todo junto cuesta %s y tienes %s',
                NOMBRE_RECURSO[r],
                Tema.numero(coste[r]),
                Tema.numero(math.floor(Simulacion.disponible(n, r)))
            )
        end
    end
    return nil
end

--- Comandos `producir` de lo elegido.
function Fabrica:comandos()
    local out = {}
    for _, p in ipairs(self:pedidos()) do
        out[#out + 1] = {
            tipo = 'producir',
            nacion = self.nacion,
            ciudad = self.ciudad,
            tropa = p.tropa,
            cantidad = p.cantidad,
        }
    end
    return out
end

--- Texto para el aviso cuando el encargo sale: «Encargados 50 soldados en Casa · 2 días».
function Fabrica:textoHecho(sim)
    local c = sim.estado.ciudades[self.ciudad]
    local partes = {}
    local dias = 0
    for _, p in ipairs(self:pedidos()) do
        local nombres = Fabrica.NOMBRES[p.tropa]
        if Simulacion.esMunicion(p.tropa) then
            partes[#partes + 1] = plural(p.cantidad, 'lote', 'lotes') .. ' de ' .. nombres[2]
        else
            partes[#partes + 1] = plural(p.cantidad, nombres[1], nombres[2])
        end
        dias = math.max(dias, Simulacion.diasProduccion(p.tropa, p.cantidad))
    end
    return string.format(
        'Encargado en %s: %s · %s',
        c and c.nombre or 'la ciudad',
        table.concat(partes, ', '),
        Fabrica.textoDias(dias)
    )
end

--- Pone una zona que se puede pulsar.
function Fabrica:zona(x, y, w, h, accion)
    self.zonas[#self.zonas + 1] = { x = x, y = y, w = w, h = h, accion = accion }
end

--- Dibuja el panel en el centro de la pantalla. Si la ciudad ya no es tuya,
-- devuelve false (main.lua lo cierra).
function Fabrica:dibujar(sim)
    local c = sim.estado.ciudades[self.ciudad]
    if not c or c.nacion ~= self.nacion then
        return false
    end
    Tema.modoClaro = true
    local ok, fallo = pcall(self.dibujarClaro, self, sim, c)
    Tema.modoClaro = false
    if not ok then
        error(fallo, 0)
    end
    return true
end

--- Filas del panel según el modo: { { alto, dibujar = function(x, y, w, h) } }.
function Fabrica:filas(sim, c)
    local filas = {}
    local texto = Acero.fuente('cuerpo')
    local fila = Tema.px(48)
    local n = sim:nacion(self.nacion)
    local lado = Tema.px(40)
    -- Fila de cantidad: nombre (con icono) a la izquierda, − cantidad + y lo de la derecha.
    local function filaCantidad(clave, etiqueta, derecha, paso, maximo, sub)
        filas[#filas + 1] = {
            alto = fila,
            dibujar = function(x, y, w)
                local g = love.graphics
                local ic = Tema.px(26)
                Acero.icono(Fabrica.ICONOS[clave], x, y + (fila - ic) / 2, ic, 'textoHud')
                g.setFont(texto)
                Tema.color('textoHud')
                local anchoDerecha = Tema.px(150)
                local bx = x + w - anchoDerecha - lado * 2 - Tema.px(84)
                local libre = bx - x - ic - Tema.px(16)
                if sub then
                    -- Nombre y, debajo, un dato pequeño («lote de 10 000»).
                    local chica = Acero.fuente('etiqueta', 14)
                    local arriba = y + math.floor((fila - texto:getHeight() - chica:getHeight()) / 2)
                    g.print(Tema.cortar(texto, etiqueta, libre), x + ic + Tema.px(10), arriba)
                    g.setFont(chica)
                    Tema.color('textoHudTenue')
                    g.print(Tema.cortar(chica, sub, libre), x + ic + Tema.px(10), arriba + texto:getHeight())
                else
                    g.print(
                        Tema.cortar(texto, etiqueta, libre),
                        x + ic + Tema.px(10),
                        y + math.floor((fila - texto:getHeight()) / 2)
                    )
                end
                local cantidad = self.cantidades[clave]
                local my = y + math.floor((fila - lado) / 2)
                Tema.boton({ texto = '−', tipo = 'oscuro', activo = cantidad > 0 }, bx, my, lado, lado, true)
                self:zona(bx, my, lado, lado, { tipo = 'cambiar', clave = clave, paso = -paso })
                local negrita = Acero.fuente('cifra')
                g.setFont(negrita)
                Tema.color('textoHud')
                g.printf(
                    Tema.numero(cantidad),
                    bx + lado,
                    y + math.floor((fila - negrita:getHeight()) / 2),
                    Tema.px(80),
                    'center'
                )
                local mx = bx + lado + Tema.px(80)
                Tema.boton({ texto = '+', tipo = 'oscuro' }, mx, my, lado, lado, true)
                self:zona(mx, my, lado, lado, { tipo = 'cambiar', clave = clave, paso = paso })
                if maximo then
                    local maxW = anchoDerecha - Tema.px(10)
                    local maxX = x + w - maxW
                    local activo = maximo > 0
                    Tema.boton(
                        { texto = 'Máx ' .. Tema.numero(maximo), tipo = 'secundario', activo = activo },
                        maxX,
                        my,
                        maxW,
                        lado,
                        true
                    )
                    if activo then
                        self:zona(maxX, my, maxW, lado, { tipo = 'maximo', clave = clave, valor = maximo })
                    end
                elseif derecha then
                    g.setFont(texto)
                    Tema.color('textoHudTenue')
                    local t = Tema.cortar(texto, derecha, anchoDerecha - Tema.px(6))
                    g.print(t, x + w - texto:getWidth(t), y + math.floor((fila - texto:getHeight()) / 2))
                end
            end,
        }
    end
    -- Fila de dato: etiqueta tenue y valor en negrita a la derecha.
    local function filaDato(etiqueta, valor, color)
        filas[#filas + 1] = {
            alto = texto:getHeight() + Tema.px(6),
            dibujar = function(x, y, w)
                local g = love.graphics
                local negrita = Acero.fuente('cifra', 18)
                g.setFont(texto)
                Tema.color('textoHudTenue')
                g.print(etiqueta, x, y)
                if type(valor) == 'function' then
                    valor(x, y, w)
                else
                    g.setFont(negrita)
                    Tema.color(color or 'textoHud')
                    local v = Tema.cortar(negrita, valor, w - texto:getWidth(etiqueta) - Tema.px(12))
                    g.print(v, x + w - negrita:getWidth(v), y)
                end
            end,
        }
    end
    local function costeFila(coste)
        return function(x, y, w)
            local negrita = Acero.fuente('cifra', 18)
            local ancho = Fabrica.anchoCoste(coste, negrita)
            Fabrica.dibujarCoste(coste, x + w - ancho, y, negrita, Fabrica.falta(n, coste))
        end
    end
    local inv = sim:inventarioCiudad(c.id)
    if self.modo == 'soldados' then
        local tope = sim:topeCiudad(c, 'soldados')
        local maximo = sim:maximoProducible(self.nacion, c.id, 'soldados')
        filaCantidad('soldados', 'Soldados', nil, 10, maximo)
        filaDato(
            'Soldados de ' .. c.nombre,
            string.format('%s / %s', Tema.numero(inv.soldados), Tema.numero(tope)),
            inv.soldados >= tope and 'rojoTexto' or nil
        )
        local cantidad = self.cantidades.soldados
        filaDato('Coste', costeFila(Simulacion.costeProduccion('soldados', math.max(0, cantidad))))
        filaDato('Tarda', cantidad > 0 and Fabrica.textoDias(Simulacion.diasProduccion('soldados', cantidad)) or '—')
        filaDato('Dejan de trabajar', plural(cantidad, 'civil', 'civiles'))
    elseif self.modo == 'municion' then
        local polvorin = sim:polvorin(c.id) or {}
        local reglas = Simulacion.produccion.municion
        for _, m in ipairs(MUNICIONES) do
            local nombre = Fabrica.NOMBRES[m][2]
            filaCantidad(
                m,
                nombre:sub(1, 1):upper() .. nombre:sub(2),
                'hay ' .. Tema.numero(polvorin[m] or 0),
                1,
                nil,
                'lotes de ' .. Tema.numero(reglas[m].lote)
            )
        end
        filaDato('Coste', costeFila(self:coste()))
        filaDato('Tarda', Fabrica.textoDias(reglas.balas.dias) .. ' · salen todos juntos, también sitiada')
    else
        -- Taller: la vida de la ciudad y lo que está dentro.
        local sitiada = sim:sitiada(c)
        local puntos, falta = Fabrica.reparacionVida(n, c)
        local vida = math.floor(Simulacion.vidaSitio(c) + 0.5)
        local botonVida
        if falta >= 1 then
            local coste = Simulacion.costeReparacion(math.max(1, puntos))
            botonVida = {
                texto = puntos >= 1 and ('Reparar +' .. puntos) or 'No alcanza',
                tipo = 'principal',
                activo = puntos >= 1,
                precio = puntos >= 1 and coste.dinero or nil,
                comando = { tipo = 'reparar', nacion = self.nacion, ciudad = c.id, puntos = puntos },
            }
        end
        local r = c.recuperando or {}
        local lineas = {
            {
                etiqueta = 'Vida de la ciudad',
                valor = string.format('%d / 100', vida)
                    .. ((c.reparacion or 0) > 0 and (' · +' .. math.floor(c.reparacion) .. ' en obra') or ''),
                boton = botonVida,
            },
        }
        for _, tropa in ipairs({ 'lanzacohetes', 'soldados' }) do
            if (r[tropa] or 0) > 0 then
                local dinero, metal = Simulacion.precioRecuperacion(c, tropa)
                local dias = Simulacion.diasRecuperacion(c, tropa)
                local nombre = tropa == 'soldados' and 'Heridos' or 'Lanzacohetes averiados'
                local detalle = sitiada and 'parado: sitiada' or ('vuelven en ' .. Fabrica.textoDias(dias))
                local puede = not sitiada and Simulacion.alcanza(n, { dinero = dinero, metal = metal })
                lineas[#lineas + 1] = {
                    etiqueta = string.format('%s: %s', nombre, Tema.numero(r[tropa])),
                    valor = detalle,
                    boton = {
                        texto = metal > 0 and ('Sacar ya · ' .. Tema.numero(metal) .. ' metal') or 'Sacar ya',
                        tipo = 'secundario',
                        activo = puede,
                        precio = dinero,
                        comando = {
                            tipo = 'acelerarRecuperacion',
                            nacion = self.nacion,
                            ciudad = c.id,
                            tropa = tropa,
                            cantidad = r[tropa],
                        },
                    },
                }
            end
        end
        if not Fabrica.hayTaller(c) then
            lineas[#lineas + 1] = { etiqueta = 'Taller', valor = 'vacío' }
        end
        for _, l in ipairs(lineas) do
            local alto = l.boton and Tema.px(92) or (texto:getHeight() + Tema.px(12))
            filas[#filas + 1] = {
                alto = alto,
                dibujar = function(x, y, w)
                    local g = love.graphics
                    local negrita = Acero.fuente('cifra', 18)
                    g.setFont(texto)
                    Tema.color('textoHud')
                    g.print(l.etiqueta, x, y)
                    g.setFont(negrita)
                    Tema.color('textoHudTenue')
                    local v = Tema.cortar(negrita, l.valor, w - texto:getWidth(l.etiqueta) - Tema.px(12))
                    g.print(v, x + w - negrita:getWidth(v), y)
                    if l.boton then
                        local by = y + texto:getHeight() + Tema.px(8)
                        Tema.boton(l.boton, x, by, w, Tema.px(40), true)
                        if l.boton.activo ~= false then
                            self:zona(x, by, w, Tema.px(40), { tipo = 'comando', comando = l.boton.comando })
                        end
                    end
                    Tema.color('lineaOliva')
                    g.rectangle('fill', x, y + alto - Tema.px(4), w, 1)
                end,
            }
        end
        if sitiada then
            filaDato('Sitiada', 'el taller y las obras están parados', 'rojoTexto')
        end
    end
    -- Lo que ya está en fábrica, en breve (se cancela desde el Arsenal).
    if self.modo ~= 'taller' then
        local cola = sim:colaFabrica(c.id) or { unidades = {}, municion = {} }
        local lista = {}
        if self.modo == 'soldados' then
            for _, o in ipairs(cola.unidades) do
                if o.tropa == 'soldados' then
                    lista[#lista + 1] = string.format(
                        '%s · %s',
                        plural(o.cantidad, 'soldado', 'soldados'),
                        o.enLinea and ('listos en ' .. Fabrica.textoDias(o.dias)) or 'esperan línea'
                    )
                end
            end
        else
            for _, o in ipairs(cola.municion) do
                lista[#lista + 1] = string.format(
                    '%s %s · %s',
                    Tema.numero(o.cantidad),
                    Fabrica.NOMBRES[o.municion][2],
                    'listos en ' .. Fabrica.textoDias(o.dias)
                )
            end
        end
        if #lista > 0 then
            local mostrar = math.min(3, #lista)
            if #lista > 3 then
                lista[3] = string.format('y %d encargos más (Arsenal)', #lista - 2)
            end
            for k = 1, mostrar do
                filaDato(k == 1 and 'En fábrica' or '', lista[k], 'textoHudTenue')
            end
        end
    end
    return filas
end

function Fabrica:dibujarClaro(sim, c)
    local g = love.graphics
    local w, h = g.getDimensions()
    self.zonas = {}
    -- Lo elegido nunca baja de 0.
    for clave, v in pairs(self.cantidades) do
        self.cantidades[clave] = math.max(0, v)
    end
    local texto = Acero.fuente('cuerpo')
    local relleno = Tema.px(16)
    local ancho = Tema.px(Tema.compacta() and 520 or 580)
    local cabecera = Tema.px(50)
    local filas = self:filas(sim, c)
    local altoFilas = 0
    for _, f in ipairs(filas) do
        altoFilas = altoFilas + f.alto
    end
    local motivo = self.motivo or self:motivoPrevio(sim)
    local cw = ancho - relleno * 2 - Tema.px(8)
    local lineasMotivo = 0
    if motivo then
        local _, partes = texto:getWrap(motivo, cw)
        lineasMotivo = #partes
    end
    local alto = cabecera
        + relleno
        + texto:getHeight()
        + Tema.px(10)
        + altoFilas
        + Tema.px(8)
        + math.max(1, lineasMotivo) * texto:getHeight()
        + Tema.px(12)
        + Tema.px(44)
        + relleno
    local x, y = math.floor((w - ancho) / 2), math.floor((h - alto) / 2)
    self.rect = { x = x, y = y, w = ancho, h = alto }
    local titulos = {
        soldados = 'Crear soldados en ',
        municion = 'Producir munición en ',
        taller = 'Reparar y taller de ',
    }
    local _, _, _, _, cierre =
        Acero.panel(x, y, ancho, alto, { titulo = titulos[self.modo] .. c.nombre, cerrar = true })
    if cierre then
        self:zona(cierre.x, cierre.y, cierre.w, cierre.h, { tipo = 'cancelar' })
    end
    local n = sim:nacion(self.nacion)
    if n then
        Tema.color(n.color)
        g.rectangle('fill', x + Tema.px(12), y + cabecera + Tema.px(3), ancho - Tema.px(24), Tema.px(3))
    end
    local cx, cy = x + relleno + Tema.px(4), y + cabecera + relleno
    local intro = {
        soldados = string.format(
            'Se instruyen de %d en %d; la ciudad sigue pagando su sueldo',
            Simulacion.produccion.tanda.soldados,
            Simulacion.produccion.tanda.soldados
        ),
        municion = 'Va al polvorín de la ciudad; los ejércitos se la llevan al salir',
        taller = 'Lo que se repara solo cada día, o se paga para tenerlo ya',
    }
    g.setFont(texto)
    Tema.color('textoHudTenue')
    g.print(Tema.cortar(texto, intro[self.modo], cw), cx, cy)
    cy = cy + texto:getHeight() + Tema.px(10)
    for _, f in ipairs(filas) do
        f.dibujar(cx, cy, cw, f.alto)
        cy = cy + f.alto
    end
    cy = cy + Tema.px(8)
    if motivo then
        g.setFont(texto)
        Tema.color('rojoTexto')
        g.printf(motivo, cx, cy, cw, 'left')
    end
    cy = cy + math.max(1, lineasMotivo) * texto:getHeight() + Tema.px(12)
    local bh = Tema.px(44)
    if self.modo == 'taller' then
        local cerrar = { texto = 'Cerrar', tipo = 'secundario' }
        local anchoC = math.max(Tema.px(120), Tema.anchoBoton(cerrar))
        Tema.boton(cerrar, cx + cw - anchoC, cy, anchoC, bh)
        self:zona(cx + cw - anchoC, cy, anchoC, bh, { tipo = 'cancelar' })
        return
    end
    local producir = { texto = 'Producir', tipo = 'principal', activo = motivo == nil }
    local coste = self:coste()
    if coste.dinero > 0 then
        producir.precio = coste.dinero
    end
    local cancelar = { texto = 'Cancelar', tipo = 'secundario' }
    local anchoP = math.max(Tema.px(160), Tema.anchoBoton(producir))
    local anchoC = math.max(Tema.px(120), Tema.anchoBoton(cancelar))
    local px = cx + cw - anchoP
    local ccx = px - Tema.px(8) - anchoC
    Tema.boton(cancelar, ccx, cy, anchoC, bh)
    Tema.boton(producir, px, cy, anchoP, bh)
    self:zona(ccx, cy, anchoC, bh, { tipo = 'cancelar' })
    if producir.activo then
        self:zona(px, cy, anchoP, bh, { tipo = 'producir' })
    end
    self.botonProducir = { x = px, y = cy, w = anchoP, h = bh }
end

--- Clic. Devuelve nil si cayó fuera del panel; si no, 'cancelar', 'nada' o
-- { comandos = { … } } (lo que hay que mandar a la simulación).
function Fabrica:pulsar(x, y)
    local r = self.rect
    if not (r and Tema.dentro(x, y, r.x, r.y, r.w, r.h)) then
        return nil
    end
    for k = #self.zonas, 1, -1 do
        local z = self.zonas[k]
        if Tema.dentro(x, y, z.x, z.y, z.w, z.h) then
            local a = z.accion
            self.motivo = nil
            if a.tipo == 'cambiar' then
                local actual = self.cantidades[a.clave]
                -- De 1 a 10 con el primer paso de 10 (no 11).
                local nuevo = actual + a.paso
                if math.abs(a.paso) > 1 and actual % a.paso ~= 0 then
                    nuevo = a.paso > 0 and (math.floor(actual / a.paso) + 1) * a.paso
                        or math.floor(actual / -a.paso) * -a.paso
                end
                self.cantidades[a.clave] = math.max(0, nuevo)
                return 'nada'
            elseif a.tipo == 'maximo' then
                self.cantidades[a.clave] = a.valor
                return 'nada'
            elseif a.tipo == 'producir' then
                return { comandos = self:comandos() }
            elseif a.tipo == 'comando' then
                return { comandos = { a.comando } }
            end
            return a.tipo
        end
    end
    return 'nada'
end

Fabrica.TROPAS = TROPAS
Fabrica.MUNICIONES = MUNICIONES

return Fabrica
