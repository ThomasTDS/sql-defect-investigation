# Investigação 03 — Status inconsistente

| | |
|---|---|
| **Defeito** | Pedidos com status incompatível com a situação do pagamento |
| **Registros afetados** | 3 pedidos: `12` (cancelado com pagamento aprovado), `11` (entregue com pagamento pendente) e `10` (confirmado sem pagamento) |
| **Causa raiz** | O status do pedido e o do pagamento são atualizados de forma independente, e o banco não impõe nenhuma regra sobre eles, nem sobre os valores aceitos nem sobre as combinações válidas |
| **Severidade** | Alta: há uma cliente cobrada por um pedido cancelado e um pedido entregue sem pagamento confirmado |
| **Status** | Diagnóstico concluído, com correção proposta e **não executada** |

Arquivos desta investigação:

- [`exploracao.sql`](exploracao.sql): as queries na ordem em que foram usadas, numeradas conforme os passos abaixo.
- [`deteccao.sql`](deteccao.sql): a query final de detecção, baseada na matriz de combinações válidas. É a mesma query que a CI executa.

---

## 1. Sintoma relatado

> Chamado de suporte: a cliente **Carla Mendes Souza** informou que cancelou um pedido no dia 01/02, mas o valor de **R$ 79,90** continua cobrado no cartão e o estorno não apareceu.

## 2. Hipóteses iniciais

| # | Hipótese | Como confirmar ou descartar |
|---|---|---|
| H1 | O estorno foi feito, mas ainda não apareceu na fatura (prazo do cartão) | Verificar se existe registro de pagamento `estornado` para o pedido |
| H2 | O cancelamento do pedido não disparou o estorno do pagamento | Pedido `cancelado` com pagamento ainda `aprovado` |
| H3 | O caso não é isolado: o status do pedido e o do pagamento estão dessincronizados em outros pedidos também | Cruzar o status de todos os pedidos com a situação dos pagamentos |

## 3. Investigação

### Passo 1: o caso relatado

Pedidos e pagamentos da cliente (`cliente_id = 3`):

```sql
SELECT p.id AS pedido_id, p.data_pedido, p.status AS status_pedido, p.valor_total,
       pg.id AS pagamento_id, pg.status AS status_pagamento, pg.valor AS valor_pago, pg.data_pagamento
FROM pedidos p
LEFT JOIN pagamentos pg ON pg.pedido_id = p.id
WHERE p.cliente_id = 3;
```

| pedido_id | data_pedido | status_pedido | valor_total | pagamento_id | status_pagamento | valor_pago | data_pagamento |
|---|---|---|---|---|---|---|---|
| 3 | 2026-01-16 11:30:00 | confirmado | 249.90 | 3 | aprovado | 249.90 | 2026-01-16 11:40:00 |
| 12 | 2026-02-01 14:00:00 | **cancelado** | 79.90 | 9 | **aprovado** | 79.90 | 2026-02-01 14:05:00 |

**Achado:** **H1 descartada e H2 confirmada.** O pedido `12` está `cancelado`, mas o único pagamento dele continua `aprovado`. Não existe nenhum registro de estorno, então não é questão de prazo do cartão: o estorno **nunca foi feito**. O pagamento foi aprovado 5 minutos depois do pedido, ou seja, o cancelamento veio depois do pagamento e não o reverteu.

### Passo 2: a matriz de status

Para testar H3, primeiro é preciso definir o que é "consistente". Pelo fluxo normal de pedidos (o mesmo usado na massa de dados de controle), as combinações válidas são:

| Status do pedido | Situação de pagamento aceita |
|---|---|
| `pendente` | sem pagamento, ou pagamento `pendente` |
| `confirmado` / `entregue` | pagamento `aprovado` |
| `cancelado` | sem pagamento, ou pagamento `estornado` |

Um pedido pode ter mais de um registro de pagamento, então a situação é consolidada por pedido: basta um `aprovado` para o pedido contar como pago; senão, vale `pendente`, depois `estornado` e, por fim, "sem pagamento".

Com isso, a matriz conta quantos pedidos existem em **cada combinação** que aparece no banco:

```sql
WITH situacao AS (
    SELECT p.id AS pedido_id, p.status AS status_pedido,
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
SELECT status_pedido, situacao_pagamento, COUNT(*) AS qtd_pedidos,
       string_agg(pedido_id::text, ', ' ORDER BY pedido_id) AS pedidos
FROM situacao
GROUP BY status_pedido, situacao_pagamento;
```

