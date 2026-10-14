# Investigação 04 — Data inválida

| | |
|---|---|
| **Defeito** | Um pagamento está datado antes do próprio pedido existir |
| **Registros afetados** | 1 pagamento: `10` (R$ 150,00), do pedido `13` |
| **Causa raiz** | O pagamento foi lançado à mão, com a data digitada errada, e o banco não valida a data informada nem registra a origem do lançamento |
| **Severidade** | Média: o dinheiro foi recebido, mas os indicadores financeiros ficam distorcidos e a conciliação por data falha |
| **Status** | Diagnóstico concluído, com correção proposta e **não executada** |

Arquivos desta investigação:

- [`exploracao.sql`](exploracao.sql): as queries na ordem em que foram usadas, numeradas conforme os passos abaixo.
- [`deteccao.sql`](deteccao.sql): a query final de detecção, que procura datas implausíveis em clientes, pedidos e pagamentos. É a mesma query que a CI executa.

---

## 1. Sintoma relatado

> Chamado do financeiro: o indicador **"tempo médio até a aprovação do pagamento"** do painel está **negativo** (cerca de -5 horas). Pelo processo, o pagamento é aprovado alguns minutos depois do pedido.

Um tempo médio negativo é impossível no mundo real. Como é uma média, basta um registro muito errado para puxar tudo para baixo, então a investigação começa procurando quem está distorcendo a conta.

## 2. Hipóteses iniciais

| # | Hipótese | Como confirmar ou descartar |
|---|---|---|
| H1 | Erro de cálculo no painel, sem problema nos dados | Recalcular o indicador direto no banco |
| H2 | Algum pagamento tem data anterior à do pedido | Listar o tempo até a aprovação de cada pagamento |
| H3 | Se H2: problema de fuso horário | A diferença seria de algumas horas (no máximo 14h), não de dias |
| H4 | Se H2: inversão de dia e mês na digitação | A data errada seria a data certa com dia e mês trocados |
| H5 | Se H2: data digitada errada num lançamento manual | O registro foge do padrão dos lançamentos automáticos |

## 3. Investigação

### Passo 1: recalcular o indicador no banco

```sql
SELECT COUNT(*) AS qtd_pagamentos_aprovados,
       MIN(pg.data_pagamento - p.data_pedido) AS menor_tempo,
       MAX(pg.data_pagamento - p.data_pedido) AS maior_tempo,
       AVG(pg.data_pagamento - p.data_pedido) AS tempo_medio
FROM pagamentos pg
JOIN pedidos p ON p.id = pg.pedido_id
WHERE pg.status = 'aprovado';
```

| qtd_pagamentos_aprovados | menor_tempo | maior_tempo | tempo_medio |
|---|---|---|---|
| 9 | **-2 days** | 00:10:04 | **-05:13:52.9** |

**Achado:** **H1 descartada.** O banco reproduz o número do painel: o tempo médio passa de -5 horas. O painel está calculando certo, e o problema está nos dados. O `menor_tempo` de **-2 dias** já mostra que existe pelo menos um pagamento aprovado dois dias antes do pedido.

### Passo 2: o tempo de cada pagamento

```sql
SELECT pg.id AS pagamento_id, p.id AS pedido_id, p.data_pedido, pg.data_pagamento,
       pg.data_pagamento - p.data_pedido AS tempo_ate_aprovacao
FROM pagamentos pg
JOIN pedidos p ON p.id = pg.pedido_id
WHERE pg.status = 'aprovado'
ORDER BY tempo_ate_aprovacao, pg.id;
```

| pagamento_id | pedido_id | data_pedido | data_pagamento | tempo_ate_aprovacao |
|---|---|---|---|---|
| **10** | **13** | **2026-02-10 10:00:00** | **2026-02-08 10:00:00** | **-2 days** |
| 1 | 1 | 2026-01-11 10:00:00 | 2026-01-11 10:05:00 | 00:05:00 |
| 5 | 5 | 2026-01-21 10:45:00 | 2026-01-21 10:50:00 | 00:05:00 |
| 6 | 7 | 2026-01-29 15:30:00 | 2026-01-29 15:35:00 | 00:05:00 |
| 7 | 8 | 2026-02-03 13:00:00 | 2026-02-03 13:05:00 | 00:05:00 |
| 9 | 12 | 2026-02-01 14:00:00 | 2026-02-01 14:05:00 | 00:05:00 |
| 2 | 2 | 2026-01-13 15:00:00 | 2026-01-13 15:10:00 | 00:10:00 |
| 3 | 3 | 2026-01-16 11:30:00 | 2026-01-16 11:40:00 | 00:10:00 |
| 11 | 2 | 2026-01-13 15:00:00 | 2026-01-13 15:10:04 | 00:10:04 |

