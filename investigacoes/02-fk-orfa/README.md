# Investigação 02 — Foreign key órfã

| | |
|---|---|
| **Defeito** | Um pedido aponta para um cliente que não existe mais |
| **Registros afetados** | 1 pedido: `10` (R$ 99,90), com `cliente_id = 12` |
| **Causa raiz** | O cliente foi removido direto no banco num período em que a foreign key não existia. Depois, a FK foi recriada como `NOT VALID`, o que escondeu o problema |
| **Severidade** | Alta: relatórios financeiros divergem, e o banco declara uma regra de integridade que os dados não cumprem |
| **Status** | Diagnóstico concluído, com correção proposta e **não executada** |

Arquivos desta investigação:

- [`exploracao.sql`](exploracao.sql): as queries na ordem em que foram usadas, numeradas conforme os passos abaixo.
- [`deteccao.sql`](deteccao.sql): a query final de detecção, que lista registros órfãos em **todas** as foreign keys do schema. É a mesma query que a CI executa.

---

## 1. Sintoma relatado

> Chamado do financeiro: o relatório "Vendas por cliente" fecha em **R$ 2.069,00**, mas o total de pedidos registrados no sistema é **R$ 2.168,90**. A diferença é de **R$ 99,90**.

Dois relatórios que deveriam somar a mesma coisa e não batem. Antes de olhar dado, a primeira pergunta é: o que um relatório faz que o outro não faz?

## 2. Hipóteses iniciais

| # | Hipótese | Como confirmar ou descartar |
|---|---|---|
| H1 | Os relatórios usam filtros diferentes (período, status) | Comparar as duas somas sem nenhum filtro |
| H2 | O relatório por cliente descarta pedidos no `JOIN` com `clientes` | Procurar pedidos sem cliente correspondente |
| H3 | Se H2: o `cliente_id` nunca existiu (id gravado errado por bug ou integração) | Verificar se o id chegou a ser gerado pela sequence |
| H4 | Se H2: a foreign key não está protegendo os dados | Verificar o estado da constraint no catálogo do banco |

## 3. Investigação

### Passo 1: reproduzir a divergência

As duas somas sem nenhum filtro: direto na tabela `pedidos`, e com o mesmo `JOIN` com `clientes` que o relatório por cliente faz:

```sql
SELECT
    (SELECT COUNT(*) FROM pedidos) AS qtd_pedidos_tabela,
    (SELECT SUM(valor_total) FROM pedidos) AS total_tabela,
    (SELECT COUNT(*) FROM pedidos p JOIN clientes c ON c.id = p.cliente_id) AS qtd_pedidos_relatorio,
    (SELECT SUM(p.valor_total) FROM pedidos p JOIN clientes c ON c.id = p.cliente_id) AS total_relatorio;
```

| qtd_pedidos_tabela | total_tabela | qtd_pedidos_relatorio | total_relatorio |
|---|---|---|---|
| 13 | 2168.90 | 12 | 2069.00 |

**Achado:** **H1 descartada.** Sem nenhum filtro, a divergência continua: o `JOIN` sozinho faz **1 pedido** e **R$ 99,90** sumirem. Um `JOIN` comum (`INNER JOIN`) só devolve as linhas que encontram correspondência dos dois lados, então algum pedido não tem cliente.

### Passo 2: quais pedidos o `JOIN` descarta?

Trocando para `LEFT JOIN`, o pedido continua no resultado mesmo sem cliente, e o filtro `c.id IS NULL` deixa só os pedidos sem correspondência:

```sql
SELECT p.id, p.cliente_id, p.vendedor_id, p.data_pedido, p.status, p.valor_total
FROM pedidos p
LEFT JOIN clientes c ON c.id = p.cliente_id
WHERE c.id IS NULL;
```

| id | cliente_id | vendedor_id | data_pedido | status | valor_total |
|---|---|---|---|---|---|
| 10 | 12 | 1 | 2025-12-01 10:00:00 | confirmado | 99.90 |

**Achado:** **H2 confirmada.** O pedido `10` aponta para o cliente `12`, que não existe na tabela `clientes`. O valor bate exatamente com a diferença do chamado.

### Passo 3: o cliente 12 chegou a existir?

Os ids de `clientes` são gerados por uma sequence (`clientes_id_seq`), que só avança. Se o id 12 foi gerado e não está na tabela, o registro existiu e foi removido:

```sql
SELECT
    (SELECT last_value FROM clientes_id_seq) AS ultimo_id_gerado,
    (SELECT MAX(id) FROM clientes) AS maior_id_existente,
    (SELECT COUNT(*) FROM clientes) AS qtd_clientes;

SELECT s.id AS id_gerado_e_ausente
FROM generate_series(1, (SELECT last_value FROM clientes_id_seq)) AS s(id)
LEFT JOIN clientes c ON c.id = s.id
WHERE c.id IS NULL;
```

