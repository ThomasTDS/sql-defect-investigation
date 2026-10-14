# Investigação 05 — Pagamento em duplicidade

| | |
|---|---|
| **Defeito** | A mesma confirmação de pagamento foi registrada duas vezes |
| **Registros afetados** | 1 pagamento duplicado: `11`, cópia do pagamento `2` (pedido `2`, R$ 99,90) |
| **Causa raiz** | O gateway reenviou a confirmação (webhook) e a aplicação gravou de novo, porque a tabela `pagamentos` não guarda nenhum identificador da transação que permita reconhecer um reenvio |
| **Severidade** | Alta: a receita registrada fica maior que a real, e um estorno do "excedente" devolveria ao cliente um dinheiro que ele pagou de fato |
| **Status** | Diagnóstico concluído, com correção proposta e **não executada** |

Arquivos desta investigação:

- [`exploracao.sql`](exploracao.sql): as queries na ordem em que foram usadas, numeradas conforme os passos abaixo.
- [`deteccao.sql`](deteccao.sql): a query final de detecção, que usa funções de janela (`LAG`) para comparar cada pagamento com o anterior do mesmo pedido. É a mesma query que a CI executa.

---

## 1. Sintoma relatado

> Chamado do financeiro: na conciliação de janeiro, o sistema registra **R$ 199,80** recebidos no pedido 2, mas o extrato do gateway mostra **uma única transação de R$ 99,90**.

O sistema diz que recebeu o dobro do que o gateway diz ter cobrado. Ou o cliente pagou duas vezes, e o gateway está errado, ou o nosso banco registrou a mesma coisa duas vezes.

## 2. Hipóteses iniciais

| # | Hipótese | Como confirmar ou descartar |
|---|---|---|
| H1 | O cliente fez dois pagamentos de verdade (duas cobranças) | O gateway teria duas transações, e o extrato mostra uma |
| H2 | O mesmo pagamento foi registrado duas vezes no banco | Dois registros idênticos (pedido, valor) com intervalo curto |
| H3 | Se H2: foi o reenvio automático da confirmação pelo gateway (webhook) | Intervalo de poucos segundos, compatível com as tentativas automáticas do gateway |
| H4 | O caso não é isolado | Procurar pedidos com pagamentos aprovados acima do valor total |

O próprio sintoma já pesa contra H1: o extrato do gateway, que é a fonte da cobrança real, mostra uma única transação.

## 3. Investigação

### Passo 1: o caso relatado

```sql
SELECT p.id AS pedido_id, p.status AS status_pedido, p.valor_total,
       pg.id AS pagamento_id, pg.valor, pg.status AS status_pagamento, pg.data_pagamento
FROM pedidos p
JOIN pagamentos pg ON pg.pedido_id = p.id
WHERE p.id = 2
ORDER BY pg.data_pagamento, pg.id;
```

| pedido_id | status_pedido | valor_total | pagamento_id | valor | status_pagamento | data_pagamento |
|---|---|---|---|---|---|---|
| 2 | entregue | 99.90 | 2 | 99.90 | aprovado | 2026-01-13 15:10:00 |
| 2 | entregue | 99.90 | **11** | **99.90** | **aprovado** | **2026-01-13 15:10:04** |

**Achado:** **H2 confirmada.** São dois pagamentos aprovados para um pedido de R$ 99,90, com o mesmo valor e **4 segundos** de diferença.

O intervalo separa as hipóteses:

- **H1 descartada:** além de o gateway mostrar uma única transação, nenhum cliente consegue concluir duas compras com cartão em 4 segundos.
- **Compatível com H3:** gateways de pagamento reenviam a confirmação automaticamente quando a aplicação não responde a tempo, normalmente em segundos. A confirmação final dessa hipótese está no painel do gateway, que registra cada tentativa de entrega do webhook. Pelo banco, o padrão bate.

Note que esse defeito **não aparece** nas investigações anteriores: o pedido está `entregue` e tem pagamento `aprovado`, uma combinação válida na [matriz de status](../03-status-inconsistente/README.md), e as datas estão em ordem. Só olhando valores e quantidades ele aparece.

### Passo 2: é isolado?

Pedidos em que a soma dos pagamentos aprovados passa do valor total:

