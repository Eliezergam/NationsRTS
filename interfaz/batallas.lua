-- Batallas en curso: la lista de las batallas en las que pelea tu nación
-- (diseno/interfaz-militar.md, §5.9). Se abre con el botón de la barra de
-- abajo (o B), a la derecha bajo la barra superior. Cada fila dice dónde es,
-- cuántos días lleva, tu lado y el poder de cada bando (el rival, solo con
-- informe de exploradores: interfaz/inteligencia.lua), con «Defender» o
-- «Atacar» (según tu lado) e «Ir» (la cámara al sitio). Sin tope de filas: la
-- rueda del ratón desplaza la lista.
--
-- Solo lee `sim:batallasEnCurso`; `pulsar` devuelve la acción para main.lua.

local Tema = require('interfaz.tema')
local Acero = require('interfaz.acero')
local Inteligencia = require('interfaz.inteligencia')

local Batallas = {}
Batallas.__index = Batallas

function Batallas.nuevo()
    local self = setmetatable({}, Batallas)
    self.abierta = false
    self.zonas = {}
    self.rect = nil
    self.lista = nil -- { x, y, w, h } de la zona de filas
    self.desplazamiento = 0
    self.maximo = 0
    return self
end

--- Nombres de las naciones de un bando, separados por comas.
local function nombres(sim, naciones)
    local out = {}
    for _, nid in ipairs(naciones or {}) do
        local n = sim:nacion(nid)
        out[#out + 1] = n and n.nombre or '?'
    end
    return #out > 0 and table.concat(out, ', ') or 'nadie'
end

--- Dibuja la lista bajo la barra superior (`arriba`), con su borde derecho en
-- `derecha` (o a 16 px del borde de la pantalla). `nid`: la nación del jugador.
function Batallas:dibujar(sim, nid, arriba, derecha)
    self.zonas = {}
    self.rect = nil
    self.lista = nil
    if not self.abierta then
        return
    end
    local g = love.graphics
    local w, h = g.getDimensions()
    local lista = sim:batallasEnCurso(nid)
    local texto = Acero.fuente('cuerpo', 16)
    local negrita = Acero.fuente('cifra', 20)
    local ancho = Tema.px(Tema.compacta() and 420 or 480)
    local altoFila = Tema.px(104)
    local cabecera = Tema.px(50)
    local pie = Tema.px(12)
    local x = (derecha or (w - Tema.px(16))) - ancho
    -- Como mucho hasta encima de la barra de navegación.
    local altoMax = h - arriba - Tema.px(16 + 72 + 16)
    local altoLista = math.max(altoFila, #lista * altoFila)
    local alto = math.min(altoMax, cabecera + altoLista + pie)
    self.rect = { x = x, y = arriba, w = ancho, h = alto }
    local _, _, _, _, cierre = Acero.panel(x, arriba, ancho, alto, {
        titulo = 'Batallas en curso',
        subtitulo = #lista > 0 and tostring(#lista) or nil,
        cerrar = true,
    })
    if cierre then
        self.zonas[#self.zonas + 1] =
            { x = cierre.x, y = cierre.y, w = cierre.w, h = cierre.h, accion = { tipo = 'cerrar' } }
    end
    local relleno = Tema.px(12)
    local lx, ly = x + relleno, arriba + cabecera
    local lw, lh = ancho - relleno * 2, alto - cabecera - pie
    if #lista == 0 then
        g.setFont(texto)
        Tema.color('textoHudTenue')
        g.print('Ninguna: tu nación no pelea ahora', lx + Tema.px(4), ly + Tema.px(12))
        return
    end
    self.maximo = math.max(0, #lista * altoFila - lh)
    self.desplazamiento = math.max(0, math.min(self.maximo, self.desplazamiento))
    self.lista = { x = lx, y = ly, w = lw, h = lh }
    local anchoLista = lw - (self.maximo > 0 and Tema.px(12) or 0)
    local mx, my = love.mouse.getPosition()
    local sx, sy, sw, sh = g.getScissor()
    g.intersectScissor(lx, ly, lw, lh)
    local altoBoton = Tema.px(36)
    for k, b in ipairs(lista) do
        local fy = ly + (k - 1) * altoFila - self.desplazamiento
        if fy + altoFila > ly and fy < ly + lh then
            local encima = Tema.dentro(mx, my, lx, math.max(fy, ly), anchoLista, math.min(altoFila, ly + lh - fy))
            Acero.fila(lx, fy + Tema.px(2), anchoLista, altoFila - Tema.px(6), encima and 'hover' or 'normal')
            local defiendes = b.lado == 'defensor'
            Tema.color(defiendes and 'rojo' or 'amarillo')
            g.rectangle('fill', lx, fy + Tema.px(6), Tema.px(3), altoFila - Tema.px(14))
            local entrar = {
                texto = b.enEscena and 'Dentro' or (defiendes and 'Defender' or 'Atacar'),
                tipo = 'principal',
                activo = b.puedeEntrar and not b.enEscena,
            }
            local ir = { texto = 'Ir', tipo = 'secundario' }
            local anchoEntrar = math.max(Tema.px(88), Tema.anchoBoton(entrar, true))
            local anchoIr = math.max(Tema.px(44), Tema.anchoBoton(ir, true))
            local bx = lx + anchoLista - Tema.px(8) - anchoEntrar
            local ix = bx - Tema.px(6) - anchoIr
            local by = fy + math.floor((altoFila - altoBoton) / 2) - Tema.px(2)
            local tx = lx + Tema.px(14)
            local tw = ix - tx - Tema.px(8)
            local lugar = b.nombre:sub(1, 1):upper() .. b.nombre:sub(2)
            g.setFont(negrita)
            Tema.color('textoHud')
            g.print(Tema.cortar(negrita, lugar, tw), tx, fy + Tema.px(6))
            g.setFont(texto)
            local dia = string.format('Día %d · %s', b.dias + 1, defiendes and 'defiendes' or 'atacas')
            if b.decidido == 'sola' then
                dia = dia .. ' · se resuelve sola'
            end
            Tema.color(defiendes and 'rojoTexto' or 'amarillo')
            local yTexto = fy + Tema.px(6) + negrita:getHeight()
            g.print(Tema.cortar(texto, dia, tw), tx, yTexto)
            local suyo, tuyo = b.atacante, b.defensor
            if not defiendes then
                suyo, tuyo = tuyo, suyo
            end
            Tema.color('textoHudTenue')
            g.print(Tema.cortar(texto, 'Contra ' .. nombres(sim, suyo.naciones), tw), tx, yTexto + texto:getHeight())
            local rival = Inteligencia.poderRival(sim, nid, b, defiendes and 'atacante' or 'defensor')
            local poder = string.format('Tu poder %s · rival %s', Tema.numero(tuyo.poder), rival)
            g.print(Tema.cortar(texto, poder, tw), tx, yTexto + texto:getHeight() * 2)
            Tema.boton(ir, ix, by, anchoIr, altoBoton, true)
            self.zonas[#self.zonas + 1] = {
                x = ix,
                y = math.max(by, ly),
                w = anchoIr,
                h = math.min(altoBoton, ly + lh - by),
                accion = { tipo = 'ir', x = b.x, y = b.y },
            }
            Tema.boton(entrar, bx, by, anchoEntrar, altoBoton, true)
            if entrar.activo then
                self.zonas[#self.zonas + 1] = {
                    x = bx,
                    y = math.max(by, ly),
                    w = anchoEntrar,
                    h = math.min(altoBoton, ly + lh - by),
                    accion = { tipo = 'entrar', batalla = b.id },
                }
            end
        end
    end
    if sx then
        g.setScissor(sx, sy, sw, sh)
    else
        g.setScissor()
    end
    if self.maximo > 0 then
        Acero.desplazamiento(lx + lw - Tema.px(6), ly, lh, lh, #lista * altoFila, self.desplazamiento / self.maximo)
    end
end

--- Rueda sobre la lista: la desplaza. Devuelve true si la usó.
function Batallas:rueda(x, y, dy)
    local r = self.rect
    if not (r and self.abierta and Tema.dentro(x, y, r.x, r.y, r.w, r.h)) then
        return false
    end
    if self.maximo > 0 then
        self.desplazamiento = math.max(0, math.min(self.maximo, self.desplazamiento - dy * Tema.px(44)))
    end
    return true
end

--- Clic: nil si cayó fuera; si no, la acción ({ tipo = 'entrar', batalla },
-- { tipo = 'ir', x, y }, { tipo = 'cerrar' }) o { tipo = 'nada' }.
function Batallas:pulsar(x, y)
    local r = self.rect
    if not (r and Tema.dentro(x, y, r.x, r.y, r.w, r.h)) then
        return nil
    end
    for _, z in ipairs(self.zonas) do
        if Tema.dentro(x, y, z.x, z.y, z.w, z.h) then
            return z.accion
        end
    end
    return { tipo = 'nada' }
end

--- La acción del primer botón «Defender» o «Atacar» activo (para las capturas).
function Batallas:primeraEntrada()
    for _, z in ipairs(self.zonas) do
        if z.accion.tipo == 'entrar' then
            return z
        end
    end
    return nil
end

return Batallas
