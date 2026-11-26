-- Explorar: el panel para mandar exploradores a un sitio o a un ejército
-- ajeno (modo jugador). Se elige desde qué sitio propio salen (el más
-- cercano por defecto, con ‹ y ›) y se ve lo que cuesta y cuándo llegan. Al
-- llegar, la simulación guarda un informe (poder, tropas, defensas y vida)
-- que la interfaz enseña con su antigüedad (interfaz/inteligencia.lua).
--
-- Solo lee la simulación; la orden la manda main.lua con el comando
-- `explorar` (`comando`). Si la simulación aún no lo tiene, el botón queda
-- apagado con el motivo.

local Tema = require('interfaz.tema')
local Acero = require('interfaz.acero')
local Simulacion = require('mundo.simulacion')

local Explorar = {}
Explorar.__index = Explorar

local NOMBRE_RECURSO = { metal = 'metal', petroleo = 'petróleo', comida = 'comida', dinero = 'dinero', oro = 'oro' }

--- Distancia (px de mundo) como texto: «12,4 km» o «350 m» (10 px = 1 m).
function Explorar.textoDistancia(px)
    local metros = px / 10
    if metros >= 1000 then
        return (string.format('%.1f km', metros / 1000):gsub('%.', ','))
    end
    return string.format('%d m', math.floor(metros / 10 + 0.5) * 10)
end

