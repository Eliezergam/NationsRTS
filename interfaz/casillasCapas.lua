-- Casillas de capas del mapa estratégico (zoom lejano, mundo/capas.lua): a la
-- izquierda, bajo la columna, como en Warpath (diseno/referencias-warpath/
-- zoom_5.5.jpg). Cada casilla muestra u oculta una capa; «Territorios» es lo
-- mismo que la tecla T y el botón Territorio de la columna.

local Tema = require('interfaz.tema')
local Acero = require('interfaz.acero')

local CasillasCapas = {}
CasillasCapas.__index = CasillasCapas

CasillasCapas.FILAS = {
    { clave = 'territorio', texto = 'Territorios' },
    { clave = 'ejercitos', texto = 'Ejércitos' },
    { clave = 'yacimientos', texto = 'Yacimientos' },
    { clave = 'batallas', texto = 'Batallas' },
}

function CasillasCapas.nuevo()
    return setmetatable({ zonas = {} }, CasillasCapas)
end

--- Dibuja las casillas desde (x, y). `estado[clave]` dice si cada una está
-- marcada; `alfa`, para el fundido al entrar en el mapa estratégico.
function CasillasCapas:dibujar(x, y, estado, alfa)
    local g = love.graphics
    self.zonas = {}
    local lado = math.floor(Tema.px(26))
    local hueco = math.floor(Tema.px(14))
    local fuente = Acero.fuente('cuerpo', 18)
    for _, fila in ipairs(CasillasCapas.FILAS) do
        local marcada = estado[fila.clave]
        Tema.color('olivaNegro', 0.8 * alfa)
        g.rectangle('fill', x, y, lado, lado)
        Tema.color('hormigon', alfa)
        g.setLineWidth(math.max(1, Tema.px(2)))
        g.rectangle('line', x + 0.5, y + 0.5, lado - 1, lado - 1)
        if marcada then
            -- La marca, en dorado.
            Tema.color('amarillo', alfa)
            g.setLineWidth(math.max(2, Tema.px(4)))
            g.line(x + lado * 0.2, y + lado * 0.52, x + lado * 0.42, y + lado * 0.74, x + lado * 0.8, y + lado * 0.26)
        end
        g.setLineWidth(1)
        local tx = x + lado + math.floor(Tema.px(12))
        local ty = math.floor(y + (lado - fuente:getHeight()) / 2)
        Acero.textoContorno(fuente, fila.texto, tx, ty, 'textoHud', nil, alfa)
        local ancho = lado + Tema.px(12) + fuente:getWidth(fila.texto)
        self.zonas[#self.zonas + 1] = { x = x, y = y, w = ancho, h = lado, clave = fila.clave }
        y = y + lado + hueco
    end
    g.setColor(1, 1, 1, 1)
end

--- Clic: la clave de la casilla pulsada, o nil.
function CasillasCapas:pulsar(x, y)
    for _, z in ipairs(self.zonas) do
        if Tema.dentro(x, y, z.x, z.y, z.w, z.h) then
            return z.clave
        end
    end
    return nil
end

--- Se deja de dibujar (fuera del mapa estratégico): sin zonas de clic.
function CasillasCapas:ocultar()
    self.zonas = {}
end

return CasillasCapas
