-- Detecção: pares de clientes que representam a mesma pessoa.
--
-- Cada linha é um par (id_original, id_duplicado). O e-mail é comparado
-- sem diferenciar maiúsculas/minúsculas e sem espaços nas pontas, e o
-- documento só pelos dígitos, para pegar também cadastros digitados com
-- formatação diferente (ex.: "111.222.333-44" e "11122233344").
--
-- Resultado esperado: zero linhas. Qualquer linha é um defeito.

SELECT
    a.id AS id_original,
    b.id AS id_duplicado,
    a.nome AS nome_original,
    b.nome AS nome_duplicado,
    lower(trim(a.email)) = lower(trim(b.email)) AS mesmo_email,
    regexp_replace(a.documento, '\D', '', 'g') = regexp_replace(b.documento, '\D', '', 'g') AS mesmo_documento,
    b.data_cadastro - a.data_cadastro AS intervalo_entre_cadastros
FROM clientes a
JOIN clientes b
    ON a.id < b.id
   AND (
        lower(trim(a.email)) = lower(trim(b.email))
        OR regexp_replace(a.documento, '\D', '', 'g') = regexp_replace(b.documento, '\D', '', 'g')
   )
ORDER BY a.id, b.id;
