# Investigação 08 — Duplicidade aproximada no catálogo

| | |
|---|---|
| **Defeito** | O mesmo serviço cadastrado duas vezes no catálogo, com nomes parecidos mas não iguais |
| **Registros afetados** | Produtos `5` ("Consultoria Avulsa (hora)") e `9` ("Consutoria avulsa - hora"), e o pedido `13`, lançado no cadastro duplicado |
| **Causa raiz** | A busca de produtos da tela de venda é por texto exato e não achou o produto existente. O vendedor cadastrou um novo, e nada no banco impede dois produtos com o mesmo nome (nem com nomes parecidos) |
| **Severidade** | Média: as vendas do serviço ficam divididas entre dois cadastros, e relatórios por produto e por categoria saem errados |
| **Status** | Diagnóstico concluído, com correção proposta e **não executada** |

Arquivos desta investigação:

- [`exploracao.sql`](exploracao.sql): as queries na ordem em que foram usadas, numeradas conforme os passos abaixo.
- [`deteccao.sql`](deteccao.sql): a query final de detecção, que usa similaridade de texto (`pg_trgm`) para achar nomes de produtos parecidos. É a mesma query que a CI executa.

---

## 1. Sintoma relatado

> Chamado do comercial: no relatório de vendas por produto aparece um item **"Consutoria avulsa - hora"**, que ninguém lembra de ter criado, e as vendas de consultoria parecem mais baixas do que o time esperava.

## 2. Hipóteses iniciais

| # | Hipótese | Como confirmar ou descartar |
|---|---|---|
| H1 | É um produto novo e legítimo, um serviço diferente | Comparar preço, categoria e nome com o catálogo existente |
| H2 | É o mesmo serviço cadastrado de novo, com outro nome | Procurar no catálogo nomes parecidos, e não só iguais |
| H3 | Há outros produtos duplicados | Medir a similaridade entre todos os pares de produtos |

## 3. Investigação

### Passo 1: o relatório de vendas por produto

```sql
SELECT pr.id AS produto_id, pr.nome AS produto, COUNT(i.id) AS qtd_itens,
       COALESCE(SUM(i.quantidade * i.preco_unitario), 0) AS receita
FROM produtos pr
LEFT JOIN itens_pedido i ON i.produto_id = pr.id
GROUP BY pr.id, pr.nome
ORDER BY receita DESC, pr.id;
```

| produto_id | produto | qtd_itens | receita |
|---|---|---|---|
| 4 | Pacote de Onboarding | 1 | 500.00 |
| 3 | Plano Enterprise Mensal | 2 | 499.80 |
| **5** | **Consultoria Avulsa (hora)** | 2 | **300.00** |
| 6 | MÃ³dulo de RelatÃ³rios | 3 | 239.70 |
| 2 | Plano Profissional Mensal | 2 | 199.80 |
| **9** | **Consutoria avulsa - hora** | 1 | **150.00** |
| 1 | Plano Básico Mensal | 3 | 149.70 |
| 7 | MÃ³dulo de IntegraÃ§Ãµes | 1 | 119.90 |
| 8 | Suporte PrioritÃ¡rio | 1 | 59.90 |

**Achado:** o produto `9` tem o **mesmo preço** do `5` (R$ 150,00 por hora) e um nome quase igual, com um erro de digitação ("Consutoria"). Tudo indica que é o mesmo serviço, o que **descarta H1**. A confirmação final é do time comercial, mas um serviço diferente teria outro nome, e não o mesmo nome escrito errado. Os nomes quebrados ("MÃ³dulo"...) são outro defeito, da [investigação 07](../07-codificacao-quebrada/README.md).

### Passo 2: por que a comparação exata não acha

A primeira ideia seria comparar os nomes de forma "tolerante", ignorando maiúsculas e pontuação:

```sql
SELECT id, nome,
       lower(nome) = lower('Consultoria Avulsa (hora)') AS igual_ignorando_maiusculas,
       trim(regexp_replace(lower(nome), '[[:punct:][:space:]]+', ' ', 'g'))
         = trim(regexp_replace(lower('Consultoria Avulsa (hora)'), '[[:punct:][:space:]]+', ' ', 'g')) AS igual_sem_pontuacao
FROM produtos
WHERE id IN (5, 9);
```

| id | nome | igual_ignorando_maiusculas | igual_sem_pontuacao |
|---|---|---|---|
| 5 | Consultoria Avulsa (hora) | true | true |
| 9 | Consutoria avulsa - hora | false | false |

