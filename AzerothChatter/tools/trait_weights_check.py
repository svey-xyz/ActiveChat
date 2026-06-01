#!/usr/bin/env python3
"""Sampling check for the weighted trait picker (data/traits.lua + engine weightedPick).

Loads ROLES / PERSONALITIES (+ the Part B bias tables) from data/traits.lua via lupa,
mirrors the engine's weightedPick and its traitCorrelationStrength scaling in Python,
draws a large sample, and asserts the *ordering* invariants the plan promises:

  - role:        citizen > soldier > noble
  - personality: kindly  > cowardly  (weight-on / correlation enabled)
  - every role and every personality appears at least once
  - flag-off personality draw (uniform) yields a roughly uniform histogram
  - correlation ON, strength=1: craftsmen are gruff more often than the global gruff
    rate; soldiers are brave more often than baseline
  - strength=0 collapses every conditional histogram back to the base-weight
    distribution (correlation modifiers vanish)
  - home city (Part C): P(role=craftsman | Ironforge) > Darnassus & > global;
    P(mood=gruff | Ironforge) > Darnassus & > global; no city zeroes a trait it
    shouldn't (only the intended ones); strength=0 makes city irrelevant to role/mood

Usage:  python3 tools/trait_weights_check.py
        (pip3 install lupa --break-system-packages  if needed)
"""
import os
import random
import sys

from lupa import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
TRAITS = os.path.join(HERE, "..", "data", "traits.lua")
SAMPLES = 100_000


def _to_dict(tbl):
    """Convert a lupa Lua table of {key -> number} into a plain Python dict."""
    if tbl is None:
        return None
    return {k: float(v) for k, v in tbl.items()}


def load_traits():
    """Execute data/traits.lua (pure data, no engine deps) and pull out the maps."""
    src = open(TRAITS, "r", encoding="utf-8").read()
    lua = LuaRuntime(unpack_returned_tuples=True)
    R = lua.execute(src)
    roles = {k: int(v["weight"]) for k, v in R["ROLES"].items()}
    moods = {k: int(v["weight"]) for k, v in R["PERSONALITIES"].items()}
    role_mood_bias = {k: _to_dict(v["moodBias"]) for k, v in R["ROLES"].items()
                      if v["moodBias"] is not None}
    gender_bias = {}
    for g, spec in R["GENDER_BIAS"].items():
        gender_bias[g] = {
            "roles": _to_dict(spec["roles"]),
            "moods": _to_dict(spec["moods"]),
        }
    faction_bias = {}
    for fac, spec in R["FACTION_BIAS"].items():
        faction_bias[fac] = {
            "roles": _to_dict(spec["roles"]),
            "moods": _to_dict(spec["moods"]),
        }
    city_bias = {}
    for city, spec in R["CITY_BIAS"].items():
        city_bias[city] = {
            "roles": _to_dict(spec["roles"]),
            "moods": _to_dict(spec["moods"]),
        }
    cities = [v for _, v in R["allianceCities"].items()] + \
             [v for _, v in R["hordeCities"].items()]
    return roles, moods, role_mood_bias, gender_bias, faction_bias, city_bias, cities


def scale_modifier(m, s):
    """Python mirror of the engine's scaleModifier: eff = 1 + (factor-1)*s."""
    if not m:
        return None
    if s == 1.0:
        return m
    return {k: 1 + (f - 1) * s for k, f in m.items()}


def weighted_pick(keys, base_of, modifiers=None):
    """Python mirror of the engine's weightedPick (logic/chatter.lua)."""
    eff, total = {}, 0.0
    for k in keys:
        w = base_of(k)
        if w is None:
            w = 1.0
        if modifiers:
            for m in modifiers:
                if m and k in m:
                    w *= m[k]
        if w < 0:
            w = 0.0
        eff[k] = w
        total += w
    if total <= 0:
        return random.choice(keys)
    r, acc = random.random() * total, 0.0
    for k in keys:
        acc += eff[k]
        if r <= acc:
            return k
    return keys[-1]


def histogram(keys, picker):
    counts = {k: 0 for k in keys}
    for _ in range(SAMPLES):
        counts[picker()] += 1
    return counts


def conditional_mood_rate(mood_keys, moods, role_mood_bias, role, mood, s):
    """P(mood == `mood` | role) over SAMPLES draws, with strength s."""
    mods = [scale_modifier(role_mood_bias.get(role), s)]
    hits = 0
    for _ in range(SAMPLES):
        if weighted_pick(mood_keys, lambda k: moods[k], mods) == mood:
            hits += 1
    return hits / SAMPLES


