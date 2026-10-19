# Investigação 07 — Texto com codificação quebrada (mojibake)

| | |
|---|---|
| **Defeito** | Nomes e categorias de produtos gravados com caracteres trocados: "MÃ³dulo de RelatÃ³rios" em vez de "Módulo de Relatórios" |
| **Registros afetados** | 5 campos em 5 produtos: o nome dos produtos `6`, `7` e `8` e a categoria dos produtos `4` e `5` |
| **Causa raiz** | A sincronização do catálogo com o ERP recebe um arquivo em UTF-8, mas o importador o lê como Windows-1252 |
| **Severidade** | Média: não há perda financeira, mas o texto errado aparece para o cliente (e-mails, documentos) e quebra buscas e relatórios por categoria |
| **Status** | Diagnóstico concluído, com correção proposta e **não executada** |

Arquivos desta investigação:

- [`exploracao.sql`](exploracao.sql): as queries na ordem em que foram usadas, numeradas conforme os passos abaixo.
- [`deteccao.sql`](deteccao.sql): a query final de detecção, que procura texto quebrado em todas as colunas de texto do banco. É a mesma query que a CI executa.

---

## 1. Sintoma relatado

> Chamado de suporte: o cliente **Henrique Lopes Teixeira** enviou o print do e-mail de confirmação do pedido 7, em que o produto aparece como **"MÃ³dulo de RelatÃ³rios"**.

Esse tipo de texto tem nome: **mojibake**, ou texto lido com a codificação errada. A pergunta é onde a troca aconteceu: no envio do e-mail, na exibição ou no próprio dado.

## 2. Hipóteses iniciais

| # | Hipótese | Como confirmar ou descartar |
|---|---|---|
| H1 | O problema está só no e-mail (template ou programa de e-mail do cliente) | Ver como o nome está gravado no banco |
| H2 | O banco (ou a conexão com ele) usa a codificação errada | Se fosse isso, **todo** texto acentuado estaria quebrado, e os bytes gravados estariam certos |
| H3 | O texto foi gravado já quebrado, por um processo que leu UTF-8 como Windows-1252 | Desfazer essa troca específica e ver se o texto volta exatamente ao original |
| H4 | O problema não se limita a esse produto | Procurar o padrão em todas as colunas de texto do banco |

## 3. Investigação

### Passo 1: o catálogo como está gravado

```sql
SELECT id, nome, categoria FROM produtos ORDER BY id;
```

| id | nome | categoria |
|---|---|---|
| 1 | Plano Básico Mensal | Assinatura |
| 2 | Plano Profissional Mensal | Assinatura |
| 3 | Plano Enterprise Mensal | Assinatura |
| 4 | Pacote de Onboarding | **ServiÃ§o** |
| 5 | Consultoria Avulsa (hora) | **ServiÃ§o** |
| 6 | **MÃ³dulo de RelatÃ³rios** | Add-on |
| 7 | **MÃ³dulo de IntegraÃ§Ãµes** | Add-on |
| 8 | **Suporte PrioritÃ¡rio** | Add-on |
| 9 | Consutoria avulsa - hora | Serviço |

**Achado:** **H1 descartada.** O nome já está gravado errado no banco, e o e-mail só mostra o que recebeu. O detalhe mais importante é o produto `1`: **"Plano Básico Mensal" está correto**, com o "á" no lugar. Uma parte dos acentos está certa e outra está quebrada. O produto `9` também está correto, porque foi cadastrado à mão, fora da sincronização. Ele é um cadastro duplicado do produto `5`, assunto da [investigação 08](../08-duplicidade-aproximada/README.md).

### Passo 2: os bytes de um nome certo e de um quebrado

Em UTF-8, uma letra acentuada ocupa 2 bytes. Comparando os bytes gravados:

```sql
SELECT id, nome, length(nome) AS caracteres,
       octet_length(convert_to(nome, 'UTF8')) AS bytes_utf8,
       encode(convert_to(nome, 'UTF8'), 'hex') AS bytes_hex
FROM produtos
WHERE id IN (1, 6);
```

| id | nome | caracteres | bytes_utf8 | bytes_hex |
|---|---|---|---|---|
| 1 | Plano Básico Mensal | 19 | 20 | 506c616e6f2042**c3a1**7369636f204d656e73616c |
| 6 | MÃ³dulo de RelatÃ³rios | 22 | 26 | 4d**c383c2b3**64756c6f2064652052656c6174**c383c2b3**72696f73 |

