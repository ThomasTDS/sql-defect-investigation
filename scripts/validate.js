// Valida o schema e as duas massas de dados contra um Postgres real
// (binário baixado sob demanda, sem precisar de Docker) — usado tanto em
// desenvolvimento local quanto no CI.
//
// 1. Sobe um Postgres limpo.
// 2. Carrega schema + seed válido isolado e confirma que nenhuma
//    investigação encontra problema (a massa "limpa" tem que estar limpa
//    de verdade).
// 3. Recria o banco, carrega schema + seed válido + seed quebrado, e
//    confirma que cada defeito esperado é encontrado.

const path = require('node:path');
const fs = require('node:fs');
const { comPostgresEmbarcado, recriarBanco, executar } = require('./postgres-embarcado');

const INVESTIGACOES_DIR = path.join(__dirname, '..', 'investigacoes');
const VALIDACOES_DIR = path.join(__dirname, '..', 'validacoes');
const PORT = 5433;
const DATA_DIR = path.join(__dirname, '..', '.pgdata-validate');

function readDeteccao(investigacao) {
  return fs.readFileSync(path.join(INVESTIGACOES_DIR, investigacao, 'deteccao.sql'), 'utf-8');
}

function readValidacao(filename) {
  return fs.readFileSync(path.join(VALIDACOES_DIR, filename), 'utf-8');
}

// Cada check é uma query de detecção que devolve uma linha por registro
// com defeito, e quantas linhas ela deve devolver em cada etapa. A query
// vem de um arquivo .sql documentado (o deteccao.sql de cada investigação,
// ou uma regra de validacoes/) — assim o que está documentado é exatamente
// o que é testado. Esperado null = o check não se aplica àquela etapa.
const CHECKS = [
  {
    label: 'pares de clientes duplicados (mesmo email ou documento)',
    sql: readDeteccao('01-clientes-duplicados'),
    esperadoValido: 0,
    esperadoQuebrado: 1,
  },
  {
    label: 'registros órfãos (FK apontando para registro inexistente)',
    sql: readDeteccao('02-fk-orfa'),
    esperadoValido: 0,
    esperadoQuebrado: 1,
  },
  {
    // 3 na massa quebrada: os 2 casos plantados (pedidos 11 e 12) e o
    // pedido órfão da investigação 02 (pedido 10), que também está
    // "confirmado" sem pagamento.
    label: 'pedidos com status incompatível com o pagamento',
    sql: readDeteccao('03-status-inconsistente'),
    esperadoValido: 0,
    esperadoQuebrado: 3,
  },
  {
    label: 'datas implausíveis (fora da ordem cadastro → pedido → pagamento, ou no futuro)',
    sql: readDeteccao('04-data-invalida'),
    esperadoValido: 0,
    esperadoQuebrado: 1,
  },
  {
    label: 'pagamentos aprovados registrados em duplicidade',
    sql: readDeteccao('05-pagamento-duplicado'),
    esperadoValido: 0,
    esperadoQuebrado: 1,
  },
  {
    // 1 na massa quebrada: o pedido 10 tem valor_total e nenhum item.
    label: 'pedidos com total diferente da soma dos itens',
    sql: readValidacao('total-pedido-igual-soma-itens.sql'),
    esperadoValido: 0,
    esperadoQuebrado: 1,
  },
  {
    // 1 na massa quebrada: o pedido 2, com o pagamento em duplicidade da
    // investigação 05 (soma 199,80 para um total de 99,90).
    label: 'pedidos com pagamentos aprovados diferentes do total',
    sql: readValidacao('pagamento-igual-total-pedido.sql'),
    esperadoValido: 0,
    esperadoQuebrado: 1,
  },
  {
    // Premissa da massa de controle, não regra de negócio: ver o
    // comentário no próprio arquivo .sql.
    label: 'itens com preço diferente do catálogo (premissa da massa de controle)',
    sql: readValidacao('item-igual-preco-catalogo.sql'),
    esperadoValido: 0,
    esperadoQuebrado: null,
  },
];

// Resultado de cada check executado, usado no resumo da CI.
const resultados = [];

async function runChecks(client, etapa, campoEsperado) {
  for (const check of CHECKS) {
    const expected = check[campoEsperado];
    if (expected === null) continue;

    // A query é usada como subquery: tira o ";" final, e a quebra de linha
    // antes do ")" evita que um comentário "--" no fim do arquivo comente
    // o fechamento do parêntese.
    const sql = check.sql.trim().replace(/;$/, '');
    const result = await client.query(`SELECT COUNT(*) AS count FROM (${sql}\n) AS deteccao`);
    const count = Number(result.rows[0].count);
    const ok = count === expected;
    console.log(`  ${ok ? '✔' : '✘'} ${check.label}: esperado ${expected}, encontrado ${count}`);
    resultados.push({ etapa, label: check.label, expected, count, ok });
    if (!ok) process.exitCode = 1;
  }
}

// No GitHub Actions, GITHUB_STEP_SUMMARY aponta para um arquivo cujo
// conteúdo (Markdown) aparece na página da execução. Fora do Actions a
// variável não existe e nada é escrito.
function escreverResumoCi() {
  const arquivo = process.env.GITHUB_STEP_SUMMARY;
  if (!arquivo) return;

  const okCount = resultados.filter((r) => r.ok).length;
  const linhas = [
    '## Validação dos dados',
    '',
    `**${okCount}/${resultados.length} checks OK**${okCount === resultados.length ? '' : ' — ver os itens marcados com ❌'}`,
    '',
    '| Etapa | Check | Esperado | Encontrado | |',
    '|---|---|---|---|---|',
    ...resultados.map((r) => `| ${r.etapa} | ${r.label} | ${r.expected} | ${r.count} | ${r.ok ? '✅' : '❌'} |`),
    '',
  ];
  fs.appendFileSync(arquivo, linhas.join('\n') + '\n');
}

async function main() {
  await comPostgresEmbarcado({ porta: PORT, pasta: DATA_DIR }, async (client) => {
    console.log('\n--- Etapa 1: schema + massa VÁLIDA (deve estar 100% limpa) ---');
    await recriarBanco(client, ['01_schema.sql', '02_seed_valido.sql']);
    await runChecks(client, 'Massa válida', 'esperadoValido');

    console.log('\n--- Etapa 2: schema + massa válida + massa QUEBRADA (defeitos esperados) ---');
    await recriarBanco(client, ['01_schema.sql', '02_seed_valido.sql', '03_seed_quebrado.sql']);
    await runChecks(client, 'Massa quebrada', 'esperadoQuebrado');
  });

  escreverResumoCi();

  if (process.exitCode === 1) {
    console.log('\nValidação FALHOU — ver itens marcados com ✘ acima.');
  } else {
    console.log('\nValidação OK — schema e as duas massas de dados se comportam como esperado.');
  }
}

executar(main);