| ultimo_id_gerado | maior_id_existente | qtd_clientes |
|---|---|---|
| 15 | 15 | 14 |

| id_gerado_e_ausente |
|---|
| 12 |

**Achado:** **H3 descartada.** A sequence já gerou 15 ids, mas só existem 14 clientes: falta exatamente um. A segunda query mostra qual é: o id 12, o único gerado e ausente. Os ids 13 a 15 são clientes cadastrados depois, os três da [investigação 06](../06-dados-de-mentira/README.md). Sozinha, uma lacuna na sequence não prova uma remoção, porque um `INSERT` que sofreu rollback também consome um id. Mas aqui existe um pedido apontando justamente para esse id, o que só faz sentido se o cliente existiu de fato. **Conclusão: o cliente 12 foi cadastrado e depois removido.**

### Passo 4: como o banco permitiu?

O schema declara `pedidos.cliente_id REFERENCES clientes (id)`, então em teoria o banco deveria ter impedido essa remoção. Estado de todas as foreign keys no catálogo:

```sql
SELECT conrelid::regclass AS tabela, conname AS constraint_nome,
       convalidated AS validada, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE contype = 'f';
```

| tabela | constraint_nome | validada | definicao |
|---|---|---|---|
| itens_pedido | itens_pedido_pedido_id_fkey | true | FOREIGN KEY (pedido_id) REFERENCES pedidos(id) |
| itens_pedido | itens_pedido_produto_id_fkey | true | FOREIGN KEY (produto_id) REFERENCES produtos(id) |
| pagamentos | pagamentos_pedido_id_fkey | true | FOREIGN KEY (pedido_id) REFERENCES pedidos(id) |
| **pedidos** | **pedidos_cliente_id_fkey** | **false** | **FOREIGN KEY (cliente_id) REFERENCES clientes(id) NOT VALID** |
| pedidos | pedidos_vendedor_id_fkey | true | FOREIGN KEY (vendedor_id) REFERENCES vendedores(id) |

**Achado:** **H4 confirmada.** A FK `pedidos_cliente_id_fkey` é a única marcada como **`NOT VALID`**.

Uma FK `NOT VALID` funciona assim:

- **Daqui pra frente, ela vale:** novos `INSERT`/`UPDATE` em `pedidos` e novos `DELETE` em `clientes` são verificados.
- **Para trás, não:** os dados que já existiam quando a constraint foi criada **nunca foram verificados**.

Isso foi comprovado numa cópia descartável do banco: hoje, `DELETE FROM clientes WHERE id = 1` (um cliente com pedidos) **é bloqueado** pela FK. Ou seja, o cliente 12 não poderia ter sido removido com a constraint no lugar. A remoção aconteceu num período em que **a FK não existia**. Depois, ela foi (re)criada com `NOT VALID`, que é uma forma comum de adicionar uma constraint a uma tabela grande sem travá-la, mas que deixou o registro órfão passar sem aviso.

Na mesma cópia, tentar validar a constraint agora falha, apontando o problema:

```sql
ALTER TABLE pedidos VALIDATE CONSTRAINT pedidos_cliente_id_fkey;
-- ERROR: insert or update on table "pedidos" violates foreign key constraint "pedidos_cliente_id_fkey"
```

### Passo 5: é isolado?

Se uma FK chegou a ser removida e recriada, outras também podem ter sido. A detecção foi generalizada para **todas** as foreign keys do schema. A query completa está em [`deteccao.sql`](deteccao.sql): um `LEFT JOIN ... WHERE pai.id IS NULL` por FK, juntos com `UNION ALL`.

| tabela | registro_id | coluna | aponta_para |
|---|---|---|---|
| pedidos | 10 | cliente_id | 12 |

**Achado:** é o único registro órfão do banco. Isso confirma o que o passo 4 indicava: as outras quatro FKs estão validadas, portanto não podem ter órfãos.

### Passo 6: impacto — o que está vinculado ao pedido órfão?

```sql
SELECT p.id AS pedido_id, p.status, p.valor_total,
       (SELECT COUNT(*) FROM itens_pedido i WHERE i.pedido_id = p.id) AS qtd_itens,
       (SELECT COUNT(*) FROM pagamentos pg WHERE pg.pedido_id = p.id) AS qtd_pagamentos
FROM pedidos p
WHERE p.id = 10;
```

| pedido_id | status | valor_total | qtd_itens | qtd_pagamentos |
|---|---|---|---|---|
| 10 | confirmado | 99.90 | 0 | 0 |

