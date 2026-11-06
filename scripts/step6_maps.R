#!/usr/bin/env Rscript
# ---------------------------------------------------------------------------
# PASSO 6 - GERAR OS DOIS MAPAS HTML + A LANDING PAGE
#
# Entradas: data/campinas_utb.gpkg
#           output/campinas_presidente_2t.csv
#           output/campinas_governador_1t.csv
#           cache/step5_stats.rds
# Saidas  : campinas_presidente_2t.html
#           campinas_governador_1t.html
#           index.html
#
# Regras (prompt §5.2, §7 Passo 6/7, §8.9):
#   - GeoJSON embutido, simplificado em EPSG:4674 (dTolerance 1e-5), HTML < 5 MB
#   - Leaflet 1.9.4 (unpkg) com preferCanvas
#   - basemap Esri World Imagery
#   - cor = margem assinada em pp; 1o colocado no municipio = azul #1f5fbf,
#     2o = vermelho #d92b2b, empate = #e6e6e6
#   - legenda colapsavel, tooltip, rodape, nota de metodo
#   - hooks: window.__feats / __mapLayer / __corMargem / __MAX_PP
# ---------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(data.table)
  library(sf)
  library(jsonlite)
})

a <- commandArgs(trailingOnly = FALSE)
f <- sub("^--file=", "", a[grep("^--file=", a)])
WORKDIR <- if (length(f)) { d <- dirname(f); if (basename(d) == "scripts") dirname(d) else d } else getwd()
setwd(WORKDIR)

AZUL <- "#1f5fbf"; AZUL_L <- "#dce6f7"
VERM <- "#d92b2b"; VERM_L <- "#f8dedb"
NEUTRO <- "#e6e6e6"
LIMIAR <- 0.05

fmt_int <- function(x) formatC(as.integer(round(x)), big.mark = ".", decimal.mark = ",", format = "d")
fmt_pct <- function(x) sub("\\.", ",", sprintf("%.2f", 100 * x))
fmt_pp  <- function(x) sprintf("%s%.2f", ifelse(x > 0, "+", ifelse(x < 0, "\u2212", "")), abs(x))
primeiro <- function(x) strsplit(x, " ")[[1]][1]
js_str <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE))

# substituicao por token: evita o inferno de %% do sprintf em CSS/JS
render <- function(tpl, vars) {
  for (k in names(vars)) tpl <- gsub(paste0("@@", k, "@@"), vars[[k]], tpl, fixed = TRUE)
  resto <- regmatches(tpl, gregexpr("@@[A-Z0-9_]+@@", tpl))[[1]]
  if (length(resto)) stop("tokens nao substituidos: ", paste(unique(resto), collapse = ", "))
  tpl
}

# --- geometria simplificada -------------------------------------------------
utb <- st_read("data/campinas_utb.gpkg", quiet = TRUE)
utb_s <- st_simplify(utb[, "CD_UTB"], dTolerance = 1e-5, preserveTopology = TRUE)
cat("Vertices antes:", sum(sapply(st_geometry(utb), function(g) length(unlist(g)))),
    "| depois:", sum(sapply(st_geometry(utb_s), function(g) length(unlist(g)))), "\n")

geojson_de <- function(dt) {
  g <- merge(utb_s, dt, by = "CD_UTB")
  g <- g[match(dt$CD_UTB, g$CD_UTB), ]
  tmp <- tempfile(fileext = ".geojson")
  st_write(g, tmp, driver = "GeoJSON", quiet = TRUE, delete_dsn = TRUE,
           layer_options = "COORDINATE_PRECISION=6")
  txt <- paste(readLines(tmp, warn = FALSE), collapse = "")
  unlink(tmp)
  txt
}

