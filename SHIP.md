
# Resumo Final - Eleições Campinas 2026

## Status da Execução
O pipeline foi executado com sucesso e todos os critérios de aceitação foram atendidos.

## Resultados Principais
- **Presidente (2º Turno)**: Flavio Bolsonaro venceu em 42 bairros (UTBs); Lula venceu em 11. 40 UTBs sem seções.
- **Governador (1º Turno)**: Tarcísio venceu em 52 bairros (UTBs); Haddad venceu em 1. 40 UTBs sem seções.

## Qualidade dos Dados
- **Geocodificação**: 259 de 268 locais resolvidos (**96,64%**).
- **Consistência**: Total de votos válidos bate 100% com o resultado oficial do município.
- **Integridade Espacial**: Todos os 2.511 setores censitários de Campinas têm seus centroides dentro de exatamente uma UTB.

## Entregas
- `index.html`: Landing page com placar e links para os mapas.
- `campinas_presidente_2t.html`: Mapa interativo (Leaflet).
- `campinas_governador_1t.html`: Mapa interativo (Leaflet).
- `output/resumo.md`: Relatório metodológico detalhado.
- `output/*.csv`: Dados agregados por bairro.

---
*Sisyphus - OhMyOpenCode*
