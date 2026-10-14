-- Investigação 03 — Status inconsistente
-- Queries na ordem em que foram usadas na investigação. A numeração bate
-- com os passos do README.md desta pasta.

-- Passo 1: o caso relatado — pedidos e pagamentos da cliente Carla
-- (cliente_id = 3).
SELECT
    p.id AS pedido_id,
    p.data_pedido,
    p.status AS status_pedido,
    p.valor_total,
    pg.id AS pagamento_id,
    pg.status AS status_pagamento,
    pg.valor AS valor_pago,
    pg.data_pagamento
FROM pedidos p
LEFT JOIN pagamentos pg ON pg.pedido_id = p.id
WHERE p.cliente_id = 3
ORDER BY p.id, pg.id;

-- Passo 2: matriz de status — quantos pedidos existem em cada
-- combinação de status do pedido x situação do pagamento.
WITH situacao AS (
    SELECT
        p.id AS pedido_id,
        p.status AS status_pedido,
        CASE
            WHEN bool_or(pg.status = 'aprovado') THEN 'aprovado'
            WHEN bool_or(pg.status = 'pendente') THEN 'pendente'
            WHEN bool_or(pg.status = 'estornado') THEN 'estornado'
            ELSE 'sem pagamento'
        END AS situacao_pagamento
    FROM pedidos p
    LEFT JOIN pagamentos pg ON pg.pedido_id = p.id
    GROUP BY p.id, p.status
)
SELECT status_pedido, situacao_pagamento, COUNT(*) AS qtd_pedidos,
       string_agg(pedido_id::text, ', ' ORDER BY pedido_id) AS pedidos
FROM situacao
GROUP BY status_pedido, situacao_pagamento
ORDER BY status_pedido, situacao_pagamento;

-- Passo 3: só as combinações inválidas (mesma query de deteccao.sql).
WITH situacao AS (
    SELECT
        p.id AS pedido_id,
        p.status AS status_pedido,
        CASE
            WHEN bool_or(pg.status = 'aprovado') THEN 'aprovado'
            WHEN bool_or(pg.status = 'pendente') THEN 'pendente'
            WHEN bool_or(pg.status = 'estornado') THEN 'estornado'
            ELSE 'sem pagamento'
        END AS situacao_pagamento
    FROM pedidos p
    LEFT JOIN pagamentos pg ON pg.pedido_id = p.id
    GROUP BY p.id, p.status
)
SELECT pedido_id, status_pedido, situacao_pagamento
FROM situacao
WHERE NOT (
       (status_pedido = 'pendente' AND situacao_pagamento IN ('sem pagamento', 'pendente'))
    OR (status_pedido IN ('confirmado', 'entregue') AND situacao_pagamento = 'aprovado')
    OR (status_pedido = 'cancelado' AND situacao_pagamento IN ('sem pagamento', 'estornado'))
)
ORDER BY pedido_id;

-- Passo 4: detalhe dos pedidos inconsistentes.
SELECT
    p.id AS pedido_id,
    p.cliente_id,
    c.nome AS cliente,
    p.data_pedido,
    p.status AS status_pedido,
    p.valor_total,
    pg.status AS status_pagamento,
    pg.valor AS valor_pago,
    pg.data_pagamento
FROM pedidos p
LEFT JOIN clientes c ON c.id = p.cliente_id
LEFT JOIN pagamentos pg ON pg.pedido_id = p.id
WHERE p.id IN (10, 11, 12)
ORDER BY p.id;

-- Passo 5: causa raiz — o que o banco garante sobre status hoje?
-- Constraints CHECK das tabelas pedidos e pagamentos.
SELECT conrelid::regclass AS tabela, conname, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE contype = 'c'
  AND conrelid IN ('pedidos'::regclass, 'pagamentos'::regclass);

-- Colunas de pedidos e pagamentos: existe algum registro de quando o
-- status mudou?
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_name IN ('pedidos', 'pagamentos')
ORDER BY table_name, ordinal_position;

-- Observação fora do escopo: clientes inativos e seus pedidos.
SELECT c.id AS cliente_id, c.nome, c.status AS status_cliente, c.data_cadastro,
       p.id AS pedido_id, p.data_pedido, p.status AS status_pedido
FROM clientes c
LEFT JOIN pedidos p ON p.cliente_id = c.id
WHERE c.status = 'inativo'
ORDER BY c.id, p.id;
