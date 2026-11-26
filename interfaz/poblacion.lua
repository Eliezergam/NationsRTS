-- Ventana de la población de una ciudad propia (diseno/poblacion.md, «Para
-- Valeria»): la abre el botón «Población» del radial. Panel claro al centro,
-- como Fábrica o el envío, con dos columnas:
--   - izquierda: la gente por edades (niños, edad de trabajar, reclutables
--     de sus aptos, mayores), los soldados (en la ciudad, fuera y el total en
--     filas, cada uno con su nombre) y la vivienda usada contra su tope, con lo
--     que frena hoy los nacimientos;
--   - derecha: la pirámide por decenios (hombres a la izquierda, mujeres a
--     la derecha, la parte en filas en dorado) y lo del año en curso
--     (nacidos, muertos por causa y retirados).
-- Debajo, las reglas de natalidad de la nación: hoy solo se leen (la política
-- que las fije aún no existe, así que no hay botones).
--
-- Solo lee la simulación; `pulsar` solo dice si se cierra.

local Tema = require('interfaz.tema')
local Acero = require('interfaz.acero')
local Simulacion = require('mundo.simulacion')

local VentanaPoblacion = {}
VentanaPoblacion.__index = VentanaPoblacion

-- Medidas de diseño (a 1080p; `Tema.px` las escala).
local ANCHO = 880
local ANCHO_COMPACTO = 800
local ALTO_FILA = 30
local ALTO_PIRAMIDE = 22
local HUECO_COLUMNAS = 32

--- Habitantes de la demografía `d` entre las edades `desde` y `hasta` (ambos sexos).
local function habitantesEntre(d, desde, hasta)
    local total = 0
    for edad = desde, hasta do
        total = total + d.H[edad + 1] + d.M[edad + 1]
    end
    return total
end

