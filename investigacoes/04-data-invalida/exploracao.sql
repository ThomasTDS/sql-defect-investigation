-- Investigação 04 — Data inválida
-- Queries na ordem em que foram usadas na investigação. A numeração bate
-- com os passos do README.md desta pasta.

-- Passo 1: reproduzir o indicador relatado — tempo entre o pedido e a
-- aprovação do pagamento.
SELECT
    COUNT(*) AS qtd_pagamentos_aprovados,
    MIN(pg.data_pagamento - p.data_pedido) AS menor_tempo,
    MAX(pg.data_pagamento - p.data_pedido) AS maior_tempo,
    AVG(pg.data_pagamento - p.data_pedido) AS tempo_medio
FROM pagamentos pg
JOIN pedidos p ON p.id = pg.pedido_id
WHERE pg.status = 'aprovado';

-- Passo 2: todos os pagamentos aprovados, com o tempo até a aprovação.
-- Ordena do menor para o maior, para o valor negativo aparecer primeiro.
SELECT
    pg.id AS pagamento_id,
    p.id AS pedido_id,
    p.data_pedido,
    pg.data_pagamento,
    pg.data_pagamento - p.data_pedido AS tempo_ate_aprovacao
FROM pagamentos pg
JOIN pedidos p ON p.id = pg.pedido_id
WHERE pg.status = 'aprovado'
ORDER BY tempo_ate_aprovacao;

-- Passo 3: detalhe do pagamento suspeito e do pedido dele.
SELECT
    pg.id AS pagamento_id,
    pg.valor,
    pg.status AS status_pagamento,
    pg.data_pagamento,
    p.id AS pedido_id,
    p.status AS status_pedido,
    p.valor_total,
    p.data_pedido,
    c.nome AS cliente,
    v.nome AS vendedor
FROM pagamentos pg
JOIN pedidos p ON p.id = pg.pedido_id
JOIN clientes c ON c.id = p.cliente_id
LEFT JOIN vendedores v ON v.id = p.vendedor_id
WHERE pg.id = 10;

-- Passo 4: é isolado? Todas as datas implausíveis do banco
-- (mesma query de deteccao.sql).
SELECT 'pagamentos' AS tabela, pg.id AS registro_id,
       'pagamento anterior ao pedido' AS motivo,
       pg.data_pagamento AS data_registro, p.data_pedido AS data_referencia
FROM pagamentos pg
JOIN pedidos p ON p.id = pg.pedido_id
WHERE pg.data_pagamento < p.data_pedido
UNION ALL
SELECT 'pedidos', p.id, 'pedido anterior ao cadastro do cliente', p.data_pedido, c.data_cadastro
FROM pedidos p
JOIN clientes c ON c.id = p.cliente_id
WHERE p.data_pedido < c.data_cadastro
UNION ALL
SELECT 'clientes', id, 'data no futuro', data_cadastro, now()::timestamp
FROM clientes WHERE data_cadastro > now()
UNION ALL
SELECT 'pedidos', id, 'data no futuro', data_pedido, now()::timestamp
FROM pedidos WHERE data_pedido > now()
UNION ALL
SELECT 'pagamentos', id, 'data no futuro', data_pagamento, now()::timestamp
FROM pagamentos WHERE data_pagamento > now()
ORDER BY tabela, registro_id;

-- Passo 5: causa raiz — o que a tabela pagamentos registra sobre a
-- origem do lançamento?
SELECT column_name, data_type, column_default, is_nullable
FROM information_schema.columns
WHERE table_name = 'pagamentos'
ORDER BY ordinal_position;

SELECT conname, contype, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'pagamentos'::regclass
ORDER BY conname;

SELECT tgname
FROM pg_trigger
WHERE tgrelid = 'pagamentos'::regclass AND NOT tgisinternal;
