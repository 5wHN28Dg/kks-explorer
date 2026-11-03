"""The first train's weather (docs/plant3d/REALISM.md §5.1, §5.5; milestone WX3): weather.json's kinds, the values
they drive and the seasons of the hot dry climate (SITE.md: long hot dry summers with dust and sandstorms on the
north-westerly wind, short mild winters with a few rain days, thunderstorms in spring and autumn, rare cold nights
and fog). It drives only what the app draws and plays (REALISM.md §5.4); `ambient_t`, `ambient_wb` and the plant's
reactions are WX2's. Diurnal tables over `world_hour`; a sandstorm's visibility under 1 km as WMO defines one."""

# solar (W/m2) on a horizontal surface over the clock hour for a clear desert day, scaled per kind
def solar(peak):
    return [[0, 0], [5.5, 0], [7, round(peak*0.25)], [9, round(peak*0.7)], [12.5, peak], [16, round(peak*0.6)],
            [18, round(peak*0.1)], [19, 0], [24, 0]]
def flat(x): return [[0, x], [24, x]]
K = {
 'clear':        dict(wind=[[0, 2], [6, 2], [14, 5], [19, 3], [24, 2]], rain=flat(0), dust=flat(0.08),
                      visibility=flat(20000), solar=solar(950), lightning=flat(0)),
 'hot':          dict(wind=[[0, 3], [6, 3], [14, 6], [19, 4], [24, 3]], rain=flat(0), dust=flat(0.2),
                      visibility=[[0, 12000], [6, 12000], [15, 8000], [24, 12000]], solar=solar(1000), lightning=flat(0)),
 'dust_haze':    dict(wind=[[0, 6], [6, 6], [14, 10], [19, 8], [24, 6]], rain=flat(0), dust=[[0, 0.8], [14, 1.5], [24, 0.8]],
                      visibility=[[0, 4000], [14, 2500], [24, 4000]], solar=solar(700), lightning=flat(0)),
 'sandstorm':    dict(wind=[[0, 14], [14, 18], [24, 14]], rain=flat(0), dust=[[0, 6], [14, 10], [24, 6]],
                      visibility=[[0, 600], [14, 300], [24, 600]], solar=solar(250), lightning=flat(0)),
 'rain':         dict(wind=flat(5), rain=flat(4), dust=flat(0.02), visibility=flat(5000), solar=solar(250),
                      lightning=flat(0)),
 'thunderstorm': dict(wind=flat(12), rain=flat(15), dust=flat(0.05), visibility=flat(2000), solar=solar(120),
                      lightning=flat(1)),
 'cold_clear':   dict(wind=[[0, 1], [6, 1], [14, 4], [19, 2], [24, 1]], rain=flat(0), dust=flat(0.05),
                      visibility=flat(25000), solar=solar(600), lightning=flat(0)),
 'fog':          dict(wind=flat(1), rain=flat(0), dust=flat(0.02), visibility=[[0, 400], [6, 200], [10, 1500], [12, 4000], [24, 1000]],
                      solar=solar(300), lightning=flat(0)),
}
VALUES = [('wind', 20), ('rain', 8), ('dust', 30), ('visibility', 20), ('solar', 10), ('lightning', 3), ('wet', 25)]
def rows(spec):   # {from: {to: w}}
    return [[a, b, w] for a, d in spec.items() for b, w in d.items()]