```sql
SELECT p.id AS pedido_id, p.valor_total,
       COUNT(pg.id) AS qtd_pagamentos_aprovados,
       SUM(pg.valor) AS soma_aprovados,
       SUM(pg.valor) - p.valor_total AS excedente
FROM pedidos p
JOIN pagamentos pg ON pg.pedido_id = p.id AND pg.status = 'aprovado'
GROUP BY p.id, p.valor_total
HAVING SUM(pg.valor) > p.valor_total;
```

| pedido_id | valor_total | qtd_pagamentos_aprovados | soma_aprovados | excedente |
|---|---|---|---|---|
| 2 | 99.90 | 2 | 199.80 | 99.90 |

**Achado:** **H4 descartada.** É o único pedido pago a mais. É também o pedido que a regra de [`validacoes/pagamento-igual-total-pedido.sql`](../../validacoes/pagamento-igual-total-pedido.sql) aponta: ela confere a mesma coisa por outro caminho, e os dois se confirmam.

### Passo 3: a assinatura da duplicidade

"Pago a mais" não basta para dizer que é duplicidade. O excedente poderia ser um pagamento legítimo com valor errado, por exemplo. A assinatura de uma duplicidade é **um pagamento igual ao anterior, logo em seguida**. Para comparar cada pagamento com o anterior **do mesmo pedido**, a função de janela `LAG` resolve sem precisar de um `JOIN` da tabela com ela mesma:

```sql
SELECT pg.pedido_id, pg.id AS pagamento_id, pg.valor, pg.data_pagamento,
       LAG(pg.id) OVER janela AS pagamento_anterior,
       LAG(pg.valor) OVER janela AS valor_anterior,
       pg.data_pagamento - LAG(pg.data_pagamento) OVER janela AS intervalo
FROM pagamentos pg
WHERE pg.status = 'aprovado'
  AND pg.pedido_id IN (SELECT pedido_id FROM pagamentos WHERE status = 'aprovado'
                       GROUP BY pedido_id HAVING COUNT(*) > 1)
WINDOW janela AS (PARTITION BY pg.pedido_id ORDER BY pg.data_pagamento, pg.id);
```

| pedido_id | pagamento_id | valor | data_pagamento | pagamento_anterior | valor_anterior | intervalo |
|---|---|---|---|---|---|---|
| 2 | 2 | 99.90 | 2026-01-13 15:10:00 | *(null)* | *(null)* | *(null)* |
| 2 | 11 | 99.90 | 2026-01-13 15:10:04 | 2 | 99.90 | 00:00:04 |

- `PARTITION BY pg.pedido_id`: cada pedido é comparado só com ele mesmo.
- `ORDER BY pg.data_pagamento, pg.id`: "anterior" significa anterior no tempo (o `id` desempata horários iguais).
- O primeiro pagamento de cada pedido tem `LAG` nulo, porque não há nenhum antes dele.

**Achado:** o pagamento `11` tem o mesmo valor do pagamento anterior (`2`) e veio 4 segundos depois. É a assinatura de duplicidade.

### Passo 4: a detecção final

A query de [`deteccao.sql`](deteccao.sql) junta as três condições. Um pagamento é marcado como duplicado quando, em relação ao pagamento aprovado anterior do mesmo pedido:

1. tem **o mesmo valor**;
2. veio em **até 10 minutos**;
3. e a **soma dos aprovados passa do total** do pedido.

| pedido_id | pagamento_original | pagamento_duplicado | valor | data_original | data_duplicado | intervalo | valor_total | soma_aprovados |
|---|---|---|---|---|---|---|---|---|
| 2 | 2 | 11 | 99.90 | 2026-01-13 15:10:00 | 2026-01-13 15:10:04 | 00:00:04 | 99.90 | 199.80 |

A terceira condição existe para não confundir duplicidade com **pagamento dividido legítimo**. Um pedido de R$ 100,00 pago em duas partes de R$ 50,00, em dois cartões, tem dois pagamentos iguais com segundos de diferença, mas a soma é exatamente o total. Isso foi testado numa cópia descartável do banco: **sem** a terceira condição, a detecção marca o pagamento dividido como duplicado; **com** ela, não marca.

### Passo 5: causa raiz — o que impediria o registro duplicado?

Colunas e índices da tabela `pagamentos`:

