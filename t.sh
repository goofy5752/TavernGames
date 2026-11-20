#!/usr/bin/env bash
# Test entry: bash t.sh [files or dirs...]   (no args = all tests/**/*_test.lua)
cd "$(dirname "$0")" || exit 2

LUA=""
for cand in "tools/lua/lua5.1.exe" \
            "$LOCALAPPDATA/Programs/LuaJIT/bin/luajit.exe" \
            "/c/Users/$USERNAME/AppData/Local/Programs/LuaJIT/bin/luajit.exe"; do
  if [ -n "$cand" ] && [ -x "$cand" ]; then LUA="$cand"; break; fi
done
if [ -z "$LUA" ]; then
  for cmd in luajit lua5.1 lua; do
    if command -v "$cmd" >/dev/null 2>&1; then LUA="$cmd"; break; fi
  done
fi
if [ -z "$LUA" ]; then echo "t.sh: no Lua interpreter found" >&2; exit 2; fi

dirs=""
for d in engines core locale wow ui; do [ -d "$d" ] && dirs="$dirs $d"; done
if [ -n "$dirs" ]; then
  find $dirs -name '*.lua' | sort > tests/.files.txt
else
  : > tests/.files.txt
fi

files=()
if [ $# -eq 0 ]; then
  while IFS= read -r f; do files+=("$f"); done < <(find tests -name '*_test.lua' | sort)
else
  for a in "$@"; do
    if [ -d "$a" ]; then
      while IFS= read -r f; do files+=("$f"); done < <(find "$a" -name '*_test.lua' | sort)
    else
      files+=("$a")
    fi
  done
fi

exec "$LUA" tests/run.lua "${files[@]}"
