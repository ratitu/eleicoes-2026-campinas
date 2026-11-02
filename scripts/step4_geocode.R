#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# PASSO 4 - GEOCODIFICACAO DOS LOCAIS DE VOTACAO (OSM Photon)
#
# Entrada : cache/voting_places_unique.csv  (268 locais unicos de Campinas)
# Saidas  : cache/geocode_result.csv        (lon, lat, metodo, osm_id, ...)
#           cache/geocode_cache.rds         (cache incremental, resumavel)
#
# Regras (prompt §7 Passo 4):
#   - Photon https://photon.komoot.io/api/?q=<urlenc>&limit=1&lang=default&bbox=...
#     lang=pt NAO e suportado
#   - bbox Campinas: -47.30,-23.13,-46.76,-22.67
#   - maximo 1,5 req/s (gap minimo 0,70 s), backoff 1,5*k s no retry
#   - cache incremental a cada 25 registros
#   - resultado fora do bbox e descartado (motivo "fora_bbox")
#   - fallback: query completa -> so o endereco -> NA (nunca fabricar coordenada)
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(data.table)
  library(jsonlite)
})

a <- commandArgs(trailingOnly = FALSE)
f <- sub("^--file=", "", a[grep("^--file=", a)])
WORKDIR <- if (length(f)) { d <- dirname(f); if (basename(d) == "scripts") dirname(d) else d } else getwd()
setwd(WORKDIR)
dir.create("cache", showWarnings = FALSE)

PLACES <- "cache/voting_places_unique.csv"
CACHE  <- "cache/geocode_cache.rds"
OUT    <- "cache/geocode_result.csv"

RATE <- 1.5; GAP <- 1 / RATE; MAXTRY <- 3L; N_SAVE <- 25L

BBOX <- "-47.30,-23.13,-46.76,-22.67"
LON_MIN <- -47.30; LON_MAX <- -46.76; LAT_MIN <- -23.13; LAT_MAX <- -22.67

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1 && is.na(a))) b else a

photon <- function(q) {
  qenc <- utils::URLencode(q, reserved = TRUE)
  url <- sprintf("https://photon.komoot.io/api/?q=%s&limit=1&lang=default&bbox=%s", qenc, BBOX)
  for (k in seq_len(MAXTRY)) {
    out <- suppressWarnings(tryCatch(
      system2("curl", args = c("-s", "--max-time", "20", "--retry", "1", url),
              stdout = TRUE, stderr = FALSE),
      error = function(e) NULL))
    if (is.null(out)) { Sys.sleep(1.5 * k); next }
    st <- attr(out, "status")
    if (!is.null(st) && st != 0) { Sys.sleep(1.5 * k); next }
    txt <- paste(out, collapse = "")
    if (!nzchar(trimws(txt))) { Sys.sleep(1.5 * k); next }
    j <- tryCatch(fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(j)) { Sys.sleep(1.5 * k); next }
    if (!is.null(j$features) && length(j$features) > 0) {
      f1 <- j$features[[1]]
      co <- f1$geometry$coordinates
      if (length(co) >= 2 && is.numeric(co[[1]]) && is.numeric(co[[2]])) {
        lon <- as.numeric(co[[1]]); lat <- as.numeric(co[[2]])
        if (is.finite(lon) && is.finite(lat) &&
            lon >= LON_MIN && lon <= LON_MAX && lat >= LAT_MIN && lat <= LAT_MAX) {
          p <- f1$properties
          return(list(ok = TRUE, lon = lon, lat = lat,
                      osm_type = as.character(p$osm_type %||% NA_character_),
                      osm_id   = as.character(p$osm_id %||% NA_character_),
                      nome_osm = as.character(p$name %||% NA_character_),
                      street   = as.character(p$street %||% NA_character_),
                      housenr  = as.character(p$housenumber %||% NA_character_),
                      bairro   = as.character((p$locality %||% p$district) %||% NA_character_),
                      city     = as.character(p$city %||% NA_character_)))
        }
      }
      return(list(ok = FALSE, reason = "fora_bbox"))
    }
    return(list(ok = FALSE, reason = "sem_resultado"))
  }
  list(ok = FALSE, reason = "erro_rede")
}