**Achado:** **H2 confirmada.** Um único pagamento (`10`) explica todo o desvio. Sem ele, o tempo médio volta para **6min53s**, coerente com o processo. Os outros oito seguem um padrão claro: são aprovados **5 a 10 minutos depois** do pedido.

O pagamento `11` chama atenção por outro motivo: ele é do mesmo pedido `2` que o pagamento `2`, tem o mesmo valor e veio 4 segundos depois. É uma duplicidade, investigada à parte na [investigação 05](../05-pagamento-duplicado/README.md). Como o tempo dele é normal, ele não muda a conclusão desta investigação.

Mais três observações sobre o pagamento 10, que ajudam a separar as hipóteses H3 a H5:

- A diferença é de **exatamente 48 horas**, e não um número quebrado de horas. **H3 descartada:** fuso horário desloca a data em algumas horas (no máximo 14), nunca em dias inteiros.
- Trocar dia e mês de uma data em torno de 10/02 geraria 02/10 (outubro), não 08/02. **H4 descartada.**
- O horário do pagamento é **idêntico ao do pedido** (10:00:00). Nenhum outro pagamento repete o horário do pedido, porque todos têm os minutos de processamento somados. Isso indica que **alguém copiou o horário do pedido e errou o dia**, o que é compatível com **H5**.

### Passo 3: detalhe do pagamento suspeito

```sql
SELECT pg.id AS pagamento_id, pg.valor, pg.status AS status_pagamento, pg.data_pagamento,
       p.id AS pedido_id, p.status AS status_pedido, p.valor_total, p.data_pedido,
       c.nome AS cliente, v.nome AS vendedor
FROM pagamentos pg
JOIN pedidos p ON p.id = pg.pedido_id
JOIN clientes c ON c.id = p.cliente_id
LEFT JOIN vendedores v ON v.id = p.vendedor_id
WHERE pg.id = 10;
```

| pagamento_id | valor | status_pagamento | data_pagamento | pedido_id | status_pedido | valor_total | data_pedido | cliente | vendedor |
|---|---|---|---|---|---|---|---|---|---|
| 10 | 150.00 | aprovado | 2026-02-08 10:00:00 | 13 | confirmado | 150.00 | 2026-02-10 10:00:00 | Henrique Lopes Teixeira | Thiago Almeida |

**Achado:** fora a data, o registro é consistente: o valor bate com o pedido e o status do pedido (`confirmado`) é compatível com o pagamento `aprovado`. Ou seja, o pagamento **aconteceu**, e só a data está errada. Por isso, ele não aparece na [investigação 03](../03-status-inconsistente/README.md), que olha só para status.

### Passo 4: é isolado?

A detecção foi generalizada para qualquer data que contradiga a ordem natural dos eventos (**cadastro do cliente → pedido → pagamento**) ou que ainda não tenha acontecido:

- pagamento anterior ao pedido;
- pedido anterior ao cadastro do cliente;
- data no futuro, em qualquer das três tabelas.

A query completa está em [`deteccao.sql`](deteccao.sql).

| tabela | registro_id | motivo | data_registro | data_referencia |
|---|---|---|---|---|
| pagamentos | 10 | pagamento anterior ao pedido | 2026-02-08 10:00:00 | 2026-02-10 10:00:00 |

**Achado:** é o único registro com data implausível no banco.

### Passo 5: causa raiz — o que o banco registra sobre o lançamento?

Colunas, constraints e triggers da tabela `pagamentos`:

```sql
SELECT column_name, data_type, column_default, is_nullable
FROM information_schema.columns
WHERE table_name = 'pagamentos';

SELECT conname, contype, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'pagamentos'::regclass;

SELECT tgname FROM pg_trigger
WHERE tgrelid = 'pagamentos'::regclass AND NOT tgisinternal;
```

| column_name | data_type | column_default | is_nullable |
|---|---|---|---|
| id | integer | nextval('pagamentos_id_seq') | NO |
| pedido_id | integer | | NO |
| valor | numeric | | NO |
| data_pagamento | timestamp without time zone | | YES |
| status | character varying | 'pendente' | NO |

| constraint | tipo | definição |
|---|---|---|
| pagamentos_pedido_id_fkey | f | FOREIGN KEY (pedido_id) REFERENCES pedidos(id) |
| pagamentos_pkey | p | PRIMARY KEY (id) |

Triggers: **nenhuma.**

**Achados:**

- **Nada valida a data.** Não há `CHECK` nem trigger. Qualquer `data_pagamento` é aceita, inclusive uma anterior ao pedido ou no futuro.
- **Não dá para saber a origem do lançamento.** A tabela não tem uma coluna de origem (gateway ou manual), nem uma data de quando o registro foi criado (`registrado_em`). A `data_pagamento` é a **única** data, e por isso, quando ela está errada, não sobra nenhuma outra referência no banco.

## 4. Causa raiz

