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
const EmbeddedPostgres = require('embedded-postgres').default;
const fs = require('node:fs');
const { Client } = require('pg');

const SQL_DIR = path.join(__dirname, '..', 'sql');
const INVESTIGACOES_DIR = path.join(__dirname, '..', 'investigacoes');
const PORT = 5433;
const DATA_DIR = path.join(__dirname, '..', '.pgdata-validate');

function readSql(filename) {
  return fs.readFileSync(path.join(SQL_DIR, filename), 'utf-8');
}

function readDeteccao(investigacao) {
  return fs.readFileSync(path.join(INVESTIGACOES_DIR, investigacao, 'deteccao.sql'), 'utf-8');
}

// Cada check é uma query de detecção que devolve uma linha por registro
// com defeito, e quantas linhas ela deve devolver em cada etapa. Quando a
// investigação do defeito já existe, a query vem do deteccao.sql dela —
// assim o que está documentado é exatamente o que é testado.
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
    label: 'pagamentos com data anterior ao pedido',
    sql: `SELECT pg.id FROM pagamentos pg
          JOIN pedidos p ON p.id = pg.pedido_id
          WHERE pg.data_pagamento IS NOT NULL AND pg.data_pagamento < p.data_pedido`,
    esperadoValido: 0,
    esperadoQuebrado: 1,
  },
];

async function freshClient() {
  const client = new Client({
    host: 'localhost',
    port: PORT,
    user: 'postgres',
    password: 'postgres',
    database: 'postgres',
  });
  await client.connect();
  return client;
}

async function resetDatabase(client) {
  await client.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
}

async function runChecks(client, campoEsperado) {
  for (const check of CHECKS) {
    // A query é usada como subquery: tira o ";" final, e a quebra de linha
    // antes do ")" evita que um comentário "--" no fim do arquivo comente
    // o fechamento do parêntese.
    const sql = check.sql.trim().replace(/;$/, '');
    const result = await client.query(`SELECT COUNT(*) AS count FROM (${sql}\n) AS deteccao`);
    const count = Number(result.rows[0].count);
    const expected = check[campoEsperado];
    const ok = count === expected;
    console.log(`  ${ok ? '✔' : '✘'} ${check.label}: esperado ${expected}, encontrado ${count}`);
    if (!ok) process.exitCode = 1;
  }
}

async function main() {
  const pg = new EmbeddedPostgres({
    databaseDir: DATA_DIR,
    user: 'postgres',
    password: 'postgres',
    port: PORT,
    persistent: false,
  });

  console.log('Subindo Postgres (embarcado, sem Docker)...');
  await pg.initialise();
  await pg.start();

  try {
    const client = await freshClient();

    console.log('\n--- Etapa 1: schema + massa VÁLIDA (deve estar 100% limpa) ---');
    await resetDatabase(client);
    await client.query(readSql('01_schema.sql'));
    await client.query(readSql('02_seed_valido.sql'));
    await runChecks(client, 'esperadoValido');

    console.log('\n--- Etapa 2: schema + massa válida + massa QUEBRADA (defeitos esperados) ---');
    await resetDatabase(client);
    await client.query(readSql('01_schema.sql'));
    await client.query(readSql('02_seed_valido.sql'));
    await client.query(readSql('03_seed_quebrado.sql'));
    await runChecks(client, 'esperadoQuebrado');

    await client.end();
  } finally {
    await pg.stop();
    fs.rmSync(DATA_DIR, { recursive: true, force: true, maxRetries: 3, retryDelay: 300 });
  }

  if (process.exitCode === 1) {
    console.log('\nValidação FALHOU — ver itens marcados com ✘ acima.');
  } else {
    console.log('\nValidação OK — schema e as duas massas de dados se comportam como esperado.');
  }
}

// Sai explicitamente com o código certo: o embedded-postgres registra um
// gancho de saída (async-exit-hook) que, se o processo terminar sozinho,
// chama process.exit(0) e descarta o process.exitCode = 1 dos checks que
// falharam — e a CI ficaria verde mesmo com defeito.
main()
  .then(() => process.exit(process.exitCode || 0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
