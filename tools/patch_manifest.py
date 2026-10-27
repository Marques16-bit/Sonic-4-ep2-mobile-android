#!/usr/bin/env python3
"""Ajustes de compatibilidade num APK já decodificado pelo apktool.

Uso: patch_manifest.py <pasta_decodificada> [target_sdk]

- uses-library -> android:required="false" (não bloqueia a instalação)
- remove uses-feature exclusivo de NVIDIA/Tegra
- se target_sdk for informado, sobe o targetSdkVersion (apktool.yml e/ou manifest)
"""
import os
import re
import sys
import xml.etree.ElementTree as ET

ANDROID = "http://schemas.android.com/apk/res/android"


def attr(nome):
    return "{%s}%s" % (ANDROID, nome)


def main():
    if len(sys.argv) < 2:
        sys.exit("uso: patch_manifest.py <pasta> [target_sdk]")
    dec = sys.argv[1]
    target = sys.argv[2].strip() if len(sys.argv) > 2 else ""
    if target and not target.isdigit():
        sys.exit("target_sdk precisa ser um número, recebi: %r" % target)

    manifest = os.path.join(dec, "AndroidManifest.xml")
    with open(manifest, encoding="utf-8") as f:
        texto = f.read()
    ET.register_namespace("android", ANDROID)
    for prefixo, uri in re.findall(r'xmlns:([A-Za-z0-9_]+)="([^"]+)"', texto):
        if prefixo != "android":
            ET.register_namespace(prefixo, uri)

    arvore = ET.parse(manifest)
    raiz = arvore.getroot()
    mudancas = []

    for lib in raiz.iter("uses-library"):
        if lib.get(attr("required")) != "false":
            lib.set(attr("required"), "false")
            mudancas.append("uses-library %s -> required=false" % lib.get(attr("name")))

    for feat in list(raiz.findall("uses-feature")):
        nome = (feat.get(attr("name")) or "").lower()
        if "nvidia" in nome or "tegra" in nome:
            raiz.remove(feat)
            mudancas.append("removido uses-feature %s" % nome)

    if target:
        for sdk in raiz.iter("uses-sdk"):
            sdk.set(attr("targetSdkVersion"), target)
            mudancas.append("uses-sdk targetSdkVersion=%s" % target)

    arvore.write(manifest, encoding="utf-8", xml_declaration=True)

    yml = os.path.join(dec, "apktool.yml")
    if target and os.path.exists(yml):
        with open(yml, encoding="utf-8") as f:
            s = f.read()
        if re.search(r"^\s*targetSdkVersion:", s, re.M):
            s = re.sub(r"(^\s*targetSdkVersion:\s*)'?\d+'?", r"\g<1>'%s'" % target, s, flags=re.M)
            mudancas.append("apktool.yml targetSdkVersion=%s" % target)
        elif re.search(r"^\s*minSdkVersion:", s, re.M):
            s = re.sub(r"^(\s*)minSdkVersion:.*$",
                       lambda m: m.group(0) + "\n" + m.group(1) + "targetSdkVersion: '%s'" % target,
                       s, count=1, flags=re.M)
            mudancas.append("apktool.yml targetSdkVersion=%s (adicionado)" % target)
        else:
            print("AVISO: não achei sdkInfo em apktool.yml; targetSdk não alterado")
        with open(yml, "w", encoding="utf-8") as f:
            f.write(s)

    if mudancas:
        for m in mudancas:
            print(" -", m)
    else:
        print(" - nenhuma mudança necessária no manifest")


if __name__ == "__main__":
    main()
