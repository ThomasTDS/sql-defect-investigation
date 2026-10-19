# Validações de consistência de valores

Regras sobre os **valores** de pedidos, itens e pagamentos que não fazem parte dos 7 defeitos investigados, mas que o `npm run validate` confere a cada execução (e a CI, a cada pull request). Cada arquivo é uma query que lista os registros que quebram a regra.

| Arquivo | Regra | Massa válida | Massa quebrada |
|---|---|---|---|
| [`total-pedido-igual-soma-itens.sql`](total-pedido-igual-soma-itens.sql) | O total do pedido é a soma dos seus itens | 0 | 1 |
| [`pagamento-igual-total-pedido.sql`](pagamento-igual-total-pedido.sql) | A soma dos pagamentos aprovados é igual ao total do pedido | 0 | 1 |
| [`item-igual-preco-catalogo.sql`](item-igual-preco-catalogo.sql) | O preço do item é o preço do catálogo | 0 | *não se aplica* |

## Por que as regras rodam em massas diferentes

As duas primeiras são **regras de negócio**: valem em qualquer sistema de vendas. Por isso, rodam nas duas massas.

A terceira é só uma **premissa da massa de controle**. Num sistema real, o preço do catálogo muda com o tempo, e o item guarda o preço da época da venda justamente por isso. Aqui a regra só vale porque a massa de dados não tem histórico de preços nem descontos. Ela protege a massa válida contra erros de digitação, e não diz nada sobre os defeitos.

## Os registros que quebram as regras na massa quebrada

Na regra de pagamentos, o único registro é o **pedido 2**: ele tem dois pagamentos aprovados de R$ 99,90 para um total de R$ 99,90. É o pagamento em duplicidade da [investigação 05](../investigacoes/05-pagamento-duplicado/README.md), que o encontra por outro caminho (comparando cada pagamento com o anterior).

Na regra de total, o único registro é o **pedido 10**: ele tem `valor_total` de R$ 99,90 e nenhum item. É o mesmo pedido órfão da [investigação 02](../investigacoes/02-fk-orfa/README.md), que também aparece na [investigação 03](../investigacoes/03-status-inconsistente/README.md) como "confirmado" sem pagamento. Um pedido incompleto quebra várias regras ao mesmo tempo, e cada verificação o encontra por um caminho diferente.
