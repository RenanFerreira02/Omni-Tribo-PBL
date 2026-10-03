# Functions e procedures PL/SQL

Código em [`sql/04_functions.sql`](../sql/04_functions.sql) e
[`sql/05_procedures.sql`](../sql/05_procedures.sql). Cada rotina tem, no próprio fonte, um cabeçalho
com propósito, parâmetros, retorno e exceções; este documento explica o **porquê** de cada uma e
onde ela se liga ao sistema.

## Visão geral

| Rotina | Tipo | Papel no enunciado | Recursos de PL/SQL |
|---|---|---|---|
| `FN_OT_TAXA_CONCLUSAO_TRIBO` | function | Calcula um indicador | `IN`, `RETURN`, `IF`, `EXCEPTION` (`ZERO_DIVIDE`), `RAISE_APPLICATION_ERROR` |
| `FN_OT_DIVERGENCIA_CARTEIRA` | function | Calcula um indicador | `IN`, `RETURN`, `%TYPE`, `EXCEPTION` (`NO_DATA_FOUND`) |
| `FN_OT_RESUMO_MISSAO` | function | Retorna dados formatados | `IN`, `RETURN`, `%ROWTYPE`, `CASE`, `IF/ELSIF`, `EXCEPTION` |
| `FN_OT_FORMATAR_TOKENS` | function | Retorna dados formatados (apoio) | `IN`, `RETURN`, `IF`, `CASE` |
| `FN_OT_NOVO_ID` | function | Apoio | `RETURN` |
| `PRC_OT_VARRER_MISSOES_PARADAS` | procedure | Rotina automatizada que registra alertas | `IN`/`OUT`, 2 `CURSOR` (um parametrizado), `FOR UPDATE`, `LOOP`, `IF`, `SAVEPOINT`, exceções nomeadas, subprogramas locais |
| `PRC_OT_RESGATAR_BENEFICIO` | procedure | **Acionada pelo Java** | `IN`/`OUT`, `SELECT … FOR UPDATE`, `LOOP` com `EXIT WHEN`, `FOR`, `IF`, blocos aninhados com `EXCEPTION` |
| `PRC_OT_RELATORIO_TRIBO` | procedure | Relatório resumido por usuário | `IN`/`OUT`, `CURSOR` explícito (`OPEN`/`FETCH`/`CLOSE`), `LOOP`, `%ROWTYPE`, `%NOTFOUND`, `%ISOPEN` |

O enunciado pede duas functions e duas procedures; há cinco e três. As duas functions de apoio
existem porque as outras rotinas precisam delas, não para fazer número.

## Functions

Todas são de leitura — nenhuma faz DML —, o que permite usá-las em `SELECT`, `WHERE` e `ORDER BY`.
Os usos estão em [`sql/06_consultas_de_uso.sql`](../sql/06_consultas_de_uso.sql).

### FN_OT_TAXA_CONCLUSAO_TRIBO — indicador

```sql
FUNCTION fn_ot_taxa_conclusao_tribo (p_tribo_id IN VARCHAR2) RETURN NUMBER
```

**O que mede.** O percentual de missões de uma tribo que terminaram `CONCLUIDA`, sobre o total das
que já terminaram (`CONCLUIDA`, `CANCELADA`, `EXPIRADA`). É o indicador de saúde do bairro: tribo
que publica muito e conclui pouco está deixando missão expirar, e pote expirado é token que voltou
sem ter remunerado ninguém.

**Decisões.**
- Missão em aberto não entra no denominador. Ela ainda não fracassou nem deu certo, e contá-la
  puniria a tribo por ter trabalho em andamento.
- Tribo sem missão encerrada devolve `NULL`, não `0`. "0% de conclusão" é desempenho ruim; "não há
  o que dividir" é ausência de dado. O `ZERO_DIVIDE` da divisão é capturado e convertido em `NULL`.
- Tribo inexistente levanta `-20010`. Devolver `NULL` aqui confundiria "não existe" com "ainda não
  encerrou nada".

**Uso prático.** Ranking de tribos:

```sql
SELECT t.nome, fn_ot_taxa_conclusao_tribo(t.id) AS taxa
  FROM ot_tribo t
 ORDER BY fn_ot_taxa_conclusao_tribo(t.id) DESC NULLS LAST;
```

### FN_OT_DIVERGENCIA_CARTEIRA — indicador

```sql
FUNCTION fn_ot_divergencia_carteira (p_carteira_id IN VARCHAR2) RETURN NUMBER
```

**O que mede.** A diferença entre o saldo que a carteira mostra e a soma do livro-razão. O saldo em
`OT_CARTEIRA` é uma projeção atualizada a cada movimento; a verdade é a soma dos lançamentos. Zero
significa íntegra.

