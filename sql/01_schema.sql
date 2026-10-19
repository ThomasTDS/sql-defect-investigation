-- Schema de um CRM/ERP de vendas genérico: clientes, vendedores, catálogo,
-- pedidos e pagamentos. Modelo propositalmente simples, mas realista o
-- bastante pra sustentar os tipos de defeito investigados neste projeto
-- (duplicidade, FK órfã, status inconsistente, data inválida, pagamento em
-- duplicidade, valores de mentira em campos obrigatórios).

CREATE TABLE clientes (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(150) NOT NULL,
    email VARCHAR(150) NOT NULL,
    documento VARCHAR(20) NOT NULL,
    telefone VARCHAR(20),
    data_cadastro TIMESTAMP NOT NULL DEFAULT now(),
    status VARCHAR(20) NOT NULL DEFAULT 'ativo'
);
-- email e documento são só NOT NULL, sem nenhuma validação de conteúdo: é o
-- que permite os valores de mentira da investigação 06.
-- Sem UNIQUE em email/documento de propósito: é exatamente a ausência dessa
-- constraint que permite o defeito de clientes duplicados investigado aqui.

CREATE TABLE vendedores (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(150) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE,
    equipe VARCHAR(50)
);

CREATE TABLE produtos (
    id SERIAL PRIMARY KEY,
    nome VARCHAR(150) NOT NULL,
    preco NUMERIC(10, 2) NOT NULL CHECK (preco >= 0),
    categoria VARCHAR(50)
);

CREATE TABLE pedidos (
    id SERIAL PRIMARY KEY,
    cliente_id INTEGER NOT NULL REFERENCES clientes (id),
    vendedor_id INTEGER REFERENCES vendedores (id),
    data_pedido TIMESTAMP NOT NULL DEFAULT now(),
    status VARCHAR(20) NOT NULL DEFAULT 'pendente',
    valor_total NUMERIC(10, 2) NOT NULL DEFAULT 0
);
-- status esperado: pendente | confirmado | entregue | cancelado

CREATE TABLE itens_pedido (
    id SERIAL PRIMARY KEY,
    pedido_id INTEGER NOT NULL REFERENCES pedidos (id),
    produto_id INTEGER NOT NULL REFERENCES produtos (id),
    quantidade INTEGER NOT NULL CHECK (quantidade > 0),
    preco_unitario NUMERIC(10, 2) NOT NULL
);

CREATE TABLE pagamentos (
    id SERIAL PRIMARY KEY,
    pedido_id INTEGER NOT NULL REFERENCES pedidos (id),
    valor NUMERIC(10, 2) NOT NULL,
    data_pagamento TIMESTAMP,
    status VARCHAR(20) NOT NULL DEFAULT 'pendente'
);
-- status esperado: pendente | aprovado | estornado
