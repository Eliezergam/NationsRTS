"""restos_campo.py - Restos abandonados para el campo de batalla (el dueño, 19-nov:
«que salgan contenedores en los terrenos, que se sienta un poco vivo»):
contenedor marítimo de 20 pies (cerrado y con una puerta abierta), bidón de
200 l y caja de madera. Geometría y texturas por script.

python3 tools/restos_campo.py

Salida en assets/batalla/restos/: <modelo>.lua (lista plana {x, y, z, nx, ny,
nz, u, v} por vértice, metros, Y arriba, origen en el suelo bajo el centro) y
las texturas metal.png y madera.png (neutras: el color de cada copia lo da su
tono, como la pintura de cada contenedor).

Medidas de un contenedor ISO 668 1CC (20 pies): 6,058 x 2,438 x 2,591 m; la
chapa de los lados es trapezoidal (paso ~278 mm, fondo ~36 mm); 4 barras de
cierre por puerta con sus manillas; postes de esquina y cantoneras (ISO 1161).
Bidón de 200 l: 0,585 m de diámetro, 0,88 m de alto, dos aros de rodadura.
"""
import math
import os
import numpy as np
from PIL import Image

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SALIDA = os.path.join(RAIZ, 'assets', 'batalla', 'restos')


class Malla:
    def __init__(self):
        self.d = []

    def tri(self, a, b, c, ua, ub, uc, n=None):
        a, b, c = np.array(a, float), np.array(b, float), np.array(c, float)
        if n is None:
            n = np.cross(b - a, c - a)
            ln = np.linalg.norm(n)
            n = n / ln if ln > 1e-12 else np.array([0, 1.0, 0])
        for p, uv in ((a, ua), (b, ub), (c, uc)):
            self.d += [p[0], p[1], p[2], n[0], n[1], n[2], uv[0], uv[1]]

    def quad(self, a, b, c, d, uv=None):
        """a-b-c-d en sentido antihorario visto desde fuera."""
        uv = uv or [(0, 1), (1, 1), (1, 0), (0, 0)]
        self.tri(a, b, c, uv[0], uv[1], uv[2])
        self.tri(a, c, d, uv[0], uv[2], uv[3])

    def caja(self, x0, x1, y0, y1, z0, z1, escalaUV=0.5):
        """Caja alineada a los ejes con UV planar por cara (metros / escalaUV)."""
        e = escalaUV
        P = lambda x, y, z: (x, y, z)
        uvx = lambda a, b, c, d: [(a / 6.06, 1 - b / 2.6), (c / 6.06, 1 - b / 2.6), (c / 6.06, 1 - d / 2.6), (a / 6.06, 1 - d / 2.6)]
        # +z
        self.quad(P(x0, y0, z1), P(x1, y0, z1), P(x1, y1, z1), P(x0, y1, z1), uvx(x0 + 3, y0, x1 + 3, y1))
        # -z
        self.quad(P(x1, y0, z0), P(x0, y0, z0), P(x0, y1, z0), P(x1, y1, z0), uvx(x1 + 3, y0, x0 + 3, y1))
        # +x
        self.quad(P(x1, y0, z1), P(x1, y0, z0), P(x1, y1, z0), P(x1, y1, z1), uvx(z1 + 1.2, y0, z0 + 1.2, y1))
        # -x
        self.quad(P(x0, y0, z0), P(x0, y0, z1), P(x0, y1, z1), P(x0, y1, z0), uvx(z0 + 1.2, y0, z1 + 1.2, y1))
        # +y
        self.quad(P(x0, y1, z1), P(x1, y1, z1), P(x1, y1, z0), P(x0, y1, z0), [(0.02, 0.02)] * 4)
        # -y
        self.quad(P(x0, y0, z0), P(x1, y0, z0), P(x1, y0, z1), P(x0, y0, z1), [(0.02, 0.98)] * 4)

    def cilindro(self, cx, cz, y0, y1, r, lados=24, tapas=True, uvAlto=None):
        uvAlto = uvAlto or (y1 - y0)
        for k in range(lados):
            a0, a1 = 2 * math.pi * k / lados, 2 * math.pi * (k + 1) / lados
            p0 = (cx + r * math.cos(a0), cz + r * math.sin(a0))
            p1 = (cx + r * math.cos(a1), cz + r * math.sin(a1))
            n0 = (math.cos(a0), 0, math.sin(a0))
            n1 = (math.cos(a1), 0, math.sin(a1))
            u0, u1 = k / lados, (k + 1) / lados
            A, B = (p0[0], y0, p0[1]), (p1[0], y0, p1[1])
            C, D = (p1[0], y1, p1[1]), (p0[0], y1, p0[1])
            v0, v1 = 1 - y0 / uvAlto, 1 - y1 / uvAlto
            # Normales suaves (sin facetas): una por vértice.
            for (p, n, uv) in ((A, n0, (u0, v0)), (C, n1, (u1, v1)), (B, n1, (u1, v0)),
                               (A, n0, (u0, v0)), (D, n0, (u0, v1)), (C, n1, (u1, v1))):
                self.d += [p[0], p[1], p[2], n[0], n[1], n[2], uv[0], uv[1]]
            if tapas:
                self.tri((cx, y1, cz), D, C, (0.5, 0.05), (0.5, 0.05), (0.5, 0.05), n=np.array([0, 1.0, 0]))

    def mover(self, dx=0, dy=0, dz=0):
        for k in range(0, len(self.d), 8):
            self.d[k] += dx
            self.d[k + 1] += dy
            self.d[k + 2] += dz

    def girarY(self, ang, px=0, pz=0):
        c, s = math.cos(ang), math.sin(ang)
        for k in range(0, len(self.d), 8):
            x, z = self.d[k] - px, self.d[k + 2] - pz
            self.d[k], self.d[k + 2] = px + x * c - z * s, pz + x * s + z * c
            nx, nz = self.d[k + 3], self.d[k + 5]
            self.d[k + 3], self.d[k + 5] = nx * c - nz * s, nx * s + nz * c

    def unir(self, otra):
        self.d += otra.d


