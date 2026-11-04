# Open-world generator: builds the countryside around and inside the city ring.
# Inputs: city.h / city.k (10 m ground dump of the city map), city.route
# Outputs (into OUT): height.bin (float32), biome.bin (uint8), world.json, map.png
import numpy as np, json, heapq, sys, math
from scipy import ndimage
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1]
NX, NZ = 460, 480
X0, Z0, CELL = -1800.0, -3400.0, 10.0
rng = np.random.default_rng(2026)

ch = np.fromfile('city.h', np.float32).reshape(NZ, NX)
ck = np.fromfile('city.k', np.uint8).reshape(NZ, NX)
lines = [l.split() for l in open('city.route')]
route = np.array([[float(a[0]), float(a[1]), float(a[2])] for a in lines if a[0] not in ('BASE', 'BANK')])
bases = {a[1]: np.array([float(a[2]), float(a[3]), float(a[4])]) for a in lines if a[0] == 'BASE'}
bank = [np.array([float(a[1]), float(a[2]), float(a[3])]) for a in lines if a[0] == 'BANK'][0]

xs = X0 + np.arange(NX) * CELL
zs = Z0 + np.arange(NZ) * CELL
GX, GZ = np.meshgrid(xs, zs)

def cell(x, z):
    return int(round((z - Z0) / CELL)), int(round((x - X0) / CELL))

# ---------------------------------------------------------------- noise
def perlin(shape_x, shape_z, freq, seed):
    r = np.random.default_rng(seed)
    gx = GX * freq; gz = GZ * freq
    x0 = np.floor(gx).astype(int); z0 = np.floor(gz).astype(int)
    fx = gx - x0; fz = gz - z0
    ang = r.random((512, 512)) * 2 * np.pi
    def grad(ix, iz):
        a = ang[iz % 512, ix % 512]
        return np.cos(a), np.sin(a)
    def dot(ix, iz, dx, dz):
        c, s = grad(ix, iz)
        return c * dx + s * dz
    n00 = dot(x0, z0, fx, fz); n10 = dot(x0 + 1, z0, fx - 1, fz)
    n01 = dot(x0, z0 + 1, fx, fz - 1); n11 = dot(x0 + 1, z0 + 1, fx - 1, fz - 1)
    u = fx * fx * fx * (fx * (fx * 6 - 15) + 10); v = fz * fz * fz * (fz * (fz * 6 - 15) + 10)
    return (n00 * (1 - u) + n10 * u) * (1 - v) + (n01 * (1 - u) + n11 * u) * v

def fbm(freq, octaves, seed, ridged=False):
    s = np.zeros_like(GX); a = 1.0; f = freq; tot = 0
    for o in range(octaves):
        n = perlin(0, 0, f, seed + o)
        if ridged:
            n = 1.0 - np.abs(n) * 1.6
            n = n * n
        s += n * a; tot += a; a *= 0.5; f *= 2.03
    return s / tot

# ---------------------------------------------------------------- masks
city = ch > -999
ocean_boxes = [(-44.1, 1022.7, 1364.0, 1128.7), (-1593.8, 200.8, 732.2, 579.3), (-978.0, 472.1, 432.2, 484.8),
               (-744.8, 710.4, 423.9, 461.5), (-430.8, 875.2, 446.5, 508.0)]
ocean = np.zeros_like(city)
for (ox, oz, sx, sz) in ocean_boxes:
    ocean |= (GX > ox - 40) & (GX < ox + sx + 40) & (GZ > oz - 40) & (GZ < oz + sz + 40)
land = ~ocean & ~((GZ > 950)) & ~((GX < -1450) & (GZ > -250))
# protect bases and bank (terrain must stay below them)
protect = np.zeros_like(city)
for p in list(bases.values()) + [bank]:
    protect |= np.hypot(GX - p[0], GZ - p[2]) < 75
city_like = city | protect
# distance (m) to the city ribbon and its height propagated outward
dist, idx = ndimage.distance_transform_edt(~city_like, return_indices=True)
dist *= CELL
edge_h = np.where(city, ch, np.nan)
for p in list(bases.values()) + [bank]:
    m = protect & ~city & (np.hypot(GX - p[0], GZ - p[2]) < 75)
    edge_h[m] = p[1]
