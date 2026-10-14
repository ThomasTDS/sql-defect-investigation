-- Premissa da massa de controle (NÃO é regra de negócio): o preço
-- unitário de cada item é o preço atual do produto no catálogo.
--
-- Num sistema real, o item guarda o preço da época da venda justamente
-- porque o catálogo muda, então essa diferença seria normal. Aqui ela só
-- vale porque a massa de dados não tem histórico de preços nem descontos.
-- Por isso, este check roda apenas contra a massa válida.
--
-- Cada linha é um item que quebra a premissa. Esperado: zero linhas.

SELECT
    i.id AS item_id,
    i.pedido_id,
    pr.nome AS produto,
    pr.preco AS preco_catalogo,
    i.preco_unitario
FROM itens_pedido i
JOIN produtos pr ON pr.id = i.produto_id
WHERE i.preco_unitario <> pr.preco
ORDER BY i.id;