# Contenedor ---------------------------------------------------------------------------------
L, W, H = 6.058, 2.438, 2.591
POSTE = 0.16
CARRIL = 0.14
PASO, FONDO = 0.278, 0.036


def perfil(u0, u1):
    """Puntos (u, profundidad) de la chapa trapezoidal entre u0 y u1."""
    pts = []
    u = u0
    tramos = [(0.0, 0.0), (0.07, 0.0), (0.139, FONDO), (0.209, FONDO), (0.278, 0.0)]
    while u < u1 - 1e-6:
        for a, p in tramos:
            if u + a <= u1 + 1e-6 and (not pts or u + a > pts[-1][0] + 1e-6):
                pts.append((u + a, p))
        u += PASO
    if pts[-1][0] < u1 - 1e-6:
        pts.append((u1, 0.0))
    return pts


def paredOndulada(m, largo, alto, eje):
    """Pared ondulada en el plano (u, y), hacia fuera +n. `eje` coloca u, y, profundidad en 3D."""
    pts = perfil(-largo / 2, largo / 2)
    for (u0, p0), (u1, p1) in zip(pts, pts[1:]):
        a, b = eje(u0, CARRIL, p0), eje(u1, CARRIL, p1)
        c, d = eje(u1, alto - CARRIL, p1), eje(u0, alto - CARRIL, p0)
        uv = [((u0 + 3) / 6.06, 1 - CARRIL / 2.6), ((u1 + 3) / 6.06, 1 - CARRIL / 2.6),
              ((u1 + 3) / 6.06, 1 - (alto - CARRIL) / 2.6), ((u0 + 3) / 6.06, 1 - (alto - CARRIL) / 2.6)]
        m.quad(a, b, c, d, uv)


def puerta(m, z0, z1, x, abierta=0.0, bisagra=None):
    """Hoja de puerta en el extremo +x, de z0 a z1, con 2 barras de cierre."""
    p = Malla()
    grosor = 0.05
    p.caja(x - grosor, x, CARRIL, H - CARRIL, z0, z1, 0.5)
    # Nervios horizontales de la hoja.
    for y in (0.6, 1.3, 2.0):
        p.caja(x, x + 0.02, y - 0.04, y + 0.04, z0 + 0.04, z1 - 0.04)
    # Barras de cierre y manillas.
    for f in (0.3, 0.7):
        bz = z0 + (z1 - z0) * f
        p.cilindro(x + 0.045, bz, CARRIL + 0.02, H - CARRIL - 0.02, 0.016, 10, False)
        for y in (0.25, H - 0.25):
            p.caja(x, x + 0.06, y - 0.05, y + 0.05, bz - 0.04, bz + 0.04)
        p.caja(x + 0.03, x + 0.12, 1.05, 1.1, bz - 0.02, bz + 0.25)
    if abierta and bisagra is not None:
        # Gira alrededor de la bisagra (x, z = bisagra); hacia fuera.
        p.girarY(-abierta, x, bisagra)
    m.unir(p)


