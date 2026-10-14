-- Introduz, de propósito, os 5 tipos de defeito investigados neste projeto.
-- Cada bloco está comentado com o cenário real que ele simula. Execute
-- depois de 01_schema.sql + 02_seed_valido.sql.

-- =====================================================================
-- DEFEITO 1: Cliente duplicado
-- Cenário real: formulário de cadastro foi enviado duas vezes (duplo
-- clique, timeout de rede e o usuário tentou de novo, etc.) e não existe
-- constraint única em email/documento pra impedir o segundo registro.
-- =====================================================================
INSERT INTO clientes (nome, email, documento, telefone, data_cadastro, status) VALUES
    ('Ana C. Ferreira', 'ana.ferreira@example.com', '11122233344', '11988887777', '2026-01-10 09:17:32', 'ativo');
-- Mesmo e-mail e documento do cliente id=1, cadastrado 2 minutos depois,
-- com o nome digitado de forma levemente diferente.

-- =====================================================================
-- DEFEITO 2: Foreign key órfã
-- Cenário real: um cliente foi removido diretamente no banco (acesso de
-- suporte/operação, fora da aplicação), sem que os pedidos vinculados a
-- ele fossem tratados. A constraint existe no schema hoje, mas não foi
-- validada retroativamente contra esse dado histórico — padrão comum em
-- bancos que já têm alguns anos de operação.
-- =====================================================================
INSERT INTO clientes (nome, email, documento, telefone, data_cadastro, status)
VALUES ('Cliente Removido Depois', 'removido@example.com', '12312312312', '11900000000', '2025-11-01 10:00:00', 'ativo');

INSERT INTO pedidos (cliente_id, vendedor_id, data_pedido, status, valor_total)
VALUES (currval('clientes_id_seq'), 1, '2025-12-01 10:00:00', 'confirmado', 99.90);

ALTER TABLE pedidos DROP CONSTRAINT pedidos_cliente_id_fkey;
DELETE FROM clientes WHERE id = currval('clientes_id_seq');
ALTER TABLE pedidos
    ADD CONSTRAINT pedidos_cliente_id_fkey
    FOREIGN KEY (cliente_id) REFERENCES clientes (id) NOT VALID;

-- =====================================================================
-- DEFEITO 3: Status inconsistente
-- Cenário real: webhook do gateway de pagamento marcou o pedido como
-- "entregue" (processo automático de fulfillment), mas o pagamento nunca
-- foi de fato aprovado — o registro de pagamento ficou "pendente" (ou,
-- no segundo caso, o pedido foi cancelado depois que o pagamento já
-- tinha sido aprovado, e o cancelamento não reverteu o pagamento).
-- =====================================================================
INSERT INTO pedidos (cliente_id, vendedor_id, data_pedido, status, valor_total)
VALUES (6, 3, '2026-01-24 09:00:00', 'entregue', 59.90);
INSERT INTO itens_pedido (pedido_id, produto_id, quantidade, preco_unitario)
VALUES (currval('pedidos_id_seq'), 8, 1, 59.90);
INSERT INTO pagamentos (pedido_id, valor, data_pagamento, status)
VALUES (currval('pedidos_id_seq'), 59.90, NULL, 'pendente');
-- Pedido "entregue" com pagamento ainda "pendente" (sem data_pagamento).

INSERT INTO pedidos (cliente_id, vendedor_id, data_pedido, status, valor_total)
VALUES (3, 2, '2026-02-01 14:00:00', 'cancelado', 79.90);
INSERT INTO itens_pedido (pedido_id, produto_id, quantidade, preco_unitario)
VALUES (currval('pedidos_id_seq'), 6, 1, 79.90);
INSERT INTO pagamentos (pedido_id, valor, data_pagamento, status)
VALUES (currval('pedidos_id_seq'), 79.90, '2026-02-01 14:05:00', 'aprovado');
-- Pedido "cancelado" com pagamento "aprovado" — o cancelamento não estornou o pagamento.

-- =====================================================================
-- DEFEITO 4: Data inválida
-- Cenário real: na conciliação manual com o gateway, um operador lançou
-- o pagamento à mão e digitou a data errada (copiou o horário do pedido
-- e errou o dia), resultando num pagamento "datado" antes do próprio
-- pedido existir. Nada no banco valida a data informada.
-- =====================================================================
INSERT INTO pedidos (cliente_id, vendedor_id, data_pedido, status, valor_total)
VALUES (8, 4, '2026-02-10 10:00:00', 'confirmado', 150.00);
INSERT INTO itens_pedido (pedido_id, produto_id, quantidade, preco_unitario)
VALUES (currval('pedidos_id_seq'), 5, 1, 150.00);
INSERT INTO pagamentos (pedido_id, valor, data_pagamento, status)
VALUES (currval('pedidos_id_seq'), 150.00, '2026-02-08 10:00:00', 'aprovado');
-- data_pagamento (08/02) é anterior a data_pedido (10/02).

-- =====================================================================
-- DEFEITO 5: Pagamento em duplicidade
-- Cenário real: o gateway confirmou o pagamento do pedido 2 por webhook,
-- mas a aplicação demorou a responder; o gateway entendeu como falha e
-- reenviou a mesma confirmação 4 segundos depois. Sem chave de
-- idempotência (id da transação no gateway), a aplicação registrou as
-- duas. O cliente foi cobrado uma vez só: a duplicidade existe apenas
-- no banco.
-- =====================================================================
INSERT INTO pagamentos (pedido_id, valor, data_pagamento, status)
VALUES (2, 99.90, '2026-01-13 15:10:04', 'aprovado');
-- Mesmo pedido, mesmo valor e 4 segundos depois do pagamento original
-- (id 2, 15:10:00).