eh = edge_h[idx[0], idx[1]]
eh = np.where(np.isnan(eh), 80.0, eh)
eh = ndimage.gaussian_filter(eh, 6)

def disc(cx, cz, r):
    return np.clip(1.0 - np.hypot(GX - cx, GZ - cz) / r, 0, 1)

def smooth01(t):
    t = np.clip(t, 0, 1); return t * t * (3 - 2 * t)

# ---------------------------------------------------------------- natural terrain
hills = fbm(1 / 600, 5, 11) * 28
ridge = fbm(1 / 900, 6, 31, ridged=True)
detail = fbm(1 / 90, 3, 71) * 3
far = smooth01((dist - 40) / 320)              # 0 near the city, 1 far away
base = eh - 1.0 + (hills + detail) * far

# Mount Sierra inside the ring
SUMMIT = (60.0, -330.0)
m = smooth01(disc(*SUMMIT, 650)) ** 1.15
base += m * (390 + ridge * 90) * smooth01((dist - 60) / 250)
# North Ridge: high snowy mountains to the north
north = smooth01((-GZ - 2100) / 900) * (0.5 + 0.5 * ridge)
base += north * 650 * far
# rolling hills west
west = smooth01((-GX - 1300) / 400) * smooth01((-GZ - 250) / 300)
base += west * 160 * ridge * far
# Redstone desert: east, flat with dunes and a couple of mesas
desert = smooth01((GX - 1250) / 300) * smooth01((GZ + 400) / -1.0 + 1) * (GZ > -2600)
desert = smooth01((GX - 1250) / 300) * (1 - smooth01((-GZ - 2500) / 400)) * (1 - smooth01((GZ + 300) / 300))
dunes = fbm(1 / 140, 3, 91) * 6
plateau = 92.0
base = base * (1 - desert * 0.85) + (plateau + dunes) * desert * 0.85
for (mx, mz, mr, mh) in [(1950, -900, 140, 55), (2350, -1650, 190, 75), (1650, -2100, 120, 45)]:
    t = np.hypot(GX - mx, GZ - mz) / mr
    base += desert * mh * smooth01((1.15 - t) / 0.25)
# Blue Lake basin (interior east)
LAKE = (520.0, 140.0, 165.0)
lake_level = 41.0
ld = np.hypot(GX - LAKE[0], GZ - LAKE[1]) / LAKE[2]
basin = smooth01((1.25 - ld) / 0.5)
base = base * (1 - basin) + (lake_level - 7 + ld * 9) * basin
# Pine Valley: a flat valley floor for the village
VILLAGE = (-470.0, -120.0)
vf = smooth01(disc(*VILLAGE, 230) * 1.6)
base = base * (1 - vf) + (np.median(eh[np.hypot(GX - VILLAGE[0], GZ - VILLAGE[1]) < 200]) + 6) * vf
# under the city itself keep terrain hidden below the map
h = np.where(city_like, np.minimum(base, np.where(city, ch, eh) - 4.0), base)
h = np.where(land, h, 20.0)

# ---------------------------------------------------------------- roads (A* on the slope)
WALK = land & ~city_like
LAB, _ = ndimage.label(WALK, structure=np.ones((3, 3)))
def astar(a, b, slope_k, max_grade, allow_near=None):
    (az, ax), (bz, bx) = a, b
    gy = h
    INF = 1e18
    best = np.full(h.shape, INF); prev = -np.ones(h.shape + (2,), int)
    best[az, ax] = 0
    pq = [(0.0, az, ax)]
    nb = [(-1, 0, 1), (1, 0, 1), (0, -1, 1), (0, 1, 1), (-1, -1, 1.414), (1, 1, 1.414), (-1, 1, 1.414), (1, -1, 1.414),
          (-2, -1, 2.236), (-2, 1, 2.236), (2, -1, 2.236), (2, 1, 2.236), (-1, -2, 2.236), (1, -2, 2.236), (-1, 2, 2.236), (1, 2, 2.236)]
    while pq:
        f, z, x = heapq.heappop(pq)
        if (z, x) == (bz, bx):
            break
        g = best[z, x]
        if f - math.hypot(z - bz, x - bx) * CELL > g + 1e-6:
            continue
        for dz, dx, l in nb:
            nz, nx = z + dz, x + dx
            if nz < 1 or nx < 1 or nz >= NZ - 1 or nx >= NX - 1:
                continue
            ok = WALK[nz, nx] or (allow_near is not None and allow_near[nz, nx])
            if not ok:
                continue
            run = l * CELL
            grade = abs(gy[nz, nx] - gy[z, x]) / run
            if grade > max_grade * 4.0:
                continue
            c = run * (1 + slope_k * max(0.0, grade - max_grade * 0.5) * 30 + (6 if grade > max_grade else 0) + (25 if grade > max_grade * 2 else 0))
            ng = g + c
            if ng < best[nz, nx]:
                best[nz, nx] = ng; prev[nz, nx] = (z, x)
                heapq.heappush(pq, (ng + math.hypot(nz - bz, nx - bx) * CELL, nz, nx))
    path = [(bz, bx)]
    while path[-1] != (az, ax):
        p = tuple(prev[path[-1]])
        if p[0] < 0:
            raise RuntimeError('no path %s -> %s' % (a, b))
        path.append(p)
    return path[::-1]

