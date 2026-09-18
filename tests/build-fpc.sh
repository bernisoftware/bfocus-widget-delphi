#!/usr/bin/env sh
# Compila os testes do núcleo com Free Pascal (Linux/macOS) e, opcionalmente, roda.
#   sh tests/build-fpc.sh [saida] [--run]
# Saída padrão: tests/out/. -vw mostra os avisos; -Sew os transforma em erro? Não: avisos
# são revisados à mão (FPC avisa sobre construções válidas no Delphi 7).
set -e
here=$(cd "$(dirname "$0")" && pwd)
out=${1:-"$here/out"}
mkdir -p "$out"
fpc -Mdelphi -vw -gl \
  -Fu"$here/../source/core" -Fi"$here/../source/core" -Fu"$here" \
  -FU"$out" -FE"$out" \
  "$here/BFocusTests.dpr"
cp "$here/scenarios.json" "$out/scenarios.json"
if [ "$2" = "--run" ]; then
  node "$here/run-tests.mjs" "$out/BFocusTests"
fi
