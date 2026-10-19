-- Detecção: clientes com valor de mentira ou inválido num campo
-- obrigatório (e-mail ou CPF).
--
-- NOT NULL só impede o campo vazio. Esta query procura o que passa por
-- ele sem ser dado de verdade:
--   - e-mail de mentira: endereço "de preenchimento" (naotem@..., teste@...);
--   - e-mail com formato inválido;
--   - CPF com todos os dígitos iguais (000.000.000-00, 111.111.111-11...);
--   - CPF de sequência conhecida (123.456.789-09);
--   - CPF com tamanho diferente de 11 dígitos;
--   - CPF com dígito verificador errado (erro de digitação).
--
-- Os dois primeiros tipos de CPF PASSAM no cálculo do dígito verificador,
-- por isso precisam de regra própria.
--
-- Cada linha é um cliente, com a lista de problemas encontrados.
-- Resultado esperado: zero linhas.

WITH emails_de_mentira (parte) AS (
    VALUES ('naotem'), ('nao'), ('sememail'), ('semmail'), ('nenhum'), ('teste'),
           ('naotem.com'), ('sememail.com'), ('teste.com'), ('email.com')
),
cpfs_de_sequencia (cpf) AS (
    VALUES ('12345678909'), ('01234567890'), ('98765432100')
),
clientes_normalizados AS (
    SELECT
        id,
        nome,
        email,
        documento,
        lower(trim(email)) AS email_norm,
        regexp_replace(documento, '\D', '', 'g') AS cpf
    FROM clientes
),
dv AS (
    -- Dígito verificador do CPF: os 9 primeiros dígitos pesam de 10 a 2
    -- (1º dígito) e de 11 a 3 mais o 1º dígito com peso 2 (2º dígito).
    -- Resto da divisão por 11 menor que 2 vira 0; senão, 11 menos o resto.
    SELECT
        c.id,
        d1.digito AS d1,
        CASE WHEN (s2.soma + d1.digito * 2) % 11 < 2 THEN 0 ELSE 11 - (s2.soma + d1.digito * 2) % 11 END AS d2
    FROM clientes_normalizados c
    CROSS JOIN LATERAL (
        SELECT SUM(substr(c.cpf, i, 1)::int * (11 - i)) AS soma
        FROM generate_series(1, 9) AS i
    ) s1
    CROSS JOIN LATERAL (
        SELECT CASE WHEN s1.soma % 11 < 2 THEN 0 ELSE 11 - s1.soma % 11 END AS digito
    ) d1
    CROSS JOIN LATERAL (
        SELECT SUM(substr(c.cpf, i, 1)::int * (12 - i)) AS soma
        FROM generate_series(1, 9) AS i
    ) s2
    WHERE c.cpf ~ '^\d{11}$'
),
problemas AS (
    SELECT
        c.id AS cliente_id,
        c.nome,
        c.email,
        c.documento,
        array_remove(ARRAY[
            CASE WHEN split_part(c.email_norm, '@', 1) IN (SELECT parte FROM emails_de_mentira)
                   OR split_part(c.email_norm, '@', 2) IN (SELECT parte FROM emails_de_mentira)
                 THEN 'e-mail de mentira' END,
            CASE WHEN c.email_norm !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
                 THEN 'e-mail com formato inválido' END,
            CASE WHEN c.cpf ~ '^(\d)\1{10}$'
                 THEN 'CPF com todos os dígitos iguais' END,
            CASE WHEN c.cpf IN (SELECT cpf FROM cpfs_de_sequencia)
                 THEN 'CPF de sequência conhecida' END,
            CASE WHEN c.cpf !~ '^\d{11}$'
                 THEN 'CPF com tamanho inválido' END,
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
