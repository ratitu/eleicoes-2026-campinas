# Prompt 01 — Dois mapas eleitorais de Campinas por bairro (UTB/UTR)

> **Como usar**: cole este arquivo inteiro como instrução para um agente de código
> trabalhando em `/home/ratitu/Documents/claude/eleicoes_2026_campinas`.
> O projeto de referência é `/home/ratitu/Documents/claude/eleicoes_2026_sao_paulo`.

---

## 1. Objetivo

Criar **dois mapas coropléticos interativos** da cidade de **Campinas/SP** para as
eleições de 2026, com a mesma ideia visual e a mesma arquitetura do projeto irmão de
São Paulo:

| Mapa | Disputa | Turno | Unidade espacial | Arquivo |
|---|---|---|---|---|
| **A** | Presidente da República | **2º turno** | bairro | `campinas_presidente_2t.html` |
| **B** | Governador de São Paulo | **1º turno** | bairro | `campinas_governador_1t.html` |

Cada mapa mostra, **em cada bairro**, quem venceu e por qual margem, colorindo o
polígono pela **margem assinada em pontos percentuais (pp)**.

---

## 2. LEIA ANTES DE ESCREVER QUALQUER CÓDIGO

Leia estes arquivos do projeto de referência e **reproduza o padrão** (não copie os
dados dele, que são de São Paulo):

- `README.md` e `AGENTS.md` — arquitetura, armadilhas e gates de QC
- `index_gov.html` e `index_pres.html` — os mapas Leaflet (é o alvo visual)
- `index.html` — a landing page com um bloco por disputa
- `scripts/step3_geocode.R` — geocodificação com Photon + cache
- `scripts/step4_join_aggregate.R` — join espacial ponto → polígono
- `scripts/step7_presidente_distritos.R` — agregação + gates de QC

**O que deve ser idêntico em espírito:**

- GeoJSON **embutido no próprio HTML** (site estático, sem backend, sem build, sem
  dependência de rede além do Leaflet e do basemap)
- **Leaflet 1.9.4** via unpkg, com `preferCanvas: true`
- Basemap **Esri World Imagery** (satélite)
- Cor = **margem assinada** em pp, com gradiente claro → forte proporcional a
  `|margem| / MAX_PP`
- **Faixa de empate** quando `|margem| < 0,05 pp`
- Legenda **colapsável**, tooltip por bairro, rodapé com totais e fonte TSE
- Hooks de QA expostos: `window.__feats`, `window.__mapLayer`, `window.__corMargem`,
  `window.__MAX_PP`

---

## 3. DECISÃO ESPACIAL OBRIGATÓRIA — leia com atenção

**Campinas NÃO tem malha de bairros do IBGE.** Isto foi verificado e não é suposição:

- `SP_bairros_CD2022.gpkg` (malha de bairros do Censo 2022) cobre **58 municípios**
  de SP e **não inclui Campinas**.
- Na malha de setores de 2022 de Campinas, `CD_BAIRRO` e `NM_BAIRRO` são **100%
  nulos** (2.593 setores).
- O arquivo `data/campinas_setores_2021.gpkg` (**2.511 setores**) **não possui campo
  de bairro** — só `CD_DIST` / `NM_DIST` (5 distritos em 2021; a malha 2022 tem 7).

**Portanto:**

1. **NÃO invente polígonos de bairro.** Nada de aproximar bairro por distrito, por
   buffer, por nome de rua ou por "cluster" arbitrário.
2. **NÃO use os distritos** como unidade: são só 5–7 e a granularidade é grosseira
   demais para o objetivo.
3. **A unidade espacial do projeto é a UTB/UTR oficial da Prefeitura de Campinas** —
   Unidades Territoriais Básicas (urbanas) + Unidades Territoriais Rurais. A própria
   metadata oficial do município declara que as divisas da UTB foram ajustadas às
   **barreiras urbanísticas, aos setores censitários do IBGE e às divisas de
   loteamentos** (Plano Diretor, LC 189/2018), o que a torna a subdivisão municipal
   correta para agregar dados censitários e eleitorais.
4. Nos mapas, legendas, tooltips e textos, chame a unidade de **"bairro (UTB/UTR)"**.
   No código e nos CSVs, use as colunas `CD_UTB` e `NM_UTB`.

### 3.1 Como baixar a UTB/UTR (passo não óbvio)

