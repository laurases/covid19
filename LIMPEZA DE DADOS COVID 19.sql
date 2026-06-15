CREATE TABLE brazil_covid19 (
date date NOT NULL,
region varchar(20) NOT NULL,
state char(2) NOT NULL,
cases decimal(8,1) NOT NULL,
deaths int NOT NULL
);
-- Importado arquivo CSV 
-- Verficando a Tabela Importada 
SELECT * FROM brazil_covid19;

-- LIMPEZA
-- Volume total e período --
SELECT COUNT(*) AS total_registros,
MIN(date) AS data_inicial,
MAX(date) AS data_final,
COUNT(DISTINCT state) AS qtd_estados,
COUNT(DISTINCT date) AS qtd_datas
FROM brazil_covid19;

-- VALORES NULOS
SELECT
SUM(CASE WHEN date IS NULL THEN 1 ELSE 0 END) AS data_nula,
SUM(CASE WHEN state IS NULL OR state = '' THEN 1 ELSE 0 END) AS state_nula,
SUM(CASE WHEN region IS NULL OR region = '' THEN 1 ELSE 0 END) AS region_nula,
SUM(CASE WHEN cases IS NULL THEN 1 ELSE 0 END) AS cases_nulos,
SUM(CASE WHEN deaths IS NULL THEN 1 ELSE 0 END) AS deaths_nulos
FROM brazil_covid19;

-- VALORES DUPLICADOS
SELECT date, state, COUNT(*) AS quantidade
FROM brazil_covid19
GROUP BY date, state
HAVING COUNT(*) > 1;

-- VERIFICANDO COMBINAÇÕES DE DATA E REGIÃO --
SELECT
(SELECT COUNT(DISTINCT date) FROM brazil_covid19) *
(SELECT COUNT(DISTINCT state) FROM brazil_covid19) AS combinacoes_esperadas,
COUNT(*) AS combinacoes_reais
FROM brazil_covid19;

-- O arquivo mostra valores acumulados, análises de tendência preciso do diário --
CREATE OR REPLACE VIEW vw_covid_diario AS
SELECT date, region, state, cases, deaths,
cases - LAG(cases) OVER (PARTITION BY state ORDER BY date) AS casos_diario,
deaths - LAG(deaths) OVER (PARTITION BY state ORDER BY date) AS obitos_diario
FROM brazil_covid19;

SELECT * FROM vw_covid_diario;

-- Ver se tem valores diários negativo --
SELECT date, state, casos_diario, obitos_diario
FROM vw_covid_diario
WHERE casos_diario < 0 OR obitos_diario < 0
ORDER BY date, state;

-- Ver o impacto: quantos dias por estado teve correção --
SELECT state,
SUM(CASE WHEN casos_diario < 0 THEN 1 ELSE 0 END) AS dias_correcao_casos,
SUM(CASE WHEN obitos_diario < 0 THEN 1 ELSE 0 END) AS dias_correcao_obitos
FROM vw_covid_diario
GROUP BY state
HAVING dias_correcao_casos > 0 OR dias_correcao_obitos > 0
ORDER BY state;

