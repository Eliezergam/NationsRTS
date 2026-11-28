--- Simulación del mundo vivo: naciones, ciudades, instalaciones, grupos y guerras.
--
-- Pensada para funcionar igual sin internet y con un servidor (ver ARQUITECTURA.md):
--
--   * El mundo FÍSICO (terreno, ciudades, depósitos) sale de la semilla.
--   * El mundo VIVO está en `self.estado`: solo datos, con identificadores que
--     salen del mundo ('rx,ry' para ciudades, 'z:zx,zy' para naciones,
--     'i:<depósito>' para instalaciones de extracción, 'b:...' para bases).
--   * `avanzarPaso` y `avanzarDia` son DETERMINISTAS: el azar sale de
--     Ruido.hash(semilla, día, ...) y todo se recorre en orden fijo. No usa LÖVE.
--     Los grupos andan en `pasosDia` pasos por día; lo demás va por días.
--   * Todo cambio desde fuera es un COMANDO (`ejecutar`).
--
-- El modelo de guerra:
--
--   Naciones    cada zona del mundo es una nación: su ciudad más grande es la
--               capital y las demás le pertenecen. El presidente dispone de todos
--               los ejércitos: saca las fuerzas del sitio (ciudad o base) más
--               cercano a cada objetivo.
--   Territorio  celdas cuadradas de 50 m, cada una con un dueño o ninguno. La
--               capital empieza con 20 x 20 y se estira con banderas (6 x 6,
--               en cualquier terreno, pegadas a lo propio) hacia los
--               yacimientos (petróleo, metal, oro y comida); un yacimiento
--               solo se explota en celda propia, con una extracción o un
--               campamento encima. Lo vencido se destruye y sus celdas quedan
--               sin dueño (diseno/territorio-y-capitales.md).
--   Bases       las naciones levantan bases militares en su territorio, hacia
--               sus vecinos, con aviones, misiles e interceptores.
--   Guerra      los ataques van contra instalaciones y bases: grupos en misión,
--               salvas de misiles (el defensor intercepta lo que puede) e
--               incursiones aéreas (el defensor despega cazas). El atacado manda
--               refuerzos. Hay días de tensión y días de calma.
--   Ciudades    golpes sueltos de misiles cada 2 a 20 días (crimen de guerra si
--               caen sobre civiles) y asaltos por tierra. Una capital nunca
--               cambia de manos: si pierde su batalla queda a 9 de vida y le
--               saquean lo que tenía afuera del almacén y de la bóveda.
--   Presidentes negocian según los daños: alto el fuego de unos días, paz con
--               concesiones, o conversaciones que fracasan.

local Ruido = require('mundo.ruido')
local Ayudas = require('mundo.simulacion.ayudas')
local Armamento = require('mundo.simulacion.armamento')
local Averias = require('mundo.simulacion.averias')
local ordenadas = Ayudas.ordenadas
local hipotenusa = Ayudas.hipotenusa
local distancia = Ayudas.distancia
local lista = Ayudas.lista
local tropasVacias = Ayudas.tropasVacias
local esCiudad = Ayudas.esCiudad
local ponerAlMando = Ayudas.ponerAlMando
local anotar = Ayudas.anotar
local claveGuerra = Ayudas.claveGuerra
local grupoEnCamino = Ayudas.grupoEnCamino

local Simulacion = {}
Simulacion.__index = Simulacion

Simulacion.version = 32 -- 4: rutas por tierra; 5: granero; 6: niveles; 7: dinero por ciudad; 8: colores de país;
-- 9: mapa a escala (las ciudades cambian de sitio: las partidas anteriores no sirven)
-- 10: sin rutas ni carreteras (los grupos aparecen donde van);
-- 11: solo capitales; los campamentos producen (las partidas anteriores no sirven)
-- 12: vida de los grupos, retirada y cola de recuperación de las ciudades
-- 13: lanzacohetes en las bases; los grupos apuntan su sitio de origen (`origen`)
-- 14: líderes (`e.lideres`): el presidente de cada nación y generales que mandan los grupos de ataque;
--     nación del jugador (`n.jugador`), por la que la IA no decide
-- 15: choques entre ejércitos: los trabados apuntan al otro en `g.choque`
-- 16: territorio y capitales (diseno/territorio-y-capitales.md): vida de las ciudades (`c.vida`,
--     `c.reparacion`), lo que no cabe en el almacén ni en la bóveda (`n.afuera`), botín de los
--     grupos (`g.botin`), banderas y yacimientos procedurales ('y:cx,cy')
-- 17: territorio por celdas cuadradas (`e.territorio`, `e.versionTerritorio`): cada celda de
--     `Simulacion.celda` px tiene un dueño y solo uno; ya no hay radios ni fronteras onduladas
-- 18: las bases no dan territorio (en la 17 daban un bloque de 6 x 6)
-- 19: recolección y batallas (diseno/recoleccion-y-batallas.md): minas finitas (`e.minas`),
--     batallas de bandos (`e.batallas`, `e.siguienteBatalla`, `g.batalla` en vez de `g.choque`),
--     grupos 'recolectar' y 'apoyo' (`g.yacimiento`, `g.fase`, `g.carga`, `g.tipoCarga`),
--     medias de consumo y recolección (`n.consumo`, `n.recolectado`); sin extracciones, sin
--     impactos (`e.impactos`) y sin golpes a ciudades (`guerra.proximoGolpeCiudad`)
-- 20: los grupos detenidos por un alto el fuego apuntan desde cuándo (`g.detenidoDesde`)
-- 21: exploradores e informes (mundo/simulacion/exploracion.lua): `e.exploradores`,
--     `e.siguienteExplorador` y `e.informes`; las partidas anteriores empiezan sin informes
-- 22: economía cerrada (diseno/economia.md): un solo dinero (sin `c.dinero`), fábricas
--     (`c.fabrica`, `c.fabricaMunicion`, `c.siguienteOrden`), polvorín (`c.municion`, sin
--     `c.misiles`), parque de lanzacohetes (`c.parque`), munición de los grupos (`g.municion`),
--     averías con su daño (`g.averias`, `c.recuperando.danos`), impago (`n.impago`), convoyes
--     de munición (misión 'abasto'), remolques (`g.remolque`) y lo que queda de redondear las
--     bajas de grupos y guarniciones (`resto`, `restoMuertos`)
-- 23: el guardado no lleva los yacimientos (salen de la semilla: `cargar` los rehace de las
--     zonas registradas, `e.zonas`, con `opciones.datosZona`) ni sangría
-- 24: población por edades y sexo (diseno/poblacion.md): `c.demografia` en cada ciudad
-- 25: modelos de armamento (diseno/catalogo-armamento.md, mundo/simulacion/armamento.lua): desglose
--     por modelo de lanzacohetes (`lanzacohetesPor`, `parquePor`...), un
--     modelo por avería y por orden de fábrica, y las tecnologías de era al final de la fila
-- 26: banderas del borde (diseno/banderas-borde.md, mundo/simulacion/banderas.lua): la bandera sale
--     de las celdas (un bloque alineado de 6 x 6 del borde) y solo se guarda la que está en obra,
--     dañada o atacada, con id 'f:<nación>:<bx>,<by>' y sin tropas; la guarnición son grupos con
--     misión 'guarnicion' (`g.bandera`, `g.alerta`)
-- 27: marcha continua (el dueño, 2026-09-30): los grupos andan en `pasosDia` pasos por día;
--     `e.paso` dice cuántos van del día en curso (0 entre días) y `g.llegada` el día de la
--     última llegada de cada grupo; `antesX`, `antesY` y `antesRecorrido` son los del paso anterior
-- 28: averías por zona (mundo/simulacion/averias.lua): un código por vehículo averiado
--     (`averias.zonas[tipo][k]`, en `g.averias` y `c.recuperando.danos`) y el daño pasa a ser el
--     trabajo de taller; tripulantes heridos (`g.averias.tripulantes`, `c.recuperando.tripulantes`
--     y `c.recuperando.avance.tripulantes`). Las averías de antes pasan a casco d (lo mismo de antes)
-- 29: almacén de cada nación (mundo/simulacion/almacen.lua, diseno/almacen.md): `e.almacenes`
-- 30: sin tanques ni obuses (19-nov, un mundo de robots): los de la partida se devuelven en lo que
--     costaron y la tecnología de los tanques sale de la fila (guardado.lua, `sinTanques`)
-- 31: aviones de transporte (mundo/simulacion/aviones.lua): todo viaje va en avión (`e.aviones`,
--     `e.vuelos`, `g.vuelo`, `c.obraAviones`); sin choques en campo abierto
-- 32: territorio de ciudades y campamentos en bloques de bandera alineados a su rejilla
--     (territorio.lua: bloqueAlineado); al cargar una v31 se rehace (`alinearTerritorio`)
Simulacion.Averias = Averias
Simulacion.maxNoticias = 60

-- Lado de una zona en px cuando se guardaron las partidas de la versión 22 (4
-- regiones de 24 576, el `Ciudades.region` de entonces; hoy las regiones son de
-- 12 288). Solo lo usa la migración a la versión 23 para saber de qué zona es
-- cada yacimiento de esas partidas: no sigue a `Ciudades.region`.
Simulacion.ladoZona = 98304

-- Vecinas (diseno/escala-del-mundo.md, 3.7.6): naciones con la capital a menos
-- de esta distancia (unas 2 zonas). Solo entre vecinas corre la diplomacia y se
-- mueven las relaciones; las lejanas se quedan en su relación de partida.
Simulacion.alcanceVecinas = 95000 -- a la mitad con las regiones (Ciudades.region 12288); antes 190000

-- Red de seguridad: un grupo detenido más de estos días vuelve a casa. Un
-- alto el fuego dura como mucho 30 días; esto no es una regla de juego.
Simulacion.maxDiasDetenido = 60

Simulacion.ordenes = {
    alba = { nombre = 'Orden del Alba', color = { 0.92, 0.45, 0.38 }, opuesto = 'estandarte' },
    estandarte = { nombre = 'Liga del Estandarte', color = { 0.36, 0.5, 0.86 }, opuesto = 'alba' },
    concordia = { nombre = 'Concordia', color = { 0.88, 0.76, 0.3 } },
}
Simulacion.listaOrdenes = { 'alba', 'estandarte', 'concordia' }

Simulacion.tecnologias = {
    { id = 'armas', nombre = 'armas de asalto', coste = 40 },
    { id = 'explosivos', nombre = 'explosivos', coste = 110 },
    { id = 'misiles', nombre = 'misiles guiados', coste = 380 },
    { id = 'interceptores', nombre = 'defensa antimisiles', coste = 520 },
    { id = 'aviones', nombre = 'aviones de combate', coste = 700 },
    { id = 'precision', nombre = 'guiado de precisión', coste = 1000 },
}

Simulacion.recursos = {
    metal = { nombre = 'mina de metal', articulo = 'una' },
    petroleo = { nombre = 'campo petrolífero', articulo = 'un' },
    comida = { nombre = 'complejo agrícola', articulo = 'un' },
    oro = { nombre = 'mina de oro', articulo = 'una' },
}

Simulacion.saludMaxima = { extraccion = 100, base = 180, campamento = 30, bandera = 100 }

-- Gasto de recursos: sin él se acumulan por miles y no hay por qué pelear.
Simulacion.consumo = {
    comeHabitante = 1 / 700, -- comida que come cada habitante al día
    cultivoRadio = 0.02, -- comida que cultivan las tierras de una ciudad al día, por px de radio
    graneroBase = 60, -- tope del granero de cada ciudad
    graneroHabitante = 0.03, -- y cuánto sube por habitante
    comidaInicial = 30, -- comida con la que nace el granero
    trabajoHambre = 0.5, -- lo que produce una ciudad con hambre (la gente no rinde)
    hambre = 0.003, -- ya no se usa: el hambre mata con `Simulacion.poblacion.hambre` (poblacion.lua)
    petroleoAvion = 0.1, -- combustible de cada avión al día (el de los lanzacohetes, `produccion.combustible`)
    metalCiudad = 0.3, -- metal de talleres y chatarra de cada ciudad al día
    reservaMetal = 40, -- metal que la fábrica no toca: queda para obras y reparaciones
    reparacion = 0.5, -- metal por cada reparación diaria de una instalación
}

-- Almacén, bóveda y afuera (diseno/territorio-y-capitales.md, 3.4, F1, F1b y
-- F2). El metal y el petróleo se guardan en el almacén hasta `nivel[nivel de
-- la capital]`; el dinero, en la bóveda, hasta `bovedaFactor` veces eso. Lo
-- que no cabe queda afuera (`n.afuera`), sin tope: se gasta primero, se
-- pierde `merma` al día y el enemigo se lo lleva si gana en la capital.
Simulacion.almacenaje = {
    nivel = { 200, 350, 500, 700, 1000 },
    bovedaFactor = 10,
    merma = 0.03,
}

-- Vida de las ciudades (3.3, 3.5, 3.6; F3 a F6), de 0 a 100. Una capital
-- nunca cambia de manos: si pierde su batalla queda en `derrota` y la saquean.
Simulacion.vidaCiudad = {
    maxima = 100,
    derrota = 9,
    efectoMinimo = 0.4, -- f(V) = efectoMinimo + (1 - efectoMinimo) × V / 100
    umbralIA = 60, -- el presidente NPC repara por debajo de esta vida
    coste = { metal = 2, petroleo = 1, dinero = 15 }, -- por punto de vida (F4)
    ritmoBase = 2, -- puntos al día: ritmoBase + nivel (F5)
    -- Lo que aguanta cada defensa del sitio (D en F3).
    pesos = { soldados = 1, lanzacohetes = 40, baterias = 20 },
}

-- Banderas del borde (diseno/banderas-borde.md, mundo/simulacion/banderas.lua):
-- solo toman territorio. Se plantan en el bloque alineado de 6 x 6 celdas
-- pegado a lo propio y se levantan solas en `dias`; cada bloque del borde
-- tiene su bandera, que sale de las celdas.
Simulacion.bandera = {
    dinero = 20,
    metal = 4,
    dias = 2,
    alcance = 1500, -- medio lado de su bloque (6 x 6 celdas de 500 px): el yacimiento que protege
    separacion = 500, -- ya no se usa (P4 A: un bloque, una bandera); queda para la vista de antes
    mantenimiento = 0.245, -- F1: dinero al día por cada 36 celdas de tierra de bandera (P5 A)
    desabasto = 5, -- vida que pierde al día cada bloque del borde que no se paga (F2)
    diasGuardada = 3, -- días sin ataque tras los que una bandera a 100 deja de guardarse
    guarnicionPorNivel = 200, -- F5: tope de guarnición = esto × nivel de la capital (vida de grupo)
    diasGuardiaIA = 5, -- días sin aviso ni batalla tras los que el NPC hace regresar la guarnición
    aguante = 300, -- F7: ΔV = min(100, G × 100 / aguante)
    cadaDias = 2, -- cada cuánto piensa el presidente NPC en plantarlas
    reservaTesoro = 60, -- lo que el presidente no gasta en banderas
    enemigoCerca = 3000, -- un yacimiento con un sitio enemigo en guerra a esta distancia no vale nada (F12)
    distanciaValor = 3000, -- F12: valor / (1 + distanciaBorde / distanciaValor)
    atractivo = 0.6, -- un grupo de tierra enemigo la ve como si estuviera así de lejos (`objetivo`)
}

-- Yacimientos (3.8, F11): los genera `recursos.lua`.
Simulacion.yacimientos = {
    precioOro = 8, -- dinero por unidad de oro
    oroNecesario = 1.5, -- necesidad de oro con el tesoro por debajo de 10 × reservaTesoro
    oroHolgado = 0.5, -- y por encima
}