O endpoint gera um shapefile temporário com **UUID por requisição** e entrega os
arquivos soltos (`.shp`, `.dbf`, `.prj`, `.shx`, `.cpg`) — **não é um ZIP**.

```bash
HTML=$(curl -sL --max-time 90 "https://zoneamento.campinas.sp.gov.br/novo_zoneamento/exporta_shp.php?id=91")
BASE=$(echo "$HTML" | grep -oP '/pmapper/tmp/ms_tmp/[0-9a-f-]+' | head -1)
echo "BASE=$BASE"
for ext in shp dbf prj shx cpg; do
  curl -sL --max-time 90 -o "data/utb_campinas.$ext" \
    "https://zoneamento.campinas.sp.gov.br$BASE.$ext"
done
```

Regras:

- O UUID é **efêmero**. Se algum arquivo vier com HTTP 404 ou tamanho 0, **refaça a
  requisição inteira** (novo `HTML` → novo `BASE`) até 3 vezes.
- Valide cada download: `file` deve reconhecer shapefile/DBF e o `.shp` deve ter
  mais de 400 KB.
- O `.dbf` é **Latin-1** — lido como UTF-8, os acentos de `DENOMINACA` saem
  corrompidos (mojibake). Converta com `iconv(from = "latin1", to = "UTF-8")` e
  confira que `Joaquim Egídio` aparece acentuado corretamente.
- O shapefile vem em **EPSG:31983** (SIRGAS 2000 / UTM 23S). Reprojete para
  **EPSG:4674** ao consolidar em GeoPackage.
- Campos: `UTB_SIGLA` (ex.: `EU-35`, `MM-71`, `RA-11`, `UTR - Campo Grande`),
  `DENOMINACA` (nome, com bairros compostos do tipo
  `Swift/Jd.São Vicente/Jd.Esmeraldina`) e `DENSIDADE_`.
- **São 93 polígonos** e a área total é **≈ 795,35 km²** (compatível com a área
  oficial do município, ≈ 794,8 km²). Use isso como gate. Se vier diferente de 93,
  **pare e reporte** — a camada pode ter sido revisada.
- **`UTB_SIGLA` NÃO é única**: 93 feições, apenas **82 siglas distintas**. As UTR vêm
  fatiadas em partes numeradas (`UTR - Campo Grande 1..5`, `UTR - Descampado 1..4`,
  `UTR - Furnas / Tanquinho 1..3`, `UTR - Amarais / Barão Geraldo 1..2`) e existe
  ainda uma colisão real: **duas feições com sigla `MM-70`** (`Aeroporto de
  Viracopos` e uma chamada literalmente `MM-70`). **Nunca use `UTB_SIGLA` como
  chave** de join, agregação ou `id` do GeoJSON.
- **`DENOMINACA` é única** (93/93) — é o nome que deve virar `NM_UTB` e o rótulo do
  tooltip.
- `UTB_SIGLA` **não é numérico**. Ordene por nome, nunca por `as.numeric()`.
- Se, e somente se, o endpoint estiver indisponível após as 3 tentativas: **pare e
  reporte o erro**. Não degrade o entregável para distritos nem para setores sem
  autorização explícita.

### 3.2 Para que serve então o `data/campinas_setores_2021.gpkg`

Ele **não** é a fonte dos bairros. Use-o para:

1. **Máscara municipal**: dissolver os 2.511 setores (`sf::st_union`) para obter o
   limite de Campinas; use para recortar a UTB e conferir que ela cobre o município.
2. **Gate de cobertura**: o centróide de cada um dos 2.511 setores deve cair dentro de
   **exatamente uma** UTB. Conte e reporte eventuais setores fora ou ambíguos.
3. **Contexto populacional** (opcional, se sobrar tempo): densidade por UTB.

Os votos **não** passam pelos setores: o caminho é
`seção → local de votação → geocodificação → ponto-em-polígono na UTB`.

---

## 4. Entradas

