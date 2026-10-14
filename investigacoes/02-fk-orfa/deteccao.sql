-- Detecção: registros órfãos, ou seja, linhas cuja chave estrangeira
-- aponta para um registro que não existe.
--
-- Cobre todas as foreign keys do schema, não só pedidos -> clientes:
-- uma FK pode ter sido desabilitada ou recriada sem validação em qualquer
-- tabela. Cada linha é um registro órfão.
--
-- Resultado esperado: zero linhas. Qualquer linha é um defeito.

SELECT 'pedidos' AS tabela, p.id AS registro_id, 'cliente_id' AS coluna, p.cliente_id AS aponta_para
FROM pedidos p
LEFT JOIN clientes c ON c.id = p.cliente_id
WHERE c.id IS NULL

UNION ALL

-- vendedor_id aceita NULL (pedido sem vendedor); só é órfão se tiver valor.
SELECT 'pedidos', p.id, 'vendedor_id', p.vendedor_id
FROM pedidos p
LEFT JOIN vendedores v ON v.id = p.vendedor_id
WHERE p.vendedor_id IS NOT NULL AND v.id IS NULL

UNION ALL

SELECT 'itens_pedido', i.id, 'pedido_id', i.pedido_id
FROM itens_pedido i
LEFT JOIN pedidos p ON p.id = i.pedido_id
WHERE p.id IS NULL

UNION ALL

SELECT 'itens_pedido', i.id, 'produto_id', i.produto_id
FROM itens_pedido i
LEFT JOIN produtos pr ON pr.id = i.produto_id
WHERE pr.id IS NULL

UNION ALL

SELECT 'pagamentos', pg.id, 'pedido_id', pg.pedido_id
FROM pagamentos pg
LEFT JOIN pedidos p ON p.id = pg.pedido_id
WHERE p.id IS NULL

ORDER BY tabela, registro_id;
