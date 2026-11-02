#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# PASSO 2 - CONSOLIDAR A UTB/UTR OFICIAL DE CAMPINAS
#
# Entrada : shapefile temporario em /tmp/opencode/utb (baixado por step1_fetch.sh)
# Saida   : data/campinas_utb.gpkg  (EPSG:4674, 93 poligonos)
#           cache/utb_geo.rds       (copia leve p/ reuso)
#
# Regras (prompt §3.1 / §7 Passo 2):
#   - shapefile vem em EPSG:31983, DBF em Latin-1
#   - DENOMINACA e unica (93/93) e vira NM_UTB
#   - UTB_SIGLA NAO e unica (82 siglas p/ 93 feicoes) -> NUNCA usar como chave
#   - CD_UTB = sprintf("C%03d", seq_len(n)) apos ordenacao por UTB_SIGLA, NM_UTB
#   - gates: 93 feicoes, geometrias validas, area 790-800 km2
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(sf)
  library(data.table)
})

a <- commandArgs(trailingOnly = FALSE)
f <- sub("^--file=", "", a[grep("^--file=", a)])
WORKDIR <- if (length(f)) { d <- dirname(f); if (basename(d) == "scripts") dirname(d) else d } else getwd()
setwd(WORKDIR)

SRC <- "/tmp/opencode/utb/utb_campinas.shp"
OUT <- "data/campinas_utb.gpkg"
stopifnot(file.exists(SRC))

cat("Lendo shapefile:", SRC, "\n")
# O DBF deste endpoint vem em UTF-8 (bytes \xc3\xad para "í"), apesar do que a
# documentacao sugere, e o .cpg publicado nao e um .cpg (e uma pagina HTML de
# erro). Sem .cpg valido o GDAL assume Latin-1 e os acentos viram mojibake
# ("EgÃ­dio"). Escrevemos um .cpg correto antes de ler.
writeLines("UTF-8", sub("\\.shp$", ".cpg", SRC), useBytes = TRUE)
utb <- st_read(SRC, quiet = TRUE)
cat("Feicoes:", nrow(utb), "| CRS:", st_crs(utb)$epsg, "\n")
print(names(utb))

# --- encoding do DBF: garantir UTF-8 ---------------------------------------
utb$DENOMINACA <- enc2utf8(as.character(utb$DENOMINACA))
utb$UTB_SIGLA  <- enc2utf8(as.character(utb$UTB_SIGLA))

# Gate de encoding: se ainda houver mojibake ("Ã"), tenta Latin-1 -> UTF-8.
if (any(grepl("00c3", utb$DENOMINACA, fixed = TRUE))) {
  cat("Detectado mojibake; reconvertendo de Latin-1.\n")
  utb$DENOMINACA <- iconv(utb$DENOMINACA, "latin1", "UTF-8")
}
stopifnot(any(grepl("Joaquim Egídio", utb$DENOMINACA, fixed = TRUE)))
stopifnot(!any(grepl("Ã", utb$DENOMINACA, fixed = TRUE)))

cat("\nAmostra de DENOMINACA:\n")
print(head(sort(unique(utb$DENOMINACA)), 12))

# --- reprojecao -------------------------------------------------------------
stopifnot(st_crs(utb)$epsg == 31983L)
utb <- st_transform(utb, 4674)

# --- gates de entrada -------------------------------------------------------
stopifnot(nrow(utb) == 93L)
stopifnot(sum(!st_is_valid(utb)) >= 0L)
utb <- st_make_valid(utb)
stopifnot(all(st_is_valid(utb)))
stopifnot(!any(st_is_empty(utb)))
stopifnot(sum(duplicated(utb$DENOMINACA)) == 0L)   # DENOMINACA unica

area_km2 <- as.numeric(sum(st_area(utb))) / 1e6
cat(sprintf("\nArea total: %.2f km2\n", area_km2))
stopifnot(area_km2 >= 790, area_km2 <= 800)

cat("UTB_SIGLA distintas:", uniqueN(utb$UTB_SIGLA), "de", nrow(utb), "feicoes\n")
cat("Colisao MM-70:", sum(utb$UTB_SIGLA == "MM-70"), "feicoes\n")

# --- colunas finais ---------------------------------------------------------
out <- data.table(
  UTB_SIGLA  = as.character(utb$UTB_SIGLA),
  NM_UTB     = as.character(utb$DENOMINACA),
  DENSIDADE_ = as.numeric(utb$DENSIDADE_),
  geometry   = st_geometry(utb)
)
setorder(out, UTB_SIGLA, NM_UTB)
out[, CD_UTB := sprintf("C%03d", seq_len(.N))]
stopifnot(uniqueN(out$CD_UTB) == 93L)

out <- st_as_sf(out, sf_column_name = "geometry", crs = 4674)
out <- out[, c("CD_UTB", "NM_UTB", "UTB_SIGLA", "DENSIDADE_", "geometry")]

dir.create("data", showWarnings = FALSE)
unlink(OUT)
st_write(out, OUT, driver = "GPKG", quiet = TRUE, delete_dsn = TRUE)

chk <- st_read(OUT, quiet = TRUE)
cat("\n=== GATE data/campinas_utb.gpkg ===\n")
cat("Feicoes :", nrow(chk), "\n")
cat("CRS     :", st_crs(chk)$epsg, "\n")
cat("Area km2:", sprintf("%.2f", as.numeric(sum(st_area(chk))) / 1e6), "\n")
cat("CD_UTB unicos:", uniqueN(chk$CD_UTB), "| NM_UTB unicos:", uniqueN(chk$NM_UTB), "\n")
stopifnot(nrow(chk) == 93L, st_crs(chk)$epsg == 4674L, uniqueN(chk$CD_UTB) == 93L)

cat("\nPrimeiras linhas:\n")
print(as.data.table(st_drop_geometry(chk))[1:8])
cat("\nUTR (rurais):\n")
print(grep("^UTR", chk$NM_UTB, value = TRUE))

cat("\nFIM PASSO 2\n")
