# Investigação 01 — Clientes duplicados

| | |
|---|---|
| **Defeito** | A mesma pessoa está cadastrada duas vezes na tabela `clientes` |
| **Registros afetados** | 1 par: clientes `1` e `11` |
| **Causa raiz** | A tabela `clientes` não tem nenhuma restrição de unicidade em e-mail ou documento |
| **Severidade** | Média: não há perda financeira, mas a base de clientes fica inflada e a comunicação com o cliente sai duplicada |
| **Status** | Diagnóstico concluído, com correção proposta e **não executada** |

Arquivos desta investigação:

- [`exploracao.sql`](exploracao.sql): as queries na ordem em que foram usadas, numeradas conforme os passos abaixo.
- [`deteccao.sql`](deteccao.sql): a query final de detecção, que lista todos os pares duplicados da base. É a mesma query que a CI executa.

---

## 1. Sintoma relatado

> Chamado de suporte: a cliente **Ana Carolina Ferreira** informou que recebeu dois e-mails de boas-vindas no dia do cadastro.

E-mail de boas-vindas duplicado tem duas explicações possíveis: o envio do e-mail se repetiu, ou o cadastro se repetiu. A segunda é mais grave, porque deixa lixo permanente na base. Por isso, a investigação começa pelo banco.

## 2. Hipóteses iniciais

| # | Hipótese | Como confirmar ou descartar |
|---|---|---|
| H1 | Existem dois registros da cliente | Buscar pelo e-mail informado no chamado |
| H2 | Se existirem dois registros, foi duplo clique no botão de cadastro | Registros idênticos, criados com milissegundos de diferença |
| H3 | Se existirem dois registros, foi um reenvio manual (timeout, erro de rede, usuário tentou de novo) | Diferença de segundos ou minutos, com dados redigitados |
| H4 | O caso não é isolado | Procurar o mesmo padrão em toda a base |

## 3. Investigação

### Passo 1: o caso relatado

Busca pelo e-mail da cliente, sem diferenciar maiúsculas de minúsculas:

```sql
SELECT id, nome, email, documento, telefone, data_cadastro, status
FROM clientes
WHERE lower(trim(email)) = 'ana.ferreira@example.com'
ORDER BY id;
```

| id | nome | email | documento | telefone | data_cadastro | status |
|---|---|---|---|---|---|---|
| 1 | Ana Carolina Ferreira | ana.ferreira@example.com | 11122233344 | 11988887777 | 2026-01-10 09:15:00 | ativo |
| 11 | Ana C. Ferreira | ana.ferreira@example.com | 11122233344 | 11988887777 | 2026-01-10 09:17:32 | ativo |

**Achado:** **H1 confirmada.** São dois registros com o mesmo e-mail, documento e telefone.

Os detalhes do par também separam H2 de H3:

- O intervalo entre os cadastros é de **2 minutos e 32 segundos**. Um duplo clique geraria registros com milissegundos de diferença.
- O nome foi **digitado de forma diferente** ("Ana Carolina Ferreira" e "Ana C. Ferreira"). Um duplo clique enviaria exatamente o mesmo formulário.

**Conclusão parcial:** **H2 descartada.** As evidências apontam para **H3**: a cliente preencheu o formulário de novo, provavelmente porque a primeira tentativa pareceu não ter funcionado (timeout, tela de erro ou demora na resposta). Para confirmar de vez, é preciso olhar os logs da aplicação no endpoint de cadastro entre 09:15 e 09:18, mas o banco já mostra um comportamento compatível só com essa hipótese.

### Passo 2: o caso é isolado?

Para varrer a base toda, a busca é generalizada para comparar todos os clientes entre si, aos pares. Dois cuidados nessa query:

- **Normalização:** o e-mail é comparado em minúsculas e sem espaços nas pontas, e o documento só pelos dígitos. Assim, cadastros como `Ana.Ferreira@Example.com` ou `111.222.333-44` também seriam pegos.
- **Cada par conta uma vez só:** a condição `a.id < b.id` evita que o mesmo par apareça duas vezes, uma como (1, 11) e outra como (11, 1). Ela também evita que um registro seja comparado com ele mesmo.

```sql
SELECT a.id AS id_original, b.id AS id_duplicado, ...
FROM clientes a
JOIN clientes b
    ON a.id < b.id
   AND (
        lower(trim(a.email)) = lower(trim(b.email))
        OR regexp_replace(a.documento, '\D', '', 'g') = regexp_replace(b.documento, '\D', '', 'g')
   );
```

A query completa está em [`deteccao.sql`](deteccao.sql).

| id_original | id_duplicado | nome_original | nome_duplicado | mesmo_email | mesmo_documento | intervalo |
|---|---|---|---|---|---|---|
| 1 | 11 | Ana Carolina Ferreira | Ana C. Ferreira | true | true | 00:02:32 |

**Achado:** **H4 descartada.** Hoje existe só esse par duplicado na base. Mesmo assim, a causa (passo 4) permite que o defeito se repita a qualquer momento.

### Passo 3: impacto — qual registro tem histórico?

Antes de propor qualquer correção, é preciso saber qual dos dois registros tem pedidos e pagamentos vinculados:

```sql
SELECT c.id AS cliente_id, c.nome, c.data_cadastro,
       COUNT(DISTINCT p.id) AS qtd_pedidos,
       COUNT(pg.id) AS qtd_pagamentos
FROM clientes c
LEFT JOIN pedidos p ON p.cliente_id = c.id
LEFT JOIN pagamentos pg ON pg.pedido_id = p.id
WHERE c.id IN (1, 11)
GROUP BY c.id, c.nome, c.data_cadastro;
```

