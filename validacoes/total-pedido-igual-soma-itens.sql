-- Regra: o valor_total de um pedido é a soma dos seus itens
-- (quantidade x preço unitário).
--
-- Pedido sem nenhum item conta como soma zero, então um pedido com valor
-- e sem itens também aparece aqui.
--
-- Cada linha é um pedido que quebra a regra. Esperado: zero linhas.

SELECT
    p.id AS pedido_id,
    p.valor_total,
    COALESCE(SUM(i.quantidade * i.preco_unitario), 0) AS soma_itens,
    COUNT(i.id) AS qtd_itens
FROM pedidos p
LEFT JOIN itens_pedido i ON i.pedido_id = p.id
GROUP BY p.id, p.valor_total
HAVING p.valor_total <> COALESCE(SUM(i.quantidade * i.preco_unitario), 0)
ORDER BY p.id;
