--- Líderes y generales: presidente y generales de cada nación, quién manda cada grupo y la ficha del ejército.
--
-- Cada nación tiene su presidente (`n.lider`) y generales. Todo grupo que sale a
-- atacar lo manda un líder libre: el presidente si está libre y, si no, el
-- primer general libre; si no hay ninguno, se nombra un general nuevo (fase 1:
-- sin coste ni sueldo). Un líder manda un solo grupo a la vez y queda libre
-- cuando su grupo desaparece (llega a casa, toma el sitio o lo aniquilan).
-- `n.gobernante` sigue siendo el presidente para la diplomacia y la economía.
--
-- Módulo de `mundo/simulacion.lua`: `Lideres.instalar(Simulacion)` cuelga sus
-- funciones y `Simulacion.reglasLideres` de la clase, así que la API pública no
-- cambia. Diseño en diseno/ejercitos-en-el-mapa.md. Solo datos y sin LÖVE.

local Ruido = require('mundo.ruido')
local Ayudas = require('mundo.simulacion.ayudas')
local Nombres = require('mundo.simulacion.nombres')

local ordenadas = Ayudas.ordenadas
local tropasVacias = Ayudas.tropasVacias

local Lideres = {}

-- Se fija en `instalar`: la clase, para `Simulacion.poder`, `Simulacion.colorNacion`...
local Simulacion

--- Reglas de los líderes: herencia del carácter, rangos y umbrales de la ficha.
Lideres.reglas = {
    herencia = 0.5, -- parte del carácter de un general que viene de su presidente
    -- Rango de un general según sus victorias (el presidente es siempre presidente).
    rangos = {
        { victorias = 8, nombre = 'Mariscal', corto = 'Mcal.' },
        { victorias = 3, nombre = 'General', corto = 'Gral.' },
        { victorias = 0, nombre = 'Coronel', corto = 'Cnel.' },
    },
    caracterAlto = 0.7, -- desde aquí, la agresividad o la prudencia se nota en la ficha
    caracterBajo = 0.35, -- hasta aquí, se nota lo contrario
}

--- Id de un líder: 'l:<nación>:<k>'; k = 0 es el presidente y los generales se
-- cuentan desde 1 dentro de su nación, así el id y el nombre no dependen del
-- orden en que se registran las zonas.
local function idLider(nid, k)
    return 'l:' .. nid .. ':' .. k
end

--- Número estable a partir de un texto (el id de una nación) para `Ruido.hash`.
local function numeroDe(texto)
    local h = 0
    for k = 1, #texto do
        h = (h * 31 + texto:byte(k)) % 1000003
    end
    return h
end