| Item | Caminho / URL | Situação |
|---|---|---|
| Setores censitários 2021 de Campinas | `data/campinas_setores_2021.gpkg` | **já existe** — 2.511 setores, EPSG:4674 |
| UTB/UTR oficial | ver §3.1 | baixar |
| Votação **federal** 2026 (Presidente) | `https://cdn.tse.jus.br/estatistica/sead/odsele/votacao_secao/votacao_secao_2026_BR.zip` | baixar — **241.891.087 bytes**, atualizado em 2026-10-26 |
| Votação **estadual** 2026 (Governador) | `https://cdn.tse.jus.br/estatistica/sead/odsele/votacao_secao/votacao_secao_2026_SP.zip` | baixar — **808.337.068 bytes**, atualizado em 2026-10-26 |
| Metadados de candidatos | `https://cdn.tse.jus.br/estatistica/sead/odsele/consulta_cand/consulta_cand_2026.zip` | baixar (≈3 MB) — opcional, para `partido` |

> ⚠️ **São dois arquivos distintos, e cada mapa usa um deles.** O TSE publicou 2026
> separado por tipo de eleição:
>
> | Arquivo | CSV interno | `CD_ELEICAO` / `DS_ELEICAO` | Cargos |
> |---|---|---|---|
> | `votacao_secao_2026_BR.zip` | `votacao_secao_2026_BR.csv` (**1.578.545.088 bytes** ≈ 1,58 GB) | `6257` — *Eleição Geral Federal 2026* | **Presidente** (1º e 2º turnos) |
> | `votacao_secao_2026_SP.zip` | `votacao_secao_2026_SP.csv` (**4.954.076.618 bytes** ≈ 4,95 GB) | `6259` — *Eleições Gerais Estaduais 2026* | **Governador**, Senador, Dep. Federal, Dep. Estadual (só 1º turno) |
>
> O `_SP.zip` **não contém Presidente em nenhuma linha** e o `_BR.zip` **não contém
> Governador**. Filtrar Campinas no arquivo errado devolve zero linhas para a
> disputa e o mapa sai vazio. Não existe arquivo `*_2t_*` no CDN (testado: 404).

**Município de Campinas: `CD_MUNICIPIO = 62910`.**

> ⚠️ **`CD_MUNICIPIO` do TSE NÃO é o código do IBGE.** O código IBGE de Campinas é
> `3509502`, mas o arquivo de votação usa o **código TSE** do município — para
> Campinas, **`62910`** (do mesmo modo, a cidade de São Paulo é `71072`, e não
> `3550308`). Filtrar por `3509502` devolve **zero linhas** e o pipeline inteiro
> fica vazio, sem erro. **Confirme o código pelo nome antes de filtrar:**
>
> ```bash
> # funciona em qualquer um dos dois arquivos; 62910 é o mesmo nos dois
> unzip -p votacao_secao_2026_BR.zip votacao_secao_2026_BR.csv \
> | awk -F';' 'NR>1{gsub(/"/,"",$15); if(toupper($15)=="CAMPINAS"){gsub(/"/,"",$14); print $14}}' \
> | sort -u
> # -> 62910
> ```

Filtre por esse código — nunca por zona eleitoral, porque Campinas tem várias zonas
e o número delas muda.

---

## 5. Entregáveis

### 5.1 Dados

1. `data/campinas_utb.gpkg` — UTB/UTR oficial, EPSG:4674, **93 polígonos**, colunas
   `CD_UTB` (**id substituto único**, `sprintf("C%03d", seq_len(n))` após ordenação
   determinística por `UTB_SIGLA` e `NM_UTB`), `NM_UTB` (= `DENOMINACA`, única),
   `UTB_SIGLA` (informativa, **não única**), `DENSIDADE_`, `geometry`.
2. `data/votacao_secao_2026_presidente_campinas.csv` — extrato do **BR.zip** só de
   Campinas, com o **encoding Latin-1 original preservado** e o mesmo separador `;`.
   Esperado: **31.403 linhas** (1 cabeçalho + 31.402), Presidente 1º e 2º turnos.
3. `data/votacao_secao_2026_governador_campinas.csv` — extrato do **SP.zip** só de
   Campinas, mesmo formato. Esperado: **454.799 linhas** (1 cabeçalho + 454.798),
   todos os cargos estaduais, só 1º turno.
4. `output/campinas_presidente_2t.csv` — uma linha por bairro (UTB).
5. `output/campinas_governador_1t.csv` — idem.
6. `output/campinas_votos_long.csv` — formato longo:
   `disputa, CD_UTB, NM_UTB, NM_VOTAVEL, NR_VOTAVEL, partido, votos, share`.

Colunas obrigatórias nos arquivos por bairro:

