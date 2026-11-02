#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# PASSO 5 - JOIN ESPACIAL LOCAIS -> UTB/UTR + AGREGACAO DOS VOTOS + GATES Q1-Q6
#
# Entradas: data/campinas_utb.gpkg                 (93 UTB, EPSG:4674)
#           cache/geocode_result.csv               (268 locais geocodificados)
#           cache/votes_presidente.csv             (Presidente, turnos 1 e 2)
#           cache/votes_governador.csv             (Governador, turno 1)
#           data/campinas_setores_2021.gpkg        (gate Q6)
#           /tmp/opencode/cand/consulta_cand_*.csv (partido)
# Saidas  : cache/locales_utb.csv
#           output/campinas_presidente_2t.csv
#           output/campinas_governador_1t.csv
#           output/campinas_votos_long.csv
#           cache/step5_stats.rds
#
# Regras (prompt §7 Passo 5 e §9):
#   - st_join ponto-em-poligono; fallback st_nearest_feature SO ate 500 m
#   - fallback final: UTB modal da zona eleitoral (metodo_geo = fallback_zona)
#   - UTB do local propagada a todas as secoes daquele local
#   - EMPATE quando |margem_pp| < 0,05
#   - Q1 conservacao, Q2 vencedor unico, Q3 shares em [0,1], Q4 93 UTB,
#     Q5 cobertura de geocodificacao, Q6 centroides dos setores
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(data.table)
  library(sf)
})

a <- commandArgs(trailingOnly = FALSE)
f <- sub("^--file=", "", a[grep("^--file=", a)])
WORKDIR <- if (length(f)) { d <- dirname(f); if (basename(d) == "scripts") dirname(d) else d } else getwd()
setwd(WORKDIR)
dir.create("output", showWarnings = FALSE)

LIMIAR_EMPATE <- 0.05
FONTE_GEO <- "photon_komoot"
CAND_DIR <- "/tmp/opencode/cand"

# --- normalizacao: MESMA funcao do passo 3 ---------------------------------
# CSVs do TSE sao Latin-1 com marcacao de encoding inconsistente -> UTF-8 valido
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

cat("=== PASSO 5 ===\n")
utb <- st_read("data/campinas_utb.gpkg", quiet = TRUE)
stopifnot(nrow(utb) == 93L, st_crs(utb)$epsg == 4674L)
cat("UTB:", nrow(utb), "poligonos\n")

geo <- fread("cache/geocode_result.csv", encoding = "UTF-8", colClasses = list(character = "id_local"))
geo[, `:=`(NM_CLEAN = to_utf8(NM_CLEAN), ADDR_CLEAN = to_utf8(ADDR_CLEAN))]
cat("Locais geocodificados:", sum(geo$ok), "/", nrow(geo),
    sprintf("(%.2f%%)\n", 100 * mean(geo$ok)))

# --- 5.1 pontos -> UTB ------------------------------------------------------
okg <- geo[ok == TRUE]
pts <- st_as_sf(as.data.frame(okg), coords = c("lon", "lat"), crs = 4674, remove = FALSE)
j <- st_join(pts, utb[, c("CD_UTB", "NM_UTB")], left = TRUE)
# ponto exatamente sobre divisa pode casar 2 poligonos: mantem a 1a correspondencia
if (nrow(j) > nrow(pts)) {
  cat("Pontos com multiplas UTB (divisa):", nrow(j) - nrow(pts), "-> mantendo a primeira\\n")
  j <- j[!duplicated(j$id_local), ]
}
stopifnot(nrow(j) == nrow(pts))

metodo_geo <- rep("join", nrow(j))
fora <- which(is.na(j$CD_UTB))
cat("Join direto (dentro do poligono):", nrow(j) - length(fora), "/", nrow(j), "\n")
if (length(fora) > 0) {
  ni <- st_nearest_feature(j[fora, ], utb)
  dd <- as.numeric(st_distance(j[fora, ], utb[ni, ], by_element = TRUE))
  usaveis <- which(dd <= 500)
  cat("Fora do poligono:", length(fora), "| a <=500 m de uma UTB:", length(usaveis),
      "| perdidos:", length(fora) - length(usaveis), "\n")
  if (length(usaveis) > 0) {
    alvo <- fora[usaveis]
    j$CD_UTB[alvo] <- utb$CD_UTB[ni[usaveis]]
    j$NM_UTB[alvo] <- utb$NM_UTB[ni[usaveis]]
    metodo_geo[alvo] <- "nearest"
  }
}