| status_pedido | situacao_pagamento | qtd_pedidos | pedidos | válida? |
|---|---|---|---|---|
| cancelado | **aprovado** | 1 | 12 | ❌ |
| cancelado | estornado | 1 | 4 | ✅ |
| confirmado | aprovado | 3 | 3, 7, 13 | ✅ |
| confirmado | **sem pagamento** | 1 | 10 | ❌ |
| entregue | aprovado | 4 | 1, 2, 5, 8 | ✅ |
| entregue | **pendente** | 1 | 11 | ❌ |
| pendente | sem pagamento | 2 | 6, 9 | ✅ |

**Achado:** **H3 confirmada.** Além do caso da Carla, há **mais duas combinações inválidas**. A matriz é mais útil que uma lista de regras soltas porque mostra o banco inteiro de uma vez, inclusive combinações que ninguém pensou em procurar.

O `LEFT JOIN` aqui é essencial: com `JOIN` comum, os pedidos sem nenhum pagamento (6, 9 e 10) sumiriam da matriz, e justamente o pedido 10 é um dos defeitos.

### Passo 3: lista dos pedidos inconsistentes

A mesma lógica, filtrando só o que não se encaixa em nenhuma combinação válida. A query completa está em [`deteccao.sql`](deteccao.sql).

| pedido_id | status_pedido | situacao_pagamento |
|---|---|---|
| 10 | confirmado | sem pagamento |
| 11 | entregue | pendente |
| 12 | cancelado | aprovado |

Um efeito colateral útil: como o filtro é "não se encaixa em nenhuma regra", um status fora da lista (por exemplo, `'Entregue'` com maiúscula, ou um erro de digitação) também apareceria aqui.

### Passo 4: detalhe de cada caso

```sql
SELECT p.id AS pedido_id, p.cliente_id, c.nome AS cliente, p.data_pedido,
       p.status AS status_pedido, p.valor_total,
       pg.status AS status_pagamento, pg.valor AS valor_pago, pg.data_pagamento
FROM pedidos p
LEFT JOIN clientes c ON c.id = p.cliente_id
LEFT JOIN pagamentos pg ON pg.pedido_id = p.id
WHERE p.id IN (10, 11, 12);
```

| pedido_id | cliente_id | cliente | data_pedido | status_pedido | valor_total | status_pagamento | valor_pago | data_pagamento |
|---|---|---|---|---|---|---|---|---|
| 10 | 12 | *(null)* | 2025-12-01 10:00:00 | confirmado | 99.90 | *(null)* | *(null)* | *(null)* |
| 11 | 6 | Fábio Nunes Castro | 2026-01-24 09:00:00 | entregue | 59.90 | pendente | 59.90 | *(null)* |
| 12 | 3 | Carla Mendes Souza | 2026-02-01 14:00:00 | cancelado | 79.90 | aprovado | 79.90 | 2026-02-01 14:05:00 |

Cada caso tem uma leitura diferente:

- **Pedido 12 (cancelado + aprovado):** o caso do chamado. O cancelamento não disparou o estorno. **Cliente cobrada indevidamente.**
- **Pedido 11 (entregue + pendente):** o pedido avançou até `entregue`, mas o pagamento nunca foi aprovado (`data_pagamento` vazia). O processo de entrega (fulfillment) não conferiu o pagamento antes de liberar. **Mercadoria entregue sem recebimento confirmado.**
- **Pedido 10 (confirmado sem pagamento):** é o **mesmo pedido órfão da [investigação 02](../02-fk-orfa/README.md)**, que aponta para o cliente removido. Lá ele apareceu como "achado secundário" (sem itens e sem pagamento); aqui, ele cai na regra de status. Um mesmo registro pode ter mais de um defeito, e as duas investigações se confirmam. A correção dele depende da decisão do negócio na investigação 02.

### Passo 5: causa raiz — o que o banco garante sobre status?

Constraints `CHECK` nas tabelas `pedidos` e `pagamentos`:

```sql
SELECT conrelid::regclass AS tabela, conname, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE contype = 'c'
  AND conrelid IN ('pedidos'::regclass, 'pagamentos'::regclass);
```

**Resultado: 0 linhas.** Não existe nenhuma regra no banco sobre status. Os valores aceitos (`pendente`, `confirmado`...) existem só como comentário no DDL, e qualquer texto é aceito.

Colunas das duas tabelas:

| tabela | colunas |
|---|---|
| pedidos | id, cliente_id, vendedor_id, data_pedido, status, valor_total |
| pagamentos | id, pedido_id, valor, data_pagamento, status |

