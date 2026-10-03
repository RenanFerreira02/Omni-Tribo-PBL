# Evidências — camada Oracle

Saída real das execuções contra a instância Oracle da FIAP (`oracle.fiap.com.br`, **Oracle Database
19c Enterprise Edition**, charset `AL32UTF8`), em 2026-10-03. Nada aqui foi editado à mão: cada
arquivo é a saída do comando indicado.

| Arquivo | Comando | O que prova |
|---|---|---|
| [`01-instalacao.txt`](01-instalacao.txt) | `bash Oracle/executar.sh instalar.sql` | As 12 tabelas, 3 triggers, 5 functions e 3 procedures foram criadas e estão `VALID`; nenhuma linha em `USER_ERRORS`; contagem de linhas carregadas por tabela |
| [`02-consultas-de-uso.txt`](02-consultas-de-uso.txt) | `bash Oracle/executar.sh 06_consultas_de_uso.sql` | As functions dentro de `SELECT`, `WHERE` e `ORDER BY`; as três procedures em execução, com os alertas que a varredura registra e o relatório impresso |
| [`03-testes.txt`](03-testes.txt) | `bash Oracle/executar.sh 07_testes.sql` | 90 de 90 asserções: caminho feliz e de erro de cada rotina, idempotência, conservação e as regras garantidas pelo banco |
| [`04-java-rest-jdbc-oracle.txt`](04-java-rest-jdbc-oracle.txt) | `curl` contra `Oracle/java` em execução | A procedure acionada pelo back-end Java: 201, replay 200, 422, 404, 400, e a conferência do resultado direto no Oracle |

## O que cada uma mostra de mais importante

**Instalação.** Compilou sem erro na primeira execução em Oracle 19c. Os scripts não usam recurso
de versão posterior.

**Consultas.** A seção 3 lista quatro missões com token parado **enquanto** a seção 2 mostra todas
as 13 carteiras íntegras. É a demonstração de que reconciliação e conservação são invariantes
diferentes, e de por que a varredura existe.

**Testes.** Os valores esperados foram escritos à mão a partir dos cenários, não derivados de outra
consulta. Três merecem destaque:
- a varredura trata quatro missões e **isola** a quinta, corrompida de propósito, registrando o
  alerta `VARREDURA_FALHOU` com o código do erro;
- a soma `carteiras + potes` muda em exatamente 22 tokens na varredura (a emissão da missão de fonte
  `CUNHAGEM`) e em exatamente 15 no resgate (a queima);
- a mesma chave de idempotência usada por outro usuário **não** devolve o resgate alheio.

**Java.** A chamada 3 repete a 2 com a mesma `Idempotency-Key` e recebe o mesmo resgate, com
`replay: true` e o saldo inalterado. A seção 11 confere no banco: um único lançamento para as duas
chamadas, nenhum para as chamadas recusadas, e o ledger íntegro.

## O que estas evidências não provam

- **Concorrência.** Nenhuma execução aqui é multi-thread. As procedures usam `SELECT … FOR UPDATE`
  e travam carteiras em ordem determinística, mas isso não foi medido sob carga no Oracle.
- **Desempenho.** A massa é pequena (26 missões, 25 lançamentos). Nenhum plano de execução foi
  analisado.
- **Sincronização.** Os dados foram carregados uma vez, a partir do seed. Não há replicação do
  PostgreSQL do sistema para o Oracle.
- **Fechamento da economia desde o zero.** O seed do projeto credita recompensas históricas sem o
  financiamento correspondente, então `emitido − queimado` não fecha com `carteiras + potes` sobre
  estes dados. O que está provado é a **variação**: cada rotina altera a soma exatamente no valor
  esperado.

## Um defeito que a medição achou

A primeira execução das chamadas REST respondeu **500** para saldo insuficiente e para benefício
inativo, onde o esperado era 422 e 404. O teste unitário da tradução de erro passava.

A causa: o código procurava a `SQLException` com `getRootCause()`. O driver da Oracle encadeia uma
`OracleDatabaseException` — que não é `SQLException` — como causa da própria `SQLException`, então
a raiz da cadeia nunca é o tipo que carrega o código `ORA`. Corrigido em
[`TratadorDeErros.sqlExceptionDe`](../java/src/main/java/com/omnitribo/oracle/TratadorDeErros.java),
que percorre a cadeia, com teste de regressão em `ErroOracleTest`. A evidência 04 é da execução
posterior à correção.