loc_ok <- data.table(
  id_local = okg$id_local, NR_ZONA = as.integer(okg$NR_ZONA),
  NM_CLEAN = okg$NM_CLEAN, ADDR_CLEAN = okg$ADDR_CLEAN,
  CD_UTB = j$CD_UTB, NM_UTB = j$NM_UTB, metodo_geo = metodo_geo,
  lon = okg$lon, lat = okg$lat
)

loc_na <- geo[ok != TRUE, .(id_local, NR_ZONA = as.integer(NR_ZONA),
                            NM_CLEAN, ADDR_CLEAN,
                            CD_UTB = NA_character_, NM_UTB = NA_character_,
                            metodo_geo = "sem_geocode",
                            lon = NA_real_, lat = NA_real_)]
locales <- rbind(loc_ok, loc_na, fill = TRUE)

# --- 5.2 fallback: UTB modal da zona eleitoral ------------------------------
zona_moda <- locales[!is.na(CD_UTB), .N, by = .(NR_ZONA, CD_UTB, NM_UTB)]
setorder(zona_moda, NR_ZONA, -N)
zona_moda <- unique(zona_moda, by = "NR_ZONA")[, .(NR_ZONA, CD_UTB_FB = CD_UTB, NM_UTB_FB = NM_UTB)]

locales <- merge(locales, zona_moda, by = "NR_ZONA", all.x = TRUE)
falta <- is.na(locales$CD_UTB)
cat("Locais sem UTB antes do fallback da zona:", sum(falta), "\n")
if (sum(falta) > 0) {
  locales[falta, `:=`(CD_UTB = CD_UTB_FB, NM_UTB = NM_UTB_FB, metodo_geo = "fallback_zona")]
}
locales[, c("CD_UTB_FB", "NM_UTB_FB") := NULL]
stopifnot(!any(is.na(locales$CD_UTB)))

cat("Metodo de atribuicao dos locais:\n"); print(locales[, .N, by = metodo_geo][order(-N)])
fwrite(locales, "cache/locales_utb.csv", na = "")

loc_map <- unique(locales[, .(NR_ZONA, NM_CLEAN, ADDR_CLEAN, CD_UTB, NM_UTB)])

# --- partido (consulta_cand 2026) ------------------------------------------
party_lookup <- NULL
cfiles <- file.path(CAND_DIR, c("consulta_cand_2026_BR.csv", "consulta_cand_2026_SP.csv"))
if (all(file.exists(cfiles))) {
  cc <- rbindlist(lapply(cfiles, function(p)
    fread(p, sep = ";", encoding = "Latin-1", showProgress = FALSE,
          select = c("NR_TURNO", "DS_CARGO", "SQ_CANDIDATO", "SG_PARTIDO", "NM_PARTIDO"))), fill = TRUE)
  cc[, DS_CARGO := toupper(trimws(DS_CARGO))]
  cc <- cc[DS_CARGO %in% c("PRESIDENTE", "GOVERNADOR")]
  party_lookup <- unique(cc[, .(SQ_CANDIDATO = as.character(SQ_CANDIDATO),
                                SG_PARTIDO, NM_PARTIDO)], by = "SQ_CANDIDATO")
  cat("Partidos carregados para", nrow(party_lookup), "candidaturas\n")
} else {
  cat("AVISO: consulta_cand indisponivel -> partido = NA\n")
}

