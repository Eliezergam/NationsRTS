--- Nombres inventados para los presidentes y generales de cada nación.
--
-- Solo datos: listas de nombres y apellidos comunes, y las propias de cada orden
-- político (`alba`, `estandarte`, `concordia`), para que cada bloque suene distinto.

local Nombres = {}

Nombres.nombres = {
    'Aldren',
    'Mira',
    'Tovas',
    'Seren',
    'Brisa',
    'Calo',
    'Dara',
    'Ilen',
    'Voro',
    'Nesta',
    'Rufo',
    'Elia',
    'Tamar',
    'Osric',
    'Lune',
    'Varo',
}
Nombres.apellidos = { 'Valcor', 'Duarn', 'Mestre', 'Oriel', 'Casten', 'Brume', 'Selvar', 'Tordo', 'Ivren', 'Lazar' }
-- Nombres de los generales: los de siempre más unos propios de cada orden
-- político, para que cada bloque suene distinto (todos inventados).
Nombres.nombresOrden = {
    alba = { 'Vesk', 'Irna', 'Dobro', 'Mirka', 'Zaven', 'Lasko', 'Tira', 'Branek', 'Olya', 'Radim' },
    estandarte = { 'Aurel', 'Ottavia', 'Leoric', 'Isaude', 'Castor', 'Belin', 'Marcel', 'Evrine', 'Tancred', 'Ysolde' },
    concordia = { 'Anselm', 'Freya', 'Joran', 'Liesl', 'Matteo', 'Neva', 'Piet', 'Solveig', 'Tobin', 'Wenna' },
}
Nombres.apellidosOrden = {
    alba = { 'Kovan', 'Strelko', 'Dubrav', 'Ilnik', 'Morav', 'Zelko', 'Varesh', 'Tomin', 'Bresk', 'Olchan' },
    estandarte = {
        'de Montval',
        'Vauclair',
        'de Rocaberta',
        'Ardencour',
        'Belmonte',
        'de Sauvre',
        'Castelmar',
        'Orvenne',
        'Lisandre',
        'de Valgrís',
    },
    concordia = {
        'Haldor',
        'Brenner',
        'Ostvik',
        'Lindqvar',
        'Morrow',
        'Tessen',
        'Aldring',
        'Veldt',
        'Kappel',
        'Sorell',
    },
}

return Nombres