def resample(pts, step=8.0):
    pts = np.array(pts, float)
    seg = np.hypot(np.diff(pts[:, 0]), np.diff(pts[:, 1])); cum = np.concatenate([[0], np.cumsum(seg)])
    n = max(2, int(cum[-1] / step) + 1)
    t = np.linspace(0, cum[-1], n)
    return np.stack([np.interp(t, cum, pts[:, 0]), np.interp(t, cum, pts[:, 1])], 1)

def chaikin(pts, it=3):
    for _ in range(it):
        q = [pts[0]]
        for i in range(len(pts) - 1):
            a, b = pts[i], pts[i + 1]
            q.append(a * 0.75 + b * 0.25); q.append(a * 0.25 + b * 0.75)
        q.append(pts[-1]); pts = np.array(q)
    return pts

def bilinear(x, z):
    fx = (x - X0) / CELL; fz = (z - Z0) / CELL
    ix = np.clip(np.floor(fx).astype(int), 0, NX - 2); iz = np.clip(np.floor(fz).astype(int), 0, NZ - 2)
    tx = fx - ix; tz = fz - iz
    return (h[iz, ix] * (1 - tx) * (1 - tz) + h[iz, ix + 1] * tx * (1 - tz) + h[iz + 1, ix] * (1 - tx) * tz + h[iz + 1, ix + 1] * tx * tz)

def route_pt(i, inward):
    # a point just off the route edge, toward the interior/outside, plus the route point itself
    p = route[i]; t = route[min(i + 1, len(route) - 1)] - route[max(i - 1, 0)]
    t = np.array([t[0], t[2]]); t /= np.linalg.norm(t)
    n = np.array([t[1], -t[0]]) * inward
    return p, n