**Achado:** também não há nenhuma coluna de "atualizado em", nem uma tabela de histórico de status. O banco guarda só o status **atual**, não **quando** nem **por quem** ele mudou. Por isso, no pedido 12, dá para saber que o pagamento foi aprovado às 14:05, mas não quando o pedido foi cancelado.

## 4. Causa raiz

1. **Aplicação (causa raiz):** o status do pedido e o do pagamento são atualizados por processos independentes, sem amarração entre eles. O cancelamento muda o pedido e não aciona o estorno (pedido 12). A entrega muda o pedido e não confere o pagamento (pedido 11).
2. **Banco (por que passou):** não há `CHECK` nem nos valores de status nem em regras mínimas (por exemplo, "pagamento aprovado precisa ter data"). Uma regra que envolve duas tabelas (pedido × pagamento) não pode ser uma `CHECK` simples, então precisa ser garantida pela aplicação e monitorada.
3. **Rastreabilidade:** sem histórico de status, não dá para reconstruir a sequência de eventos de cada pedido. Para confirmar qual processo fez cada mudança, é preciso ir aos logs da aplicação.

## 5. Impacto

| Pedido | Impacto | Valor |
|---|---|---|
| 12 | Cliente cobrada por pedido cancelado. Gera obrigação de estorno, risco de reclamação formal e de chargeback | R$ 79,90 |
| 11 | Mercadoria entregue sem pagamento confirmado: possível perda de receita | R$ 59,90 |
| 10 | Pedido "confirmado" sem pagamento e sem cliente (ver investigação 02) | R$ 99,90 |

## 6. Correção proposta

> **Não executada.** As `CHECK` constraints da seção 6.2 foram testadas numa cópia descartável do banco. Elas são aceitas pelos dados atuais, bloqueiam um status inválido (`'Entregue'`) e bloqueiam marcar o pagamento do pedido 11 como `aprovado` sem data. Também foi testado que, depois do estorno do pedido 12, a detecção passa a listar apenas os pedidos 10 e 11.

### 6.1 Tratar os pedidos afetados

Nenhum destes casos se resolve **só mudando o status no banco**. O status precisa refletir o que aconteceu de fato no gateway de pagamento.

| Pedido | Ação |
|---|---|
| 12 | Executar o estorno **no gateway**. Só depois de confirmado, registrar no banco: `UPDATE pagamentos SET status = 'estornado' WHERE id = 9;` e avisar a cliente |
| 11 | Consultar o gateway. Se o pagamento foi aprovado, registrar com a data real; se não, acionar a cobrança. Não marcar como `aprovado` sem confirmação |
| 10 | Seguir a decisão da [investigação 02](../02-fk-orfa/README.md#6-correção-proposta) |

### 6.2 Prevenção no banco

```sql
ALTER TABLE pedidos ADD CONSTRAINT pedidos_status_valido
    CHECK (status IN ('pendente', 'confirmado', 'entregue', 'cancelado'));

ALTER TABLE pagamentos ADD CONSTRAINT pagamentos_status_valido
    CHECK (status IN ('pendente', 'aprovado', 'estornado'));

ALTER TABLE pagamentos ADD CONSTRAINT pagamentos_aprovado_tem_data
    CHECK (status <> 'aprovado' OR data_pagamento IS NOT NULL);
```

- As duas primeiras transformam a lista de status, que hoje é só um comentário, em regra.
- A terceira impede um pagamento `aprovado` sem data. Ela evita, por exemplo, que alguém "resolva" o pedido 11 trocando só o status.
- A regra entre tabelas (status do pedido × pagamento) **não** cabe numa `CHECK`. Ela fica com a aplicação (6.3) e com o monitoramento.

### 6.3 Prevenção na aplicação

- **Máquina de estados:** centralizar as transições de status do pedido num único ponto, que valida o pagamento antes de cada transição. Cancelar precisa disparar o estorno; entregar só é permitido com pagamento aprovado. Pedido e pagamento devem ser atualizados **na mesma transação**.
- **Histórico de status:** registrar cada mudança (status anterior, novo status, data, origem) numa tabela de histórico. Nesta investigação, foi a informação que faltou para reconstruir a sequência de eventos.
- **Monitoramento:** rodar o [`deteccao.sql`](deteccao.sql) diariamente. Pedido cancelado com pagamento aprovado deveria gerar alerta para o financeiro antes de virar chamado do cliente.

## 7. Como reproduzir

Com o banco no ar (`docker compose up`, ver o [README principal](../../README.md)):

```bash
docker compose exec -T postgres psql -U postgres -d defect_investigation < investigacoes/03-status-inconsistente/exploracao.sql
```
