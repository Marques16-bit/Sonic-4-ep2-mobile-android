#!/usr/bin/env python3
"""Aplica as regras de patches/regras.json no APK decodificado.

Uso: aplicar_regras.py <pasta_decodificada> <regras.json>

Formato de cada regra:
  {"tipo": "texto", "arquivos": "smali*/**/Foo.smali", "procurar": "...", "trocar": "..."}
  {"tipo": "hex",   "arquivos": "lib/armeabi-v7a/libx.so", "procurar": "74 65 67", "trocar": "78 78 78"}
Campos opcionais: "obrigatorio" (padrão true: se nada for encontrado, o build falha).
"arquivos" é um glob relativo à pasta decodificada. Regras "hex" exigem o mesmo tamanho.
"""
import glob
import json
import os
import sys


def main():
    if len(sys.argv) < 3:
        sys.exit("uso: aplicar_regras.py <pasta> <regras.json>")
    dec, caminho = sys.argv[1], sys.argv[2]
    if not os.path.exists(caminho):
        print(" - sem arquivo de regras, nada a fazer")
        return
    with open(caminho, encoding="utf-8") as f:
        regras = json.load(f).get("regras", [])
    if not regras:
        print(" - nenhuma regra definida")
        return

    falhas = 0
    for i, r in enumerate(regras, 1):
        tipo = r.get("tipo")
        obrigatorio = r.get("obrigatorio", True)
        arquivos = sorted(glob.glob(os.path.join(dec, r["arquivos"]), recursive=True))
        total = 0
        for caminho_arq in arquivos:
            if not os.path.isfile(caminho_arq):
                continue
            if tipo == "texto":
                with open(caminho_arq, encoding="utf-8", errors="surrogateescape", newline="") as f:
                    s = f.read()
                n = s.count(r["procurar"])
                if n:
                    with open(caminho_arq, "w", encoding="utf-8", errors="surrogateescape", newline="") as f:
                        f.write(s.replace(r["procurar"], r["trocar"]))
                    total += n
            elif tipo == "hex":
                a = bytes.fromhex(r["procurar"].replace(" ", ""))
                b = bytes.fromhex(r["trocar"].replace(" ", ""))
                if len(a) != len(b):
                    sys.exit("regra %d: 'procurar' e 'trocar' precisam ter o mesmo tamanho" % i)
                with open(caminho_arq, "rb") as f:
                    dados = f.read()
                n = dados.count(a)
                if n:
                    with open(caminho_arq, "wb") as f:
                        f.write(dados.replace(a, b))
                    total += n
            else:
                sys.exit("regra %d: tipo desconhecido %r" % (i, tipo))
        print(" - regra %d (%s, %s): %d substituição(ões) em %d arquivo(s)"
              % (i, tipo, r["arquivos"], total, len(arquivos)))
        if total == 0 and obrigatorio:
            falhas += 1
    if falhas:
        sys.exit("%d regra(s) obrigatória(s) não encontraram nada" % falhas)


if __name__ == "__main__":
    main()
