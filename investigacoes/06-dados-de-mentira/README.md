# Investigação 06 — Valores de mentira em campos obrigatórios

| | |
|---|---|
| **Defeito** | Clientes cadastrados com e-mail e CPF que não são dados de verdade, ou com o CPF digitado errado |
| **Registros afetados** | 3 clientes: `13` e `14` (e-mail `naotem@naotem.com` e CPFs de mentira) e `15` (CPF com dois dígitos trocados) |
| **Causa raiz** | O formulário de televendas exige e-mail e CPF, e o banco só garante que o campo não está vazio (`NOT NULL`), sem validar o conteúdo nem oferecer um jeito honesto de dizer "não informado" |
| **Severidade** | Média: cadastros barrados na análise de crédito, comunicação que não chega ao cliente e um falso positivo na detecção de duplicados |
| **Status** | Diagnóstico concluído, com correção proposta e **não executada** |

Arquivos desta investigação:

- [`exploracao.sql`](exploracao.sql): as queries na ordem em que foram usadas, numeradas conforme os passos abaixo.
- [`deteccao.sql`](deteccao.sql): a query final de detecção, que lista os clientes com valor de mentira ou inválido e o motivo de cada um. É a mesma query que a CI executa.

---

## 1. Sintoma relatado

> Chamado da área de crédito: a integração que consulta o CPF de cada cliente novo no birô de crédito **rejeitou 3 cadastros de fevereiro**. Os três foram feitos pela equipe de televendas.

## 2. Hipóteses iniciais

| # | Hipótese | Como confirmar ou descartar |
|---|---|---|
| H1 | Falha técnica na integração de crédito, sem problema nos dados | Comparar os cadastros rejeitados com os aceitos do mesmo período |
| H2 | CPF digitado errado | Calcular o dígito verificador de cada CPF |
| H3 | Dados de preenchimento: o atendente não tinha a informação e digitou qualquer coisa para salvar | Procurar valores repetidos entre clientes diferentes e padrões típicos de "valor de mentira" |
| H4 | O problema não se limita aos 3 cadastros | Rodar a verificação em toda a base |

## 3. Investigação

### Passo 1: os cadastros de fevereiro

```sql
SELECT id, nome, email, documento, telefone, data_cadastro
FROM clientes
WHERE data_cadastro >= '2026-02-01'
ORDER BY id;
```

| id | nome | email | documento | telefone | data_cadastro |
|---|---|---|---|---|---|
| 9 | Isabela Rocha Barbosa | isabela.barbosa@example.com | 99900011112 | 51900001111 | 2026-02-02 12:30:00 |
| 10 | João Pedro Azevedo | joao.azevedo@example.com | 00011122285 | 51999990000 | 2026-02-05 08:40:00 |
| **13** | **Roberto Lima Santos** | **naotem@naotem.com** | **00000000000** | 11987654321 | 2026-02-12 10:30:00 |
| **14** | **Sandra Melo Prado** | **naotem@naotem.com** | **12345678909** | 21976543210 | 2026-02-12 14:05:00 |
| **15** | **Paulo Henrique Dias** | paulo.dias@example.com | **14725836928** | 31965432109 | 2026-02-13 09:40:00 |

**Achado:** **H1 descartada.** Os dois cadastros aceitos (`9` e `10`) têm e-mail e CPF com cara de dado real. Os três rejeitados se destacam a olho nu: um e-mail que diz "não tem", um CPF todo de zeros e o famoso `123.456.789-09`. O CPF do Paulo parece real, mas foi rejeitado também. A integração está funcionando, e o problema está nos dados.

### Passo 2: valores repetidos entre clientes diferentes

Um dado de verdade identifica uma pessoa. Se o mesmo valor aparece em clientes diferentes, ou é a mesma pessoa duplicada, ou não é dado de verdade:

```sql
SELECT 'email' AS campo, lower(trim(email)) AS valor, COUNT(*) AS qtd_clientes,
       string_agg(id::text, ', ' ORDER BY id) AS clientes
FROM clientes
GROUP BY lower(trim(email))
HAVING COUNT(*) > 1
UNION ALL
SELECT 'documento', regexp_replace(documento, '\D', '', 'g'), COUNT(*),
       string_agg(id::text, ', ' ORDER BY id)
FROM clientes
GROUP BY regexp_replace(documento, '\D', '', 'g')
HAVING COUNT(*) > 1;
```