- No produto `1`, o "á" é `c3 a1`: os 2 bytes corretos do "á" em UTF-8.
- No produto `6`, o "ó" (que seria `c3 b3`) virou `c3 83 c2 b3`, ou seja, **dois caracteres**: "Ã" (`c3 83`) e "³" (`c2 b3`). O nome passou de 20 para 22 caracteres.

**Achado:** **H2 descartada.** Se a codificação do banco ou da conexão estivesse errada, os bytes gravados estariam certos e só a exibição sairia trocada, e isso valeria para todos os acentos. Aqui, os bytes do produto `1` estão certos, e os do `6` contêm, de fato, os caracteres errados. **O defeito está no dado, não na exibição.**

### Passo 3: prova do diagnóstico

O padrão do passo 2 é a assinatura de um erro específico. Os 2 bytes UTF-8 de cada letra (`c3 b3`) foram lidos como Windows-1252, em que cada byte é um caractere (`c3` = "Ã", `b3` = "³"), e regravados em UTF-8. Se o diagnóstico estiver certo, a operação inversa (voltar o texto para os bytes Windows-1252 e reler como UTF-8) devolve o texto original **exatamente**. O teste só lê, sem alterar nada:

```sql
SELECT id, nome AS gravado,
       convert_from(convert_to(nome, 'WIN1252'), 'UTF8') AS relido_como_utf8
FROM produtos
WHERE nome ~ '[ÃÂ][¡-¿€‚ƒ„…†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ]';
```

| id | gravado | relido_como_utf8 |
|---|---|---|
| 6 | MÃ³dulo de RelatÃ³rios | Módulo de Relatórios |
| 7 | MÃ³dulo de IntegraÃ§Ãµes | Módulo de Integrações |
| 8 | Suporte PrioritÃ¡rio | Suporte Prioritário |

**Achado:** **H3 confirmada.** A inversão devolve o texto perfeito. Isso só acontece se a troca foi exatamente "UTF-8 lido como Windows-1252". Qualquer outra causa (outra codificação, digitação, corrupção) não seria desfeita por essa operação.

### Passo 4: é isolado?

A detecção procura o padrão em **todas** as colunas de texto do banco: um "Ã" ou "Â" seguido de um caractere que só aparece nesse tipo de erro. Um "Ã" legítimo do português, como em "SÃO PAULO" ou "CORAÇÃO", é seguido de letra e não é marcado. Isso foi testado com casos de borda, e "IRMÃ," e "CORAÇÃO" ficaram de fora, enquanto "JoÃ£o" e "Ã‰RICA" foram marcados. A query completa está em [`deteccao.sql`](deteccao.sql).

| tabela | registro_id | coluna | valor |
|---|---|---|---|
| produtos | 4 | categoria | ServiÃ§o |
| produtos | 5 | categoria | ServiÃ§o |
| produtos | 6 | nome | MÃ³dulo de RelatÃ³rios |
| produtos | 7 | nome | MÃ³dulo de IntegraÃ§Ãµes |
| produtos | 8 | nome | Suporte PrioritÃ¡rio |

**Achado:** **H4 descartada** fora do catálogo. Clientes e vendedores, inclusive nomes acentuados como "Fábio", "João" e "Patrícia", estão corretos. No catálogo, o padrão atinge só alguns produtos, e o "Plano Básico Mensal" continua certo. Isso é compatível com a sincronização semanal com o ERP, que regrava apenas os produtos alterados no ERP naquela semana. A lista de produtos enviados em cada sincronização, no log da integração, confirma quais foram atingidos.

### Passo 5: impacto — onde o texto quebrado aparece

```sql
SELECT pr.id AS produto_id, pr.nome AS produto, COUNT(i.id) AS qtd_itens,
       array_to_string(array_agg(DISTINCT i.pedido_id ORDER BY i.pedido_id), ', ') AS pedidos
FROM produtos pr
LEFT JOIN itens_pedido i ON i.produto_id = pr.id
WHERE pr.nome ~ '[ÃÂ][¡-¿€‚ƒ„…†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ]'
GROUP BY pr.id, pr.nome;
```

| produto_id | produto | qtd_itens | pedidos |
|---|---|---|---|
| 6 | MÃ³dulo de RelatÃ³rios | 3 | 1, 7, 12 |
| 7 | MÃ³dulo de IntegraÃ§Ãµes | 1 | 6 |
| 8 | Suporte PrioritÃ¡rio | 1 | 11 |

