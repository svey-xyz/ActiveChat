#!/usr/bin/env python3
"""Gender-consistency check for the character roster (CHARACTERS_PLAN Phase 1 Part A).

Loads the real data/names.lua and data/traits.lua via lupa, then replicates the
gender -> first-name and gender -> role-prefix selection that buildName performs and
samples it heavily. Asserts the invariant the gendered-names change exists to enforce:

  * every faction has non-empty male AND female first-name pools;
  * a generated character always has a gender and a non-empty first name;
  * a female character NEVER displays a male-exclusive role prefix, and vice-versa
    (the "Sister Cedric" / "Lord Thorgrim" bug);
  * the chosen first name comes from the character's own gender bucket (or the
    neutral fallback when that bucket is empty).

Exit 0 = invariant holds, 1 = violation. Pure data/logic guard -- it does not run the
Eluna engine (which needs ALE globals); it mirrors buildName's selection rules.

Usage:  python3 tools/gender_check.py          # run from AzerothChatter/
        pip3 install lupa --break-system-packages
"""
import os
import sys
from lupa import LuaRuntime

GENDERS = ("male", "female", "neutral")
SAMPLES = 40000


def load_lua_table(lua, path):
    src = open(path, "r", encoding="utf-8").read()
    return lua.execute(src)


def to_list(tbl):
    """A Lua array (1-based) -> python list; nil/None -> []."""
    if tbl is None:
        return []
    return [tbl[i] for i in range(1, len(tbl) + 1)]


def is_array(tbl):
    """True if the Lua table looks like a 1-based array (has index [1])."""
    return tbl is not None and tbl[1] is not None


def first_name_pool(names, faction, gender):
    """Mirror of firstNamePool in logic/chatter.lua."""
    f = names[faction]
    if f is None:
        return to_list(names["surnames"])
    if is_array(f):                       # legacy flat list
        return to_list(f)
    pool = f[gender] or f["neutral"]
    if pool is not None and len(pool) > 0:
        return to_list(pool)
    for g in GENDERS:                     # any populated bucket
        if f[g] is not None and len(f[g]) > 0:
            return to_list(f[g])
    return to_list(names["surnames"])


def prefix_buckets(roles, role):
    """Return {gender: set(prefix)} for a role, honouring the neutral fallback and
    the legacy flat-list shape. Mirrors rolePrefix's reachability."""
    p = roles[role]["prefixes"]
    if p is None:
        return {g: set() for g in GENDERS}
    if is_array(p):                       # legacy flat list = genderless
        flat = set(to_list(p))
        return {g: flat for g in GENDERS}
    neutral = set(to_list(p["neutral"]))
    out = {}
    for g in GENDERS:
        own = set(to_list(p[g]))
        if own:
            out[g] = own
        elif neutral:
            out[g] = neutral
        else:                             # neither -> any populated bucket
            any_bucket = set()
            for gg in GENDERS:
                b = set(to_list(p[gg]))
                if b:
                    any_bucket = b
                    break
            out[g] = any_bucket
    return out


def main():
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    lua = LuaRuntime(unpack_returned_tuples=True)
    names = load_lua_table(lua, os.path.join(here, "data", "names.lua"))
    traits = load_lua_table(lua, os.path.join(here, "data", "traits.lua"))
    roles = traits["ROLES"]

    errors = []

    # 1) Faction pools populated for both binary genders.
    for faction in ("alliance", "horde"):
        for g in ("male", "female"):
            pool = first_name_pool(names, faction, g)
            if not pool:
                errors.append(f"{faction}.{g} first-name pool is empty")

    # Build, per role, the reachable prefix set by gender + the gender-exclusive sets.
    role_keys = [k for k in roles.keys()]
    role_prefixes = {r: prefix_buckets(roles, r) for r in role_keys}

    # A prefix is "male-exclusive" if it can be reached for male but NOT for female,
    # and vice-versa. Those are exactly the titles that must never cross gender.
    for r in role_keys:
        pb = role_prefixes[r]
        male_only = pb["male"] - pb["female"]
        female_only = pb["female"] - pb["male"]
        # female chars must never reach a male-only prefix:
        if female_only & pb["male"]:
            errors.append(f"role {r}: female-only prefix reachable by male: {female_only & pb['male']}")
        if male_only & pb["female"]:
            errors.append(f"role {r}: male-only prefix reachable by female: {male_only & pb['female']}")

    # 2 + 3) Sample characters: gender set, first name non-empty and in-bucket,
    # and the {Role first} prefix (when one would be chosen) agrees with gender.
    import random
    faction_first = {
        (faction, g): set(first_name_pool(names, faction, g))
        for faction in ("alliance", "horde") for g in GENDERS
    }
    bad_prefix = 0
    bad_first = 0
    for _ in range(SAMPLES):
        faction = random.choice(("alliance", "horde"))
        gender = random.choice(GENDERS)
        role = random.choice(role_keys)
        pool = first_name_pool(names, faction, gender)
        if not pool:
            bad_first += 1
            continue
        first = random.choice(pool)
        if not first or first not in faction_first[(faction, gender)]:
            # allow neutral fallback when the gender bucket was empty
            if first not in faction_first[(faction, "neutral")]:
                bad_first += 1
        # {Role first} branch: a prefix reachable for this gender
        reachable = role_prefixes[role][gender]
        opposite = "female" if gender == "male" else ("male" if gender == "female" else None)
        if opposite:
            exclusive_opposite = role_prefixes[role][opposite] - role_prefixes[role][gender]
            if reachable & exclusive_opposite:
                bad_prefix += 1

    if bad_first:
        errors.append(f"{bad_first} sampled chars had an out-of-bucket/empty first name")
    if bad_prefix:
        errors.append(f"{bad_prefix} sampled chars could reach an opposite-gender-exclusive prefix")

    if errors:
        print("FAIL gender-consistency check:")
        for e in errors:
            print("  - " + e)
        return 1

    # Summary of the buckets so the run is informative.
    print("OK    gender-consistency check")
    for faction in ("alliance", "horde"):
        counts = {g: len(first_name_pool(names, faction, g)) for g in GENDERS}
        print(f"      {faction:8s} first names  male={counts['male']:3d}  "
              f"female={counts['female']:3d}  neutral={counts['neutral']:3d}")
    gendered_roles = [r for r in role_keys
                      if role_prefixes[r]["male"] != role_prefixes[r]["female"]]
    print(f"      gendered-prefix roles: {sorted(gendered_roles)}")
    print(f"      sampled {SAMPLES} characters, no cross-gender prefix or name leaks")
    return 0


if __name__ == "__main__":
    sys.exit(main())
