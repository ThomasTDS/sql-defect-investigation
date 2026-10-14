-- Regra: num pedido que tem pagamento aprovado, a soma dos pagamentos
-- aprovados é igual ao valor_total do pedido.
--
-- Soma, e não cada pagamento, porque um pedido pode ser pago em mais de
-- uma parte (dois cartões, por exemplo). Pagamentos pendentes ou
-- estornados não entram: só o que foi efetivamente recebido.
--
-- Cada linha é um pedido que quebra a regra. Esperado: zero linhas.

SELECT
    p.id AS pedido_id,
    p.valor_total,
    SUM(pg.valor) AS soma_pagamentos_aprovados
FROM pedidos p
JOIN pagamentos pg ON pg.pedido_id = p.id AND pg.status = 'aprovado'
GROUP BY p.id, p.valor_total
HAVING SUM(pg.valor) <> p.valor_total
ORDER BY p.id;
