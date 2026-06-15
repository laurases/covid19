-- PROJETO: COVID-19 no Brasil
-- ETAPA: Views para importação no Power BI

-- ============================================================
-- VIEW 1 — Tabela Fato Principal (base no Power BI)

CREATE OR REPLACE VIEW vw_fato_covid AS
SELECT
c.date,
c.region,
c.state,
c.cases,
c.deaths,
c.novos_casos,
c.novos_obitos,
c.flag_correcao_dados,
c.ano,
c.mes,
c.semana_epi,
p.populacao,
ROUND(c.cases * 100000.0 / p.populacao, 2) AS casos_por_100k_hab,
ROUND(c.deaths * 100000.0 / p.populacao, 2) AS obitos_por_100k_hab
FROM covid19_limpo c
JOIN populacao_state p ON c.state = p.state;
 
-- ============================================================
-- VIEW 2 — Situação Atual por Estado
 
CREATE OR REPLACE VIEW vw_covid_por_uf AS
SELECT
c.state,
c.region,
c.cases,
c.deaths,
p.populacao,
ROUND(c.cases * 100000.0 / p.populacao, 2) AS casos_por_100k_hab,
ROUND(c.deaths * 100000.0 / p.populacao, 2) AS obitos_por_100k_hab,
ROUND(c.deaths * 100.0 / NULLIF(c.cases, 0), 2) AS letalidade_pct,
RANK() OVER (ORDER BY c.cases * 1.0 / p.populacao DESC) AS ranking_casos_percapita,
RANK() OVER (ORDER BY c.deaths * 1.0 / p.populacao DESC) AS ranking_obitos_percapita,
RANK() OVER (ORDER BY c.deaths * 1.0 / NULLIF(c.cases,0) DESC) AS ranking_letalidade
FROM covid19_limpo c
JOIN populacao_state p ON c.state = p.state
WHERE c.date = (SELECT MAX(date) FROM covid19_limpo);

-- ============================================================
-- VIEW 3 — Evolução Diária Nacional (com média móvel de 7 dias)
 
CREATE OR REPLACE VIEW vw_evolucao_nacional AS
WITH diario AS (
SELECT date, ano, mes, semana_epi,
SUM(novos_casos) AS novos_casos,
SUM(novos_obitos) AS novos_obitos,
SUM(cases) AS casos_acumulados,
SUM(deaths) AS obitos_acumulados
FROM covid19_limpo
GROUP BY date, ano, mes, semana_epi
)
SELECT
date, ano, mes, semana_epi,
novos_casos,
novos_obitos,
casos_acumulados,
obitos_acumulados,
ROUND(AVG(novos_casos) OVER (ORDER BY date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 1) AS media_movel_casos_7d,
ROUND(AVG(novos_obitos) OVER (ORDER BY date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 1) AS media_movel_obitos_7d
FROM diario;
  
-- ============================================================
-- VIEW 4 — Evolução Diária por Região
 
CREATE OR REPLACE VIEW vw_evolucao_regiao AS
SELECT date, region, ano, mes, semana_epi,
SUM(novos_casos) AS novos_casos,
SUM(novos_obitos) AS novos_obitos,
SUM(cases) AS casos_acumulados,
SUM(deaths) AS obitos_acumulados
FROM covid19_limpo
GROUP BY date, region, ano, mes, semana_epi;

-- ============================================================
-- VIEW 5 — Picos (Ondas) por Região
 
CREATE OR REPLACE VIEW vw_picos_regiao AS
WITH casos_regiao_dia AS (
    SELECT region, date,
	SUM(novos_casos) AS novos_casos,
	SUM(novos_obitos) AS novos_obitos
    FROM covid19_limpo
    GROUP BY region, date)
SELECT
region,
date,
novos_casos,
novos_obitos,
RANK() OVER (PARTITION BY region ORDER BY novos_casos DESC) AS ranking_pico_casos,
RANK() OVER (PARTITION BY region ORDER BY novos_obitos DESC) AS ranking_pico_obitos
FROM casos_regiao_dia;

-- ============================================================
-- VIEW 6 — Qualidade dos Dados (correções identificadas)
 
CREATE OR REPLACE VIEW vw_qualidade_dados AS
SELECT
date,
state,
region,
novos_casos,
novos_obitos,
flag_correcao_dados
FROM covid19_limpo
WHERE flag_correcao_dados = 1;

SHOW FULL TABLES IN covid19 WHERE TABLE_TYPE = 'VIEW';