# Eleições 2026 em Campinas — Bairro a Bairro (UTB/UTR)

[![GitHub Pages](https://img.shields.io/badge/demo-online-brightgreen?style=flat-square&logo=github)](https://ratitu.github.io/eleicoes-2026-campinas/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)

Visualização geoespacial interativa e rigorosa dos resultados das **Eleições 2026 em Campinas/SP** por **bairro (UTB/UTR, 93 unidades)** para dois recortes cruciais:
1. **Presidente (2º turno)** — Flávio Bolsonaro vs. Lula
2. **Governador (1º turno)** — Tarcísio de Freitas vs. Fernando Haddad

🌐 **Acesse a aplicação online:** [ratitu.github.io/eleicoes-2026-campinas](https://ratitu.github.io/eleicoes-2026-campinas/)

---

## 🗺️ Destaques dos Mapas
- **93 unidades territoriais (UTBs/UTRs)** da Prefeitura de Campinas mapeadas.
- **268 locais de votação** geocodificados com precisão via API Photon (Komoot) com bounding box restrita a Campinas.
- **Coloração por margem percentual (pp)** relativa ao Top-2 municipal (Azul `#1f5fbf` para o 1º colocado, Vermelho `#d92b2b` para o 2º).
- **Imputação espacial por vizinho mais próximo** aplicada a UTBs rurais/industriais sem seção de votação física, garantindo cobertura de 100% do território municipal sem vazios no mapa.
- **Hooks de QA embutidos** (`window.__feats`, `window.__mapLayer`, `window.__corMargem`, `window.__MAX_PP`).

---

## 🛠️ Arquitetura do Pipeline (`scripts/`)

O projeto possui um pipeline totalmente automatizado em **R** (`sf`, `data.table`) e **Bash**:

- `step1_fetch.sh` — Download e filtragem em streaming dos microdados do TSE para Campinas (`CD_MUNICIPIO = 62910`).
- `step2_utb.R` — Consolidação da malha territorial de UTBs (EPSG:4674).
- `step3_places.R` — Validação e deduplicação dos 268 locais de votação.
- `step4_geocode.R` — Geocodificação resiliente com cache incremental via Photon.
- `step5_join_aggregate.R` — Junção espacial ponto-em-polígono (com fallback de 500m e modal de zona) + agregação por UTB + verificação das travas de qualidade (Gates Q1–Q6).
- `step6_maps.R` — Renderização dos mapas coropléticos interativos (Leaflet) e da página central (`index.html`).

Para executar o pipeline completo do zero:
```bash
bash scripts/run_all.sh --clean
```

---

## 📊 Placar Municipal

| Eleição | Vencedor Principal | Votos / % | Segundo Colocado | Votos / % | Total Válidos |
|---|---|---|---|---|---|
| **Presidente (2º T)** | Flávio Bolsonaro (PL) | 360.222 (54,24%) | Lula (PT) | 303.914 (45,76%) | **664.136** |
| **Governador (1º T)** | Tarcísio de Freitas (Republicanos) | 367.121 (61,88%) | Fernando Haddad (PT) | 219.874 (37,06%) | **593.302** |

### Distribuição Territorial (Bairros Vencidos)
- **Presidente 2º Turno:** Flávio Bolsonaro 70 bairros | Lula 23 bairros
- **Governador 1º Turno:** Tarcísio de Freitas 92 bairros | Fernando Haddad 1 bairro

---

## 💻 Como Rodar Localmente

1. Clone o repositório:
   ```bash
   git clone https://github.com/ratitu/eleicoes-2026-campinas.git
   cd eleicoes-2026-campinas
   ```
2. Sirva os arquivos estáticos via HTTP (necessário para carregamento correto dos iframes e GeoJSONs):
   ```bash
   python3 -m http.server 8000
   ```
3. Abra no navegador: `http://localhost:8000`

---

## 📄 Licença
Distribuído sob a licença MIT. Veja `LICENSE` para mais detalhes.
