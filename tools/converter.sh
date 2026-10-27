#!/usr/bin/env bash
# Uso: tools/converter.sh <entrada.apk> [pasta_saida] [target_sdk]
# Decodifica com apktool, aplica ajustes (manifest + regras), reconstrói, alinha e assina.
set -euo pipefail

APK="${1:?uso: converter.sh arquivo.apk [saida] [target_sdk]}"
OUT="${2:-saida}"
TARGET_SDK="${3:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$OUT"

BT="${BUILD_TOOLS:-}"
if [ -z "$BT" ] && [ -n "${ANDROID_HOME:-}" ]; then
  BT="$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -n 1)"
fi
[ -x "$BT/zipalign" ] || { echo "ERRO: zipalign não encontrado (BUILD_TOOLS=$BT)"; exit 1; }
APKTOOL=(java -jar "$ROOT/tools/bin/apktool.jar")

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

echo "==> 1/6 Decodificando com apktool"
"${APKTOOL[@]}" d -f -o "$W/dec" "$APK"

echo "==> 2/6 Ajustando o manifest"
python3 "$ROOT/tools/patch_manifest.py" "$W/dec" "$TARGET_SDK"

echo "==> 3/6 Aplicando regras de patches/regras.json"
python3 "$ROOT/tools/aplicar_regras.py" "$W/dec" "$ROOT/patches/regras.json"

echo "==> 4/6 Reconstruindo"
"${APKTOOL[@]}" b -o "$W/novo.apk" "$W/dec"

echo "==> 5/6 Alinhando"
"$BT/zipalign" -p -f 4 "$W/novo.apk" "$W/alinhado.apk"

echo "==> 6/6 Assinando"
"$BT/apksigner" sign \
  --ks "$ROOT/tools/thd.p12" --ks-type PKCS12 \
  --ks-pass pass:android --ks-key-alias thd \
  --out "$OUT/thd-convertido.apk" "$W/alinhado.apk"
"$BT/apksigner" verify -v "$OUT/thd-convertido.apk" | head -n 8

echo "==> Pronto: $OUT/thd-convertido.apk ($(du -h "$OUT/thd-convertido.apk" | cut -f1))"
if [ -x "$BT/aapt2" ]; then
  "$BT/aapt2" dump badging "$OUT/thd-convertido.apk" 2>/dev/null \
    | grep -E "^(package|sdkVersion|targetSdkVersion|native-code)" || true
fi