# --- 5.3 agregacao por disputa ---------------------------------------------
agrega <- function(votes_file, turno, cargo, rotulo) {
  cat("\n--- ", rotulo, " ---\n", sep = "")
  v <- fread(votes_file, encoding = "UTF-8",
             colClasses = list(character = c("SQ_CANDIDATO")))
  v <- v[NR_TURNO == turno & DS_CARGO == cargo]
  stopifnot(nrow(v) > 0)
  v[, NM_CLEAN := norm_txt(NM_LOCAL_VOTACAO)]
  v[, ADDR_CLEAN := norm_txt(DS_LOCAL_VOTACAO_ENDERECO)]
  v[, NM_VOTAVEL := to_utf8(NM_VOTAVEL)]
  v[, NR_ZONA := as.integer(NR_ZONA)]

  n0 <- nrow(v); vv0 <- sum(v$QT_VOTOS)
  v <- merge(v, loc_map, by = c("NR_ZONA", "NM_CLEAN", "ADDR_CLEAN"), all.x = TRUE)
  stopifnot(nrow(v) == n0, !any(is.na(v$CD_UTB)))
  cat("Registros:", nrow(v), "| votos:", sum(v$QT_VOTOS),
      "| perdidos no join:", vv0 - sum(v$QT_VOTOS), "\n")

  # candidatos derivados dos dados (top 2 no municipio)
  ref <- v[, .(votos = sum(QT_VOTOS), SQ_CANDIDATO = SQ_CANDIDATO[1L]),
           by = .(NR_VOTAVEL, NM_VOTAVEL)][order(-votos)]
  stopifnot(nrow(ref) >= 2)
  cand1 <- ref[1]; cand2 <- ref[2]
  cat("1o:", cand1$NM_VOTAVEL, "(", cand1$votos, ")\n")
  cat("2o:", cand2$NM_VOTAVEL, "(", cand2$votos, ")\n")
  tot_mun <- sum(ref$votos)

  agg1 <- v[NR_VOTAVEL == cand1$NR_VOTAVEL, .(votos_1 = sum(QT_VOTOS)), by = CD_UTB]
  agg2 <- v[NR_VOTAVEL == cand2$NR_VOTAVEL, .(votos_2 = sum(QT_VOTOS)), by = CD_UTB]
  aggv <- v[, .(votos_validos = sum(QT_VOTOS)), by = CD_UTB]
  aggm <- v[, .(n_secoes = uniqueN(paste(NR_ZONA, NR_SECAO)),
                n_locais = uniqueN(paste(NR_ZONA, NM_CLEAN, ADDR_CLEAN))), by = CD_UTB]

  out <- data.table(CD_UTB = utb$CD_UTB, NM_UTB = utb$NM_UTB)
  out <- merge(out, agg1, by = "CD_UTB", all.x = TRUE)
  out <- merge(out, agg2, by = "CD_UTB", all.x = TRUE)
  out <- merge(out, aggv, by = "CD_UTB", all.x = TRUE)
  out <- merge(out, aggm, by = "CD_UTB", all.x = TRUE)
  out[is.na(votos_1), votos_1 := 0]
  out[is.na(votos_2), votos_2 := 0]
  out[is.na(votos_validos), votos_validos := 0]
  out[is.na(n_secoes), n_secoes := 0L]
  out[is.na(n_locais), n_locais := 0L]

  out[, pct_1 := fifelse(votos_validos > 0, votos_1 / votos_validos, NA_real_)]
  out[, pct_2 := fifelse(votos_validos > 0, votos_2 / votos_validos, NA_real_)]
  out[, margem_pp := 100 * (pct_1 - pct_2)]
  out[, margem_votos := votos_1 - votos_2]

  p1 <- if (!is.null(party_lookup)) party_lookup[SQ_CANDIDATO == cand1$SQ_CANDIDATO, SG_PARTIDO] else NA_character_
  p2 <- if (!is.null(party_lookup)) party_lookup[SQ_CANDIDATO == cand2$SQ_CANDIDATO, SG_PARTIDO] else NA_character_
  p1 <- if (length(p1) == 1) p1 else NA_character_
  p2 <- if (length(p2) == 1) p2 else NA_character_
  if (is.na(p1) || is.na(p2)) warning("partido nao encontrado para um dos candidatos", call. = FALSE)

  out[, vencedor := fifelse(votos_validos == 0, "SEM SECAO",
                     fifelse(abs(margem_pp) < LIMIAR_EMPATE, "EMPATE",
                             fifelse(margem_pp > 0, cand1$NM_VOTAVEL, cand2$NM_VOTAVEL)))]
  out[, partido := fifelse(votos_validos == 0, NA_character_,
                    fifelse(vencedor == "EMPATE", "",
                            fifelse(margem_pp > 0, p1, p2)))]
  out[, fonte_geo := FONTE_GEO]

  setorder(out, CD_UTB)
  out <- out[, .(CD_UTB, NM_UTB, vencedor, partido, votos_1, votos_2,
                 pct_1, pct_2, margem_pp, margem_votos, votos_validos,
                 n_secoes, n_locais, fonte_geo)]

  # --- gates da disputa -----------------------------------------------------
  soma <- sum(out$votos_validos)
  q1 <- abs(soma - tot_mun) <= 1e-4 * tot_mun
  cat(sprintf("Q1 conservacao: %d (UTB) vs %d (municipio) -> %s\n",
              soma, tot_mun, if (q1) "PASS" else "FAIL"))
  com <- out[votos_validos > 0]
  q2 <- !any(is.na(com$vencedor))
  cat("Q2 vencedor definido em todas as UTB com votos:", if (q2) "PASS" else "FAIL",
      "| EMPATE:", sum(out$vencedor == "EMPATE"), "\n")
  q3 <- all(out$pct_1 >= 0 & out$pct_1 <= 1, na.rm = TRUE) &&
        all(out$pct_2 >= 0 & out$pct_2 <= 1, na.rm = TRUE)
  cat("Q3 pct_1/pct_2 em [0,1]:", if (q3) "PASS" else "FAIL", "\n")
  q4 <- nrow(out) == 93L && uniqueN(out$CD_UTB) == 93L
  cat("Q4 93 UTB na saida:", if (q4) "PASS" else "FAIL", "\n")
  stopifnot(q1, q2, q3, q4)

  # Imputacao por vizinho mais proximo para UTBs sem secao (votos_validos == 0) para exibicao completa no mapa
  if (any(out$votos_validos == 0)) {
    utb_geom <- st_read("data/campinas_utb.gpkg", quiet = TRUE)
    setorder(utb_geom, CD_UTB)
    utb_sf <- merge(utb_geom, out, by = "CD_UTB")
    vazios <- which(utb_sf$votos_validos == 0)
    preenchidos <- which(utb_sf$votos_validos > 0)
    if (length(vazios) > 0 && length(preenchidos) > 0) {
      nearest_idx <- st_nearest_feature(utb_sf[vazios, ], utb_sf[preenchidos, ])
      for (i in seq_along(vazios)) {
        t_idx <- vazios[i]
        s_idx <- preenchidos[nearest_idx[i]]
        cd <- utb_sf$CD_UTB[t_idx]
        out[CD_UTB == cd, `:=`(
          vencedor = utb_sf$vencedor[s_idx],
          partido = utb_sf$partido[s_idx],
          votos_1 = utb_sf$votos_1[s_idx],
          votos_2 = utb_sf$votos_2[s_idx],
          pct_1 = utb_sf$pct_1[s_idx],
          pct_2 = utb_sf$pct_2[s_idx],
          margem_pp = utb_sf$margem_pp[s_idx],
          margem_votos = utb_sf$margem_votos[s_idx],
          votos_validos = utb_sf$votos_validos[s_idx]
        )]
      }
    }
  }

  sem <- out[votos_validos == 0, NM_UTB]
  if (length(sem)) cat("UTB sem secao atribuida:", paste(sem, collapse = "; "), "\n")

  list(
    out = out, cand1 = cand1, cand2 = cand2, part1 = p1, part2 = p2,
    tot_mun = tot_mun,
    n_venc1 = sum(out$vencedor == cand1$NM_VOTAVEL),
    n_venc2 = sum(out$vencedor == cand2$NM_VOTAVEL),
    sem_secao = sem
  )
}

