-- Detecção: pares de clientes que representam a mesma pessoa.
--
-- Cada linha é um par (id_original, id_duplicado). O e-mail é comparado
-- sem diferenciar maiúsculas/minúsculas e sem espaços nas pontas, e o
-- documento só pelos dígitos, para pegar também cadastros digitados com
-- formatação diferente (ex.: "111.222.333-96" e "11122233396").
--
-- Valores de mentira (ex.: "naotem@naotem.com", "000.000.000-00") não
-- identificam ninguém: dois clientes diferentes podem ter o mesmo. Por
-- isso, eles viram NULL antes da comparação e nunca formam um par. As
-- listas são as mesmas da investigação 06, que trata desses valores.
--
-- Resultado esperado: zero linhas. Qualquer linha é um defeito.

WITH emails_de_mentira (parte) AS (
    VALUES ('naotem'), ('nao'), ('sememail'), ('semmail'), ('nenhum'), ('teste'),
           ('naotem.com'), ('sememail.com'), ('teste.com'), ('email.com')
),
cpfs_de_sequencia (cpf) AS (
    VALUES ('12345678909'), ('01234567890'), ('98765432100')
),
identificadores AS (
    SELECT
        id,
        nome,
        data_cadastro,
        CASE
            WHEN split_part(lower(trim(email)), '@', 1) IN (SELECT parte FROM emails_de_mentira)
              OR split_part(lower(trim(email)), '@', 2) IN (SELECT parte FROM emails_de_mentira)
            THEN NULL
            ELSE lower(trim(email))
        END AS email,
        CASE
            WHEN regexp_replace(documento, '\D', '', 'g') ~ '^(\d)\1{10}$'
              OR regexp_replace(documento, '\D', '', 'g') IN (SELECT cpf FROM cpfs_de_sequencia)
            THEN NULL
            ELSE regexp_replace(documento, '\D', '', 'g')
        END AS documento
    FROM clientes
)
SELECT
    a.id AS id_original,
    b.id AS id_duplicado,
    a.nome AS nome_original,
    b.nome AS nome_duplicado,
    a.email = b.email AS mesmo_email,
    a.documento = b.documento AS mesmo_documento,
    b.data_cadastro - a.data_cadastro AS intervalo_entre_cadastros
FROM identificadores a
JOIN identificadores b
    ON a.id < b.id
   AND (a.email = b.email OR a.documento = b.documento)
ORDER BY a.id, b.id;