-- Niveles de ciudad, como en Bannerlord: el presidente los mejora con el almacén
-- del país y la mejora tarda `dias`. `minas` multiplica lo que dan sus minas y
-- sus tierras; `granero`, el tope de su granero. Las defensas por nivel vendrán
-- con los lanzacohetes y las baterías.
Simulacion.niveles = {
    { minas = 1, granero = 1 },
    { mejora = { metal = 60, petroleo = 20 }, dias = 30, minas = 1.25, granero = 1.5 },
    { mejora = { metal = 150, petroleo = 60 }, dias = 70, minas = 1.5, granero = 2 },
    { mejora = { metal = 300, petroleo = 120 }, dias = 110, minas = 1.75, granero = 3 },
    { mejora = { metal = 500, petroleo = 200 }, dias = 160, minas = 2, granero = 4 },
}
--- Datos del nivel `nivel` de una ciudad. Los niveles por encima de la tabla
-- usan el último: la tabla puede crecer (niveles 1 a 50) sin tocar a quien pregunta.
function Simulacion.nivel(nivel)
    local tabla = Simulacion.niveles
    return tabla[math.max(1, math.min(#tabla, nivel or 1))]
end

--- Radio físico de una ciudad (sus calles, a escala real). Las partidas viejas
-- no lo guardaban: 5 veces el radio de la economía, como en el mundo.
function Simulacion.casco(c)
    return c.casco or (c.radio or 0) * 5
end

--- Nivel con el que nace una ciudad: 1, y la capital 2. `radio` queda para
-- ajustes futuros (ciudades grandes que nazcan más altas).
function Simulacion.nivelInicial(_radio, esCapital)
    return esCapital and 2 or 1
end

-- Huerto de emergencia: el presidente lo planta junto a una ciudad sin granjas
-- que pasa apuros. Da como mucho `porRadio` × radio × nivel de comida al día,
-- y solo lo que le falta a la gente: no alcanza para mantener a los soldados.
Simulacion.huerto = { coste = 5, dias = 8, porRadio = 0.03, distancia = 160 }

-- Defensas de las ciudades: lanzacohetes (se producen con `producir`, ver
-- produccion.lua) y baterías antiaéreas (se compran). Cada ciudad tiene
-- `tope[nivel]` plataformas de cada tipo; los lanzacohetes que no caben
-- esperan en su parque. Las bases solo llevan lanzacohetes (ver `defensasBase`).
Simulacion.defensasCiudad = {
    tope = { 2, 5, 10, 18, 30 },
    coste = {
        baterias = { dinero = 50, metal = 8, petroleo = 2 },
    },
    disparosBateria = 3, -- interceptores que dispara cada batería contra un ataque
    misilesLanzacohetes = 4, -- misiles que dispara cada lanzacohetes en una salva
    frontera = 55000, -- una ciudad con un rival hostil a esta distancia está en la frontera
    hostil = -60, -- relación por debajo de la cual un vecino se considera hostil
}

-- Lanzacohetes de las bases (diseno/guerra.md, P7): la misma regla de disparo
-- que en las ciudades. Una base nace vacía (economía cerrada: nada aparece sin
-- producir) y admite como mucho `topeLanzacohetes` (sus plataformas, fijo); se
-- llena colocando los del parque de su ciudad (`enviarDefensas`).
-- `lanzacohetesIniciales` queda para las partidas viejas.
Simulacion.defensasBase = {
    lanzacohetesIniciales = 2,
    topeLanzacohetes = 6,
    perdidaImpacto = 0.3, -- probabilidad de perder uno con un impacto de más de 8 de daño
}

-- Conquista de ciudades: cada impacto de misil contra una ciudad destruye
-- primero una defensa (batería o lanzacohetes), después mata `soldadosImpacto`
-- soldados, y solo si no queda nada militar cae sobre civiles (crimen de guerra).
-- En tierra, cada lanzacohetes defiende como `fuerzaLanzacohetes` soldados.
Simulacion.conquista = {
    soldadosImpacto = 25,
    fuerzaLanzacohetes = 40,
    atractivoNivel = 0.12, -- cuánto más apetece una ciudad por cada nivel
    distanciaCiudad = 1, -- una ciudad cuenta como si estuviera así de lejos
    asalto = { soldados = 0.8 }, -- parte del sitio que va a asaltar una ciudad
}

-- Retirada y recuperación (diseno/retirada-y-recuperacion.md). Un grupo que
-- sale a atacar tiene vida: lo que pesa en combate lo que lleva (soldado 1,
-- lanzacohetes 40). De lo que cae en combate, parte de los soldados
-- muere (`produccion.muertos`) y el resto queda herido o averiado y viaja con
-- el grupo; con la vida por debajo de su umbral, el grupo se retira. En casa
-- entran en el taller de la ciudad (taller.lua): cada día vuelven `ritmo` ×
-- nivel soldados, y se reparan `ritmo` × nivel puntos de daño de cada tipo de
-- vehículo; pagando `precio` por unidad (y la reparación), vuelven al momento.
Simulacion.recuperacion = {
    umbralBase = 0.15, -- umbral de retirada de un presidente: umbralBase + umbralPrudencia × prudencia
    umbralPrudencia = 0.2,
    umbralMaximo = 0.5, -- lo más alto que puede elegir quien manda un grupo
    preventiva = 0.1, -- se retira si el peor día del enemigo (10 % de su fuerza) acabaría con él
    ritmo = { soldados = 25, lanzacohetes = 0.4 }, -- por día y por nivel de la ciudad
    precio = { soldados = 1, lanzacohetes = 33 }, -- dinero por unidad acelerada
    parteLanzacohetes = { ciudad = 0.5, instalacion = 0.25 }, -- los que se lleva el presidente de su ciudad
    diasMinimos = 3, -- el presidente no paga lo que vuelve solo en estos días
    reservaTesoro = 60, -- lo que el presidente no toca para acelerar
    presupuestoTesoro = 0.2, -- y del tesoro: presupuestoTesoro + presupuestoAgresividad × agresividad
    presupuestoAgresividad = 0.5,
}

-- Colores de los países: bien distintos entre sí para que el territorio se lea.
Simulacion.paleta = {
    { 0.9, 0.25, 0.25 }, -- rojo
    { 0.2, 0.45, 0.95 }, -- azul
    { 0.95, 0.78, 0.1 }, -- amarillo
    { 0.62, 0.3, 0.88 }, -- morado
    { 0.1, 0.78, 0.78 }, -- cian
    { 0.98, 0.52, 0.1 }, -- naranja
    { 0.92, 0.32, 0.68 }, -- magenta
    { 0.6, 0.12, 0.28 }, -- granate (verde no: no se distingue sobre la hierba)
    { 0.58, 0.36, 0.2 }, -- marrón
    { 0.72, 0.92, 0.2 }, -- lima
    { 0.96, 0.96, 0.96 }, -- blanco
    { 1, 0.64, 0.58 }, -- salmón
}

--- Color de un país por su zona ('z:zx,zy'): (5·zx + 3·zy) mod 12 da un color
-- distinto a cada una de sus 8 zonas vecinas.
function Simulacion.colorNacion(nid)
    local zx, zy = nid:match('^z:(-?%d+),(-?%d+)$')
    local indice = (5 * tonumber(zx or 0) + 3 * tonumber(zy or 0)) % #Simulacion.paleta + 1
    local c = Simulacion.paleta[indice]
    return { c[1], c[2], c[3] }
end

-- Arsenal con el que nace cada ciudad (la capital, más). Los misiles son
-- munición de lanzacohetes y van a su polvorín (más `reservaMunicion` días de
-- su guarnición).
Simulacion.arsenalInicial = {
    capital = { misiles = 20, interceptores = 10, lanzacohetes = 2, baterias = 2 },
    ciudad = { misiles = 8, interceptores = 0, lanzacohetes = 1, baterias = 0 },
}

--- Cuántos misiles puede disparar un sitio (ciudad o base) en una salva: los
-- que le permitan sus lanzacohetes.
function Simulacion.misilesListos(s)
    return math.min(s.misiles or 0, (s.lanzacohetes or 0) * Simulacion.defensasCiudad.misilesLanzacohetes)
end

--- Cuántos lanzacohetes admite un sitio: una base, los de sus plataformas; una
-- ciudad, el tope de su nivel (el mismo que para sus baterías).
function Simulacion.topeLanzacohetes(s)
    if s.tipo == 'base' then
        return Simulacion.defensasBase.topeLanzacohetes
    end
    local tope = Simulacion.defensasCiudad.tope
    return tope[math.max(1, math.min(#tope, s.nivel or 1))]
end

-- Metal que cuesta levantar cada instalación (se paga al salir el convoy).
Simulacion.costeObra = { base = 30 }

-- Campamentos: puestos de acopio (diseno/recoleccion-y-batallas.md, 3.3). Dan
-- territorio (su bloque, terminados), de ellos salen grupos a recolectar y en
-- ellos se entrega (lo que entra va al almacén del país: acortan el viaje a las
-- minas lejanas). No producen. Solo se plantan dentro del territorio propio y
-- el enemigo los destruye con su ejército. Cada uno terminado cuesta
-- `recoleccion.mantenimientoCampamento` de petróleo al día; el que no se paga
-- pierde `desabasto` de salud al día hasta que se abandona.
Simulacion.campamento = {
    dinero = 40, -- del tesoro del presidente
    metal = 10, -- del almacén del país
    petroleo = 6,
    alcance = 3000, -- territorio alrededor (300 m)
    dias = 6, -- de obra, desde que llega la tropa
    soldados = 15, -- los que lo levantan y lo guardan
    separacion = 2400, -- entre dos campamentos de la misma nación
    cadaDias = 4, -- cada cuánto piensa el presidente en plantar uno
    reservaTesoro = 60, -- lo que el presidente no gasta en campamentos
    alcanceMeta = 60000, -- yacimientos que conoce el presidente, alrededor de su capital (6 km)
    desabasto = 5,
    margen = 0.5, -- petróleo al día que el presidente quiere que le sobre tras el siguiente
    lejosAcopio = 9000, -- el presidente planta uno junto a una mina suya a más de esto de sus puestos
}

-- Territorio por celdas (diseno/territorio-y-capitales.md): el mundo se parte
-- en celdas cuadradas de `celda` px (50 m), alineadas a la rejilla del mundo
-- (celda cx = floor(x / celda)). Cada celda tiene un dueño y solo uno, o
-- ninguno: eso es el territorio, lo que se dibuja y lo que se pregunta. Cada
-- sitio que da territorio siembra un bloque cuadrado de `bloques[tipo]` celdas
-- de lado centrado en él: solo toma las celdas libres, nunca las de otra
-- nación. Las extracciones y las bases no dan territorio: se levantan dentro
-- del propio.
Simulacion.celda = 500
Simulacion.bloques = {
    -- En bloques de bandera enteros, alineados a su rejilla (territorio.lua:
    -- bloqueAlineado; el dueño, 26-nov).
    ciudad = 18, -- 3 x 3 bloques de bandera (9 km)
    bandera = 6, -- 3 km
    campamento = 12, -- 2 x 2 bloques de bandera (6 km)
}

-- Medio lado del bloque de cada tipo de instalación (px de mundo).
local ALCANCE_INSTALACION = {
    campamento = Simulacion.bloques.campamento * Simulacion.celda / 2,
    bandera = Simulacion.bloques.bandera * Simulacion.celda / 2,
}
Simulacion.alcanceInstalacion = ALCANCE_INSTALACION

--- ¿Da ya territorio? Los campamentos, terminados. Las banderas ya no son
-- sitios que den un bloque: su tierra sale de las celdas (banderas.lua).
local function daTerritorio(i)
    return i.tipo ~= 'bandera' and Simulacion.bloques[i.tipo] ~= nil and i.progreso >= 1
end

-- Los lanzacohetes pesan lo de su modelo (armamento.lua).
local FUERZA = { soldados = 1, misiles = 2, interceptores = 1, aviones = 15 }

-- Modelos de armamento (mundo/simulacion/armamento.lua) ---
Armamento.instalar(Simulacion)

--- Vida de un grupo: sus soldados y la vida de cada modelo de lanzacohetes
-- que lleva (con todo Scud-B, lanzacohetes 40).
function Simulacion.vidaGrupo(g)
    return g.soldados * FUERZA.soldados + Armamento.vidaDe(g, 'lanzacohetes')
end

--- Golpe de un grupo con toda su munición: soldados y el golpe de cada modelo.
function Simulacion.golpeGrupo(g)
    return g.soldados * FUERZA.soldados + Armamento.golpeDe(g, 'lanzacohetes')
end

-- Poder (diseno/ejercitos-en-el-mapa.md, 3.4, F1 y F2): el número que se ve en
-- la ficha de un ejército. Es una escala fija de lo que ya decide el combate:
-- con las cifras de hoy (vida = golpe = FUERZA), poder = 5,5 × vidaGrupo.
Simulacion.escalaPoder = 5.5

--- Poder de una unidad (F1): escalaPoder × (vida + golpe) / 2. Un soldado;
-- un lanzacohetes, el de referencia o, con `sitio`, la media de
-- los que hay en él (los que saldrían de allí).
function Simulacion.poderUnidad(tropa, sitio)
    if tropa == 'soldados' then
        return Simulacion.escalaPoder * (FUERZA.soldados + FUERZA.soldados) / 2
    end
    if sitio and (sitio[tropa] or 0) > 0 then
        return Armamento.poderDe(sitio, tropa) / sitio[tropa]
    end
    return Armamento.poder(Armamento.referencia(tropa))
end

--- Poder de lo que hay sano en `s` (un grupo, una ciudad o una instalación):
-- la suma del poder de sus soldados y de cada modelo de lanzacohetes (F2).
-- Los heridos no cuentan.
local function poderDe(s)
    return (s.soldados or 0) * Simulacion.poderUnidad('soldados') + Armamento.poderDe(s, 'lanzacohetes')
end

--- Poder de un grupo (F2). Hoy es exactamente 5,5 × `vidaGrupo(g)`.
function Simulacion.poder(g)
    return poderDe(g)
end

--- Poder de las tropas sanas de un sitio (ciudad, base, extracción o
-- campamento), con la misma cuenta que un ejército. No incluye la
-- fortificación ni las defensas fijas (misiles, baterías, aviones).
function Simulacion.poderSitio(s)
    return poderDe(s)
end

--- El poder como se muestra: redondeado al entero (F2).
function Simulacion.poderRedondeado(poder)
    return math.floor(poder + 0.5)
end

-- Escala de países (1 px = 10 cm): ciudades del mismo país a 3-5 km, capitales
-- vecinas a unos 8-10 km. Los viajes duran días de juego, no km reales.
Simulacion.velocidadGrupo = 1600 -- px de mundo por día de un convoy de obra (no se ve por el camino)
Simulacion.velocidadEjercito = 9000 -- px por día de un ejército (ataques, refuerzos, regresos)
-- Marcha continua (el dueño, 2026-09-30: «no tiene que ser por día, es en el
-- momento»): los grupos andan en pasos fijos de tiempo de juego, los mismos en
-- todas las máquinas. La economía, la producción, la población y la
-- diplomacia siguen yendo por días.
-- Con 720 (dos minutos de juego), a velocidad 1 (un día en 60 s) hay un paso
-- cada 83 ms; medido con 24 y 348 naciones, la marcha cuesta 0,8 veces lo que
-- el resto del día (con 1440, 1,5 veces).
Simulacion.pasosDia = 720 -- pasos de marcha por día
-- Choques entre ejércitos por el camino: ya no (todo va en avión y solo se
-- pelea en minas y ciudades). Queda el código por si se vuelve a querer.
Simulacion.choquesEnCampo = false
Simulacion.marchaSinActivos = false -- true: cada paso mira todos los grupos (para comprobar `moverPaso`)
Simulacion.intentosRuta = 6 -- depósitos que se prueban por día hasta dar con uno al que se llegue por tierra
-- Misiles y aviones ya no vuelan por el mapa (diseno/recoleccion-y-batallas.md,
-- 3.6); sus velocidades quedan para la vista, que aún dibuja los de antes.
Simulacion.velocidadMisil = 160000 -- px por día
Simulacion.velocidadAvion = 120000 -- px por día
Simulacion.alcanceGuerra = 110000 -- distancia entre naciones para poder chocar (11 km)
Simulacion.alcanceAtaque = 130000 -- hasta dónde manda ejércitos el presidente (13 km: al vecino, no a medio mapa)
Simulacion.alcanceCodicia = 80000 -- las minas del rival a esta distancia de una ciudad o un campamento se codician (8 km)
Simulacion.basesPorCiudad = 2

local Nombres = require('mundo.simulacion.nombres')
local NOMBRES = Nombres.nombres
local APELLIDOS = Nombres.apellidos

local TITULOS = {
    alba = { 'República Popular de', 'Comuna de', 'Unión del Alba de' },
    estandarte = { 'Principado de', 'Liga Soberana de', 'Estado de' },
    concordia = { 'Federación de', 'Mancomunidad de', 'Cantón de' },
}

-- Utilidades deterministas (mundo/simulacion/ayudas.lua) ---------------------------------

Simulacion.ordenadas = ordenadas

--- Mete `g` al final de la lista `clave` de `t` (la crea si hace falta).
local function anotarEn(t, clave, g)
    local l = t[clave]
    if not l then
        l = {}
        t[clave] = l
    end
    l[#l + 1] = g
end

--- Mete el grupo `g` en las listas del índice de grupos.
local function indexarGrupo(c, g)
    c.lista[#c.lista + 1] = g
    anotarEn(c.porNacion, g.nacion, g)
    anotarEn(c.porMision, g.mision, g)
    if g.objetivo ~= nil then
        anotarEn(c.porObjetivo, g.objetivo, g)
    end
end

--- Mete `g` en la lista `clave` de `t` en su sitio por id (la crea si hace
-- falta), si no está ya.
local function insertarPorId(t, clave, g)
    local l = t[clave]
    if not l then
        l = {}
        t[clave] = l
    end
    local lo, hi = 1, #l + 1
    while lo < hi do
        local medio = math.floor((lo + hi) / 2)
        if l[medio].id < g.id then
            lo = medio + 1
        else
            hi = medio
        end
    end
    if l[lo] and l[lo].id == g.id then
        l[lo] = g
        return
    end
    table.insert(l, lo, g)
end

--- Índice de grupos: todos en orden de id y, en el mismo orden, por nación,
-- por misión y por objetivo. No es estado: se rehace del estado. Los ids de
-- grupo son enteros que solo crecen (`siguienteGrupo`), así que un grupo que
-- nace va al final de cada lista; los que ya no están se saltan al leer y las
-- listas se compactan cuando sobran más muertos que vivos. La nación de un
-- grupo no cambia mientras vive; su misión y su objetivo sí: quien los cambie
-- llama a `reindexarGrupo`, que lo mete en su sitio de las listas nuevas, y
-- al leer se saltan los que ya no tienen esa misión o ese objetivo.
function Simulacion:indiceGrupos()
    local e = self.estado
    local c = self.cacheGrupos
    if not c or c.tabla ~= e.grupos then
        c = {
            siguiente = e.siguienteGrupo,
            tabla = e.grupos,
            lista = {},
            porNacion = {},
            porMision = {},
            porObjetivo = {},
        }
        for _, g in ipairs(lista(e.grupos)) do
            indexarGrupo(c, g)
        end
        self.cacheGrupos = c
    elseif c.siguiente ~= e.siguienteGrupo then
        for id = c.siguiente, e.siguienteGrupo - 1 do
            local g = e.grupos[id]
            if g then
                indexarGrupo(c, g)
            end
        end
        c.nuevos = (c.nuevos or 0) + e.siguienteGrupo - c.siguiente
        c.siguiente = e.siguienteGrupo
        if c.nuevos > math.max(64, #c.lista - c.nuevos) then
            -- Compacta (cada vez que la lista ha podido doblarse): vuelve a
            -- indexar solo los vivos, en el mismo orden.
            local viejos = c.lista
            c.lista, c.porNacion, c.porMision, c.porObjetivo = {}, {}, {}, {}
            for _, g in ipairs(viejos) do
                if e.grupos[g.id] == g then
                    indexarGrupo(c, g)
                end
            end
            c.nuevos = 0
        end
    end
    return c
end

--- Tras cambiar la misión o el objetivo de `g`: lo mete en las listas del
-- índice que le tocan ahora (las viejas lo saltan al leer).
function Simulacion:reindexarGrupo(g)
    local c = self.cacheGrupos
    if not c or c.tabla ~= self.estado.grupos or g.id >= c.siguiente then
        -- Sin índice, o aún no indexado: entrará con lo que tenga entonces.
        return
    end
    insertarPorId(c.porMision, g.mision, g)
    if g.objetivo ~= nil then
        insertarPorId(c.porObjetivo, g.objetivo, g)
    end
end

--- Los vivos de la lista `l` del índice, en su orden (una copia: se puede
-- cambiar el estado mientras se recorre); con `campo`, solo los que siguen
-- teniendo `valor` en él (la misión o el objetivo).
local function vivosDe(e, l, campo, valor)
    local out = {}
    if l then
        for _, g in ipairs(l) do
            if e.grupos[g.id] == g and (not campo or g[campo] == valor) then
                out[#out + 1] = g
            end
        end
    end
    return out
end

--- Grupos en orden de id, lo mismo que `lista(e.grupos)` pero sin ordenar
-- cada vez (ver `indiceGrupos`).
function Simulacion:gruposOrdenados()
    return vivosDe(self.estado, self:indiceGrupos().lista)
end

--- Grupos de la nación `nid`, en orden de id.
function Simulacion:gruposDe(nid)
    return vivosDe(self.estado, self:indiceGrupos().porNacion[nid])
end

--- Grupos con la misión `mision`, en orden de id.
function Simulacion:gruposConMision(mision)
    return vivosDe(self.estado, self:indiceGrupos().porMision[mision], 'mision', mision)
end

--- Grupos cuyo objetivo es `id` (un sitio, un yacimiento o un grupo), en orden de id.
function Simulacion:gruposHacia(id)
    return vivosDe(self.estado, self:indiceGrupos().porObjetivo[id], 'objetivo', id)
end

--- Grupos de las naciones `a` y `b`, en orden de id.
function Simulacion:gruposDeAmbas(a, b)
    local la, lb = self:gruposDe(a), self:gruposDe(b)
    local out = {}
    local i, j = 1, 1
    while i <= #la or j <= #lb do
        if j > #lb or (i <= #la and la[i].id < lb[j].id) then
            out[#out + 1] = la[i]
            i = i + 1
        else
            out[#out + 1] = lb[j]
            j = j + 1
        end
    end
    return out
end

-- Almacén, bóveda y afuera -------------------------------------------------------------------

--- Nivel de la capital de una nación (1 si no la tiene).
function Simulacion:nivelCapital(nid)
    local n = self.estado.naciones[nid]
    local c = n and self.estado.ciudades[n.capital]
    return c and c.nivel or 1
end

--- Tope del almacén de una nación, para el metal y para el petróleo (F1).
function Simulacion:almacen(nid)
    local tabla = Simulacion.almacenaje.nivel
    return tabla[math.max(1, math.min(#tabla, self:nivelCapital(nid)))]
end

--- Tope de la bóveda de una nación, para el dinero (F1b).
function Simulacion:boveda(nid)
    return Simulacion.almacenaje.bovedaFactor * self:almacen(nid)
end

-- Recursos que se guardan en el almacén o en la bóveda y pueden quedar afuera.
local RECURSOS_ALMACEN = { 'metal', 'petroleo', 'dinero' }
Simulacion.recursosAlmacen = RECURSOS_ALMACEN

local function guardado(n, recurso)
    if recurso == 'dinero' then
        return n.tesoro
    end
    return n.recursos[recurso] or 0
end

local function ponerGuardado(n, recurso, cantidad)
    if recurso == 'dinero' then
        n.tesoro = cantidad
    else
        n.recursos[recurso] = cantidad
    end
end

--- Lo que una nación puede gastar de un recurso ('metal', 'petroleo' o
-- 'dinero'): lo guardado más lo de afuera.
function Simulacion.disponible(n, recurso)
    return guardado(n, recurso) + n.afuera[recurso]
end
local disponible = Simulacion.disponible

--- Entra `cantidad` de un recurso: al almacén o a la bóveda hasta su tope, y
-- el resto afuera.
function Simulacion:ingresar(n, recurso, cantidad)
    if cantidad <= 0 then
        return
    end
    local tope = recurso == 'dinero' and self:boveda(n.id) or self:almacen(n.id)
    local tiene = guardado(n, recurso)
    local cabe = math.max(0, math.min(cantidad, tope - tiene))
    ponerGuardado(n, recurso, tiene + cabe)
    n.afuera[recurso] = n.afuera[recurso] + cantidad - cabe
end

--- Gasta `cantidad` de un recurso, primero de afuera y después de lo guardado.
-- Quien llama ya comprobó que alcanza (`disponible`).
local function gastar(n, recurso, cantidad)
    if n.consumo then
        n.consumo[recurso] = n.consumo[recurso] + cantidad * Simulacion.recoleccion.mediaConsumo
    end
    local deAfuera = math.min(n.afuera[recurso], cantidad)
    n.afuera[recurso] = n.afuera[recurso] - deAfuera
    ponerGuardado(n, recurso, guardado(n, recurso) - (cantidad - deAfuera))
end
Simulacion.gastar = gastar

--- ¿Le alcanza a la nación para `coste` ({ metal, petroleo, dinero })?
function Simulacion.alcanza(n, coste)
    for _, recurso in ipairs(RECURSOS_ALMACEN) do
        if disponible(n, recurso) < (coste[recurso] or 0) then
            return false
        end
    end
    return true
end

--- Paga `coste` si alcanza (primero de afuera). Devuelve si pagó.
function Simulacion.pagar(n, coste)
    if not Simulacion.alcanza(n, coste) then
        return false
    end
    for _, recurso in ipairs(RECURSOS_ALMACEN) do
        if (coste[recurso] or 0) > 0 then
            gastar(n, recurso, coste[recurso])
        end
    end
    return true
end

--- Merma de lo que está afuera (F2): una vez al día, antes de que entre nada.
function Simulacion:mermar()
    local queda = 1 - Simulacion.almacenaje.merma
    for _, n in ipairs(lista(self.estado.naciones)) do
        for _, recurso in ipairs(RECURSOS_ALMACEN) do
            n.afuera[recurso] = n.afuera[recurso] * queda
        end
    end
end

--- Lo que pasa del tope del almacén o de la bóveda sale afuera (si baja el
-- tope o si algo entró sin `ingresar`).
function Simulacion:ajustarAlmacen(n)
    for _, recurso in ipairs(RECURSOS_ALMACEN) do
        local tope = recurso == 'dinero' and self:boveda(n.id) or self:almacen(n.id)
        local tiene = guardado(n, recurso)
        if tiene > tope then
            ponerGuardado(n, recurso, tope)
            n.afuera[recurso] = n.afuera[recurso] + tiene - tope
        end
    end
end

--- Camino de (x0, y0) a (x1, y1): en línea recta. Los grupos no recorren el
-- mapa (no hay rutas ni carreteras): el presidente los manda, tardan lo que
-- tardarían en llegar y aparecen allí. Solo sirve para medir el viaje.
function Simulacion:trazar(x0, y0, x1, y1)
    -- Una ruta nueva pone a alguien en marcha: los activos se buscan de nuevo.
    self.cambiosMarcha = (self.cambiosMarcha or 0) + 1
    return { x0, y0, x1, y1 }
end

--- Largo total de una ruta.
function Simulacion.largoRuta(ruta)
    local largo = 0

    for k = 3, #ruta, 2 do
        largo = largo + hipotenusa(ruta[k] - ruta[k - 2], ruta[k + 1] - ruta[k - 1])
    end

    return largo
end

-- Largos acumulados de cada ruta (no es estado: sale de la ruta, que no cambia
-- una vez trazada). `acumulados[ruta][i]` es lo que mide la ruta hasta su punto i.
local acumulados = setmetatable({}, { __mode = 'k' })

local function acumuladosDe(ruta)
    local a = acumulados[ruta]
    if not a then
        a = { 0 }
        local largo = 0
        for k = 3, #ruta, 2 do
            largo = largo + hipotenusa(ruta[k] - ruta[k - 2], ruta[k + 1] - ruta[k - 1])
            a[#a + 1] = largo
        end
        acumulados[ruta] = a
    end
    return a
end

--- Punto de la ruta a `recorrido` px del inicio, y el rumbo del tramo. Busca
-- el tramo por bisección en los largos acumulados: cada paso de marcha lo pide.
function Simulacion.puntoEnRuta(ruta, recorrido)
    if #ruta < 4 then
        return ruta[1], ruta[2], 0
    end
    local a = acumuladosDe(ruta)
    local resto = math.max(0, recorrido)
    -- El primer tramo i (del punto i al i + 1) que llega a `resto`; si no, el último.
    local bajo, alto = 1, #a - 1
    while bajo < alto do
        local medio = math.floor((bajo + alto) / 2)
        if a[medio + 1] >= resto then
            alto = medio
        else
            bajo = medio + 1
        end
    end
    local k = bajo * 2 + 1
    local dx, dy = ruta[k] - ruta[k - 2], ruta[k + 1] - ruta[k - 1]
    local tramo = a[bajo + 1] - a[bajo]
    local t = tramo > 0 and math.min(1, (resto - a[bajo]) / tramo) or 1
    return ruta[k - 2] + dx * t, ruta[k - 1] + dy * t, math.atan2(dy, dx)
end

--- Dónde dibujar un grupo entre el paso de marcha anterior y el actual
-- (`fraccion` de 0 a 1, ver `fraccionPaso`) y hacia dónde mira. Un paso es
-- tan corto que basta la recta entre los dos puntos, también en las curvas de
-- la ruta y cuando una orden nueva la cambia: así nunca salta hacia atrás.
function Simulacion.posicionGrupo(g, fraccion)
    local ax, ay = g.antesX or g.x, g.antesY or g.y
    local x = ax + (g.x - ax) * fraccion
    local y = ay + (g.y - ay) * fraccion
    local angulo
    if g.ruta and g.largo and g.recorrido < g.largo then
        local _, _, a = Simulacion.puntoEnRuta(g.ruta, g.recorrido)
        angulo = a
    elseif g.x ~= ax or g.y ~= ay then
        angulo = math.atan2(g.y - ay, g.x - ax)
    elseif g.ruta and #g.ruta >= 4 then
        local n = #g.ruta
        angulo = math.atan2(g.ruta[n] - g.ruta[n - 2], g.ruta[n - 1] - g.ruta[n - 3])
    else
        angulo = math.atan2((g.destinoY or y) - y, (g.destinoX or x) - x)
    end
    return x, y, angulo
end

-- Estado -------------------------------------------------------------------------------

--- `opciones.sitioValido(x, y)` dice si se puede construir ahí (tierra firme,
-- fuera de las ciudades). Sale del mundo físico: no se guarda.
function Simulacion.nueva(semilla, opciones)
    local self = setmetatable({}, Simulacion)
    self.estado = {
        version = Simulacion.version,
        semilla = semilla,
        dia = 1,
        paso = 0, -- pasos de marcha hechos del día en curso (0: entre días)
        siguienteGrupo = 1,
        naciones = {},
        ciudades = {},
        depositos = {}, -- salen de la semilla: no se guardan (ver `rehacerYacimientos`)
        zonas = {}, -- zonas registradas: clave -> true
        instalaciones = {},
        grupos = {},
        minas = {}, -- yacimientos tocados: id -> { queda, agotadaHasta } (ver `recolectarDia`)
        batallas = {}, -- id -> batalla (ver `crearBatalla`)
        siguienteBatalla = 1,
        lideres = {}, -- presidentes y generales (ver `nombrarPresidente` y `nombrarGeneral`)
        guerras = {},
        noticias = {},
        territorio = {}, -- nación -> fila -> tramos de celdas (ver `mapaTerritorio`)
        versionTerritorio = 0, -- sube cada vez que cambia una celda
        exploradores = {}, -- id -> explorador en camino (ver `explorar`)
        siguienteExplorador = 1,
        informes = {}, -- nación -> { sitios, grupos } (ver `llegadaExploradores`)
        almacenes = {}, -- nación -> { misiles } (ver mundo/simulacion/almacen.lua)
        aviones = {}, -- id -> { id, nacion, base } (ver mundo/simulacion/aviones.lua)
        vuelos = {}, -- id -> vuelo en curso
    }
    self.sitioValido = opciones and opciones.sitioValido
    self.eventos = {}
    self.cambios = 0
    return self
end

function Simulacion:noticia(texto, color)
    local l = self.estado.noticias
    table.insert(l, 1, { dia = self.estado.dia, texto = texto, color = color or { 1, 1, 1 } })
    while #l > Simulacion.maxNoticias do
        table.remove(l)
    end
end

function Simulacion:nacion(id)
    return self.estado.naciones[id]
end

function Simulacion:ciudad(id)
    return self.estado.ciudades[id]
end

function Simulacion:instalacion(id)
    return self.estado.instalaciones[id]
end

--- Ciudad o instalación con ese id; una bandera del borde, aunque no esté
-- guardada (banderas.lua).
function Simulacion:sitio(id)
    local e = self.estado
    local s = e.ciudades[id] or e.instalaciones[id]
    if s or type(id) ~= 'string' or id:sub(1, 2) ~= 'f:' then
        return s
    end
    return self:banderaPorId(id)
end

--- Índices por nación (ciudades e instalaciones), en orden fijo. Se rehacen
-- solo cuando algo nace, cae o cambia de manos (`self.sucio`): consultar no
-- vuelve a ordenar todo el mundo cada vez.
-- Lado de la rejilla de instalaciones por posición (px): un bloque de
-- territorio mide como mucho 3000 px de medio lado, así que 3 x 3 celdas bastan
-- para encontrar las que cubren un punto.
local CELDA_INSTALACIONES = 8192
Simulacion.celdaInstalaciones = CELDA_INSTALACIONES

function Simulacion:indice()
    if self.indiceHecho and not self.sucio then
        return self.indiceHecho
    end
    local idx = {
        ciudades = {},
        instalaciones = {},
        porTipo = {}, -- nid -> tipo -> instalaciones (se llena al preguntar)
        todasInstalaciones = lista(self.estado.instalaciones),
    }
    -- Rejilla de ciudades por posición, como la de instalaciones.
    idx.rejillaCiudades = {}
    for _, c in ipairs(lista(self.estado.ciudades)) do
        idx.ciudades[c.nacion] = idx.ciudades[c.nacion] or {}
        table.insert(idx.ciudades[c.nacion], c)
        local clave = math.floor(c.x / CELDA_INSTALACIONES) * 65536 + math.floor(c.y / CELDA_INSTALACIONES)
        idx.rejillaCiudades[clave] = idx.rejillaCiudades[clave] or {}
        table.insert(idx.rejillaCiudades[clave], c)
    end
    for _, i in ipairs(idx.todasInstalaciones) do
        idx.instalaciones[i.nacion] = idx.instalaciones[i.nacion] or {}
        table.insert(idx.instalaciones[i.nacion], i)
    end
    -- Rejilla de instalaciones por posición: solo se miran las cercanas. Las
    -- bases, también aparte (`enFrontera` solo mira bases).
    idx.rejillaInstalaciones = {}
    idx.rejillaBases = {}
    for _, i in ipairs(idx.todasInstalaciones) do
        local clave = math.floor(i.x / CELDA_INSTALACIONES) * 65536 + math.floor(i.y / CELDA_INSTALACIONES)
        idx.rejillaInstalaciones[clave] = idx.rejillaInstalaciones[clave] or {}
        table.insert(idx.rejillaInstalaciones[clave], i)
        if i.tipo == 'base' then
            idx.rejillaBases[clave] = idx.rejillaBases[clave] or {}
            table.insert(idx.rejillaBases[clave], i)
        end
    end
    self.indiceHecho, self.sucio = idx, false
    return idx
end

--- Mete `inst` en la lista `t`, ordenada por id, en su sitio.
local function insertarOrdenado(t, inst)
    local k = #t + 1
    while k > 1 and t[k - 1].id > inst.id do
        t[k] = t[k - 1]
        k = k - 1
    end
    t[k] = inst
end

--- Apunta una instalación nueva en el índice sin rehacerlo entero (quedan
-- las mismas listas, en el mismo orden, que al rehacerlo). Si el índice ya
-- estaba por rehacer, solo lo marca.
function Simulacion:anotarInstalacion(inst)
    local idx = self.indiceHecho
    if not idx or self.sucio then
        self:ensuciar()
        return
    end
    -- La lista de todas no se toca aquí (meter en medio cuesta tantas como
    -- haya): se junta al pedirla (`todasInstalaciones`).
    idx.nuevasInstalaciones = idx.nuevasInstalaciones or {}
    table.insert(idx.nuevasInstalaciones, inst)
    idx.instalaciones[inst.nacion] = idx.instalaciones[inst.nacion] or {}
    insertarOrdenado(idx.instalaciones[inst.nacion], inst)
    local tipos = idx.porTipo[inst.nacion]
    if tipos and tipos[inst.tipo] then
        insertarOrdenado(tipos[inst.tipo], inst)
    end
    local clave = math.floor(inst.x / CELDA_INSTALACIONES) * 65536 + math.floor(inst.y / CELDA_INSTALACIONES)
    idx.rejillaInstalaciones[clave] = idx.rejillaInstalaciones[clave] or {}
    insertarOrdenado(idx.rejillaInstalaciones[clave], inst)
    if inst.tipo == 'base' then
        idx.rejillaBases[clave] = idx.rejillaBases[clave] or {}
        insertarOrdenado(idx.rejillaBases[clave], inst)
    end
end

--- Copia de la lista `t` sin las instalaciones del conjunto `fuera` (o nil
-- si `t` es nil). Se copia en vez de quitar en su sitio: quien esté
-- recorriendo la lista vieja no salta a nadie.
local function sinInstalaciones(t, fuera)
    if not t then
        return nil
    end
    local out = {}
    for _, i in ipairs(t) do
        if not fuera[i] then
            out[#out + 1] = i
        end
    end
    return out
end

--- Quita instalaciones borradas (la lista `quitadas`) del índice sin
-- rehacerlo entero (lo contrario de `anotarInstalacion`): quedan las mismas
-- listas, en el mismo orden, que al rehacerlo, y cada lista se recorre una
-- sola vez. Si el índice ya estaba por rehacer, solo lo marca.
function Simulacion:desanotarInstalaciones(quitadas)
    local idx = self.indiceHecho
    if #quitadas == 0 then
        return
    end
    if not idx or self.sucio then
        self:ensuciar()
        return
    end
    local fuera, naciones, claves = {}, {}, {}
    for _, inst in ipairs(quitadas) do
        fuera[inst] = true
        naciones[inst.nacion] = true
        claves[math.floor(inst.x / CELDA_INSTALACIONES) * 65536 + math.floor(inst.y / CELDA_INSTALACIONES)] = true
    end
    idx.nuevasInstalaciones = sinInstalaciones(idx.nuevasInstalaciones, fuera)
    idx.todasInstalaciones = sinInstalaciones(idx.todasInstalaciones, fuera)
    for nid in pairs(naciones) do
        idx.instalaciones[nid] = sinInstalaciones(idx.instalaciones[nid], fuera)
        for tipo, l in pairs(idx.porTipo[nid] or {}) do
            idx.porTipo[nid][tipo] = sinInstalaciones(l, fuera)
        end
        if idx.cubren then
            idx.cubren[nid] = nil
        end
    end
    for clave in pairs(claves) do
        idx.rejillaInstalaciones[clave] = sinInstalaciones(idx.rejillaInstalaciones[clave], fuera)
        idx.rejillaBases[clave] = sinInstalaciones(idx.rejillaBases[clave], fuera)
    end
end

--- Quita una instalación borrada del índice (ver `desanotarInstalaciones`).
function Simulacion:desanotarInstalacion(inst)
    self:desanotarInstalaciones({ inst })
end

--- Todas las instalaciones en orden de id (del índice: no se cambia). Junta
-- las que se anotaron desde la última vez.
function Simulacion:todasInstalaciones()
    local idx = self:indice()
    local nuevas = idx.nuevasInstalaciones
    if nuevas and #nuevas > 0 then
        table.sort(nuevas, function(a, b)
            return a.id < b.id
        end)
        local viejas = idx.todasInstalaciones
        local out = {}
        local i, j = 1, 1
        while i <= #viejas or j <= #nuevas do
            if j > #nuevas or (i <= #viejas and viejas[i].id < nuevas[j].id) then
                out[#out + 1] = viejas[i]
                i = i + 1
            else
                out[#out + 1] = nuevas[j]
                j = j + 1
            end
        end
        idx.todasInstalaciones = out
        idx.nuevasInstalaciones = nil
    end
    return idx.todasInstalaciones
end

--- Marca el índice para rehacerlo (algo nació, cayó o cambió de manos). El
-- territorio no cambia aquí: cambia celda a celda (`ponerCelda`).
function Simulacion:ensuciar()
    self.sucio = true
end

--- Algo nació o cayó en `sitio` (una instalación): el índice se rehace.
function Simulacion:ensuciarEn(_sitio)
    self.sucio = true
end

function Simulacion:ciudadesDe(nid)
    return self:indice().ciudades[nid] or {}
end

--- Instalación que explota un yacimiento: ya no hay (las extracciones
-- desaparecieron y los campamentos no producen). Queda para la vista de
-- antes: siempre nil.
function Simulacion.explotacion()
    return nil
end

-- Lado de la rejilla de yacimientos para buscar los cercanos a un punto.
local CELDA_DEPOSITOS = 8192

--- Yacimientos registrados a menos de `radio` de (x, y), en orden fijo.
function Simulacion:depositosCerca(x, y, radio)
    if not self.rejillaDepositos then
        self.listaDepositos = self.listaDepositos or lista(self.estado.depositos)
        local rejilla = {}
        for _, d in ipairs(self.listaDepositos) do
            local clave = math.floor(d.x / CELDA_DEPOSITOS) * 65536 + math.floor(d.y / CELDA_DEPOSITOS)
            rejilla[clave] = rejilla[clave] or {}
            table.insert(rejilla[clave], d)
        end
        self.rejillaDepositos = rejilla
    end
    local out = {}
    for cy = math.floor((y - radio) / CELDA_DEPOSITOS), math.floor((y + radio) / CELDA_DEPOSITOS) do
        for cx = math.floor((x - radio) / CELDA_DEPOSITOS), math.floor((x + radio) / CELDA_DEPOSITOS) do
            for _, d in ipairs(self.rejillaDepositos[cx * 65536 + cy] or {}) do
                if hipotenusa(d.x - x, d.y - y) <= radio then
                    out[#out + 1] = d
                end
            end
        end
    end
    return out
end

function Simulacion:instalacionesDe(nid, tipo)
    local idx = self:indice()
    local todas = idx.instalaciones[nid] or {}
    if not tipo then
        return todas
    end
    local tipos = idx.porTipo[nid]
    if not tipos then
        tipos = {}
        idx.porTipo[nid] = tipos
    end
    local out = tipos[tipo]
    if not out then
        out = {}
        for _, i in ipairs(todas) do
            if i.tipo == tipo then
                out[#out + 1] = i
            end
        end
        tipos[tipo] = out
    end
    return out
end

--- Sitios con fuerzas de una nación: sus ciudades y sus bases terminadas.
function Simulacion:sitiosDe(nid)
    local out = {}
    for _, c in ipairs(self:ciudadesDe(nid)) do
        out[#out + 1] = c
    end
    for _, b in ipairs(self:instalacionesDe(nid, 'base')) do
        if b.progreso >= 1 then
            out[#out + 1] = b
        end
    end
    return out
end

--- Naciones con alguna ciudad, en orden de id (una copia). La lista se
-- guarda en el índice: cambia solo cuando nace una nación o una ciudad
-- cambia de manos, y las dos cosas rehacen el índice.
function Simulacion:vivas()
    local idx = self:indice()
    if not idx.vivas then
        idx.vivas = {}
        for _, n in ipairs(lista(self.estado.naciones)) do
            if idx.ciudades[n.id] and #idx.ciudades[n.id] > 0 then
                idx.vivas[#idx.vivas + 1] = n
            end
        end
    end
    local out = {}
    for k, n in ipairs(idx.vivas) do
        out[k] = n
    end
    return out
end

local function fuerzaDe(s)
    return (s.soldados or 0) * FUERZA.soldados
        + (s.misiles or 0) * FUERZA.misiles
        + (s.interceptores or 0) * FUERZA.interceptores
        + (s.aviones or 0) * FUERZA.aviones
end
Simulacion.fuerzaDe = fuerzaDe

function Simulacion:fuerzaCiudad(c)
    return fuerzaDe(c)
end

function Simulacion:fuerza(nid)
    local total = Simulacion.tecnologiasQueCuentan(self.estado.naciones[nid]) * 12
    for _, s in ipairs(self:ciudadesDe(nid)) do
        total = total + fuerzaDe(s)
    end
    for _, i in ipairs(self:instalacionesDe(nid)) do
        total = total + fuerzaDe(i)
    end
    for _, g in ipairs(self:gruposDe(nid)) do
        total = total + fuerzaDe(g)
    end
    return total
end

--- Coordenadas de zona de un id 'z:zx,zy' (o nil).
local function coordenadasZona(id)
    local zx, zy = tostring(id):match('^z:(%-?%d+),(%-?%d+)$')
    return tonumber(zx), tonumber(zy)
end

--- Relación de partida entre `a` y `b` (ids de nación): el azar del par, igual
-- se registre antes la una o la otra (-30 a 30), +30 si son del mismo orden
-- político y -25 si de órdenes opuestos. No se guarda: sale de la semilla.
function Simulacion:relacionInicial(a, b)
    local e = self.estado
    if b < a then
        a, b = b, a
    end
    local ax, ay = coordenadasZona(a)
    local bx, by = coordenadasZona(b)
    local h = Ruido.hash(Ruido.hash(e.semilla, ax or 0, ay or 0, 58), bx or 0, by or 0, 59)
    local base = Ruido.azar(h)(-30, 30)
    local na, nb = e.naciones[a], e.naciones[b]
    if na.orden == nb.orden then
        base = base + 30
    elseif Simulacion.ordenes[na.orden].opuesto == nb.orden or Simulacion.ordenes[nb.orden].opuesto == na.orden then
        base = base - 25
    end
    return base
end

--- Relación entre `a` y `b` (-100 a 100): la que se apuntó al cambiar o, si
-- nunca cambió, la de partida. Solo se guardan las que cambian.
function Simulacion:relacion(a, b)
    local v = self.estado.naciones[a].relaciones[b]
    if v == nil then
        return self:relacionInicial(a, b)
    end
    return v
end

--- Vecinas de `nid` (ver `alcanceVecinas`), en orden de id. Se calcula con una
-- rejilla de capitales y se rehace al registrar una nación (no es estado).
function Simulacion:vecinas(nid)
    local e = self.estado
    if not self.cacheVecinas then
        local lado = Simulacion.alcanceVecinas
        local rejilla, capitales = {}, {}
        for _, id in ipairs(ordenadas(e.naciones)) do
            local c = e.ciudades[e.naciones[id].capital]
            if c then
                capitales[#capitales + 1] = { id = id, x = c.x, y = c.y }
                local clave = math.floor(c.x / lado) * 65536 + math.floor(c.y / lado)
                rejilla[clave] = rejilla[clave] or {}
                table.insert(rejilla[clave], capitales[#capitales])
            end
        end
        local cache = {}
        for _, p in ipairs(capitales) do
            local suyas = {}
            local cx, cy = math.floor(p.x / lado), math.floor(p.y / lado)
            for dx = -1, 1 do
                for dy = -1, 1 do
                    for _, o in ipairs(rejilla[(cx + dx) * 65536 + cy + dy] or {}) do
                        if o.id ~= p.id and hipotenusa(o.x - p.x, o.y - p.y) < lado then
                            suyas[#suyas + 1] = o.id
                        end
                    end
                end
            end
            table.sort(suyas)
            cache[p.id] = suyas
        end
        self.cacheVecinas = cache
    end
    return self.cacheVecinas[nid] or {}
end

function Simulacion:guerraEntre(a, b)
    return self.estado.guerras[claveGuerra(a, b)]
end

function Simulacion:guerrasDe(nid)
    local out = {}
    for _, g in ipairs(lista(self.estado.guerras)) do
        if g.atacante == nid or g.defensor == nid then
            out[#out + 1] = g
        end
    end
    return out
end

--- Cuántas guerras tiene `nid` (contar no depende del orden: sin ordenar).
function Simulacion:numeroGuerras(nid)
    local cuantas = 0
    for _, g in pairs(self.estado.guerras) do
        if g.atacante == nid or g.defensor == nid then
            cuantas = cuantas + 1
        end
    end
    return cuantas
end

function Simulacion:tiene(nid, tecnologia)
    local n = self.estado.naciones[nid]
    for k = 1, n.tecnologia do
        if Simulacion.tecnologias[k].id == tecnologia then
            return true
        end
    end
    return false
end

-- Registro de lo que sale de la semilla -----------------------------------------------------

--- Registra una nación entera (su zona): capital, ciudades y depósitos.
-- `zona = { clave, ciudades = { {id, nombre, x, y, radio, altura}, ... }, depositos = {...} }`
-- La primera ciudad de la lista es la capital. Si ya existe (partida cargada), no se toca.
function Simulacion:registrarZona(zona)
    local e = self.estado
    e.zonas[zona.clave] = true
    self:anotarYacimientos(zona)
    if #zona.ciudades == 0 or e.naciones[zona.clave] then
        return e.naciones[zona.clave]
    end

    local capital = zona.ciudades[1]
    local azar = Ruido.azar(Ruido.hash(e.semilla, math.floor(capital.x), math.floor(capital.y), 57))
    local orden = Simulacion.listaOrdenes[math.floor(azar(1, 3.99))]
    local titulos = TITULOS[orden]
    local _ = azar() -- antes era el tono del color; se sigue tirando para no cambiar los demás sorteos
    local nid = zona.clave
    local nacion = {
        id = nid,
        nombre = titulos[math.floor(azar(1, #titulos + 0.99))] .. ' ' .. capital.nombre,
        orden = orden,
        color = Simulacion.colorNacion(nid),
        gobernante = {
            nombre = NOMBRES[math.floor(azar(1, #NOMBRES + 0.99))] .. ' ' .. APELLIDOS[math.floor(
                azar(1, #APELLIDOS + 0.99)
            )],
            agresividad = azar(0.1, 1),
            prudencia = azar(0.1, 1),
        },
        capital = capital.id,
        tecnologia = 0,
        investigacion = 0,
        recursos = { metal = 12, petroleo = 6 }, -- la comida está en cada ciudad
        relaciones = {},
        treguas = {},
        cansancio = 0,
        bases = 0,
        tesoro = 0,
        afuera = { metal = 0, petroleo = 0, dinero = 0 }, -- lo que no cabe en el almacén ni en la bóveda
        -- Medias de unos 10 días de lo gastado y lo recolectado (la IA de recolección, F9).
        consumo = { metal = 0, petroleo = 0, dinero = 0 },
        recolectado = { metal = 0, petroleo = 0, comida = 0, oro = 0 },
    }
    e.naciones[nid] = nacion
    self:nombrarPresidente(nacion)

    for k, c in ipairs(zona.ciudades) do
        if not e.ciudades[c.id] then
            local poblacion = math.floor(c.radio * azar(8, 14) * (k == 1 and 1.4 or 1))
            local soldados = math.floor(poblacion * azar(0.05, 0.09))
            -- Antes, sus tanques: la tirada se queda para que cada semilla
            -- siga dando el mismo mundo.
            azar(1, 5)
            e.ciudades[c.id] = {
                id = c.id,
                nombre = c.nombre,
                x = c.x,
                y = c.y,
                radio = c.radio,
                casco = c.casco, -- tamaño físico de sus calles (el mundo lo da)
                altura = c.altura,
                nacion = nid,
                poblacion = poblacion,
                soldados = soldados,
                -- Arsenal con el que nace: un país ya tiene ejército desde el principio.
                interceptores = k == 1 and Simulacion.arsenalInicial.capital.interceptores
                    or Simulacion.arsenalInicial.ciudad.interceptores,
                lanzacohetes = k == 1 and Simulacion.arsenalInicial.capital.lanzacohetes
                    or Simulacion.arsenalInicial.ciudad.lanzacohetes,
                baterias = k == 1 and Simulacion.arsenalInicial.capital.baterias
                    or Simulacion.arsenalInicial.ciudad.baterias,
                aviones = 0,
                comida = Simulacion.consumo.comidaInicial,
                nivel = Simulacion.nivelInicial(c.radio, k == 1),
                vida = Simulacion.vidaCiudad.maxima,
            }
            local ciudad = e.ciudades[c.id]
            -- Nace con modelos de la era 1 (Scud-B).
            for _, tipo in ipairs(Armamento.TIPOS) do
                if ciudad[tipo] > 0 then
                    ciudad[Armamento.POR[tipo]] = { [Armamento.modeloInicial(tipo)] = ciudad[tipo] }
                end
            end
            local arsenal = k == 1 and Simulacion.arsenalInicial.capital or Simulacion.arsenalInicial.ciudad
            ciudad.municion = Simulacion.dotacion(ciudad, Simulacion.produccion.reservaMunicion)
            ciudad.municion.misiles = ciudad.municion.misiles + arsenal.misiles
            -- Su gente por edades y sexo, con sus soldados en filas (diseno/poblacion.md, F11).
            ciudad.demografia = Simulacion.Poblacion.crearDemografia(ciudad.poblacion, ciudad.soldados)
            ciudad.poblacion = Simulacion.Poblacion.total(ciudad.demografia)
        end
    end

    -- Las relaciones de partida no se guardan: salen de `relacionInicial`.
    self.cacheVecinas = nil
    self:ensuciar()
    -- Cada ciudad siembra su bloque de territorio (la capital, la primera).
    for _, c in ipairs(zona.ciudades) do
        if e.ciudades[c.id].nacion == nid then
            self:reclamarBloque(e.ciudades[c.id])
        end
    end
    self:noticia(
        string.format(
            '%s (%s): capital %s, presidente %s',
            nacion.nombre,
            Simulacion.ordenes[orden].nombre,
            capital.nombre,
            nacion.gobernante.nombre
        ),
        nacion.color
    )
    -- Su primer avión, en la capital (mundo/simulacion/aviones.lua).
    self:avionInicial(nid)
    return nacion
end

--- Mete en el estado los yacimientos de `zona` que aún no están.
function Simulacion:anotarYacimientos(zona)
    local e = self.estado
    self.listaDepositos, self.rejillaDepositos, self.cacheConocidos = nil, nil, nil
    for _, d in ipairs(zona.depositos or {}) do
        if not e.depositos[d.id] then
            e.depositos[d.id] = { id = d.id, tipo = d.tipo, x = d.x, y = d.y, riqueza = d.riqueza }
        end
    end
end

--- Vuelve a poner los yacimientos de todas las zonas registradas (al
-- cargar: el guardado no los lleva). `datosZona(zx, zy)` da la zona como a
-- `registrarZona` (sale de la semilla). Devuelve false si no hay con qué.
function Simulacion:rehacerYacimientos(datosZona)
    local e = self.estado
    local claves = ordenadas(e.zonas)
    if #claves > 0 and not datosZona then
        return false
    end
    for _, clave in ipairs(claves) do
        local zx, zy = clave:match('^z:(%-?%d+),(%-?%d+)$')
        self:anotarYacimientos(datosZona(tonumber(zx), tonumber(zy)))
    end
    return true
end

function Simulacion:todasCiudades()
    local idx = self:indice()
    if not idx.todasCiudades then
        idx.todasCiudades = lista(self.estado.ciudades)
    end
    return idx.todasCiudades
end

-- Territorio por celdas (mundo/simulacion/territorio.lua) --------------------------------------

local CELDA = Simulacion.celda
local claveCelda = Ayudas.claveCelda
local VECINOS = Ayudas.VECINOS
Simulacion.daTerritorio = daTerritorio
require('mundo.simulacion.territorio').instalar(Simulacion)

-- Banderas del borde (mundo/simulacion/banderas.lua) -----------------------------------------

require('mundo.simulacion.banderas').instalar(Simulacion)
require('mundo.simulacion.guarnicion').instalar(Simulacion)

--- ¿Puede `nid` atacar `objetivoId`? Una bandera enemiga (guardada o del
-- borde) solo se ataca si el trozo de territorio donde está toca por un lado
-- una celda de quien ataca. Lo demás, siempre; una mina (un yacimiento), en
-- cualquier sitio, sin mirar fronteras. Devuelve true, o false y el motivo:
-- 'nacion', 'objetivo' o 'sinFrontera'.
function Simulacion:puedeAtacar(nid, objetivoId)
    local e = self.estado
    if not e.naciones[nid] then
        return false, 'nacion'
    end
    if e.depositos[objetivoId] then
        return true
    end
    local objetivo = self:sitio(objetivoId)
    if not objetivo then
        return false, 'objetivo'
    end
    if objetivo.nacion == nid or objetivo.tipo ~= 'bandera' then
        return true
    end
    if not self:tocaTrozo(nid, objetivo) then
        return false, 'sinFrontera'
    end
    return true
end

-- Líderes y generales (mundo/simulacion/lideres.lua) ----------------------------------------

require('mundo.simulacion.lideres').instalar(Simulacion)

-- Jugador y escenario de prueba ---------------------------------------------------------------
--
-- Una nación con `n.jugador = true` la gobierna una persona: la IA diaria no
-- decide por ella (ni guerras, ni envíos, ni obras, ni paz, ni producción, ni
-- convoyes de munición), pero todo lo demás le pasa igual (sus fábricas,
-- sueldos, taller y daño).
-- Los NPC la tratan como a cualquier otra nación y pueden atacarla.

-- Lo que el escenario de prueba suma a la capital de cada uno de los dos.
Simulacion.escenario = { soldados = 300, lanzacohetes = 4, petroleo = 30 }

--- Naciones de jugador, en orden fijo.
function Simulacion:jugadores()
    local out = {}
    for _, n in ipairs(lista(self.estado.naciones)) do
        if n.jugador then
            out[#out + 1] = n
        end
    end
    return out
end

--- Escenario para probar el combate: la nación viva cuya capital está más
-- cerca del origen del mundo pasa a ser del jugador; la capital viva más
-- cercana a la suya es su rival NPC. El jugador le declara la guerra y las
-- dos capitales reciben tropas (`c.soldados`, `c.lanzacohetes`
-- y `c.petroleo` del comando; lo que falte, de `Simulacion.escenario`).
-- Devuelve { jugador, rival, capitalJugador, capitalRival } (ids) o false si
-- no hay dos naciones vivas.
function Simulacion:escenarioPrueba(c)
    local e = self.estado
    local capitales = {}
    for _, n in ipairs(self:vivas()) do
        local capital = e.ciudades[n.capital]
        if capital and capital.nacion == n.id then
            capitales[#capitales + 1] = { nacion = n, ciudad = capital }
        end
    end
    local function masCerca(x, y, salvo)
        local mejor, mejorD
        for _, p in ipairs(capitales) do
            local d = hipotenusa(p.ciudad.x - x, p.ciudad.y - y)
            if p ~= salvo and (not mejorD or d < mejorD) then
                mejor, mejorD = p, d
            end
        end
        return mejor
    end
    local jugador = masCerca(0, 0)
    local rival = jugador and masCerca(jugador.ciudad.x, jugador.ciudad.y, jugador)
    if not rival then
        return false
    end
    jugador.nacion.jugador = true
    self:ejecutar({
        tipo = 'declararGuerra',
        nacion = jugador.nacion.id,
        contra = rival.nacion.id,
        motivo = 'escenario de prueba',
    })
    local reglas = Simulacion.escenario
    for _, p in ipairs({ jugador, rival }) do
        local capital = p.ciudad
        local soldados = c.soldados or reglas.soldados
        capital.soldados = capital.soldados + soldados
        -- Salen de su gente (diseno/poblacion.md).
        self:reclutar(capital, soldados)
        local n = p.nacion
        -- Del modelo que encargaría esa nación hoy.
        capital.lanzacohetes = capital.lanzacohetes or 0
        for _, tipo in ipairs(Armamento.TIPOS) do
            -- Sin pasar del tope de la ciudad (QA 2026-10-01: salía «6 / 5»).
            local hueco = math.max(0, self:topeCiudad(capital, tipo) - (capital[tipo] or 0))
            local cantidad = math.min(c[tipo] or reglas[tipo], hueco)
            Armamento.meter(capital, tipo, self:modeloPorDefecto(n.id, tipo), cantidad)
        end
        self:ingresar(n, 'petroleo', c.petroleo or reglas.petroleo)
        n.sinCombustible = disponible(n, 'petroleo') < self:gastoCombustible(n.id)
    end
    self:noticia(
        string.format('Escenario de prueba: %s (jugador) contra %s', jugador.nacion.nombre, rival.nacion.nombre),
        jugador.nacion.color
    )
    return {
        jugador = jugador.nacion.id,
        rival = rival.nacion.id,
        capitalJugador = jugador.ciudad.id,
        capitalRival = rival.ciudad.id,
    }
end

-- Comandos --------------------------------------------------------------------------------

function Simulacion:ejecutar(c)
    local t = c.tipo
    -- Un comando puede poner en marcha (o parar) a cualquier grupo.
    self.activos = nil
    if t == 'declararGuerra' then
        return self:declararGuerra(c.nacion, c.contra, c.motivo)
    elseif t == 'campamento' then
        return self:levantarCampamento(c.nacion, c.x, c.y)
    elseif t == 'enviarGrupo' and c.grupo then
        -- Un grupo que ya recolecta en la mina ataca allí sin moverse (3.5.5).
        return self:atacarDesdeMina(c.nacion, c.grupo, c.objetivo, c.lider)
    elseif t == 'enviarGrupo' then
        return self:enviarGrupo(
            c.nacion,
            c.desde,
            c.mision,
            c.objetivo,
            c.construye,
            c.soldados,
            c.lanzacohetes,
            c.retirada,
            c.lider,
            c.municion,
            c.modelos
        )
    elseif t == 'altoElFuego' then
        local g = self:guerraEntre(c.nacion, c.contra)
        return g and self:altoElFuego(g, c.dias or 15)
    elseif t == 'firmarPaz' then
        local g = self:guerraEntre(c.nacion, c.contra)
        return g and self:firmarPaz(g)
    elseif t == 'mejorarCiudad' then
        return self:mejorarCiudad(c.nacion, c.ciudad)
    elseif t == 'plantarHuerto' then
        return self:plantarHuerto(c.nacion, c.ciudad)
    elseif t == 'enviarDefensas' then
        return self:enviarDefensas(c.nacion, c.ciudad or c.base, c.defensa, c.cantidad, c.pagaTesoro)
    elseif t == 'acelerarRecuperacion' then
        return self:acelerarRecuperacion(c.nacion, c.ciudad, c.tropa, c.cantidad, c.pagaTesoro)
    elseif t == 'escenarioPrueba' then
        return self:escenarioPrueba(c)
    elseif t == 'reparar' then
        return self:reparar(c.nacion, c.ciudad, c.puntos)
    elseif t == 'fabricarAvion' then
        return self:fabricarAvion(c.nacion, c.ciudad)
    elseif t == 'bandera' then
        return self:plantarBandera(c.nacion, c.x, c.y)
    elseif t == 'recolectar' then
        return self:recolectar(
            c.nacion,
            c.desde,
            c.yacimiento,
            c.soldados,
            c.lanzacohetes,
            c.municion,
            c.modelos
        )
    elseif t == 'retirar' or t == 'regresarGrupo' then
        return self:retirarGrupo(c.nacion, c.grupo)
    elseif t == 'regresarTodos' then
        return self:regresarTodos(c.nacion, c.batalla)
    elseif t == 'guarnecer' then
        return self:guarnecer(c.nacion, c.grupo, c.bandera)
    elseif t == 'redirigir' then
        return self:redirigir(c.nacion, c.grupo, c.destino)
    elseif t == 'irAPunto' then
        -- Manda un grupo propio a un punto del mapa (dueño 2026-09-29): el
        -- jugador puede caminar con el ejército por el mundo, no solo entre
        -- ciudades. Si el punto cae sobre una ciudad enemiga, el grupo la
        -- ataca al llegar; si cae sobre una propia, simplemente camina.
        return self:irAPunto(c.nacion, c.grupo, c.x, c.y)
    elseif t == 'entrarBatalla' then
        return self:entrarBatalla(c.nacion, c.batalla)
    elseif t == 'explorar' then
        return self:explorar(c.nacion, c.desde, c.objetivo)
    elseif t == 'noDefender' then
        return self:noDefender(c.nacion, c.batalla)
    elseif t == 'resolverBatalla' then
        return self:resolverBatalla(c)
    elseif t == 'producir' then
        -- Unidades o munición (produccion.lua); también la forma { municion, lotes }.
        return self:producir(c.nacion, c.ciudad, c.tropa or c.municion, c.cantidad or c.lotes, c.modelo)
    elseif t == 'cancelarProduccion' then
        return self:cancelarProduccion(c.nacion, c.ciudad, c.orden)
    elseif t == 'abastecer' then
        return self:abastecer(c.nacion, c.desde, c.grupo, c.balas, c.misiles)
    elseif t == 'misilesAlmacen' then
        return self:ponerMisilesAlmacen(c.nacion, c.misiles)
    elseif t == 'sumarMisilesAlmacen' then
        return self:sumarMisilesAlmacen(c.nacion, c.cantidad)
    elseif t == 'pagarAlmacen' then
        return self:pagarAlmacen(c.nacion, c.coste)
    end
    return false, 'tipoDesconocido'
end

--- Empieza a mejorar una ciudad al nivel siguiente, pagando del almacén del
-- país. Solo su presidente (o, más adelante, el jugador que la gobierne), una
-- mejora a la vez por ciudad.
function Simulacion:mejorarCiudad(nid, cid)
    local e = self.estado
    local n, c = e.naciones[nid], e.ciudades[cid]
    if not (n and c) or c.nacion ~= nid or c.mejora then
        return false, 'noEsSuya'
    end
    local siguiente = Simulacion.niveles[(c.nivel or 1) + 1]
    if not siguiente then
        return false, 'nivelMaximo'
    end
    if not Simulacion.pagar(n, siguiente.mejora) then
        return false, 'coste'
    end
    c.mejora = { nivel = (c.nivel or 1) + 1, hasta = e.dia + siguiente.dias }
    return true
end

--- Planta un huerto junto a una ciudad propia que no lo tenga: en el primer
-- sitio de tierra firme a su alrededor (en orden fijo desde un ángulo que sale
-- de la ciudad), pagando el metal del almacén del país.
function Simulacion:plantarHuerto(nid, cid)
    local e = self.estado
    local n, c = e.naciones[nid], e.ciudades[cid]
    if not (n and c) or c.nacion ~= nid or c.huerto or disponible(n, 'metal') < Simulacion.huerto.coste then
        return false, 'noPuede'
    end
    local inicio = Ruido.azar(Ruido.hash(e.semilla, math.floor(c.x), math.floor(c.y), 61))() * math.pi * 2
    local r = Simulacion.casco(c) + Simulacion.huerto.distancia
    for k = 0, 7 do
        local angulo = inicio + k * math.pi / 4
        local x, y = c.x + math.cos(angulo) * r, c.y + math.sin(angulo) * r
        if not self.sitioValido or self.sitioValido(x, y) then
            gastar(n, 'metal', Simulacion.huerto.coste)
            c.huerto = { x = x, y = y, hasta = e.dia + Simulacion.huerto.dias }
            return true
        end
    end
    return false, 'sinSitio'
end

--- Lo que cuesta reparar `puntos` de vida de una ciudad (F4).
function Simulacion.costeReparacion(puntos)
    local coste = Simulacion.vidaCiudad.coste
    return { metal = coste.metal * puntos, petroleo = coste.petroleo * puntos, dinero = coste.dinero * puntos }
end

--- Puntos de vida al día que recupera una ciudad en reparación (F5).
function Simulacion.ritmoReparacion(c)
    return Simulacion.vidaCiudad.ritmoBase + (c.nivel or 1)
end

--- Días que le quedan a la reparación encargada de una ciudad (0 si no hay).
-- No cuenta los días de asedio, que la paran.
function Simulacion.diasReparacion(c)
    return math.ceil((c.reparacion or 0) / Simulacion.ritmoReparacion(c))
end

--- Encarga `puntos` de vida para una ciudad propia (3.5): se paga todo al
-- empezar (F4, primero de afuera) y entra en `c.reparacion`, que sube la vida
-- `ritmoReparacion` al día salvo si está sitiada. Se pueden encargar más
-- mientras sigue, hasta llenar a 100. Devuelve false si no es suya, si pasa
-- de 100 o si no alcanza.
function Simulacion:reparar(nid, cid, puntos)
    local e = self.estado
    local n, c = e.naciones[nid], e.ciudades[cid]
    puntos = math.floor(tonumber(puntos) or 0)
    if not (n and c) or c.nacion ~= nid or puntos < 1 then
        return false, 'noEsSuya'
    end
    if (c.vida or Simulacion.vidaCiudad.maxima) + (c.reparacion or 0) + puntos > Simulacion.vidaCiudad.maxima then
        return false, 'pasaDelMaximo'
    end
    if not Simulacion.pagar(n, Simulacion.costeReparacion(puntos)) then
        return false, 'coste'
    end
    c.reparacion = (c.reparacion or 0) + puntos
    return true
end

--- Un día de reparación de una ciudad: sube su vida si no está sitiada.
function Simulacion:avanzarReparacion(c)
    if not c.reparacion or self:sitiada(c) then
        return
    end
    local maxima = Simulacion.vidaCiudad.maxima
    local sube = math.max(0, math.min(c.reparacion, Simulacion.ritmoReparacion(c), maxima - c.vida))
    c.vida = c.vida + sube
    c.reparacion = c.reparacion - sube
    if c.reparacion <= 0 or c.vida >= maxima then
        c.reparacion = nil
    end
end

--- El presidente NPC repara sus ciudades por debajo de `umbralIA` que no
-- estén sitiadas: los puntos que pueda pagar sin bajar de `reservaMetal` de
-- metal ni de `reservaTesoro` de dinero.
function Simulacion:planearReparaciones(n)
    local reglas = Simulacion.vidaCiudad
    for _, c in ipairs(self:ciudadesDe(n.id)) do
        local vida = c.vida or reglas.maxima
        if vida < reglas.umbralIA and not self:sitiada(c) then
            local puntos = reglas.maxima - vida - (c.reparacion or 0)
            puntos = math.min(
                puntos,
                math.floor((disponible(n, 'metal') - Simulacion.consumo.reservaMetal) / reglas.coste.metal),
                math.floor(disponible(n, 'petroleo') / reglas.coste.petroleo),
                math.floor((disponible(n, 'dinero') - Simulacion.recuperacion.reservaTesoro) / reglas.coste.dinero)
            )
            if puntos >= 1 then
                self:ejecutar({ tipo = 'reparar', nacion = n.id, ciudad = c.id, puntos = puntos })
            end
        end
    end
end

--- Pone defensas en un sitio propio. Lanzacohetes: los COLOCA desde el
-- parque de su ciudad (no se compran: se producen con `producir`); en una
-- ciudad, en sus plataformas al momento; en una base terminada, los lleva un
-- convoy desde su ciudad. Baterías antiaéreas: se compran (tesoro y almacén)
-- y se instalan en una ciudad. Siempre hasta el tope de plataformas del
-- sitio. Devuelve cuántas puso, o false y el motivo: 'noEsSuya', 'sitiada',
-- 'sitio', 'tope', 'parque' (no hay lanzacohetes en el parque) o 'coste'.
-- `pagaTesoro` queda por compatibilidad: ya solo hay un dinero.
function Simulacion:enviarDefensas(nid, sid, defensa, cantidad)
    local e = self.estado
    local n, c = e.naciones[nid], self:sitio(sid)
    if not (n and c) or c.nacion ~= nid or (defensa ~= 'lanzacohetes' and defensa ~= 'baterias') then
        return false, 'noEsSuya'
    end
    if esCiudad(c) then
        if self:sitiada(c) then
            return false, 'sitiada'
        end
    elseif not (c.tipo == 'base' and c.progreso >= 1 and defensa == 'lanzacohetes') then
        return false, 'sitio'
    end
    local libre
    if esCiudad(c) then
        libre = Simulacion.topeLanzacohetes(c) - (c[defensa] or 0)
    else
        -- Lo que ya va de camino a la base cuenta: no se manda de más.
        libre = Simulacion.topeLanzacohetes(c) - (c[defensa] or 0) - self:enCamino(c.id, defensa)
    end
    local quiere = math.min(math.floor(cantidad or 1), libre)
    if quiere < 1 then
        return false, 'tope'
    end
    if defensa == 'baterias' then
        local coste = Simulacion.defensasCiudad.coste.baterias
        local puestas = 0
        for _ = 1, quiere do
            if not Simulacion.pagar(n, coste) then
                break
            end
            puestas = puestas + 1
        end
        if puestas == 0 then
            return false, 'coste'
        end
        c.baterias = (c.baterias or 0) + puestas
        return puestas
    end
    local ciudad = self:ciudadDeSitio(nid, c)
    local puestas = math.min(quiere, ciudad and ciudad.parque or 0)
    if puestas < 1 then
        return false, 'parque'
    end
    local por = Armamento.sacar(ciudad, 'parque', puestas)
    if ciudad.parque == 0 then
        ciudad.parque = nil
    end
    if c == ciudad then
        c.lanzacohetes = c.lanzacohetes or 0
        Armamento.meterPor(c, 'lanzacohetes', por)
    else
        self:entregar(n, c, 'lanzacohetes', puestas, ciudad, por)
    end
    return puestas
end

--- Cuántas defensas de un tipo van de camino a un sitio (ciudad o base). Los
-- lanzacohetes que el sitio tiene fuera (en un grupo) también cuentan: van a
-- volver, y con ellos no se pasa del tope. En una ciudad cuentan además los
-- averiados, en un grupo o en su cola de recuperación; los de una base se
-- reparan en una ciudad y ya no vuelven a ella.
function Simulacion:enCamino(sid, defensa)
    local total = 0
    local c = self:sitio(sid)
    local fuera = defensa == 'lanzacohetes' and c
    local ciudad = fuera and esCiudad(c)
    -- Suma enteros: no depende del orden. Las entregas hacia el sitio y, si
    -- son lanzacohetes, los que salieron de él y siguen fuera.
    local function entrega(g)
        return g.mision == 'entrega' and g.objetivo == sid and g.carga.tipo == defensa
    end
    for _, g in ipairs(self:gruposHacia(sid)) do
        if entrega(g) then
            total = total + g.carga.cantidad
        end
    end
    if fuera then
        for _, g in ipairs(self:gruposDe(c.nacion)) do
            if not entrega(g) and g.origen == sid then
                total = total + (g.lanzacohetes or 0)
                if ciudad and g.heridos then
                    total = total + g.heridos.lanzacohetes
                end
            end
        end
    end
    if ciudad and c.recuperando then
        total = total + c.recuperando.lanzacohetes
    end
    return total
end

--- Los lanzacohetes salen de la ciudad `desde` (o de la capital) y protegen
-- la base al llegar (tardan el viaje, pero no se ven por el camino). En la
-- misma ciudad se instalan al momento. `por`: sus modelos (sin él, de referencia).
function Simulacion:entregar(n, c, defensa, cantidad, desde, por)
    local e = self.estado
    local capital = desde or e.ciudades[n.capital]
    local ruta = capital and capital ~= c and capital.nacion == n.id and self:trazar(capital.x, capital.y, c.x, c.y)
    local carga = { tipo = defensa, cantidad = 0 }
    Armamento.meterPor(carga, 'cantidad', por)
    Armamento.meter(carga, 'cantidad', Armamento.referencia(defensa), cantidad - carga.cantidad)
    if not ruta then
        c[defensa] = c[defensa] or 0
        Armamento.meterPor(c, defensa, carga.cantidadPor)
        return
    end
    local gid = e.siguienteGrupo
    e.siguienteGrupo = gid + 1
    e.grupos[gid] = {
        id = gid,
        nacion = n.id,
        mision = 'entrega',
        desde = capital.id,
        objetivo = c.id,
        destinoX = c.x,
        destinoY = c.y,
        x = capital.x,
        y = capital.y,
        antesX = capital.x,
        antesY = capital.y,
        ruta = ruta,
        largo = Simulacion.largoRuta(ruta),
        recorrido = 0,
        antesRecorrido = 0,
        soldados = 0,
        carga = carga,
    }
end

--- ¿Hay un rival hostil (en guerra, o con la relación por debajo de `hostil`)
-- con una ciudad o una base a menos de `frontera` de esta ciudad?
function Simulacion:enFrontera(c)
    local idx = self:indice()
    local frontera = Simulacion.defensasCiudad.frontera
    local hostil = {}
    -- ¿Es `s` un sitio con fuerzas (ciudad o base terminada) de una nación
    -- viva y hostil a menos de `frontera`?
    local function amenaza(s)
        local otra = s.nacion
        if otra == c.nacion or distancia(s, c) >= frontera then
            return false
        end
        if hostil[otra] == nil then
            hostil[otra] = #self:ciudadesDe(otra) > 0
                and (
                    self:guerraEntre(c.nacion, otra) ~= nil
                    or self:relacion(c.nacion, otra) < Simulacion.defensasCiudad.hostil
                )
        end
        return hostil[otra]
    end
    local x0, x1 =
        math.floor((c.x - frontera) / CELDA_INSTALACIONES), math.floor((c.x + frontera) / CELDA_INSTALACIONES)
    local y0, y1 =
        math.floor((c.y - frontera) / CELDA_INSTALACIONES), math.floor((c.y + frontera) / CELDA_INSTALACIONES)
    for cx = x0, x1 do
        for cy = y0, y1 do
            local clave = cx * 65536 + cy
            for _, s in ipairs(idx.rejillaCiudades[clave] or {}) do
                if amenaza(s) then
                    return true
                end
            end
            for _, s in ipairs(idx.rejillaBases[clave] or {}) do
                if s.progreso >= 1 and amenaza(s) then
                    return true
                end
            end
        end
    end
    return false
end

--- El presidente resguarda sus ciudades: las de frontera y la capital hasta el
-- tope de su nivel, pagando del tesoro si la ciudad no puede; las del interior
-- según su prudencia (un presidente imprudente las deja medio vacías), y solo
-- si la ciudad se lo paga. Puede equivocarse: una ciudad de nivel alto sin
-- defensas es presa fácil.
function Simulacion:protegerCiudades(n)
    for _, c in ipairs(self:ciudadesDe(n.id)) do
        local tope = Simulacion.topeLanzacohetes(c)
        local importante = c.id == n.capital or self:enFrontera(c)
        local parte = importante and 1 or (0.3 + 0.6 * n.gobernante.prudencia)
        local quiere = math.floor(tope * parte)
        for _, defensa in ipairs({ 'baterias', 'lanzacohetes' }) do
            local faltan = quiere - (c[defensa] or 0)
            if faltan > 0 then
                self:ejecutar({
                    tipo = 'enviarDefensas',
                    nacion = n.id,
                    ciudad = c.id,
                    defensa = defensa,
                    cantidad = faltan,
                    pagaTesoro = importante,
                })
            end
        end
    end
end

--- El presidente llena de lanzacohetes sus bases terminadas hasta el tope de
-- sus plataformas, pagando del tesoro si la ciudad que las abastece no puede:
-- una base siempre mira al vecino.
function Simulacion:protegerBases(n)
    for _, b in ipairs(self:instalacionesDe(n.id, 'base')) do
        if b.progreso >= 1 then
            local faltan = Simulacion.topeLanzacohetes(b) - (b.lanzacohetes or 0) - self:enCamino(b.id, 'lanzacohetes')
            if faltan > 0 then
                self:ejecutar({
                    tipo = 'enviarDefensas',
                    nacion = n.id,
                    base = b.id,
                    defensa = 'lanzacohetes',
                    cantidad = faltan,
                    pagaTesoro = true,
                })
            end
        end
    end
end

--- El presidente no deja que su gente pase hambre: a una ciudad sin granjas
-- propias que va justa de comida o ya la pasa le planta un huerto.
function Simulacion:atenderHambre(n)
    for _, c in ipairs(self:ciudadesDe(n.id)) do
        if not c.huerto and (c.hambre or self:reservaComida(c).estado ~= 'holgado') then
            self:ejecutar({ tipo = 'plantarHuerto', nacion = n.id, ciudad = c.id })
        end
    end
end

--- El presidente mejora todas las ciudades que puede pagar, a la vez: no hay
-- turnos, solo recursos. Va de la que más rinde a la que menos (primero las que
-- pasan hambre; después más minas y la capital; el nivel bajo pesa poco, así
-- que un país pobre deja atrás a sus ciudades pobres). Si no le alcanza para
-- la siguiente, ahorra para ella: la fábrica no toca ese metal ni ese petróleo.
function Simulacion:planearMejoras(n)
    self:planearReparaciones(n)
    local tope = self:almacen(n.id)
    local candidatas = {}
    for _, c in ipairs(self:ciudadesDe(n.id)) do
        local siguiente = Simulacion.niveles[(c.nivel or 1) + 1]
        -- Solo lo que cabe en el almacén: si no, nunca juntaría para pagarla.
        if not c.mejora and siguiente and siguiente.mejora.metal <= tope and siguiente.mejora.petroleo <= tope then
            candidatas[#candidatas + 1] = {
                ciudad = c,
                valor = (c.hambre and 3 or 0) + (c.id == n.capital and 1 or 0) - (c.nivel or 1) * 0.3,
            }
        end
    end
    table.sort(candidatas, function(a, b)
        if a.valor ~= b.valor then
            return a.valor > b.valor
        end
        return a.ciudad.id < b.ciudad.id
    end)
    n.plan = nil
    for _, candidata in ipairs(candidatas) do
        local c = candidata.ciudad
        if not self:ejecutar({ tipo = 'mejorarCiudad', nacion = n.id, ciudad = c.id }) then
            local coste = Simulacion.niveles[(c.nivel or 1) + 1].mejora
            n.plan = { ciudad = c.id, metal = coste.metal, petroleo = coste.petroleo }
            return
        end
    end
end

function Simulacion:declararGuerra(a, b, motivo)
    local e = self.estado
    if a == b or self:guerraEntre(a, b) then
        return false
    end
    e.guerras[claveGuerra(a, b)] = {
        atacante = a,
        defensor = b,
        dias = 0,
        fase = 'tension',
        faseHasta = 0,
    }
    self:noticia(
        string.format(
            '¡%s declara la guerra a %s!%s',
            e.naciones[a].nombre,
            e.naciones[b].nombre,
            motivo and (' Motivo: ' .. motivo) or ''
        ),
        { 1, 0.35, 0.3 }
    )
    return true
end

--- Umbral de retirada de un grupo de `nid`: el que elija quien lo manda
-- (`retirada`, de 0 a `umbralMaximo`; con 0 lucha hasta el final) o, si no
-- elige, el de su presidente según su prudencia.
function Simulacion:umbralRetirada(nid, retirada)
    local reglas = Simulacion.recuperacion
    if retirada then
        return math.max(0, math.min(reglas.umbralMaximo, retirada))
    end
    return reglas.umbralBase + reglas.umbralPrudencia * self.estado.naciones[nid].gobernante.prudencia
end

--- Manda un grupo desde un sitio. Misiones: 'construir' (con `construye`),
-- 'atacar' y 'refuerzo' (con `objetivo`, id de instalación; a una bandera no
-- se manda refuerzo), 'guarnicion' (con `objetivo`, id de una bandera propia
-- del borde, hasta su tope: banderas.lua) y 'mover' (un ejército que el
-- jugador forma y deja parado en `objetivo`, su propia ciudad, para moverlo
-- después). Un grupo que sale a atacar, de guarnición o a moverse es un
-- EJÉRCITO: lo manda un líder (`lider`, id de un líder libre de la nación;
-- sin él, el primero libre o un general nuevo, ver `liderParaSalir`), puede
-- llevarse `lanzacohetes` de su sitio (primero los del parque) y tiene vida y
-- umbral de retirada (`retirada`, ver `umbralRetirada`). Se lleva su munición
-- del polvorín (`municion`: tabla, días o nil para su dotación; ver
-- municion.lua). Sin combustible no salen vehículos. `modelos` (modelo ->
-- cantidad) elige qué modelos salen; sin él, en proporción a lo que hay.
function Simulacion:enviarGrupo(
    nid,
    desdeId,
    mision,
    objetivoId,
    construye,
    soldados,
    lanzacohetes,
    retirada,
    liderId,
    municion,
    modelos
)
    local e = self.estado
    local desde = self:sitio(desdeId)
    if not desde or desde.nacion ~= nid or desde.tipo == 'bandera' then
        return false, 'origen'
    end
    local pide = type(modelos) == 'table' and modelos or nil
    if pide then
        lanzacohetes = lanzacohetes or Armamento.pedidas(pide, 'lanzacohetes')
    end
    local ejercito = mision == 'atacar' or mision == 'mover' or mision == 'guarnicion'
    soldados = math.max(0, math.min(desde.soldados, math.floor(soldados or math.floor(desde.soldados * 0.4))))
    -- Los lanzacohetes solo salen con un ejército: primero los del parque.
    local llevan = 0
    if ejercito then
        llevan = math.max(0, math.min((desde.lanzacohetes or 0) + (desde.parque or 0), math.floor(lanzacohetes or 0)))
    end
    if e.naciones[nid].sinCombustible then
        llevan = 0
    end
    -- No hay mínimo para salir: basta con una unidad, del tipo que sea.
    if soldados + llevan < 1 then
        return false, 'sinTropas'
    end
    local destino = construye or (objetivoId ~= nil and self:sitio(objetivoId))
    if mision == 'atacar' and not destino then
        destino = e.depositos[objetivoId]
    end
    if not destino then
        return false, 'destino'
    end
    if mision == 'mover' and destino.nacion ~= nid then
        return false, 'destino'
    end
    -- Una bandera no guarda nada: se protege con guarnición, no con refuerzos.
    if
        (mision == 'refuerzo' and destino.tipo == 'bandera') or (mision == 'guarnicion' and destino.tipo ~= 'bandera')
    then
        return false, 'destino'
    end
    -- Una bandera enemiga solo se ataca desde un territorio que hace frontera.
    if mision == 'atacar' then
        local puede, motivo = self:puedeAtacar(nid, objetivoId)
        if not puede then
            return false, motivo
        end
    end
    -- Sin camino por tierra (una isla, otro continente) no se manda nada.
    local ruta = self:trazar(desde.x, desde.y, destino.x, destino.y)
    if not ruta then
        return false, 'sinCamino'
    end
    -- La guarnición de una bandera, hasta su tope (F5): la vida de lo que saldría.
    if mision == 'guarnicion' then
        local delParque = math.min(llevan, desde.parque or 0)
        local porParque = Armamento.partir(desde, 'parque', delParque, pide)
        local porPlataformas =
            Armamento.partir(desde, 'lanzacohetes', llevan - delParque, Armamento.restar(pide, porParque))
        local salen = { soldados = soldados, lanzacohetes = 0 }
        Armamento.meterPor(salen, 'lanzacohetes', porParque)
        Armamento.meterPor(salen, 'lanzacohetes', porPlataformas)
        local cabe, motivo = self:admiteGuarnicion(nid, objetivoId, Simulacion.vidaGrupo(salen))
        if not cabe then
            return false, motivo
        end
    end
    local jefe
    if ejercito then
        jefe = self:liderParaSalir(nid, liderId)
        if not jefe then
            return false, 'sinLider'
        end
    end
    desde.soldados = desde.soldados - soldados
    local gid = e.siguienteGrupo
    e.siguienteGrupo = gid + 1
    local g = {
        id = gid,
        nacion = nid,
        mision = mision,
        desde = desdeId,
        objetivo = objetivoId,
        construye = construye,
        destinoX = destino.x,
        destinoY = destino.y,
        x = desde.x,
        y = desde.y,
        antesX = desde.x,
        antesY = desde.y,
        ruta = ruta,
        largo = Simulacion.largoRuta(ruta),
        recorrido = 0,
        antesRecorrido = 0,
        soldados = soldados,
    }
    e.grupos[gid] = g
    if ejercito then
        local delParque = math.min(llevan, desde.parque or 0)
        local porParque = {}
        if delParque > 0 then
            porParque = Armamento.sacar(desde, 'parque', delParque, pide)
            if desde.parque == 0 then
                desde.parque = nil
            end
        end
        desde.lanzacohetes = desde.lanzacohetes or 0
        local porPlataformas =
            Armamento.sacar(desde, 'lanzacohetes', llevan - delParque, Armamento.restar(pide, porParque))
        g.origen = desde.id
        g.lanzacohetes = 0
        Armamento.meterPor(g, 'lanzacohetes', porParque)
        Armamento.meterPor(g, 'lanzacohetes', porPlataformas)
        g.vidaMax = Simulacion.vidaGrupo(g)
        g.umbral = self:umbralRetirada(nid, retirada)
        g.heridos = tropasVacias()
        g.resto = tropasVacias()
        ponerAlMando(e, g, jefe)
    end
    if mision ~= 'construir' then
        self:dotar(g, desde, municion)
    end
    -- Atacar una bandera del borde la guarda: desde ya tiene estado.
    if mision == 'atacar' and destino.tipo == 'bandera' then
        self:guardarBandera(objetivoId)
    end
    return gid
end

-- Nombres, cansancio y destrucción de instalaciones ------------------------------------------------

local function nombreInstalacion(self, inst)
    if inst.tipo == 'base' then
        return 'una base militar'
    elseif inst.tipo == 'campamento' then
        return 'un campamento'
    elseif inst.tipo == 'bandera' then
        return 'una bandera'
    end
    local recurso = Simulacion.recursos[self.estado.depositos[inst.deposito].tipo]
    return recurso.articulo .. ' ' .. recurso.nombre
end

--- Nombre de un blanco: una instalación, "la ciudad de X" o un texto ya hecho.
local function nombreBlanco(self, blanco)
    if type(blanco) == 'string' then
        return blanco
    end
    if esCiudad(blanco) then
        return 'la ciudad de ' .. blanco.nombre
    end
    return nombreInstalacion(self, blanco)
end
Simulacion.nombreInstalacion = nombreInstalacion
Simulacion.nombreBlanco = nombreBlanco

function Simulacion:sumarCansancio(nid, cuanto)
    local n = self.estado.naciones[nid]
    if n then
        n.cansancio = n.cansancio + cuanto
    end
end

--- Una instalación vencida se borra y su tierra queda sin dueño si nadie más
-- la cubre. Nada se destruye con ella (diseno/economia.md, 3.8.6): sus
-- vehículos vuelven averiados (daño 1), remolcados, al taller de la ciudad
-- que la abastecía; sus soldados caen (F11b: unos mueren, los heridos van
-- con el remolque).
function Simulacion:destruirInstalacion(inst, por)
    local e = self.estado
    local duena = e.naciones[inst.nacion]
    if inst.tipo == 'bandera' then
        -- Una bandera no guarda nada: cae su tierra de bandera (banderas.lua).
        self:noticia(
            string.format(
                '%s arranca una bandera de %s en (%d, %d)',
                e.naciones[por].nombre,
                duena.nombre,
                math.floor(inst.x),
                math.floor(inst.y)
            ),
            { 1, 0.55, 0.3 }
        )
        self:caerBandera(inst)
        self:sumarCansancio(inst.nacion, 3)
        return
    end
    self:remolcarGuarnicion(inst)
    self:noticia(
        string.format('%s destruye %s de %s', e.naciones[por].nombre, nombreInstalacion(self, inst), duena.nombre),
        { 1, 0.55, 0.3 }
    )
    e.instalaciones[inst.id] = nil
    -- Un depósito de antes de los yacimientos (versión 15) se borra con su extracción.
    if inst.tipo == 'extraccion' and inst.deposito and not inst.deposito:match('^y:') then
        e.depositos[inst.deposito] = nil
        self.listaDepositos, self.rejillaDepositos, self.cacheConocidos = nil, nil, nil
    end
    if inst.tipo == 'base' then
        duena.bases = math.max(0, duena.bases - 1)
    end
    self:ensuciarEn(inst)
    self:soltarBloque(inst)
    self:sumarCansancio(inst.nacion, 3)
end

--- Lo que queda en una instalación que se pierde vuelve remolcado al taller
-- de su ciudad (ver `destruirInstalacion`): sus vehículos, averiados por
-- zonas como en la batalla simulada (averias.lua), con sus tripulantes
-- heridos; los tripulantes muertos salen de la población.
function Simulacion:remolcarGuarnicion(inst)
    local heridos = tropasVacias()
    local averias = Simulacion.averiasVacias()
    local azar = self:azarAverias(nil, inst, 4)
    local tripMuertos, tripHeridos = 0, 0
    for _, tipo in ipairs(Armamento.TIPOS) do
        local cuantos = inst[tipo] or 0
        for _, modelo in ipairs(Armamento.lista(Armamento.vaciar(inst, tipo), tipo, cuantos)) do
            local codigo, bajas, muertos = Averias.simular(azar, tipo, Armamento.tripulacion(modelo))
            Simulacion.anotarAveria(averias, tipo, codigo, modelo)
            tripMuertos = tripMuertos + muertos
            tripHeridos = tripHeridos + bajas - muertos
        end
        heridos[tipo] = cuantos
    end
    averias.tripulantes = tripHeridos > 0 and tripHeridos or nil
    self:morirTripulantes(inst.nacion, self:ciudadDeSitio(inst.nacion, inst), tripMuertos)
    local soldados = inst.soldados or 0
    inst.soldados = 0
    if soldados > 0 then
        local muertos = math.floor(soldados * Simulacion.produccion.muertos + 0.5)
        heridos.soldados = soldados - muertos
        self:morirSoldados(inst.nacion, self:ciudadDeSitio(inst.nacion, inst), muertos)
    end
    local ciudad = self:ciudadDeSitio(inst.nacion, inst)
    self:remolcar(inst.nacion, inst.x, inst.y, ciudad, heridos, averias)
end

-- Economía, investigación y fábricas ----------------------------------------------------------------

--- ¿Produce hoy la instalación? Ya no: nada produce solo (3.3). Queda para
-- la vista de antes.
function Simulacion.produce()
    return false
end

--- Efecto de la vida (F6): f(V) = efectoMinimo + (1 - efectoMinimo) × V / 100.
function Simulacion.efectoVida(vida)
    local minimo = Simulacion.vidaCiudad.efectoMinimo
    return minimo + (1 - minimo) * math.max(0, math.min(100, vida)) / 100
end

--- Vida de un sitio de 0 a 100: la de una ciudad (`c.vida`) o la salud de una
-- instalación sobre su máximo (un campamento, sobre 30).
function Simulacion.vidaSitio(s)
    if esCiudad(s) then
        return s.vida or Simulacion.vidaCiudad.maxima
    end
    return 100 * (s.salud or 0) / Simulacion.saludMaxima[s.tipo]
end

--- Comida que le falta al día a una ciudad: lo que come su gente menos lo que
-- cultivan sus tierras (negativo si le sobra).
local function faltaComida(c)
    local cultivo = c.radio * Simulacion.consumo.cultivoRadio * Simulacion.nivel(c.nivel).minas
    return c.poblacion * Simulacion.consumo.comeHabitante - cultivo
end
Simulacion.faltaComida = faltaComida

--- Comida que da hoy el huerto de una ciudad: lo que le falta a su gente (sin
-- contar a los soldados) hasta su tope, y nada si no está terminado.
function Simulacion:comidaHuerto(c)
    local h = c.huerto
    if not h or self.estado.dia < h.hasta then
        return 0
    end
    local nivel = Simulacion.nivel(c.nivel)
    local civiles = math.max(0, c.poblacion - c.soldados)
    local tierras = c.radio * Simulacion.consumo.cultivoRadio * nivel.minas
    local falta = math.max(0, civiles * Simulacion.consumo.comeHabitante - tierras)
    return math.min(falta, c.radio * Simulacion.huerto.porRadio * nivel.minas)
end

--- Tope del granero de una ciudad.
function Simulacion.granero(c)
    local tope = Simulacion.consumo.graneroBase + Simulacion.consumo.graneroHabitante * c.poblacion
    return tope * Simulacion.nivel(c.nivel).granero
end

--- Ciudad propia más cercana a un punto: la que se queda lo que da una granja
-- y la que abastece a una base.
function Simulacion:ciudadDuena(nid, x, y)
    local mejor, mejorD
    for _, c in ipairs(self:ciudadesDe(nid)) do
        local d = hipotenusa(c.x - x, c.y - y)
        if not mejor or d < mejorD then
            mejor, mejorD = c, d
        end
    end
    return mejor
end

--- ¿Está parado hoy un grupo (en su mina, detenido o esperando donde lo
-- dejaron)? Si no, va en marcha o pelea.
local function grupoParado(g)
    if g.batalla then
        return false
    end
    if g.mision == 'recolectar' and g.fase == 'recolectando' then
        return true
    end
    if g.mision == 'guarnicion' and g.bandera then
        return true
    end
    return g.detenido == true or (g.mision == 'mover' and g.ruta ~= nil and g.recorrido >= g.largo)
end

--- Combustible que gastan al día los vehículos y aviones de una nación (F9):
-- `combustible.parado` por vehículo en sus sitios, en su parque o en un
-- grupo parado, y `combustible.marcha` en un grupo en marcha o en batalla.
-- Los averiados no gastan.
function Simulacion:gastoCombustible(nid)
    local reglas = Simulacion.produccion.combustible
    -- Cada vehículo pesa el consumo de su modelo (F5; la referencia, 1).
    local parados = { lanzacohetes = 0 }
    local marcha = { lanzacohetes = 0 }
    local aviones = 0
    for _, sitio in ipairs(self:sitiosDe(nid)) do
        parados.lanzacohetes = parados.lanzacohetes
            + Armamento.suma(sitio, 'lanzacohetes', 'consumo')
            + Armamento.suma(sitio, 'parque', 'consumo')
        aviones = aviones + (sitio.aviones or 0)
    end
    -- En orden fijo de grupos (con la referencia, suma enteros).
    for _, g in ipairs(self:gruposDe(nid)) do
        local t = grupoParado(g) and parados or marcha
        t.lanzacohetes = t.lanzacohetes + Armamento.suma(g, 'lanzacohetes', 'consumo')
    end
    local total = aviones * Simulacion.consumo.petroleoAvion
    for _, tipo in ipairs(Armamento.TIPOS) do
        total = total + parados[tipo] * reglas.parado[tipo] + marcha[tipo] * reglas.marcha[tipo]
    end
    return total
end

--- Mantenimiento de un campamento (petróleo al día, fijo: 3.3) y su
-- distancia a la ciudad propia más cercana (el orden en que se paga).
function Simulacion:mantenimientoCampamento(i)
    local c = self:ciudadDuena(i.nacion, i.x, i.y)
    local d = c and distancia(c, i) or 0
    return Simulacion.recoleccion.mantenimientoCampamento, d
end

--- Petróleo al día que cuestan todos los campamentos terminados de una nación.
function Simulacion:mantenimientoCampamentos(nid)
    local total = 0
    for _, i in ipairs(self:instalacionesDe(nid, 'campamento')) do
        if i.progreso >= 1 then
            total = total + Simulacion.recoleccion.mantenimientoCampamento
        end
    end
    return total
end

--- Lo que costaría el siguiente campamento.
function Simulacion.mantenimientoSiguiente()
    return Simulacion.recoleccion.mantenimientoCampamento
end

Simulacion.estadosReserva = { 'holgado', 'justo', 'escasez', 'crisis' }

-- Cuánto necesita una nación un recurso (0 a 1) según el estado de su reserva.
-- `fabrica`: metal o petróleo con el almacén casi vacío (menos de `umbralFabrica`
-- del tope) aunque cubra lo básico: quiere más para fabricar, con menos fuerza.
Simulacion.necesidad = {
    crisis = 1,
    escasez = 0.8,
    justo = 0.5,
    holgado = 0,
    fabrica = 0.3,
    umbralFabrica = 0.2,
    -- Petróleo cuando no le da para mantener el siguiente campamento: quiere
    -- crecer y ese petróleo lo tiene el vecino.
    expansion = 0.3,
    -- Probabilidad (relativa, por día) de declarar una guerra sin nada material
    -- que ganar, solo por odio ideológico. En 0: las guerras son por recursos.
    -- Ojo: se tira cada día mientras se odian, así que incluso 0,05 acaba en
    -- muchas guerras ideológicas a lo largo de un año.
    guerraSinMotivo = 0,
}

--- Necesidad de cada recurso para una nación: { metal = n, petroleo = n, comida = n }.
-- Se calcula una vez por día y nación (no se guarda: sale del estado).
function Simulacion:necesidades(nid)
    local dia = self.estado.dia
    if not self.cacheNecesidad or self.cacheNecesidad.dia ~= dia then
        self.cacheNecesidad = { dia = dia }
    end
    local guardada = self.cacheNecesidad[nid]
    if guardada then
        return guardada
    end
    local tabla = Simulacion.necesidad
    local out = {}
    for _, r in ipairs(self:reservas(nid)) do
        local necesidad = tabla[r.estado]
        if r.tipo ~= 'comida' and r.cantidad < r.tope * tabla.umbralFabrica then
            necesidad = math.max(necesidad, tabla.fabrica)
        end
        out[r.tipo] = necesidad
        if r.tipo == 'petroleo' and r.entra - r.gasta < self:mantenimientoSiguiente(nid) then
            -- No le da para mantener el siguiente campamento: quiere más petróleo.
            out.petroleo = math.max(out.petroleo, tabla.expansion)
        end
    end
    -- El oro da dinero: se quiere más con el tesoro bajo (F12).
    local yac = Simulacion.yacimientos
    local pobre = disponible(self.estado.naciones[nid], 'dinero') < 10 * Simulacion.recuperacion.reservaTesoro
    out.oro = pobre and yac.oroNecesario or yac.oroHolgado
    self.cacheNecesidad[nid] = out
    return out
end

--- Estado de una reserva: holgado (más de 60 días o no baja), justo (15 a
-- 60), escasez (menos de 15) o crisis (vacía y sin cubrir el gasto).
local function valorarReserva(tipo, cantidad, tope, entra, gasta)
    local balance = entra - gasta
    local dias = balance < 0 and cantidad / -balance or math.huge
    local estado
    if balance >= 0 or dias > 60 then
        estado = 'holgado'
    elseif dias >= 15 then
        estado = 'justo'
    elseif cantidad >= 1 then
        estado = 'escasez'
    else
        estado = 'crisis'
    end
    return {
        tipo = tipo,
        cantidad = cantidad,
        tope = tope,
        entra = entra,
        gasta = gasta,
        dias = dias,
        estado = estado,
    }
end

--- Granero de una ciudad: lo que tiene, lo que dan sus tierras (y, en la
-- capital, lo que traen sus recolectores de media), lo que come su gente y
-- cuánto le dura.
function Simulacion:reservaComida(c)
    local entra = 0
    local n = self.estado.naciones[c.nacion]
    if n and n.capital == c.id and n.recolectado then
        entra = n.recolectado.comida
    end
    local falta = faltaComida(c) - self:comidaHuerto(c)
    local reserva =
        valorarReserva('comida', c.comida or 0, Simulacion.granero(c), entra + math.max(0, -falta), math.max(0, falta))
    reserva.ciudad = c
    return reserva
end

local ORDEN_ESTADO = { holgado = 1, justo = 2, escasez = 3, crisis = 4 }

--- Cómo va una nación de cada recurso: cuánto tiene, lo que entra y lo que
-- gasta a la fuerza cada día (mantener vehículos, aviones y campamentos), cuántos días le dura
-- y en qué estado está. Lo que sobra del petróleo y el metal va a la fábrica,
-- que no cuenta como gasto. La comida es la de su ciudad peor alimentada.
function Simulacion:reservas(nid)
    local e = self.estado
    local n = e.naciones[nid]
    local ciudades = self:ciudadesDe(nid)
    -- Entra lo de los talleres y lo que traen sus recolectores (de media).
    local recolectado = n.recolectado or {}
    local entra = {
        metal = Simulacion.consumo.metalCiudad * #ciudades + (recolectado.metal or 0),
        petroleo = recolectado.petroleo or 0,
    }
    local tope = self:almacen(nid)
    local out = {
        valorarReserva('metal', disponible(n, 'metal'), tope, entra.metal, 0),
        valorarReserva(
            'petroleo',
            disponible(n, 'petroleo'),
            tope,
            entra.petroleo,
            self:gastoCombustible(nid) + self:mantenimientoCampamentos(nid)
        ),
    }
    local peor
    for _, c in ipairs(ciudades) do
        local r = self:reservaComida(c)
        if
            not peor
            or ORDEN_ESTADO[r.estado] > ORDEN_ESTADO[peor.estado]
            or (r.estado == peor.estado and r.dias < peor.dias)
        then
            peor = r
        end
    end
    out[#out + 1] = peor or valorarReserva('comida', 0, 0, 0, 0)
    return out
end

--- Nada produce solo (3.3): cada día solo se paga el mantenimiento de los
-- campamentos y las banderas. Lo que entra lo traen los recolectores.
function Simulacion:producirRecursos()
    for _, n in ipairs(self:vivas()) do
        self:mantenerCampamentos(n)
    end
end

--- Paga el petróleo de los campamentos terminados de una nación, del más
-- cercano a su ciudad al más lejano. Desde el primero que no se puede pagar,
-- los que quedan están desabastecidos: pierden salud y, a 0, se abandonan.
function Simulacion:mantenerCampamentos(n)
    local e = self.estado
    local cola = {}
    for _, i in ipairs(self:instalacionesDe(n.id, 'campamento')) do
        if i.progreso >= 1 then
            local coste, d = self:mantenimientoCampamento(i)
            cola[#cola + 1] = { inst = i, coste = coste, distancia = d }
        end
    end
    table.sort(cola, function(a, b)
        if a.distancia ~= b.distancia then
            return a.distancia < b.distancia
        end
        return a.inst.id < b.inst.id
    end)
    local abastece = true
    for _, pago in ipairs(cola) do
        local i = pago.inst
        if abastece and disponible(n, 'petroleo') >= pago.coste then
            gastar(n, 'petroleo', pago.coste)
        else
            abastece = false
            i.salud = i.salud - Simulacion.campamento.desabasto
            if i.salud <= 0 then
                self:noticia(
                    string.format('%s abandona un campamento por falta de suministro', n.nombre),
                    { 1, 0.7, 0.4 }
                )
                self:retirarGuarnicion(i)
                e.instalaciones[i.id] = nil
                self:ensuciarEn(i)
                self:soltarBloque(i)
            end
        end
    end
    self:mantenerBanderas(n)
end

--- La guarnición de un campamento abandonado vuelve a pie a la ciudad propia
-- más cercana (misión 'regreso'), con sus lanzacohetes. Si la nación no tiene
-- ciudad, se pierde con ella.
function Simulacion:retirarGuarnicion(i)
    local e = self.estado
    local soldados = i.soldados or 0
    local lanzacohetes = i.lanzacohetes or 0
    local casa = self:ciudadDuena(i.nacion, i.x, i.y)
    if not casa or soldados + lanzacohetes <= 0 then
        return
    end
    local lanzacohetesPor = Armamento.vaciar(i, 'lanzacohetes')
    -- Vuelve por tierra; si no hay camino, en línea recta (como volver()).
    local ruta = self:trazar(i.x, i.y, casa.x, casa.y) or { i.x, i.y, casa.x, casa.y }
    local gid = e.siguienteGrupo
    e.siguienteGrupo = gid + 1
    e.grupos[gid] = {
        id = gid,
        nacion = i.nacion,
        mision = 'regreso',
        desde = casa.id,
        destinoX = casa.x,
        destinoY = casa.y,
        x = i.x,
        y = i.y,
        antesX = i.x,
        antesY = i.y,
        ruta = ruta,
        largo = Simulacion.largoRuta(ruta),
        recorrido = 0,
        antesRecorrido = 0,
        soldados = soldados,
        lanzacohetes = 0,
    }
    Armamento.meterPor(e.grupos[gid], 'lanzacohetes', lanzacohetesPor)
    i.soldados = 0
end

--- La economía de un día de una nación (diseno/economia.md): cada ciudad
-- come de su granero (sus tierras dan una parte y el resto llega de sus
-- recolectores); sin comida la población baja, parte de la guarnición se
-- licencia (F8: vuelven a ser civiles) y la gente rinde menos. El trabajo de
-- los civiles (F2b: sin los soldados de la ciudad, estén donde estén, ni los
-- que están en instrucción) da la investigación y el dinero, que va entero al
-- tesoro. Después avanzan sus fábricas, se paga el combustible y los sueldos
-- (F7). Nada se recluta ni se fabrica solo.
function Simulacion:economia(n)
    local e = self.estado
    local ciudades = self:ciudadesDe(n.id)
    local consumo = Simulacion.consumo
    local produccion = 0

    -- Las medias de unos 10 días de lo gastado y lo recolectado (IA, F9).
    local peso = 1 - Simulacion.recoleccion.mediaConsumo
    for _, r in ipairs(ordenadas(n.consumo)) do
        n.consumo[r] = n.consumo[r] * peso
    end
    for _, r in ipairs(ordenadas(n.recolectado)) do
        n.recolectado[r] = n.recolectado[r] * peso
    end
    local inventario = self:inventario(n.id)
    n.hambre = false
    for _, c in ipairs(ciudades) do
        if c.mejora and e.dia >= c.mejora.hasta then
            c.nivel = c.mejora.nivel
            c.mejora = nil
        end
        self:avanzarReparacion(c)
        c.comida = (c.comida or 0) - faltaComida(c) + self:comidaHuerto(c)
        c.hambre = c.comida < 0
        -- La población cambia en el día demográfico (poblacion.lua), al final.
        if c.hambre then
            c.comida = 0
            n.hambre = true
            self:licenciar(c, 1)
        end
        c.comida = math.min(c.comida, Simulacion.granero(c))
        local suyos = inventario.ciudades[c.id]
        produccion = produccion + Simulacion.trabajoCiudad(n, c, suyos and suyos.soldados or c.soldados)
        self:ingresar(n, 'metal', consumo.metalCiudad)
    end

    -- Combustible (F9). Sin él, los vehículos no salen y los grupos van a media marcha.
    local gasto = self:gastoCombustible(n.id)
    n.sinCombustible = disponible(n, 'petroleo') < gasto
    gastar(n, 'petroleo', math.min(gasto, disponible(n, 'petroleo')))

    n.investigacion = n.investigacion + produccion * 0.3
    local siguiente = Simulacion.tecnologias[n.tecnologia + 1]
    if siguiente and n.investigacion >= siguiente.coste then
        n.investigacion = n.investigacion - siguiente.coste
        n.tecnologia = n.tecnologia + 1
        self:noticia(string.format('%s desarrolla %s', n.nombre, siguiente.nombre), n.color)
    end

    self:ingresar(n, 'dinero', Simulacion.dineroDelTrabajo(produccion))
    self:mercadoComida(ciudades)
    for _, c in ipairs(ciudades) do
        self:avanzarFabrica(c)
    end
    self:pagarSueldos(n, inventario.total)
    self:ajustarAlmacen(n)
    -- Población (diseno/poblacion.md): nacen, mueren, cumplen años y se retiran.
    self:ajustarFilas(n.id)
    for _, c in ipairs(ciudades) do
        self:diaDemografico(n, c)
    end
end

-- Mercado de comida entre las ciudades de un país: la que tiene poco toma de
-- la que tiene de sobra. Con un solo dinero (el tesoro) no hay nada que
-- pagar: es un reparto dentro del país. La comida de otros países llegará
-- con el comercio.
Simulacion.mercado = {
    comprarBajo = 0.3, -- compra si su granero baja de esta parte de su tope
    objetivo = 0.5, -- y compra hasta llegar a esta parte
    venderSobre = 0.6, -- vende lo que tenga por encima de esta parte
}

function Simulacion:mercadoComida(ciudades)
    local reglas = Simulacion.mercado
    local function llenado(c)
        return (c.comida or 0) / Simulacion.granero(c)
    end
    local orden = {}
    for _, c in ipairs(ciudades) do
        c.comprado = nil -- lo recibido hoy
        orden[#orden + 1] = c
    end
    -- Recibe primero la más necesitada; da primero la más llena.
    table.sort(orden, function(a, b)
        if llenado(a) ~= llenado(b) then
            return llenado(a) < llenado(b)
        end
        return a.id < b.id
    end)
    for _, compradora in ipairs(orden) do
        if llenado(compradora) < reglas.comprarBajo then
            local quiere = Simulacion.granero(compradora) * reglas.objetivo - compradora.comida
            for k = #orden, 1, -1 do
                local vendedora = orden[k]
                local sobra = vendedora.comida - Simulacion.granero(vendedora) * reglas.venderSobre
                local cantidad = math.min(quiere, sobra)
                if vendedora ~= compradora and cantidad > 0 then
                    compradora.comida = compradora.comida + cantidad
                    vendedora.comida = vendedora.comida - cantidad
                    compradora.comprado = (compradora.comprado or 0) + cantidad
                    quiere = quiere - cantidad
                end
                if quiere <= 0 then
                    break
                end
            end
        end
    end
end

-- Expansión: instalaciones y bases ---------------------------------------------------------------

--- Sitio propio más cercano a un punto, con al menos `soldados`.
function Simulacion:sitioCercano(nid, x, y, soldados, campo)
    local mejor, mejorD
    for _, s in ipairs(self:sitiosDe(nid)) do
        if s.soldados >= (soldados or 0) and (not campo or (s[campo] or 0) > 0) then
            local d = hipotenusa(s.x - x, s.y - y)
            if not mejor or d < mejorD then
                mejor, mejorD = s, d
            end
        end
    end
    return mejor, mejorD
end

function Simulacion:expansion(n, azar, turno)
    self:construirBase(n, azar)
    if (self.estado.dia + turno) % Simulacion.campamento.cadaDias == 0 then
        self:planearCampamento(n)
    end
    if (self.estado.dia + turno) % Simulacion.bandera.cadaDias == 0 then
        self:planearBanderas(n)
    end
    self:defenderBanderas(n)
end

-- Banderas (diseno/territorio-y-capitales.md, 3.7 y 3.9) ------------------------------------

--- Sitios de una nación que ya dan territorio, con su alcance: { sitio, alcance }.
function Simulacion:sitiosConTerritorio(nid)
    local out = {}
    for _, c in ipairs(self:ciudadesDe(nid)) do
        out[#out + 1] = { sitio = c, alcance = self:alcance(c) }
    end
    for _, i in ipairs(self:instalacionesDe(nid)) do
        if daTerritorio(i) then
            out[#out + 1] = { sitio = i, alcance = ALCANCE_INSTALACION[i.tipo] }
        end
    end
    return out
end

local function costeBandera()
    return { dinero = Simulacion.bandera.dinero, metal = Simulacion.bandera.metal }
end

--- ¿Puede `nid` plantar una bandera en el bloque alineado de 6 x 6 que
-- contiene (x, y) (P4 A)? En cualquier terreno. Devuelve true, o false y el
-- motivo, comprobado en este orden: 'nacion', 'coste', 'propia' (todo el
-- bloque ya es suyo), 'ajena' (no queda ninguna celda sin dueño), 'lejos' (el
-- bloque no toca por un lado ninguna celda suya) o 'enObra' (ya tiene una
-- bandera en obra en ese bloque).
function Simulacion:puedePlantarBandera(nid, x, y)
    local n = self.estado.naciones[nid]
    if not (n and x and y) then
        return false, 'nacion'
    end
    if not Simulacion.alcanza(n, costeBandera()) then
        return false, 'coste'
    end
    local cx0, cy0, cx1, cy1 = Simulacion.bloqueBandera(x, y)
    local libres, suyas = 0, 0
    for cy = cy0, cy1 do
        for cx = cx0, cx1 do
            local dueno = self:duenoCelda(cx, cy)
            if dueno == nil then
                libres = libres + 1
            elseif dueno == nid then
                suyas = suyas + 1
            end
        end
    end
    if libres == 0 then
        return false, suyas == (cx1 - cx0 + 1) * (cy1 - cy0 + 1) and 'propia' or 'ajena'
    end
    if not self:bloqueToca(nid, cx0, cy0, cx1, cy1) then
        return false, 'lejos'
    end
    local b = self.estado.instalaciones[Simulacion.idBandera(
        nid,
        cx0 / Simulacion.bloques.bandera,
        cy0 / Simulacion.bloques.bandera
    )]
    if b and b.progreso < 1 then
        return false, 'enObra'
    end
    return true
end

--- Planta una bandera en el bloque alineado que contiene (x, y): se paga al
-- momento y se levanta sola en `dias` de obra, sin tropa; al terminarse
-- toma las celdas sin dueño de su bloque (las de otra nación no se pisan).
-- La misma acción para un presidente NPC y para un jugador. Devuelve su id
-- ('f:<nación>:<bx>,<by>') o false y el motivo.
function Simulacion:plantarBandera(nid, x, y)
    local e = self.estado
    local puede, motivo = self:puedePlantarBandera(nid, x, y)
    if not puede then
        return false, motivo
    end
    local lado = Simulacion.bloques.bandera
    local cx0, cy0 = Simulacion.bloqueBandera(x, y)
    local bx, by = cx0 / lado, cy0 / lado
    local id = Simulacion.idBandera(nid, bx, by)
    Simulacion.pagar(e.naciones[nid], costeBandera())
    local b = e.instalaciones[id]
    if b then
        -- Una bandera dañada del borde en ese bloque: se levanta con su vida.
        b.progreso, b.inicio = 0, e.dia
        return id
    end
    e.instalaciones[id] = {
        id = id,
        tipo = 'bandera',
        nacion = nid,
        x = (cx0 + lado / 2) * CELDA,
        y = (cy0 + lado / 2) * CELDA,
        progreso = 0,
        salud = Simulacion.saludMaxima.bandera,
        inicio = e.dia,
    }
    self:anotarInstalacion(e.instalaciones[id])
    return id
end

--- Yacimientos de un tipo que conoce una nación (ver `yacimientosConocidos`).
function Simulacion:yacimientosConocidosDe(nid, tipo)
    local todos = self:yacimientosConocidos(nid)
    if not self.cachePorTipo or self.cachePorTipo.de ~= self.cacheConocidos then
        self.cachePorTipo = { de = self.cacheConocidos }
    end
    local clave = nid .. '|' .. tipo
    local out = self.cachePorTipo[clave]
    if not out then
        out = {}
        for _, d in ipairs(todos) do
            if d.tipo == tipo then
                out[#out + 1] = d
            end
        end
        self.cachePorTipo[clave] = out
    end
    return out
end

--- Yacimientos que conoce una nación: los registrados a menos de
-- `alcanceMeta` de su capital (se recalcula al registrar zonas).
function Simulacion:yacimientosConocidos(nid)
    self.cacheConocidos = self.cacheConocidos or {}
    local conocidos = self.cacheConocidos[nid]
    if not conocidos then
        local n = self.estado.naciones[nid]
        local capital = n and self.estado.ciudades[n.capital]
        conocidos = capital and self:depositosCerca(capital.x, capital.y, Simulacion.campamento.alcanceMeta) or {}
        self.cacheConocidos[nid] = conocidos
    end
    return conocidos
end

--- Sitios (ciudades e instalaciones) de las naciones en guerra con `nid`.
function Simulacion:sitiosEnemigos(nid)
    local out = {}
    for _, g in ipairs(self:guerrasDe(nid)) do
        local otra = g.atacante == nid and g.defensor or g.atacante
        for _, c in ipairs(self:ciudadesDe(otra)) do
            out[#out + 1] = c
        end
        for _, i in ipairs(self:instalacionesDe(otra)) do
            out[#out + 1] = i
        end
    end
    return out
end

--- Valor de un yacimiento para una nación (F12): riqueza × necesidad / (1 +
-- distanciaBorde / distanciaValor), y 0 si hay un sitio enemigo en guerra a
-- menos de `enemigoCerca`. `enemigos` se pasa ya calculado. La distancia al
-- borde es la de la celda propia más cercana (`distanciaYacimiento`).
function Simulacion:valorYacimiento(nid, d, enemigos)
    local reglas = Simulacion.bandera
    local necesidad = self:necesidades(nid)[d.tipo] or 0
    if necesidad <= 0 then
        return 0
    end
    for _, s in ipairs(enemigos) do
        if hipotenusa(s.x - d.x, s.y - d.y) < reglas.enemigoCerca then
            return 0
        end
    end
    local borde = self:distanciaYacimiento(nid, d)
    return d.riqueza * necesidad / (1 + (borde or 0) / reglas.distanciaValor)
end

--- ¿Va el candidato `a` antes que el `b`? Por `valor` y, a igual valor, por
-- id de yacimiento menor.
local function antes(a, b)
    if a.valor ~= b.valor then
        return a.valor > b.valor
    end
    return a.deposito.id < b.deposito.id
end

-- Búsqueda del camino de celdas de las banderas: celdas que mira como mucho.
local NODOS_CAMINO = 4000

--- ¿Va el nodo a antes que el b en la búsqueda? Por coste estimado y, a igual
-- coste, por clave de celda menor (orden fijo).
local function nodoAntes(a, b)
    if a.f ~= b.f then
        return a.f < b.f
    end
    return a.clave < b.clave
end

local function meterNodo(monticulo, nodo)
    local k = #monticulo + 1
    monticulo[k] = nodo
    while k > 1 do
        local padre = math.floor(k / 2)
        if not nodoAntes(monticulo[k], monticulo[padre]) then
            break
        end
        monticulo[k], monticulo[padre] = monticulo[padre], monticulo[k]
        k = padre
    end
end

local function sacarNodo(monticulo)
    local cima = monticulo[1]
    local ultimo = table.remove(monticulo)
    if #monticulo > 0 then
        monticulo[1] = ultimo
        local k = 1
        while true do
            local mejor = k
            local izquierdo, derecho = 2 * k, 2 * k + 1
            if monticulo[izquierdo] and nodoAntes(monticulo[izquierdo], monticulo[mejor]) then
                mejor = izquierdo
            end
            if monticulo[derecho] and nodoAntes(monticulo[derecho], monticulo[mejor]) then
                mejor = derecho
            end
            if mejor == k then
                break
            end
            monticulo[k], monticulo[mejor] = monticulo[mejor], monticulo[k]
            k = mejor
        end
    end
    return cima
end

--- Camino más corto de celdas (por sus cuatro lados) desde el territorio de
-- `nid` hasta la celda (tx, ty), en cualquier terreno y sin pisar celdas de
-- otra nación. Devuelve las celdas desde la primera pegada a su territorio
-- hasta la meta ({ {cx, cy}, ... }; vacía si la meta ya es suya), o nil si no
-- hay camino o está demasiado lejos.
function Simulacion:caminoCeldas(nid, tx, ty)
    local dueno = self:duenoCelda(tx, ty)
    if dueno == nid then
        return {}
    elseif dueno then
        return nil
    end
    local filas = self.estado.territorio[nid]
    if not filas then
        return nil
    end
    -- La celda suya más cercana a la meta guía la búsqueda (en empate, la de
    -- fila menor y después columna menor: no depende del orden de `pairs`).
    local gx, gy, gd
    for cy, tramos in pairs(filas) do
        for k = 1, #tramos, 2 do
            local cx = math.max(tramos[k], math.min(tramos[k + 1], tx))
            local d = math.abs(cx - tx) + math.abs(cy - ty)
            if not gd or d < gd or (d == gd and (cy < gy or (cy == gy and cx < gx))) then
                gx, gy, gd = cx, cy, d
            end
        end
    end
    -- Se busca desde la meta hacia su territorio: así cada celda apunta a la
    -- siguiente hacia la meta.
    local inicio = claveCelda(tx, ty)
    local coste, siguiente, cerrada, posicion = { [inicio] = 0 }, {}, {}, { [inicio] = { tx, ty } }
    local abiertos = {}
    meterNodo(abiertos, { f = gd, clave = inicio })
    local miradas = 0
    while #abiertos > 0 do
        local nodo = sacarNodo(abiertos)
        local clave = nodo.clave
        if not cerrada[clave] then
            cerrada[clave] = true
            miradas = miradas + 1
            if miradas > NODOS_CAMINO then
                return nil
            end
            local cx, cy = posicion[clave][1], posicion[clave][2]
            for _, v in ipairs(VECINOS) do
                if self:duenoCelda(cx + v[1], cy + v[2]) == nid then
                    local camino = {}
                    local k = clave
                    while k do
                        camino[#camino + 1] = posicion[k]
                        k = siguiente[k]
                    end
                    return camino
                end
            end
            for _, v in ipairs(VECINOS) do
                local nx, ny = cx + v[1], cy + v[2]
                local k = claveCelda(nx, ny)
                if not cerrada[k] and self:duenoCelda(nx, ny) == nil then
                    local g = coste[clave] + 1
                    if not coste[k] or g < coste[k] then
                        coste[k], siguiente[k], posicion[k] = g, clave, { nx, ny }
                        meterNodo(abiertos, { f = g + math.abs(nx - gx) + math.abs(ny - gy), clave = k })
                    end
                end
            end
        end
    end
    return nil
end

--- ¿Tiene `nid` una bandera en obra en el bloque alineado de (x, y)?
-- Entonces esa tierra ya está pedida: no se planta otra encima.
function Simulacion:banderaEnObraCerca(nid, x, y)
    local lado = Simulacion.bloques.bandera
    local cx0, cy0 = Simulacion.bloqueBandera(x, y)
    local b = self.estado.instalaciones[Simulacion.idBandera(nid, cx0 / lado, cy0 / lado)]
    return b ~= nil and b.progreso < 1
end

--- Sigue el camino más corto de celdas hacia la meta (`caminoCeldas`) y
-- planta una bandera en el bloque alineado más adelantado del camino que aún
-- toca lo suyo, en cualquier terreno. La siguiente se apoya en esta cuando
-- termine.
function Simulacion:banderaHacia(n, meta)
    local camino = self:caminoCeldas(n.id, Simulacion.celdaDe(meta.x, meta.y))
    if not camino or #camino == 0 then
        return false
    end
    for k = math.min(#camino, Simulacion.bloques.bandera + 1), 1, -1 do
        local x, y = (camino[k][1] + 0.5) * CELDA, (camino[k][2] + 0.5) * CELDA
        if self:banderaEnObraCerca(n.id, x, y) then
            return false
        end
        if self:puedePlantarBandera(n.id, x, y) then
            return self:ejecutar({ tipo = 'bandera', nacion = n.id, x = x, y = y })
        end
    end
    return false
end

--- El presidente NPC estira su tierra con banderas hacia el yacimiento que
-- más le vale (3.9, F12): uno sin explotar, o suyo pero descubierto, que no
-- tenga dueño y sin enemigos cerca. Solo si le alcanza sin tocar su reserva.
function Simulacion:planearBanderas(n)
    local reglas = Simulacion.bandera
    if
        disponible(n, 'dinero') < reglas.dinero + reglas.reservaTesoro
        or disponible(n, 'metal') < reglas.metal + Simulacion.consumo.reservaMetal * 0.5
    then
        return
    end
    local enemigos = self:sitiosEnemigos(n.id)
    local capital = self.estado.ciudades[n.capital]
    if not capital or not self.estado.territorio[n.id] then
        return
    end
    -- Valor de cada yacimiento conocido sin dueño (F12) sin mirar aún a los
    -- enemigos: la distancia de cada uno al territorio se guarda y se corrige
    -- al cambiar las celdas (`distanciaYacimiento`).
    local necesidad = self:necesidades(n.id)
    local candidatos = {}
    for _, d in ipairs(self:yacimientosConocidos(n.id)) do
        local quiere = d.riqueza * (necesidad[d.tipo] or 0)
        if quiere > 0 and not self:duenoDeposito(d) then
            local borde = self:distanciaYacimiento(n.id, d) or 0
            candidatos[#candidatos + 1] = { deposito = d, valor = quiere / (1 + borde / reglas.distanciaValor) }
        end
    end
    -- De mayor a menor valor (en empate, id menor); con un sitio enemigo en
    -- guerra cerca, el yacimiento no vale nada y se salta.
    table.sort(candidatos, antes)
    local intentos = 0
    for _, candidato in ipairs(candidatos) do
        local d = candidato.deposito
        local libre = true
        for _, s in ipairs(enemigos) do
            if hipotenusa(s.x - d.x, s.y - d.y) < reglas.enemigoCerca then
                libre = false
                break
            end
        end
        if libre then
            if self:banderaHacia(n, d) then
                return
            end
            intentos = intentos + 1
            if intentos >= 3 then
                return
            end
        end
    end
end

--- Valor de una bandera para su dueño: el F12 del yacimiento que protege (el
-- más cercano en su territorio), o 1 si no protege ninguno.
function Simulacion:valorBandera(n, b)
    local mejor, mejorD
    for _, d in ipairs(self:depositosCerca(b.x, b.y, Simulacion.bandera.alcance)) do
        local dist = hipotenusa(d.x - b.x, d.y - b.y)
        if not mejor or dist < mejorD or (dist == mejorD and d.id < mejor.id) then
            mejor, mejorD = d, dist
        end
    end
    if not mejor then
        return 1
    end
    return mejor.riqueza * (self:necesidades(n.id)[mejor.tipo] or 0)
end

--- Planta un campamento en (x, y): tiene que caer dentro del territorio propio,
-- en tierra donde se pueda construir y lejos de otro campamento suyo. Paga al
-- salir la tropa, que va por tierra desde el sitio propio más cercano.
-- La misma acción para un presidente NPC y para un jugador.
function Simulacion:levantarCampamento(nid, x, y)
    local e = self.estado
    local n = e.naciones[nid]
    local c = Simulacion.campamento
    if not n or not Simulacion.alcanza(n, c) then
        return false, 'coste'
    end
    local dueno = self:dueno(x, y)
    if not dueno or dueno.id ~= nid or (self.sitioValido and not self.sitioValido(x, y)) then
        return false, 'sitio'
    end
    for _, otro in ipairs(self:instalacionesDe(nid, 'campamento')) do
        if hipotenusa(otro.x - x, otro.y - y) < c.separacion then
            return false, 'cercaDeCampamento'
        end
    end
    -- Ni pegado a su ciudad.
    for _, ciudad in ipairs(self:ciudadesDe(nid)) do
        if hipotenusa(ciudad.x - x, ciudad.y - y) < c.separacion then
            return false, 'cercaDeCiudad'
        end
    end
    local desde = self:sitioCercano(nid, x, y, c.soldados)
    if not desde then
        return false, 'sinTropas'
    end
    local id = 'k:' .. nid .. ':' .. e.dia .. ':' .. math.floor(x) .. ',' .. math.floor(y)
    local construye = { id = id, tipo = 'campamento', x = x, y = y }
    local gid, motivo = self:enviarGrupo(nid, desde.id, 'construir', nil, construye, c.soldados)
    if not gid then
        return false, motivo
    end
    Simulacion.pagar(n, c)
    self:noticia(string.format('%s sale a plantar un campamento', n.nombre), n.color)
    return true
end

--- El presidente estira su territorio con campamentos: hacia el depósito sin
-- dueño más cercano o, si no hay, hacia el vecino más cercano. Lo planta en el
-- borde de lo suyo, en esa dirección. Sin tocar sus reservas y solo si el
-- petróleo que le entra alcanza para mantenerlo, con los que ya tiene en obra
-- o en camino (el jugador puede plantar sin mirarlo y pagar las consecuencias).
function Simulacion:planearCampamento(n)
    local c = Simulacion.campamento
    if
        disponible(n, 'dinero') < c.dinero + c.reservaTesoro
        or disponible(n, 'metal') < c.metal + Simulacion.consumo.reservaMetal * 0.5
        or disponible(n, 'petroleo') < c.petroleo + 10
    then
        return
    end
    local enObra = 0
    for _, i in ipairs(self:instalacionesDe(n.id, 'campamento')) do
        if i.progreso < 1 then
            enObra = enObra + 1
        end
    end
    for _, g in ipairs(self:gruposDe(n.id)) do
        if g.mision == 'construir' and g.construye and g.construye.tipo == 'campamento' then
            enObra = enObra + 1
        end
    end
    local petroleo = self:reservas(n.id)[2]
    local balance = petroleo.entra - petroleo.gasta
    if balance - (enObra + 1) * self:mantenimientoSiguiente(n.id) < c.margen then
        return
    end
    local ciudades = self:ciudadesDe(n.id)
    if #ciudades == 0 then
        return
    end
    -- Primero un puesto de acopio junto a una mina suya lejos de sus puestos
    -- (acorta el viaje de sus recolectores); estirar la tierra hacia las de
    -- nadie es cosa de las banderas.
    local puestos = {}
    for _, ciudad in ipairs(ciudades) do
        puestos[#puestos + 1] = ciudad
    end
    for _, k in ipairs(self:instalacionesDe(n.id, 'campamento')) do
        puestos[#puestos + 1] = k
    end
    local libres = {}
    for _, d in ipairs(self:yacimientosConocidos(n.id)) do
        local lejos = true
        for _, p in ipairs(puestos) do
            if distancia(p, d) < c.lejosAcopio then
                lejos = false
                break
            end
        end
        if lejos and self:duenoDeposito(d) == n.id then
            libres[#libres + 1] = { deposito = d, distancia = distancia(ciudades[1], d) }
        end
    end
    table.sort(libres, function(a, b)
        if a.distancia ~= b.distancia then
            return a.distancia < b.distancia
        end
        return a.deposito.id < b.deposito.id
    end)
    for _, libre in ipairs(libres) do
        local d = libre.deposito
        if self:ejecutar({ tipo = 'campamento', nacion = n.id, x = d.x, y = d.y }) then
            return
        end
    end
    -- Si no, hacia el vecino más cercano.
    local meta, metaD
    for _, otra in ipairs(self:todasCiudades()) do
        if otra.nacion ~= n.id then
            for _, ciudad in ipairs(ciudades) do
                local dist = distancia(ciudad, otra)
                if dist < Simulacion.alcanceGuerra and (not meta or dist < metaD) then
                    meta, metaD = otra, dist
                end
            end
        end
    end
    if not meta then
        return
    end
    -- Desde la ciudad propia más cercana a la meta, el último punto suyo en
    -- esa dirección (probando un poco a los lados).
    local origen, origenD
    for _, ciudad in ipairs(ciudades) do
        local dist = distancia(ciudad, meta)
        if not origen or dist < origenD then
            origen, origenD = ciudad, dist
        end
    end
    local rumbo = math.atan2(meta.y - origen.y, meta.x - origen.x)
    -- El rayo sigue hasta salir de lo suyo o pasar la meta.
    for _, giro in ipairs({ 0, 0.4, -0.4, 0.8, -0.8 }) do
        local a = rumbo + giro
        local ultimo
        local r = 0
        while true do
            r = r + 250
            if r > origenD then
                break
            end
            local x, y = origen.x + math.cos(a) * r, origen.y + math.sin(a) * r
            local dueno = self:dueno(x, y)
            if not dueno or dueno.id ~= n.id then
                break
            end
            if not self.sitioValido or self.sitioValido(x, y) then
                ultimo = { x, y }
            end
        end
        if ultimo then
            if self:ejecutar({ tipo = 'campamento', nacion = n.id, x = ultimo[1], y = ultimo[2] }) then
                return
            end
        end
    end
end

--- Bases militares en su territorio, hacia el vecino más cercano: una a la vez.
function Simulacion:construirBase(n, azar)
    local e = self.estado
    if grupoEnCamino(self, n.id, 'construir', 'base') then
        return
    end
    local ciudades = self:ciudadesDe(n.id)
    -- La base nace vacía: sus lanzacohetes se colocan después desde el parque.
    local tesoro = 60
    local metal = Simulacion.costeObra.base
    local petroleo = 0
    if
        n.tecnologia < 1
        or not Simulacion.alcanza(n, { dinero = tesoro, metal = metal, petroleo = petroleo })
        or n.bases >= #ciudades * Simulacion.basesPorCiudad
    then
        return
    end
    -- La ciudad con menos bases alrededor (hasta 4 cada una).
    local origen, menos
    for _, c in ipairs(ciudades) do
        local cuenta = 0
        for _, b in ipairs(self:instalacionesDe(n.id, 'base')) do
            if distancia(b, c) < self:alcance(c) then
                cuenta = cuenta + 1
            end
        end
        if cuenta < Simulacion.basesPorCiudad and (not origen or cuenta < menos) then
            origen, menos = c, cuenta
        end
    end
    if not origen then
        return
    end
    -- Hacia la ciudad extranjera más cercana; repartidas en abanico.
    local rival, rd
    for _, c in ipairs(self:todasCiudades()) do
        if c.nacion ~= n.id then
            local d = distancia(origen, c)
            if not rival or d < rd then
                rival, rd = c, d
            end
        end
    end
    local rumbo = rival and math.atan2(rival.y - origen.y, rival.x - origen.x) or azar() * math.pi * 2
    rumbo = rumbo + (menos - 1.5) * 0.9
    for intento = 1, 8 do
        local a = rumbo + azar(-0.5, 0.5)
        local r = self:alcance(origen) * azar(0.35, 0.8)
        local x, y = origen.x + math.cos(a) * r, origen.y + math.sin(a) * r
        local dueno = self:dueno(x, y)
        local valido = not self.sitioValido or self.sitioValido(x, y)
        local desde = valido and dueno and dueno.id == n.id and self:sitioCercano(n.id, x, y, 60)
        -- Solo donde se llega por tierra; si no, se prueba otro sitio.
        if desde and self:trazar(desde.x, desde.y, x, y) then
            local id = 'b:' .. n.id .. ':' .. e.dia .. ':' .. intento
            do
                local construye = { id = id, tipo = 'base', x = x, y = y, lanzacohetes = 0 }
                local gid = self:enviarGrupo(n.id, desde.id, 'construir', nil, construye, 60)
                if gid then
                    n.bases = n.bases + 1
                    Simulacion.pagar(n, { dinero = tesoro, metal = metal, petroleo = petroleo })
                    self:noticia(string.format('%s empieza a levantar una base militar', n.nombre), n.color)
                end
            end
            return
        end
    end
end

--- Obras del día: avanza la construcción, crece la fortificación y se repara.
function Simulacion:obras()
    local e = self.estado
    for _, i in ipairs(self:todasInstalaciones()) do
        if i.progreso < 1 then
            local avance
            if i.tipo == 'campamento' then
                avance = 1 / Simulacion.campamento.dias
            elseif i.tipo == 'bandera' then
                avance = 1 / Simulacion.bandera.dias
            else
                avance = 0.05 * math.min(1.5, i.soldados / 40)
            end
            i.progreso = math.min(1, i.progreso + avance)
            if i.progreso >= 1 then
                local n = e.naciones[i.nacion]
                -- Las banderas son muchas: no llenan las noticias.
                if i.tipo == 'bandera' then
                    self:terminarBandera(i)
                else
                    self:noticia(string.format('%s termina %s', n.nombre, nombreInstalacion(self, i)), n.color)
                    self:reclamarBloque(i)
                end
            end
        else
            -- Cuanto más tiempo en pie, más fortificada (un año para el máximo).
            -- Un campamento son tiendas y sacos terreros: no se fortifica.
            if i.tipo ~= 'campamento' and i.tipo ~= 'bandera' then
                i.fortificacion = math.min(1, i.fortificacion + 1 / 365)
            end
            local n = e.naciones[i.nacion]
            local maxima = Simulacion.saludMaxima[i.tipo]
            if
                (i.atacadaDia or 0) < e.dia - 3
                and i.salud < maxima
                and disponible(n, 'metal') >= Simulacion.consumo.reparacion
            then
                i.salud = math.min(maxima, i.salud + 2)
                gastar(n, 'metal', Simulacion.consumo.reparacion)
            end
        end
    end
end

-- Grupos en marcha ---------------------------------------------------------------------------

--- El grupo vuelve a casa (misión 'regreso'): a su sitio de salida o, si ya
-- no es suyo, al sitio propio más cercano; con carga, a una ciudad o un
-- campamento, donde la entrega. Sale de su batalla si estaba en una.
function Simulacion:volver(g)
    local casa = self:sitio(g.desde)
    if not casa or casa.nacion ~= g.nacion then
        casa = self:sitioCercano(g.nacion, g.x, g.y, 0)
    end
    if casa and type(g.carga) == 'number' and g.carga > 0 and not Simulacion.puestoDeAcopio(casa) then
        casa = self:ciudadDuena(g.nacion, g.x, g.y)
    end
    if not casa then
        self.estado.grupos[g.id] = nil
        return
    end
    if g.tipoCarga then
        g.fase = 'vuelta'
    end
    g.batalla, g.apoyo, g.bandera, g.alerta = nil, nil, nil, nil
    g.mision, g.desde, g.detenido, g.detenidoDesde = 'regreso', casa.id, nil, nil
    self:reindexarGrupo(g)
    g.destinoX, g.destinoY = casa.x, casa.y
    -- Vuelve por tierra; si por lo que sea no hay camino, en línea recta.
    g.ruta = self:trazar(g.x, g.y, casa.x, casa.y) or { g.x, g.y, casa.x, casa.y }
    g.largo = Simulacion.largoRuta(g.ruta)
    g.recorrido, g.antesRecorrido = 0, 0
end

--- El grupo da media vuelta hacia su sitio con los vivos y los heridos.
function Simulacion:retirar(g, blanco)
    local e = self.estado
    anotar(self, g, 'derrotas')
    local heridos = g.heridos or tropasVacias()
    self:noticia(
        string.format(
            'El ejército de %s se retira de %s: vuelven %d soldados y %d lanzacohetes; %d heridos y averiados',
            e.naciones[g.nacion].nombre,
            nombreBlanco(self, blanco),
            g.soldados,
            g.lanzacohetes or 0,
            heridos.soldados + heridos.lanzacohetes
        ),
        { 1, 0.7, 0.45 }
    )
    self:volver(g)
    if e.grupos[g.id] then
        g.retirada = true
    end
end

--- ¿Tiene una ciudad un ejército enemigo encima (combatió hoy o ayer)? Sitiada
-- no recluta, no recibe defensas ni avanza su reparación.
function Simulacion:sitiada(c)
    return (c.asediadaDia or -math.huge) >= self.estado.dia - 1
end

--- Una capital pierde su batalla (3.3): no cambia de manos. Queda con
-- `derrota` de vida, conserva lo que sobrevivió (tropas, defensas, mejora y
-- cola de heridos), y el grupo se lleva todo lo que su nación tenía afuera
-- (`g.botin`) y vuelve a casa con ello. El almacén y la bóveda no se tocan.
function Simulacion:saquearCapital(c, g)
    local e = self.estado
    local n = e.naciones[c.nacion]
    local atacante = e.naciones[g.nacion]
    c.vida = Simulacion.vidaCiudad.derrota
    local botin = g.botin or { metal = 0, petroleo = 0, dinero = 0 }
    local hoy = {}
    for _, recurso in ipairs(RECURSOS_ALMACEN) do
        hoy[recurso] = n.afuera[recurso]
        botin[recurso] = botin[recurso] + n.afuera[recurso]
        n.afuera[recurso] = 0
    end
    g.botin = botin
    anotar(self, g, 'victorias')
    self:sumarCansancio(n.id, 8)
    self:noticia(
        string.format(
            '%s saquea %s: se lleva %d de metal, %d de petróleo y %d de dinero',
            atacante.nombre,
            c.nombre,
            math.floor(hoy.metal),
            math.floor(hoy.petroleo),
            math.floor(hoy.dinero)
        ),
        atacante.color
    )
    self:volver(g)
end

function Simulacion:llegada(g)
    local e = self.estado
    if g.mision == 'regreso' then
        -- Si la casa cayó o cambió de manos mientras volvía, sigue hacia el
        -- sitio propio más cercano; sin sitios, volver() lo da por perdido.
        local casa = self:sitio(g.desde)
        if not casa or casa.nacion ~= g.nacion then
            return self:volver(g)
        end
        -- Recolectores que volvieron con el avión lleno: entregan y vuelven a
        -- su mina con su avión, hasta que los retiren o se acabe la mina
        -- (diseno/aviones-de-transporte.md).
        local mina = g.ciclo and e.depositos[g.ciclo]
        local tipoCarga = g.tipoCarga
        if mina then
            -- Entrega primero: sigue el ciclo solo si aún le falta ese recurso.
            self:entregarCarga(g, casa)
            if tipoCarga and (self:faltanRecursos(e.naciones[g.nacion], {})[tipoCarga] or 0) <= 0 then
                mina = nil
                g.ciclo = nil
            end
        end
        if mina and not self:minaCerrada(mina) then
            self:recibirHeridos(g, casa)
            g.ciclo = nil
            g.mision, g.fase, g.yacimiento = 'recolectar', 'ida', mina.id
            g.carga = 0
            self:reindexarGrupo(g)
            g.destinoX, g.destinoY = mina.x, mina.y
            g.ruta = { g.x, g.y, mina.x, mina.y }
            g.largo = Simulacion.largoRuta(g.ruta)
            g.recorrido, g.antesRecorrido = 0, 0
            return
        end
        casa.soldados = casa.soldados + g.soldados
        self:recibirHeridos(g, casa)
        self:devolverMunicion(g, casa)
        -- La carga de un grupo de recolección (o lo que ganó en una batalla).
        self:entregarCarga(g, casa)
        -- El botín de un saqueo entra en su nación; lo que no cabe, afuera.
        if g.botin then
            local n = e.naciones[g.nacion]
            for _, recurso in ipairs(RECURSOS_ALMACEN) do
                self:ingresar(n, recurso, g.botin[recurso])
            end
            g.botin = nil
        end
        -- Una obra que no llegó a levantarse devuelve sus lanzacohetes al sitio
        -- hasta su tope; lo que no quepa, al parque de su ciudad.
        if g.construye and (g.construye.lanzacohetes or 0) > 0 then
            local cuantos = g.construye.lanzacohetes
            self:colocarLanzacohetes(casa, cuantos, Armamento.vaciar(g.construye, 'lanzacohetes'))
        end
        -- Unos lanzacohetes de entrega que no pudieron instalarse.
        if type(g.carga) == 'table' then
            self:colocarLanzacohetes(casa, g.carga.cantidad, g.carga.cantidadPor)
            g.carga = nil
        end
        e.grupos[g.id] = nil
    elseif g.mision == 'construir' then
        local c = g.construye
        -- Las extracciones ya no existen (una partida de la versión 18 las
        -- traía en camino): el convoy vuelve.
        if e.instalaciones[c.id] or c.tipo == 'extraccion' then
            return self:volver(g)
        end
        e.instalaciones[c.id] = {
            id = c.id,
            tipo = c.tipo,
            nacion = g.nacion,
            x = c.x,
            y = c.y,
            progreso = 0,
            fortificacion = 0,
            salud = Simulacion.saludMaxima[c.tipo],
            soldados = g.soldados,
            misiles = 0,
            interceptores = 0,
            aviones = 0,
            lanzacohetes = c.lanzacohetes,
            inicio = e.dia,
        }
        local inst = e.instalaciones[c.id]
        if (c.lanzacohetes or 0) > 0 then
            inst.lanzacohetesPor = Armamento.porModelo(c, 'lanzacohetes')
        end
        self:ensuciarEn(e.instalaciones[c.id])
        self:devolverMunicion(g, e.instalaciones[c.id])
        e.grupos[g.id] = nil
    elseif g.mision == 'entrega' then
        -- Se instalan si la ciudad o la base sigue siendo suya (lo que no cabe,
        -- al parque de su ciudad); si no, la carga vuelve a casa.
        local c = self:sitio(g.objetivo)
        if c and c.nacion == g.nacion then
            self:colocarLanzacohetes(c, g.carga.cantidad, g.carga.cantidadPor)
            e.grupos[g.id] = nil
        else
            self:volver(g)
        end
    elseif g.mision == 'abasto' then
        self:llegadaAbasto(g)
    elseif g.mision == 'guarnicion' then
        -- Llega a su bandera del borde, o ya estaba en ella (banderas.lua).
        self:llegarAGuarnicion(g)
    elseif g.mision == 'refuerzo' then
        local inst = e.instalaciones[g.objetivo]
        if inst and inst.nacion == g.nacion and inst.tipo ~= 'bandera' then
            inst.soldados = inst.soldados + g.soldados
            self:devolverMunicion(g, inst)
            e.grupos[g.id] = nil
        else
            self:volver(g)
        end
    elseif g.mision == 'recolectar' then
        -- Llega a su mina: recolecta desde hoy; cerrada (o ya no existe), vuelve vacío.
        local d = e.depositos[g.yacimiento]
        if not d or self:minaCerrada(d) then
            return self:volver(g)
        end
        g.fase = 'recolectando'
    elseif g.mision == 'apoyo' then
        -- Llega a una batalla de su nación: se suma a su bando; si ya acabó, vuelve.
        local b = e.batallas[g.apoyo]
        local lado = b and self:ladoDe(b, g.nacion)
        g.apoyo = nil
        if lado then
            self:unirBatalla(b, g, lado)
        else
            self:volver(g)
        end
    elseif g.mision == 'atacar' then
        local d = e.depositos[g.objetivo]
        if d then
            return self:llegarAMina(g, d)
        end
        local sitio = e.instalaciones[g.objetivo] or e.ciudades[g.objetivo]
        if not sitio or sitio.nacion == g.nacion then
            return self:volver(g)
        end
        self:llegarASitio(g, sitio)
    elseif g.mision == 'mover' then
        -- El jugador llevó al grupo a un punto libre (dueño 2026-09-29): se
        -- queda ahí esperando nuevas órdenes. Si tiene soldados a 0 (batalla,
        -- derrota), se borra el grupo como cualquier otro.
        if (g.soldados or 0) <= 0 and (g.lanzacohetes or 0) <= 0 and not g.lider then
            e.grupos[g.id] = nil
        end
    end
end

-- Choques entre ejércitos (diseno/ejercitos-en-el-mapa.md, 3.7, F7) --------------------------
--
-- Tras mover a todos, dos grupos de naciones hostiles (`hostiles`) cuyos
-- trayectos del día pasan a menos de `radio` quedan trabados si al menos uno va
-- a atacar: se paran donde se cruzan y empieza una batalla de campo entre los
-- dos (diseno/recoleccion-y-batallas.md, 3.7). Los que vuelven retirados no
-- chocan (aún no hay persecución), ni los recolectores quietos en su mina.

Simulacion.choque = {
    radio = 3000, -- distancia de choque entre los trayectos del día (300 m)
    celda = 16384, -- lado de la rejilla que busca solo a los vecinos
    sinRejilla = 24, -- con tan pocos candidatos en un paso, todos con todos (sin rejilla)
    ventajaDefensa = 0.1, -- más golpe al pelear dentro del territorio propio
}

--- ¿Están `a` y `b` en guerra abierta (no en alto el fuego)?
function Simulacion:enGuerraAbierta(a, b)
    local guerra = self:guerraEntre(a, b)
    return guerra ~= nil and guerra.fase == 'tension'
end

--- ¿Pelean `a` y `b` si se encuentran? Hoy, dos naciones en guerra abierta.
-- Es la única pregunta de hostilidad de las batallas: los bandos que no son
-- una nación (los campamentos rebeldes, cuando existan) entrarán aquí.
function Simulacion:hostiles(a, b)
    return a ~= b and self:enGuerraAbierta(a, b)
end

--- ¿Puede chocar hoy? Ejércitos (con líder) que atacan o vuelven, grupos de
-- recolección en camino (ida o vuelta con carga) y grupos que van a una
-- batalla; ni en una batalla ya, ni detenidos por un alto el fuego, ni
-- retirados.
local function puedeChocar(g)
    if g.batalla or g.detenido or g.retirada then
        return false
    end
    if g.mision == 'recolectar' then
        return g.fase == 'ida'
    end
    if g.mision == 'apoyo' then
        return true
    end
    if g.mision == 'guarnicion' then
        -- En camino a su bandera, como un ejército; ya en ella, no.
        return g.bandera == nil
    end
    if g.mision == 'regreso' and g.tipoCarga then
        return true
    end
    return g.lider ~= nil and (g.mision == 'atacar' or g.mision == 'regreso')
end

--- Distancia mínima entre dos trayectos del día que se recorren a la vez (F7)
-- y el momento `t` (0 a 1) en que se da.
local function cruce(a, b)
    local rx, ry = a.antesX - b.antesX, a.antesY - b.antesY
    local vx = (a.x - a.antesX) - (b.x - b.antesX)
    local vy = (a.y - a.antesY) - (b.y - b.antesY)
    local vv = vx * vx + vy * vy
    local t = 0
    if vv > 0 then
        t = math.max(0, math.min(1, -(rx * vx + ry * vy) / vv))
    end
    return hipotenusa(rx + vx * t, ry + vy * t), t
end

--- Lleva el grupo al punto de su trayecto del día en el momento `t`.
local function pararEn(g, t)
    if g.ruta then
        g.recorrido = g.antesRecorrido + (g.recorrido - g.antesRecorrido) * t
        g.x, g.y = Simulacion.puntoEnRuta(g.ruta, g.recorrido)
    else
        g.x, g.y = g.antesX + (g.x - g.antesX) * t, g.antesY + (g.y - g.antesY) * t
    end
end

--- Nombre de la ciudad más cercana a (x, y), para las noticias.
function Simulacion:lugarCercano(x, y)
    local mejor, mejorD
    for _, c in ipairs(lista(self.estado.ciudades)) do
        local d = hipotenusa(c.x - x, c.y - y)
        if not mejorD or d < mejorD then
            mejor, mejorD = c, d
        end
    end
    return mejor and mejor.nombre or 'ninguna parte'
end

--- Punto del choque entre `g` y `o`: entre los dos.
local function puntoChoque(g, o)
    return (g.x + o.x) / 2, (g.y + o.y) / 2
end

--- Nombre de la nación de un grupo, para las noticias.
function Simulacion:nombreNacionDe(g)
    local n = self.estado.naciones[g.nacion]
    return n and n.nombre or '?'
end

--- Apunta en `pares` el par (g, o) si chocan: uno de los dos ataca, sus
-- trayectos del paso pasan a menos de `radio` y sus naciones son hostiles (lo
-- más caro, al final).
local function probarChoque(self, pares, g, o, radio)
    if g.nacion ~= o.nacion and (g.mision == 'atacar' or o.mision == 'atacar') then
        local d, t = cruce(g, o)
        if d < radio and self:hostiles(g.nacion, o.nacion) then
            pares[#pares + 1] = { g = g, o = o, d = d, t = t }
        end
    end
end

--- Naciones en guerra abierta (id -> true), o nil si no hay ninguna: solo
-- ellas pueden chocar.
function Simulacion:nacionesEnGuerra()
    local enGuerra
    for _, guerra in pairs(self.estado.guerras) do
        if guerra.fase == 'tension' then
            enGuerra = enGuerra or {}
            enGuerra[guerra.atacante], enGuerra[guerra.defensor] = true, true
        end
    end
    return enGuerra
end

--- Busca los choques del paso de marcha (F7) entre los `candidatos` (los que
-- pueden chocar, de naciones en guerra abierta, en orden de id; si no se dan,
-- se buscan). Solo compara ejércitos que
-- comparten celda de la rejilla (el trayecto de cada uno, ensanchado `radio`,
-- la marca). Si un ejército puede chocar con varios, primero el de menor
-- distancia; a igual distancia, el de id menor.
function Simulacion:detectarChoques(candidatos)
    local e = self.estado
    local reglas = Simulacion.choque
    local lado, radio = reglas.celda, reglas.radio
    if not candidatos then
        local enGuerra = self:nacionesEnGuerra()
        if not enGuerra then
            return
        end
        candidatos = {}
        local indice = self:indiceGrupos().lista
        for i = 1, #indice do
            local g = indice[i]
            if e.grupos[g.id] == g and enGuerra[g.nacion] and puedeChocar(g) then
                candidatos[#candidatos + 1] = g
            end
        end
    end
    local atacan = false
    for _, g in ipairs(candidatos) do
        atacan = atacan or g.mision == 'atacar'
    end
    if #candidatos < 2 or not atacan then
        return
    end
    local pares = {}
    if #candidatos <= Simulacion.choque.sinRejilla then
        -- Pocos (lo normal): todos con todos, en orden de id.
        for i = 1, #candidatos - 1 do
            local g = candidatos[i]
            for j = i + 1, #candidatos do
                probarChoque(self, pares, g, candidatos[j], radio)
            end
        end
    else
        -- Rejilla: cada candidato marca las celdas de su trayecto del paso,
        -- ensanchado `radio`; solo se comparan los que comparten celda.
        local rejilla = {}
        for _, g in ipairs(candidatos) do
            local x0 = math.floor((math.min(g.antesX, g.x) - radio) / lado)
            local x1 = math.floor((math.max(g.antesX, g.x) + radio) / lado)
            local y0 = math.floor((math.min(g.antesY, g.y) - radio) / lado)
            local y1 = math.floor((math.max(g.antesY, g.y) + radio) / lado)
            for cx = x0, x1 do
                for cy = y0, y1 do
                    local clave = cx * 65536 + cy
                    local celda = rejilla[clave]
                    if not celda then
                        celda = {}
                        rejilla[clave] = celda
                    end
                    celda[#celda + 1] = g
                end
            end
        end
        for _, g in ipairs(candidatos) do
            local vistos = {}
            local x0 = math.floor(math.min(g.antesX, g.x) / lado)
            local x1 = math.floor(math.max(g.antesX, g.x) / lado)
            local y0 = math.floor(math.min(g.antesY, g.y) / lado)
            local y1 = math.floor(math.max(g.antesY, g.y) / lado)
            for cx = x0, x1 do
                for cy = y0, y1 do
                    local celda = rejilla[cx * 65536 + cy]
                    if celda then
                        for _, o in ipairs(celda) do
                            if o.id > g.id and not vistos[o.id] then
                                vistos[o.id] = true
                                probarChoque(self, pares, g, o, radio)
                            end
                        end
                    end
                end
            end
        end
    end
    if #pares == 0 then
        return
    end
    table.sort(pares, function(p, q)
        if p.d ~= q.d then
            return p.d < q.d
        end
        if p.g.id ~= q.g.id then
            return p.g.id < q.g.id
        end
        return p.o.id < q.o.id
    end)
    local trabados = false
    for _, p in ipairs(pares) do
        if not p.g.batalla and not p.o.batalla then
            self:trabar(p.g, p.o, p.t)
            trabados = true
        end
    end
    return trabados
end

--- Traba a `g` y `o` en el momento `t` de sus trayectos: se paran y empieza
-- una batalla de campo entre los dos (ataca el que iba a atacar; si iban los
-- dos, el de id menor).
function Simulacion:trabar(g, o, t)
    pararEn(g, t)
    pararEn(o, t)
    local atacante, defensor = g, o
    if g.mision ~= 'atacar' then
        atacante, defensor = o, g
    end
    local x, y = puntoChoque(g, o)
    self:crearBatalla({ tipo = 'campo' }, x, y, { atacante }, { defensor })
    self:noticia(
        string.format(
            'El ejército de %s se enfrenta al de %s cerca de %s',
            self:nombreNacionDe(atacante),
            self:nombreNacionDe(defensor),
            self:lugarCercano(x, y)
        ),
        { 1, 0.55, 0.35 }
    )
end

--- Qué hace hoy un grupo detenido: 'espera' (su guerra está en calma),
-- 'sigue' (su guerra está abierta) o 'vuelve' (ya no hay guerra, o lleva
-- más de `maxDiasDetenido` días parado). Contra una mina, la guerra es
-- cualquiera de su nación.
function Simulacion:esperaDetenido(g)
    local e = self.estado
    if e.dia - (g.detenidoDesde or e.dia) > Simulacion.maxDiasDetenido then
        return 'vuelve'
    end
    local blanco = e.instalaciones[g.objetivo] or e.ciudades[g.objetivo]
    local guerras = {}
    if blanco then
        guerras[1] = self:guerraEntre(g.nacion, blanco.nacion)
    elseif e.depositos[g.objetivo] then
        guerras = self:guerrasDe(g.nacion)
    end
    if #guerras == 0 then
        return 'vuelve'
    end
    local abierta = false
    for _, guerra in ipairs(guerras) do
        if guerra.fase == 'calma' then
            return 'espera'
        end
        abierta = abierta or guerra.fase == 'tension'
    end
    return abierta and 'sigue' or 'espera'
end

--- Un ejército que gana un choque junto a su destino (ya en él: `recorrido`
-- al final de la ruta) hace su llegada ese mismo día y empieza el asalto,
-- en vez de esperar al día siguiente (decisión del dueño: si no, los que
-- salen de la ciudad lo traban cada día y el asalto se retrasa semanas).
-- Los que ya llegaron hoy (`g.llegada`) no vuelven a llegar.
function Simulacion:asaltarTrasChoque()
    local e = self.estado
    for _, g in ipairs(self:gruposOrdenados()) do
        if
            g.mision == 'atacar'
            and not g.batalla
            and not g.detenido
            and g.llegada ~= e.dia
            and g.ruta
            and g.recorrido >= g.largo
            and e.grupos[g.id] == g
        then
            self.trasChoque = true -- para quien mire (el registro); no es estado
            self:llegar(g)
            self.trasChoque = nil
        end
    end
end

--- Lo que anda `g` en un paso de marcha (px de mundo), o 0 si ahora no anda:
-- en una batalla, detenido por un alto el fuego, recolectando en su mina o ya
-- en su destino. Un ejército va a la velocidad de su modelo más lento (F4) y,
-- sin combustible, un grupo con vehículos va a media marcha (F9). La vista no
-- adivina nada: dibuja entre el paso anterior y el actual (`posicionGrupo`).
function Simulacion:pasoDeMarcha(g)
    if g.batalla or g.detenido or (g.mision == 'recolectar' and g.fase == 'recolectando') then
        return 0
    end
    if g.ruta then
        if g.recorrido >= g.largo then
            return 0
        end
        -- Todo viaje largo va en avión: espera el suyo y vuela a su velocidad.
        if Simulacion.Aviones.vuela(g) then
            return self:pasoEnAvion(g)
        end
    elseif g.x == g.destinoX and g.y == g.destinoY then
        return 0
    end
    local paso = g.mision == 'construir' and Simulacion.velocidadGrupo or Simulacion.velocidadEjercito
    if g.mision ~= 'construir' then
        local velocidad = Armamento.velocidadGrupo(g)
        if velocidad ~= 1 then
            paso = paso * velocidad
        end
    end
    local n = self.estado.naciones[g.nacion]
    if n and n.sinCombustible and (g.lanzacohetes or 0) > 0 then
        paso = paso / 2
    end
    return paso / Simulacion.pasosDia
end

--- Llegada de `g` apuntando el día (`g.llegada`): un grupo llega una vez al
-- día como mucho (ver `llegadasDelDia` y `asaltarTrasChoque`).
function Simulacion:llegar(g)
    g.llegada = self.estado.dia
    self:llegada(g)
end

--- Un paso de marcha: andan los que van de camino (los demás se quedan con el
-- paso anterior igual al actual, para que la vista no los mueva); luego se
-- buscan los choques (los trabados no llegan), llegan los demás y se avisa de
-- los ataques que están por llegar. Todo en el paso en que ocurre.
--
-- Para no mirar en cada paso los miles de grupos quietos (guarniciones,
-- recolectores en su mina, ejércitos en batalla), se recuerdan los activos
-- (`self.activos`, no es estado): los que anduvieron en el último paso y los
-- que pueden chocar. Se vuelven a buscar entre todos tras cualquier cosa que
-- pueda poner en marcha a un grupo: un comando, el principio o el final del
-- día, un grupo nuevo, una ruta nueva (`trazar`) o una batalla que acaba
-- (`cambiosMarcha`). El resultado es el mismo que mirarlos todos siempre
-- (`marchaSinActivos`; lo comprueba tests/test_nationsrts_marcha.lua).
function Simulacion:moverPaso()
    local e = self.estado
    -- Los aviones primero: uno que llega a buscar a su grupo lo pone en marcha.
    self:moverVuelos()
    local llegan = {}
    local esperan = {} -- grupos que esperan avión (mundo/simulacion/aviones.lua)
    -- Sin choques en campo abierto: solo se pelea en minas y ciudades
    -- (diseno/aviones-de-transporte.md).
    local enGuerra = Simulacion.choquesEnCampo and self:nacionesEnGuerra()
    local candidatos = enGuerra and {}
    local activos = self.activos
    local recorrer, pasos
    if activos and activos.tabla == e.grupos and activos.siguiente == e.siguienteGrupo then
        recorrer, pasos = activos.lista, activos.pasos
    else
        recorrer = self:indiceGrupos().lista
    end
    -- Los que siguen activos: en su sitio de la lista (sin copiarla si no cae ninguno).
    local siguen, pasosSiguen, n = recorrer, pasos, 0
    if not pasos then
        siguen, pasosSiguen = {}, {}
    end
    for i = 1, #recorrer do
        local g = recorrer[i]
        if e.grupos[g.id] == g then
            if g.antesX ~= g.x or g.antesY ~= g.y or g.antesRecorrido ~= g.recorrido then
                g.antesX, g.antesY, g.antesRecorrido = g.x, g.y, g.recorrido
            end
            local paso = 0
            if not (g.batalla or g.detenido or (g.ruta and g.recorrido >= g.largo)) then
                -- Lo que anda no cambia hasta que algo obliga a buscar de nuevo los activos.
                paso = pasos and pasos[i] or self:pasoDeMarcha(g)
            end
            if paso > 0 then
                local ruta = g.ruta
                if ruta then
                    if g.largo - g.recorrido > paso then
                        local recorrido = g.recorrido + paso
                        g.recorrido = recorrido
                        if #ruta == 4 and g.largo > 0 then
                            -- En línea recta (`trazar`): sin buscar el tramo.
                            local t = recorrido / g.largo
                            g.x, g.y = ruta[1] + (ruta[3] - ruta[1]) * t, ruta[2] + (ruta[4] - ruta[2]) * t
                        else
                            g.x, g.y = Simulacion.puntoEnRuta(ruta, recorrido)
                        end
                    else
                        -- A menos de un paso: llega (y se queda en el sitio).
                        g.recorrido = g.largo
                        g.x, g.y = g.destinoX, g.destinoY
                        llegan[#llegan + 1] = g
                    end
                else
                    -- Partidas de la versión 3: en línea recta.
                    local dx, dy = g.destinoX - g.x, g.destinoY - g.y
                    local d = math.sqrt(dx * dx + dy * dy)
                    if d > paso then
                        g.x, g.y = g.x + dx / d * paso, g.y + dy / d * paso
                    else
                        g.x, g.y = g.destinoX, g.destinoY
                        llegan[#llegan + 1] = g
                    end
                end
            end
            local choca = candidatos and puedeChocar(g)
            if candidatos and choca and enGuerra[g.nacion] then
                candidatos[#candidatos + 1] = g
            end
            local espera = paso == 0 and not (g.batalla or g.detenido) and Simulacion.Aviones.vuela(g)
            if espera and not (g.vuelo and e.vuelos[g.vuelo]) then
                esperan[#esperan + 1] = g
            end
            if paso > 0 or choca or espera then
                n = n + 1
                siguen[n], pasosSiguen[n] = g, paso
            end
        end
    end
    for k = #siguen, n + 1, -1 do
        siguen[k], pasosSiguen[k] = nil, nil
    end
    self.activos = { tabla = e.grupos, siguiente = e.siguienteGrupo, lista = siguen, pasos = pasosSiguen }
    local cambios = self.cambiosMarcha
    if candidatos then
        self:detectarChoques(candidatos)
    end
    if #esperan > 0 then
        self:asignarAviones(esperan)
    end
    for _, g in ipairs(llegan) do
        -- Una llegada puede borrar otros grupos: esos ya no llegan.
        if e.grupos[g.id] == g and not g.batalla then
            self:llegar(g)
        end
    end
    -- Una ruta nueva o una batalla que acaba pueden poner en marcha a
    -- cualquiera: en el paso siguiente se miran todos. Los que llegan o se
    -- traban solo se paran, y eso ya lo ve el paso siguiente.
    if self.cambiosMarcha ~= cambios or Simulacion.marchaSinActivos then
        self.activos = nil
    end
    self:avisarAtaques()
end

--- Al empezar el día, los grupos que ya estaban en su destino (y no pelean,
-- ni esperan un alto el fuego, ni recolectan) vuelven a llegar: el ejército
-- ante un sitio enemigo lo vuelve a asaltar, la guarnición sigue en su
-- bandera, el que se llevó a un punto se queda. Los detenidos miran su guerra.
function Simulacion:llegadasDelDia()
    local e = self.estado
    for _, g in ipairs(self:gruposOrdenados()) do
        if e.grupos[g.id] == g and g.detenido then
            -- Detenido por un alto el fuego: espera donde está mientras dure la
            -- calma de su guerra; si la guerra sigue sin calma, retoma la marcha;
            -- si ya no hay guerra (paz o cayó una nación), vuelve a casa.
            local espera = self:esperaDetenido(g)
            if espera == 'sigue' then
                g.detenido, g.detenidoDesde = nil, nil
            elseif espera == 'vuelve' then
                self:volver(g)
            end
        end
    end
    for _, g in ipairs(self:gruposOrdenados()) do
        local quieto = g.batalla or g.detenido or (g.mision == 'recolectar' and g.fase == 'recolectando')
        local enDestino
        if g.ruta then
            enDestino = g.recorrido >= g.largo
        else
            enDestino = g.x == g.destinoX and g.y == g.destinoY
        end
        if e.grupos[g.id] == g and enDestino and not quieto then
            self:llegar(g)
        end
    end
end

-- Batallas (mundo/simulacion/batallas.lua) ---

require('mundo.simulacion.batallas').instalar(Simulacion)

-- Consultas para la vista (mundo/simulacion/consultas.lua) -----------------------------------------

require('mundo.simulacion.consultas').instalar(Simulacion)

-- Ataques y órdenes a los grupos (mundo/simulacion/ataques.lua) ------------------------------------

require('mundo.simulacion.ataques').instalar(Simulacion)

-- IA de recolección de los NPC (mundo/simulacion/recoleccionIA.lua) ---

require('mundo.simulacion.recoleccionIA').instalar(Simulacion)

-- Diplomacia y guerra (mundo/simulacion/diplomacia.lua) ---

require('mundo.simulacion.diplomacia').instalar(Simulacion)

-- Exploradores e informes (mundo/simulacion/exploracion.lua) ---

require('mundo.simulacion.exploracion').instalar(Simulacion)

-- Economía cerrada: producción, munición y taller (diseno/economia.md) ---

require('mundo.simulacion.produccion').instalar(Simulacion)
require('mundo.simulacion.municion').instalar(Simulacion)
require('mundo.simulacion.almacen').instalar(Simulacion)
require('mundo.simulacion.taller').instalar(Simulacion)
require('mundo.simulacion.poblacion').instalar(Simulacion)

-- El día ------------------------------------------------------------------------------------

--- Lo que pasa al empezar un día: la economía, las decisiones de los NPC, las
-- obras, la diplomacia, las guerras y las llegadas del día.
function Simulacion:empezarDia()
    local e = self.estado
    e.dia = e.dia + 1
    local azar = Ruido.azar(Ruido.hash(e.semilla, e.dia, 91))
    self:mermar()
    self:producirRecursos()
    local vivas = self:vivas()
    for k, n in ipairs(vivas) do
        self:economia(n)
        -- Las decisiones del presidente NPC; la nación de un jugador decide él.
        if not n.jugador then
            self:atenderHambre(n)
            self:planearMejoras(n)
            self:planearProduccion(n)
            self:protegerCiudades(n)
            self:protegerBases(n)
            self:expansion(n, azar, k)
            self:planearRecoleccion(n)
            self:defenderLoSuyo(n)
        end
        n.cansancio = n.cansancio * 0.995
    end
    self:obras()
    -- Diplomacia solo entre vecinas vivas (en orden de id, como antes entre todas).
    local viva = {}
    for _, n in ipairs(vivas) do
        viva[n.id] = true
    end
    for _, a in ipairs(vivas) do
        for _, bid in ipairs(self:vecinas(a.id)) do
            if viva[bid] then
                self:diplomacia(a, e.naciones[bid], azar)
            end
        end
    end
    for _, g in ipairs(lista(e.guerras)) do
        if e.guerras[claveGuerra(g.atacante, g.defensor)] then
            self:guerra(g, azar)
        end
    end
    self:llegadasDelDia()
    self.activos = nil
end

--- Lo que pasa al acabar un día, tras su último paso de marcha: un día de
-- cada batalla, la recolección, las banderas, la recuperación y los abastos.
-- Con su propio azar (otra sal que `empezarDia`), para que guardar a mitad de
-- día no cambie nada.
function Simulacion:terminarDia()
    local e = self.estado
    local azar = Ruido.azar(Ruido.hash(e.semilla, e.dia, 92))
    self:resolverBatallas(azar)
    self:asaltarTrasChoque()
    self:recolectarDia()
    self:diaAviones()
    -- Banderas guardadas que ya están normales o que ya no son de borde, y su guarnición.
    self:revisarBanderas()
    self:recuperar()
    -- Munición al final del día: los convoyes salen ahora.
    for _, n in ipairs(self:vivas()) do
        if not n.jugador then
            self:planearAbastos(n)
        end
    end
    self:avisarMunicion()
    self:liberarLideres()
    self:olvidarInformes()
    self:llegadaExploradores()
    self.activos = nil
end

--- Un paso de marcha (y, en el primero del día, `empezarDia`; tras el
-- último, `terminarDia`). Devuelve true si con él acabó un día.
function Simulacion:avanzarPaso()
    local e = self.estado
    if e.paso == 0 then
        self:empezarDia()
    end
    self:moverPaso()
    e.paso = e.paso + 1
    if e.paso >= Simulacion.pasosDia then
        self:terminarDia()
        e.paso = 0
        return true
    end
    return false
end

--- Avanza hasta acabar el día en curso (un día entero si no había empezado).
function Simulacion:avanzarDia()
    while not self:avanzarPaso() do
    end
end

-- Guardar y cargar (mundo/simulacion/guardado.lua) -------------------------------------------
require('mundo.simulacion.guardado').instalar(Simulacion)
require('mundo.simulacion.recoleccion').instalar(Simulacion)
-- Aviones de transporte (mundo/simulacion/aviones.lua) -----------------------------------------
require('mundo.simulacion.aviones').instalar(Simulacion)

--- Avanza el tiempo real: `velocidad` días por segundo, en pasos de marcha
-- (`pasosDia` por día). `self.reloj` es la parte del paso siguiente que ya
-- pasó (no es estado). Los eventos de comandos dados entre dos pasos se
-- conservan hasta que el mundo los dibuje. Devuelve los días que acabaron.
function Simulacion:actualizar(dt, velocidad)
    self.reloj = (self.reloj or 0) + dt * velocidad * Simulacion.pasosDia
    local dias = 0
    local eventos = self.eventos or {}
    while self.reloj >= 1 do
        self.reloj = self.reloj - 1
        self.eventos = {}
        if self:avanzarPaso() then
            dias = dias + 1
        end
        for _, ev in ipairs(self.eventos) do
            eventos[#eventos + 1] = ev
        end
    end
    self.eventos = eventos
    return dias
end

--- Parte del paso de marcha en curso que ya pasó (0 a 1): con ella la vista
-- dibuja a los grupos entre el paso anterior y el actual (`posicionGrupo`).
function Simulacion:fraccionPaso()
    return math.min(1, math.max(0, self.reloj or 0))
end

--- Hora del juego en días con decimales (sigue al reloj entre pasos): durante
-- el día `d` va de `d` a `d + 1`, como las marcas de día que se ponen en él.
-- Entre dos días (`e.paso` = 0) ya cuenta el día siguiente, que empieza en el
-- próximo paso.
function Simulacion:ahora()
    local e = self.estado
    local f = self:fraccionPaso()
    if e.paso == 0 then
        return e.dia + 1 + f / Simulacion.pasosDia
    end
    return e.dia + (e.paso + f) / Simulacion.pasosDia
end

return Simulacion