| cliente_id | nome | data_cadastro | qtd_pedidos | qtd_pagamentos |
|---|---|---|---|---|
| 1 | Ana Carolina Ferreira | 2026-01-10 09:15:00 | 1 | 1 |
| 11 | Ana C. Ferreira | 2026-01-10 09:17:32 | 0 | 0 |

**Achado:** todo o histórico da cliente está no registro original (`1`). O duplicado (`11`) está vazio, então pode ser removido sem perda de dados. Os `LEFT JOIN` são necessários aqui: com `JOIN` comum, o cliente `11`, que não tem pedidos, simplesmente sumiria do resultado.

### Passo 4: causa raiz — o que o banco garante hoje?

Lista das constraints e índices da tabela `clientes`:

```sql
SELECT conname, contype, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'clientes'::regclass;

SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'clientes';
```

| constraint | tipo | definição |
|---|---|---|
| clientes_pkey | p (primary key) | PRIMARY KEY (id) |

| índice | definição |
|---|---|
| clientes_pkey | CREATE UNIQUE INDEX clientes_pkey ON public.clientes USING btree (id) |

**Achado:** a única garantia de unicidade é a chave primária `id`, que é gerada automaticamente e por isso nunca vai se repetir. **Nada no banco impede dois clientes com o mesmo e-mail ou documento.**

## 4. Causa raiz

O defeito tem duas camadas:

1. **Banco (causa raiz):** a tabela `clientes` não tem constraint de unicidade em `email` nem em `documento`. É a ausência dessa regra que permitiu o segundo registro.
2. **Aplicação (gatilho):** o fluxo de cadastro não detectou que o e-mail já existia e aceitou um segundo envio do formulário. Ainda falta investigar nos logs por que a primeira tentativa pareceu ter falhado para a cliente.

Corrigir só a aplicação não basta. Qualquer outro caminho de escrita (importação, integração, script de suporte) continuaria podendo gerar duplicados. A regra precisa existir no banco.

## 5. Impacto

- **Cliente:** recebe comunicações em dobro (o sintoma relatado). Se ela tivesse comprado usando o segundo cadastro, o histórico de compras ficaria dividido entre dois registros.
- **Negócio:** a base de clientes aparece inflada em relatórios (11 registros para 10 pessoas) e pode distorcer métricas de aquisição.
- **Dados:** neste caso, nenhum pedido ou pagamento está no registro duplicado, então não há dado financeiro a reconciliar.

## 6. Correção proposta

> **Não executada.** Fica como recomendação para o time de desenvolvimento. O script foi testado numa cópia descartável do banco: depois dele, a detecção retorna 0 pares, o pedido da cliente continua vinculado ao registro `1`, e uma nova tentativa de cadastro com `' Ana.Ferreira@Example.com'` e `'111.222.333-44'` é bloqueada pelo banco.

### 6.1 Limpeza dos dados

```sql
BEGIN;

-- Reaponta qualquer pedido do registro duplicado para o original.
-- Hoje afeta 0 linhas (passo 3), mas o script não deve depender disso:
-- se um pedido for criado no registro 11 antes da correção, ele é preservado.
UPDATE pedidos SET cliente_id = 1 WHERE cliente_id = 11;

DELETE FROM clientes WHERE id = 11;

COMMIT;
```

Antes de rodar, vale guardar uma cópia do registro removido (por exemplo, numa tabela de auditoria), para o caso de alguém precisar consultar o que foi descartado.

### 6.2 Prevenção no banco

```sql
CREATE UNIQUE INDEX clientes_email_unico
    ON clientes (lower(trim(email)));

CREATE UNIQUE INDEX clientes_documento_unico
    ON clientes (regexp_replace(documento, '\D', '', 'g'));
```

São índices únicos sobre **expressões** (e-mail normalizado, documento só com dígitos), e não sobre a coluna crua. Um `UNIQUE (email)` simples deixaria passar `Ana.Ferreira@Example.com` como se fosse outro cliente.

Pontos de atenção para aplicar em produção:

- **Ordem:** a limpeza (6.1) precisa vir antes. Se ainda houver qualquer duplicado na base, o `CREATE UNIQUE INDEX` falha. Rode o [`deteccao.sql`](deteccao.sql) antes e confirme que ele retorna zero linhas.
- **Bloqueio:** num banco grande, o `CREATE UNIQUE INDEX` comum bloqueia escritas na tabela enquanto o índice é construído. Em produção, use `CREATE UNIQUE INDEX CONCURRENTLY`, que não bloqueia, mas não pode rodar dentro de uma transação.

### 6.3 Prevenção na aplicação

- Tratar o erro de unicidade que o banco passa a devolver com uma mensagem amigável ("Este e-mail já está cadastrado. Deseja recuperar o acesso?") em vez de um erro genérico.
- Desabilitar o botão de envio enquanto o cadastro está sendo processado, e investigar nos logs por que a primeira tentativa pareceu falhar (H3).

## 7. Como reproduzir

Com o banco no ar (`docker compose up`, ver o [README principal](../../README.md)):

```bash
docker compose exec -T postgres psql -U postgres -d defect_investigation < investigacoes/01-clientes-duplicados/exploracao.sql
```