No sistema de origem este cálculo é o endpoint `GET /admin/carteiras/reconciliacao`
(`ReconciliacaoService`). Aqui ele vira uma função que qualquer consulta pode chamar.

**Limite declarado.** Isto é reconciliação, não conservação. Todas as carteiras podem estar íntegras
enquanto um pote fica preso numa missão parada — são invariantes diferentes. Quem trata o segundo
caso é `PRC_OT_VARRER_MISSOES_PARADAS`.

**Uso prático.** Auditoria:

```sql
SELECT u.handle, fn_ot_divergencia_carteira(c.id) AS divergencia
  FROM ot_carteira c JOIN ot_usuario u ON u.id = c.usuario_id
 WHERE fn_ot_divergencia_carteira(c.id) <> 0;      -- nenhuma linha = tudo íntegro
```

### FN_OT_RESUMO_MISSAO — dados formatados

```sql
FUNCTION fn_ot_resumo_missao (p_missao_id IN VARCHAR2) RETURN VARCHAR2
```

**O que devolve.** Uma linha legível com o que está espalhado em oito colunas:

```
[Em andamento] Mutirão: reforma da quadra da rua Tapes · Tribo · 120 XP + 40 tokens · Cidade Líder/SP · há 3 dias · pote: 40 tokens
```

O estado é traduzido por `CASE`, o tempo no estado atual é calculado a partir de `ESTADO_DESDE` com
`IF/ELSIF` (dias, horas ou "menos de 1 h"), e o trecho do pote só aparece quando há token parado.

**Decisão.** Para id desconhecido a função devolve `[Missão não encontrada] <id>` em vez de levantar
erro. Ela é usada em coluna de `SELECT`, e uma linha órfã não deve derrubar a consulta inteira. É o
contrário da escolha feita nas duas funções de indicador, onde um número errado seria pior que um
erro.

**Uso prático.** Listagem dos potes imobilizados:

```sql
SELECT fn_ot_resumo_missao(m.id)
  FROM ot_missao m
 WHERE m.status IN ('EM_ANDAMENTO', 'AGUARDANDO_CONFIRMACAO', 'EM_DISPUTA')
   AND m.pote_tokens > 0;
```

### FN_OT_FORMATAR_TOKENS e FN_OT_NOVO_ID — apoio

`FN_OT_FORMATAR_TOKENS(p_tokens IN NUMBER) RETURN VARCHAR2` devolve `1.234 tokens`, `1 token` ou
`—` para nulo. O separador de milhar é fixado na chamada: depender do NLS da sessão faria o mesmo
relatório sair diferente em cada máquina.

`FN_OT_NOVO_ID RETURN VARCHAR2` gera um identificador no formato dos ids vindos do PostgreSQL, para
que linha criada pelas procedures e linha vinda do seed tenham o mesmo tipo.

## Procedures

**Nenhuma procedure faz `COMMIT`.** A transação é de quem chama: o Java confirma ou desfaz junto com
o resto da requisição, e os scripts de teste e de uso terminam em `ROLLBACK` e por isso podem ser
repetidos. É a mesma regra do sistema de origem, onde toda operação de valor roda na transação de
quem a chamou.

### PRC_OT_VARRER_MISSOES_PARADAS — rotina automatizada

```sql
PROCEDURE prc_ot_varrer_missoes_paradas (
    p_prazo_execucao_h     IN  NUMBER DEFAULT 48,
    p_prazo_confirmacao_h  IN  NUMBER DEFAULT 72,
    p_agora                IN  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    p_expiradas            OUT NUMBER,
    p_concluidas           OUT NUMBER,
    p_tokens_estornados    OUT NUMBER,
    p_falhas               OUT NUMBER)
```

**Propósito.** Todo estado não-terminal precisa de uma saída que não dependa de uma pessoa
específica aparecer. Sem esta rotina, o token de quem financiou o pote fica imobilizado para sempre
quando o executor ou o criador somem. No sistema de origem é um job agendado
(`ExpiracaoMissoesService`, a cada 5 minutos); aqui é a mesma regra dentro do banco.

**O que decide.**

| Situação | Desfecho | Token |
|---|---|---|
| `ABERTA` com a janela fechada | `EXPIRADA` | Pote volta aos financiadores |
| `EM_ANDAMENTO` além do prazo de execução | `EXPIRADA` | Pote volta aos financiadores |
| `AGUARDANDO_CONFIRMACAO` além do prazo | `CONCLUIDA` | **Executor é pago** |