-- Fazendo uma Tabela com Dados LIMPOS (valores negativos devem ser zerados e o valor acumulado é preservado por ser dado oficial
-- Uma flag marca os dias com correção para transparência.

SELECT * FROM vw_covid_diario;

CREATE TABLE covid19_limpo
SELECT date, region, state, cases, deaths,
    -- Primeiro dia de cada estado: novo = acumulado (não há LAG)
    GREATEST(COALESCE(casos_diario, cases), 0) AS novos_casos,
    GREATEST(COALESCE(obitos_diario, deaths), 0) AS novos_obitos,
    CASE WHEN casos_diario < 0 OR obitos_diario < 0
    THEN 1 ELSE 0 END AS flag_correcao_dados,
    YEAR(date) AS ano,
    MONTH(date) AS mes,
    -- Semana epidemiológica (aproximação ISO)
    WEEK(date, 3) AS semana_epi
FROM vw_covid_diario;
 
-- Quantidade de Linhas(deve ser igual ao brazil_covid19, pois não foi removido linha) --
SELECT COUNT(*) AS registros_limpo 
FROM covid19_limpo;

SELECT * FROM covid19_limpo;

-- Fazendo uma Tabela da População para indicadores --
-- Fonte: estimativas IBGE 2021 --

CREATE TABLE IF NOT EXISTS populacao_state (
state CHAR(2) PRIMARY KEY,
populacao int
);
 
INSERT INTO populacao_state (state, populacao) VALUES
('AC',  906876),  ('AL', 3365351),  ('AM', 4269995),  ('AP',  877613),
('BA', 14985284), ('CE', 9240580),  ('DF', 3094325),  ('ES', 4108508),
('GO', 7206589),  ('MA', 7153262),  ('MG', 21411923), ('MS', 2839188),
('MT', 3567234),  ('PA', 8777124),  ('PB', 4059905),  ('PE', 9674793),
('PI', 3289290),  ('PR', 11597484), ('RJ', 17463349), ('RN', 3560903),
('RO', 1815278),  ('RR',  652713),  ('RS', 11466630), ('SC', 7338473),
('SE', 2338474),  ('SP', 46649132), ('TO', 1607363);
 
 -- Total de Casos e Óbitos no fim do período, por região --
 SELECT * FROM covid19_limpo;
 SELECT region,
 SUM(cases) AS casos_totais,
 SUM(deaths) AS obitos_totais
FROM covid19_limpo
WHERE date=(SELECT MAX(date) FROM covid19_limpo)
GROUP BY region
ORDER BY casos_totais DESC;

-- Letalidade por estado (óbitos/casos no fim do período) --
SELECT * FROM covid19_limpo;
SELECT state, cases, deaths,
ROUND(deaths * 100.0 / NULLIF(cases, 0), 2) AS letalidade_pct
FROM covid19_limpo
WHERE date = (SELECT MAX(date) FROM covid19_limpo)
ORDER BY letalidade_pct DESC;

-- Total de dias com a correção de dados (visão geral da qualidade dos dados) --
SELECT
SUM(flag_correcao_dados) AS total_dias_correcao,
COUNT(*) AS total_registros,
ROUND(SUM(flag_correcao_dados) * 100.0 / COUNT(*), 3) AS pct_correcoes
FROM covid19_limpo;

-- Investigando se há valores anormalmente altos --
SELECT * FROM covid19_limpo;
SELECT state, date, novos_casos
FROM covid19_limpo
ORDER BY novos_casos DESC
LIMIT 15;

-- Adicionando questão de qualidade na Tabela --
ALTER TABLE covid19_limpo
ADD COLUMN status_qualidade VARCHAR(30);

SELECT * FROM covid19_limpo;

SET SQL_SAFE_UPDATES = 0;
UPDATE covid19_limpo SET status_qualidade =
CASE WHEN novos_casos < 0 OR novos_obitos < 0 THEN 'Correção Oficial'
WHEN novos_casos IS NULL OR novos_obitos IS NULL THEN 'Dado Faltante'
WHEN novos_casos > 50000 THEN 'Verificar Casos'
WHEN novos_casos = 0 AND novos_obitos = 0 THEN 'Sem Notificação'
ELSE 'VALIDO' END;
SET SQL_SAFE_UPDATES = 1;

SELECT * FROM covid19_limpo;

-- Ranking dos Estadaos mais Afetados
SELECT state,
MAX(cases) AS total_casos
FROM covid19_limpo
GROUP BY state
ORDER BY total_casos DESC;

-- Picos dos Novos Casos
SELECT date,
SUM(novos_casos) AS casos_brasil
FROM covid19_limpo
GROUP BY date
ORDER BY casos_brasil DESC;

-- Evolucao Mensal --
SELECT ano, mes,
SUM(novos_casos) AS casos_mes
FROM covid19_limpo
GROUP BY ano, mes
ORDER BY ano, mes;

-- Estados que mais tiveram aumento percentual de casos ao longo da pandemia --
SELECT * FROM covid19_limpo;
SELECT state, 
MIN(cases) AS casos_inicio,
MAX(cases) AS casos_fim,
ROUND(((MAX(cases) - MIN(cases)) * 100.0) / NULLIF(MIN(cases), 0), 2) AS crescimento_pct
FROM covid19_limpo
GROUP BY state
ORDER BY crescimento_pct DESC;

-- Média diária de novos casos por estado -- 
SELECT state,
ROUND(AVG(novos_casos), 0) AS media_diaria_casos
FROM covid19_limpo
GROUP BY state
ORDER BY media_diaria_casos DESC;

-- Estados com maior volatilidade --
SELECT state,
ROUND(STDDEV(novos_casos),0) AS volatilidade
FROM covid19_limpo
GROUP BY state
ORDER BY volatilidade DESC;

-- Análise de qualidade dos dados --
SELECT status_qualidade,
COUNT(*) AS quantidade
FROM covid19_limpo
GROUP BY status_qualidade;

-- Correções oficiais por estado -- 
SELECT * FROM covid19_limpo;
SELECT state,
COUNT(*) AS total_correcoes
FROM covid19_limpo
WHERE status_qualidade = 'Correção Oficial'
GROUP BY state
ORDER BY total_correcoes DESC;

-- Top 10 dias mais críticos da pandemia além do pico absoluto --
SELECT date,
SUM(novos_casos) AS casos_brasil
FROM covid19_limpo
GROUP BY date
ORDER BY casos_brasil DESC
LIMIT 10;

-- Média móvel de 7 dias --
SELECT date, state, novos_casos,
ROUND(
	AVG(novos_casos) OVER (
            PARTITION BY state
            ORDER BY date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ),
        0
    ) AS media_movel_7d
FROM covid19_limpo;

-- Participação de cada estado nos casos nacionais -- 
SELECT state,
    ROUND(
        MAX(cases) * 100.0 /
        (SELECT SUM(total_casos)
         FROM (
             SELECT MAX(cases) AS total_casos
             FROM covid19_limpo
             GROUP BY state
         ) t),
        2
    ) AS participacao_pct
FROM covid19_limpo
GROUP BY state
ORDER BY participacao_pct DESC;