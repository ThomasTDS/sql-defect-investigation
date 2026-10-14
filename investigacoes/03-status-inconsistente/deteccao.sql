-- Detecção: pedidos cujo status é incompatível com a situação do pagamento.
--
-- A situação do pagamento é consolidada por pedido (um pedido pode ter
-- mais de um registro de pagamento): basta um "aprovado" para o pedido
-- contar como pago; senão, vale "pendente", depois "estornado", e por fim
-- "sem pagamento".
--
-- Combinações válidas:
--   pendente            -> sem pagamento | pendente
--   confirmado/entregue -> aprovado
--   cancelado           -> sem pagamento | estornado
--
-- Qualquer outra combinação é um defeito, inclusive um status fora da
-- lista (ex.: "Entregue" com maiúscula), que não casa com nenhuma regra.
--
-- Resultado esperado: zero linhas.

WITH situacao AS (
    SELECT
        p.id AS pedido_id,
        p.status AS status_pedido,
        CASE
            WHEN bool_or(pg.status = 'aprovado') THEN 'aprovado'
            WHEN bool_or(pg.status = 'pendente') THEN 'pendente'
            WHEN bool_or(pg.status = 'estornado') THEN 'estornado'
            ELSE 'sem pagamento'
        END AS situacao_pagamento
    FROM pedidos p
    LEFT JOIN pagamentos pg ON pg.pedido_id = p.id
    GROUP BY p.id, p.status
)
SELECT pedido_id, status_pedido, situacao_pagamento
FROM situacao
WHERE NOT (
       (status_pedido = 'pendente' AND situacao_pagamento IN ('sem pagamento', 'pendente'))
    OR (status_pedido IN ('confirmado', 'entregue') AND situacao_pagamento = 'aprovado')
    OR (status_pedido = 'cancelado' AND situacao_pagamento IN ('sem pagamento', 'estornado'))
)
ORDER BY pedido_id;