--- Lo que la vista enseña de la población de la ciudad `c` (o nil si no
-- tiene demografía): lo de `sim:demografiaCiudad` más niños, edad de
-- trabajar, mayores, reclutables, soldados en la ciudad y fuera, y el tope
-- de la vivienda. Lo usan esta ventana y el pendón.
function VentanaPoblacion.desglose(sim, c)
    local d = c and c.demografia
    local r = d and sim:demografiaCiudad(c.id)
    if not r then
        return nil
    end
    local reglas = Simulacion.poblacion
    local viviendas = reglas.viviendas
    r.ninos = habitantesEntre(d, 0, reglas.trabajaMin - 1)
    r.enEdadDeTrabajar = habitantesEntre(d, reglas.trabajaMin, reglas.trabajaMax)
    r.mayores = habitantesEntre(d, reglas.trabajaMax + 1, reglas.edades - 1)
    r.reclutables = math.max(0, Simulacion.maximoSoldados(c, sim:inventarioCiudad(c.id)))
    r.enLaCiudad = c.soldados or 0
    r.fuera = math.max(0, r.enFilas - r.enLaCiudad)
    r.tope = c.radio * viviendas[math.max(1, math.min(#viviendas, c.nivel or 1))]
    local frena = {}
    if r.frena.vivienda then
        frena[#frena + 1] = 'ciudad llena'
    end
    if r.frena.hambre then
        frena[#frena + 1] = 'hambre'
    end
    if r.frena.sitiada then
        frena[#frena + 1] = 'sitiada'
    end
    r.textoFrena = #frena > 0 and ('Nacen menos: ' .. table.concat(frena, ' · ')) or nil
    return r
end

function VentanaPoblacion.nuevo(ciudad)
    local self = setmetatable({}, VentanaPoblacion)
    self.ciudad = ciudad.id
    self.nacion = ciudad.nacion
    self.zonas = {}
    self.rect = nil
    return self
end

--- Título de sección (el mismo del pendón y Fábrica); devuelve su alto.
local function titulo(texto, x, y, w)
    return Tema.tituloSeccion(texto, x, y, w) + Tema.px(8)
end

--- Fila dato-valor: etiqueta a la izquierda, valor en negrita a la derecha y
-- una línea punteada debajo. Devuelve su alto.
local function fila(x, y, w, etiqueta, valor, colorValor)
    local g = love.graphics
    local texto = Acero.fuente('cuerpo', 17)
    local negrita = Acero.fuente('cifra', 18)
    local alto = Tema.px(ALTO_FILA)
    local anchoValor = negrita:getWidth(valor)
    g.setFont(texto)
    Tema.color('textoHudTenue')
    g.print(
        Tema.cortar(texto, etiqueta, w - anchoValor - Tema.px(10)),
        x,
        math.floor(y + (alto - texto:getHeight()) / 2)
    )
    g.setFont(negrita)
    Tema.color(colorValor or 'textoHud')
    g.print(valor, x + w - anchoValor, math.floor(y + (alto - negrita:getHeight()) / 2))
    Tema.color('lineaOliva', 0.5)
    for px = x, x + w, 4 do
        g.rectangle('fill', px, y + alto - 1, 2, 1)
    end
    return alto
end

--- Línea de texto pequeña; devuelve su alto.
local function nota(x, y, w, texto, color)
    local fuente = Acero.fuente('etiqueta', 15)
    love.graphics.setFont(fuente)
    Tema.color(color or 'textoHudTenue')
    love.graphics.print(Tema.cortar(fuente, texto, w), x, y + Tema.px(4))
    return fuente:getHeight() + Tema.px(8)
end

--- Barra de la vivienda: etiqueta, «usada / tope» y la barra. Devuelve su alto.
local function barraVivienda(x, y, w, r)
    local g = love.graphics
    local texto = Acero.fuente('cuerpo', 17)
    local negrita = Acero.fuente('cifra', 18)
    local valor = string.format('%s / %s', Tema.numero(r.total), Tema.numero(r.tope))
    g.setFont(texto)
    Tema.color('textoHudTenue')
    g.print('Habitantes / plazas de vivienda', x, y)
    g.setFont(negrita)
    Tema.color('textoHud')
    g.print(valor, x + w - negrita:getWidth(valor), y)
    local by = y + negrita:getHeight() + Tema.px(4)
    local bh = Tema.px(12)
    local parte = math.max(0, math.min(1, r.ocupacion))
    Tema.color('olivaClaro')
    g.rectangle('fill', x, by, w, bh)
    local llena = r.ocupacion >= Simulacion.poblacion.viviendaLlena
    Tema.color(llena and 'amarilloDinero' or 'verdeGalon')
    g.rectangle('fill', x + 1, by + 1, math.floor((w - 2) * parte), bh - 2)
    Tema.color('lineaOliva')
    g.rectangle('line', x + 0.5, by + 0.5, w - 1, bh - 1)
    return by + bh + Tema.px(4) - y
end

--- Pirámide por decenios desde (x, y) con ancho `w`: una fila por decenio,
-- hombres hacia la izquierda y mujeres hacia la derecha del rótulo de edad;
-- el tramo en filas, en dorado junto al rótulo. Devuelve su alto.
local function piramide(x, y, w, decenios)
    local g = love.graphics
    local etiqueta = Acero.fuente('etiqueta', 14)
    local cabeza = Acero.fuente('cuerpo', 16)
    local hombres, mujeres, mayor = 0, 0, 1
    for _, dec in ipairs(decenios) do
        hombres = hombres + dec.hombres
        mujeres = mujeres + dec.mujeres
        mayor = math.max(mayor, dec.hombres, dec.mujeres)
    end
    local cy = y
    -- Cabecera: «Hombres 5 123» a la izquierda y «Mujeres 5 050» a la derecha.
    g.setFont(cabeza)
    Tema.color('textoHudTenue')
    g.print('Hombres ' .. Tema.numero(hombres), x, cy)
    local derecha = 'Mujeres ' .. Tema.numero(mujeres)
    g.print(derecha, x + w - cabeza:getWidth(derecha), cy)
    cy = cy + cabeza:getHeight() + Tema.px(6)
    local rotulo = Tema.px(60)
    local centro = x + math.floor(w / 2)
    local medio = math.floor((w - rotulo) / 2)
    local altoFila = Tema.px(ALTO_PIRAMIDE)
    local bh = altoFila - Tema.px(5)
    -- De arriba abajo, de los mayores a los niños (como una pirámide).
    for k = #decenios, 1, -1 do
        local dec = decenios[k]
        local by = cy + math.floor((altoFila - bh) / 2)
        local lados = {
            { total = dec.hombres, filas = dec.hombresEnFilas, signo = -1 },
            { total = dec.mujeres, filas = dec.mujeresEnFilas, signo = 1 },
        }
        for _, lado in ipairs(lados) do
            local largo = math.floor(medio * lado.total / mayor + 0.5)
            local largoFilas = math.floor(medio * lado.filas / mayor + 0.5)
            local interior = centro + lado.signo * math.floor(rotulo / 2)
            local bx = lado.signo < 0 and interior - largo or interior
            if largo > 0 then
                Tema.color('papel')
                g.rectangle('fill', bx, by, largo, bh)
                if largoFilas > 0 then
                    Tema.color('amarilloDinero')
                    local fx = lado.signo < 0 and interior - largoFilas or interior
                    g.rectangle('fill', fx, by, largoFilas, bh)
                end
                Tema.color('lineaOliva')
                g.rectangle('line', bx + 0.5, by + 0.5, largo - 1, bh - 1)
            end
        end
        local texto = string.format('%d–%d', dec.desde, dec.hasta)
        g.setFont(etiqueta)
        Tema.color('textoHud')
        g.print(
            texto,
            centro - math.floor(etiqueta:getWidth(texto) / 2),
            cy + math.floor((altoFila - etiqueta:getHeight()) / 2)
        )
        cy = cy + altoFila
    end
    -- Leyenda: civiles en gris claro y en filas en dorado.
    cy = cy + Tema.px(6)
    local lado = Tema.px(12)
    local lx = x
    for _, par in ipairs({ { 'papel', 'Civiles' }, { 'amarilloDinero', 'En filas' } }) do
        Tema.color(par[1])
        g.rectangle('fill', lx, cy + Tema.px(2), lado, lado)
        Tema.color('lineaOliva')
        g.rectangle('line', lx + 0.5, cy + Tema.px(2) + 0.5, lado - 1, lado - 1)
        g.setFont(etiqueta)
        Tema.color('textoHudTenue')
        g.print(par[2], lx + lado + Tema.px(6), cy)
        lx = lx + lado + Tema.px(6) + etiqueta:getWidth(par[2]) + Tema.px(18)
    end
    cy = cy + etiqueta:getHeight() + Tema.px(4)
    return cy - y
end

--- Pone una zona que se puede pulsar.
function VentanaPoblacion:zona(x, y, w, h, accion)
    self.zonas[#self.zonas + 1] = { x = x, y = y, w = w, h = h, accion = accion }
end

--- Dibuja la ventana en el centro de la pantalla. Si la ciudad ya no es
-- tuya, devuelve false (main.lua la cierra).
function VentanaPoblacion:dibujar(sim)
    local c = sim.estado.ciudades[self.ciudad]
    if not c or c.nacion ~= self.nacion then
        return false
    end
    local r = VentanaPoblacion.desglose(sim, c)
    if not r then
        return false
    end
    Tema.modoClaro = true
    local ok, fallo = pcall(self.dibujarClaro, self, sim, c, r)
    Tema.modoClaro = false
    if not ok then
        error(fallo, 0)
    end
    return true
end

--- Columna izquierda: gente, soldados y vivienda. Devuelve el alto.
local function columnaGente(x, y, w, r)
    local reglas = Simulacion.poblacion
    local cy = y
    cy = cy + titulo('GENTE', x, cy, w)
    cy = cy + fila(x, cy, w, string.format('Niños (0 a %d años)', reglas.trabajaMin - 1), Tema.numero(r.ninos))
    cy = cy
        + fila(
            x,
            cy,
            w,
            string.format('Edad de trabajar (%d a %d)', reglas.trabajaMin, reglas.trabajaMax),
            Tema.numero(r.enEdadDeTrabajar)
        )
    cy = cy
        + fila(
            x,
            cy,
            w,
            string.format('Reclutables (%d a %d)', reglas.edadMin, reglas.edadMax),
            string.format('%s de %s aptos', Tema.numero(r.reclutables), Tema.numero(r.aptos)),
            r.reclutables > 0 and 'textoHud' or 'rojoTexto'
        )
    cy = cy + fila(x, cy, w, string.format('Mayores (%d o más)', reglas.trabajaMax + 1), Tema.numero(r.mayores))
    cy = cy + Tema.px(14)
    cy = cy + titulo('SOLDADOS', x, cy, w)
    cy = cy + fila(x, cy, w, 'En la ciudad (guarnición)', Tema.numero(r.enLaCiudad))
    cy = cy + fila(x, cy, w, 'Fuera, heridos o en instrucción', Tema.numero(r.fuera))
    cy = cy + fila(x, cy, w, 'Total en filas (de esta ciudad)', Tema.numero(r.enFilas), 'amarillo')
    cy = cy + Tema.px(14)
    cy = cy + titulo('VIVIENDA', x, cy, w)
    cy = cy + barraVivienda(x, cy, w, r)
    cy = cy + nota(x, cy, w, r.textoFrena or 'Nada frena hoy los nacimientos', r.textoFrena and 'rojoTexto' or nil)
    return cy - y
end

--- Columna derecha: pirámide y el año en curso. Devuelve el alto.
local function columnaAnio(x, y, w, r, anio)
    local cy = y
    cy = cy + titulo('PIRÁMIDE POR EDADES', x, cy, w)
    cy = cy + piramide(x, cy, w, r.decenios)
    cy = cy + Tema.px(10)
    cy = cy + titulo(string.format('AÑO %s, EN CURSO', Tema.numero(anio)), x, cy, w)
    local a = r.anio
    local muertos = a.natural + a.hambre + a.vejez + a.combate
    cy = cy + fila(x, cy, w, 'Nacidos', Tema.numero(a.nacidos), 'verde')
    cy = cy + fila(x, cy, w, 'Muertos', Tema.numero(muertos), muertos > a.nacidos and 'rojoTexto' or nil)
    cy = cy
        + nota(
            x,
            cy,
            w,
            string.format(
                'natural %s · hambre %s · vejez %s · combate %s',
                Tema.numero(a.natural),
                Tema.numero(a.hambre),
                Tema.numero(a.vejez),
                Tema.numero(a.combate)
            )
        )
    cy = cy + fila(x, cy, w, 'Veteranos retirados', Tema.numero(a.retirados))
    return cy - y
end

--- Cuerpo de la ventana bajo la cabecera, desde (cx, cy) con ancho `cw`:
-- intro, las dos columnas, la política y «Cerrar». Devuelve la y final.
function VentanaPoblacion:cuerpo(sim, r, n, cx, cy, cw)
    local g = love.graphics
    local texto = Acero.fuente('cuerpo')
    local hueco = Tema.px(HUECO_COLUMNAS)
    local columna = math.floor((cw - hueco) / 2)
    local anio = Simulacion.anioDelJuego(math.max(1, sim.estado.dia))
    g.setFont(texto)
    Tema.color('textoHudTenue')
    local intro = string.format(
        'Un año son %d días. Los soldados salen de la gente: cada caído es un habitante menos',
        Simulacion.poblacion.anio
    )
    g.print(Tema.cortar(texto, intro, cw), cx, cy)
    cy = cy + texto:getHeight() + Tema.px(14)
    local altoIzquierda = columnaGente(cx, cy, columna, r)
    local altoDerecha = columnaAnio(cx + columna + hueco, cy, columna, r, anio)
    cy = cy + math.max(altoIzquierda, altoDerecha) + Tema.px(14)
    -- Reglas de natalidad de la nación: el hueco de la futura política.
    cy = cy + titulo('POLÍTICA DE NATALIDAD', cx, cy, cw)
    local politica = n and n.natalidad or 1
    local textoPolitica = politica == 1 and 'sin reglas (×1)' or string.format('×%s', Tema.decimal(politica))
    cy = cy + fila(cx, cy, cw, 'Hijos por pareja', textoPolitica)
    cy = cy + nota(cx, cy, cw, 'La fijará la política de la nación cuando exista; hoy nadie la limita')
    cy = cy + Tema.px(10)
    local bh = Tema.px(44)
    local cerrar = { texto = 'Cerrar', tipo = 'secundario' }
    local anchoC = math.max(Tema.px(140), Tema.anchoBoton(cerrar))
    Tema.boton(cerrar, cx + cw - anchoC, cy, anchoC, bh)
    self:zona(cx + cw - anchoC, cy, anchoC, bh, 'cerrar')
    return cy + bh
end

function VentanaPoblacion:dibujarClaro(sim, c, r)
    local g = love.graphics
    local w, h = g.getDimensions()
    local relleno = Tema.px(20)
    local ancho = Tema.px(Tema.compacta() and ANCHO_COMPACTO or ANCHO)
    local cabecera = Tema.px(50)
    local cw = ancho - relleno * 2
    local n = sim:nacion(self.nacion)
    local arriba = cabecera + Tema.px(14)
    -- Primero se mide: el cuerpo se dibuja sin escribir color para saber su alto.
    g.setColorMask(false, false, false, false)
    local ok, fin = pcall(self.cuerpo, self, sim, r, n, 0, arriba, cw)
    g.setColorMask(true, true, true, true)
    if not ok then
        error(fin, 0)
    end
    local alto = fin + relleno
    self.zonas = {}
    local x, y = math.floor((w - ancho) / 2), math.max(Tema.px(8), math.floor((h - alto) / 2))
    self.rect = { x = x, y = y, w = ancho, h = alto }
    local _, _, _, _, cierre = Acero.panel(x, y, ancho, alto, {
        titulo = 'Población de ' .. (c.nombre or 'la ciudad'),
        subtitulo = string.format(
            '%s habitantes · año %s',
            Tema.numero(r.total),
            Tema.numero(Simulacion.anioDelJuego(math.max(1, sim.estado.dia)))
        ),
        cerrar = true,
    })
    if cierre then
        self:zona(cierre.x, cierre.y, cierre.w, cierre.h, 'cerrar')
    end
    if n then
        Tema.color(n.color)
        g.rectangle('fill', x + Tema.px(12), y + cabecera + Tema.px(3), ancho - Tema.px(24), Tema.px(3))
    end
    self:cuerpo(sim, r, n, x + relleno, y + arriba, cw)
end

--- Clic. Devuelve nil si cayó fuera de la ventana; si no, 'cerrar' o 'nada'.
function VentanaPoblacion:pulsar(x, y)
    local r = self.rect
    if not (r and Tema.dentro(x, y, r.x, r.y, r.w, r.h)) then
        return nil
    end
    for k = #self.zonas, 1, -1 do
        local z = self.zonas[k]
        if Tema.dentro(x, y, z.x, z.y, z.w, z.h) then
            return z.accion
        end
    end
    return 'nada'
end

return VentanaPoblacion
