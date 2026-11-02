#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# PASSO 3 - VALIDAR OS EXTRATOS E DEDUPLICAR OS LOCAIS DE VOTACAO
#
# Entradas: data/votacao_secao_2026_presidente_campinas.csv   (BR -> Presidente 1T+2T)
#           data/votacao_secao_2026_governador_campinas.csv   (SP -> Governador 1T)
# Saidas  : cache/votes_presidente.csv / cache/votes_governador.csv (so votos validos)
#           cache/voting_places_unique.csv                    (268 locais unicos)
#           cache/step3_stats.rds
#
# Regras (prompt §7 Passo 1 e 3):
#   - CD_MUNICIPIO TSE = 62910 (nao 3509502)
#   - Presidente so existe no _BR.zip; Governador so no _SP.zip
#   - excluir NR_VOTAVEL 95/96 (branco/nulo)
#   - chave do local = (NR_ZONA, NM_LOCAL_VOTACAO, DS_LOCAL_VOTACAO_ENDERECO)
#     normalizados; NR_LOCAL_VOTACAO NAO e unico entre zonas
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(data.table)
})

a <- commandArgs(trailingOnly = FALSE)
f <- sub("^--file=", "", a[grep("^--file=", a)])
WORKDIR <- if (length(f)) { d <- dirname(f); if (basename(d) == "scripts") dirname(d) else d } else getwd()
setwd(WORKDIR)
dir.create("cache", showWarnings = FALSE)

COD_MUN <- 62910L
COLS <- c("NR_TURNO", "CD_ELEICAO", "DS_ELEICAO", "SG_UE", "NM_UE", "CD_MUNICIPIO",
          "NM_MUNICIPIO", "NR_ZONA", "NR_SECAO", "CD_CARGO", "DS_CARGO",
          "NR_VOTAVEL", "NM_VOTAVEL", "QT_VOTOS", "NR_LOCAL_VOTACAO",
          "NM_LOCAL_VOTACAO", "DS_LOCAL_VOTACAO_ENDERECO")

# Os CSVs do TSE sao Latin-1 e o fread marca as strings de forma inconsistente
# ("latin1" em umas, "unknown" em outras). Sem isso, toupper() falha com
# "invalid input ... in 'utf8towcs'". Converte tudo para UTF-8 valido.
to_utf8 <- function(x) {
  x <- enc2utf8(as.character(x))
  bad <- is.na(iconv(x, "UTF-8", "UTF-8"))
  if (any(bad)) x[bad] <- iconv(x[bad], "latin1", "UTF-8")
  x
}

norm_txt <- function(x) {
  x <- toupper(to_utf8(x))
  x <- gsub("[[:space:]]+", " ", x)
  trimws(x)
}

read_extract <- function(path) {
  stopifnot(file.exists(path))
  d <- fread(path, sep = ";", encoding = "Latin-1", colClasses = "character",
             na.strings = c("", "NA", "#N/A", "null"), showProgress = FALSE)
  # Garante UTF-8 valido antes de qualquer operacao de string
  chr_cols <- names(which(sapply(d, is.character)))
  d[, (chr_cols) := lapply(.SD, to_utf8), .SDcols = chr_cols]
  cat("Lido", path, "->", nrow(d), "linhas\n")
  d
}

# --- leitura + assertivas basicas -------------------------------------------
pres <- read_extract("data/votacao_secao_2026_presidente_campinas.csv")
gov  <- read_extract("data/votacao_secao_2026_governador_campinas.csv")

for (d in list(pres, gov)) {
  stopifnot(nrow(d) > 1)
  stopifnot(all(COLS %in% names(d)))
  stopifnot(all(grepl("CAMPINAS", toupper(d$NM_MUNICIPIO))))
  stopifnot(all(as.integer(d$CD_MUNICIPIO) == COD_MUN))
}

for (nm in c("QT_VOTOS", "NR_TURNO", "NR_ZONA", "NR_SECAO", "NR_LOCAL_VOTACAO",
             "NR_VOTAVEL", "CD_CARGO")) {
  pres[, (nm) := as.integer(get(nm))]
  gov[,  (nm) := as.integer(get(nm))]
}

cat("\n=== Extrato FEDERAL (Presidente) ===\n")
print(pres[, .N, by = .(NR_TURNO, DS_CARGO)][order(NR_TURNO, DS_CARGO)])
cat("\n=== Extrato ESTADUAL ===\n")
print(gov[, .N, by = .(NR_TURNO, DS_CARGO)][order(NR_TURNO, DS_CARGO)])

# --- gates de cargo/turno (falha ruidosa) -----------------------------------
stopifnot("Presidente" %in% unique(pres$DS_CARGO))
stopifnot(sort(unique(pres[DS_CARGO == "Presidente"]$NR_TURNO)) == c(1L, 2L))
stopifnot(!"Governador" %in% unique(pres$DS_CARGO))
stopifnot("Governador" %in% unique(gov$DS_CARGO))
stopifnot(all(gov[DS_CARGO == "Governador"]$NR_TURNO == 1L))
stopifnot(!"Presidente" %in% unique(gov$DS_CARGO))

