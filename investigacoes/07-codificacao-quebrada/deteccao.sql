-- Detecção: texto com codificação quebrada (mojibake) em qualquer coluna
-- de texto do banco.
--
-- Quando um texto UTF-8 é lido como Windows-1252, cada letra acentuada
-- vira dois caracteres: "Ã" ou "Â" seguido de um caractere de pontuação
-- ou símbolo ("ó" vira "Ã³", "ç" vira "Ã§", "ã" vira "Ã£"). Essa
-- combinação praticamente não existe em português escrito certo: um "Ã"
-- legítimo, como em "SÃO PAULO", é seguido de letra.
--
-- O segundo caractere vem de duas faixas: U+00A1 a U+00BF (¡ a ¿, das
-- minúsculas acentuadas) e os símbolos que o Windows-1252 coloca nos
-- bytes 0x80 a 0x9F (€, ‰, “, Š..., das maiúsculas acentuadas).
--
-- Cada linha é uma coluna de um registro com texto quebrado.
-- Resultado esperado: zero linhas.

WITH textos (tabela, registro_id, coluna, valor) AS (
    SELECT 'clientes', id, 'nome', nome FROM clientes
    UNION ALL SELECT 'clientes', id, 'email', email FROM clientes
    UNION ALL SELECT 'vendedores', id, 'nome', nome FROM vendedores
    UNION ALL SELECT 'vendedores', id, 'equipe', equipe FROM vendedores
    UNION ALL SELECT 'produtos', id, 'nome', nome FROM produtos
    UNION ALL SELECT 'produtos', id, 'categoria', categoria FROM produtos
)
SELECT tabela, registro_id, coluna, valor
FROM textos
WHERE valor ~ '[ÃÂ][¡-¿€‚ƒ„…†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ]'
ORDER BY tabela, coluna, registro_id;
