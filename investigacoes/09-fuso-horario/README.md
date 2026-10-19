# Investigação 09 — Fuso horário misturado na mesma coluna

| | |
|---|---|
| **Defeito** | Pedidos do app gravados em UTC numa coluna em que o resto do sistema grava horário de Brasília |
| **Registros afetados** | 2 pedidos: `14` e `15`, feitos na noite de 31/01 e registrados como 01/02 |
| **Causa raiz** | As colunas de data são `timestamp without time zone`: guardam só "dia e hora", sem dizer de que fuso. O app grava em UTC, e o site e o gateway, em horário de Brasília |
| **Severidade** | Alta: vendas atribuídas ao dia e ao mês errados, o que afeta fechamento mensal, metas e comissões |
| **Status** | Diagnóstico concluído, com correção proposta e **não executada** |

Arquivos desta investigação:

- [`exploracao.sql`](exploracao.sql): as queries na ordem em que foram usadas, numeradas conforme os passos abaixo.
- [`deteccao.sql`](deteccao.sql): a query final de detecção, que procura pedidos cujo pagamento só fica no padrão normal quando se descontam as 3 horas do fuso. É a mesma query que a CI executa.

---

## 1. Sintoma relatado

> Chamado do financeiro: no fechamento de janeiro, o relatório de **vendas** (pela data do pedido) e o de **recebimentos** (pela data do pagamento) não batem. Há pagamentos de 31/01 cujos pedidos aparecem em fevereiro.

## 2. Hipóteses iniciais

| # | Hipótese | Como confirmar ou descartar |
|---|---|---|
| H1 | Pedidos de fim de mês pagos no mês seguinte (diferença normal entre vendas e recebimentos) | O pagamento viria **depois** do pedido |
| H2 | Datas digitadas erradas, como na [investigação 04](../04-data-invalida/README.md) | Diferenças arbitrárias, sem padrão |
| H3 | Fuso horário: parte das datas gravada em UTC, e parte em horário de Brasília | Diferença de exatamente 3 horas (o fuso), mais o tempo normal de aprovação |

## 3. Investigação

### Passo 1: pedidos e pagamentos em meses diferentes

```sql
SELECT p.id AS pedido_id, p.data_pedido, pg.data_pagamento,
       to_char(p.data_pedido, 'YYYY-MM') AS mes_do_pedido,
       to_char(pg.data_pagamento, 'YYYY-MM') AS mes_do_pagamento,
       p.valor_total
FROM pedidos p
JOIN pagamentos pg ON pg.pedido_id = p.id AND pg.status = 'aprovado'
WHERE to_char(p.data_pedido, 'YYYY-MM') <> to_char(pg.data_pagamento, 'YYYY-MM');
```

| pedido_id | data_pedido | data_pagamento | mes_do_pedido | mes_do_pagamento | valor_total |
|---|---|---|---|---|---|
| 14 | 2026-02-01 01:30:00 | 2026-01-31 22:35:00 | 2026-02 | 2026-01 | 99.90 |
| 15 | 2026-02-01 02:10:00 | 2026-01-31 23:15:00 | 2026-02 | 2026-01 | 49.90 |

**Achado:** **H1 descartada.** Os pagamentos não vieram depois, e sim **antes** dos pedidos: o pagamento é de 31/01 e o pedido, de 01/02. Pela ordem natural dos eventos, isso é impossível.

### Passo 2: os dois pedidos e o horário de todos

```sql
SELECT p.id AS pedido_id, c.nome AS cliente, p.vendedor_id, p.data_pedido, p.status, p.valor_total
FROM pedidos p
JOIN clientes c ON c.id = p.cliente_id
WHERE p.id IN (14, 15);

SELECT COUNT(*) FILTER (WHERE extract(hour FROM data_pedido) BETWEEN 8 AND 20) AS pedidos_entre_8h_e_20h,
       COUNT(*) FILTER (WHERE extract(hour FROM data_pedido) NOT BETWEEN 8 AND 20) AS pedidos_fora_desse_horario,
       string_agg(id::text, ', ' ORDER BY id) FILTER (WHERE extract(hour FROM data_pedido) NOT BETWEEN 8 AND 20) AS quais
FROM pedidos;
```

| pedido_id | cliente | vendedor_id | data_pedido | status | valor_total |
|---|---|---|---|---|---|
| 14 | Gabriela Dias Ramos | *(null)* | 2026-02-01 01:30:00 | entregue | 99.90 |
| 15 | Diego Alves Pereira | *(null)* | 2026-02-01 02:10:00 | confirmado | 49.90 |

| pedidos_entre_8h_e_20h | pedidos_fora_desse_horario | quais |
|---|---|---|
| 13 | 2 | 14, 15 |

**Achados:**

- Os dois pedidos **não têm vendedor**, porque foram feitos pelo **app**, que não passa por vendedor. São os únicos sem vendedor.
- São também os **únicos fora do horário comercial**: 01:30 e 02:10 da madrugada. Todos os outros 13 pedidos estão entre 8h e 20h. Um pedido de madrugada não é impossível, mas dois, os dois do app, e os dois com o pagamento "antes" do pedido, é um padrão.

