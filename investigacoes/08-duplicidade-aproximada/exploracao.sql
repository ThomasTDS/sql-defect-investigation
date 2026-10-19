-- Investigação 08 — Duplicidade aproximada no catálogo
-- Queries na ordem em que foram usadas na investigação. A numeração bate
-- com os passos do README.md desta pasta.

-- Passo 1: o relatório de vendas por produto, como o time comercial vê.
SELECT
    pr.id AS produto_id,
    pr.nome AS produto,
    COUNT(i.id) AS qtd_itens,
    COALESCE(SUM(i.quantidade * i.preco_unitario), 0) AS receita
FROM produtos pr
LEFT JOIN itens_pedido i ON i.produto_id = pr.id
GROUP BY pr.id, pr.nome
ORDER BY receita DESC, pr.id;

-- Passo 2: a busca exata não acha o produto suspeito — nem ignorando
-- maiúsculas e pontuação.
SELECT
    id,
    nome,
    lower(nome) = lower('Consultoria Avulsa (hora)') AS igual_ignorando_maiusculas,
    trim(regexp_replace(lower(nome), '[[:punct:][:space:]]+', ' ', 'g'))
        = trim(regexp_replace(lower('Consultoria Avulsa (hora)'), '[[:punct:][:space:]]+', ' ', 'g')) AS igual_sem_pontuacao
FROM produtos
WHERE id IN (5, 9)
ORDER BY id;

-- Passo 3: similaridade entre todos os pares de produtos, da maior para a
-- menor (as 6 maiores).
SELECT
    a.id AS produto_a,
    b.id AS produto_b,
    a.nome AS nome_a,
    b.nome AS nome_b,
    round(similarity(a.nome, b.nome)::numeric, 3) AS similaridade
FROM produtos a
JOIN produtos b ON a.id < b.id
ORDER BY similarity(a.nome, b.nome) DESC, a.id, b.id
LIMIT 6;

-- Passo 4: detecção final (mesma query de deteccao.sql).
SELECT
    a.id AS produto_original,
    b.id AS produto_suspeito,
    a.nome AS nome_original,
    b.nome AS nome_suspeito,
    round(similarity(a.nome, b.nome)::numeric, 3) AS similaridade,
    a.preco = b.preco AS mesmo_preco
FROM produtos a
JOIN produtos b
    ON a.id < b.id
   AND similarity(a.nome, b.nome) >= 0.6
ORDER BY similaridade DESC, a.id, b.id;

-- Passo 5: impacto — as vendas de consultoria somando os dois cadastros.
SELECT
    pr.id AS produto_id,
    pr.nome AS produto,
    pr.categoria,
    array_to_string(array_agg(i.pedido_id ORDER BY i.pedido_id), ', ') AS pedidos,
    SUM(i.quantidade * i.preco_unitario) AS receita
FROM produtos pr
JOIN itens_pedido i ON i.produto_id = pr.id
WHERE pr.id IN (5, 9)
GROUP BY pr.id, pr.nome, pr.categoria
ORDER BY pr.id;

-- Passo 6: causa raiz — o que o banco garante sobre o nome do produto?
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'produtos'
ORDER BY indexname;