roads = []
def add_road(name, kind, width, waypoints, smooth_win, max_grade, start=None, end=None):
    # waypoints: list of (x,z) or ('route', idx, side)
    pts_xz = []
    start_h = None; end_h = None
    wps = []
    for wi, w in enumerate(waypoints):
        if w[0] == 'route':
            nbr = waypoints[wi + 1] if wi + 1 < len(waypoints) else waypoints[wi - 1]
            nbr = np.array(nbr, float)
            best = None
            for side in (1, -1):
                p, n = route_pt(w[1], side)
                d = 6.0
                q = None
                while d < 400:
                    qq = np.array([p[0], p[2]]) + n * d
                    z, x = cell(*qq)
                    nz_, nx_ = cell(*nbr)
                    if 0 <= z < NZ and 0 <= x < NX and WALK[z, x] and LAB[z, x] == LAB[nz_, nx_]:
                        q = qq
                        break
                    d += 5
                if q is None:
                    continue
                score = d * 3 + np.linalg.norm(q - nbr)
                if best is None or score < best[0]:
                    best = (score, p, q)
            _, p, q = best
            wps.append(('r', np.array([p[0], p[2]]), q, p[1], w[1]))
        else:
            wps.append(('p', np.array(w, float)))
    allow = np.zeros_like(city)
    full = []
    for i in range(len(wps) - 1):
        a = wps[i][2] if wps[i][0] == 'r' else wps[i][1]
        b = wps[i + 1][2] if wps[i + 1][0] == 'r' else wps[i + 1][1]
        path = astar(cell(*a), cell(*b), 1.0, max_grade)
        seg = [(X0 + x * CELL, Z0 + z * CELL) for z, x in path]
        if full:
            seg = seg[1:]
        full += seg
        print('   seg', i, len(seg) * 10, 'm  straight', int(np.linalg.norm(np.array(b) - np.array(a))))
    if wps[0][0] == 'r':
        full = [tuple(wps[0][1])] + full
    if wps[-1][0] == 'r':
        full = full + [tuple(wps[-1][1])]
    xz = chaikin(resample(full, 18.0), 4)
    xz = resample(xz, 8.0)
    y = bilinear(xz[:, 0], xz[:, 1])
    # endpoints attach to the city road height
    if wps[0][0] == 'r':
        y[0] = wps[0][3]
    if wps[-1][0] == 'r':
        y[-1] = wps[-1][3]
    if smooth_win > 1:
        k = np.ones(smooth_win) / smooth_win
        pad = np.concatenate([np.full(smooth_win, y[0]), y, np.full(smooth_win, y[-1])])
        ys = np.convolve(pad, k, 'same')[smooth_win:-smooth_win]
        ys[0] = y[0]; ys[-1] = y[-1]
        y = ys
    # limit grade
    for _ in range(40):
        g = np.diff(y) / 8.0
        bad = np.abs(g) > max_grade
        if not bad.any():
            break
        y[1:-1] = np.where(np.convolve(bad.astype(float), [1, 1], 'valid') > 0, (y[:-2] + y[2:]) / 2, y[1:-1])
    terr = bilinear(xz[:, 0], xz[:, 1])
    bridge = (y - terr > 5.0)
    roads.append({'name': name, 'kind': kind, 'width': width, 'xz': xz, 'y': y, 'bridge': bridge,
                  'start_route': int(wps[0][4]) if wps[0][0] == 'r' else -1,
                  'end_route': int(wps[-1][4]) if wps[-1][0] == 'r' else -1})
    print('road', name, 'pts', len(xz), 'len %.0f m' % (len(xz) * 8), 'bridge pts', int(bridge.sum()))
    return roads[-1]

# road network
valley = add_road('VALLEY ROAD', 'road', 9.0, [('route', 786, 1), VILLAGE, (-200, 70), (230, 90), (LAKE[0] - 30, LAKE[1] - LAKE[2] - 40), (800, 180), ('route', 306, -1)], 3, 0.09)
pass_ = add_road('SIERRA PASS', 'road', 8.0, [(-200, 70), (-60, -120), SUMMIT], 1, 0.12)
timber = add_road('TIMBER TRAIL', 'dirt', 6.5, [('route', 559, -1), (-260, -760), (-140, -420)], 3, 0.13)
hw = add_road('HIGHWAY 7', 'highway', 13.0, [('route', 318, 1), (1600, -150), (1980, -1150), (2050, -1900)], 25, 0.06)
ridge_rd = add_road('NORTH RIDGE ROAD', 'road', 8.5, [(2050, -1900), (1100, -1900), (100, -1780), ('route', 600, 1)], 7, 0.1)
ranch_rd = add_road('RANCH ROAD', 'dirt', 6.0, [(1980, -1150), (1720, -1380)], 3, 0.12)

# ---------------------------------------------------------------- flatten terrain along roads
hf = h.copy()
for rd in roads:
    xz, y, w = rd['xz'], rd['y'], rd['width']
    half = w * 0.5 + 1.5; shoulder = 14.0 if rd['kind'] != 'highway' else 22.0
    for i in range(len(xz)):
        if rd['bridge'][i]:
            continue
        x, z = xz[i]
        r = half + shoulder
        z0i, x0i = cell(x - r, z - r); z1i, x1i = cell(x + r, z + r)
        z0i = max(z0i, 0); x0i = max(x0i, 0); z1i = min(z1i, NZ - 1); x1i = min(x1i, NX - 1)
        sx = GX[z0i:z1i + 1, x0i:x1i + 1]; sz = GZ[z0i:z1i + 1, x0i:x1i + 1]
        d = np.hypot(sx - x, sz - z)
        t = smooth01((d - half) / shoulder)
        target = y[i] - 0.45
        blk = hf[z0i:z1i + 1, x0i:x1i + 1]
        newv = target * (1 - t) + blk * t
        keep_city = city_like[z0i:z1i + 1, x0i:x1i + 1]
        hf[z0i:z1i + 1, x0i:x1i + 1] = np.where(keep_city, blk, np.where(d < half + shoulder, newv, blk))
