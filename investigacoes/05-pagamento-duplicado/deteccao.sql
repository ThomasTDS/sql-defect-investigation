-- Detecção: pagamentos aprovados registrados em duplicidade.
--
-- Um pagamento é suspeito de ser duplicado quando, no mesmo pedido, vem
-- logo depois de outro pagamento aprovado (LAG, na ordem do tempo) com:
--   - o mesmo valor;
--   - no máximo 10 minutos de diferença;
--   - e a soma dos pagamentos aprovados do pedido passa do valor_total.
--
-- A última condição separa duplicidade de pagamento dividido legítimo
-- (ex.: duas partes iguais em dois cartões, que somam o total certo).
--
-- Cada linha é um pagamento duplicado, junto com o pagamento original.
-- Resultado esperado: zero linhas.

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