`CD_UTB`, `NM_UTB`, `vencedor`, `partido`, `votos_1`, `votos_2`, `pct_1`, `pct_2`,
`margem_pp`, `margem_votos`, `votos_validos`, `n_secoes`, `n_locais`, `fonte_geo`.

Onde `_1` é o **1º colocado no município** naquela disputa/turno e `_2` o 2º.
`margem_pp = pct_1 - pct_2`.

### 5.2 Mapas (HTML estático)

7. `campinas_presidente_2t.html` — Mapa A.
8. `campinas_governador_1t.html` — Mapa B.
9. `index.html` — landing `lang="pt-BR"` com um bloco por disputa, cada um embutindo
   o respectivo mapa num `<iframe>` (um `loading="eager"`, outro `loading="lazy"`),
   com link para tela cheia. Espelhe `index.html` do projeto de referência.

Cada mapa deve ter:

- Título: `Presidente 2026 — Campinas, 2º turno` / `Governador 2026 — Campinas, 1º turno`
- Subtítulo: `Vencedor por bairro (UTB/UTR) · cor pela margem de vitória em pontos percentuais (pp)`
- Legenda colapsável com os dois candidatos, a contagem de bairros de cada um e a
  faixa de empate
- Tooltip: nome do bairro, vencedor e partido, votos e % de cada candidato, margem
  em pp e em votos, votos válidos
- Rodapé: `votos válidos · candidato 1 X% · candidato 2 Y% · Fonte: TSE`
- Nota de método no rodapé ou na legenda: `Seções agregadas por geocodificação do
  local de votação + ponto-em-polígono na UTB/UTR (Prefeitura de Campinas)`

### 5.3 Método e QC

10. `output/resumo.md` — método, cobertura de geocodificação, locais não resolvidos,
    bairros sem seção, e as limitações da §10.
11. `scripts/` — pipeline executável e reexecutável do zero.

---

## 6. Restrições de ambiente (duras)

- **Nunca `install.packages()`.** Use só o que já existe: `sf`, `data.table`,
  `ggplot2`, `jsonlite`, `dplyr` (todos presentes).
- **`ragg` está quebrado.** Qualquer PNG deve usar Cairo explicitamente:
  ```r
  png_dev <- function(f, w = 8, h = 9, r = 300)
    grDevices::png(f, width = w, height = h, units = "in", res = r, type = "cairo")
  ```
- **Disco apertado (≈1,6 GB livres).** Os CSVs do TSE somam **6,5 GB**
  (1,58 GB federal + 4,95 GB estadual) e os ZIPs somam ~1 GB. **Nunca extraia um
  arquivo inteiro.** Filtre em streaming, **um arquivo por vez**, apagando o ZIP
  logo depois:
  ```bash
  # 1) Presidente (federal) -> 8,2 MB
  unzip -p votacao_secao_2026_BR.zip votacao_secao_2026_BR.csv \
  | awk -F';' 'NR==1{print; next} {c=$14; gsub(/"/,"",c); if(c=="62910") print}' \
  > data/votacao_secao_2026_presidente_campinas.csv
  rm -f votacao_secao_2026_BR.zip

  # 2) Governador (estadual) -> 127 MB
  unzip -p votacao_secao_2026_SP.zip votacao_secao_2026_SP.csv \
  | awk -F';' 'NR==1{print; next} {c=$14; gsub(/"/,"",c); if(c=="62910") print}' \
  > data/votacao_secao_2026_governador_campinas.csv
  rm -f votacao_secao_2026_SP.zip
  ```
  Rode na ordem acima: o federal é menor e libera espaço antes do estadual. Se o
  disco ainda apertar, apague `data/SP_Setores_2021.zip`, `data/kmz_extract/` e o
  ZIP já consumido antes de baixar o próximo.
- **Leitura do CSV do TSE**: `data.table::fread(..., sep = ";", encoding = "Latin-1")`.
  Para o arquivo grande, use `select =` com apenas as colunas necessárias.
- **Não modifique** `data/campinas_setores_2021.gpkg`,
  `data/3509502_campinas_setores_2021.kmz`, `data/README_setores_2021.md` nem
  `prompt01.md`. Escreva scripts novos.

---

## 7. Método (siga na ordem)

### Passo 1 — Baixar e filtrar os votos

