-- Detecção: datas implausíveis, ou seja, datas que contradizem a ordem
-- natural dos eventos ou que ainda não aconteceram.
--
-- Ordem natural: cliente se cadastra -> faz o pedido -> paga.
-- Cada linha é um registro com data impossível, com o motivo.
--
-- Resultado esperado: zero linhas. Qualquer linha é um defeito.

SELECT 'pagamentos' AS tabela, pg.id AS registro_id,
       'pagamento anterior ao pedido' AS motivo,
       pg.data_pagamento AS data_registro, p.data_pedido AS data_referencia
FROM pagamentos pg
JOIN pedidos p ON p.id = pg.pedido_id
WHERE pg.data_pagamento < p.data_pedido

UNION ALL

SELECT 'pedidos', p.id,
       'pedido anterior ao cadastro do cliente',
       p.data_pedido, c.data_cadastro
FROM pedidos p
JOIN clientes c ON c.id = p.cliente_id
WHERE p.data_pedido < c.data_cadastro

UNION ALL

SELECT 'clientes', id, 'data no futuro', data_cadastro, now()::timestamp
FROM clientes
WHERE data_cadastro > now()

UNION ALL

SELECT 'pedidos', id, 'data no futuro', data_pedido, now()::timestamp
FROM pedidos
WHERE data_pedido > now()

UNION ALL

SELECT 'pagamentos', id, 'data no futuro', data_pagamento, now()::timestamp
FROM pagamentos
WHERE data_pagamento > now()

ORDER BY tabela, registro_id;
