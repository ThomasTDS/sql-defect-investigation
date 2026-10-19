-- Detecção: pedidos com data gravada em UTC numa coluna que, no resto do
-- sistema, guarda horário de Brasília (UTC-3).
--
-- O sinal vem do pagamento, que o gateway grava em hora local. No padrão
-- normal, ele é aprovado de 0 a 30 minutos DEPOIS do pedido. Num pedido
-- gravado em UTC, o pagamento parece ter sido feito cerca de 3 horas
-- ANTES. A query desconta as 3 horas do fuso da data do pedido e procura
-- os pagamentos que, com esse desconto, voltam ao padrão normal.
--
-- O Brasil não tem horário de verão desde 2019, então a diferença entre
-- UTC e Brasília é sempre de 3 horas no período dos dados.
--
-- Cada linha é um pedido com fuso suspeito. Resultado esperado: zero
-- linhas.

SELECT
    p.id AS pedido_id,
    p.data_pedido AS data_pedido_gravada,
    pg.data_pagamento,
    pg.data_pagamento - p.data_pedido AS diferenca_gravada,
    p.data_pedido - interval '3 hours' AS data_pedido_em_brasilia,
    pg.data_pagamento - (p.data_pedido - interval '3 hours') AS diferenca_corrigida
FROM pedidos p
JOIN pagamentos pg ON pg.pedido_id = p.id AND pg.status = 'aprovado'
WHERE pg.data_pagamento < p.data_pedido
  AND pg.data_pagamento - (p.data_pedido - interval '3 hours')
      BETWEEN interval '0 minutes' AND interval '30 minutes'
ORDER BY p.id;
