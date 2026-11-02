#!/bin/bash
# ---------------------------------------------------------------------------
# PIPELINE COMPLETO - dois mapas eleitorais de Campinas por bairro (UTB/UTR)
#
#   ./scripts/run_all.sh            # tudo (usa cache quando existir)
#   ./scripts/run_all.sh --clean    # apaga cache/ e output/ antes de rodar
#
# Passos:
#   1. step1_fetch.sh           baixa e filtra TSE (streaming) + UTB + candidatos
#   2. step2_utb.R              consolida a UTB/UTR em data/campinas_utb.gpkg
#   3. step3_places.R           valida extratos e deduplica os 268 locais
#   4. step4_geocode.R          geocodifica os locais (Photon, cache resumivel)
#   5. step5_join_aggregate.R   join espacial + agregacao + gates Q1-Q6
#   6. step6_maps.R             gera os 2 mapas + index.html
# ---------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")/.." || exit 1
mkdir -p cache output data

if [ "${1:-}" = "--clean" ]; then
  echo "== limpando cache/ e output/ =="
  rm -rf cache output
  mkdir -p cache output
fi

step () { echo; echo "################ $* ################"; }

step "PASSO 1/6 - download e filtro TSE + UTB + candidatos"
bash scripts/step1_fetch.sh

step "PASSO 2/6 - consolidar UTB/UTR"
Rscript scripts/step2_utb.R

step "PASSO 3/6 - validar extratos e deduplicar locais"
Rscript scripts/step3_places.R

step "PASSO 4/6 - geocodificar locais (Photon)"
Rscript scripts/step4_geocode.R

step "PASSO 5/6 - join espacial, agregacao e gates Q1-Q6"
Rscript scripts/step5_join_aggregate.R

step "PASSO 6/6 - gerar mapas HTML e landing"
Rscript scripts/step6_maps.R

echo
echo "################ PRONTO ################"
ls -la campinas_presidente_2t.html campinas_governador_1t.html index.html output/*.csv
echo
echo "Para ver no navegador:  python3 -m http.server 8000"
echo "Depois abra http://localhost:8000/"
