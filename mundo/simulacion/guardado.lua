--- Guardar y cargar la partida: el estado vivo como texto, y las migraciones de versión.
--
-- Módulo de `mundo/simulacion.lua`: `Guardado.instalar(Simulacion)` cuelga
-- sus funciones de la clase, así que la API pública no cambia (`sim:guardar()`,
-- `Simulacion.cargar(...)`, `Simulacion.serializar(...)`).
--
--   * `serializar` escribe tablas planas con las claves en orden fijo: el mismo
--     estado da siempre el mismo texto (sirve de huella para comprobar el determinismo).
--   * `cargar` lee el texto sin acceso a nada (una partida es solo datos) y sube
--     el estado versión a versión (`migrar`) hasta `Simulacion.version`.
--   * Al subir `Simulacion.version` se añade aquí el paso de migración de la anterior.
--
-- Solo datos y sin LÖVE, como el resto de la simulación.

local Guardado = {}

local Ayudas = require('mundo.simulacion.ayudas')

local ordenadas = Ayudas.ordenadas
local tropasVacias = Ayudas.tropasVacias
local ponerAlMando = Ayudas.ponerAlMando

-- Se fija en `instalar`: la clase, para las migraciones que llaman a sus métodos.
local Simulacion

--- Número en texto: la forma más corta (15, 16 o 17 cifras) que vuelve
-- exactamente al mismo número al leerla.
local function numero(v)
    local texto = string.format('%.15g', v)
    if tonumber(texto) ~= v then
        texto = string.format('%.16g', v)
        if tonumber(texto) ~= v then
            texto = string.format('%.17g', v)
        end
    end
    return texto
end

--- Texto de `v` compacto: sin espacios ni saltos de línea, y las listas
-- (claves 1..n) sin sus claves. `_sangria` queda por compatibilidad y no se usa.
local function serializar(v, _sangria)
    local t = type(v)
    if t == 'number' then
        return numero(v)
    elseif t == 'string' then
        return string.format('%q', v)
    elseif t == 'boolean' then
        return tostring(v)
    elseif t ~= 'table' then
        return 'nil'
    end
    local claves = ordenadas(v)
    local esLista = true
    for k, clave in ipairs(claves) do
        if clave ~= k then
            esLista = false
            break
        end
    end
    local partes = {}
    for k, clave in ipairs(claves) do
        if esLista then
            partes[k] = serializar(v[clave])
        else
            local texto = type(clave) == 'string' and clave:match('^[%a_][%w_]*$') and clave
                or ('[' .. serializar(clave) .. ']')
            partes[k] = texto .. '=' .. serializar(v[clave])
        end
    end
    return '{' .. table.concat(partes, ',') .. '}'
end

--- Texto Lua (`return {...}`) del valor `v`, con las claves en orden fijo.
Guardado.serializar = serializar

--- Texto con todo el estado vivo (para guardar la partida o enviarla a un servidor).
-- Lo que no va en el guardado porque sale de la semilla.
local NO_SE_GUARDA = { depositos = true }

--- Texto con todo el estado vivo (para guardar la partida o enviarla a un
-- servidor), sin lo que sale de la semilla (`NO_SE_GUARDA`).
function Guardado.guardar(self)
    local estado = {}
    for k, v in pairs(self.estado) do
        if not NO_SE_GUARDA[k] then
            estado[k] = v
        end
    end
    return 'return ' .. serializar(estado) .. '\n'
end

-- Sube `estado` (una partida vieja) hasta la versión actual, un paso por versión.
-- Coste de cada modelo de tanque cuando se quitaron (19-nov, `Armamento.coste`
-- de entonces), para devolverlo; sin modelo, el de referencia (T-72B). Y el de
-- un obús (un lote de 100 costaba 8 de dinero y 1 de metal).
local COSTE_TANQUE = {
    t55 = { dinero = 22.0755, metal = 2.427, petroleo = 1 },
    t72b = { dinero = 30, metal = 3, petroleo = 1 },
    m1a1 = { dinero = 34.371, metal = 3.8427, petroleo = 1 },
    k2 = { dinero = 36.282, metal = 3.7752, petroleo = 1 },
}
local COSTE_OBUS = { dinero = 0.08, metal = 0.01 }
local POSICION_TECNOLOGIA_TANQUES = 3

