# AGENTS.md — 2026 Campinas Election Maps (Presidente 2T + Governador 1T)

Choropleth maps of 2026 election results by **bairro** (UTB/UTR, 93 units) for Campinas/SP. Two races: Presidente 2º Turno and Governador 1º Turno. TSE `CD_MUNICIPIO = 62910`.

## Pipeline

```bash
bash scripts/run_all.sh --clean   # full pipeline: TSE extract → UTB mesh → geocode → join → aggregate → maps
```

Each step self-resolves its working directory. Key artifacts:
- `data/campinas_utb.gpkg` — 93 UTB polygons, EPSG:4674
- `data/votacao_secao_2026_presidente_campinas.csv` — 31,403 lines
- `data/votacao_secao_2026_governador_campinas.csv` — 454,799 lines

## Web Deliverables

Serve over HTTP (`python -m http.server`) — opening `index.html` from disk breaks iframes.

- `index.html` — landing page with placar and links
- `campinas_presidente_2t.html` — Presidente 2T choropleth by signed margin (pp)
- `campinas_governador_1t.html` — Governador 1T choropleth by signed margin (pp)

QA hooks on map pages: `window.__feats` (93), `window.__mapLayer`, `window.__corMargem`, `window.__MAX_PP`.

## Critical Data & Encoding Traps

1. **Source CSVs are Latin-1**: TSE files are ISO-8859-1. Always read with `data.table::fread(..., encoding = "Latin-1")` or `iconv(x, "latin1", "UTF-8")`.
2. **Text normalization**: Never pass raw Latin-1 into `stringr::str_to_upper()`. Use base-R `iconv()`, `toupper()`, `trimws()`.
3. **UTB join**: Spatial point-in-polygon with 500m nearest fallback. Remaining 9 locations use Zone modal UTB (`metodo_distrito = "fallback_zona"`).
4. **40 UTBs have no voting sections** (rural UTRs / industrial zones) — handled explicitly, not errors.
5. **Colors are relative to municipal top-2**, not fixed candidate IDs: Blue `#1f5fbf` (leader), Red `#d92b2b` (second), Gray `#e6e6e6` (tie/no votes).
6. **Map colors**: Positive `margem_pp` = Blue, Negative = Red, Null = Gray.

## Geocoding & Spatial Invariants

- **Photon endpoint**: `https://photon.komoot.io/api/?q=<urlenc>&limit=1&lang=default&bbox=-46.92,-24.05,-46.28,-23.30`. Do not pass `lang=pt`.
- **Coverage**: 268 locations, 96.64% geocoded (259/268). Unmatched stay `NA` (`metodo_geo = NA`).
- **Topological validity**: Wrap UTB dissolving with `sf_use_s2(FALSE) -> st_make_valid() -> st_union() -> st_make_valid() -> sf_use_s2(TRUE)`.
- **Nearest match**: `sf::st_nearest_feature` only up to 500m, flagged `metodo_distrito = "nearest"`.

## Environment & Tooling Constraints

- **No `install.packages()`**: Use only pre-installed packages (`data.table`, `sf`, `ggplot2`, `jsonlite`, `dplyr`).
- **Cairo device for maps**: `ragg` is broken. Use `grDevices::png(..., type = "cairo")` for `ggsave`.
- **Stream-filter TSE ZIPs**: Do not extract full ZIPs; filter during read.

## QC Gates (Q1–Q6)

- **Q1 (Vote conservation)**: District valid-vote sum = municipal benchmark within 0.01%.
- **Q2 (Unambiguous winner)**: Exactly one winner per UTB; zero `NA`.
- **Q3 (Share range)**: Candidate share ∈ [0, 1].
- **Q4 (Completeness)**: 93 UTBs covered.
- **Q5 (Geocode honesty)**: Unmatched locations explicitly reported as `NA`.
- **Q6 (Spatial join)**: All 2,511 census sectors fall inside exactly one UTB.

## Key Numbers

| Metric | Value |
|---|---|
| UTBs (bairros) | 93 |
| Locations geocoded | 259/268 (96.64%) |
| Census sectors | 2,511 |
| UTBs without voting sections | 40 |
| Presidente 2T winners | Flavio Bolsonaro 42, Lula 11 |
| Governador 1T winners | Tarcísio 52, Haddad 1 |