### Passo 3: a diferença, antes e depois de descontar o fuso

Se o app grava em UTC e o gateway grava em horário de Brasília (UTC-3), descontar 3 horas da data do pedido deve colocar o pagamento de volta no padrão normal, que é de 5 a 10 minutos depois do pedido. Para todos os pagamentos aprovados anteriores ao pedido:

```sql
SELECT p.id AS pedido_id,
       pg.data_pagamento - p.data_pedido AS diferenca_gravada,
       pg.data_pagamento - (p.data_pedido - interval '3 hours') AS diferenca_corrigida
FROM pedidos p
JOIN pagamentos pg ON pg.pedido_id = p.id AND pg.status = 'aprovado'
WHERE pg.data_pagamento < p.data_pedido;
```

| pedido_id | diferenca_gravada | diferenca_corrigida |
|---|---|---|
| 13 | -2 days | -1 days -21:00:00 |
| **14** | **-02:55:00** | **00:05:00** |
| **15** | **-02:55:00** | **00:05:00** |

**Achados:**

- **H3 confirmada para os pedidos 14 e 15.** A diferença gravada é de **-2h55**, ou seja, as 3 horas do fuso menos os 5 minutos de aprovação. Descontado o fuso, o pagamento cai **exatamente 5 minutos depois** do pedido, o mesmo padrão de todos os outros pagamentos.
- **H2 descartada** para eles: uma data digitada errada não daria a mesma diferença, ao minuto, em dois pedidos diferentes.
- **O contraste com a investigação 04.** O pedido 13 é o pagamento datado errado da [investigação 04](../04-data-invalida/README.md). Descontar o fuso **não** o explica: continua quase 2 dias antes do pedido. Lá, a hipótese de fuso foi descartada justamente porque a diferença era de dias inteiros. Aqui, ela é a causa. O mesmo sintoma ("pagamento antes do pedido") tem duas causas diferentes, e é o tamanho da diferença que as separa.

### Passo 4: a detecção final — é isolado?

A query de [`deteccao.sql`](deteccao.sql) procura pedidos cujo pagamento está antes do pedido **e** volta ao padrão normal (0 a 30 minutos depois) quando se descontam as 3 horas do fuso.

| pedido_id | data_pedido_gravada | data_pagamento | diferenca_gravada | data_pedido_em_brasilia | diferenca_corrigida |
|---|---|---|---|---|---|
| 14 | 2026-02-01 01:30:00 | 2026-01-31 22:35:00 | -02:55:00 | 2026-01-31 22:30:00 | 00:05:00 |
| 15 | 2026-02-01 02:10:00 | 2026-01-31 23:15:00 | -02:55:00 | 2026-01-31 23:10:00 | 00:05:00 |

**Achado:** são só os dois pedidos do app. Com o fuso descontado, eles foram feitos em **31/01 às 22:30 e 23:10**, ainda em janeiro.

Esta detecção depende do pagamento: um pedido do app em UTC **sem** pagamento aprovado (pendente, por exemplo) não seria encontrado por ela. Para esses, o sinal que sobra é o do passo 2 (pedido sem vendedor e de madrugada), que é um indício, mas não uma prova.

### Passo 5: causa raiz — o tipo das colunas de data

```sql
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_name IN ('clientes', 'pedidos', 'pagamentos') AND data_type LIKE 'timestamp%';
```

| table_name | column_name | data_type |
|---|---|---|
| clientes | data_cadastro | timestamp without time zone |
| pagamentos | data_pagamento | timestamp without time zone |
| pedidos | data_pedido | timestamp without time zone |

**Achado:** as três colunas de data são `timestamp without time zone`. Esse tipo guarda "2026-02-01 01:30" e mais nada: não diz se é horário de Brasília, UTC ou qualquer outro. Enquanto um único sistema gravava (o site, em horário de Brasília), funcionava. Quando o app passou a gravar em UTC, os dois fusos se misturaram na mesma coluna, e o banco não tem como distinguir um do outro.

### Passo 6: impacto — as vendas de janeiro e fevereiro

```sql
WITH corrigido AS (
    SELECT id, valor_total,
           CASE WHEN id IN (14, 15) THEN data_pedido - interval '3 hours' ELSE data_pedido END AS data_pedido
    FROM pedidos
)
SELECT m.mes,
       (SELECT SUM(valor_total) FROM pedidos   WHERE to_char(data_pedido, 'YYYY-MM') = m.mes) AS vendas_como_estao,
       (SELECT SUM(valor_total) FROM corrigido WHERE to_char(data_pedido, 'YYYY-MM') = m.mes) AS vendas_corrigidas
FROM (VALUES ('2026-01'), ('2026-02')) AS m(mes);
```

| mes | vendas_como_estao | vendas_corrigidas |
|---|---|---|
| 2026-01 | 1439.20 | 1589.00 |
| 2026-02 | 779.60 | 629.80 |

