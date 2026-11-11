#!/usr/bin/env bash
# ClassPages: syntax check, lint and headless tests (CI and Git Bash). Mirrors tools/check.ps1.
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
addon="$root/ClassPages"
failed=0
ran=0

lua=""
for candidate in lua5.1 luajit lua51 lua; do
  if command -v "$candidate" >/dev/null 2>&1; then lua="$candidate"; break; fi
done

if [ -n "$lua" ]; then
  bad=0; total=0
  while IFS= read -r -d '' file; do
    total=$((total + 1))
    if ! "$lua" -e "local f, e = loadfile([[$file]]); if not f then io.stderr:write(e, '\n'); os.exit(1) end"; then
      echo "SYNTAX: $file"; bad=$((bad + 1))
    fi
  done < <(find "$addon" -name '*.lua' -print0)
  echo "syntax ($lua): $total files, $bad errors"
  [ "$bad" -gt 0 ] && failed=1
  ran=$((ran + 1))
else
  echo "no Lua 5.1 interpreter found"
fi

if command -v luacheck >/dev/null 2>&1; then
  luacheck "$addon" --config "$root/.luacheckrc" --no-color || failed=1
  ran=$((ran + 1))
else
  echo "luacheck not found"
fi

if [ -n "$lua" ]; then
  "$lua" "$root/tools/tests/run.lua" "$root" || failed=1
  ran=$((ran + 1))
fi

# whole-addon session simulation
if [ -n "$lua" ]; then
  "$lua" "$root/tools/tests/sim.lua" "$root" || failed=1
  ran=$((ran + 1))
fi

if [ "$ran" -eq 0 ]; then echo "CHECK FAILED: no tool available"; exit 2; fi
if [ "$failed" -ne 0 ]; then echo "CHECK FAILED"; exit 1; fi
echo "CHECK OK ($ran steps)"