1. Baixe **os dois** ZIPs do TSE (§4) e filtre `CD_MUNICIPIO == 62910` (código
   **TSE**, não IBGE) em streaming (§6), gerando **dois** extratos separados:
   `data/votacao_secao_2026_presidente_campinas.csv` (do `_BR.zip`) e
   `data/votacao_secao_2026_governador_campinas.csv` (do `_SP.zip`).
2. Assertivas em cada extrato: `nrow > 1`; `NM_MUNICIPIO` contém `CAMPINAS`; as
   colunas `NR_TURNO`, `DS_CARGO`, `NR_VOTAVEL`, `NM_VOTAVEL`, `QT_VOTOS`,
   `NR_ZONA`, `NR_SECAO`, `NR_LOCAL_VOTACAO`, `NM_LOCAL_VOTACAO`,
   `DS_LOCAL_VOTACAO_ENDERECO` existem. Se um extrato tiver **só o cabeçalho**,
   você filtrou pelo código errado ou baixou o arquivo errado — pare.
3. **Verifique os turnos e cargos realmente presentes em cada extrato**:
   ```r
   print(d[, .N, by = .(NR_TURNO, DS_CARGO)][order(NR_TURNO, DS_CARGO)])
   ```
   - No extrato **federal** deve aparecer **`DS_CARGO == "Presidente"`**, com
     `NR_TURNO` 1 **e 2**. Se o turno 2 não estiver lá, **pare e reporte** — não use
     o 1º turno no lugar do 2º nem invente resultado.
   - No extrato **estadual** deve aparecer **`DS_CARGO == "Governador"`** com
     `NR_TURNO == 1`. Se não aparecer, você pegou o arquivo errado.
   - Se `Presidente` aparecer no extrato estadual ou `Governador` no federal, algo
     está muito errado — reporte antes de continuar.
4. Exclua brancos e nulos: `NR_VOTAVEL %in% c(95L, 96L)`.
5. Derive os **dois candidatos de cada disputa a partir dos dados** (top 2 por votos
   no município). **Não hardcode nomes de candidatos** — o prompt é de 2026 e os
   nomes devem sair do arquivo.
6. Calcule a referência de votos válidos do município para cada disputa e guarde-a
   para o gate Q1 (§9).

### Passo 2 — Consolidar a UTB/UTR

1. Baixe os 5 arquivos (§3.1), valide, leia com `sf::st_read`.
2. Corrija o encoding de `DENOMINACA` (Latin-1 → UTF-8).
3. Reprojete para EPSG:4674 e grave `data/campinas_utb.gpkg` com `CD_UTB` (**id
   substituto único**, §5.1), `NM_UTB` (= `DENOMINACA`) e `UTB_SIGLA` como coluna
   informativa — nunca como chave.
4. Gates: 93 feições, todas as geometrias válidas (`st_make_valid()`), área total
   entre 790 e 800 km².

### Passo 3 — Locais de votação únicos

1. Deduplique por **`(NR_ZONA, NM_LOCAL_VOTACAO, DS_LOCAL_VOTACAO_ENDERECO)`**
   normalizados (maiúsculas, trim, espaços colapsados).
   `NR_LOCAL_VOTACAO` **não é único entre zonas** — nunca use sozinho como chave.
2. Normalize texto com base R, nunca com `stringr` sobre Latin-1 cru:
   `iconv(x, "latin1", "UTF-8", sub = "")` → `toupper()` → `trimws()`.

### Passo 4 — Geocodificar

1. Se o TSE publicar coordenadas oficiais dos locais de votação de 2026, **prefira-as**
   (verifique `dadosabertos.tse.jus.br`). Caso contrário:
2. OSM **Photon**: `https://photon.komoot.io/api/?q=<urlenc>&limit=1&lang=default&bbox=-47.30,-23.13,-46.76,-22.67`
   - **Não** use `lang=pt` (não suportado).
   - Chame via `system2("curl", ...)` e parseie com `jsonlite::fromJSON`.
   - Máximo **1,5 req/s** (sleep mínimo 0,70 s; backoff `1,5 * k` s no retry).
   - **Cache incremental** em `cache/geocode_cache.rds`, gravado a cada 25 registros.
   - Descarte resultados fora do bbox (motivo `fora_bbox`).
3. Fallback em caso de erro: repetir só com o nome da rua. Se ainda falhar, deixe
   `NA` e conte — **nunca fabrique coordenadas**.

