#!/usr/bin/env bash
# Uso: tools/analisar.sh <arquivo.apk> [pasta_saida] [pasta_com_obb]
# Gera <pasta_saida>/relatorio.md com o que o APK exige do aparelho.
set -uo pipefail

APK="${1:?uso: analisar.sh arquivo.apk [saida] [pasta_obb]}"
OUT="${2:-saida}"
OBBDIR="${3:-}"
mkdir -p "$OUT"
R="$OUT/relatorio.md"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

BT="${BUILD_TOOLS:-}"
if [ -z "$BT" ] && [ -n "${ANDROID_HOME:-}" ]; then
  BT="$(ls -d "$ANDROID_HOME"/build-tools/* 2>/dev/null | sort -V | tail -n 1)"
fi
AAPT2="${BT:+$BT/}aapt2"

: > "$R"
say()   { printf '%s\n' "$*" >> "$R"; }
bloco() { say '```'; head -n "${1:-60}" >> "$R"; say '```'; }

say "# Relatório: $(basename "$APK")"
say ""

if ! unzip -q -o "$APK" -d "$W/apk" 2>/dev/null; then
  say "Não consegui abrir o arquivo como APK (zip inválido)."
  exit 1
fi

# ---------- 1. Manifest ----------
: > "$W/badging.txt"
if [ -x "$AAPT2" ]; then
  "$AAPT2" dump badging "$APK" > "$W/badging.txt" 2>&1 || true
fi
PKG="$(sed -n "s/^package: name='\([^']*\)'.*/\1/p" "$W/badging.txt" | head -n 1)"
MINSDK="$(sed -n "s/^sdkVersion:'\([0-9]*\)'.*/\1/p" "$W/badging.txt" | head -n 1)"
TARGET="$(sed -n "s/^targetSdkVersion:'\([0-9]*\)'.*/\1/p" "$W/badging.txt" | head -n 1)"
ABIS="$(ls "$W/apk/lib" 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')"

say "## 1. Resumo"
say "- Pacote: \`${PKG:-?}\`"
say "- minSdk: \`${MINSDK:-?}\` / targetSdk: \`${TARGET:-?}\`"
say "- ABIs nativas: \`${ABIS:-nenhuma}\`"
say "- Tamanho do APK: $(du -h "$APK" | cut -f1)"
say ""
say "Itens do manifest que importam:"
grep -E '^(uses-feature|uses-implied-feature|uses-library|uses-gl-es|launchable-activity|native-code)' "$W/badging.txt" | bloco 40
say ""

# ---------- 2. Conteúdo ----------
say "## 2. Conteúdo (extensões mais comuns)"
find "$W/apk" -type f -printf '%f\n' | awk -F. 'NF>1{print tolower($NF)}' | sort | uniq -c | sort -rn | bloco 25
if [ -n "$OBBDIR" ] && ls "$OBBDIR"/*.obb > /dev/null 2>&1; then
  for obb in "$OBBDIR"/*.obb; do
    say "OBB \`$(basename "$obb")\` ($(du -h "$obb" | cut -f1)):"
    unzip -Z1 "$obb" 2>/dev/null | awk -F. 'NF>1{print tolower($NF)}' | sort | uniq -c | sort -rn | bloco 15
  done
fi
say ""

# ---------- 3. Bibliotecas nativas ----------
say "## 3. Bibliotecas nativas"
: > "$W/gl_ext.txt"; : > "$W/syms.txt"; : > "$W/tegra.txt"
for so in "$W"/apk/lib/*/*.so; do
  [ -f "$so" ] || continue
  rel="${so#"$W"/apk/}"
  say "### \`$rel\` ($(du -h "$so" | cut -f1))"
  readelf -h "$so" 2>/dev/null | grep -E 'Class|Machine' | sed 's/^ *//' | bloco 5
  say "Depende de: $(readelf -d "$so" 2>/dev/null | grep NEEDED | sed 's/.*\[\(.*\)\]/\1/' | tr '\n' ' ')"
  readelf --dyn-syms -W "$so" 2>/dev/null | awk '$7=="UND"{print $8}' | sed 's/@.*//' \
    | grep -E '^(gl|egl)' | sort -u >> "$W/syms.txt"
  strings -a -n 6 "$so" > "$W/str.txt"
  grep -aoE 'GL_(NV|EXT|OES|IMG|ARM|QCOM|AMD|ATI|KHR|APPLE|ANGLE|OVR|INTEL|MESA)_[A-Za-z0-9_]+' "$W/str.txt" \
    | sort -u >> "$W/gl_ext.txt"
  grep -aiE 'tegra|nvidia|tegrazone|ouya' "$W/str.txt" | sort -u | head -n 30 | sed "s|^|$(basename "$so"): |" >> "$W/tegra.txt"