| campo | valor | qtd_clientes | clientes |
|---|---|---|---|
| documento | 11122233396 | 2 | 1, 11 |
| email | ana.ferreira@example.com | 2 | 1, 11 |
| email | naotem@naotem.com | 2 | 13, 14 |

**Achado:** são dois casos de natureza diferente.

- **Clientes `1` e `11`:** e-mail **e** CPF iguais. É a mesma pessoa cadastrada duas vezes, o defeito da [investigação 01](../01-clientes-duplicados/README.md).
- **Clientes `13` e `14`:** e-mail igual, mas **nomes, CPFs e telefones diferentes**. São duas pessoas, e o e-mail é um valor de preenchimento. **H3 confirmada** para esses dois.

Esse segundo caso tem um efeito colateral. A primeira versão da detecção de duplicados da investigação 01 comparava e-mails crus e marcava Roberto e Sandra como a mesma pessoa, um **falso positivo**. A detecção da 01 foi ajustada para que valores de mentira não formem par, usando as mesmas listas desta investigação.

### Passo 3: o dígito verificador de cada CPF

Os dois últimos dígitos de um CPF são calculados a partir dos nove primeiros: cada dígito é multiplicado por um peso, de 10 a 2 para o primeiro verificador e de 11 a 2 para o segundo, e o resto da divisão da soma por 11 define o verificador (resto menor que 2 vira 0; senão, 11 menos o resto). Um erro de digitação quase sempre quebra essa conta. O cálculo foi feito em SQL, com `generate_series` percorrendo os nove dígitos:

```sql
SELECT SUM(substr(cpf, i, 1)::int * (11 - i)) AS soma
FROM generate_series(1, 9) AS i;   -- 1º dígito verificador; o 2º usa (12 - i) e soma o 1º com peso 2
```

A query completa está em [`exploracao.sql`](exploracao.sql). Resultado para os 14 clientes:

| id | nome | cpf | dv_informado | dv_calculado | dv_confere |
|---|---|---|---|---|---|
| 1 | Ana Carolina Ferreira | 11122233396 | 96 | 96 | true |
| 2 | Bruno Costa Lima | 22233344405 | 05 | 05 | true |
| 3 | Carla Mendes Souza | 33344455508 | 08 | 08 | true |
| 4 | Diego Alves Pereira | 44455566619 | 19 | 19 | true |
| 5 | Elisa Martins Rocha | 55566677720 | 20 | 20 | true |
| 6 | Fábio Nunes Castro | 66677788830 | 30 | 30 | true |
| 7 | Gabriela Dias Ramos | 77788899941 | 41 | 41 | true |
| 8 | Henrique Lopes Teixeira | 88899900078 | 78 | 78 | true |
| 9 | Isabela Rocha Barbosa | 99900011112 | 12 | 12 | true |
| 10 | João Pedro Azevedo | 00011122285 | 85 | 85 | true |
| 11 | Ana C. Ferreira | 11122233396 | 96 | 96 | true |
| **13** | **Roberto Lima Santos** | **00000000000** | **00** | **00** | **true** |
| **14** | **Sandra Melo Prado** | **12345678909** | **09** | **09** | **true** |
| **15** | **Paulo Henrique Dias** | **14725836928** | **28** | **82** | **false** |

**Achados:**

- **H2 confirmada para o Paulo (`15`).** O verificador informado é `28` e o calculado é `82`: os dois últimos dígitos foram **trocados** na digitação, o erro mais comum ao copiar um número. O CPF certo seria `147.258.369-82`.
- **O dígito verificador sozinho não pega valor de mentira.** `000.000.000-00` e `123.456.789-09` **passam** no cálculo. Todo CPF com os 11 dígitos iguais passa, por uma propriedade da própria conta, e `123.456.789-09` é justamente um exemplo famoso por ser válido. Por isso a detecção precisa de duas regras a mais: dígitos todos iguais e sequências conhecidas.

### Passo 4: a detecção final — é isolado?

A query de [`deteccao.sql`](deteccao.sql) junta todas as regras e lista, para cada cliente, os problemas encontrados:

| Regra | O que pega |
|---|---|
| e-mail de mentira | `naotem@...`, `teste@...`, `...@sememail.com` e afins |
| e-mail com formato inválido | sem `@`, sem domínio, com espaço |
| CPF com todos os dígitos iguais | `000.000.000-00`, `111.111.111-11`... |
| CPF de sequência conhecida | `123.456.789-09` e afins |
| CPF com tamanho inválido | diferente de 11 dígitos |
| CPF com dígito verificador errado | erro de digitação |