--- Sitios propios de `nid` desde donde pueden salir exploradores, del más
-- cercano a (x, y) al más lejano: ciudades e instalaciones terminadas (sin
-- banderas, que no tienen gente).
function Explorar.origenes(sim, nid, x, y)
    local lista = {}
    for _, s in ipairs(sim:sitiosDe(nid)) do
        local terminado = sim.estado.ciudades[s.id] or ((s.progreso or 0) >= 1 and s.tipo ~= 'bandera')
        if terminado then
            lista[#lista + 1] = { sitio = s, d = math.sqrt((s.x - x) ^ 2 + (s.y - y) ^ 2) }
        end
    end
    table.sort(lista, function(a, b)
        if a.d ~= b.d then
            return a.d < b.d
        end
        return tostring(a.sitio.id) < tostring(b.sitio.id)
    end)
    return lista
end

--- Abre el panel: `nid` explora `objetivo` = { id, x, y, nombre } (un sitio
-- o un grupo ajeno).
function Explorar.nuevo(sim, nid, objetivo)
    local self = setmetatable({}, Explorar)
    self.nacion = nid
    self.objetivo = objetivo
    self.origenes = Explorar.origenes(sim, nid, objetivo.x, objetivo.y)
    self.indice = 1
    self.zonas = {}
    self.motivo = nil
    return self
end

--- El sitio elegido de salida (y su distancia), o nil.
function Explorar:origen()
    local o = self.origenes[self.indice]
    return o and o.sitio, o and o.d
end

--- Coste de la exploración como texto: «40 dinero» o «10 metal · 5 petróleo».
function Explorar.textoCoste(coste)
    if type(coste) == 'number' then
        return Tema.numero(coste) .. ' dinero'
    end
    if type(coste) ~= 'table' then
        return '—'
    end
    local partes = {}
    for _, recurso in ipairs({ 'dinero', 'metal', 'petroleo', 'comida', 'oro' }) do
        if (coste[recurso] or 0) > 0 then
            partes[#partes + 1] = Tema.numero(coste[recurso]) .. ' ' .. NOMBRE_RECURSO[recurso]
        end
    end
    return #partes > 0 and table.concat(partes, ' · ') or 'gratis'
end

--- Días que tardan en llegar desde el origen (en línea recta, a la
-- velocidad de los exploradores), o nil si no se sabe.
function Explorar:dias()
    local _, d = self:origen()
    local reglas = Simulacion.exploracion
    local velocidad = reglas and reglas.velocidad
    if not (d and velocidad and velocidad > 0) then
        return nil
    end
    return math.max(1, math.ceil(d / velocidad))
end

--- Por qué no se puede mandar, o nil.
function Explorar:motivoPrevio()
    if not Simulacion.exploracion then
        return 'La simulación aún no manda exploradores'
    end
    if not self:origen() then
        return 'No tienes ningún sitio desde donde salir'
    end
    return nil
end

function Explorar:dibujar(sim)
    Tema.modoClaro = true
    local ok, fallo = pcall(self.dibujarClaro, self, sim)
    Tema.modoClaro = false
    if not ok then
        error(fallo, 0)
    end
end

function Explorar:dibujarClaro(sim)
    local g = love.graphics
    local w, h = g.getDimensions()
    self.zonas = {}
    local texto = Acero.fuente('cuerpo')
    local negrita = Acero.fuente('cifra')
    local relleno = Tema.px(16)
    local ancho = Tema.px(Tema.compacta() and 480 or 540)
    local cabecera = Tema.px(50)
    local fila = Tema.px(44)
    local alto = cabecera + relleno + fila * 4 + texto:getHeight() * 2 + Tema.px(12) + Tema.px(44) + relleno
    local x, y = math.floor((w - ancho) / 2), math.floor((h - alto) / 2)
    self.rect = { x = x, y = y, w = ancho, h = alto }
    local _, _, _, _, cierre =
        Acero.panel(x, y, ancho, alto, { titulo = 'Explorar ' .. (self.objetivo.nombre or ''), cerrar = true })
    if cierre then
        self.zonas[#self.zonas + 1] = { x = cierre.x, y = cierre.y, w = cierre.w, h = cierre.h, accion = 'cancelar' }
    end
    local n = sim:nacion(self.nacion)
    if n then
        Tema.color(n.color)
        g.rectangle('fill', x + Tema.px(12), y + cabecera + Tema.px(3), ancho - Tema.px(24), Tema.px(3))
    end
    local cx, cy = x + relleno + Tema.px(4), y + cabecera + relleno
    local cw = ancho - relleno * 2 - Tema.px(8)
    local function linea(etiqueta, valor, color)
        g.setFont(texto)
        Tema.color('textoHudTenue')
        g.print(etiqueta, cx, cy + math.floor((fila - texto:getHeight()) / 2))
        g.setFont(negrita)
        Tema.color(color or 'textoHud')
        local v = Tema.cortar(negrita, valor, cw - texto:getWidth(etiqueta) - Tema.px(12))
        g.print(v, cx + cw - negrita:getWidth(v), cy + math.floor((fila - negrita:getHeight()) / 2))
        Tema.color('lineaOliva')
        g.rectangle('fill', cx, cy + fila - 1, cw, 1)
        cy = cy + fila
    end
    -- Desde: ‹ nombre ›.
    local origen, distancia = self:origen()
    local lado = Tema.px(36)
    g.setFont(texto)
    Tema.color('textoHudTenue')
    g.print('Salen desde', cx, cy + math.floor((fila - texto:getHeight()) / 2))
    local by = cy + math.floor((fila - lado) / 2)
    local derecha = cx + cw - lado
    local izquierda = cx + texto:getWidth('Salen desde') + Tema.px(16)
    local varios = #self.origenes > 1
    Tema.boton({ texto = '‹', tipo = 'oscuro', activo = varios }, izquierda, by, lado, lado, true)
    Tema.boton({ texto = '›', tipo = 'oscuro', activo = varios }, derecha, by, lado, lado, true)
    if varios then
        self.zonas[#self.zonas + 1] = { x = izquierda, y = by, w = lado, h = lado, accion = 'anterior' }
        self.zonas[#self.zonas + 1] = { x = derecha, y = by, w = lado, h = lado, accion = 'siguiente' }
    end
    local nombreOrigen = origen and (origen.nombre or Simulacion.nombreInstalacion(sim, origen)) or 'ninguno'
    g.setFont(negrita)
    Tema.color('textoHud')
    local libre = derecha - izquierda - lado - Tema.px(16)
    local v = Tema.cortar(negrita, nombreOrigen, libre)
    g.print(
        v,
        izquierda + lado + math.floor((libre + Tema.px(16) - negrita:getWidth(v)) / 2),
        by + math.floor((lado - negrita:getHeight()) / 2)
    )
    Tema.color('lineaOliva')
    g.rectangle('fill', cx, cy + fila - 1, cw, 1)
    cy = cy + fila
    linea('Distancia', distancia and Explorar.textoDistancia(distancia) or '—')
    local reglas = Simulacion.exploracion
    linea('Coste', reglas and Explorar.textoCoste(reglas.coste) or '—', 'amarillo')
    local dias = self:dias()
    linea('Llegan en', dias and string.format('%d %s', dias, dias == 1 and 'día' or 'días') or '—')
    local motivo = self.motivo or self:motivoPrevio()
    if motivo then
        g.setFont(texto)
        Tema.color('rojoTexto')
        g.printf(motivo, cx, cy + Tema.px(4), cw, 'left')
    else
        g.setFont(texto)
        Tema.color('textoHudTenue')
        g.printf('Al llegar traen su poder, sus tropas y sus defensas de ese día.', cx, cy + Tema.px(4), cw, 'left')
    end
    cy = cy + texto:getHeight() * 2 + Tema.px(12)
    local mandar = { texto = 'Enviar exploradores', tipo = 'principal', activo = self:motivoPrevio() == nil }
    local cancelar = { texto = 'Cancelar', tipo = 'secundario' }
    local anchoM = math.max(Tema.px(160), Tema.anchoBoton(mandar))
    local anchoC = math.max(Tema.px(120), Tema.anchoBoton(cancelar))
    local bh = Tema.px(44)
    local mx = cx + cw - anchoM
    local ccx = mx - Tema.px(8) - anchoC
    Tema.boton(cancelar, ccx, cy, anchoC, bh)
    Tema.boton(mandar, mx, cy, anchoM, bh)
    self.zonas[#self.zonas + 1] = { x = ccx, y = cy, w = anchoC, h = bh, accion = 'cancelar' }
    if mandar.activo then
        self.zonas[#self.zonas + 1] = { x = mx, y = cy, w = anchoM, h = bh, accion = 'enviar' }
    end
end

--- Clic: nil si cayó fuera; si no, 'enviar', 'cancelar' o 'nada' (‹ y › se aplican aquí).
function Explorar:pulsar(x, y)
    local r = self.rect
    if not (r and Tema.dentro(x, y, r.x, r.y, r.w, r.h)) then
        return nil
    end
    for _, z in ipairs(self.zonas) do
        if Tema.dentro(x, y, z.x, z.y, z.w, z.h) then
            if z.accion == 'anterior' or z.accion == 'siguiente' then
                local n = #self.origenes
                local paso = z.accion == 'anterior' and -1 or 1
                self.indice = (self.indice - 1 + paso) % n + 1
                self.motivo = nil
                return 'nada'
            end
            return z.accion
        end
    end
    return 'nada'
end

--- El comando `explorar` con lo elegido.
function Explorar:comando()
    local origen = self:origen()
    return {
        tipo = 'explorar',
        nacion = self.nacion,
        desde = origen and origen.id,
        objetivo = self.objetivo.id,
    }
end

return Explorar