1. **Processo (causa raiz):** o pagamento do pedido 13 foi lançado manualmente, na conciliação com o gateway, e a data foi digitada errada. O operador manteve o horário do pedido e errou o dia. As evidências do passo 2 (horário idêntico ao do pedido, diferença de dias exatos, fora do padrão de 5 a 10 minutos dos lançamentos automáticos) apontam nessa direção. A confirmação definitiva depende do registro de conciliação ou dos logs da aplicação, porque o banco não guarda a origem.
2. **Banco (por que passou):** não há validação da data do pagamento em relação ao pedido nem em relação ao momento atual. Como essa regra envolve duas tabelas, ela não cabe numa `CHECK` simples e precisa de um trigger.
3. **Rastreabilidade:** a tabela mistura "quando o pagamento aconteceu" e "quando foi registrado" numa única coluna, e não diz quem registrou.

## 5. Impacto

- **Indicadores:** o "tempo médio até aprovação" sai negativo (-5h14min no lugar de 6min53s). Qualquer indicador por período também atribui R$ 150,00 ao dia 08/02, quando o pedido nem existia.
- **Conciliação:** um cruzamento com o extrato do gateway por data não vai encontrar esse pagamento no dia 08/02, e vai gerar uma divergência falsa nos dois dias.
- **Cliente:** nenhum, já que o pagamento foi feito e o pedido está correto.

## 6. Correção proposta

> **Não executada.** O trigger da seção 6.2 foi testado numa cópia descartável do banco. Com a data do pagamento corrigida, ele é criado sem erro e a detecção passa a retornar 0 linhas. Uma nova tentativa de lançar um pagamento datado antes do pedido é bloqueada, e uma com data no futuro também.

### 6.1 Corrigir o registro

Buscar a **data real** da transação no extrato do gateway e atualizar só esse registro:

```sql
-- Substituir pela data real que consta no gateway.
UPDATE pagamentos
SET data_pagamento = '<data real do gateway>'
WHERE id = 10;
```

Não vale "chutar" uma data, como copiar a do pedido ou somar 5 minutos. Uma data inventada só esconde o defeito, e a conciliação com o gateway continuaria sem bater.

### 6.2 Prevenção no banco

Como a regra compara duas tabelas, ela precisa de um trigger:

```sql
CREATE FUNCTION valida_data_pagamento() RETURNS trigger AS $$
DECLARE
    v_data_pedido timestamp;
BEGIN
    IF NEW.data_pagamento IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT data_pedido INTO v_data_pedido FROM pedidos WHERE id = NEW.pedido_id;

    IF NEW.data_pagamento < v_data_pedido THEN
        RAISE EXCEPTION 'data_pagamento (%) anterior a data do pedido % (%)',
            NEW.data_pagamento, NEW.pedido_id, v_data_pedido;
    END IF;

    IF NEW.data_pagamento > now() THEN
        RAISE EXCEPTION 'data_pagamento (%) no futuro', NEW.data_pagamento;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER pagamentos_valida_data
    BEFORE INSERT OR UPDATE OF data_pagamento, pedido_id ON pagamentos
    FOR EACH ROW EXECUTE FUNCTION valida_data_pagamento();
```

Pontos de atenção:

- **Ordem:** corrigir o pagamento 10 (6.1) antes. O trigger não verifica os dados que já existem, só os novos `INSERT`/`UPDATE`. Ele não falharia na criação, mas também não acusaria o registro antigo. O [`deteccao.sql`](deteccao.sql) é quem confirma que a base está limpa.
- **Limite:** o trigger fica em `pagamentos`. Se alguém alterar a `data_pedido` de um pedido já pago para uma data posterior ao pagamento, ele não dispara. Esse caso fica coberto pelo monitoramento com o `deteccao.sql`.

### 6.3 Rastreabilidade

Separar as duas informações que hoje estão misturadas numa única coluna:

```sql
ALTER TABLE pagamentos
    ADD COLUMN origem VARCHAR(20),                        -- 'gateway' | 'manual'
    ADD COLUMN registrado_em TIMESTAMP NOT NULL DEFAULT now();
```

- `registrado_em` é preenchida pelo banco e não pode ser digitada. Com ela, uma data de pagamento suspeita sempre tem uma segunda referência para comparação.
- `origem` permite cobrar uma conferência extra só dos lançamentos manuais, que é onde este defeito nasceu.

### 6.4 Processo

- Na tela de lançamento manual, validar a data antes de salvar e mostrar a data do pedido ao lado do campo.
- Rodar o [`deteccao.sql`](deteccao.sql) periodicamente, junto com o fechamento financeiro.

## 7. Como reproduzir

Com o banco no ar (`docker compose up`, ver o [README principal](../../README.md)):

```bash
docker compose exec -T postgres psql -U postgres -d defect_investigation < investigacoes/04-data-invalida/exploracao.sql
```