### Passo 5 — Join espacial e agregação

1. Monte um `sf` de pontos (EPSG:4674) e faça `st_join()` com a UTB.
2. Fallback para pontos fora de todos os polígonos: `sf::st_nearest_feature` **só até
   500 m**, marcando `metodo_geo = "nearest"`.
3. Fallback final: maioria da zona eleitoral, marcando `metodo_geo = "fallback_zona"`.
4. Propague a UTB do local para todas as seções daquele local.
5. Agregue por (`CD_UTB`, `NM_VOTAVEL`) somando `QT_VOTOS`.
6. Calcule vencedor, `pct_1`, `pct_2`, `margem_pp`, `margem_votos`, `votos_validos`,
   `n_secoes`, `n_locais`.
7. Declare `EMPATE` quando `|margem_pp| < 0,05`.

### Passo 6 — Gerar os HTML

1. Serialize o GeoJSON **simplificado** (veja §8.9) e embuta no HTML.
2. Reaproveite o CSS e o JS de `index_gov.html` / `index_pres.html` do projeto de
   referência, trocando apenas nomes, cores e textos.
3. Convenção de cor: 1º colocado no município = **azul** (`#1f5fbf`),
   2º = **vermelho** (`#d92b2b`), empate = `#e6e6e6`. A legenda **deve dizer
   explicitamente** qual candidato é qual cor.
4. Exponha os hooks de QA.

### Passo 7 — Landing

`index.html` com um `<section>` por disputa, título, um parágrafo de resumo com os
números reais (quantos bairros cada candidato venceu, % municipal) e o `<iframe>`.

---

## 8. Armadilhas críticas (todas verificadas neste ambiente)

1. **Não existe bairro do IBGE para Campinas** (§3). Este é o erro nº 1 que um agente
   comete aqui: tentar extrair bairro do `campinas_setores_2021.gpkg` e receber
   `NULL`. O arquivo tem 12 colunas e nenhuma é bairro.
2. **`CD_MUNICIPIO` é o código TSE, não o do IBGE** (§4). Campinas = `62910`;
   `3509502` (IBGE) devolve **zero linhas** e nenhum erro. Valide `nrow > 1` logo
   após o filtro.
3. **Presidente e Governador estão em arquivos diferentes** (§4). `_SP.zip` é a
   eleição **estadual** (`CD_ELEICAO 6259`, sem nenhuma linha de Presidente);
   `_BR.zip` é a **federal** (`6257`, só Presidente). Usar `_SP.zip` para o Mapa A
   produz zero linhas de Presidente e um mapa vazio — sem erro de execução.
4. **A UTB não vem em ZIP** e o link expira (§3.1).
5. **`UTB_SIGLA` não é numérico nem único** — 93 polígonos para 82 siglas; usar a
   sigla como chave funde UTRs distintas e colide as duas feições `MM-70`. Use
   `CD_UTB` substituto (§5.1). E `as.numeric()` na sigla gera `NA` e warnings.
6. **DBF da UTB é Latin-1** — sem `iconv`, os nomes saem corrompidos no mapa.
7. **Disco**: 6,5 GB de CSV + ~1 GB de ZIP vs. ~1,6 GB livres — filtrar em streaming,
   um arquivo por vez, apagando o ZIP depois, é obrigatório.
8. **`NR_LOCAL_VOTACAO` não é único entre zonas** — a chave é a tripla com nome e
   endereço normalizados.
9. **GeoJSON grande**: 93 polígonos da UTB, com precisão de 1 m, podem gerar dezenas
   de MB. Simplifique com `sf::st_simplify(dTolerance = 1e-5, preserveTopology = TRUE)`
   **em EPSG:4674** antes de serializar. O HTML final deve ficar abaixo de ~5 MB.
10. **2º turno tem só 2 candidatos**, mas ainda tem brancos/nulos (95/96) — exclua.
11. **Turno errado**: não existe "Presidente 2º turno" se o arquivo só tiver 1º. Assert
    explícito, com falha ruidosa.
12. **Partido**: se `consulta_cand_2026.zip` não casar por `SQ_CANDIDATO`, deixe
    `partido = NA` e reporte. Não invente sigla.

---

## 9. Gates de QC (assertivas duras, `stopifnot`)

