// Teste de regressão dos relatórios das investigações.
//
// Os relatórios (investigacoes/*/README.md) mostram o resultado real de
// cada query do exploracao.sql. Se a massa de dados mudar, esses números
// podem ficar desatualizados sem que nenhum check de detecção falhe.
//
// Este script roda cada exploracao.sql contra o banco completo (schema +
// massa válida + massa quebrada) e compara o resultado inteiro de cada
// consulta com o arquivo resultado-esperado.json da investigação.
//
//   npm run relatorios             compara; falha se algo mudou
//   npm run relatorios:atualizar   regrava os arquivos de referência
//
// Quando a comparação falhar, o caminho certo é: revisar e corrigir o
// README.md da investigação para os números novos, e só então atualizar
// a referência.

const path = require('node:path');
const fs = require('node:fs');
const { comPostgresEmbarcado, recriarBanco, executar } = require('./postgres-embarcado');

const INVESTIGACOES_DIR = path.join(__dirname, '..', 'investigacoes');
const PORT = 5434;
const DATA_DIR = path.join(__dirname, '..', '.pgdata-relatorios');
const ARQUIVO_ESPERADO = 'resultado-esperado.json';
const MODO_ATUALIZAR = process.argv.includes('--atualizar');

// Todos os valores chegam como o texto exato que o Postgres devolve. Sem
// isso, o driver converteria datas para o fuso horário da máquina e
// intervalos para objetos, e a referência gerada num computador não
// bateria na CI.
const TEXTO_PURO = { getTypeParser: () => (valor) => valor };

async function executarExploracao(client, investigacao) {
  const sql = fs.readFileSync(path.join(INVESTIGACOES_DIR, investigacao, 'exploracao.sql'), 'utf-8');
  const resultado = await client.query({ text: sql, rowMode: 'array' });
  const resultados = Array.isArray(resultado) ? resultado : [resultado];
  return resultados
    .filter((r) => r.command === 'SELECT')
    .map((r, i) => ({
      consulta: i + 1,
      colunas: r.fields.map((f) => f.name),
      linhas: r.rows,
    }));
}

// JSON com uma linha do resultado por linha do arquivo, para o diff de
// um PR mostrar exatamente qual valor mudou.
function formatar(consultas) {
  const blocos = consultas.map((c) => {
    const linhas = c.linhas.map((l) => `      ${JSON.stringify(l)}`).join(',\n');
    return [
      '  {',
      `    "consulta": ${c.consulta},`,
      `    "colunas": ${JSON.stringify(c.colunas)},`,
      `    "linhas": [${linhas ? `\n${linhas}\n    ` : ''}]`,
      '  }',
    ].join('\n');
  });
  return `[\n${blocos.join(',\n')}\n]\n`;
}

// Devolve null se for igual, ou uma descrição curta da primeira diferença.
function primeiraDiferenca(esperado, encontrado) {
  if (esperado.length !== encontrado.length) {
    return `quantidade de consultas: esperado ${esperado.length}, encontrado ${encontrado.length}`;
  }
  for (let i = 0; i < esperado.length; i++) {
    const e = esperado[i];
    const f = encontrado[i];
    if (JSON.stringify(e.colunas) !== JSON.stringify(f.colunas)) {
      return `consulta ${i + 1}: colunas mudaram`;
    }
    if (e.linhas.length !== f.linhas.length) {
      return `consulta ${i + 1}: esperado ${e.linhas.length} linha(s), encontrado ${f.linhas.length}`;
    }
    for (let j = 0; j < e.linhas.length; j++) {
      if (JSON.stringify(e.linhas[j]) !== JSON.stringify(f.linhas[j])) {
        return `consulta ${i + 1}, linha ${j + 1}: esperado ${JSON.stringify(e.linhas[j])}, encontrado ${JSON.stringify(f.linhas[j])}`;
      }
    }
  }
  return null;
}

function escreverResumoCi(resultados) {
  const arquivo = process.env.GITHUB_STEP_SUMMARY;
  if (!arquivo) return;
  const okCount = resultados.filter((r) => r.ok).length;
  const linhas = [
    '## Relatórios das investigações',
    '',
    `**${okCount}/${resultados.length} relatórios com resultados iguais à referência**`,
    '',
    '| Investigação | Resultado | |',
    '|---|---|---|',
    ...resultados.map((r) => `| ${r.investigacao} | ${r.mensagem} | ${r.ok ? '✅' : '❌'} |`),
    '',
  ];
  fs.appendFileSync(arquivo, linhas.join('\n') + '\n');
}

async function main() {
  const investigacoes = fs
    .readdirSync(INVESTIGACOES_DIR, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => d.name)
    .sort();
  const resultados = [];

  await comPostgresEmbarcado({ porta: PORT, pasta: DATA_DIR, opcoesCliente: { types: TEXTO_PURO } }, async (client) => {
    await recriarBanco(client, ['01_schema.sql', '02_seed_valido.sql', '03_seed_quebrado.sql']);
    console.log(MODO_ATUALIZAR ? '\n--- Atualizando as referências ---' : '\n--- Comparando com as referências ---');

    for (const investigacao of investigacoes) {
      const encontrado = await executarExploracao(client, investigacao);
      const arquivo = path.join(INVESTIGACOES_DIR, investigacao, ARQUIVO_ESPERADO);

      if (MODO_ATUALIZAR) {
        fs.writeFileSync(arquivo, formatar(encontrado));
        console.log(`  ✎ ${investigacao}: ${encontrado.length} consultas gravadas`);
        continue;
      }

      let mensagem;
      if (!fs.existsSync(arquivo)) {
        mensagem = `sem ${ARQUIVO_ESPERADO} (rode npm run relatorios:atualizar)`;
      } else {
        const esperado = JSON.parse(fs.readFileSync(arquivo, 'utf-8'));
        mensagem = primeiraDiferenca(esperado, encontrado);
      }
      const ok = mensagem === null;
      if (ok) mensagem = `${encontrado.length} consultas iguais`;
      console.log(`  ${ok ? '✔' : '✘'} ${investigacao}: ${mensagem}`);
      resultados.push({ investigacao, ok, mensagem });
      if (!ok) process.exitCode = 1;
    }
  });

  if (MODO_ATUALIZAR) {
    console.log('\nReferências atualizadas. Confira no diff se os README.md das investigações mostram os mesmos números.');
    return;
  }

  escreverResumoCi(resultados);

  if (process.exitCode === 1) {
    console.log('\nRelatórios DESATUALIZADOS — o resultado de alguma exploração mudou.');
    console.log('Revise o README.md da investigação marcada com ✘ e depois rode npm run relatorios:atualizar.');
  } else {
    console.log('\nRelatórios OK — todas as explorações devolvem o mesmo resultado da referência.');
  }
}

executar(main);
