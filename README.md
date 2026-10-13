# 🔎 SQL Defect Investigation

![license](https://img.shields.io/badge/license-MIT-blue.svg)
![postgres](https://img.shields.io/badge/PostgreSQL-16-blue.svg)

## Descrição

Este repositório simula um banco de dados de CRM/ERP de vendas com defeitos de dados reais — clientes duplicados, foreign keys órfãs, status inconsistentes e datas inválidas — e documenta as investigações SQL que encontram cada um deles, com a mesma metodologia (hipótese → query → evidência → causa raiz) usada em investigação de bugs de produção.

Não é um exercício de sintaxe SQL: o objetivo é demonstrar a habilidade de usar SQL para **encontrar defeito real** num banco com dados já corrompidos, do jeito que aconteceria investigando um bug relatado em produção.

> **Nota sobre os dados:** todo o schema e os dados aqui são fictícios, criados especificamente para este projeto de portfólio. Nenhuma informação de empregador atual ou anterior foi usada.

---

## Estrutura do Projeto

```text
sql-defect-investigation/
├── sql/
│   ├── 01_schema.sql          # DDL: tabelas, FKs, constraints
│   ├── 02_seed_valido.sql     # massa de dados limpa (controle)
│   └── 03_seed_quebrado.sql   # defeitos introduzidos de propósito, comentados
├── scripts/
│   └── validate.js            # sobe um Postgres real e valida schema + as duas massas
├── docker-compose.yml         # Postgres pronto, já carregado com os dados
├── package.json
├── LICENSE
└── README.md
```

---

## Como rodar

### Opção 1 — Docker (recomendado)

```bash
docker compose up
```

Isso sobe um PostgreSQL 16 na porta 5432 já com o schema e as duas massas de dados carregadas (os arquivos em `sql/` rodam automaticamente, em ordem, na primeira inicialização do container).

```bash
docker exec -it sql-defect-investigation-postgres-1 psql -U postgres -d defect_investigation
```

### Opção 2 — Validação local sem Docker

```bash
npm install
npm run validate
```

Isso baixa um binário real do PostgreSQL (sem precisar de Docker instalado), sobe um banco temporário, carrega o schema e as duas massas de dados, e confirma que cada defeito esperado é encontrado pelas queries de investigação — e que a massa "válida", sozinha, não aciona nenhuma delas.

---

## Os 4 defeitos investigados

| # | Defeito | Cenário real simulado |
|---|---------|------------------------|
| 1 | Clientes duplicados | Formulário de cadastro enviado duas vezes, sem constraint única em email/documento |
| 2 | Foreign key órfã | Cliente removido diretamente no banco (acesso de suporte), sem tratar os pedidos vinculados |
| 3 | Status inconsistente | Pedido marcado "entregue" sem pagamento aprovado; pedido "cancelado" com pagamento ainda "aprovado" |
| 4 | Data inválida | Importação em lote gravou a data de processamento, não a data real do pagamento |

Cada um está implementado e comentado em `sql/03_seed_quebrado.sql`, com a query de detecção correspondente em `scripts/validate.js`.

---

## Licença

Distribuído sob a licença MIT. Veja [LICENSE](LICENSE) para mais detalhes.