S = [
 {'id': 'winter', 'days': [335, 59], 'start': 'cold_clear', 'hourly': rows({
   'clear': {'clear': 94, 'cold_clear': 3, 'rain': 2, 'dust_haze': 1},
   'cold_clear': {'cold_clear': 92, 'clear': 5, 'fog': 2, 'rain': 1},
   'fog': {'fog': 70, 'clear': 30},
   'rain': {'rain': 85, 'clear': 14, 'thunderstorm': 1},
   'thunderstorm': {'thunderstorm': 60, 'rain': 40},
   'hot': {'clear': 1}, 'dust_haze': {'dust_haze': 85, 'clear': 15}, 'sandstorm': {'dust_haze': 1}})},
 {'id': 'spring', 'days': [60, 151], 'start': 'clear', 'hourly': rows({
   'clear': {'clear': 92, 'hot': 3, 'dust_haze': 3, 'rain': 1, 'thunderstorm': 1},
   'hot': {'hot': 92, 'clear': 5, 'dust_haze': 3},
   'dust_haze': {'dust_haze': 85, 'clear': 9, 'sandstorm': 6},
   'sandstorm': {'sandstorm': 80, 'dust_haze': 20},
   'rain': {'rain': 85, 'clear': 13, 'thunderstorm': 2},
   'thunderstorm': {'thunderstorm': 65, 'rain': 35},
   'cold_clear': {'clear': 1}, 'fog': {'clear': 1}})},
 {'id': 'summer', 'days': [152, 273], 'start': 'hot', 'hourly': rows({
   'clear': {'clear': 90, 'hot': 9, 'dust_haze': 1},
   'hot': {'hot': 93, 'clear': 3, 'dust_haze': 4},
   'dust_haze': {'dust_haze': 84, 'hot': 10, 'sandstorm': 6},
   'sandstorm': {'sandstorm': 82, 'dust_haze': 18},
   'rain': {'clear': 1}, 'thunderstorm': {'clear': 1}, 'cold_clear': {'clear': 1}, 'fog': {'clear': 1}})},
 {'id': 'autumn', 'days': [274, 334], 'start': 'clear', 'hourly': rows({
   'clear': {'clear': 93, 'hot': 2, 'dust_haze': 2, 'rain': 2, 'thunderstorm': 1},
   'hot': {'hot': 90, 'clear': 10},
   'dust_haze': {'dust_haze': 85, 'clear': 11, 'sandstorm': 4},
   'sandstorm': {'sandstorm': 80, 'dust_haze': 20},
   'rain': {'rain': 85, 'clear': 14, 'thunderstorm': 1},
   'thunderstorm': {'thunderstorm': 65, 'rain': 35},
   'cold_clear': {'cold_clear': 85, 'clear': 15}, 'fog': {'fog': 70, 'clear': 30}})},
]
WET = {'rain': 1, 'thunderstorm': 1, 'fog': 0.3}
for k in K: K[k]['wet'] = flat(WET.get(k, 0))


# the driven values as plant.json's ext values and every scenario's step 0 values: clear weather before sunrise (the
# values then lag toward the season's kind at the start's hour: at 06:00, the scenarios without `start`, solar rises)
EXT = [v for v, _ in VALUES]
CLEAR_INIT = {'wind': 2, 'rain': 0, 'dust': 0.08, 'visibility': 20000, 'solar': 0, 'lightning': 0, 'wet': 0}
# free play's weather (the user, 2026-11-01): every scenario, seeded by the season of its start day. The crews'
# shifts first; then (the user, 2026-11-03) the five that were format 1, made version 2 for it: each in the season of
# its crews' twin (cold_iron and hot_restart as shift_cold, a summer day; the WTP's three as shift_wtp, a spring
# day). Their clock starts at plant.json's (day 1, 06:00); their world seed is the default, 1, so the twins of one
# season draw the same weather.
SUMMER = {'year_day': 196, 'weather': {'season': 'summer'}}
SPRING = {'year_day': 100, 'weather': {'season': 'spring'}}
FREE_PLAY = {'shift_cold': SUMMER, 'shift_wtp': SPRING,
             'cold_iron': SUMMER, 'hot_restart': SUMMER, 'wtp_cold': SPRING, 'wtp_normal': SPRING,
             'wtp_flood': SPRING}


def weather():
    return {'format': 'walkdown-plant-weather', 'version': 1,
            'values': [{'id': v, 'tau': t} for v, t in VALUES],
            'kinds': [{'id': k, 'targets': {v: K[k][v] for v, _ in VALUES}} for k in K],
            'seasons': S}