| cliente_id | nome | email | documento | problemas |
|---|---|---|---|---|
| 13 | Roberto Lima Santos | naotem@naotem.com | 00000000000 | e-mail de mentira; CPF com todos os dígitos iguais |
| 14 | Sandra Melo Prado | naotem@naotem.com | 12345678909 | e-mail de mentira; CPF de sequência conhecida |
| 15 | Paulo Henrique Dias | paulo.dias@example.com | 14725836928 | CPF com dígito verificador errado |

**Achado:** **H4 descartada.** São exatamente os 3 cadastros do chamado. Os outros 11 clientes passam em todas as regras.

As listas de "valores de mentira" são, por natureza, incompletas: alguém sempre inventa um novo (`xxx@xxx.com`, `999.999.999-99`). As regras de formato e de dígito verificador não dependem de lista, e as listas cobrem os casos que essas regras não pegam.

### Passo 5: causa raiz — o que o banco exige hoje?

```sql
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'clientes' AND column_name IN ('email', 'documento');

SELECT conname, contype, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'clientes'::regclass;
```

| column_name | data_type | is_nullable |
|---|---|---|
| documento | character varying | NO |
| email | character varying | NO |

| constraint | tipo | definição |
|---|---|---|
| clientes_pkey | p | PRIMARY KEY (id) |

**Achado:** as duas colunas são `NOT NULL`, e não existe nenhuma `CHECK`. O banco exige **que algo seja digitado**, mas não **que seja válido**. Para quem atende um cliente que não sabe ou não quer informar o e-mail, a regra deixa só duas saídas: perder a venda ou digitar qualquer coisa.

## 4. Causa raiz

1. **Processo e aplicação (causa raiz):** o formulário de televendas trata e-mail e CPF como obrigatórios e não oferece uma opção "não informado". Diante de um cliente sem a informação, o atendente faz o que o sistema permite: digita um valor de preenchimento.
2. **Banco (por que passou):** `NOT NULL` garante presença, não validade. Nenhuma regra confere formato de e-mail, dígito verificador de CPF ou valores de preenchimento conhecidos. E, ao exigir o campo, o banco empurra o atendente justamente para o valor de mentira.

O CPF do Paulo é um caso à parte do mesmo problema: o número foi informado, mas digitado errado, e nada no caminho conferiu o dígito verificador.

## 5. Impacto

- **Crédito e vendas:** os 3 cadastros foram barrados na análise de crédito, e as vendas para esses clientes ficam travadas até a correção.
- **Comunicação:** os e-mails para Roberto e Sandra não chegam a ninguém. Se um dia `naotem.com` virar um domínio real, chegam a um desconhecido, com dados de dois clientes.
- **Outras verificações:** o e-mail compartilhado criou um falso positivo na detecção de duplicados (investigação 01) e **impede** a criação do índice único de e-mail que a própria investigação 01 propõe. Um defeito contamina a verificação e a correção de outro.
- **Relatórios:** contagens de "clientes com e-mail" ou "com CPF" ficam infladas, porque contam valores que não são dado.

## 6. Correção proposta

> **Não executada.** A correção foi testada numa cópia descartável do banco, em sequência com a da investigação 01. **Sem** esta correção, o índice único de e-mail da 01 falha. **Com** ela, os índices da 01 são criados, a detecção desta investigação retorna 0 linhas, um cadastro sem e-mail e sem CPF (`NULL`) é aceito, e os novos cadastros com `naotem@naotem.com`, `000.000.000-00`, CPF com dígito trocado ou e-mail sem `@` são bloqueados pelo banco.

### 6.1 Permitir "não informado" de forma honesta

```sql
ALTER TABLE clientes ALTER COLUMN email DROP NOT NULL;
ALTER TABLE clientes ALTER COLUMN documento DROP NOT NULL;
```

Parece um passo para trás, mas é o oposto. `NULL` diz a verdade ("não sabemos"), e um valor de mentira finge que sabemos. Relatórios passam a contar só dado real, e o índice único aceita vários `NULL`.

### 6.2 Limpar os valores de mentira

