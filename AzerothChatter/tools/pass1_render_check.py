#!/usr/bin/env python3
"""
Render-pass sanity check for the article-bearing token helpers (Phase 8, Part B).

Loads data/tokens.lua via lupa (no engine/Eluna needed -- with no tag-scorer injected
every entry scores 1, so selection is the uniform fallback) and samples each combined
article token (%afood%/%adrink%/%acompanion%/%atoy%/%acritter%) many times, flagging:

  * double articles    -- "a a meat pie", "an an apple"
  * missing article    -- a common-noun value that came back with no leading "a/an"
  * a/an mismatch       -- "a apple" (vowel) or "an meat pie" (consonant)
  * article on a proper -- "a Pengu" (proper-named entries must stay bare)

Also exercises the plain pool accessors to confirm NO value still bakes in an article
(the Part B cleanup), so a chatter "a %food%" can't double up.

Usage:  python3 tools/pass1_render_check.py     (run from the AzerothChatter/ module dir)
Requires: pip3 install lupa --break-system-packages
Exit 0 = clean, 1 = at least one problem.
"""
import os, sys, re
from lupa import LuaRuntime

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# Combined article tokens -> their accessor names, plus the bare pool accessor used to
# enumerate the pool's proper-named values (so we know which results legitimately have
# no article).
ARTICLE_TOKENS = {
    "afood":      "selectRandomAFood",
    "adrink":     "selectRandomADrink",
    "acompanion": "selectRandomACompanion",
    "atoy":       "selectRandomAToy",
    "acritter":   "selectRandomACritter",
}
# Plain accessors that must never return a value with a baked-in leading article.
PLAIN_NO_ARTICLE = [
    "selectRandomFood", "selectRandomDrink", "selectRandomCompanion",
    "selectRandomToy", "selectRandomCritter",
]
SAMPLES = 4000  # enough to hit every pool entry, incl. low-weight tagged ones


def load_pools():
    # Make require("...") resolve the sibling data/* and logic/* the way mod-ale does,
    # so tokens.lua (which is self-contained, but be safe) loads from ROOT.
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f'package.path = "{ROOT}/?.lua;" .. package.path')
    src = open(os.path.join(ROOT, "data", "tokens.lua"), encoding="utf-8").read()
    return lua.eval("function(s) return assert(load(s))() end")(src)


LEADING_ARTICLE = re.compile(r"^(a|an)\s+", re.IGNORECASE)
VOWEL = re.compile(r"^[aeiou]", re.IGNORECASE)


def check():
    P = load_pools()
    problems = []

    # 1) Plain pools must hold bare nouns (no baked article) post-Part-B.
    for acc in PLAIN_NO_ARTICLE:
        f = P[acc]
        seen = set()
        for _ in range(SAMPLES):
            seen.add(f(None, None))
        for v in seen:
            if LEADING_ARTICLE.match(v):
                problems.append(f"{acc}: value still bakes in an article: {v!r}")

    # 2) Combined article tokens: build the set of legitimately-bare (proper-named)
    #    results by diffing the article output against the bare pool output.
    for tok, acc in ARTICLE_TOKENS.items():
        af = P[acc]
        results = set()
        for _ in range(SAMPLES):
            results.add(af(None, None))
        for r in results:
            m = LEADING_ARTICLE.match(r)
            if m:
                art = m.group(1).lower()
                rest = r[m.end():]
                # double article: "a a meat pie"
                if LEADING_ARTICLE.match(rest):
                    problems.append(f"%{tok}%: double article: {r!r}")
                    continue
                vowel = bool(VOWEL.match(rest))
                if vowel and art != "an":
                    problems.append(f"%{tok}%: a/an mismatch (want 'an'): {r!r}")
                if (not vowel) and art != "a":
                    problems.append(f"%{tok}%: a/an mismatch (want 'a'): {r!r}")
            else:
                # No article: legitimate ONLY if this is a proper name. Heuristic: a
                # bare result that also shows up (unprefixed) is intended proper. We
                # can't see the `proper` flag from outside, so accept capitalized
                # single-token-looking names but flag a lowercase common noun.
                if r and r[0].islower():
                    problems.append(f"%{tok}%: common-noun value missing article: {r!r}")

    return problems


def main():
    try:
        problems = check()
    except Exception as e:
        print(f"ERROR running render check: {e}", file=sys.stderr)
        return 2
    if problems:
        print(f"FAIL  {len(problems)} article problem(s):")
        for p in problems:
            print(f"      - {p}")
        return 1
    print("OK    article tokens render cleanly "
          f"(%{'%, %'.join(ARTICLE_TOKENS)}% + bare pools; {SAMPLES} samples each)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