**Achado:** 5 pedidos (`1`, `6`, `7`, `11` e `12`) mostram nomes quebrados em qualquer documento gerado a partir do catálogo: e-mails, segunda via, nota. O pedido 7 é o do chamado.

## 4. Causa raiz

1. **Integração (causa raiz):** o importador da sincronização do catálogo lê o arquivo do ERP como Windows-1252, a codificação padrão do servidor em que ele roda, mas o arquivo é UTF-8. O importador não declara a codificação do arquivo e depende do padrão da máquina.
2. **Banco (por que passou):** para o banco, "MÃ³dulo" é um texto válido como qualquer outro. Nenhuma regra impede gravar a combinação típica de mojibake.

## 5. Impacto

- **Cliente:** nomes de produto quebrados em e-mails e documentos de 5 pedidos, o que passa uma imagem de sistema malfeito.
- **Busca:** quem procurar "Módulo" no catálogo não encontra os produtos `6` e `7`.
- **Relatórios:** a categoria "ServiÃ§o" é, para o banco, um texto **diferente** de "Serviço". Os dois produtos que vieram da sincronização estão em "ServiÃ§o", e o produto `9`, cadastrado à mão, está em "Serviço" correto. **A categoria já está dividida em duas**: qualquer relatório agrupado por categoria mostra "Serviço" e "ServiÃ§o" como se fossem categorias diferentes.
- **Reincidência:** como a causa está no importador, **a próxima sincronização quebra de novo** qualquer produto acentuado que for alterado no ERP.

## 6. Correção proposta

> **Não executada.** A correção foi testada numa cópia descartável do banco. Os 5 textos voltaram exatamente ao original (comparação texto a texto). A detecção passou a retornar 0 linhas, e uma nova gravação quebrada passou a ser bloqueada pela `CHECK`.

### 6.1 Corrigir o importador (antes de tudo)

Fazer o importador **declarar** que o arquivo é UTF-8, em vez de depender do padrão do servidor. Sem isso, qualquer correção nos dados dura só até a próxima sincronização.

### 6.2 Reverter o texto quebrado

```sql
BEGIN;

UPDATE produtos
SET nome = convert_from(convert_to(nome, 'WIN1252'), 'UTF8')
WHERE nome ~ '[ÃÂ][¡-¿€‚ƒ„…†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ]';

UPDATE produtos
SET categoria = convert_from(convert_to(categoria, 'WIN1252'), 'UTF8')
WHERE categoria ~ '[ÃÂ][¡-¿€‚ƒ„…†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ]';

COMMIT;
```

- **O filtro (`WHERE`) é obrigatório.** Aplicada num texto que já está certo, a mesma operação **quebra** o texto ou dá erro. Testado: no "Plano Básico Mensal", o PostgreSQL recusa com `invalid byte sequence for encoding "UTF8"`. Com o filtro, a correção só toca o texto quebrado.
- **Pode rodar mais de uma vez:** depois da primeira execução, nenhum texto casa mais com o filtro, então uma segunda execução não faz nada.
- **Limite:** algumas letras maiúsculas acentuadas, como "Á" e "Í", geram em UTF-8 um byte que **não existe** no Windows-1252. Dependendo do importador, esse byte vira "?" ou é descartado, e a informação se perde. Nesses casos, a reversão automática não funciona, e o texto precisa ser corrigido à mão a partir da origem (o ERP). Não é o caso de nenhum dos 5 campos daqui.

### 6.3 Impedir que volte

```sql
ALTER TABLE produtos ADD CONSTRAINT produtos_texto_sem_mojibake CHECK (
    nome !~ '[ÃÂ][¡-¿€‚ƒ„…†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ]'
    AND (categoria IS NULL OR categoria !~ '[ÃÂ][¡-¿€‚ƒ„…†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ]')
);
```

- Testado: depois da correção, uma nova gravação com o mesmo erro é recusada pelo banco. A sincronização passa a **falhar com erro**, em vez de gravar texto quebrado em silêncio, e o problema aparece no primeiro produto, e não no chamado de um cliente.
- **Ordem:** a `CHECK` só pode ser criada depois da reversão (6.2).
- **Monitoramento:** rodar o [`deteccao.sql`](deteccao.sql) depois de cada sincronização. Ele cobre também clientes e vendedores, que podem receber o mesmo erro por outra integração.

## 7. Como reproduzir

Com o banco no ar (`docker compose up -d --wait`, ver o [README principal](../../README.md)):

```bash
docker compose exec -T postgres psql -U postgres -d defect_investigation < investigacoes/07-codificacao-quebrada/exploracao.sql
```