**Achado:** nenhuma comparação exata reconhece o produto `9`, nem a mais tolerante. Basta uma letra faltando ("Consutoria") para a igualdade falhar. É o mesmo motivo pelo qual a busca da tela de venda, que é por texto exato, não achou o produto `5`, e o vendedor acabou cadastrando outro.

### Passo 3: similaridade entre todos os pares

Para achar nomes **parecidos**, a extensão `pg_trgm` do PostgreSQL quebra cada nome em sequências de 3 letras (trigramas) e mede a fração em comum: 0 é nada em comum, 1 é igual. Ela já ignora maiúsculas e pontuação, e um erro de digitação só afeta alguns trigramas. A extensão tem um limite padrão (o do operador `%`) de **0.3**: pares acima dele são considerados parecidos. Os pares de produtos acima desse limite:

```sql
SELECT a.id AS produto_a, b.id AS produto_b, a.nome AS nome_a, b.nome AS nome_b,
       round(similarity(a.nome, b.nome)::numeric, 3) AS similaridade
FROM produtos a
JOIN produtos b ON a.id < b.id
WHERE similarity(a.nome, b.nome) >= 0.3
ORDER BY similarity(a.nome, b.nome) DESC;
```

| produto_a | produto_b | nome_a | nome_b | similaridade |
|---|---|---|---|---|
| **5** | **9** | **Consultoria Avulsa (hora)** | **Consutoria avulsa - hora** | **0.808** |
| 1 | 2 | Plano Básico Mensal | Plano Profissional Mensal | 0.419 |
| 1 | 3 | Plano Básico Mensal | Plano Enterprise Mensal | 0.419 |
| 2 | 3 | Plano Profissional Mensal | Plano Enterprise Mensal | 0.371 |

**Achados:**

- **H2 confirmada:** o par `5` e `9` tem similaridade **0.808**, muito acima de todos os outros.
- **A escolha do limite importa.** Os três planos ("Plano Básico Mensal", "Plano Profissional Mensal", "Plano Enterprise Mensal") são produtos **legítimos e diferentes**, mas compartilham "Plano" e "Mensal" e chegam a **0.419**. Com o limite padrão de 0.3, os três pares de planos seriam marcados como duplicados: três falsos positivos para um caso real.
- **O limite foi definido pelos dados:** 0.6 fica no meio do intervalo entre o maior par legítimo (0.419) e o duplicado (0.808). Num catálogo maior, esse intervalo pode ser menor, e o resultado da detecção deve ser tratado como **lista de suspeitos para revisão**, e não como certeza.
- **A similaridade depende do locale do banco.** A `pg_trgm` decide o que conta como "letra" a partir do locale do banco, e isso muda o resultado para caracteres fora do ASCII. O par "MÃ³dulo de RelatÃ³rios" × "MÃ³dulo de IntegraÃ§Ãµes" (texto quebrado da investigação 07) dá **0.297** num banco com locale português (Windows) e **0.286** num banco Linux. O teste de regressão dos relatórios pegou essa diferença na primeira execução da CI. Os valores que sustentam a conclusão (0.808, 0.419 e 0.371) são **iguais** nos dois ambientes, e o par divergente fica abaixo do limite padrão, fora da tabela. Na prática, um limite escolhido num ambiente deve ser validado no ambiente onde a detecção vai rodar, principalmente com nomes acentuados.

### Passo 4: a detecção final — é isolado?

A query de [`deteccao.sql`](deteccao.sql) lista os pares com similaridade de pelo menos 0.6. Ela mostra também se o preço é o mesmo, um sinal a mais para quem revisar.

| produto_original | produto_suspeito | nome_original | nome_suspeito | similaridade | mesmo_preco |
|---|---|---|---|---|---|
| 5 | 9 | Consultoria Avulsa (hora) | Consutoria avulsa - hora | 0.808 | true |

**Achado:** **H3 descartada.** É o único par suspeito do catálogo.

### Passo 5: impacto — as vendas divididas

```sql
SELECT pr.id AS produto_id, pr.nome AS produto, pr.categoria,
       array_to_string(array_agg(i.pedido_id ORDER BY i.pedido_id), ', ') AS pedidos,
       SUM(i.quantidade * i.preco_unitario) AS receita
FROM produtos pr
JOIN itens_pedido i ON i.produto_id = pr.id
WHERE pr.id IN (5, 9)
GROUP BY pr.id, pr.nome, pr.categoria;
```

| produto_id | produto | categoria | pedidos | receita |
|---|---|---|---|---|
| 5 | Consultoria Avulsa (hora) | ServiÃ§o | 5, 9 | 300.00 |
| 9 | Consutoria avulsa - hora | Serviço | 13 | 150.00 |

**Achados:**

