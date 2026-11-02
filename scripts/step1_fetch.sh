#!/bin/bash
# ---------------------------------------------------------------------------
# PASSO 1 - BAIXAR E FILTRAR (streaming) OS DOIS ARQUIVOS DO TSE + A UTB/UTR
#
# Saidas:
#   data/votacao_secao_2026_presidente_campinas.csv   (do votacao_secao_2026_BR.zip)
#   data/votacao_secao_2026_governador_campinas.csv   (do votacao_secao_2026_SP.zip)
#   /tmp/opencode/utb/utb_campinas.{shp,dbf,prj,shx}  (UTB/UTR, consumida no passo 2)
#
# Regras duras:
#   - CD_MUNICIPIO do TSE (Campinas = 62910), NAO o codigo IBGE (3509502)
#   - nunca extrair o CSV inteiro: unzip -p | awk, um arquivo por vez
#   - apagar o ZIP logo apos filtrar (disco ~1,7 GB livres)
#   - federal primeiro (menor), depois o estadual
# ---------------------------------------------------------------------------
set -u
cd "$(dirname "$0")/.." || exit 1
mkdir -p data /tmp/opencode/utb
LOG="${LOG:-/tmp/opencode/step1.log}"
: > "$LOG"
say(){ echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

TSE=https://cdn.tse.jus.br/estatistica/sead/odsele/votacao_secao
COD_MUN=62910

fetch_filter () {
  ZIP=$1; CSV=$2; OUT=$3; MINBYTES=$4
  say "== $ZIP =="
  if [ -s "$OUT" ]; then
    say "$OUT ja existe ($(wc -l < "$OUT") linhas) - pulando"
    return 0
  fi
  for try in 1 2 3; do
    say "baixando $ZIP (tentativa $try)"
    curl -sL --max-time 3600 -C - -o "$ZIP" "$TSE/$ZIP"
    sz=$(stat -c %s "$ZIP" 2>/dev/null || echo 0)
    say "tamanho $ZIP = $sz"
    [ "$sz" -gt "$MINBYTES" ] && break
    sleep 10
  done
  [ "${sz:-0}" -gt "$MINBYTES" ] || { say "FALHA no download de $ZIP"; return 1; }

  say "filtrando $CSV -> $OUT (CD_MUNICIPIO=$COD_MUN)"
  unzip -p "$ZIP" "$CSV" \
    | awk -F';' 'NR==1{print; next} {c=$14; gsub(/"/,"",c); if(c=="'"$COD_MUN"'") print}' > "$OUT"
  say "linhas=$(wc -l < "$OUT") bytes=$(stat -c %s "$OUT")"
  rm -f "$ZIP"
  say "removido $ZIP"
  df -h / | tail -1 | tee -a "$LOG"
}

fetch_filter votacao_secao_2026_BR.zip votacao_secao_2026_BR.csv \
             data/votacao_secao_2026_presidente_campinas.csv 200000000 || exit 1
fetch_filter votacao_secao_2026_SP.zip votacao_secao_2026_SP.csv \
             data/votacao_secao_2026_governador_campinas.csv 700000000 || exit 1

# --- UTB/UTR: shapefile solto, UUID efemero, nao e ZIP ----------------------
UDIR=/tmp/opencode/utb
if [ -s "$UDIR/utb_campinas.shp" ] && [ "$(stat -c %s "$UDIR/utb_campinas.shp")" -gt 400000 ]; then
  say "UTB ja baixada - pulando"
else
  for try in 1 2 3; do
    say "UTB: tentativa $try"
    HTML=$(curl -sL --max-time 90 "https://zoneamento.campinas.sp.gov.br/novo_zoneamento/exporta_shp.php?id=91")
    BASE=$(echo "$HTML" | grep -oP '/pmapper/tmp/ms_tmp/[0-9a-f-]+' | head -1)
    [ -z "$BASE" ] && { say "sem BASE"; sleep 3; continue; }
    ok=1
    for ext in shp dbf prj shx; do
      curl -sL --max-time 90 -o "$UDIR/utb_campinas.$ext" \
        "https://zoneamento.campinas.sp.gov.br$BASE.$ext"
      sz=$(stat -c %s "$UDIR/utb_campinas.$ext" 2>/dev/null || echo 0)
      [ "$sz" -lt 50 ] && ok=0
    done
    # o .cpg do endpoint e uma pagina HTML de erro: escrevemos o correto
    printf 'UTF-8' > "$UDIR/utb_campinas.cpg"
    if [ "$ok" = 1 ] && [ "$(stat -c %s "$UDIR/utb_campinas.shp")" -gt 400000 ]; then
      say "UTB ok (BASE=$BASE)"; break
    fi
    ok=0; sleep 3
  done
  [ "${ok:-0}" = 1 ] || { say "FALHA: UTB/UTR indisponivel apos 3 tentativas"; exit 1; }
fi

# --- metadados de candidatos (partido) - opcional, ~3 MB --------------------
CDIR=/tmp/opencode/cand
mkdir -p "$CDIR"
if [ ! -s "$CDIR/consulta_cand_2026_SP.csv" ] || [ ! -s "$CDIR/consulta_cand_2026_BR.csv" ]; then
  say "baixando consulta_cand_2026.zip"
  curl -sL --max-time 300 -o /tmp/opencode/cand.zip \
    "https://cdn.tse.jus.br/estatistica/sead/odsele/consulta_cand/consulta_cand_2026.zip" \
    && unzip -o -q /tmp/opencode/cand.zip \
         'consulta_cand_2026_SP.csv' 'consulta_cand_2026_BR.csv' -d "$CDIR" \
    && rm -f /tmp/opencode/cand.zip
fi
[ -s "$CDIR/consulta_cand_2026_SP.csv" ] && say "consulta_cand ok" \
  || say "AVISO: consulta_cand indisponivel - partido ficara NA"

say "FIM PASSO 1"
wc -l data/votacao_secao_2026_*_campinas.csv | tee -a "$LOG"
