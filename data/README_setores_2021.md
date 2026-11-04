# Malha de Setores Censitários 2021 — Campinas/SP

## Origem (IBGE)

Diretório oficial:
`https://geoftp.ibge.gov.br/organizacao_do_territorio/malhas_territoriais/malhas_de_setores_censitarios__divisoes_intramunicipais/2021/`

Arquivos baixados:

| Arquivo local | URL de origem |
|---|---|
| `3509502_campinas_setores_2021.kmz` | `.../2021/Malha_de_setores_(kmz)_por_municipios/UF/SP/3509502_campinas_setores_2021.kmz` |
| `SP_Setores_2021.zip` | `.../2021/Malha_de_setores_(shp)_por_UFs/SP/SP_Setores_2021.zip` |
| `campinas_setores_2021.gpkg` | derivado do shapefile de SP, filtrado por `CD_MUN = 3509502` |

Data de publicação do shapefile de SP: 2022-10-18 (última modificação no servidor: 2022-11-21).

## Conteúdo

- **2511 setores censitários** no município de Campinas (código IBGE `3509502`).
- CRS: **SIRGAS 2000 / EPSG:4674** (graus decimais), o mesmo do arquivo original do IBGE.
- Extensão: lon -47.2468 a -46.8153; lat -23.0612 a -22.7292.
- Área total: **794,80 km²** (cálculo em EPSG:31983) — compatível com a área oficial do município (~794,6 km²).
- Geometrias: MultiPolygon, todas válidas, sem nulos ou vazias.
- Distritos: 5 (Campinas, Barão Geraldo, Joaquim Egídio, Sousas, Nova Aparecida).

Distribuição por situação (código do IBGE):

| CD_SIT | NM_SIT | Setores |
|---|---|---|
| 1 | Área Urbana de Alta Densidade de Edificações | 2275 |
| 2 | Área Urbana de Baixa Densidade de Edificações | 167 |
| 3 | Núcleo Urbano | 18 |
| 5 | Povoado | 2 |
| 7 | Lugarejo | 1 |
| 8 | Área Rural (exclusive aglomerados) | 48 |

O KMZ é organizado em 6 camadas com esses mesmos nomes de situação e soma exatamente 2511 feições.

## Dicionário de campos

| Campo | Descrição |
|---|---|
| `CD_SETOR` | Código do setor censitário (15 dígitos: UF 2 + município 5 + distrito 2 + subdistrito 2 + setor 4) |
| `CD_SIT` / `NM_SIT` | Código e nome da situação do setor (tabela acima) |
| `CD_UF` / `NM_UF` / `SIGLA_UF` | Unidade da federação (35 / São Paulo / SP) |
| `CD_MUN` / `NM_MUN` | Município (3509502 / Campinas) |
| `CD_DIST` / `NM_DIST` | Distrito |
| `CD_SUBDIST` / `NM_SUBDIST` | Subdistrito (vazio em Campinas) |

## Observações

- Esta é a malha **2021**, base pré-coletora do Censo 2022. Ela **não** traz o campo de bairro (`CD_BAIRRO`), incluído apenas na malha definitiva do Censo 2022.
- A malha definitiva do Censo 2022 (limites revistos após a coleta) está em `.../censo_2022/setores/`, caso a análise precise dos limites finais do Censo 2022 em vez da base 2021.
- Códigos de setor 2021 e 2022 não são 1:1 — ver `Historico_formacao_Setores_Censitarios_2010_2022.xlsx` no diretório `censo_2022/` antes de comparar séries.

## Como reusar

```python
import geopandas as gpd
g = gpd.read_file("data/campinas_setores_2021.gpkg")
g_utm = g.to_crs(31983)  # SIRGAS 2000 / UTM 23S, para cálculos métricos
```