**Achado secundário:** o pedido está `confirmado` com valor de R$ 99,90, mas **não tem nenhum item nem pagamento**. Pode ser um pedido incompleto, um registro de teste ou ter perdido os dados vinculados junto com o cliente. Isso não pode ser decidido só pelo banco, então entra como pergunta para o negócio na correção (seção 6).

## 4. Causa raiz

1. **Operação (causa raiz):** o cliente `12` foi removido diretamente no banco, fora da aplicação, num período em que a FK `pedidos_cliente_id_fkey` não existia. O pedido `10`, vinculado a ele, não foi tratado.
2. **Banco (por que ninguém percebeu):** a FK foi (re)criada com `NOT VALID` e nunca foi validada (`VALIDATE CONSTRAINT`). O schema "declara" a integridade, mas não a garante para os dados antigos, e isso cria uma falsa sensação de segurança.

O banco não tem trilha de auditoria. Por isso, não é possível saber **quem** removeu o cliente nem **quando**, além de que foi depois de 2025-12-01 (data do pedido).

## 5. Impacto

- **Financeiro:** qualquer relatório que faça `JOIN` com `clientes` subnotifica R$ 99,90, como no relatório do chamado. Relatórios de comissão por vendedor que passem por `clientes` também perdem esse pedido (vendedor `1`).
- **Dados:** não se sabe a quem pertence um pedido `confirmado`. Não dá para contatar o cliente, emitir nota ou cobrar.
- **Confiança no schema:** quem lê o DDL entende que `pedidos.cliente_id` sempre aponta para um cliente válido, e isso é falso.

## 6. Correção proposta

> **Não executada.** Fica como recomendação. O caminho B, seguido do `VALIDATE`, foi testado numa cópia descartável do banco: depois dele, a FK fica `validada = true`, a detecção retorna 0 órfãos e os dois totais do chamado passam a bater (R$ 2.168,90 nos dois).

### 6.1 Tratar o pedido órfão: decisão do negócio

| Caminho | Quando usar | Observação |
|---|---|---|
| **A. Restaurar o cliente 12** de backup ou log, com o mesmo id | **Recomendado**, se existir backup do período | Recupera o dado real |
| **B. Reconstituir um registro** de cliente com id 12, marcado como inativo | Se não houver backup | Preserva o pedido e o histórico financeiro sem inventar dados do cliente |
| **C. Remover o pedido 10** | Só se o negócio confirmar que é lixo (lembre: não tem itens nem pagamento) | Apaga um registro financeiro, **não recomendado** sem essa confirmação |

Exemplo do caminho B:

```sql
BEGIN;

INSERT INTO clientes (id, nome, email, documento, data_cadastro, status)
VALUES (12, 'Cliente removido (registro reconstituído)',
        'cliente-removido-12@invalido.local', 'REMOVIDO-12',
        '2025-11-01 10:00:00', 'inativo');

ALTER TABLE pedidos VALIDATE CONSTRAINT pedidos_cliente_id_fkey;

COMMIT;
```

O `INSERT` usa um id explícito, que normalmente conflitaria com a sequence. Aqui não há conflito: a sequence já está em 12 (passo 3), então o próximo cliente cadastrado receberá o id 13.

### 6.2 Validar a constraint

Em qualquer dos caminhos, o passo final é o mesmo:

```sql
ALTER TABLE pedidos VALIDATE CONSTRAINT pedidos_cliente_id_fkey;
```

A partir daí, a FK passa a garantir **todos** os dados, antigos e novos. O `VALIDATE CONSTRAINT` pode rodar em produção sem parar a aplicação, porque usa um lock mais leve do que a criação da constraint e não bloqueia leituras nem escritas comuns na tabela.

### 6.3 Prevenção

- **Processo:** remover ou recriar constraints e fazer `DELETE` direto em produção só via mudança revisada, nunca em acesso de suporte.
- **Soft delete:** para clientes, preferir `status = 'inativo'` a `DELETE`. O histórico continua íntegro e a FK nunca precisa ser contornada.
- **Toda FK criada com `NOT VALID` precisa de um `VALIDATE CONSTRAINT` planejado logo em seguida.** Vale incluir no checklist de migrations.
- **Auditoria:** registrar quem remove o quê (trigger de auditoria ou extensão como `pgaudit`). Nesta investigação, essa foi a única pergunta que o banco não conseguiu responder.
- **Monitoramento:** rodar o [`deteccao.sql`](deteccao.sql) periodicamente. Ele cobre todas as FKs, inclusive as que forem desabilitadas no futuro.

## 7. Como reproduzir

Com o banco no ar (`docker compose up`, ver o [README principal](../../README.md)):

```bash
docker compose exec -T postgres psql -U postgres -d defect_investigation < investigacoes/02-fk-orfa/exploracao.sql
```
