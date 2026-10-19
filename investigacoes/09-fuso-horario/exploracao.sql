-- Investigação 09 — Fuso horário misturado na mesma coluna
-- Queries na ordem em que foram usadas na investigação. A numeração bate
-- com os passos do README.md desta pasta.

-- Passo 1: pedidos cujo pagamento aprovado caiu em outro mês — é por
-- causa deles que vendas de janeiro (por data do pedido) e recebimentos
-- de janeiro (por data do pagamento) não batem.
SELECT
    p.id AS pedido_id,
    p.data_pedido,
    pg.data_pagamento,
    to_char(p.data_pedido, 'YYYY-MM') AS mes_do_pedido,
    to_char(pg.data_pagamento, 'YYYY-MM') AS mes_do_pagamento,
    p.valor_total
FROM pedidos p
JOIN pagamentos pg ON pg.pedido_id = p.id AND pg.status = 'aprovado'
WHERE to_char(p.data_pedido, 'YYYY-MM') <> to_char(pg.data_pagamento, 'YYYY-MM')
ORDER BY p.id;

-- Passo 2: o detalhe dos dois pedidos e o horário de todos os pedidos.
SELECT p.id AS pedido_id, c.nome AS cliente, p.vendedor_id, p.data_pedido, p.status, p.valor_total
FROM pedidos p
JOIN clientes c ON c.id = p.cliente_id
WHERE p.id IN (14, 15)
ORDER BY p.id;

SELECT
    COUNT(*) FILTER (WHERE extract(hour FROM data_pedido) BETWEEN 8 AND 20) AS pedidos_entre_8h_e_20h,
    COUNT(*) FILTER (WHERE extract(hour FROM data_pedido) NOT BETWEEN 8 AND 20) AS pedidos_fora_desse_horario,
    string_agg(id::text, ', ' ORDER BY id) FILTER (WHERE extract(hour FROM data_pedido) NOT BETWEEN 8 AND 20) AS quais
FROM pedidos;

-- Passo 3: o intervalo entre pedido e pagamento, antes e depois de
-- descontar as 3 horas do fuso.
SELECT
    p.id AS pedido_id,
    pg.data_pagamento - p.data_pedido AS diferenca_gravada,
    pg.data_pagamento - (p.data_pedido - interval '3 hours') AS diferenca_corrigida
FROM pedidos p
JOIN pagamentos pg ON pg.pedido_id = p.id AND pg.status = 'aprovado'
WHERE pg.data_pagamento < p.data_pedido
ORDER BY p.id;

-- Passo 4: detecção final (mesma query de deteccao.sql).
SELECT
    p.id AS pedido_id,
    p.data_pedido AS data_pedido_gravada,
    pg.data_pagamento,
    pg.data_pagamento - p.data_pedido AS diferenca_gravada,
    p.data_pedido - interval '3 hours' AS data_pedido_em_brasilia,
    pg.data_pagamento - (p.data_pedido - interval '3 hours') AS diferenca_corrigida
FROM pedidos p
JOIN pagamentos pg ON pg.pedido_id = p.id AND pg.status = 'aprovado'
WHERE pg.data_pagamento < p.data_pedido
  AND pg.data_pagamento - (p.data_pedido - interval '3 hours')
      BETWEEN interval '0 minutes' AND interval '30 minutes'
ORDER BY p.id;

-- Passo 5: causa raiz — o tipo das colunas de data.
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_name IN ('clientes', 'pedidos', 'pagamentos')
  AND data_type LIKE 'timestamp%'
ORDER BY table_name, column_name;

-- Passo 6: impacto — vendas por mês (pela data do pedido), como estão e
-- com a data dos dois pedidos corrigida para Brasília.
WITH corrigido AS (
    SELECT
        id,
        valor_total,
        CASE WHEN id IN (14, 15) THEN data_pedido - interval '3 hours' ELSE data_pedido END AS data_pedido
    FROM pedidos
)
SELECT
    m.mes,
    (SELECT SUM(valor_total) FROM pedidos WHERE to_char(data_pedido, 'YYYY-MM') = m.mes) AS vendas_como_estao,
    (SELECT SUM(valor_total) FROM corrigido WHERE to_char(data_pedido, 'YYYY-MM') = m.mes) AS vendas_corrigidas
FROM (VALUES ('2026-01'), ('2026-02')) AS m(mes)
ORDER BY m.mes;