**Achado:** janeiro aparece com **R$ 149,80 a menos**, e fevereiro com **R$ 149,80 a mais**. É exatamente a soma dos dois pedidos.

## 4. Causa raiz

1. **Integração (gatilho):** o app, lançado em janeiro, envia a data do pedido em UTC, o padrão de muitas APIs. O site e o gateway gravam em horário de Brasília.
2. **Banco (causa raiz):** as colunas de data são `timestamp without time zone`. Elas aceitam os dois formatos sem reclamar, porque não guardam o fuso, e a mistura passa a existir em silêncio.

Todo pedido feito pelo app entre 21h e 23h59 de Brasília cai no **dia seguinte**. No último dia do mês, cai no **mês seguinte**.

## 5. Impacto

- **Fechamento mensal:** vendas de janeiro subestimadas em R$ 149,80, e de fevereiro superestimadas no mesmo valor.
- **Relatórios diários e comissões:** qualquer relatório por dia atribui as vendas noturnas do app ao dia seguinte.
- **Outras verificações:** os dois pagamentos "antes do pedido" também aparecem na detecção de datas implausíveis da investigação 04, que passou a encontrar 3 casos (o pagamento 10 e estes dois). Lá, o relatório explica que os novos casos são deste defeito.
- **Crescimento do problema:** cada pedido novo do app aumenta a mistura. Quanto mais tempo passa, maior a correção.

## 6. Correção proposta

> **Não executada.** A correção foi testada numa cópia descartável do banco. Depois dela, os pedidos 14 e 15 aparecem às 22:30 e 23:10 de 31/01 no horário de Brasília (e continuam corretos em UTC). Entre os pagamentos anteriores ao pedido, sobra só o 10, da investigação 04. O relatório mensal fecha janeiro em R$ 1.589,00, e um pedido novo enviado pelo app em UTC é gravado e lido corretamente.

### 6.1 Corrigir os pedidos do app

```sql
UPDATE pedidos
SET data_pedido = (data_pedido AT TIME ZONE 'UTC') AT TIME ZONE 'America/Sao_Paulo'
WHERE id IN (14, 15);
```

A expressão lê o valor como UTC e o converte para o horário de Brasília, em vez de simplesmente subtrair 3 horas. Isso deixa a conversão correta mesmo se um dia houver horário de verão de novo. Os ids vêm da detecção. Antes de rodar, confirmar no log do app quais pedidos vieram por ele.

### 6.2 Fazer as colunas guardarem o fuso

```sql
ALTER TABLE pedidos    ALTER COLUMN data_pedido    TYPE timestamptz USING data_pedido    AT TIME ZONE 'America/Sao_Paulo';
ALTER TABLE pagamentos ALTER COLUMN data_pagamento TYPE timestamptz USING data_pagamento AT TIME ZONE 'America/Sao_Paulo';
ALTER TABLE clientes   ALTER COLUMN data_cadastro  TYPE timestamptz USING data_cadastro  AT TIME ZONE 'America/Sao_Paulo';
```

- **`timestamptz` guarda o instante**, e não "dia e hora soltos". Um valor enviado como `2026-02-01 02:50:00+00` (UTC) e outro enviado como `2026-01-31 23:50:00-03` (Brasília) viram **o mesmo instante**. A mistura deixa de ser possível.
- O `USING ... AT TIME ZONE 'America/Sao_Paulo'` diz ao banco como interpretar os valores antigos, que (depois da 6.1) estão todos no horário de Brasília.
- **Ordem:** a 6.1 precisa vir antes. Senão, os dois pedidos do app seriam interpretados como horário de Brasília e ficariam 3 horas errados para sempre.
- **Bloqueio:** o `ALTER COLUMN ... TYPE` reescreve a tabela inteira e bloqueia leituras e escritas enquanto roda. Numa base grande, precisa de janela de manutenção.

### 6.3 Relatórios sempre com o fuso explícito

```sql
SELECT to_char(data_pedido AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM') AS mes, SUM(valor_total) AS vendas
FROM pedidos
GROUP BY 1;
```

Com `timestamptz`, "que dia foi" depende de qual fuso se usa para perguntar. Os relatórios devem dizer **explicitamente** que o dia de negócio é o de Brasília, e não depender da configuração do servidor.

### 6.4 Na integração

O app pode continuar enviando em UTC, desde que mande **com o fuso** (`...Z` ou `+00:00`), e não "dia e hora soltos". Com a coluna `timestamptz`, o banco faz a conversão.

- **Monitoramento:** até a 6.2 ser aplicada, rodar o [`deteccao.sql`](deteccao.sql) no fechamento de cada mês.

## 7. Como reproduzir

Com o banco no ar (`docker compose up -d --wait`, ver o [README principal](../../README.md)):

```bash
docker compose exec -T postgres psql -U postgres -d defect_investigation < investigacoes/09-fuso-horario/exploracao.sql
```