- **Q1 — Conservação de votos**: a soma dos votos válidos por UTB deve igualar a
  referência municipal daquela disputa/turno com tolerância de **0,01%**. A referência
  é **calculada do próprio arquivo filtrado** — não hardcode um número.

**Valores de referência observados em 2026-10-31** (use só para **detectar filtro
errado**, não para escrever no código):

| Disputa | Votos válidos em Campinas | 1º colocado | 2º colocado |
|---|---|---|---|
| Presidente — 2º turno | **664.136** | FLAVIO NANTES BOLSONARO — 360.222 (54,24%) | LUIZ INÁCIO LULA DA SILVA — 303.914 (45,76%) |
| Governador — 1º turno | **593.302** | TARCISIO GOMES DE FREITAS — 367.121 (61,88%) | FERNANDO HADDAD — 219.874 (37,06%) |

Se os seus totais municipais divergirem materialmente desses valores, **pare e
investigue** antes de seguir: quase sempre é filtro de município, de turno ou de cargo
errado. Os nomes e percentuais, porém, devem ser **lidos do arquivo** em tempo de
execução (o prompt não os fixa).

- **Q2 — Vencedor inequívoco**: exatamente um vencedor por UTB, zero `NA`.
- **Q3 — Faixa de share**: `pct_1`, `pct_2` e todos os `share` em `[0, 1]`.
- **Q4 — Completude**: as **93** UTB aparecem na saída. Bairros sem seção atribuída
  são permitidos, mas devem ser **listados** em `output/resumo.md`.
- **Q5 — Cobertura de geocodificação**: reportar o % de locais únicos resolvidos
  (meta ≥ 90%) e o número exato de não resolvidos. Campinas tem **268 locais de
  votação únicos** em **7 zonas** (33, 274, 275, 378, 379, 380, 423) e **2.531
  seções** — use isso como checagem de completude.
- **Q6 — Setores × UTB**: o centróide de cada um dos 2.511 setores cai em exatamente
  uma UTB; reportar contagem fora/ambígua.
- **Q7 — Paridade HTML × CSV**: `window.__feats.length === 93` e os totais do rodapé
  do HTML batem com o CSV.

---

## 10. Honestidade — deve aparecer no rodapé do mapa e no `resumo.md`

- A ligação **seção → bairro é inferida** por geocodificação do endereço do local de
  votação + ponto-em-polígono; **não existe campo oficial** de bairro na seção.
  Informe a cobertura de geocodificação e o número de locais não resolvidos.
- A unidade "bairro" é a **UTB/UTR da Prefeitura de Campinas**, porque **Campinas não
  possui malha de bairros do IBGE**. A UTB é uma divisão de planejamento, alinhada aos
  setores censitários, e pode não coincidir com a percepção popular de bairro.
- O Mapa A é **2º turno** e o Mapa B é **1º turno** — turnos diferentes, bases de
  votos válidos diferentes, **não comparáveis diretamente**.
- Fonte dos votos: **TSE**. Fonte da geometria: **Prefeitura de Campinas (DEPLAN)** e
  **IBGE** (setores 2021).

---

## 11. Critérios de aceitação

- [ ] `data/campinas_utb.gpkg` existe, EPSG:4674, 93 polígonos válidos, área 790–800 km².
- [ ] `data/votacao_secao_2026_presidente_campinas.csv` existe, Latin-1, só Campinas,
      e contém **Presidente com `NR_TURNO` 1 e 2** (≈31.403 linhas).
- [ ] `data/votacao_secao_2026_governador_campinas.csv` existe, Latin-1, só Campinas,
      e contém **Governador com `NR_TURNO == 1`** (≈454.799 linhas).
- [ ] Nenhum dos dois extratos tem só o cabeçalho (sintoma de código IBGE ou arquivo
      errado).
- [ ] Os dois CSVs por bairro têm **93 linhas**, sem `NA` em `vencedor`.
- [ ] Todos os gates Q1–Q7 passam com `stopifnot`.
- [ ] Os dois HTML abrem por HTTP (`python3 -m http.server`), renderizam o basemap e
      os 93 polígonos, sem erro no console.
- [ ] `window.__feats.length === 93` nos dois mapas.
- [ ] `index.html` embute os dois mapas e traz números reais.
- [ ] `output/resumo.md` traz método, cobertura de geocodificação, bairros sem seção e
      as limitações da §10.
- [ ] Nenhum arquivo de `data/` foi modificado; nenhum pacote instalado; sem `ragg`.