h = hf

# ---------------------------------------------------------------- biomes
gy_, gx_ = np.gradient(h, CELL)
slope = np.hypot(gx_, gy_)
biome = np.zeros(h.shape, np.uint8)
biome[land] = 1                                         # grass
forest_n = fbm(1 / 350, 3, 123)
forest = land & (forest_n > -0.05) & (h < 330) & (slope < 0.7) & (desert < 0.3)
forest |= land & (np.hypot(GX + 260, GZ + 760) < 330) & (slope < 0.8)
biome[forest] = 2                                       # forest
biome[land & (slope > 0.75)] = 3                         # rock
biome[land & (h > 360) & (slope > 0.45)] = 3
biome[land & (h > 540)] = 4                              # snow
biome[land & (desert > 0.5)] = 5                         # desert
biome[land & (ld < 1.12) & (ld > 0.85)] = 6              # lake shore
biome[land & (ld <= 0.85)] = 7                           # lake bed
biome[city_like] = 0

# ---------------------------------------------------------------- places, zones, village
def nearest_road_dist(x, z):
    best = 1e9
    for rd in roads:
        d = np.hypot(rd['xz'][:, 0] - x, rd['xz'][:, 1] - z).min()
        best = min(best, d)
    return best

houses = []
tries = 0
while len(houses) < 16 and tries < 3000:
    tries += 1
    ang = rng.random() * 2 * np.pi; rr = 25 + rng.random() * 150
    x = VILLAGE[0] + np.cos(ang) * rr; z = VILLAGE[1] + np.sin(ang) * rr
    dr = nearest_road_dist(x, z)
    if dr < 13 or dr > 40:
        continue
    zc, xc = cell(x, z)
    if slope[zc - 1:zc + 2, xc - 1:xc + 2].max() > 0.25 or city_like[zc, xc]:
        continue
    if any(np.hypot(x - hx, z - hz) < 22 for hx, hz, *_ in houses):
        continue
    # face the closest road point
    best = None
    for rd in roads:
        d = np.hypot(rd['xz'][:, 0] - x, rd['xz'][:, 1] - z); i = int(d.argmin())
        if best is None or d[i] < best[0]:
            best = (d[i], rd['xz'][i])
    yaw = math.atan2(-(best[1][0] - x), -(best[1][1] - z))
    houses.append((float(x), float(z), float(yaw), int(rng.integers(0, 4))))
for (x, z, yaw, v) in houses:
    zc, xc = cell(x, z)
    hh = h[zc - 1:zc + 2, xc - 1:xc + 2].mean()
    h[max(zc - 1, 0):zc + 2, max(xc - 1, 0):xc + 2] = hh
print('houses', len(houses))

# ranch buildings
ranch = []
for i in range(5):
    a = i / 5 * 2 * np.pi + 0.4
    x, z = 1700 + np.cos(a) * 45, -1400 + np.sin(a) * 40
    ranch.append((float(x), float(z), float(a + np.pi), int(i % 4)))
    zc, xc = cell(x, z)
    h[zc - 1:zc + 2, xc - 1:xc + 2] = h[zc - 1:zc + 2, xc - 1:xc + 2].mean()

def hat(x, z):
    return float(bilinear(np.array([x]), np.array([z]))[0])

# gas station next to the valley road at the village
gi = int(np.argmin(np.hypot(valley['xz'][:, 0] - (VILLAGE[0] + 120), valley['xz'][:, 1] - VILLAGE[1])))
gp = valley['xz'][gi]; gt = valley['xz'][min(gi + 1, len(valley['xz']) - 1)] - valley['xz'][max(gi - 1, 0)]
gn = np.array([gt[1], -gt[0]]) / np.linalg.norm(gt)
gas = gp + gn * 22
zc, xc = cell(*gas); h[zc - 2:zc + 3, xc - 2:xc + 3] = valley['y'][gi] - 0.3