--- Elige de la lista común más la de su orden político.
local function elegirNombre(azar, comunes, propios)
    local k = math.floor(azar(1, #comunes + #propios + 0.99))
    if k <= #comunes then
        return comunes[k]
    end
    return propios[k - #comunes]
end

--- Da a la nación su presidente como líder (si no lo tiene ya).
function Lideres:nombrarPresidente(n)
    local e = self.estado
    local id = idLider(n.id, 0)
    if not e.lideres[id] then
        e.lideres[id] = {
            id = id,
            nacion = n.id,
            presidente = true,
            nombre = n.gobernante.nombre,
            agresividad = n.gobernante.agresividad,
            prudencia = n.gobernante.prudencia,
            victorias = 0,
            derrotas = 0,
            estado = 'libre',
            desde = e.dia,
        }
    end
    n.lider = id
    n.siguienteGeneral = n.siguienteGeneral or 1
    return e.lideres[id]
end

--- Nombra un general nuevo en la nación `nid`, sin coste (fase 1). Su carácter
-- hereda en parte el del presidente que lo nombra.
function Lideres:nombrarGeneral(nid)
    local e = self.estado
    local n = e.naciones[nid]
    local presidente = e.lideres[n.lider]
    local k = n.siguienteGeneral
    n.siguienteGeneral = k + 1
    local azar = Ruido.azar(Ruido.hash(e.semilla, numeroDe(nid), k, 73))
    local nombre = elegirNombre(azar, Nombres.nombres, Nombres.nombresOrden[n.orden] or {})
    local apellido = elegirNombre(azar, Nombres.apellidos, Nombres.apellidosOrden[n.orden] or {})
    local herencia = Simulacion.reglasLideres.herencia
    local id = idLider(nid, k)
    e.lideres[id] = {
        id = id,
        nacion = nid,
        nombre = nombre .. ' ' .. apellido,
        agresividad = herencia * presidente.agresividad + (1 - herencia) * azar(0.1, 1),
        prudencia = herencia * presidente.prudencia + (1 - herencia) * azar(0.1, 1),
        victorias = 0,
        derrotas = 0,
        estado = 'libre',
        desde = e.dia,
    }
    return e.lideres[id]
end

--- Si el grupo que mandaba `l` ya no existe (o ya no es suyo), queda libre.
local function soltarSiAcabo(e, l)
    if l.estado ~= 'campo' then
        return
    end
    local g = l.ejercito and e.grupos[l.ejercito]
    if not g or g.lider ~= l.id then
        l.estado = 'libre'
        l.ejercito = nil
        l.desde = e.dia
    end
end

--- Deja libres a los líderes cuyo grupo ya no está (al final de cada día).
function Lideres:liberarLideres()
    local e = self.estado
    for _, id in ipairs(ordenadas(e.lideres)) do
        soltarSiAcabo(e, e.lideres[id])
    end
end

--- Primer líder libre de la nación: el presidente y luego los generales por
-- orden de nombramiento. Nil si todos están en campaña.
function Lideres:liderLibre(nid)
    local e = self.estado
    local n = e.naciones[nid]
    for k = 0, (n.siguienteGeneral or 1) - 1 do
        local l = e.lideres[idLider(nid, k)]
        if l then
            soltarSiAcabo(e, l)
            if l.estado == 'libre' then
                return l
            end
        end
    end
    return nil
end

--- Líder que mandará un grupo de ataque de `nid`: `liderId` si lo pide quien
-- manda (debe ser suyo y estar libre) o el primero libre; si no hay ninguno,
-- se nombra un general. Nil si el pedido no vale.
function Lideres:liderParaSalir(nid, liderId)
    local e = self.estado
    if liderId then
        local l = e.lideres[liderId]
        if not l or l.nacion ~= nid then
            return nil
        end
        soltarSiAcabo(e, l)
        return l.estado == 'libre' and l or nil
    end
    return self:liderLibre(nid) or self:nombrarGeneral(nid)
end

-- Consultas para la vista (la ficha del ejército) ---------------------------------------------

--- Líder con ese id, o nil.
function Lideres:lider(id)
    return id and self.estado.lideres[id]
end

--- Líder que manda el grupo `g`, o nil (convoyes de obra, entregas, refuerzos).
function Lideres:liderDe(g)
    return g.lider and self.estado.lideres[g.lider]
end

--- ¿Se dibuja como ejército (estandarte con líder y poder) o como convoy?
function Lideres.esEjercito(g)
    return g.lider ~= nil
end

--- Líderes de una nación: el presidente primero y luego los generales por
-- orden de nombramiento.
function Lideres:lideresDe(nid)
    local e = self.estado
    local n = e.naciones[nid]
    local out = {}
    for k = 0, (n and n.siguienteGeneral or 1) - 1 do
        local l = e.lideres[idLider(nid, k)]
        if l then
            out[#out + 1] = l
        end
    end
    return out
end

--- Rango de un líder: nombre largo y abreviado ('General', 'Gral.').
function Lideres.rangoLider(l)
    if l.presidente then
        return 'Presidente', 'Pdte.'
    end
    for _, r in ipairs(Simulacion.reglasLideres.rangos) do
        if l.victorias >= r.victorias then
            return r.nombre, r.corto
        end
    end
end

--- Nombre con el rango abreviado, para la etiqueta: 'Gral. Mira Oriel'.
function Lideres.etiquetaLider(l)
    local _, corto = Simulacion.rangoLider(l)
    return corto .. ' ' .. l.nombre
end

--- Carácter a grandes rasgos: 'agresivo y prudente', 'temerario', 'equilibrado'...
function Lideres.caracterLider(l)
    local reglas = Simulacion.reglasLideres
    local rasgos = {}
    if l.agresividad >= reglas.caracterAlto then
        rasgos[#rasgos + 1] = 'agresivo'
    elseif l.agresividad <= reglas.caracterBajo then
        rasgos[#rasgos + 1] = 'tranquilo'
    end
    if l.prudencia >= reglas.caracterAlto then
        rasgos[#rasgos + 1] = 'prudente'
    elseif l.prudencia <= reglas.caracterBajo then
        rasgos[#rasgos + 1] = 'temerario'
    end
    if #rasgos == 0 then
        return 'equilibrado'
    end
    return table.concat(rasgos, ' y ')
end

--- Lo que lleva un grupo: sanos y heridos de cada tropa, y los sanos de
-- cada modelo de vehículo (`lanzacohetesPor`: modelo -> cantidad).
function Lideres.composicion(g)
    local heridos = g.heridos or tropasVacias()
    return {
        soldados = g.soldados,
        lanzacohetes = g.lanzacohetes or 0,
        lanzacohetesPor = Simulacion.Armamento.porModelo(g, 'lanzacohetes'),
        heridos = { soldados = heridos.soldados, lanzacohetes = heridos.lanzacohetes },
    }
end

--- Todo lo que muestra la ficha de un grupo, visto por la nación `mira`
-- (nil: observador, lo ve todo). La composición y la munición solo las ve su
-- dueño: para los demás son nil («desconocida») hasta que haya exploradores.
-- Devuelve nil si el grupo no existe.
function Lideres:fichaGrupo(gid, mira)
    local e = self.estado
    local g = e.grupos[gid]
    if not g then
        return nil
    end
    local n = e.naciones[g.nacion]
    local poder = Simulacion.poder(g)
    local ficha = {
        id = g.id,
        nacion = g.nacion,
        nombreNacion = n and n.nombre,
        color = Simulacion.colorNacion(g.nacion),
        ejercito = Simulacion.esEjercito(g),
        mision = g.mision,
        -- La bandera que guarnece (o hacia la que va de guarnición), o nil.
        bandera = g.mision == 'guarnicion' and g.objetivo or nil,
        retirada = g.retirada == true,
        poder = poder,
        poderRedondeado = Simulacion.poderRedondeado(poder),
        batalla = g.batalla, -- id de la batalla en la que pelea, o nil
        carga = type(g.carga) == 'number' and g.carga or nil, -- lo que lleva un recolector
        tipoCarga = g.tipoCarga,
        capacidad = g.tipoCarga and Simulacion.capacidad(g) or nil,
    }
    local l = self:liderDe(g)
    if l then
        local rango = Simulacion.rangoLider(l)
        ficha.lider = {
            id = l.id,
            nombre = l.nombre,
            rango = rango,
            etiqueta = Simulacion.etiquetaLider(l),
            presidente = l.presidente == true,
            caracter = Simulacion.caracterLider(l),
            victorias = l.victorias,
            derrotas = l.derrotas,
        }
    end
    if mira == nil or mira == g.nacion then
        ficha.composicion = Simulacion.composicion(g)
        -- Munición que lleva, días que le quedan y qué tropas ya no disparan
        -- (municion.lua): la ficha avisa «Lanzacohetes sin misiles».
        ficha.municion = self:municionGrupo(gid)
    end
    return ficha
end

local publicas = {
    'nombrarPresidente',
    'nombrarGeneral',
    'liberarLideres',
    'liderLibre',
    'liderParaSalir',
    'lider',
    'liderDe',
    'esEjercito',
    'lideresDe',
    'rangoLider',
    'etiquetaLider',
    'caracterLider',
    'composicion',
    'fichaGrupo',
}

--- Cuelga de la clase Simulacion las funciones de líderes y `Simulacion.reglasLideres`.
function Lideres.instalar(clase)
    Simulacion = clase
    clase.reglasLideres = Lideres.reglas
    for _, nombre in ipairs(publicas) do
        clase[nombre] = Lideres[nombre]
    end
end

return Lideres