cat("\nOK: Presidente com turnos 1 e 2 no arquivo federal;",
    "Governador so no 1o turno no arquivo estadual.\n")

# --- eleicao / abrangencia --------------------------------------------------
cat("\nCD_ELEICAO federal :", unique(pres$CD_ELEICAO), "|", unique(pres$DS_ELEICAO), "\n")
cat("CD_ELEICAO estadual:", unique(gov$CD_ELEICAO),  "|", unique(gov$DS_ELEICAO), "\n")

# --- votos validos (exclui 95 branco / 96 nulo) ------------------------------
val <- function(d) d[!NR_VOTAVEL %in% c(95L, 96L)]
pres_v <- val(pres)
gov_v  <- val(gov)

# --- locais unicos ----------------------------------------------------------
loc_cols <- c("NR_ZONA", "NM_LOCAL_VOTACAO", "DS_LOCAL_VOTACAO_ENDERECO")
mk_places <- function(...) {
  d <- rbindlist(list(...), use.names = TRUE, fill = TRUE)
  d <- unique(d[, ..loc_cols])
  d[, NM_CLEAN   := norm_txt(NM_LOCAL_VOTACAO)]
  d[, ADDR_CLEAN := norm_txt(DS_LOCAL_VOTACAO_ENDERECO)]
  unique(d, by = c("NR_ZONA", "NM_CLEAN", "ADDR_CLEAN"))
}

places <- mk_places(pres[, ..loc_cols], gov[, ..loc_cols])
places[, NR_ZONA := as.integer(NR_ZONA)]
setorder(places, NR_ZONA, NM_CLEAN, ADDR_CLEAN)
places[, id_local := sprintf("L%03d", seq_len(.N))]

cat("\n=== LOCAIS DE VOTACAO ===\n")
cat("Locais unicos          :", nrow(places), "\n")
cat("Zonas eleitorais       :", uniqueN(places$NR_ZONA), "->",
    paste(sort(unique(places$NR_ZONA)), collapse = ", "), "\n")
n_secoes_pres <- uniqueN(pres_v[, .(NR_ZONA, NR_SECAO)])
n_secoes_gov  <- uniqueN(gov_v[,  .(NR_ZONA, NR_SECAO)])
cat("Secoes (federal)       :", n_secoes_pres, "\n")
cat("Secoes (estadual)      :", n_secoes_gov, "\n")
cat("Locais distintos por (zona, NR_LOCAL_VOTACAO):",
    uniqueN(pres_v[, .(NR_ZONA, NR_LOCAL_VOTACAO)]), "\n")

# --- referencias municipais (usadas nos gates Q1) ---------------------------
ref <- function(d, turno, cargo) {
  x <- d[NR_TURNO == turno & DS_CARGO == cargo]
  tot <- x[, .(votos = sum(QT_VOTOS)), by = .(NR_VOTAVEL, NM_VOTAVEL)][order(-votos)]
  tot[, pct := votos / sum(votos)]
  tot
}
ref_pres <- ref(pres_v, 2L, "Presidente")
ref_gov  <- ref(gov_v,  1L, "Governador")

cat("\n=== REFERENCIA MUNICIPAL - Presidente 2o turno ===\n")
cat("Votos validos:", format(sum(ref_pres$votos), big.mark = ".", decimal.mark = ","), "\n")
print(head(ref_pres, 4))
cat("\n=== REFERENCIA MUNICIPAL - Governador 1o turno ===\n")
cat("Votos validos:", format(sum(ref_gov$votos), big.mark = ".", decimal.mark = ","), "\n")
print(head(ref_gov, 5))

# Sanidade contra os valores observados em 2026-10-31 (prompt §9) -- aviso, nao gate
chk <- function(v, esperado, rotulo) {
  if (abs(v - esperado) / esperado > 0.001)
    warning(sprintf("%s: %d votos, esperado ~%d", rotulo, v, esperado), call. = FALSE)
  else cat(sprintf("OK  %s: %d votos (esperado ~%d)\n", rotulo, v, esperado))
}
chk(sum(ref_pres$votos), 664136L, "Presidente 2T")
chk(sum(ref_gov$votos),  593302L, "Governador 1T")

# --- saidas -----------------------------------------------------------------
fwrite(pres_v, "cache/votes_presidente.csv", na = "")
fwrite(gov_v,  "cache/votes_governador.csv",  na = "")
fwrite(places, "cache/voting_places_unique.csv", na = "")

stats <- list(
  n_linhas_pres = nrow(pres), n_linhas_gov = nrow(gov),
  n_locais = nrow(places), n_zonas = uniqueN(places$NR_ZONA),
  zonas = sort(unique(places$NR_ZONA)),
  n_secoes_pres = n_secoes_pres, n_secoes_gov = n_secoes_gov,
  ref_pres = ref_pres, ref_gov = ref_gov
)
saveRDS(stats, "cache/step3_stats.rds")
cat("\nFIM PASSO 3\n")