places = [
    {'name': 'PINE VALLEY', 'kind': 'zone', 'x': VILLAGE[0], 'z': VILLAGE[1], 'r': 260},
    {'name': 'MOUNT SIERRA', 'kind': 'zone', 'x': SUMMIT[0], 'z': SUMMIT[1], 'r': 420},
    {'name': 'BLUE LAKE', 'kind': 'zone', 'x': LAKE[0], 'z': LAKE[1], 'r': 260},
    {'name': 'TIMBER FOREST', 'kind': 'zone', 'x': -260, 'z': -780, 'r': 300},
    {'name': 'REDSTONE DESERT', 'kind': 'zone', 'x': 1950, 'z': -1300, 'r': 900},
    {'name': 'NORTH RIDGE', 'kind': 'zone', 'x': 700, 'z': -2500, 'r': 1100},
    {'name': 'RADIO TOWER', 'kind': 'tower', 'x': SUMMIT[0], 'z': SUMMIT[1], 'y': hat(*SUMMIT)},
    {'name': 'SANDY RANCH', 'kind': 'ranch', 'x': 1700, 'z': -1400, 'y': hat(1700, -1400)},
    {'name': 'PINE VALLEY GAS', 'kind': 'gas', 'x': float(gas[0]), 'z': float(gas[1]), 'y': float(valley['y'][gi]), 'yaw': float(math.atan2(-gn[0], -gn[1]))},
    {'name': 'BLUE LAKE', 'kind': 'lake', 'x': LAKE[0], 'z': LAKE[1], 'r': LAKE[2] * 1.05, 'y': lake_level},
    {'name': 'RIDGE LOOKOUT', 'kind': 'lookout', 'x': float(ridge_rd['xz'][len(ridge_rd['xz']) // 2][0]), 'z': float(ridge_rd['xz'][len(ridge_rd['xz']) // 2][1]), 'y': float(ridge_rd['y'][len(ridge_rd['y']) // 2])},
]
city_zones = [[0, 120, 'VENICE BEACH'], [120, 250, 'DOWNTOWN'], [250, 360, 'HARBOR'], [360, 480, 'ARTS DISTRICT'],
              [480, 620, 'HOLLYWOOD'], [620, 760, 'GRIFFITH HILLS'], [760, 850, 'SANTA MONICA']]

# ---------------------------------------------------------------- export
h.astype(np.float32).tofile(OUT + '/height.bin')
biome.tofile(OUT + '/biome.bin')
js = {
    'x0': X0, 'z0': Z0, 'cell': CELL, 'nx': NX, 'nz': NZ, 'lake_level': lake_level,
    'roads': [{'name': r['name'], 'kind': r['kind'], 'width': r['width'],
               'pts': [[round(float(a), 2), round(float(c), 2), round(float(b), 2)] for (a, b), c in zip(r['xz'], r['y'])],
               'bridge': [int(v) for v in r['bridge']], 'start_route': r['start_route'], 'end_route': r['end_route']} for r in roads],
    'houses': houses, 'ranch': ranch, 'places': places, 'city_zones': city_zones,
}
json.dump(js, open(OUT + '/world.json', 'w'))

# ---------------------------------------------------------------- map picture (2 px per cell)
col = np.zeros(h.shape + (3,), float)
pal = {0: (0, 0, 0), 1: (96, 128, 72), 2: (52, 88, 50), 3: (120, 112, 104), 4: (230, 232, 236), 5: (196, 160, 112), 6: (170, 160, 120), 7: (60, 110, 150)}
for k_, c in pal.items():
    col[biome == k_] = c
shade = np.clip(1.0 + (gx_ * -0.6 + gy_ * -0.6) * 1.2, 0.55, 1.35)
col *= shade[..., None]
col[ck == 2] = (88, 92, 98); col[ck == 1] = (150, 150, 155)
col[~land & ~city] = (22, 52, 92)
col[ocean & ~city] = (22, 52, 92)
col[(ld <= 1.0) & land] = (40, 96, 150)
img = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8)).resize((NX * 4, NZ * 4), Image.BICUBIC)
img.save(OUT + '/map.png')
print('done', float(h[land].min()), float(h[land].max()))
