-- Investigação 07 — Texto com codificação quebrada (mojibake)
-- Queries na ordem em que foram usadas na investigação. A numeração bate
-- com os passos do README.md desta pasta.

-- Passo 1: o catálogo de produtos como está gravado no banco.
SELECT id, nome, categoria
FROM produtos
ORDER BY id;

-- Passo 2: os bytes de um nome correto e de um nome quebrado. Cada letra
-- acentuada ocupa 2 bytes em UTF-8; no texto quebrado, ocupa 4.
SELECT
    id,
    nome,
    length(nome) AS caracteres,
    octet_length(convert_to(nome, 'UTF8')) AS bytes_utf8,
    encode(convert_to(nome, 'UTF8'), 'hex') AS bytes_hex
FROM produtos
WHERE id IN (1, 6)
ORDER BY id;

-- Passo 3: prova do diagnóstico — desfazer o erro só na leitura (sem
-- alterar nada): pegar o texto, voltar para os bytes Windows-1252 e
-- reler como UTF-8.
SELECT
    id,
    nome AS gravado,
    convert_from(convert_to(nome, 'WIN1252'), 'UTF8') AS relido_como_utf8
FROM produtos
WHERE nome ~ '[ÃÂ][¡-¿€‚ƒ„…†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ]'
ORDER BY id;

-- Passo 4: é isolado? Texto quebrado em todas as colunas de texto do
-- banco (mesma query de deteccao.sql).
WITH textos (tabela, registro_id, coluna, valor) AS (
    SELECT 'clientes', id, 'nome', nome FROM clientes
    UNION ALL SELECT 'clientes', id, 'email', email FROM clientes
    UNION ALL SELECT 'vendedores', id, 'nome', nome FROM vendedores
    UNION ALL SELECT 'vendedores', id, 'equipe', equipe FROM vendedores
    UNION ALL SELECT 'produtos', id, 'nome', nome FROM produtos
    UNION ALL SELECT 'produtos', id, 'categoria', categoria FROM produtos
)
SELECT tabela, registro_id, coluna, valor
FROM textos
WHERE valor ~ '[ÃÂ][¡-¿€‚ƒ„…†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ]'
ORDER BY tabela, coluna, registro_id;

-- Passo 5: impacto — pedidos que têm itens dos produtos com nome quebrado
-- (são os que mostram o nome errado em e-mails e documentos).
SELECT
    pr.id AS produto_id,
    pr.nome AS produto,
    COUNT(i.id) AS qtd_itens,
    array_to_string(array_agg(DISTINCT i.pedido_id ORDER BY i.pedido_id), ', ') AS pedidos
FROM produtos pr
LEFT JOIN itens_pedido i ON i.produto_id = pr.id
WHERE pr.nome ~ '[ÃÂ][¡-¿€‚ƒ„…†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ]'
GROUP BY pr.id, pr.nome
ORDER BY pr.id;
