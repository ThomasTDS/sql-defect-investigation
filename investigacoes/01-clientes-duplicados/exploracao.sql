-- Investigação 01 — Clientes duplicados
-- Queries na ordem em que foram usadas na investigação. A numeração bate
-- com os passos do README.md desta pasta.

-- Passo 1: olhar o caso relatado no chamado.
SELECT id, nome, email, documento, telefone, data_cadastro, status
FROM clientes
WHERE lower(trim(email)) = 'ana.ferreira@example.com'
ORDER BY id;

-- Passo 2: o caso é isolado ou existe em outros clientes?
-- (mesma query de deteccao.sql)
SELECT
    a.id AS id_original,
    b.id AS id_duplicado,
    a.nome AS nome_original,
    b.nome AS nome_duplicado,
    lower(trim(a.email)) = lower(trim(b.email)) AS mesmo_email,
    regexp_replace(a.documento, '\D', '', 'g') = regexp_replace(b.documento, '\D', '', 'g') AS mesmo_documento,
    b.data_cadastro - a.data_cadastro AS intervalo_entre_cadastros
FROM clientes a
JOIN clientes b
    ON a.id < b.id
   AND (
        lower(trim(a.email)) = lower(trim(b.email))
        OR regexp_replace(a.documento, '\D', '', 'g') = regexp_replace(b.documento, '\D', '', 'g')
   )
ORDER BY a.id, b.id;

-- Passo 3: impacto — quais registros do par têm pedidos e pagamentos
-- vinculados? Define qual registro deve ser mantido numa correção.
SELECT
    c.id AS cliente_id,
    c.nome,
    c.data_cadastro,
    COUNT(DISTINCT p.id) AS qtd_pedidos,
    COUNT(pg.id) AS qtd_pagamentos
FROM clientes c
LEFT JOIN pedidos p ON p.cliente_id = c.id
LEFT JOIN pagamentos pg ON pg.pedido_id = p.id
WHERE c.id IN (1, 11)
GROUP BY c.id, c.nome, c.data_cadastro
ORDER BY c.id;

-- Passo 4: causa raiz — o que o banco garante hoje na tabela clientes?
-- Lista todas as constraints e índices únicos da tabela.
SELECT conname AS constraint_nome, contype AS tipo, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'clientes'::regclass
ORDER BY conname;

SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'clientes'
ORDER BY indexname;