def contenedor(abierto=False):
    m = Malla()
    x0, x1, z0, z1 = -L / 2, L / 2, -W / 2, W / 2
    # Postes y cantoneras de las 4 esquinas.
    for x in (x0, x1 - POSTE):
        for z in (z0, z1 - POSTE):
            m.caja(x, x + POSTE, 0, H, z, z + POSTE)
            for y in (0, H - 0.118):
                m.caja(x - 0.005, x + POSTE + 0.005, y, y + 0.118, z - 0.005, z + POSTE + 0.005)
    # Carriles de abajo y de arriba (largos y testeros).
    for y in (0, H - CARRIL):
        for z in (z0, z1 - 0.12):
            m.caja(x0 + POSTE, x1 - POSTE, y, y + CARRIL, z, z + 0.12)
        m.caja(x0, x0 + 0.12, y, y + CARRIL, z0 + POSTE, z1 - POSTE)
        m.caja(x1 - 0.12, x1, y, y + CARRIL, z0 + POSTE, z1 - POSTE)
    largo = L - 2 * POSTE
    # Lados ondulados (+z y -z) y testero de atrás ondulado (-x).
    paredOndulada(m, largo, H, lambda u, y, p: (u, y, z1 - 0.05 - p))
    paredOndulada(m, largo, H, lambda u, y, p: (-u, y, z0 + 0.05 + p))
    paredOndulada(m, W - 2 * POSTE, H, lambda u, y, p: (x0 + 0.05 + p, y, u))
    # Techo: chapa algo abombada (dos aguas muy suaves) y por dentro oscuro.
    m.quad((x0 + 0.05, H - 0.04, z1 - 0.05), (x1 - 0.05, H - 0.04, z1 - 0.05), (x1 - 0.05, H - 0.02, 0), (x0 + 0.05, H - 0.02, 0),
           [(0.1, 0.05), (0.9, 0.05), (0.9, 0.06), (0.1, 0.06)])
    m.quad((x0 + 0.05, H - 0.02, 0), (x1 - 0.05, H - 0.02, 0), (x1 - 0.05, H - 0.04, z0 + 0.05), (x0 + 0.05, H - 0.04, z0 + 0.05),
           [(0.1, 0.06), (0.9, 0.06), (0.9, 0.05), (0.1, 0.05)])
    # Puertas en +x: dos hojas; con `abierto`, la derecha girada 110°.
    xp = x1 - 0.02
    puerta(m, z0 + POSTE, 0, xp)
    puerta(m, 0, z1 - POSTE, xp, 1.9 if abierto else 0, z1 - POSTE)
    if abierto:
        # Interior visible: suelo de madera y paredes oscuras (la parte baja del atlas).
        m.quad((x1 - 0.1, CARRIL + 0.01, z1 - 0.06), (x0 + 0.1, CARRIL + 0.01, z1 - 0.06), (x0 + 0.1, CARRIL + 0.01, z0 + 0.06), (x1 - 0.1, CARRIL + 0.01, z0 + 0.06),
               [(0.02, 0.99)] * 4)
        m.quad((x0 + 0.1, CARRIL, z0 + 0.08), (x1 - 0.1, CARRIL, z0 + 0.08), (x1 - 0.1, H - CARRIL, z0 + 0.08), (x0 + 0.1, H - CARRIL, z0 + 0.08), [(0.02, 0.99)] * 4)
        m.quad((x1 - 0.1, CARRIL, z1 - 0.08), (x0 + 0.1, CARRIL, z1 - 0.08), (x0 + 0.1, H - CARRIL, z1 - 0.08), (x1 - 0.1, H - CARRIL, z1 - 0.08), [(0.02, 0.99)] * 4)
        m.quad((x0 + 0.1, H - CARRIL, z1 - 0.06), (x1 - 0.1, H - CARRIL, z1 - 0.06), (x1 - 0.1, H - CARRIL, z0 + 0.06), (x0 + 0.1, H - CARRIL, z0 + 0.06), [(0.02, 0.99)] * 4)
        m.quad((x0 + 0.09, CARRIL, z1 - 0.06), (x0 + 0.09, CARRIL, z0 + 0.06), (x0 + 0.09, H - CARRIL, z0 + 0.06), (x0 + 0.09, H - CARRIL, z1 - 0.06), [(0.02, 0.99)] * 4)
    return m


def bidon():
    m = Malla()
    r, h = 0.2925, 0.88
    m.cilindro(0, 0, 0, h, r, 32, True, uvAlto=2.6)
    # Aros de rodadura y rebordes de arriba y abajo.
    for y in (0.0, h / 3, 2 * h / 3, h - 0.02):
        m.cilindro(0, 0, y, y + 0.025, r + 0.012, 32, False, uvAlto=2.6)
    # Tapón.
    m.cilindro(0.17, 0, h, h + 0.015, 0.03, 12, True, uvAlto=2.6)
    return m