done
sort -u -o "$W/gl_ext.txt" "$W/gl_ext.txt"
sort -u -o "$W/syms.txt" "$W/syms.txt"
say ""
say "Extensões GL citadas no código nativo ($(wc -l < "$W/gl_ext.txt")):"
bloco 60 < "$W/gl_ext.txt"
say "Funções gl*/egl* importadas ($(wc -l < "$W/syms.txt")), destaques:"
grep -E 'glGetString|eglGetProcAddress|CompressedTex|NV$|OES$|EXT$|KHR$' "$W/syms.txt" | bloco 30
say "Menções a Tegra/NVIDIA nas bibliotecas:"
bloco 30 < "$W/tegra.txt"
say ""

# ---------- 4. Código Java (dex) ----------
say "## 4. Código Java (dex)"
: > "$W/dex.txt"
for dex in "$W"/apk/classes*.dex; do
  [ -f "$dex" ] || continue
  strings -a -n 5 "$dex" \
    | grep -aiE 'tegra|nvidia|vending/licensing|LicenseChecker|android/os/Build;|GL_RENDERER|GL_VENDOR|glGetString' \
    | sort -u | head -n 50 | sed "s|^|$(basename "$dex"): |" >> "$W/dex.txt"
done
bloco 50 < "$W/dex.txt"
say ""

# ---------- 5. Veredito automático (hipóteses, não certezas) ----------
say "## 5. Hipóteses para tela preta / não abrir"
V=0
hip() { say "- $*"; V=$((V+1)); }

if [ -n "$ABIS" ] && ! grep -q 'arm64-v8a' <<< "$ABIS"; then
  hip "**Só 32-bit** (\`$ABIS\`): aparelhos sem suporte a 32-bit não abrem o jogo. Sem o código-fonte não dá para converter para 64-bit."
fi
if [ -n "$TARGET" ] && [ "$TARGET" -lt 24 ]; then
  hip "**targetSdk $TARGET (antigo)**: celulares com Android 14/15 podem recusar a instalação (abaixo de 23 / 24). A etapa converter tem a opção \`target_sdk\`, mas isso liga permissões em tempo de execução (conceder armazenamento nas configurações)."
fi
if grep -qiE 's3tc|dxt' "$W/gl_ext.txt" || [ -n "$(find "$W/apk" -iname '*.dds' -print -quit)" ]; then
  hip "**Texturas DXT/S3TC**: o código cita extensões DXT/S3TC ou há arquivos .dds. GPUs de celular como Mali e Adreno costumam não suportar isso e a tela fica preta. Possível caminho: converter texturas (ETC2/ASTC) ou usar um shim que responda ao jogo como se fosse Tegra."
fi
if grep -qiE 'pvrtc' "$W/gl_ext.txt"; then
  hip "O código cita **PVRTC** (PowerVR): só funciona bem em GPU PowerVR."
fi
if grep -qE 'GL_NV_' "$W/gl_ext.txt" || [ -s "$W/tegra.txt" ]; then
  hip "**Checagem de Tegra/NVIDIA**: $(grep -c . "$W/tegra.txt") linhas citam Tegra/NVIDIA e $(grep -c 'GL_NV_' "$W/gl_ext.txt") extensões \`GL_NV_*\`. O jogo pode escolher o caminho de renderização (ou travar) conforme o GPU."
fi
if grep -qiE 'licens|vending' "$W/dex.txt"; then
  hip "**Verificação de licença do Google Play** (LVL) no código Java: pode travar se o app não foi instalado pela Play Store."
fi
if [ "$V" -eq 0 ]; then
  say "- Nada óbvio encontrado: a causa deve estar em outro ponto (OBB/permissões/crash em runtime). Próximo passo: coletar o logcat do aparelho."
fi
say ""
say "_Isto são pistas, não diagnóstico final. Mande este relatório para eu escrever as regras de correção sob medida._"