- A consultoria vendeu **R$ 450,00** em 3 pedidos, mas o relatório mostra R$ 300,00 num produto e R$ 150,00 em outro.
- **Dois defeitos se somam na categoria:** o produto `5` está em "ServiÃ§o", com o texto quebrado da [investigação 07](../07-codificacao-quebrada/README.md), e o `9`, cadastrado à mão, está em "Serviço" correto. A categoria aparece dividida em duas, exatamente o risco que a investigação 07 apontava.

### Passo 6: causa raiz — o que o banco garante sobre o nome

```sql
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'produtos';
```

| indexname | indexdef |
|---|---|
| produtos_pkey | CREATE UNIQUE INDEX produtos_pkey ON public.produtos USING btree (id) |

**Achado:** a única regra de unicidade é o `id`. Nada impede dois produtos com o **mesmo** nome, e muito menos com nomes **parecidos**.

## 4. Causa raiz

1. **Aplicação (causa raiz):** a busca de produtos da tela de venda é por texto exato. Quando o vendedor não achou a consultoria (por digitar diferente, ou por buscar "consultoria hora"), a única saída que a tela oferecia era cadastrar um produto novo.
2. **Banco (por que passou):** `produtos.nome` não tem nenhuma restrição de unicidade, e nenhum processo compara um nome novo com os existentes antes de gravar.

## 5. Impacto

- **Relatórios:** vendas de um mesmo serviço divididas entre dois produtos, o que distorce ranking, metas e comissões por produto.
- **Categoria dividida:** somado ao defeito da investigação 07, o mesmo serviço aparece em duas categorias, "ServiÃ§o" e "Serviço".
- **Manutenção:** um reajuste de preço feito em um dos cadastros não vale para o outro, e o catálogo deriva com o tempo.

## 6. Correção proposta

> **Não executada.** A correção foi testada numa cópia descartável do banco. Depois dela, o produto `5` tem os 3 pedidos (5, 9 e 13) e R$ 450,00, e um novo cadastro "consultoria avulsa - HORA" é bloqueado pelo índice único. O teste também mostrou o **limite** do índice: "Consutoria avulsa - hora", com erro de digitação, passa por ele, e por isso a correção tem duas camadas.

### 6.1 Unificar os cadastros

```sql
BEGIN;

UPDATE itens_pedido SET produto_id = 5 WHERE produto_id = 9;
DELETE FROM produtos WHERE id = 9;

COMMIT;
```

Antes de rodar, confirmar com o time comercial que os dois produtos são o mesmo serviço (passo 1). O registro mantido é o original (`5`). Assim como nas investigações 01 e 05, vale guardar uma cópia do registro removido.

### 6.2 Impedir nomes iguais (com variações de escrita)

```sql
CREATE UNIQUE INDEX produtos_nome_unico
    ON produtos (trim(regexp_replace(lower(nome), '[[:punct:][:space:]]+', ' ', 'g')));
```

O índice é sobre o nome **normalizado** (minúsculas, sem pontuação e com os espaços padronizados). Ele barra "consultoria avulsa - HORA", "Consultoria Avulsa (hora)" e "consultoria  avulsa hora" como se fossem o mesmo nome. Os acentos são preservados.

### 6.3 Sugerir nomes parecidos na tela de cadastro

O índice da 6.2 **não** pega erro de digitação. Para isso, a tela de cadastro deve, antes de salvar, procurar produtos parecidos e perguntar "você quis dizer...?":

```sql
SELECT id, nome, round(similarity(nome, $1)::numeric, 3) AS similaridade
FROM produtos
WHERE similarity(nome, $1) >= 0.6
ORDER BY similaridade DESC;
```

Testado com "Consutoria avulsa - hora": a sugestão devolve "Consultoria Avulsa (hora)" com 0.808. A decisão final continua com quem cadastra, porque nomes parecidos podem ser produtos diferentes (como os planos do passo 3). Num catálogo grande, um índice `GIN` com `gin_trgm_ops` deixa essa busca rápida.

### 6.4 Busca tolerante na tela de venda

A causa raiz é a busca exata. Trocá-la por uma busca por similaridade, a mesma técnica, faz o vendedor encontrar o produto existente e elimina o motivo para cadastrar outro.

- **Monitoramento:** rodar o [`deteccao.sql`](deteccao.sql) periodicamente e revisar os pares suspeitos. O limite de 0.6 deve ser revisto se o catálogo crescer.

## 7. Como reproduzir

Com o banco no ar (`docker compose up -d --wait`, ver o [README principal](../../README.md)):

```bash
docker compose exec -T postgres psql -U postgres -d defect_investigation < investigacoes/08-duplicidade-aproximada/exploracao.sql
```