def caja():
    """Caja de madera de tablas (1,2 x 0,8 x 0,8 m) con listones en las esquinas."""
    m = Malla()
    lx, lz, ly = 0.6, 0.4, 0.8
    # Tablas: 4 por cara lateral, con rendija.
    for k in range(4):
        y0, y1 = k * 0.2 + 0.01, (k + 1) * 0.2 - 0.01
        m.caja(-lx, lx, y0, y1, lz - 0.025, lz, 0.5)
        m.caja(-lx, lx, y0, y1, -lz, -lz + 0.025)
        m.caja(lx - 0.025, lx, y0, y1, -lz, lz)
        m.caja(-lx, -lx + 0.025, y0, y1, -lz, lz)
    m.caja(-lx, lx, ly - 0.025, ly, -lz, lz)  # tapa
    # Listones de esquina y diagonales.
    for x in (-lx - 0.02, lx - 0.06):
        for z in (-lz - 0.02, lz - 0.06):
            m.caja(x, x + 0.08, 0, ly, z, z + 0.08)
    return m


def escribirLua(nombre, m):
    with open(os.path.join(SALIDA, nombre + '.lua'), 'w') as f:
        f.write('-- Generado por tools/restos_campo.py.\nreturn {' + ','.join('%.4f' % x for x in m.d) + '}\n')
    print(nombre, len(m.d) // 24, 'triangulos')


def texturaMetal():
    """Chapa pintada neutra (el tono de la copia da el color): mugre abajo,
    chorretones de óxido y bordes gastados; la esquina de abajo, interior oscuro."""
    rng = np.random.default_rng(7)
    N = 512
    y = np.linspace(0, 1, N)[:, None] * np.ones((1, N))
    base = np.full((N, N, 3), 0.86)
    ruido = rng.normal(0, 1, (N // 8, N // 8))
    ruido = np.asarray(Image.fromarray(((ruido - ruido.min()) / np.ptp(ruido) * 255).astype(np.uint8)).resize((N, N), Image.BICUBIC)) / 255
    base *= (0.92 + 0.12 * ruido)[..., None]
    # Mugre de abajo (el suelo salpica): y = 1 es el suelo.
    mugre = np.clip((y - 0.8) / 0.2, 0, 1) ** 1.5
    base = base * (1 - 0.45 * mugre[..., None]) + np.array([0.33, 0.28, 0.2]) * 0.45 * mugre[..., None]
    # Ondas de la chapa también en la textura (paso de 278 mm en 6,06 m de u):
    # los valles más oscuros, para que se lea de lejos y a pleno sol.
    u = np.arange(N)[None, :] / N * 6.06 / 0.278
    fase = u - np.floor(u)
    valle = ((fase > 0.25) & (fase < 0.75)).astype(float)
    borde = np.clip(1 - np.abs(fase - 0.25) * 12, 0, 1) + np.clip(1 - np.abs(fase - 0.75) * 12, 0, 1)
    onda = 1 - 0.16 * valle - 0.12 * borde
    base *= onda[..., None]
    # Chorretones de óxido desde arriba: pocos, finos y cortos.
    for _ in range(9):
        x = rng.integers(0, N)
        ancho = rng.integers(1, 3)
        largo = rng.uniform(0.08, 0.3)
        col = np.clip((largo - y[:, 0]) / largo, 0, 1) * rng.uniform(0.3, 0.6)
        for dx in range(-ancho, ancho + 1):
            xx = (x + dx) % N
            k = col * (1 - abs(dx) / (ancho + 1))
            base[:, xx] = base[:, xx] * (1 - k[:, None]) + np.array([0.3, 0.16, 0.08]) * k[:, None]
    # Interior (u, v cerca de (0, 1)): oscuro.
    base[N - 24:, :24] = [0.18, 0.16, 0.13]
    # Cantos de techo (0.05): chapa gris clara.
    Image.fromarray((np.clip(base, 0, 1) * 255).astype(np.uint8)).save(os.path.join(SALIDA, 'metal.png'))


def texturaMadera():
    rng = np.random.default_rng(3)
    N = 512
    x = np.arange(N)[None, :] * np.ones((N, 1))
    veta = 0.5 + 0.5 * np.sin(x / 7 + rng.normal(0, 1, (N, 1)).cumsum(0) * 0.05)
    base = np.array([0.55, 0.4, 0.25])[None, None] * (0.8 + 0.25 * veta[..., None])
    gris = np.array([0.5, 0.47, 0.42])
    base = base * 0.6 + gris * 0.4  # madera vieja, agrisada
    Image.fromarray((np.clip(base, 0, 1) * 255).astype(np.uint8)).save(os.path.join(SALIDA, 'madera.png'))


if __name__ == '__main__':
    os.makedirs(SALIDA, exist_ok=True)
    escribirLua('contenedor', contenedor(False))
    escribirLua('contenedor_abierto', contenedor(True))
    escribirLua('bidon', bidon())
    escribirLua('caja', caja())
    texturaMetal()
    texturaMadera()