Os desfechos diferem de propósito. Quem abandona sem check-in não entregou nada, então o dinheiro
volta. Quando o executor já fez o check-in geolocalizado e é o criador quem some, o check-in é a
prova que o sistema aceita em qualquer outro caminho; punir o executor pela omissão alheia seria o
defeito. A procedure confere que existe check-in **válido** antes de pagar.

**Funcionamento.**

1. O cursor `c_paradas`, com `FOR UPDATE`, trava as missões vencidas na ordem em que venceram.
2. Cada missão é tratada depois de um `SAVEPOINT` próprio.
3. No estorno, o cursor parametrizado `c_financiamentos` percorre os lançamentos de financiamento
   da missão — dos **dois** motivos, `FINANCIAMENTO_TRIBO` e `FINANCIAMENTO_PATROCINADOR` — e
   credita um `ESTORNO` a cada financiador. As carteiras são travadas em ordem de id, que é o que
   evita deadlock entre duas rotinas que mexem nas mesmas duas.
4. Se a soma devolvida não é exatamente o que estava no pote, a missão levanta `-20021`.
5. Qualquer erro da missão é capturado: ela é desfeita até o savepoint, contada em `p_falhas` e
   registrada em `OT_ALERTA` com prioridade máxima. **A varredura segue** com as demais.
6. Cada desfecho grava a trilha em `OT_MISSAO_EVENTO` (com `ATOR_ID` nulo: quem agiu foi o sistema)
   e os alertas dos envolvidos.

**Sobre o `WHEN OTHERS`.** Ele aparece uma vez, no laço, e não engole nada: o erro é desfeito,
contado, gravado e impresso. O que não pode acontecer é uma missão corrompida impedir o estorno de
todas as que vêm depois. O cenário C6 da carga existe para provar isso.

**Alertas registrados.** `ESTORNO_RECEBIDO` (um por financiador), `MISSAO_EXPIRADA` (ao criador),
`MISSAO_CONCLUIDA` (ao executor) e `VARREDURA_FALHOU` (operacional, sem destinatário).

**Conservação.** O estorno e o pagamento a partir do pote só movem token de lugar: a soma
`carteiras + potes` não muda. A única exceção é a missão de fonte `CUNHAGEM`, que não tem pote e
emite na conclusão — comportamento do sistema de origem, mantido.

**Idempotência.** A missão tratada sai do conjunto vencido, e cada lançamento leva uma chave
determinística (`estorno:<missão>:<financiamento>`, `conclusao:<missão>:<executor>`) protegida por
`UNIQUE`. Rodar duas vezes não duplica nada.

### PRC_OT_RESGATAR_BENEFICIO — acionada pelo Java

```sql
PROCEDURE prc_ot_resgatar_beneficio (
    p_usuario_id       IN  VARCHAR2,
    p_beneficio_id     IN  VARCHAR2,
    p_chave            IN  VARCHAR2,
    p_resgate_id       OUT VARCHAR2,
    p_codigo_retirada  OUT VARCHAR2,
    p_saldo_apos       OUT NUMBER,
    p_replay           OUT NUMBER)
```

**Propósito.** Trocar token por um benefício de parceiro do bairro. É o **sumidouro** da economia: o
lançamento debita com motivo `RESGATE` e não credita ninguém. Sem sumidouro, todo token emitido se
acumularia para sempre. Espelha `ResgateService.resgatar` do sistema de origem.

**Funcionamento.**

1. Confere que o benefício é resgatável. Inexistente, inativo e de parceiro inativo levantam o
   **mesmo** erro `-20031`: distinguir os três contaria a quem pergunta quais ids existem.
2. Trava a carteira com `SELECT … FOR UPDATE`. Dois resgates simultâneos do mesmo usuário entram em
   fila aqui, e o segundo lê o saldo já debitado.
3. Procura a chave de idempotência. Se já existe, devolve o resgate **anterior** com `p_replay = 1`
   e não debita de novo. É a proteção contra o toque duplo no botão e a retentativa de rede.
4. Confere o saldo (`-20033` se insuficiente).
5. Gera o código de retirada num `LOOP` de até 3 tentativas, com alfabeto sem `0`, `O`, `1` e `I`.
6. Debita, grava o lançamento e grava o resgate com o mesmo id.

**Duas decisões de segurança.**
- A chave é guardada como `resgate:<usuário>:<chave do cliente>`, nunca crua. A `UNIQUE` é global,
  e com a chave crua o cliente que mandasse `"1"` receberia de volta o resgate de outra pessoa.
- O código de retirada não é credencial — quem autoriza a baixa é o administrador, pelo id. Por
  isso `DBMS_RANDOM` basta; para segredo de verdade ele não serviria.

**Erros.** `-20030` chave ausente ou longa, `-20031` benefício indisponível, `-20032` usuário sem
carteira, `-20033` saldo insuficiente, `-20034` código único não gerado, `-20035` conflito de
concorrência.