last_time <- 0
throttle <- function() {
  now <- as.numeric(Sys.time()); dt <- now - last_time
  if (dt < GAP) Sys.sleep(GAP - dt)
  last_time <<- as.numeric(Sys.time())
}

places <- fread(PLACES, colClasses = "character", encoding = "UTF-8")
cat("Locais unicos:", nrow(places), "\n")

store <- if (file.exists(CACHE)) readRDS(CACHE) else list()
cat("Cache carregado:", length(store), "registros\n")

keys <- paste(places$NR_ZONA, places$NM_CLEAN, places$ADDR_CLEAN, sep = " ||| ")
todo <- which(!(keys %in% names(store)))
cat("A geocodificar:", length(todo), "\n\n")

t0 <- Sys.time()
for (i in seq_along(todo)) {
  r <- todo[i]; k <- keys[r]
  nm <- places$NM_CLEAN[r]; ad <- places$ADDR_CLEAN[r]

  throttle()
  g <- photon(paste(nm, ad, "CAMPINAS, SP, BRASIL", sep = ", "))
  metodo <- "completa"

  if (!isTRUE(g$ok) && !identical(g$reason, "erro_rede")) {
    throttle()
    g2 <- photon(paste(ad, "CAMPINAS, SP, BRASIL", sep = ", "))
    metodo <- "endereco"
    if (isTRUE(g2$ok)) g <- g2 else if (identical(g2$reason, g$reason)) g$reason <- g2$reason
  }

  store[[k]] <- if (isTRUE(g$ok)) {
    list(ok = TRUE, lon = g$lon, lat = g$lat, metodo = metodo,
         osm_type = g$osm_type, osm_id = g$osm_id, nome_osm = g$nome_osm,
         street = g$street, housenumber = g$housenr, bairro = g$bairro, city = g$city)
  } else {
    list(ok = FALSE, lon = NA_real_, lat = NA_real_, metodo = NA_character_, motivo = g$reason)
  }

  if (i %% N_SAVE == 0) {
    saveRDS(store, CACHE)
    el <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
    cat(sprintf("[%s] %d/%d  %.1f%%  %.2f s/local  eta %.1f min\n",
                format(Sys.time(), "%H:%M:%S"), i, length(todo), 100 * i / length(todo),
                el / i, (length(todo) - i) * el / i / 60))
    flush.console()
  }
}
saveRDS(store, CACHE)

tab <- rbindlist(lapply(seq_len(nrow(places)), function(r) {
  s <- store[[keys[r]]]
  if (is.null(s)) s <- list(ok = FALSE, motivo = "nao_processado")
  data.table(ok = isTRUE(s$ok),
             lon = as.numeric(s$lon %||% NA_real_),
             lat = as.numeric(s$lat %||% NA_real_),
             metodo = as.character(s$metodo %||% NA_character_),
             osm_type = as.character(s$osm_type %||% NA_character_),
             osm_id = as.character(s$osm_id %||% NA_character_),
             nome_osm = as.character(s$nome_osm %||% NA_character_),
             street = as.character(s$street %||% NA_character_),
             housenumber = as.character(s$housenumber %||% NA_character_),
             bairro = as.character(s$bairro %||% NA_character_),
             city = as.character(s$city %||% NA_character_),
             motivo = as.character(s$motivo %||% NA_character_))
}), fill = TRUE)

out <- cbind(places[, .(id_local, NR_ZONA, NM_CLEAN, ADDR_CLEAN)], tab)
fwrite(out, OUT, na = "")

cat("\n=== RESULTADO GEOCODIFICACAO ===\n")
cat("Total locais            :", nrow(out), "\n")
cat("Geocodificados (ok)     :", sum(out$ok), "\n")
cat("Nao geocodificados (NA) :", sum(!out$ok), "\n")
cat(sprintf("Cobertura               : %.2f%%\n", 100 * mean(out$ok)))
if (any(!out$ok)) print(out[ok == FALSE, .N, by = motivo])
print(out[ok == TRUE, .N, by = metodo])
cat("Min/max lon:", range(out$lon, na.rm = TRUE), "\n")
cat("Min/max lat:", range(out$lat, na.rm = TRUE), "\n")
cat("FIM PASSO 4\n")
