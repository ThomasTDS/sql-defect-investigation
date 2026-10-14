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
const PORT = 5433;
const DATA_DIR = path.join(__dirname, '..', '.pgdata-validate');

function readSql(filename) {
  return fs.readFileSync(path.join(SQL_DIR, filename), 'utf-8');
}

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

async function expectCount(client, label, sql, expected) {
  const result = await client.query(sql);
  const count = Number(result.rows[0].count);
  const ok = count === expected;
  console.log(`  ${ok ? '✔' : '✘'} ${label}: esperado ${expected}, encontrado ${count}`);
  if (!ok) process.exitCode = 1;
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

    await expectCount(
      client,
      'pares de clientes duplicados (mesmo email ou documento)',
      `SELECT COUNT(*) FROM clientes a
       JOIN clientes b ON a.id < b.id AND (a.email = b.email OR a.documento = b.documento)`,
      0
    );
    await expectCount(
      client,
      'pedidos com cliente_id órfão',
      `SELECT COUNT(*) FROM pedidos p LEFT JOIN clientes c ON c.id = p.cliente_id WHERE c.id IS NULL`,
      0
    );
    await expectCount(
      client,
      'pedidos entregues sem pagamento aprovado',
      `SELECT COUNT(*) FROM pedidos p
       WHERE p.status = 'entregue'
         AND NOT EXISTS (SELECT 1 FROM pagamentos pg WHERE pg.pedido_id = p.id AND pg.status = 'aprovado')`,
      0
    );
    await expectCount(
      client,
      'pedidos cancelados com pagamento aprovado',
      `SELECT COUNT(*) FROM pedidos p
       JOIN pagamentos pg ON pg.pedido_id = p.id
       WHERE p.status = 'cancelado' AND pg.status = 'aprovado'`,
      0
    );
    await expectCount(
      client,
      'pagamentos com data anterior ao pedido',
      `SELECT COUNT(*) FROM pagamentos pg
       JOIN pedidos p ON p.id = pg.pedido_id
       WHERE pg.data_pagamento IS NOT NULL AND pg.data_pagamento < p.data_pedido`,
      0
    );

    console.log('\n--- Etapa 2: schema + massa válida + massa QUEBRADA (defeitos esperados) ---');
    await resetDatabase(client);
    await client.query(readSql('01_schema.sql'));
    await client.query(readSql('02_seed_valido.sql'));
    await client.query(readSql('03_seed_quebrado.sql'));

    await expectCount(
      client,
      'pares de clientes duplicados (mesmo email ou documento)',
      `SELECT COUNT(*) FROM clientes a
       JOIN clientes b ON a.id < b.id AND (a.email = b.email OR a.documento = b.documento)`,
      1
    );
    await expectCount(
      client,
      'pedidos com cliente_id órfão',
      `SELECT COUNT(*) FROM pedidos p LEFT JOIN clientes c ON c.id = p.cliente_id WHERE c.id IS NULL`,
      1
    );
    await expectCount(
      client,
      'pedidos entregues sem pagamento aprovado',
      `SELECT COUNT(*) FROM pedidos p
       WHERE p.status = 'entregue'
         AND NOT EXISTS (SELECT 1 FROM pagamentos pg WHERE pg.pedido_id = p.id AND pg.status = 'aprovado')`,
      1
    );
    await expectCount(
      client,
      'pedidos cancelados com pagamento aprovado',
      `SELECT COUNT(*) FROM pedidos p
       JOIN pagamentos pg ON pg.pedido_id = p.id
       WHERE p.status = 'cancelado' AND pg.status = 'aprovado'`,
      1
    );
    await expectCount(
      client,
      'pagamentos com data anterior ao pedido',
      `SELECT COUNT(*) FROM pagamentos pg
       JOIN pedidos p ON p.id = pg.pedido_id
       WHERE pg.data_pagamento IS NOT NULL AND pg.data_pagamento < p.data_pedido`,
      1
    );

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