| column_name | data_type |
|---|---|
| id | integer |
| pedido_id | integer |
| valor | numeric |
| data_pagamento | timestamp without time zone |
| status | character varying |

| indexname | indexdef |
|---|---|
| pagamentos_pkey | CREATE UNIQUE INDEX pagamentos_pkey ON public.pagamentos USING btree (id) |

**Achado:** a tabela **não guarda nenhum identificador da transação no gateway**. A única chave única é o `id`, gerado pelo próprio banco a cada `INSERT`. Quando o mesmo webhook chega duas vezes, a aplicação não tem como saber que já registrou aquela transação, e cada chegada vira um pagamento novo.

## 4. Causa raiz

1. **Integração (gatilho):** a aplicação demorou para responder à confirmação do gateway, e o gateway, como manda o protocolo de webhooks, reenviou a mesma confirmação. Reenvio é comportamento **esperado** de qualquer gateway, não um erro dele.
2. **Aplicação e banco (causa raiz):** o processamento do webhook **não é idempotente**. Processar a mesma mensagem duas vezes gera dois registros, quando deveria gerar um só. Falta a **chave de idempotência**: o id da transação no gateway, gravado com restrição de unicidade.

## 5. Impacto

- **Financeiro:** a receita registrada do pedido 2 é R$ 199,80, para um recebimento real de R$ 99,90. Relatórios de faturamento e a conciliação ficam superestimados.
- **Risco de estorno indevido:** quem tentar "resolver" pelo gateway, estornando o excedente, vai devolver ao cliente R$ 99,90 que ele pagou de fato. **A correção é só no banco.**
- **Indicadores:** o pagamento duplicado também entra nas estatísticas de pagamentos aprovados (por exemplo, no tempo médio até aprovação da [investigação 04](../04-data-invalida/README.md)).

## 6. Correção proposta

> **Não executada.** A correção foi testada numa cópia descartável do banco: depois dela, a detecção retorna 0 linhas, um webhook reenviado com o mesmo id de transação é ignorado (o segundo `INSERT` grava 0 linhas) e um pagamento dividido legítimo continua sendo aceito e não é marcado como duplicado.

### 6.1 Remover o registro duplicado

Antes, confirmar no painel do gateway que existe **uma única transação** para o pedido 2. Depois:

```sql
DELETE FROM pagamentos WHERE id = 11;
```

O registro mantido é o primeiro (`2`), que corresponde à entrega original do webhook. Assim como na [investigação 01](../01-clientes-duplicados/README.md), vale guardar uma cópia do registro removido numa tabela de auditoria.

### 6.2 Chave de idempotência no banco

```sql
ALTER TABLE pagamentos ADD COLUMN transacao_gateway_id VARCHAR(64);

CREATE UNIQUE INDEX pagamentos_transacao_gateway_unica
    ON pagamentos (transacao_gateway_id);
```

- Os pagamentos antigos ficam com a coluna vazia (`NULL`). O índice único aceita vários `NULL`, então ele pode ser criado sem preencher o histórico. Se o gateway permitir consultar as transações antigas, vale preencher depois.
- Em produção, criar o índice com `CREATE UNIQUE INDEX CONCURRENTLY`, para não bloquear a tabela.

### 6.3 Processamento idempotente na aplicação

Gravar o webhook usando a chave de idempotência, de forma que um reenvio não faça nada:

```sql
INSERT INTO pagamentos (pedido_id, valor, data_pagamento, status, transacao_gateway_id)
VALUES ($1, $2, $3, 'aprovado', $4)
ON CONFLICT (transacao_gateway_id) DO NOTHING;
```

- **Responder rápido ao gateway:** confirmar o recebimento do webhook logo que ele chega e processar depois (numa fila, por exemplo). Isso reduz os reenvios, mas **não substitui** a idempotência: reenvios acontecem de qualquer forma (rede, deploy, timeout).
- **Monitoramento:** rodar o [`deteccao.sql`](deteccao.sql) junto com a conciliação diária.

## 7. Como reproduzir

Com o banco no ar (`docker compose up -d --wait`, ver o [README principal](../../README.md)):

```bash
docker compose exec -T postgres psql -U postgres -d defect_investigation < investigacoes/05-pagamento-duplicado/exploracao.sql
```