```sql
UPDATE clientes SET email = NULL     WHERE id IN (13, 14);   -- naotem@naotem.com
UPDATE clientes SET documento = NULL WHERE id IN (13, 14);   -- 000.000.000-00 e 123.456.789-09
UPDATE clientes SET documento = NULL WHERE id = 15;          -- CPF digitado errado
```

- **Roberto e Sandra:** os dados reais só podem vir dos próprios clientes. Até lá, `NULL`.
- **Paulo:** é muito provável que o certo seja `147.258.369-82` (os dois últimos dígitos trocados), mas isso continua sendo um palpite. Um CPF corrigido "por dedução" que estiver errado é pior que um campo vazio, porque parece verdade. O certo é confirmar com o cliente. Até lá, `NULL`, e o cadastro entra numa fila de contato.

### 6.3 Validar o conteúdo no banco

```sql
CREATE FUNCTION cpf_valido(doc text) RETURNS boolean
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    cpf text := regexp_replace(doc, '\D', '', 'g');
    soma int;
    d1 int;
    d2 int;
BEGIN
    IF cpf !~ '^\d{11}$' OR cpf ~ '^(\d)\1{10}$'
       OR cpf IN ('12345678909', '01234567890', '98765432100') THEN
        RETURN false;
    END IF;
    soma := 0;
    FOR i IN 1..9 LOOP
        soma := soma + substr(cpf, i, 1)::int * (11 - i);
    END LOOP;
    d1 := CASE WHEN soma % 11 < 2 THEN 0 ELSE 11 - soma % 11 END;
    soma := 0;
    FOR i IN 1..9 LOOP
        soma := soma + substr(cpf, i, 1)::int * (12 - i);
    END LOOP;
    soma := soma + d1 * 2;
    d2 := CASE WHEN soma % 11 < 2 THEN 0 ELSE 11 - soma % 11 END;
    RETURN substr(cpf, 10, 1)::int = d1 AND substr(cpf, 11, 1)::int = d2;
END;
$$;

CREATE FUNCTION email_valido(email text) RETURNS boolean
LANGUAGE sql IMMUTABLE AS $$
    SELECT lower(trim(email)) ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
       AND split_part(lower(trim(email)), '@', 1) NOT IN ('naotem', 'nao', 'sememail', 'semmail', 'nenhum', 'teste')
       AND split_part(lower(trim(email)), '@', 2) NOT IN ('naotem.com', 'sememail.com', 'teste.com', 'email.com');
$$;

ALTER TABLE clientes ADD CONSTRAINT clientes_documento_valido
    CHECK (documento IS NULL OR cpf_valido(documento));

ALTER TABLE clientes ADD CONSTRAINT clientes_email_valido
    CHECK (email IS NULL OR email_valido(email));
```

- **Ordem:** as `CHECK` só podem ser criadas depois da limpeza (6.2). Com os valores atuais na base, a criação falharia.
- **Por que funções:** a regra do CPF não cabe numa expressão simples. Com as funções, a mesma lógica fica num lugar só, e as `CHECK` ficam legíveis. Elas precisam ser `IMMUTABLE` (mesmo resultado para a mesma entrada), uma exigência do PostgreSQL para uso em `CHECK`.
- **Limite:** a lista de e-mails de mentira dentro do `email_valido` bloqueia os valores conhecidos, mas não os que alguém inventar amanhã. É por isso que a parte mais importante da correção é a 6.4.

### 6.4 Corrigir o formulário

- Oferecer **"Cliente não informou"** para e-mail e CPF, gravando `NULL`. Se a saída honesta existir, o atendente não precisa inventar.
- Validar o CPF (dígito verificador) e o formato do e-mail **na tela**, no momento da digitação. O erro do Paulo seria pego antes de salvar.
- **Monitoramento:** rodar o [`deteccao.sql`](deteccao.sql) periodicamente e revisar os valores novos que aparecerem para atualizar as listas.

### 6.5 Ordem em relação à investigação 01

A correção da [investigação 01](../01-clientes-duplicados/README.md) cria índices únicos em e-mail e documento. Esses índices só podem ser criados **depois** desta correção: enquanto Roberto e Sandra compartilharem `naotem@naotem.com`, o índice único de e-mail falha.

## 7. Como reproduzir

Com o banco no ar (`docker compose up -d --wait`, ver o [README principal](../../README.md)):

```bash
docker compose exec -T postgres psql -U postgres -d defect_investigation < investigacoes/06-dados-de-mentira/exploracao.sql
```
