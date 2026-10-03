# Oracle — PBL Fase 6

Camada Oracle PL/SQL do Omni-Tribo: modelo relacional, dados, functions, procedures e a integração
com Java.

Esta pasta é **autocontida**. O sistema continua sendo PostgreSQL + PostGIS (`services/api`), com
Flyway como única fonte de schema; nada lá foi alterado para esta fase. O Oracle recebe uma projeção
das entidades principais, e é sobre ela que o PL/SQL roda.

## Onde está cada item do enunciado

| Item | Onde |
|---|---|
| **Parte 2** — modelo lógico/físico | [`sql/01_tabelas.sql`](sql/01_tabelas.sql) · [`docs/DER.md`](docs/DER.md) |
| **Parte 2** — tabelas implantadas no Oracle | [`evidencias/`](evidencias/) |
| **Parte 2** — dados importados | [`sql/02_carga_seed.sql`](sql/02_carga_seed.sql) (do sistema) · [`sql/03_carga_cenarios.sql`](sql/03_carga_cenarios.sql) (simulados) |
| **Parte 2** — DER e tabelas documentados | [`docs/DER.md`](docs/DER.md) · [`docs/DICIONARIO.md`](docs/DICIONARIO.md) |
| **Parte 3** — function de indicador | `FN_OT_TAXA_CONCLUSAO_TRIBO`, `FN_OT_DIVERGENCIA_CARTEIRA` em [`sql/04_functions.sql`](sql/04_functions.sql) |
| **Parte 3** — function de dados formatados | `FN_OT_RESUMO_MISSAO` em [`sql/04_functions.sql`](sql/04_functions.sql) |
| **Parte 3** — functions em consultas SQL | [`sql/06_consultas_de_uso.sql`](sql/06_consultas_de_uso.sql) |
| **Parte 3** — procedures | `PRC_OT_VARRER_MISSOES_PARADAS`, `PRC_OT_RESGATAR_BENEFICIO`, `PRC_OT_RELATORIO_TRIBO` em [`sql/05_procedures.sql`](sql/05_procedures.sql) |
| **Parte 3** — procedure acionada pelo Java | `PRC_OT_RESGATAR_BENEFICIO`, por [`java/`](java/) (REST → Java → JDBC → Oracle) |
| **Parte 3** — `EXCEPTION`, `IF`, `LOOP`, `CURSOR` | Tabela em [`docs/PLSQL.md`](docs/PLSQL.md#visão-geral) |
| **Parte 3** — propósito e funcionamento | [`docs/PLSQL.md`](docs/PLSQL.md) |
| Documento da entrega | [`docs/ENTREGA-FASE6.md`](docs/ENTREGA-FASE6.md) |
| PDFs, slides, ZIP e roteiro do vídeo | [`entrega/`](entrega/README.md) |

## Estrutura

```
Oracle/
  sql/
    instalar.sql              instala tudo do zero (roda 00 a 05)
    00_desinstalar.sql        remove só os objetos OT_
    01_tabelas.sql            12 tabelas, constraints, índices, 3 triggers
    02_carga_seed.sql         dados do sistema (gerado)
    03_carga_cenarios.sql     dados simulados
    04_functions.sql          5 functions
    05_procedures.sql         3 procedures
    06_consultas_de_uso.sql   functions em SELECT e chamadas das procedures
    07_testes.sql             testes com asserção
  dados/exportar_do_postgres.sh   gera o 02 a partir do PostgreSQL do projeto
  java/                       aplicação Spring Boot que chama as procedures
  docs/                       DER, dicionário, PL/SQL e documento da entrega
  evidencias/                 saída real das execuções
  entrega/                    gera o PDF do documento, o PDF dos slides e o ZIP; roteiro do vídeo
  executar.sh                 roda um script SQL com a credencial de .env
```

## Como executar

### 1. Credencial

```bash
cp Oracle/.env.example Oracle/.env    # preencha ORACLE_USER e ORACLE_PASSWORD
```

`Oracle/.env` não é versionado.

### 2. Instalar no Oracle

Com [SQLcl](https://www.oracle.com/database/sqldeveloper/technologies/sqlcl/) e um JDK:

```bash
bash Oracle/executar.sh instalar.sql
```

Sem SQLcl, abra `Oracle/sql/instalar.sql` no SQL Developer e execute como script (F5), ou rode os
arquivos `00` a `05` em ordem.

A instalação termina listando os objetos criados, e todos devem estar `VALID`. Ela é repetível:
rodar de novo devolve o banco ao estado inicial.

Todo objeto tem o prefixo `OT_`. O schema do aluno é compartilhado com outras disciplinas, e o
`00_desinstalar.sql` apaga só o que tem esse prefixo.

### 3. Ver as rotinas em uso

```bash
bash Oracle/executar.sh 06_consultas_de_uso.sql
bash Oracle/executar.sh 07_testes.sql
```

Os dois terminam em `ROLLBACK` e podem ser repetidos.

### 4. Java → Oracle

```bash
set -a; source Oracle/.env; set +a
services/api/mvnw -f Oracle/java/pom.xml spring-boot:run      # porta 8085
```

Em outro terminal:

```bash
# Resgate: Marlene troca 15 tokens por um café. 201 na primeira vez.
curl -i -X POST http://localhost:8085/oracle/resgates \
  -H 'Content-Type: application/json' \
  -H 'Idempotency-Key: demo-1' \
  -d '{"usuarioId":"bbbbbbbb-0000-0000-0000-000000000902","beneficioId":"33333333-0000-0000-0000-000000000960"}'

# A mesma chamada de novo: 200, mesmo resgate, nada debitado.

# Saldo insuficiente: Gustavo não tem token. 422.
curl -i -X POST http://localhost:8085/oracle/resgates \
  -H 'Content-Type: application/json' \
  -H 'Idempotency-Key: demo-2' \
  -d '{"usuarioId":"bbbbbbbb-0000-0000-0000-000000000905","beneficioId":"33333333-0000-0000-0000-000000000960"}'

# Varredura de missões paradas.
curl -i -X POST http://localhost:8085/oracle/varredura

# As functions dentro de SELECT.
curl -s http://localhost:8085/oracle/indicadores
```

Ao contrário dos scripts SQL, as chamadas pelo Java **confirmam** a transação. Para voltar ao estado
inicial, rode `instalar.sql` de novo.

## Decisões

**Oracle ao lado do PostgreSQL, não no lugar dele.** O projeto depende do PostGIS para o radar de
missões e para a validação do check-in, e tem 28 migrations e 580 testes de back-end sobre ele. Trocar
o banco inteiro por uma fase colocaria tudo isso em risco sem que o enunciado peça. O enunciado
fala em "estender a arquitetura com uma camada de persistência Oracle", e é o que foi feito.

**As procedures repetem regras que já existem em Java.** A varredura espelha
`ExpiracaoMissoesService`, o resgate espelha `ResgateService` e a reconciliação espelha
`ReconciliacaoService`. Elas rodam sobre uma cópia dos dados e mostram a mesma regra implementada
na camada de banco; o sistema em produção segue usando os serviços Java.

**Dado pessoal não sobe.** E-mail, hash de senha e coordenada de check-in não são exportados. O
servidor é institucional, e esta camada não precisa deles.

**A aplicação Java é separada de `services/api`.** A integração pedida pelo enunciado está aqui, em
`java/`, e não dentro do back-end principal. Fazer a chamada de lá exigiria um segundo banco de dados
na API, com reflexo em configuração, testes e CI. A limitação que isso traz: a demonstração não tem
autenticação, e o usuário vem no corpo da requisição.

## O que esta entrega não cobre

- **Sincronização contínua.** Os dados são carregados uma vez. Não há replicação do PostgreSQL para
  o Oracle; uma mudança no sistema não aparece aqui até a carga ser gerada de novo.
- **Concorrência medida.** As procedures usam `SELECT … FOR UPDATE` e travam em ordem
  determinística, mas não há teste multi-thread contra o Oracle como há no back-end principal.
- **Geoespacial.** Nenhuma consulta por distância roda no Oracle.
