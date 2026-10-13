-- Massa de dados "limpa": nenhum registro aqui é um defeito de propósito.
-- Serve de base realista antes de introduzir os problemas em
-- 03_seed_quebrado.sql, e também de controle: qualquer investigação deve
-- retornar zero resultados rodada só contra este arquivo.

INSERT INTO clientes (nome, email, documento, telefone, data_cadastro, status) VALUES
    ('Ana Carolina Ferreira', 'ana.ferreira@example.com', '11122233344', '11988887777', '2026-01-10 09:15:00', 'ativo'),
    ('Bruno Costa Lima',      'bruno.lima@example.com',   '22233344455', '11977776666', '2026-01-12 14:30:00', 'ativo'),
    ('Carla Mendes Souza',    'carla.souza@example.com',  '33344455566', '21966665555', '2026-01-15 11:00:00', 'ativo'),
    ('Diego Alves Pereira',   'diego.pereira@example.com','44455566677', '21955554444', '2026-01-18 16:45:00', 'ativo'),
    ('Elisa Martins Rocha',   'elisa.rocha@example.com',  '55566677788', '31944443333', '2026-01-20 10:20:00', 'ativo'),
    ('Fábio Nunes Castro',    'fabio.castro@example.com', '66677788899', '31933332222', '2026-01-22 13:10:00', 'inativo'),
    ('Gabriela Dias Ramos',   'gabriela.ramos@example.com','77788899900','41922221111', '2026-01-25 09:50:00', 'ativo'),
    ('Henrique Lopes Teixeira','henrique.teixeira@example.com','88899900011','41911110000','2026-01-28 15:00:00', 'ativo'),
    ('Isabela Rocha Barbosa', 'isabela.barbosa@example.com','99900011122','51900001111', '2026-02-02 12:30:00', 'ativo'),
    ('João Pedro Azevedo',    'joao.azevedo@example.com', '00011122233', '51999990000', '2026-02-05 08:40:00', 'ativo');

INSERT INTO vendedores (nome, email, equipe) VALUES
    ('Mariana Oliveira', 'mariana.oliveira@empresa.com', 'Equipe A'),
    ('Rafael Santos',    'rafael.santos@empresa.com',    'Equipe A'),
    ('Patrícia Gomes',   'patricia.gomes@empresa.com',   'Equipe B'),
    ('Thiago Almeida',   'thiago.almeida@empresa.com',   'Equipe B');

INSERT INTO produtos (nome, preco, categoria) VALUES
    ('Plano Básico Mensal',      49.90,  'Assinatura'),
    ('Plano Profissional Mensal',99.90,  'Assinatura'),
    ('Plano Enterprise Mensal',  249.90, 'Assinatura'),
    ('Pacote de Onboarding',     500.00, 'Serviço'),
    ('Consultoria Avulsa (hora)',150.00, 'Serviço'),
    ('Módulo de Relatórios',     79.90,  'Add-on'),
    ('Módulo de Integrações',    119.90, 'Add-on'),
    ('Suporte Prioritário',      59.90,  'Add-on');

-- Pedidos com fluxo completo e consistente: pendente -> confirmado -> entregue,
-- cada um com pagamento compatível com o status do pedido.

INSERT INTO pedidos (cliente_id, vendedor_id, data_pedido, status, valor_total) VALUES
    (1, 1, '2026-01-11 10:00:00', 'entregue',   149.80),
    (2, 1, '2026-01-13 15:00:00', 'entregue',   99.90),
    (3, 2, '2026-01-16 11:30:00', 'confirmado', 249.90),
    (4, 2, '2026-01-19 17:00:00', 'cancelado',  49.90),
    (5, 3, '2026-01-21 10:45:00', 'entregue',   569.90),
    (7, 3, '2026-01-26 10:10:00', 'pendente',   119.90),
    (8, 4, '2026-01-29 15:30:00', 'confirmado', 79.90),
    (9, 4, '2026-02-03 13:00:00', 'entregue',   209.80),
    (10,1, '2026-02-06 09:20:00', 'pendente',   150.00);

INSERT INTO itens_pedido (pedido_id, produto_id, quantidade, preco_unitario) VALUES
    (1, 1, 1, 49.90),
    (1, 6, 1, 99.90),
    (2, 2, 1, 99.90),
    (3, 3, 1, 249.90),
    (4, 1, 1, 49.90),
    (5, 4, 1, 500.00),
    (5, 5, 1, 69.90),
    (6, 7, 1, 119.90),
    (7, 6, 1, 79.90),
    (8, 3, 1, 209.80),
    (9, 5, 1, 150.00);

-- Pagamentos condizentes com o status de cada pedido.
INSERT INTO pagamentos (pedido_id, valor, data_pagamento, status) VALUES
    (1, 149.80, '2026-01-11 10:05:00', 'aprovado'),
    (2, 99.90,  '2026-01-13 15:10:00', 'aprovado'),
    (3, 249.90, '2026-01-16 11:40:00', 'aprovado'),
    (4, 49.90,  '2026-01-19 17:05:00', 'estornado'),
    (5, 569.90, '2026-01-21 10:50:00', 'aprovado'),
    (7, 79.90,  '2026-01-29 15:35:00', 'aprovado'),
    (8, 209.80, '2026-02-03 13:05:00', 'aprovado');
-- Pedidos 6 (pendente) e 9 (pendente) ainda não têm pagamento registrado —
-- comportamento esperado para pedidos que ainda não foram confirmados.