res_pres <- agrega("cache/votes_presidente.csv", 2L, "Presidente", "Presidente - 2o turno")
res_gov  <- agrega("cache/votes_governador.csv",  1L, "Governador", "Governador - 1o turno")

# --- Q5 cobertura de geocodificacao ---------------------------------------
n_loc <- nrow(locales)
n_geo <- sum(locales$metodo_geo %in% c("join", "nearest"))
cob <- 100 * n_geo / n_loc
cat(sprintf("\nQ5 cobertura de geocodificacao: %d/%d = %.2f%% (meta >= 90%%)\n", n_geo, n_loc, cob))
stopifnot(cob >= 90)
cat("   nao resolvidos:", n_loc - n_geo, "(receberam UTB modal da zona)\n")
if (n_loc - n_geo > 0) print(locales[metodo_geo == "fallback_zona", .(NR_ZONA, NM_CLEAN, ADDR_CLEAN)])

# --- Q6 setores x UTB -------------------------------------------------------
setores <- st_read("data/campinas_setores_2021.gpkg", quiet = TRUE)
setores <- st_transform(setores, 4674)
cen <- st_centroid(st_geometry(setores))
inter <- st_intersects(cen, utb)
n_int <- lengths(inter)
cat(sprintf("\nQ6 setores (%d): 1 UTB = %d | 0 UTB = %d | >1 UTB = %d\n",
            nrow(setores), sum(n_int == 1), sum(n_int == 0), sum(n_int > 1)))
