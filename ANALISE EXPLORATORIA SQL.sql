-- PROJETO: COVID-19 no Brasil — Análise de Casos e Óbitos
-- ETAPA: Análise Exploratória de Dados

-- ============================================================
-- PERGUNTA 1 - Como evoluíram os casos e óbitos ao longo do tempo?
 
-- Evolução mensal nacional de novos casos e óbitos
SELECT * FROM covid19_limpo;
SELECT ano, mes,
SUM(novos_casos)  AS novos_casos,
SUM(novos_obitos) AS novos_obitos
FROM covid19_limpo
GROUP BY ano, mes
ORDER BY ano, mes;

-- Média móvel de 7 dias de novos casos (nacional)
SELECT * FROM covid19_limpo;
WITH casos_diarios AS (
    SELECT date,
	SUM(novos_casos)  AS novos_casos,
	SUM(novos_obitos) AS novos_obitos
    FROM covid19_limpo
    GROUP BY date
)
SELECT date, novos_casos, novos_obitos,
ROUND(AVG(novos_casos) OVER (ORDER BY date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 1) AS media_movel_casos_7d,
ROUND(AVG(novos_obitos) OVER (ORDER BY date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 1) AS media_movel_obitos_7d
FROM casos_diarios
ORDER BY date;

-- Crescimento acumulado mês a mês (nacional)
SELECT * FROM covid19_limpo;
WITH totais_mensais AS (
    SELECT
        ano, mes,
        MAX(casos_acumulados) AS casos_fim_mes
    FROM (
        SELECT
            ano, mes, state,
            MAX(cases) AS casos_acumulados
        FROM covid19_limpo
        GROUP BY ano, mes, state
    ) t
    GROUP BY ano, mes
)
SELECT
    ano, mes,
    casos_fim_mes,
    LAG(casos_fim_mes) OVER (ORDER BY ano, mes) AS casos_mes_anterior,
    ROUND(
        (casos_fim_mes - LAG(casos_fim_mes) OVER (ORDER BY ano, mes)) * 100.0 /
        NULLIF(LAG(casos_fim_mes) OVER (ORDER BY ano, mes), 0),
    2) AS variacao_pct
FROM totais_mensais
ORDER BY ano, mes;

-- ============================================================
-- PERGUNTA 2: Quais estados e regiões foram mais afetados (absoluto e relativo à população)?
 
-- Casos e óbitos acumulados no final do período, por estado
SELECT * FROM covid19_limpo;
SELECT * FROM populacao_state;
SELECT c.state, c.region, c.cases, c.deaths,
    p.populacao,
    ROUND(c.cases  * 100000.0 / p.populacao, 1) AS casos_por_100k_hab,
    ROUND(c.deaths * 100000.0 / p.populacao, 1) AS obitos_por_100k_hab,
    RANK() OVER (ORDER BY c.cases  * 1.0 / p.populacao DESC) AS ranking_casos_percapita,
    RANK() OVER (ORDER BY c.deaths * 1.0 / p.populacao DESC) AS ranking_obitos_percapita
FROM covid19_limpo c
JOIN populacao_state p ON c.state = p.state
WHERE c.date = (SELECT MAX(date) FROM covid19_limpo)
ORDER BY casos_por_100k_hab DESC;

-- Totais por região no final do período
SELECT * FROM covid19_limpo;
SELECT * FROM populacao_state;
SELECT c.region,
SUM(c.cases) AS casos_totais,
SUM(c.deaths) AS obitos_totais,
SUM(p.populacao) AS populacao_total,
ROUND(SUM(c.cases) * 100000.0 / SUM(p.populacao), 1) AS casos_por_100k_hab,
ROUND(SUM(c.deaths) * 100000.0 / SUM(p.populacao), 1) AS obitos_por_100k_hab
FROM covid19_limpo c
JOIN populacao_state p ON c.state = p.state
WHERE c.date = (SELECT MAX(date) FROM covid19_limpo)
GROUP BY c.region
ORDER BY casos_totais DESC;

-- ============================================================
-- PERGUNTA 3: Qual a taxa de letalidade aparente por estado?
-- (letalidade = óbitos / casos confirmados), NÃO é mortalidade

SELECT * FROM covid19_limpo;
SELECT state, region, cases, deaths,
ROUND(deaths * 100.0 / NULLIF(cases, 0), 2) AS letalidade_pct,
RANK() OVER (ORDER BY deaths * 1.0 / NULLIF(cases, 0) DESC) AS ranking_letalidade
FROM covid19_limpo
WHERE date = (SELECT MAX(date) FROM covid19_limpo)
ORDER BY letalidade_pct DESC;

-- Letalidade nacional (referência geral)
SELECT
ROUND(SUM(deaths) * 100.0 / SUM(cases), 2) AS letalidade_nacional_pct
FROM covid19_limpo
WHERE date = (SELECT MAX(date) FROM covid19_limpo);


-- ============================================================
-- PERGUNTA 4: Existe relação entre população e taxa de casos/óbitos por habitante?

-- Classificar estados por porte populacional e comparar taxas médias
WITH ultima AS (
    SELECT c.*, p.populacao
    FROM covid19_limpo c
    JOIN populacao_state p ON c.state = p.state
    WHERE c.date = (SELECT MAX(date) FROM covid19_limpo)
),
classificado AS (
    SELECT *,
	CASE
		WHEN populacao >= 10000000 THEN 'Grande (10M+)'
		WHEN populacao >= 3000000  THEN 'Médio (3-10M)'
		ELSE 'Pequeno (<3M)'
        END AS porte_populacional
    FROM ultima
)
SELECT porte_populacional,
COUNT(*) AS qtd_estados,
ROUND(AVG(cases * 100000.0 / populacao), 1) AS media_casos_por_100k,
ROUND(AVG(deaths * 100000.0 / populacao), 1) AS media_obitos_por_100k
FROM classificado
GROUP BY porte_populacional
ORDER BY media_casos_por_100k DESC;

-- Estados pequenos com taxas desproporcionalmente altas
SELECT * FROM covid19_limpo;
SELECT * FROM populacao_state;
SELECT 
c.state, c.region, p.populacao,
ROUND(c.cases * 100000.0 / p.populacao, 1) AS casos_por_100k_hab
FROM covid19_limpo c
JOIN populacao_state p ON c.state = p.state
WHERE c.date = (SELECT MAX(date) FROM covid19_limpo)
  AND p.populacao < 3000000
ORDER BY casos_por_100k_hab DESC;


-- ============================================================
-- PERGUNTA 5: Quando ocorreram os picos de novos casos/óbitos por região?

-- Dia de pico de novos casos por região
SELECT * FROM covid19_limpo;
WITH casos_regiao_dia AS (
SELECT region, date,
SUM(novos_casos) AS novos_casos
FROM covid19_limpo
GROUP BY region, date),
ranqueado AS (
SELECT *,
RANK() OVER (PARTITION BY region ORDER BY novos_casos DESC) AS posicao
FROM casos_regiao_dia)
SELECT region, date AS data_pico, novos_casos AS pico_novos_casos
FROM ranqueado
WHERE posicao = 1
ORDER BY pico_novos_casos DESC;

-- Dia de pico de novos óbitos por região
SELECT * FROM covid19_limpo;
WITH obitos_regiao_dia AS (
SELECT region, date,
SUM(novos_obitos) AS novos_obitos
FROM covid19_limpo
GROUP BY region, date),
ranqueado AS (
SELECT *,
RANK() OVER (PARTITION BY region ORDER BY novos_obitos DESC) AS posicao
FROM obitos_regiao_dia
)
SELECT region, date AS data_pico, novos_obitos AS pico_novos_obitos
FROM ranqueado
WHERE posicao = 1
ORDER BY pico_novos_obitos DESC;

-- Identificar "ondas": semanas epidemiológicas com maior volume nacional
SELECT * FROM covid19_limpo;
SELECT ano, semana_epi,
SUM(novos_casos)  AS novos_casos,
SUM(novos_obitos) AS novos_obitos
FROM covid19_limpo
GROUP BY ano, semana_epi
ORDER BY novos_casos DESC
LIMIT 10;

-- ============================================================
-- ANÁLISE COMPLEMENTAR
-- Top 10 dias com correção de dados
 
SELECT date, state, region, novos_casos, novos_obitos, flag_correcao_dados
FROM covid19_limpo
WHERE flag_correcao_dados = 1
ORDER BY date, state;