---

## 12. Verificação final (obrigatória, não opcional)

Não basta "os testes passaram". Antes de dizer que terminou:

1. Suba `python3 -m http.server 8000` e **abra os dois mapas num navegador real**
   (Playwright/agent-browser).
2. Confirme: basemap carregou, 93 polígonos desenhados, tooltip abre com os números,
   legenda colapsa, nenhum erro de console, `window.__feats.length === 93`.
3. Tire um screenshot de cada mapa e confira visualmente que a cor faz sentido
   (bairros de um candidato claramente de um lado do espectro).
4. Confira 3 bairros manualmente: abra o CSV, pegue `votos_1`/`votos_2`, e verifique
   que o tooltip mostra exatamente aqueles valores.
5. Rode o pipeline do zero (`rm -rf cache/ output/` e reexecute) para provar que é
   reprodutível.

---

## 13. Fora de escopo

- Outras cidades, outros cargos, outros turnos, eleições anteriores.
- Mapas por zona eleitoral ou por seção.
- Backend, banco de dados, deploy, CI.
- Recriar malha de bairros "oficial" de Campinas — não existe (§3).
- Alterar o projeto de São Paulo.

---

## VERSÃO CURTA

Faça dois choropleths Leaflet de Campinas/SP para 2026, por bairro, com a mesma ideia
do projeto `eleicoes_2026_sao_paulo`: **Presidente 2º turno** e **Governador 1º
turno**, cor pela margem assinada em pp. Campinas **não tem bairro do IBGE** — use a
**UTB/UTR da Prefeitura** (`zoneamento.campinas.sp.gov.br/novo_zoneamento/exporta_shp.php?id=91`,
UUID efêmero, 93 polígonos, EPSG:31983, DBF Latin-1). **São dois arquivos do TSE, um
por disputa**: Presidente vem de `votacao_secao_2026_BR.zip` (241 MB → CSV 1,58 GB,
`CD_ELEICAO 6257`, turnos 1 e 2); Governador vem de `votacao_secao_2026_SP.zip`
(808 MB → CSV 4,95 GB, `CD_ELEICAO 6259`, só 1º turno) — **o `_SP.zip` não tem
Presidente e o `_BR.zip` não tem Governador**. Filtre cada um por
`CD_MUNICIPIO == 62910` — **código TSE, não IBGE** (`3509502` devolve zero linhas) —
**em streaming, um por vez** (disco tem ~1,6 GB livre), apagando o ZIP depois, exclua
`NR_VOTAVEL` 95/96, deduplique locais por `(NR_ZONA, NM_LOCAL_VOTACAO,
DS_LOCAL_VOTACAO_ENDERECO)`, geocodifique com Photon (`lang=default`, bbox
`-47.30,-23.13,-46.76,-22.67`, 1,5 req/s, cache), `st_join` na UTB, agregue e valide
com `stopifnot` (conservação de votos, 93 bairros, cobertura de geocodificação).
Derive os candidatos dos dados — não hardcode nomes. Abra os mapas num navegador real
e confirme `window.__feats.length === 93` antes de entregar.

---

## RACIONAL DAS DECISÕES

- **UTB em vez de bairro**: é a única subdivisão municipal oficial de Campinas com
  polígonos, e foi construída alinhada aos setores censitários do IBGE. Inventar
  bairros ou usar 5–7 distritos destruiria a granularidade do mapa.
- **Streaming do TSE**: os CSVs descompactados somam 6,5 GB e o disco tem ~1,6 GB
  livres — extrair quebraria a execução. Por isso: um arquivo por vez, filtro em
  pipe, ZIP apagado em seguida.
- **Dois arquivos do TSE**: o TSE publica 2026 em duas eleições separadas
  (`6257` federal / `6259` estadual). Presidente só existe no `_BR.zip`; Governador
  só no `_SP.zip`. Tratar como um único arquivo é o erro que zera um dos mapas.
- **Candidatos derivados dos dados**: o prompt precisa continuar válido sem saber de
  antemão quem disputou o 2º turno de 2026.
- **Gates calculados, não hardcoded**: a referência de votos válidos sai do próprio
  arquivo filtrado, então o pipeline não mente se o TSE republicar os dados.
- **Verificação em navegador**: mapa que não renderiza não é entregável, mesmo com
  todos os CSVs corretos.
