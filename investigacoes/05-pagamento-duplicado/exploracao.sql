-- Investigação 05 — Pagamento em duplicidade
-- Queries na ordem em que foram usadas na investigação. A numeração bate
-- com os passos do README.md desta pasta.

-- Passo 1: o caso relatado — pedido 2: valor do pedido x pagamentos
-- registrados.
SELECT
    p.id AS pedido_id,
    p.status AS status_pedido,
    p.valor_total,
    pg.id AS pagamento_id,
    pg.valor,
    pg.status AS status_pagamento,
    pg.data_pagamento
FROM pedidos p
JOIN pagamentos pg ON pg.pedido_id = p.id
WHERE p.id = 2
ORDER BY pg.data_pagamento, pg.id;

-- Passo 2: é isolado? Pedidos em que a soma dos pagamentos aprovados
-- passa do valor_total.
SELECT
    p.id AS pedido_id,
    p.valor_total,
    COUNT(pg.id) AS qtd_pagamentos_aprovados,
    SUM(pg.valor) AS soma_aprovados,
    SUM(pg.valor) - p.valor_total AS excedente
FROM pedidos p
JOIN pagamentos pg ON pg.pedido_id = p.id AND pg.status = 'aprovado'
GROUP BY p.id, p.valor_total
HAVING SUM(pg.valor) > p.valor_total
ORDER BY p.id;

-- Passo 3: a assinatura da duplicidade — cada pagamento aprovado ao lado
-- do anterior do mesmo pedido (LAG), com o intervalo entre eles.
SELECT
    pg.pedido_id,
    pg.id AS pagamento_id,
    pg.valor,
    pg.data_pagamento,
    LAG(pg.id) OVER janela AS pagamento_anterior,
    LAG(pg.valor) OVER janela AS valor_anterior,
    pg.data_pagamento - LAG(pg.data_pagamento) OVER janela AS intervalo
FROM pagamentos pg
WHERE pg.status = 'aprovado'
  AND pg.pedido_id IN (
      SELECT pedido_id FROM pagamentos
      WHERE status = 'aprovado'
      GROUP BY pedido_id
      HAVING COUNT(*) > 1
  )
WINDOW janela AS (PARTITION BY pg.pedido_id ORDER BY pg.data_pagamento, pg.id)
ORDER BY pg.pedido_id, pg.data_pagamento, pg.id;

-- Passo 4: detecção final (mesma query de deteccao.sql).
WITH aprovados AS (
    SELECT
        pg.id,
        pg.pedido_id,
        pg.valor,
        pg.data_pagamento,
        LAG(pg.id) OVER janela AS id_anterior,
        LAG(pg.valor) OVER janela AS valor_anterior,
        LAG(pg.data_pagamento) OVER janela AS data_anterior,
        SUM(pg.valor) OVER (PARTITION BY pg.pedido_id) AS soma_aprovados
    FROM pagamentos pg
    WHERE pg.status = 'aprovado'
    WINDOW janela AS (PARTITION BY pg.pedido_id ORDER BY pg.data_pagamento, pg.id)
)
SELECT
    a.pedido_id,
    a.id_anterior AS pagamento_original,
    a.id AS pagamento_duplicado,
    a.valor,
    a.data_anterior AS data_original,
    a.data_pagamento AS data_duplicado,
    a.data_pagamento - a.data_anterior AS intervalo,
    p.valor_total,
    a.soma_aprovados
FROM aprovados a
JOIN pedidos p ON p.id = a.pedido_id
WHERE a.valor = a.valor_anterior
  AND a.data_pagamento - a.data_anterior <= interval '10 minutes'
  AND a.soma_aprovados > p.valor_total
ORDER BY a.pedido_id, a.id;

-- Passo 5: causa raiz — existe algo na tabela que identifique a
-- transação no gateway e impeça registrá-la duas vezes?
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'pagamentos'
ORDER BY ordinal_position;

SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'pagamentos'
ORDER BY indexname;
