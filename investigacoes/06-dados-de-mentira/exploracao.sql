-- Investigação 06 — Valores de mentira em campos obrigatórios
-- Queries na ordem em que foram usadas na investigação. A numeração bate
-- com os passos do README.md desta pasta.

-- Passo 1: os cadastros de fevereiro, quando a análise de crédito
-- começou a rejeitar clientes novos.
SELECT id, nome, email, documento, telefone, data_cadastro
FROM clientes
WHERE data_cadastro >= '2026-02-01'
ORDER BY id;

-- Passo 2: e-mails e documentos que se repetem entre clientes.
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
HAVING COUNT(*) > 1
ORDER BY campo, valor;

-- Passo 3: o dígito verificador de cada CPF — o calculado a partir dos
-- 9 primeiros dígitos e o que foi informado.
WITH c AS (
    SELECT id, nome, regexp_replace(documento, '\D', '', 'g') AS cpf
    FROM clientes
),
calculo AS (
    SELECT
        c.id,
        c.nome,
        c.cpf,
        d1.digito AS d1,
        CASE WHEN (s2.soma + d1.digito * 2) % 11 < 2 THEN 0 ELSE 11 - (s2.soma + d1.digito * 2) % 11 END AS d2
    FROM c
    CROSS JOIN LATERAL (
        SELECT SUM(substr(c.cpf, i, 1)::int * (11 - i)) AS soma FROM generate_series(1, 9) AS i
    ) s1
    CROSS JOIN LATERAL (
        SELECT CASE WHEN s1.soma % 11 < 2 THEN 0 ELSE 11 - s1.soma % 11 END AS digito
    ) d1
    CROSS JOIN LATERAL (
        SELECT SUM(substr(c.cpf, i, 1)::int * (12 - i)) AS soma FROM generate_series(1, 9) AS i
    ) s2
    WHERE c.cpf ~ '^\d{11}$'
)
SELECT
    id,
    nome,
    cpf,
    substr(cpf, 10, 2) AS dv_informado,
    d1::text || d2::text AS dv_calculado,
    substr(cpf, 10, 2) = d1::text || d2::text AS dv_confere
FROM calculo
ORDER BY id;

-- Passo 4: detecção final (mesma query de deteccao.sql).
WITH emails_de_mentira (parte) AS (
    VALUES ('naotem'), ('nao'), ('sememail'), ('semmail'), ('nenhum'), ('teste'),
           ('naotem.com'), ('sememail.com'), ('teste.com'), ('email.com')
),
cpfs_de_sequencia (cpf) AS (
    VALUES ('12345678909'), ('01234567890'), ('98765432100')
),
clientes_normalizados AS (
    SELECT id, nome, email, documento,
           lower(trim(email)) AS email_norm,
           regexp_replace(documento, '\D', '', 'g') AS cpf
    FROM clientes
),
dv AS (
    SELECT
        c.id,
        d1.digito AS d1,
        CASE WHEN (s2.soma + d1.digito * 2) % 11 < 2 THEN 0 ELSE 11 - (s2.soma + d1.digito * 2) % 11 END AS d2
    FROM clientes_normalizados c
    CROSS JOIN LATERAL (
        SELECT SUM(substr(c.cpf, i, 1)::int * (11 - i)) AS soma FROM generate_series(1, 9) AS i
    ) s1
    CROSS JOIN LATERAL (
        SELECT CASE WHEN s1.soma % 11 < 2 THEN 0 ELSE 11 - s1.soma % 11 END AS digito
    ) d1
    CROSS JOIN LATERAL (
        SELECT SUM(substr(c.cpf, i, 1)::int * (12 - i)) AS soma FROM generate_series(1, 9) AS i
    ) s2
    WHERE c.cpf ~ '^\d{11}$'
),
problemas AS (
    SELECT
        c.id AS cliente_id, c.nome, c.email, c.documento,
        array_remove(ARRAY[
            CASE WHEN split_part(c.email_norm, '@', 1) IN (SELECT parte FROM emails_de_mentira)
                   OR split_part(c.email_norm, '@', 2) IN (SELECT parte FROM emails_de_mentira)
                 THEN 'e-mail de mentira' END,
            CASE WHEN c.email_norm !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN 'e-mail com formato inválido' END,
            CASE WHEN c.cpf ~ '^(\d)\1{10}$' THEN 'CPF com todos os dígitos iguais' END,
            CASE WHEN c.cpf IN (SELECT cpf FROM cpfs_de_sequencia) THEN 'CPF de sequência conhecida' END,
            CASE WHEN c.cpf !~ '^\d{11}$' THEN 'CPF com tamanho inválido' END,
            CASE WHEN dv.id IS NOT NULL
                  AND (substr(c.cpf, 10, 1)::int <> dv.d1 OR substr(c.cpf, 11, 1)::int <> dv.d2)
                 THEN 'CPF com dígito verificador errado' END
        ], NULL) AS lista
    FROM clientes_normalizados c
    LEFT JOIN dv ON dv.id = c.id
)
SELECT cliente_id, nome, email, documento, array_to_string(lista, '; ') AS problemas
FROM problemas
WHERE cardinality(lista) > 0
ORDER BY cliente_id;

-- Passo 5: causa raiz — o que o banco exige hoje de e-mail e documento?
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'clientes' AND column_name IN ('email', 'documento')
ORDER BY column_name;

SELECT conname, contype, pg_get_constraintdef(oid) AS definicao
FROM pg_constraint
WHERE conrelid = 'clientes'::regclass
ORDER BY conname;