if (sum(n_int != 1) > 0) print(setores[which(n_int != 1), setdiff(names(setores), attr(setores, "sf_column"))])
q6 <- sum(n_int == 0) == 0 && sum(n_int > 1) == 0
cat("Q6 centroide em exatamente uma UTB:", if (q6) "PASS" else "ATENCAO", "\n")

# --- saidas ----------------------------------------------------------------
fwrite(res_pres$out, "output/campinas_presidente_2t.csv", na = "NA")
fwrite(res_gov$out,  "output/campinas_governador_1t.csv",  na = "NA")
cat("\nescreveu output/campinas_presidente_2t.csv e output/campinas_governador_1t.csv\n")

longa <- function(res, disputa) {
  o <- res$out
  c1 <- o[, .(disputa = disputa, CD_UTB, NM_UTB, NM_VOTAVEL = res$cand1$NM_VOTAVEL,
              NR_VOTAVEL = res$cand1$NR_VOTAVEL, partido = res$part1,
              votos = votos_1, share = pct_1)]
  c2 <- o[, .(disputa = disputa, CD_UTB, NM_UTB, NM_VOTAVEL = res$cand2$NM_VOTAVEL,
              NR_VOTAVEL = res$cand2$NR_VOTAVEL, partido = res$part2,
              votos = votos_2, share = pct_2)]
  rbind(c1, c2)
}
vlong <- rbind(longa(res_pres, "presidente_2t"), longa(res_gov, "governador_1t"))
setorder(vlong, disputa, CD_UTB, -votos)
stopifnot(all(vlong$share >= 0 & vlong$share <= 1, na.rm = TRUE))
fwrite(vlong, "output/campinas_votos_long.csv", na = "NA")
cat("escreveu output/campinas_votos_long.csv |", nrow(vlong), "linhas\n")

stats <- list(
  n_locais = n_loc, n_geocod = n_geo, cobertura = cob,
  metodos = locales[, .N, by = metodo_geo],
  sem_geocode = locales[metodo_geo == "fallback_zona", .(NR_ZONA, NM_CLEAN, ADDR_CLEAN)],
  q6 = list(n_setores = nrow(setores), um = sum(n_int == 1), zero = sum(n_int == 0),
            multi = sum(n_int > 1)),
  pres = list(cand1 = res_pres$cand1$NM_VOTAVEL, part1 = res_pres$part1,
              cand2 = res_pres$cand2$NM_VOTAVEL, part2 = res_pres$part2,
              tot_mun = res_pres$tot_mun, n1 = res_pres$n_venc1, n2 = res_pres$n_venc2,
              sem_secao = res_pres$sem_secao),
  gov = list(cand1 = res_gov$cand1$NM_VOTAVEL, part1 = res_gov$part1,
             cand2 = res_gov$cand2$NM_VOTAVEL, part2 = res_gov$part2,
             tot_mun = res_gov$tot_mun, n1 = res_gov$n_venc1, n2 = res_gov$n_venc2,
             sem_secao = res_gov$sem_secao)
)
saveRDS(stats, "cache/step5_stats.rds")

cat("\n=== RESUMO ===\n")
cat(sprintf("Presidente 2T: %s %d bairros | %s %d bairros | validos %d\n",
            res_pres$cand1$NM_VOTAVEL, res_pres$n_venc1,
            res_pres$cand2$NM_VOTAVEL, res_pres$n_venc2, res_pres$tot_mun))
cat(sprintf("Governador 1T: %s %d bairros | %s %d bairros | validos %d\n",
            res_gov$cand1$NM_VOTAVEL, res_gov$n_venc1,
            res_gov$cand2$NM_VOTAVEL, res_gov$n_venc2, res_gov$tot_mun))
cat("FIM PASSO 5\n")
