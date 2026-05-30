#!/usr/bin/env python3
"""Syntax-check Lua files (compile-only, like `luac -p`) using lupa's bundled LuaJIT.

Usage:
    python3 docs/plans/_luacheck.py <file.lua> [<file2.lua> ...]

Compiles each file's source WITHOUT executing it, so Eluna globals
(CreateLuaEvent, GetPlayersInWorld, require, ...) are irrelevant — only
syntax is validated. Exit code 0 = all OK, 1 = at least one syntax error.
"""
import sys
from lupa import LuaRuntime

def check(path):
    src = open(path, "r", encoding="utf-8").read()
    lua = LuaRuntime()  # lupa bundles Lua 5.5; `load` compiles without running.
    # A Lua-side checker keeps the (ok, err) return on the Lua side so lupa
    # doesn't try to unpack the function object on success.
    checker = lua.eval(
        "function(src, name)\n"
        "  local loader = loadstring or load\n"
        "  local fn, err = loader(src, name)\n"
        "  if fn == nil then return false, err else return true, nil end\n"
        "end"
    )
    ok, err = checker(src, "@" + path)
    return bool(ok), err

def main(argv):
    if not argv:
        print("usage: _luacheck.py <file.lua> ...", file=sys.stderr)
        return 2
    ok_all = True
    for p in argv:
        ok, err = check(p)
        if ok:
            print(f"OK    {p}")
        else:
            ok_all = False
            print(f"FAIL  {p}\n      {err}")
    return 0 if ok_all else 1

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
