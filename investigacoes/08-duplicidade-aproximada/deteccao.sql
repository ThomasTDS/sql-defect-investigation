-- Detecção: produtos com nomes muito parecidos, provável cadastro
-- duplicado do mesmo item.
--
-- Usa a similaridade por trigramas da extensão pg_trgm: o nome é quebrado
-- em sequências de 3 letras, e a similaridade é a fração de sequências em
-- comum (0 = nada em comum, 1 = iguais). Ela já ignora maiúsculas e
-- pontuação, e tolera erros de digitação.
--
-- O limite de 0,6 foi escolhido a partir dos dados (ver o relatório): o
-- limite padrão da extensão (0,3) marcaria como duplicados produtos
-- legítimos e diferentes, como "Plano Básico Mensal" e "Plano
-- Profissional Mensal" (0,419).
--
-- Cada linha é um par de produtos suspeito. Resultado esperado: zero
-- linhas.

SELECT
    a.id AS produto_original,
    b.id AS produto_suspeito,
    a.nome AS nome_original,
    b.nome AS nome_suspeito,
    round(similarity(a.nome, b.nome)::numeric, 3) AS similaridade,
    a.preco = b.preco AS mesmo_preco
FROM produtos a
JOIN produtos b
    ON a.id < b.id
   AND similarity(a.nome, b.nome) >= 0.6
ORDER BY similaridade DESC, a.id, b.id;
