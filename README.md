# Sonic 4 Ep. II THD: conversão para Androids normais

Pipeline 100% no GitHub Actions (nada compila no celular). Em vez de portar a versão iOS,
parte do APK Android do THD e descobre/corrige o que impede de rodar em aparelhos não-Tegra.

## Preparação (uma vez)
1. Cole `.github/workflows/thd-port.yml` no repositório pelo editor do GitHub
   (Add file -> Create new file). Workflows de dentro de um zip precisam ser colados à mão.
2. **Mantenha o repositório privado**: o APK tem assets e código do jogo.
3. Em **Releases -> Draft a new release**, use a tag `apk`, anexe o APK do THD
   (e o `.obb`, se o jogo tiver) e clique em **Publish release** (draft não funciona).

## Passo 1: analisar
Actions -> **THD Port** -> Run workflow -> etapa `analisar`.
Abra a execução e leia a aba **Summary**: manifest, ABIs, extensões GL que o jogo checa,
menções a Tegra/NVIDIA, formatos de textura e uma lista de hipóteses.
Mande esse relatório para o Claude: as correções são escritas sob medida em `patches/regras.json`.

## Passo 2: converter
Run workflow -> etapa `converter`. O workflow:
1. decodifica o APK (apktool);
2. relaxa `uses-library`, remove exigências de Tegra/NVIDIA do manifest e, se pedido, sobe o `targetSdk`;
3. aplica as regras de `patches/regras.json` (texto em smali ou bytes em `.so`);
4. reconstrói, alinha (zipalign) e assina;
5. publica `thd-convertido.apk` na Release de tag `thd-convertido` (download direto, sem zip).

O pacote continua o mesmo, então o `.obb` original segue valendo. A assinatura muda:
desinstale o THD original antes de instalar o convertido.

## Limites
- Só funciona se o motivo do erro estiver no manifest, nas texturas, em checagens do jogo ou no
  código que dá para corrigir com regras. Não converte 32-bit para 64-bit.
- O relatório aponta hipóteses, não certezas. Sem o logcat do aparelho, parte do diagnóstico é palpite.