--- v29 -> v30: sin tanques ni obuses (el dueño, 19-nov: «todo esto será un
-- mundo de robots»). Cada tanque (sano, averiado, en el taller o encargado
-- en la fábrica) y cada obús (en el polvorín, con un grupo o encargado) se
-- devuelve a su nación en lo que costó: dinero, metal y petróleo, al almacén
-- y a la bóveda (lo que no cabe, afuera). La tecnología de los tanques sale
-- de la fila: quien ya la tenía conserva el resto.
local function sinTanques(estado)
    local migra = setmetatable({ estado = estado, cambios = 0, eventos = {} }, Simulacion)
    local devolver = {} -- nid -> { dinero, metal, petroleo }
    local function sumar(nid, coste, veces)
        if not nid or not estado.naciones[nid] or veces <= 0 then
            return
        end
        local d = devolver[nid]
        if not d then
            d = { dinero = 0, metal = 0, petroleo = 0 }
            devolver[nid] = d
        end
        for recurso, v in pairs(coste) do
            d[recurso] = d[recurso] + v * veces
        end
    end
    -- `cuantos` tanques de `q`, con su desglose `por` (lo que falte, T-72B).
    local function tanques(nid, cuantos, por)
        cuantos = cuantos or 0
        local puestos = 0
        for _, m in ipairs(ordenadas(por or {})) do
            local k = math.min(por[m], cuantos - puestos)
            sumar(nid, COSTE_TANQUE[m] or COSTE_TANQUE.t72b, k)
            puestos = puestos + k
        end
        sumar(nid, COSTE_TANQUE.t72b, cuantos - puestos)
    end
    -- Averiados de una lista de averías (daños y sus modelos).
    local function averias(nid, a)
        if not a then
            return
        end
        local modelos = a.modelos and a.modelos.tanques or {}
        for k = 1, #(a.tanques or {}) do
            sumar(nid, COSTE_TANQUE[modelos[k]] or COSTE_TANQUE.t72b, 1)
        end
        a.tanques = nil
        if a.modelos then
            a.modelos.tanques = nil
        end
        if a.zonas then
            a.zonas.tanques = nil
        end
    end
    local function municion(nid, m)
        if m then
            sumar(nid, COSTE_OBUS, m.obuses or 0)
            m.obuses = nil
        end
    end
    -- Lo que queda del reparto de bajas en combate (ayudas.lua, `resto`).
    local function sinResto(q)
        if q.resto then
            q.resto.tanques = nil
        end
    end
    -- Ciudades: guarnición, taller, fábrica y polvorín.
    for _, id in ipairs(ordenadas(estado.ciudades)) do
        local c = estado.ciudades[id]
        tanques(c.nacion, c.tanques, c.tanquesPor)
        c.tanques, c.tanquesPor = nil, nil
        local r = c.recuperando
        if r then
            -- Los de la cola sin lista de daños (partidas muy viejas), del de referencia.
            local enLista = #(r.danos and r.danos.tanques or {})
            averias(c.nacion, r.danos)
            sumar(c.nacion, COSTE_TANQUE.t72b, (r.tanques or 0) - enLista)
            r.tanques = nil
            if r.avance then
                r.avance.tanques = nil
            end
        end
        local cola = {}
        for _, o in ipairs(c.fabrica or {}) do
            if o.tropa == 'tanques' then
                sumar(c.nacion, COSTE_TANQUE[o.modelo] or COSTE_TANQUE.t72b, o.cantidad or 0)
            else
                cola[#cola + 1] = o
            end
        end
        if c.fabrica then
            c.fabrica = cola
        end
        local colaMunicion = {}
        for _, o in ipairs(c.fabricaMunicion or {}) do
            if o.municion == 'obuses' then
                sumar(c.nacion, COSTE_OBUS, (o.lotes or 0) * 100)
            else
                colaMunicion[#colaMunicion + 1] = o
            end
        end
        if c.fabricaMunicion then
            c.fabricaMunicion = colaMunicion
        end
        municion(c.nacion, c.municion)
        sinResto(c)
    end
    -- Instalaciones (bases, campamentos, banderas).
    for _, id in ipairs(ordenadas(estado.instalaciones)) do
        local i = estado.instalaciones[id]
        tanques(i.nacion, i.tanques, i.tanquesPor)
        i.tanques, i.tanquesPor = nil, nil
        municion(i.nacion, i.municion)
        sinResto(i)
    end
    -- Grupos: sanos, averiados y lo que resta o lleva.
    for _, gid in ipairs(ordenadas(estado.grupos)) do
        local g = estado.grupos[gid]
        tanques(g.nacion, g.tanques, g.tanquesPor)
        g.tanques, g.tanquesPor = nil, nil
        if g.heridos then
            local enLista = #(g.averias and g.averias.tanques or {})
            averias(g.nacion, g.averias)
            sumar(g.nacion, COSTE_TANQUE.t72b, (g.heridos.tanques or 0) - enLista)
            g.heridos.tanques = nil
        end
        sinResto(g)
        municion(g.nacion, g.municion)
    end
    -- Informes: lo que se vio de tanques ya no existe.
    for _, nid in ipairs(ordenadas(estado.informes or {})) do
        for _, parte in ipairs({ 'sitios', 'grupos' }) do
            local lista = estado.informes[nid][parte] or {}
            for _, k in ipairs(ordenadas(lista)) do
                local tropas = lista[k].tropas
                if tropas then
                    tropas.tanques, tropas.tanquesPor = nil, nil
                end
            end
        end
    end
    for _, nid in ipairs(ordenadas(estado.naciones)) do
        local n = estado.naciones[nid]
        if (n.tecnologia or 0) >= POSICION_TECNOLOGIA_TANQUES then
            n.tecnologia = n.tecnologia - 1
        end
        local d = devolver[nid]
        if d then
            for _, recurso in ipairs({ 'dinero', 'metal', 'petroleo' }) do
                migra:ingresar(n, recurso, d[recurso])
            end
        end
    end
end

local function migrar(estado)
    if estado.version == 3 then
        estado.version = 4
    end
    if estado.version == 4 then
        -- La versión 4 guardaba la comida en el país: se reparte entre sus ciudades.
        for _, n in pairs(estado.naciones) do
            local suyas = {}
            for _, c in pairs(estado.ciudades) do
                if c.nacion == n.id then
                    suyas[#suyas + 1] = c
                end
            end
            for _, c in ipairs(suyas) do
                c.comida = (n.recursos.comida or 0) / #suyas
            end
            n.recursos.comida = nil
        end
        estado.version = 5
    end
    if estado.version == 5 then
        -- La versión 5 no tenía niveles: se ponen los de nacimiento.
        for _, c in pairs(estado.ciudades) do
            local n = estado.naciones[c.nacion]
            c.nivel = Simulacion.nivelInicial(c.radio, n and n.capital == c.id)
        end
        estado.version = 6
    end
    if estado.version == 6 then
        -- La versión 6 lo llamaba ahorro: es el dinero de la ciudad.
        for _, c in pairs(estado.ciudades) do
            c.dinero, c.ahorro = c.ahorro or 0, nil
        end
        estado.version = 7
    end
    if estado.version == 7 then
        -- La versión 7 tenía colores pastel casi iguales: se ponen los de la paleta.
        for id, n in pairs(estado.naciones) do
            n.color = Simulacion.colorNacion(id)
        end
        estado.version = 8
    end
    if estado.version == 9 then
        -- La versión 9 tenía carreteras; los grupos ya en marcha siguen su camino.
        estado.carreteras = nil
        estado.version = 10
    end
    if estado.version == 11 then
        -- La versión 11 no tenía vida en los grupos: los que atacan salen con la
        -- barra llena (la vida que tienen al cargar) y el umbral de su presidente.
        local reglas = Simulacion.recuperacion
        for _, id in ipairs(ordenadas(estado.grupos)) do
            local g = estado.grupos[id]
            local n = estado.naciones[g.nacion]
            if g.mision == 'atacar' and n then
                g.lanzacohetes = g.lanzacohetes or 0
                g.vidaMax = Simulacion.vidaGrupo(g)
                g.umbral = reglas.umbralBase + reglas.umbralPrudencia * n.gobernante.prudencia
                g.heridos = tropasVacias()
                g.resto = tropasVacias()
            end
        end
        estado.version = 12
    end
    if estado.version == 12 then
        -- La versión 12 no tenía lanzacohetes en las bases: las que existen y las
        -- que van de camino nacen con los iniciales, sin coste. Los grupos que
        -- salieron de una ciudad la apuntaban en `origenCiudad`.
        local iniciales = Simulacion.defensasBase.lanzacohetesIniciales
        for _, id in ipairs(ordenadas(estado.instalaciones)) do
            local i = estado.instalaciones[id]
            if i.tipo == 'base' and i.lanzacohetes == nil then
                i.lanzacohetes = iniciales
            end
        end
        for _, id in ipairs(ordenadas(estado.grupos)) do
            local g = estado.grupos[id]
            if g.construye and g.construye.tipo == 'base' and g.construye.lanzacohetes == nil then
                g.construye.lanzacohetes = iniciales
            end
            g.origen, g.origenCiudad = g.origenCiudad, nil
        end
        estado.version = 13
    end
    if estado.version == 13 then
        -- La versión 13 no tenía líderes: cada nación recibe su presidente y los
        -- grupos de ataque (también los que vuelven de atacar) un líder, sin
        -- coste: el primero de cada nación, el presidente; los demás, generales
        -- nuevos.
        estado.lideres = estado.lideres or {}
        local migra = setmetatable({ estado = estado }, Simulacion)
        for _, nid in ipairs(ordenadas(estado.naciones)) do
            migra:nombrarPresidente(estado.naciones[nid])
        end
        for _, id in ipairs(ordenadas(estado.grupos)) do
            local g = estado.grupos[id]
            if (g.mision == 'atacar' or g.origen) and estado.naciones[g.nacion] then
                ponerAlMando(estado, g, migra:liderParaSalir(g.nacion))
            end
        end
        estado.version = 14
    end
    if estado.version == 14 then
        -- La versión 14 no tenía choques entre ejércitos: nadie está trabado.
        estado.version = 15
    end
    if estado.version == 15 then
        -- La versión 15 no tenía vida en las ciudades, ni afuera, ni banderas, y
        -- sus depósitos salían de otra regla: las ciudades nacen con la vida
        -- llena; lo que pase de la bóveda sale afuera; de los depósitos viejos
        -- solo quedan los que tienen una extracción encima (los yacimientos
        -- nuevos entran al registrar las zonas).
        for _, id in ipairs(ordenadas(estado.ciudades)) do
            local c = estado.ciudades[id]
            c.vida = Simulacion.vidaCiudad.maxima
            c.reparacion = nil
        end
        local explotados = {}
        for _, id in ipairs(ordenadas(estado.instalaciones)) do
            local i = estado.instalaciones[id]
            if i.deposito then
                explotados[i.deposito] = true
            end
        end
        -- También los que esperan a un convoy que ya salió a construir.
        for _, id in ipairs(ordenadas(estado.grupos)) do
            local g = estado.grupos[id]
            if g.construye and g.construye.deposito then
                explotados[g.construye.deposito] = true
            end
        end
        for _, id in ipairs(ordenadas(estado.depositos)) do
            if not explotados[id] then
                estado.depositos[id] = nil
            end
        end
        local migra = setmetatable({ estado = estado, cambios = 0 }, Simulacion)
        for _, nid in ipairs(ordenadas(estado.naciones)) do
            local n = estado.naciones[nid]
            n.afuera = { metal = 0, petroleo = 0, dinero = 0 }
            migra:ajustarAlmacen(n)
        end
        estado.version = 16
    end
    if estado.version == 16 then
        -- La versión 16 medía el territorio con radios: se pasa a celdas. Cada
        -- ciudad siembra su bloque de 20 x 20 y después, por orden de id, cada
        -- campamento y bandera terminados, el suyo (sin pisar lo de otro).
        estado.territorio = {}
        estado.versionTerritorio = 0
        local migra = setmetatable({ estado = estado, cambios = 0 }, Simulacion)
        for _, id in ipairs(ordenadas(estado.ciudades)) do
            migra:reclamarBloque(estado.ciudades[id])
        end
        for _, id in ipairs(ordenadas(estado.instalaciones)) do
            local i = estado.instalaciones[id]
            if i.tipo == 'bandera' and i.progreso >= 1 then
                -- Las banderas de entonces daban su bloque centrado.
                local cx0, cy0, cx1, cy1 = Simulacion.bloque(i.x, i.y, Simulacion.bloques.bandera)
                for cy = cy0, cy1 do
                    for cx = cx0, cx1 do
                        if migra:duenoCelda(cx, cy) == nil then
                            migra:ponerCelda(cx, cy, i.nacion)
                        end
                    end
                end
            else
                migra:reclamarBloque(i)
            end
        end
        estado.version = 18
    end
    if estado.version == 17 then
        -- En la versión 17 las bases daban un bloque de 6 x 6: se suelta lo que
        -- no cubra otro sitio de su nación.
        local migra = setmetatable({ estado = estado, cambios = 0 }, Simulacion)
        for _, id in ipairs(ordenadas(estado.instalaciones)) do
            local i = estado.instalaciones[id]
            if i.tipo == 'base' and i.progreso >= 1 then
                local cx0, cy0, cx1, cy1 = Simulacion.bloque(i.x, i.y, 6)
                for cy = cy0, cy1 do
                    for cx = cx0, cx1 do
                        if migra:duenoCelda(cx, cy) == i.nacion and not migra:cubre(i.nacion, cx, cy) then
                            migra:ponerCelda(cx, cy, nil)
                        end
                    end
                end
            end
        end
        estado.version = 18
    end
    if estado.version == 18 then
        -- La versión 18 producía sola y tenía ataques a distancia: las
        -- extracciones se borran y su guarnición vuelve a la ciudad propia más
        -- cercana; los campamentos se quedan (sin producir); los convoyes de
        -- extracciones vuelven; los choques pasan a batallas de dos (en orden
        -- de id); los impactos pendientes se borran.
        estado.minas = {}
        estado.batallas = {}
        estado.siguienteBatalla = 1
        estado.impactos = nil
        for _, clave in ipairs(ordenadas(estado.guerras)) do
            estado.guerras[clave].proximoGolpeCiudad = nil
        end
        for _, nid in ipairs(ordenadas(estado.naciones)) do
            local n = estado.naciones[nid]
            n.consumo = { metal = 0, petroleo = 0, dinero = 0 }
            n.recolectado = { metal = 0, petroleo = 0, comida = 0, oro = 0 }
        end
        local migra = setmetatable({ estado = estado, cambios = 0, eventos = {} }, Simulacion)
        for _, id in ipairs(ordenadas(estado.instalaciones)) do
            local i = estado.instalaciones[id]
            if i.tipo == 'extraccion' then
                local c = migra:ciudadDuena(i.nacion, i.x, i.y)
                if c then
                    for _, campo in ipairs({
                        'soldados',
                        'tanques',
                        'lanzacohetes',
                        'misiles',
                        'interceptores',
                        'aviones',
                    }) do
                        c[campo] = (c[campo] or 0) + (i[campo] or 0)
                    end
                end
                estado.instalaciones[id] = nil
                if i.deposito and not i.deposito:match('^y:') then
                    estado.depositos[i.deposito] = nil
                end
            else
                i.deposito = nil
            end
        end
        migra:ensuciar()
        for _, gid in ipairs(ordenadas(estado.grupos)) do
            local g = estado.grupos[gid]
            if g.mision == 'construir' and g.construye and g.construye.tipo == 'extraccion' then
                migra:volver(g)
            end
        end
        for _, gid in ipairs(ordenadas(estado.grupos)) do
            local g = estado.grupos[gid]
            local o = g and g.choque and estado.grupos[g.choque]
            if o and o.choque == g.id and g.id < o.id then
                local atacante, defensor = g, o
                if g.mision ~= 'atacar' then
                    atacante, defensor = o, g
                end
                migra:crearBatalla({ tipo = 'campo' }, (g.x + o.x) / 2, (g.y + o.y) / 2, { atacante }, { defensor })
            end
        end
        for _, gid in ipairs(ordenadas(estado.grupos)) do
            estado.grupos[gid].choque = nil
        end
        estado.version = 19
    end
    if estado.version == 19 then
        -- La versión 19 no apuntaba desde cuándo espera un grupo detenido: cuenta desde hoy.
        for _, gid in ipairs(ordenadas(estado.grupos)) do
            local g = estado.grupos[gid]
            if g.detenido then
                g.detenidoDesde = estado.dia
            end
        end
        estado.version = 20
    end
    if estado.version == 20 then
        -- La versión 20 no tenía exploradores: nadie sabe nada de sus enemigos.
        estado.exploradores = {}
        estado.siguienteExplorador = 1
        estado.informes = {}
        estado.version = 21
    end
    if estado.version == 21 then
        -- La versión 21 no tenía la economía cerrada (diseno/economia.md, §5): el
        -- dinero de cada ciudad pasa al tesoro (lo que no quepa, afuera); cada
        -- ciudad recibe un polvorín con `reservaMunicion` días de su guarnición
        -- y sus misiles de antes; los grupos armados, su dotación; lo averiado
        -- queda con daño 1. Los soldados por encima del tope se quedan.
        local reglas = Simulacion.produccion
        local migra = setmetatable({ estado = estado, cambios = 0, eventos = {} }, Simulacion)
        for _, id in ipairs(ordenadas(estado.ciudades)) do
            local c = estado.ciudades[id]
            local n = estado.naciones[c.nacion]
            if n and (c.dinero or 0) > 0 then
                migra:ingresar(n, 'dinero', c.dinero)
            end
            c.dinero = nil
            if not c.municion then
                c.municion = Simulacion.dotacion(c, reglas.reservaMunicion)
                c.municion.misiles = c.municion.misiles + (c.misiles or 0)
            end
            c.misiles = nil
            if c.recuperando then
                c.recuperando.danos = c.recuperando.danos or Simulacion.averiasDe(c.recuperando, nil)
            end
        end
        for _, gid in ipairs(ordenadas(estado.grupos)) do
            local g = estado.grupos[gid]
            local dias = reglas.dotacion[g.mision] or (g.lider and reglas.dotacion.atacar)
            if dias and not g.municion then
                g.municion = Simulacion.dotacion(g, dias)
            end
            if g.heridos and (g.heridos.tanques or 0) + (g.heridos.lanzacohetes or 0) > 0 then
                g.averias = g.averias or Simulacion.averiasDe(g.heridos, nil)
            end
        end
        estado.version = 22
    end
    if estado.version == 22 then
        -- Los yacimientos dejan de guardarse: se apuntan las zonas de donde
        -- salen (las de las naciones y las de los yacimientos que había) para
        -- rehacerlos al cargar. Los de esta carga se quedan.
        estado.zonas = estado.zonas or {}
        for _, nid in ipairs(ordenadas(estado.naciones)) do
            if nid:match('^z:') then
                estado.zonas[nid] = true
            end
        end
        for _, id in ipairs(ordenadas(estado.depositos)) do
            local d = estado.depositos[id]
            local zx = math.floor(d.x / Simulacion.ladoZona)
            local zy = math.floor(d.y / Simulacion.ladoZona)
            estado.zonas['z:' .. zx .. ',' .. zy] = true
        end
        estado.version = 23
    end
    if estado.version == 23 then
        -- Población por edades y sexo (diseno/poblacion.md, §5): cada ciudad
        -- recibe la pirámide inicial sobre su población y sus soldados (los
        -- del inventario de la ciudad) salen de sus aptos.
        local migra = setmetatable({ estado = estado, cambios = 0 }, Simulacion)
        for _, nid in ipairs(ordenadas(estado.naciones)) do
            local inv = migra:inventario(nid)
            for _, c in ipairs(migra:ciudadesDe(nid)) do
                if not c.demografia then
                    local suyos = inv.ciudades[c.id]
                    c.demografia = Simulacion.Poblacion.crearDemografia(c.poblacion, suyos and suyos.soldados or 0)
                    c.poblacion = Simulacion.Poblacion.total(c.demografia)
                end
            end
        end
        for _, cid in ipairs(ordenadas(estado.ciudades)) do
            local c = estado.ciudades[cid]
            if not c.demografia then
                c.demografia = Simulacion.Poblacion.crearDemografia(c.poblacion, 0)
            end
        end
        estado.version = 24
    end
    if estado.version == 24 then
        -- Modelos de armamento (diseno/catalogo-armamento.md, §5): todo lo que
        -- había pasa a T-72B y Scud-B (las cifras de antes: nada cambia de
        -- golpe); las naciones tienen la era que les dé su tecnología (las de
        -- era se investigan después de las siete de antes).
        Simulacion.Armamento.migrar(estado)
        estado.version = 25
    end
    if estado.version == 25 then
        -- Banderas del borde (diseno/banderas-borde.md, P1-P9): las banderas
        -- dejan de ser instalaciones con tropas; solo se guardan las que tienen
        -- algo (obra, daño, ataque). Lo que guardaban pasa a un grupo.
        Simulacion.migrarBanderas(estado)
        estado.version = 26
    end
    if estado.version == 26 then
        -- Marcha continua: una partida de antes se guardó entre dos días. Lo
        -- de antes de cada grupo pasa a ser donde está (sin tramo a medias).
        estado.paso = 0
        for _, gid in ipairs(ordenadas(estado.grupos)) do
            local g = estado.grupos[gid]
            g.antesX, g.antesY, g.antesRecorrido = g.x, g.y, g.recorrido
        end
        estado.version = 27
    end
    if estado.version == 27 then
        -- Averías por zona (averias.lua): cada avería de antes, que solo tenía
        -- su daño d, pasa a casco d. Cuesta y tarda lo mismo que antes y el
        -- daño de la lista ya es su trabajo de taller. Sin tripulantes heridos.
        local Averias = Simulacion.Averias
        local function zonas(a)
            if a and #(a.tanques or {}) + #(a.lanzacohetes or {}) > 0 then
                -- Las de los tanques, a mano: ya no son un tipo de vehículo
                -- (la v30 los devuelve en dinero).
                a.zonas = a.zonas or {}
                a.zonas.tanques = a.zonas.tanques or {}
                for k = #a.zonas.tanques + 1, #(a.tanques or {}) do
                    a.zonas.tanques[k] = Averias.deDano(a.tanques[k])
                end
                a.lanzacohetes = a.lanzacohetes or {}
                Averias.zonasDe(a, 'lanzacohetes')
            end
        end
        for _, id in ipairs(ordenadas(estado.ciudades)) do
            local c = estado.ciudades[id]
            if c.recuperando then
                zonas(c.recuperando.danos)
            end
        end
        for _, gid in ipairs(ordenadas(estado.grupos)) do
            zonas(estado.grupos[gid].averias)
        end
        estado.version = 28
    end
    if estado.version == 28 then
        -- Almacén de cada nación (almacen.lua): se crea al pedirlo.
        estado.almacenes = estado.almacenes or {}
        estado.version = 29
    end
    if estado.version == 29 then
        sinTanques(estado)
        estado.version = 30
    end
end

--- Simulación con el estado del texto `texto` (de `guardar`), migrado si es de una
-- versión anterior; `nil` y el motivo si no se entiende o es de otra versión.
function Guardado.cargar(texto, opciones)
    local trozo, err = loadstring(texto, 'partida')
    if not trozo then
        return nil, err
    end
    -- Sin acceso a nada: una partida es solo datos.
    setfenv(trozo, {})
    local ok, estado = pcall(trozo)
    if not ok or type(estado) ~= 'table' then
        return nil, ok and 'partida sin datos' or estado
    end
    -- Desde la 23 el guardado no trae yacimientos: se rehacen tras migrar.
    estado.depositos = estado.depositos or {}
    migrar(estado)
    if estado.version ~= Simulacion.version then
        return nil, 'partida de otra versión'
    end
    local self = setmetatable({}, Simulacion)
    self.estado = estado
    self.sitioValido = opciones and opciones.sitioValido
    self.eventos = {}
    self.cambios = 1
    if not self:rehacerYacimientos(opciones and opciones.datosZona) then
        return nil, 'faltan los yacimientos: cargar necesita opciones.datosZona'
    end
    return self
end

--- Cuelga `guardar`, `cargar` y `serializar` de la clase Simulacion.
function Guardado.instalar(clase)
    Simulacion = clase
    clase.serializar = Guardado.serializar
    clase.guardar = Guardado.guardar
    clase.cargar = Guardado.cargar
end

return Guardado