### PRC_OT_RELATORIO_TRIBO — relatório resumido por usuário

```sql
PROCEDURE prc_ot_relatorio_tribo (
    p_tribo_id       IN  VARCHAR2,
    p_membros        OUT NUMBER,
    p_tokens_ganhos  OUT NUMBER)
```

**Propósito.** Resumir a movimentação de token de cada membro de uma tribo: quanto ganhou executando
missão, quanto financiou do próprio bolso, quanto resgatou e quanto tem. Responde à pergunta que a
tese do produto faz: o cuidado está circulando, ou está parado na carteira de poucos?

**Funcionamento.** Um cursor explícito (`OPEN`, `FETCH`, `EXIT WHEN %NOTFOUND`, `CLOSE`) percorre os
membros ativos. Para cada um, a procedure soma os lançamentos por motivo, grava uma linha em
`OT_RELATORIO_TRIBO` e imprime a linha formatada por `DBMS_OUTPUT`. A fotografia anterior da tribo é
substituída.

O financiamento é **líquido de estorno**: token que voltou não foi, no fim, financiado.

**Erros.** `-20040` se a tribo não existe. Qualquer erro no meio fecha o cursor (`%ISOPEN`) antes de
propagar — cursor explícito não fecha sozinho quando a exceção sai do bloco.

## Integração com o Java

Aplicação em [`java/`](../java/), Spring Boot, independente de `services/api`.

```
POST /oracle/resgates  ──►  OracleController  ──►  RotinasService (@Transactional)
                                                        │
                                                        ▼
                                          RotinasOracle (CallableStatement)
                                                        │  { call prc_ot_resgatar_beneficio(…) }
                                                        ▼
                                                     Oracle
```

| Endpoint | Rotina PL/SQL | Resposta |
|---|---|---|
| `POST /oracle/resgates` (cabeçalho `Idempotency-Key`) | `PRC_OT_RESGATAR_BENEFICIO` | 201 na primeira vez, 200 no replay |
| `POST /oracle/varredura` | `PRC_OT_VARRER_MISSOES_PARADAS` | 200 com os quatro contadores |
| `GET /oracle/indicadores` | as três functions, dentro de `SELECT` | 200 |

Pontos do código Java que valem leitura:

- [`RotinasOracle`](../java/src/main/java/com/omnitribo/oracle/RotinasOracle.java) usa
  `CallableStatement` à mão, com `IN` bindado e `OUT` registrado. Nenhum SQL é montado por
  concatenação.
- [`RotinasService`](../java/src/main/java/com/omnitribo/oracle/RotinasService.java) delimita a
  transação. Como as procedures não confirmam, é o `@Transactional` que faz o `COMMIT` no retorno e
  o `ROLLBACK` quando o PL/SQL levanta erro.
- [`ErroOracle`](../java/src/main/java/com/omnitribo/oracle/ErroOracle.java) traduz cada código
  `-200xx` em status HTTP e devolve só o texto que a procedure escreveu. Erro não mapeado responde
  500 genérico: mensagem de driver, nome de schema e pilha `ORA-06512` não chegam ao cliente.

| Código PL/SQL | HTTP |
|---|---|
| `-20020`, `-20030` | 400 |
| `-20031`, `-20032` | 404 |
| `-20033` | 422 |
| `-20035` | 409 |
| qualquer outro | 500, sem detalhe |

**Limitação declarada.** Em `POST /oracle/resgates` o usuário vem no corpo, porque esta demonstração
não tem autenticação. No sistema real a identidade vem sempre do JWT.

## Relação com o sistema de origem

As três procedures implementam regras que já existem em Java e rodam sobre uma cópia dos dados. Elas
mostram **a mesma regra implementada na camada de banco**; o sistema em produção continua usando o
PostgreSQL e os serviços Java.

| PL/SQL | Equivalente em `services/api` |
|---|---|
| `PRC_OT_VARRER_MISSOES_PARADAS` | `missoes/dominio/ExpiracaoMissoesService` + `EstornoFinanciamentoService` |
| `PRC_OT_RESGATAR_BENEFICIO` | `carteira/dominio/ResgateService.resgatar` |
| `FN_OT_DIVERGENCIA_CARTEIRA` | `carteira/dominio/ReconciliacaoService` |
| Nível em `concluir_por_prazo` | `identidade/dominio/RegraNivel.nivelPara` |

O que **não** foi trazido, e por quê: o cálculo de recompensa (a fórmula é versionada e calibrada
por configuração no Java, e uma cópia aqui divergiria na primeira mudança de parâmetro) e a
validação de check-in (depende do PostGIS e do antifraude cinemático).