def conditional_trait_rate(keys, base, bias_map, target, s):
    """P(trait == `target`) over SAMPLES draws with a single city modifier at strength s."""
    mods = [scale_modifier(bias_map, s)]
    hits = 0
    for _ in range(SAMPLES):
        if weighted_pick(keys, lambda k: base[k], mods) == target:
            hits += 1
    return hits / SAMPLES


def main():
    random.seed(1234)  # deterministic run
    roles, moods, role_mood_bias, gender_bias, faction_bias, city_bias, cities = load_traits()
    role_keys = list(roles.keys())
    mood_keys = list(moods.keys())

    results = []  # (label, passed)

    # Weights must all be > 0 (no globally-impossible trait).
    all_pos = all(w > 0 for w in roles.values()) and all(w > 0 for w in moods.values())
    results.append(("all base weights > 0", all_pos))

    # Bias tables are multipliers only (all > 0) -- no Part B zeros (those are Part C).
    bias_pos = True
    for m in role_mood_bias.values():
        if m:
            bias_pos = bias_pos and all(f > 0 for f in m.values())
    for spec in list(gender_bias.values()) + list(faction_bias.values()):
        for m in (spec.get("roles"), spec.get("moods")):
            if m:
                bias_pos = bias_pos and all(f > 0 for f in m.values())
    results.append(("Part B bias factors all > 0 (no hard exclude)", bias_pos))

    # Role histogram (base weights).
    rh = histogram(role_keys, lambda: weighted_pick(role_keys, lambda k: roles[k]))
    # Personality histogram, correlation ON (weight-driven, no role context).
    mh = histogram(mood_keys, lambda: weighted_pick(mood_keys, lambda k: moods[k]))
    # Personality histogram, correlation OFF (uniform draw).
    mu = histogram(mood_keys, lambda: random.choice(mood_keys))

    results.append(("role: citizen > soldier", rh["citizen"] > rh["soldier"]))
    results.append(("role: soldier > noble", rh["soldier"] > rh["noble"]))
    results.append(("mood: kindly > cowardly", mh["kindly"] > mh["cowardly"]))

    results.append(("every role appears >= 1", all(c >= 1 for c in rh.values())))
    results.append(("every mood appears >= 1", all(c >= 1 for c in mh.values())))

    # Uniform (flag-off) histogram: each bucket within +/-15% of the mean.
    expected = SAMPLES / len(mood_keys)
    uniform_ok = all(abs(c - expected) <= 0.15 * expected for c in mu.values())
    results.append(("flag-off personality ~uniform (+/-15%)", uniform_ok))

    # --- Part B conditional correlations (strength = 1) ---------------------
    global_gruff = mh["gruff"] / SAMPLES
    global_brave = mh["brave"] / SAMPLES
    craftsman_gruff_s1 = conditional_mood_rate(mood_keys, moods, role_mood_bias,
                                               "craftsman", "gruff", 1.0)
    soldier_brave_s1 = conditional_mood_rate(mood_keys, moods, role_mood_bias,
                                             "soldier", "brave", 1.0)
    results.append(("craftsman gruff > global gruff (s=1)",
                    craftsman_gruff_s1 > global_gruff))
    results.append(("soldier brave > global brave (s=1)",
                    soldier_brave_s1 > global_brave))

    # --- strength = 0 collapses conditional histograms to base distribution -
    # With s=0 every modifier scales to 1.0, so a role-conditioned mood draw must match
    # the unconditioned base-weight rate within tolerance.
    craftsman_gruff_s0 = conditional_mood_rate(mood_keys, moods, role_mood_bias,
                                               "craftsman", "gruff", 0.0)
    soldier_brave_s0 = conditional_mood_rate(mood_keys, moods, role_mood_bias,
                                             "soldier", "brave", 0.0)
    collapse_gruff = abs(craftsman_gruff_s0 - global_gruff) <= 0.10 * global_gruff
    collapse_brave = abs(soldier_brave_s0 - global_brave) <= 0.10 * global_brave
    results.append(("s=0 craftsman gruff ~= base gruff (+/-10%)", collapse_gruff))
    results.append(("s=0 soldier brave ~= base brave (+/-10%)", collapse_brave))

    # --- Part C: home-city affinity matrices -------------------------------
    # All eight home cities must carry an entry (a half-filled table reads as a bug).
    results.append(("all 8 home cities present in CITY_BIAS",
                    all(c in city_bias for c in cities) and len(city_bias) == len(cities)))

    # Only the intended zeros exist (per-context exclusions). Anything else must be > 0.
    intended_zeros = {("Thunder Bluff", "roles", "noble")}
    no_stray_zeros = True
    for city, spec in city_bias.items():
        for kind in ("roles", "moods"):
            m = spec.get(kind)
            if not m:
                continue
            for k, f in m.items():
                if f <= 0 and (city, kind, k) not in intended_zeros:
                    no_stray_zeros = False
    results.append(("CITY_BIAS: only intended zeros (no stray hard-excludes)", no_stray_zeros))

    # Role: P(craftsman | Ironforge) > Darnassus & > global base craftsman rate.
    global_craftsman = rh["craftsman"] / SAMPLES
    iron_craft = conditional_trait_rate(role_keys, roles,
                                        city_bias["Ironforge"]["roles"], "craftsman", 1.0)
    darn_craft = conditional_trait_rate(role_keys, roles,
                                        city_bias["Darnassus"]["roles"], "craftsman", 1.0)
    results.append(("craftsman: Ironforge > Darnassus", iron_craft > darn_craft))
    results.append(("craftsman: Ironforge > global", iron_craft > global_craftsman))

    # Mood: P(gruff | Ironforge) > Darnassus & > global base gruff rate.
    iron_gruff = conditional_trait_rate(mood_keys, moods,
                                        city_bias["Ironforge"]["moods"], "gruff", 1.0)
    darn_gruff = conditional_trait_rate(mood_keys, moods,
                                        city_bias["Darnassus"]["moods"], "gruff", 1.0)
    results.append(("gruff: Ironforge > Darnassus", iron_gruff > darn_gruff))
    results.append(("gruff: Ironforge > global", iron_gruff > global_gruff))

    # strength=0 makes home city irrelevant: city-conditioned rates collapse to base.
    iron_craft_s0 = conditional_trait_rate(role_keys, roles,
                                           city_bias["Ironforge"]["roles"], "craftsman", 0.0)
    iron_gruff_s0 = conditional_trait_rate(mood_keys, moods,
                                           city_bias["Ironforge"]["moods"], "gruff", 0.0)
    city_role_collapse = abs(iron_craft_s0 - global_craftsman) <= 0.10 * global_craftsman
    city_mood_collapse = abs(iron_gruff_s0 - global_gruff) <= 0.10 * global_gruff
    results.append(("s=0 Ironforge craftsman ~= base (city irrelevant)", city_role_collapse))
    results.append(("s=0 Ironforge gruff ~= base (city irrelevant)", city_mood_collapse))

    print(f"roles   ({SAMPLES} draws):")
    for k in sorted(rh, key=lambda x: -rh[x]):
        print(f"  {k:<11} base={roles[k]:>2}  {rh[k]:>6}")
    print(f"moods   ({SAMPLES} draws, correlation ON):")
    for k in sorted(mh, key=lambda x: -mh[x]):
        print(f"  {k:<11} base={moods[k]:>2}  {mh[k]:>6}   uniform={mu[k]:>6}")
    print("\nconditional mood rates:")
    print(f"  gruff:  global={global_gruff:.3f}  craftsman(s=1)={craftsman_gruff_s1:.3f}"
          f"  craftsman(s=0)={craftsman_gruff_s0:.3f}")
    print(f"  brave:  global={global_brave:.3f}  soldier(s=1)={soldier_brave_s1:.3f}"
          f"  soldier(s=0)={soldier_brave_s0:.3f}")
    print("\nhome-city affinity rates (s=1):")
    print(f"  craftsman:  global={global_craftsman:.3f}  Ironforge={iron_craft:.3f}"
          f"  Darnassus={darn_craft:.3f}")
    print(f"  gruff:      global={global_gruff:.3f}  Ironforge={iron_gruff:.3f}"
          f"  Darnassus={darn_gruff:.3f}")

    print("\nchecks:")
    ok_all = True
    for label, passed in results:
        ok_all = ok_all and passed
        print(f"  [{'PASS' if passed else 'FAIL'}] {label}")

    print("\n" + ("PASS — all trait-weight invariants hold" if ok_all
                  else "FAIL — see failing checks above"))
    return 0 if ok_all else 1


if __name__ == "__main__":
    sys.exit(main())