# --- template do mapa -------------------------------------------------------
TPL_MAPA <- readLines(textConnection('<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1.0"/>
<title>@@TITULO@@</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
<style>
  html,body{width:100%;height:100%;margin:0;padding:0;font-family:Helvetica,Arial,sans-serif;}
  #map{position:absolute;top:0;bottom:0;right:0;left:0;background:#eef0f2;}
  .painel{position:fixed;z-index:9999;background:#fff;border:1px solid #bbb;border-radius:4px;
          box-shadow:0 1px 6px rgba(0,0,0,.3);font-size:13px;}
  #cabecalho{top:12px;left:12px;padding:10px 14px;line-height:1.5;max-width:370px;}
  #cabecalho h1{margin:0;font-size:15px;font-weight:bold;}
  #cabecalho .sub{font-size:12px;color:#555;margin-top:3px;}
  .colapsavel{display:flex;justify-content:space-between;align-items:center;gap:12px;
              cursor:pointer;user-select:none;font-weight:bold;font-size:13px;margin-top:8px;
              border-top:1px solid #eee;padding-top:7px;}
  #corpo-legenda{margin-top:6px;}
  #corpo-legenda.fechada{display:none;}
  .legenda-linha{display:flex;align-items:center;gap:6px;margin:3px 0;font-size:12px;}
  .swatch{display:inline-block;width:12px;height:12px;border:1px solid #333;flex:none;}
  .barra-grad{height:12px;border:1px solid #333;margin:8px 0 2px;
              background:linear-gradient(to right,@@VERM_L@@,@@NEUTRO@@,@@AZUL_L@@);}
  .eixos{display:flex;justify-content:space-between;font-size:10px;color:#444;}
  #rodape{bottom:14px;left:12px;right:12px;padding:8px 12px;font-size:12px;color:#444;line-height:1.5;}
  #rodape .metodo{color:#666;font-size:11px;margin-top:3px;}
  .foliumtooltip{background:#fff;border:1px solid #999;font-size:12px;padding:6px 9px;
                 border-radius:3px;line-height:1.55;box-shadow:0 1px 4px rgba(0,0,0,.25);}
  .leaflet-container{font-size:1rem;}
  @media (max-width:620px){
    #cabecalho{max-width:calc(100% - 24px);}
    #rodape{font-size:11px;}
  }
</style>
</head>
<body>
<div id="map"></div>

<div id="cabecalho" class="painel">
  <h1>@@TITULO@@</h1>
  <div class="sub">@@SUBTITULO@@</div>
  <div class="colapsavel" id="colapso-legenda"><span>Legenda</span><span class="seta">&#9662;</span></div>
  <div id="corpo-legenda">
    <div class="legenda-linha"><span class="swatch" style="background:@@AZUL@@"></span> @@C1N@@@@C1P@@ &mdash; <span id="n-1"></span> bairros</div>
    <div class="legenda-linha"><span class="swatch" style="background:@@VERM@@"></span> @@C2N@@@@C2P@@ &mdash; <span id="n-2"></span> bairros</div>
    <div class="legenda-linha"><span class="swatch" style="background:@@NEUTRO@@"></span> Empate (|margem| &lt; 0,05 pp)</div>@@LINHA_SEM@@
    <div class="barra-grad"></div>
    <div class="eixos"><span id="eixo-min"></span><span>0</span><span id="eixo-max"></span></div>
    <div style="color:#666;font-size:11px;margin-top:6px;border-top:1px solid #ddd;padding-top:5px">Passe o mouse para ver os n&uacute;meros &middot; clique para dar zoom</div>
  </div>
</div>

<div id="rodape" class="painel"><span id="rodape-txt"></span>
  <div class="metodo">Se&ccedil;&otilde;es agregadas por geocodifica&ccedil;&atilde;o do local de vota&ccedil;&atilde;o + ponto-em-pol&iacute;gono na UTB/UTR (Prefeitura de Campinas). &ldquo;Bairro&rdquo; aqui &eacute; a UTB/UTR oficial &mdash; Campinas n&atilde;o possui malha de bairros do IBGE.</div>
</div>

<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<script>
const GEOJSON = @@GEOJSON@@;
const NOME_1 = @@NOME1_JS@@, PART_1 = @@PART1_JS@@;
const NOME_2 = @@NOME2_JS@@, PART_2 = @@PART2_JS@@;
const COR_1 = {"strong":"@@AZUL@@", "light":"@@AZUL_L@@"};
const COR_2 = {"strong":"@@VERM@@", "light":"@@VERM_L@@"};
const NEUTRAL = "@@NEUTRO@@";
const LIMIAR_EMPATE = 0.05;

function lerp(c1, c2, t) {
  const a = parseInt(c1.slice(1), 16), b = parseInt(c2.slice(1), 16);
  const ch = i => {
    const sa = (a >>> (16 - 8 * i)) & 255, sb = (b >>> (16 - 8 * i)) & 255;
    return Math.round(sa + (sb - sa) * t).toString(16).padStart(2, "0");
  };
  return "#" + ch(0) + ch(1) + ch(2);
}
const feats = GEOJSON.features;
let MAX_PP = 0;
for (const f of feats) { const a = Math.abs(f.properties.margem_pp); if (a > MAX_PP) MAX_PP = a; }

function corMargem(pp) {
  if (pp == null || Number.isNaN(pp)) return NEUTRAL;
  const a = Math.abs(pp);
  if (a < LIMIAR_EMPATE) return NEUTRAL;
  const t = Math.min(1, a / MAX_PP);
  return pp > 0 ? lerp(COR_1.light, COR_1.strong, t) : lerp(COR_2.light, COR_2.strong, t);
}
function fmtInt(n) { return (n == null ? 0 : n).toLocaleString("pt-BR"); }
function fmtPct(x) { return x == null ? "&mdash;" : (100 * x).toFixed(2).replace(".", ","); }
function fmtPp(pp) { const s = pp > 0 ? "+" : (pp < 0 ? "\\u2212" : ""); return s + Math.abs(pp).toFixed(2).replace(".", ",") + " pp"; }

const map = L.map("map", {preferCanvas: true, zoomControl: true});
L.tileLayer("https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}", {
  attribution: "Tiles &copy; Esri &mdash; Source: Esri, Maxar, Earthstar Geographics, and the GIS User Community",
  maxZoom: 19
}).addTo(map);

const camada = L.geoJSON(GEOJSON, {
  style: f => ({color: "#ffffff", weight: 0.8, fillColor: corMargem(f.properties.margem_pp), fillOpacity: 0.85}),
  onEachFeature: (f, l) => {
    const p = f.properties;
    l.on({
      mouseover: e => e.target.setStyle({color: "#333333", weight: 1.6, fillOpacity: 0.95}),
      mouseout:  e => camada.resetStyle(e.target),
      click:     e => map.fitBounds(e.target.getBounds())
    });
    l.bindTooltip(function () {
      const cor = p.margem_pp > LIMIAR_EMPATE ? COR_1.strong
                : p.margem_pp < -LIMIAR_EMPATE ? COR_2.strong : NEUTRAL;
      const venc = p.vencedor === "EMPATE" ? "Empate"
                 : p.vencedor + (p.partido ? " (" + p.partido + ")" : "");
      return "<div style=\\"line-height:1.5\\"><b>" + p.NM_UTB + "</b> <span style=\\"color:#888;font-size:11px\\">" + p.CD_UTB + "</span><br>" +
        "<span style=\\"display:inline-block;width:10px;height:10px;background:" + cor +
        ";border:1px solid #333\\"></span> <b>" + venc + "</b><br>" +
        NOME_1 + ": " + fmtInt(p.votos_1) + " votos &middot; " + fmtPct(p.pct_1) + "%<br>" +
        NOME_2 + ": " + fmtInt(p.votos_2) + " votos &middot; " + fmtPct(p.pct_2) + "%<br>" +
        "<b>Margem: " + fmtPp(p.margem_pp) + " &middot; " + fmtInt(p.margem_votos) + " votos</b><br>" +
        "<span style=\\"color:#666\\">Votos v&aacute;lidos: " + fmtInt(p.votos_validos) +
        " &middot; " + p.n_secoes + " se&ccedil;&otilde;es em " + p.n_locais + " locais</span></div>";
    }, {sticky: true, className: "foliumtooltip"});
  }
}).addTo(map);
map.fitBounds(camada.getBounds());

let n1 = 0, n2 = 0, n0 = 0, s1 = 0, s2 = 0, sv = 0;
for (const f of feats) {
  const p = f.properties;
  if (p.margem_pp > LIMIAR_EMPATE) n1++;
  else if (p.margem_pp < -LIMIAR_EMPATE) n2++;
  else if (p.votos_validos > 0) n0++;
  if (p.n_secoes > 0) {
    s1 += p.votos_1; s2 += p.votos_2; sv += p.votos_validos;
  }
}
document.getElementById("n-1").textContent = n1;
document.getElementById("n-2").textContent = n2;
document.getElementById("eixo-min").textContent = NOME_2.split(" ")[0] + " \\u2212" + MAX_PP.toFixed(0);
document.getElementById("eixo-max").textContent = NOME_1.split(" ")[0] + " +" + MAX_PP.toFixed(0);
document.getElementById("rodape-txt").innerHTML =
  fmtInt(sv) + " votos v&aacute;lidos &middot; " + NOME_1 + " " + fmtPct(s1 / sv) + "% &middot; " +
  NOME_2 + " " + fmtPct(s2 / sv) + "% &middot; Fonte: TSE";

document.getElementById("colapso-legenda").addEventListener("click", function () {
  const corpo = document.getElementById("corpo-legenda");
  const aberto = corpo.style.display !== "none";
  corpo.style.display = aberto ? "none" : "";
  this.querySelector(".seta").textContent = aberto ? "\\u25b8" : "\\u25be";
});

// QA hooks
window.__mapLayer = camada;
window.__feats = feats;
window.__corMargem = corMargem;
window.__MAX_PP = MAX_PP;
window.__totais = {votos_validos: sv, votos_1: s1, votos_2: s2, n1: n1, n2: n2, n0: n0};
</script>
</body>
</html>'), warn = FALSE)

mapa_html <- function(dt, titulo, subtitulo, nome_arquivo) {
  stopifnot(nrow(dt) == 93L)
  c1n <- unique(dt$venc_1_nome); c1p_raw <- unique(dt$venc_1_partido)
  c2n <- unique(dt$venc_2_nome); c2p_raw <- unique(dt$venc_2_partido)
  stopifnot(length(c1n) == 1L, length(c2n) == 1L)
  c1p_raw <- if (length(c1p_raw) == 1L && !is.na(c1p_raw)) c1p_raw else ""
  c2p_raw <- if (length(c2p_raw) == 1L && !is.na(c2p_raw)) c2p_raw else ""
  c1p <- if (nzchar(c1p_raw)) paste0(" (", c1p_raw, ")") else ""
  c2p <- if (nzchar(c2p_raw)) paste0(" (", c2p_raw, ")") else ""

  n1 <- sum(dt$margem_pp > LIMIAR, na.rm = TRUE)
  n2 <- sum(dt$margem_pp < -LIMIAR, na.rm = TRUE)
  n0 <- sum(abs(dt$margem_pp) <= LIMIAR & dt$votos_validos > 0, na.rm = TRUE)
  n_sem <- sum(dt$votos_validos == 0)

  sem_linha <- if (n_sem > 0)
    sprintf('<div class="legenda-linha"><span class="swatch" style="background:#9aa0a6"></span> Sem se&ccedil;&atilde;o atribu&iacute;da &mdash; %d</div>', n_sem) else ""

  html <- render(TPL_MAPA, list(
    TITULO = titulo, SUBTITULO = subtitulo,
    AZUL = AZUL, AZUL_L = AZUL_L, VERM = VERM, VERM_L = VERM_L, NEUTRO = NEUTRO,
    C1N = c1n, C1P = c1p, C2N = c2n, C2P = c2p, LINHA_SEM = sem_linha,
    GEOJSON = geojson_de(dt),
    NOME1_JS = js_str(c1n), PART1_JS = js_str(c1p_raw),
    NOME2_JS = js_str(c2n), PART2_JS = js_str(c2p_raw)
  ))

  writeLines(html, nome_arquivo, useBytes = TRUE)
  cat(sprintf("escreveu %s (%.2f MB) | %s %d x %s %d | empates %d | sem secao %d\n",
              nome_arquivo, file.size(nome_arquivo) / 1e6, c1n, n1, c2n, n2, n0, n_sem))
  invisible(list(n1 = n1, n2 = n2, n0 = n0, n_sem = n_sem,
                 tot_val = sum(dt$votos_validos), tot_1 = sum(dt$votos_1),
                 tot_2 = sum(dt$votos_2), maxpp = max(abs(dt$margem_pp[dt$votos_validos > 0])),
                 c1n = c1n, c1p = c1p_raw, c2n = c2n, c2p = c2p_raw))
}

# --- carrega resultados -----------------------------------------------------
pres <- fread("output/campinas_presidente_2t.csv", encoding = "UTF-8")
gov  <- fread("output/campinas_governador_1t.csv",  encoding = "UTF-8")
stopifnot(nrow(pres) == 93L, nrow(gov) == 93L)

s3 <- readRDS("cache/step5_stats.rds")
pres[, `:=`(venc_1_nome = s3$pres$cand1, venc_2_nome = s3$pres$cand2,
            venc_1_partido = s3$pres$part1, venc_2_partido = s3$pres$part2)]
gov[,  `:=`(venc_1_nome = s3$gov$cand1, venc_2_nome = s3$gov$cand2,
            venc_1_partido = s3$gov$part1, venc_2_partido = s3$gov$part2)]

r_pres <- mapa_html(pres,
  "Presidente 2026 — Campinas, 2º turno",
  "Vencedor por bairro (UTB/UTR) · cor pela margem de vitória em pontos percentuais (pp)",
  "campinas_presidente_2t.html")

r_gov <- mapa_html(gov,
  "Governador 2026 — Campinas, 1º turno",
  "Vencedor por bairro (UTB/UTR) · cor pela margem de vitória em pontos percentuais (pp)",
  "campinas_governador_1t.html")

# --- landing page -----------------------------------------------------------
extremos <- function(dt) {
  d <- dt[votos_validos > 0]
  list(max_pos = d[which.max(margem_pp)], max_neg = d[which.min(margem_pp)])
}
ep <- extremos(pres); eg <- extremos(gov)

bloco_placar <- function(r) {
  e <- ""
  if (r$n0 > 0) e <- sprintf('<li><span class="nome" style="color:var(--ink2)">Empate</span><span class="lider" aria-hidden="true"></span><span class="val">%d</span></li>', r$n0)
  paste0(
    '<li><span class="azul-dot" aria-hidden="true"></span><span class="nome">', r$c1n,
    ' <span class="pfx">· ', r$c1p, '</span></span><span class="lider" aria-hidden="true"></span><span class="val">', r$n1, '</span></li>\n',
    '        <li><span class="verm-dot" aria-hidden="true"></span><span class="nome">', r$c2n,
    ' <span class="pfx">· ', r$c2p, '</span></span><span class="lider" aria-hidden="true"></span><span class="val">', r$n2, '</span></li>\n',
    '        ', e)
}
frase_empate <- function(r) if (r$n0 > 0) sprintf(" Houve %d empate(s) técnico(s).", r$n0) else " Não houve nenhum bairro em empate."

tpl_landing <- readLines(textConnection('<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Campinas, bairro a bairro — Eleições 2026</title>
<meta name="description" content="Votação de 2026 em Campinas agregada aos bairros (UTB/UTR) da Prefeitura: Presidente no 2º turno e Governador no 1º turno, com o vencedor de cada bairro colorido pela margem de vitória.">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Archivo:wght@400;500;600;700&family=Fraunces:ital,opsz,wght@0,9..144,400;0,9..144,600;1,9..144,400&display=swap" rel="stylesheet">
<style>
  :root{
    --panel:#07090C; --ink:#F2EFE9; --dim:#AAAAA5; --accent:#FFB22C;
    --rule:#1E2228; --rule2:rgba(255,255,255,0.12);
    --azul:#1f5fbf; --verm:#d92b2b;
    --serif:\'Fraunces\',Georgia,\'Times New Roman\',serif;
    --sans:\'Archivo\',\'Helvetica Neue\',Helvetica,Arial,sans-serif;
    --max:1180px;
  }
  *{box-sizing:border-box}
  html{-webkit-text-size-adjust:100%}
  body{margin:0;background:var(--panel);color:var(--ink);font-family:var(--sans);
    font-size:16px;line-height:1.5;-webkit-font-smoothing:antialiased;text-rendering:optimizeLegibility;}
  a{color:inherit}
  .wrap{max-width:var(--max);margin:0 auto;padding:0 clamp(18px,4vw,40px)}
  .topo{border-bottom:1px solid var(--rule);background:
      radial-gradient(120% 90% at 12% 0%,rgba(255,178,44,.06),transparent 55%),
      radial-gradient(120% 90% at 92% 8%,rgba(31,95,191,.08),transparent 55%);}
  .topo .wrap{padding-top:clamp(46px,9vh,104px);padding-bottom:clamp(28px,6vh,56px)}
  .kicker{display:inline-flex;align-items:center;gap:.6em;font-size:12px;font-weight:600;
    letter-spacing:.18em;text-transform:uppercase;color:var(--accent);}
  .kicker::before{content:"";width:26px;height:1px;background:var(--rule2)}
  h1{font-family:var(--serif);font-weight:600;font-size:clamp(38px,7.2vw,86px);line-height:.98;
    letter-spacing:-.022em;margin:.34em 0 .34em;max-width:16ch;color:var(--ink)}
  h1 em{font-style:italic;font-weight:400;color:var(--dim)}
  .deck{max-width:60ch;font-size:clamp(16.5px,1.55vw,20px);line-height:1.62;color:var(--dim);margin:0}
  .fichas{display:flex;flex-wrap:wrap;gap:10px;margin:clamp(24px,4vh,40px) 0 0;padding:0;list-style:none}
  .fichas li{border:1px solid var(--rule);border-radius:999px;padding:8px 15px;font-size:13px;
    font-weight:500;letter-spacing:.01em;background:rgba(255,255,255,0.04);color:var(--dim);font-variant-numeric:tabular-nums;}
  .fichas b{font-weight:700;color:var(--ink);font-variant-numeric:tabular-nums}
  .nav{position:sticky;top:0;z-index:20;background:rgba(7,9,12,0.9);
    -webkit-backdrop-filter:saturate(140%) blur(9px);backdrop-filter:saturate(140%) blur(9px);
    border-bottom:1px solid var(--rule)}
  .nav .wrap{display:flex;align-items:center;gap:8px;padding-top:10px;padding-bottom:10px;overflow-x:auto}
  .nav-rot{font-size:12px;font-weight:600;letter-spacing:.16em;text-transform:uppercase;color:var(--dim);white-space:nowrap;margin-right:6px}
  .nav a{text-decoration:none;white-space:nowrap;font-size:13.5px;font-weight:600;border:1px solid var(--rule);
    border-radius:999px;padding:7px 14px;color:var(--dim);transition:background .18s ease,color .18s ease,border-color .18s ease;}
  .nav a:hover{background:var(--accent);color:var(--panel);border-color:var(--accent)}
  .bloco{margin:clamp(46px,8vh,86px) 0}
  .bloco-cabeca{display:grid;grid-template-columns:minmax(0,1fr) auto;gap:clamp(18px,4vw,48px);
    align-items:end;border-top:2px solid var(--accent);padding-top:18px;}
  .eyebrow{font-size:11.5px;font-weight:700;letter-spacing:.2em;text-transform:uppercase;color:var(--accent)}
  h2{font-family:var(--serif);font-weight:600;font-size:clamp(27px,4.2vw,46px);line-height:1.02;
    letter-spacing:-.018em;margin:.28em 0 .3em;color:var(--ink)}
  .resumo{margin:0;max-width:52ch;color:var(--dim);font-size:15.5px;line-height:1.6}
  .placar{margin:0;padding:0;list-style:none;min-width:min(320px,100%)}
  .placar li{display:flex;align-items:baseline;gap:.6em;font-size:14.5px;padding:7px 0;border-bottom:1px solid var(--rule);color:var(--dim)}
  .placar li:last-child{border-bottom:0}
  .placar .nome{font-weight:600;color:var(--ink)}
  .placar .pfx{font-size:11.5px;letter-spacing:.08em;text-transform:uppercase;color:var(--dim)}
  .placar .azul-dot,.placar .verm-dot{width:9px;height:9px;border-radius:50%;flex:none;align-self:center}
  .placar .azul-dot{background:var(--azul)}
  .placar .verm-dot{background:var(--verm)}
  .placar .lider{flex:1;border-bottom:1px dotted var(--rule);transform:translateY(-.28em)}
  .placar .val{font-weight:700;color:var(--ink);font-variant-numeric:tabular-nums;letter-spacing:-.01em}
  .mapa{margin-top:22px;border:1px solid var(--rule);border-radius:16px;overflow:hidden;
    background:var(--panel);box-shadow:0 26px 64px -34px rgba(0,0,0,.85)}
  .mapa-barra{display:flex;align-items:center;justify-content:space-between;gap:14px;
    padding:10px 15px;background:#12161D;color:var(--ink);font-size:12.5px;letter-spacing:.02em;border-bottom:1px solid var(--rule)}
  .mapa-barra .rot{display:inline-flex;align-items:center;gap:9px;font-weight:600;text-transform:uppercase;letter-spacing:.14em;font-size:11px;color:var(--dim)}
  .mapa-barra .rot::before{content:"";width:7px;height:7px;border-radius:50%;background:var(--accent);box-shadow:0 0 0 3px rgba(255,178,44,.22)}
  .mapa-barra a{text-decoration:none;border-bottom:1px solid rgba(242,239,233,.5);padding-bottom:1px;white-space:nowrap;color:var(--ink)}
  .mapa-barra a:hover{border-bottom-color:var(--accent);color:var(--accent)}
  .frame{position:relative;aspect-ratio:16/10;min-height:540px;background:#12161D}
  .frame iframe{position:absolute;inset:0;width:100%;height:100%;border:0;display:block}
  .aviso{margin:10px 2px 0;font-size:12.5px;color:var(--dim)}
  .aviso code{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:12px;
    background:rgba(255,255,255,.07);color:var(--ink);padding:1.5px 5px;border-radius:5px}
  .rodape{margin-top:clamp(56px,10vh,110px);border-top:1px solid var(--rule);background:#040507}
  .rodape .wrap{padding-top:clamp(30px,5vh,52px);padding-bottom:clamp(34px,6vh,60px);
    display:grid;grid-template-columns:repeat(auto-fit,minmax(258px,1fr));gap:clamp(20px,4vw,44px)}
  .rodape h3{font-size:11.5px;font-weight:700;letter-spacing:.2em;text-transform:uppercase;color:var(--accent);margin:0 0 .7em}
  .rodape p{margin:0;font-size:14px;line-height:1.62;color:var(--dim)}
  .rodape ul{margin:0;padding-left:1.05em;font-size:14px;line-height:1.62;color:var(--dim)}
  .rodape li+li{margin-top:.35em}
  .rodape .lnk{display:inline-block;margin-top:.7em;font-weight:600;color:var(--ink);text-decoration:none;border-bottom:1px solid var(--rule)}
  .rodape .lnk:hover{color:var(--accent);border-bottom-color:var(--accent)}
  .placar li:last-child{border-bottom:0}
  .placar .nome{font-weight:600}
  .placar .pfx{font-size:11.5px;letter-spacing:.08em;text-transform:uppercase;color:var(--ink2)}
  .placar .azul-dot,.placar .verm-dot{width:9px;height:9px;border-radius:50%;flex:none;align-self:center}
  .placar .azul-dot{background:var(--azul)}
  .placar .verm-dot{background:var(--verm)}
  .placar .lider{flex:1;border-bottom:1px dotted var(--rule2);transform:translateY(-.28em)}
  .placar .val{font-weight:700;font-variant-numeric:tabular-nums;letter-spacing:-.01em}
  .mapa{margin-top:22px;border:1px solid var(--rule2);border-radius:16px;overflow:hidden;
    background:#dfe3e6;box-shadow:0 26px 64px -34px rgba(22,19,15,.55)}
  .mapa-barra{display:flex;align-items:center;justify-content:space-between;gap:14px;
    padding:10px 15px;background:var(--ink);color:var(--paper);font-size:12.5px;letter-spacing:.02em;}
  .mapa-barra .rot{display:inline-flex;align-items:center;gap:9px;font-weight:600;text-transform:uppercase;letter-spacing:.14em;font-size:11px}
  .mapa-barra .rot::before{content:"";width:7px;height:7px;border-radius:50%;background:var(--verm);box-shadow:0 0 0 3px rgba(217,43,43,.22)}
  .mapa-barra a{text-decoration:none;border-bottom:1px solid rgba(241,236,225,.5);padding-bottom:1px;white-space:nowrap}
  .mapa-barra a:hover{border-bottom-color:var(--paper)}
  .frame{position:relative;aspect-ratio:16/10;min-height:540px;background:#dfe3e6}
  .frame iframe{position:absolute;inset:0;width:100%;height:100%;border:0;display:block}
  .aviso{margin:10px 2px 0;font-size:12.5px;color:var(--ink2)}
  .aviso code{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:12px;
    background:rgba(22,19,15,.07);padding:1.5px 5px;border-radius:5px}
  .rodape{margin-top:clamp(56px,10vh,110px);border-top:1px solid var(--rule2);background:var(--paper2)}
  .rodape .wrap{padding-top:clamp(30px,5vh,52px);padding-bottom:clamp(34px,6vh,60px);
    display:grid;grid-template-columns:repeat(auto-fit,minmax(258px,1fr));gap:clamp(20px,4vw,44px)}
  .rodape h3{font-size:11.5px;font-weight:700;letter-spacing:.2em;text-transform:uppercase;color:var(--ink2);margin:0 0 .7em}
  .rodape p{margin:0;font-size:14px;line-height:1.62;color:var(--ink2)}
  .rodape ul{margin:0;padding-left:1.05em;font-size:14px;line-height:1.62;color:var(--ink2)}
  .rodape li+li{margin-top:.35em}
  .rodape .lnk{display:inline-block;margin-top:.7em;font-weight:600;color:var(--ink);text-decoration:none;border-bottom:1px solid var(--rule2)}
  @media (max-width:760px){
    .bloco-cabeca{grid-template-columns:1fr}
    .placar{min-width:0;margin-top:6px}
    .frame{aspect-ratio:4/5;min-height:0}
  }
  @media (prefers-reduced-motion:reduce){*{transition:none !important}}
</style>
</head>
<body>

<header class="topo">
  <div class="wrap">
    <span class="kicker">Eleições 2026 · Campinas (SP) · 1º e 2º turnos</span>
    <h1>Campinas votou <em>bairro a bairro</em>.</h1>
    <p class="deck">A votação de 2026 em Campinas, agregada das seções do TSE aos <b>93 bairros (UTB/UTR)</b> da Prefeitura por geocodificação do local de votação e sobreposição espacial. Dois recortes — <b>Presidente no 2º turno</b> e <b>Governador no 1º turno</b> — com o vencedor de cada bairro colorido pela margem de vitória em pontos percentuais.</p>
    <ul class="fichas">
      <li><b>93</b> bairros (UTB/UTR)</li>
      <li><b>@@TOT_PRES@@</b> votos válidos · Presidente 2º turno</li>
      <li><b>@@TOT_GOV@@</b> votos válidos · Governador 1º turno</li>
      <li><b>268</b> locais de votação · 7 zonas</li>
    </ul>
  </div>
</header>

<nav class="nav" aria-label="Seções">
  <div class="wrap">
    <span class="nav-rot">Ir para</span>
    <a href="#presidente">Presidente (2º turno)</a>
    <a href="#governador">Governador (1º turno)</a>
    <a href="#metodo">Método e fonte</a>
  </div>
</nav>

<main class="wrap">

  <section class="bloco" id="presidente" aria-labelledby="t-presidente">
    <div class="bloco-cabeca">
      <div>
        <span class="eyebrow">Mapa 01 · Presidente · 2º turno</span>
        <h2 id="t-presidente">@@PRES_TITULO@@</h2>
        <p class="resumo">No 2º turno presidencial, a maior margem pró-@@PRES_P1@@ aparece em <b>@@PRES_MAXPOS_UTB@@ (@@PRES_MAXPOS_PP@@ pp)</b>; a maior margem pró-@@PRES_P2@@, em <b>@@PRES_MAXNEG_UTB@@ (@@PRES_MAXNEG_PP@@ pp)</b>.@@PRES_EMPATE@@</p>
      </div>
      <ul class="placar">
        @@PRES_PLACAR@@
      </ul>
    </div>
    <figure class="mapa" style="margin:22px 0 0">
      <div class="mapa-barra">
        <span class="rot">Vencedor por bairro · margem de vitória</span>
        <a href="campinas_presidente_2t.html" target="_blank" rel="noopener">abrir em tela cheia ↗</a>
      </div>
      <div class="frame">
        <iframe src="campinas_presidente_2t.html" title="Mapa interativo — Presidente 2026, Campinas, 2º turno, vencedor por bairro (UTB/UTR)" loading="eager"></iframe>
      </div>
    </figure>
    <p class="aviso">Passe o mouse sobre um bairro para ver os votos · clique para dar zoom. Se o mapa não aparecer, sirva esta pasta por HTTP (<code>python3 -m http.server</code>) em vez de abrir direto do disco.</p>
  </section>

  <section class="bloco" id="governador" aria-labelledby="t-governador">
    <div class="bloco-cabeca">
      <div>
        <span class="eyebrow">Mapa 02 · Governador · 1º turno</span>
        <h2 id="t-governador">@@GOV_TITULO@@</h2>
        <p class="resumo">No 1º turno estadual, a maior margem pró-@@GOV_P1@@ aparece em <b>@@GOV_MAXPOS_UTB@@ (@@GOV_MAXPOS_PP@@ pp)</b>; a maior margem pró-@@GOV_P2@@, em <b>@@GOV_MAXNEG_UTB@@ (@@GOV_MAXNEG_PP@@ pp)</b>.@@GOV_EMPATE@@</p>
      </div>
      <ul class="placar">
        @@GOV_PLACAR@@
      </ul>
    </div>
    <figure class="mapa" style="margin:22px 0 0">
      <div class="mapa-barra">
        <span class="rot">Vencedor por bairro · margem de vitória</span>
        <a href="campinas_governador_1t.html" target="_blank" rel="noopener">abrir em tela cheia ↗</a>
      </div>
      <div class="frame">
        <iframe src="campinas_governador_1t.html" title="Mapa interativo — Governador 2026, Campinas, 1º turno, vencedor por bairro (UTB/UTR)" loading="lazy"></iframe>
      </div>
    </figure>
    <p class="aviso">Passe o mouse sobre um bairro para ver os votos · clique para dar zoom. Se o mapa não aparecer, sirva esta pasta por HTTP (<code>python3 -m http.server</code>) em vez de abrir direto do disco.</p>
  </section>

</main>

<footer class="rodape" id="metodo">
  <div class="wrap">
    <div>
      <h3>Fonte</h3>
      <p>Votação por seção eleitoral do Tribunal Superior Eleitoral (TSE), município de Campinas (<code>CD_MUNICIPIO 62910</code> — código TSE, não o IBGE). Presidente vem de <code>votacao_secao_2026_BR.zip</code> (2º turno); Governador vem de <code>votacao_secao_2026_SP.zip</code> (1º turno). Totais de votos válidos excluem brancos e nulos.</p>
    </div>
    <div>
      <h3>Método</h3>
      <ul>
        <li>Geocodificação dos <b>268 locais de votação</b> (OSM Photon) e junção espacial ponto-em-polígono.</li>
        <li>Agregação até os <b>93 bairros (UTB/UTR)</b> da Prefeitura de Campinas, a subdivisão municipal alinhada aos setores censitários do IBGE.</li>
        <li>Vencedor por bairro pela margem em pontos percentuais (pp).</li>
        <li>Quando o ponto cai fora do polígono, usa-se a UTB mais próxima até 500 m; sem geocodificação, a UTB modal da zona eleitoral.</li>
        <li>Campinas <b>não possui malha de bairros do IBGE</b> — “bairro” aqui é a UTB/UTR, que pode não coincidir com a percepção popular.</li>
      </ul>
    </div>
    <div>
      <h3>Os dois mapas</h3>
      <p>Turnos diferentes, bases de votos válidos diferentes: os dois recortes <b>não são comparáveis diretamente</b>.</p>
      <a class="lnk" href="campinas_presidente_2t.html" target="_blank" rel="noopener">Presidente 2026 · 2º turno ↗</a><br>
      <a class="lnk" href="campinas_governador_1t.html" target="_blank" rel="noopener">Governador 2026 · 1º turno ↗</a>
    </div>
  </div>
</footer>

</body>
</html>'), warn = FALSE)

titulo_bloco <- function(r) sprintf("%s venceu em %d dos 93 bairros; %s, em %d.",
                                    r$c1n, r$n1, r$c2n, r$n2)

landing <- render(tpl_landing, list(
  TOT_PRES = fmt_int(r_pres$tot_val), TOT_GOV = fmt_int(r_gov$tot_val),
  PRES_TITULO = titulo_bloco(r_pres), GOV_TITULO = titulo_bloco(r_gov),
  PRES_P1 = primeiro(r_pres$c1n), PRES_P2 = primeiro(r_pres$c2n),
  PRES_MAXPOS_UTB = ep$max_pos$NM_UTB, PRES_MAXPOS_PP = fmt_pp(ep$max_pos$margem_pp),
  PRES_MAXNEG_UTB = ep$max_neg$NM_UTB, PRES_MAXNEG_PP = fmt_pp(ep$max_neg$margem_pp),
  PRES_EMPATE = frase_empate(r_pres), PRES_PLACAR = bloco_placar(r_pres),
  GOV_P1 = primeiro(r_gov$c1n), GOV_P2 = primeiro(r_gov$c2n),
  GOV_MAXPOS_UTB = eg$max_pos$NM_UTB, GOV_MAXPOS_PP = fmt_pp(eg$max_pos$margem_pp),
  GOV_MAXNEG_UTB = eg$max_neg$NM_UTB, GOV_MAXNEG_PP = fmt_pp(eg$max_neg$margem_pp),
  GOV_EMPATE = frase_empate(r_gov), GOV_PLACAR = bloco_placar(r_gov)
))

writeLines(landing, "index.html", useBytes = TRUE)
cat(sprintf("escreveu index.html (%.1f KB)\n", file.size("index.html") / 1024))

# --- gate Q7 (tamanho) ------------------------------------------------------
for (f in c("campinas_presidente_2t.html", "campinas_governador_1t.html")) {
  sz <- file.size(f) / 1e6
  cat(sprintf("Q7 %s: %.2f MB -> %s\n", f, sz, if (sz < 5) "PASS" else "FAIL"))
  stopifnot(sz < 5)
}
cat("FIM PASSO 6\n")
