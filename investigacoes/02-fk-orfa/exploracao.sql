-- Investigação 02 — Foreign key órfã
-- Queries na ordem em que foram usadas na investigação. A numeração bate
-- com os passos do README.md desta pasta.

-- Passo 1: reproduzir a divergência relatada — total de pedidos direto
-- na tabela vs. total do relatório de vendas por cliente (que faz JOIN
-- com clientes).
SELECT
    (SELECT COUNT(*) FROM pedidos) AS qtd_pedidos_tabela,
    (SELECT SUM(valor_total) FROM pedidos) AS total_tabela,
    (SELECT COUNT(*) FROM pedidos p JOIN clientes c ON c.id = p.cliente_id) AS qtd_pedidos_relatorio,
    (SELECT SUM(p.valor_total) FROM pedidos p JOIN clientes c ON c.id = p.cliente_id) AS total_relatorio;

-- Passo 2: quais pedidos o JOIN está descartando?
SELECT p.id, p.cliente_id, p.vendedor_id, p.data_pedido, p.status, p.valor_total
FROM pedidos p
LEFT JOIN clientes c ON c.id = p.cliente_id
WHERE c.id IS NULL;

-- Passo 3: o cliente 12 chegou a existir? Compara o último valor gerado
-- pela sequence de clientes com os ids que existem hoje, e lista os ids
-- que foram gerados mas não estão mais na tabela.
SELECT
    (SELECT last_value FROM clientes_id_seq) AS ultimo_id_gerado,
    (SELECT MAX(id) FROM clientes) AS maior_id_existente,
    (SELECT COUNT(*) FROM clientes) AS qtd_clientes;

SELECT s.id AS id_gerado_e_ausente
FROM generate_series(1, (SELECT last_value FROM clientes_id_seq)) AS s(id)
LEFT JOIN clientes c ON c.id = s.id
WHERE c.id IS NULL;

-- Passo 4: como o banco permitiu? Estado de todas as foreign keys do
-- schema — convalidated = false significa que a constraint nunca foi
-- verificada contra os dados que já existiam.
SELECT
    conrelid::regclass AS tabela,
    conname AS constraint_nome,
    convalidated AS validada,
    pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE contype = 'f'
ORDER BY conrelid::regclass::text, conname;

-- Passo 5: é isolado? Órfãos em todas as foreign keys do schema
-- (mesma query de deteccao.sql).
SELECT 'pedidos' AS tabela, p.id AS registro_id, 'cliente_id' AS coluna, p.cliente_id AS aponta_para
FROM pedidos p LEFT JOIN clientes c ON c.id = p.cliente_id
WHERE c.id IS NULL
UNION ALL
SELECT 'pedidos', p.id, 'vendedor_id', p.vendedor_id
FROM pedidos p LEFT JOIN vendedores v ON v.id = p.vendedor_id
WHERE p.vendedor_id IS NOT NULL AND v.id IS NULL
UNION ALL
SELECT 'itens_pedido', i.id, 'pedido_id', i.pedido_id
FROM itens_pedido i LEFT JOIN pedidos p ON p.id = i.pedido_id
WHERE p.id IS NULL
UNION ALL
SELECT 'itens_pedido', i.id, 'produto_id', i.produto_id
FROM itens_pedido i LEFT JOIN produtos pr ON pr.id = i.produto_id
WHERE pr.id IS NULL
UNION ALL
SELECT 'pagamentos', pg.id, 'pedido_id', pg.pedido_id
FROM pagamentos pg LEFT JOIN pedidos p ON p.id = pg.pedido_id
WHERE p.id IS NULL
ORDER BY tabela, registro_id;

-- Passo 6: impacto — o pedido órfão tem itens e pagamentos?
SELECT
    p.id AS pedido_id,
    p.status,
    p.valor_total,
    (SELECT COUNT(*) FROM itens_pedido i WHERE i.pedido_id = p.id) AS qtd_itens,
    (SELECT COUNT(*) FROM pagamentos pg WHERE pg.pedido_id = p.id) AS qtd_pagamentos
FROM pedidos p
WHERE p.id = 10;
