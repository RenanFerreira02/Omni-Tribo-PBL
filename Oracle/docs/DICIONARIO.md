# Dicionário de dados — camada Oracle

Tabelas criadas por [`sql/01_tabelas.sql`](../sql/01_tabelas.sql). O diagrama está em
[DER.md](DER.md). Os comentários abaixo também estão gravados no banco (`USER_TAB_COMMENTS`,
`USER_COL_COMMENTS`).

## Conversão PostgreSQL → Oracle

O modelo é a projeção do schema PostgreSQL do projeto
(`services/api/src/main/resources/db/migration`). As regras de tipo foram mantidas:

| No PostgreSQL | No Oracle | Regra preservada |
|---|---|---|
| `UUID` | `VARCHAR2(36)` | O id original é mantido, então toda linha é rastreável até o seed. |
| `BIGINT` (token) | `NUMBER(19)` | Token é inteiro. Nunca decimal, nunca texto. |
| `TIMESTAMPTZ` | `TIMESTAMP WITH TIME ZONE` | Nunca data sem fuso. |
| `BOOLEAN` | `NUMBER(1)` + `CHECK (… IN (0,1))` | `BOOLEAN` em SQL só existe a partir do Oracle 23ai. |
| `VARCHAR` + `CHECK` (enum) | `VARCHAR2` + `CHECK` | Enum por nome, nunca por ordinal. |
| `TEXT` | `VARCHAR2(n CHAR)` | Tamanho em caracteres, não em bytes, por causa dos acentos. |
| `GEOGRAPHY(POINT,4326)` | não vem | O geoespacial continua no PostGIS. |
| `REVOKE UPDATE, DELETE` | trigger `BEFORE UPDATE OR DELETE` | Tabela append-only. No Oracle o dono das tabelas é quem executa, e não se revoga privilégio do dono. |

## Tabelas

### OT_TRIBO — a comunidade de um bairro

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `ID` | `VARCHAR2(36)` | não | PK |
| `NOME` | `VARCHAR2(100 CHAR)` | não | Nome da tribo |
| `BAIRRO` | `VARCHAR2(100 CHAR)` | não | Bairro que ela cobre |
| `CRIADA_EM` | `TIMESTAMP WITH TIME ZONE` | não | |

### OT_USUARIO — morador

Origem: `usuario`, **sem** `email`, `senha_hash`, `streak`, `rating` e colunas de controle.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `ID` | `VARCHAR2(36)` | não | PK |
| `NOME` | `VARCHAR2(100 CHAR)` | não | |
| `HANDLE` | `VARCHAR2(50 CHAR)` | não | O `@` do morador. UNIQUE |
| `TRIBO_ID` | `VARCHAR2(36)` | sim | FK → `OT_TRIBO`. Nulo para apoiador e conta de sistema |
| `XP` | `NUMBER(19)` | não | Reputação. Monotônico, `CHECK (xp >= 0)` |
| `NIVEL` | `NUMBER(5)` | não | **Derivado** do XP: `1 + piso(raiz(xp / 100))` |
| `PAPEL` | `VARCHAR2(20)` | não | `USUARIO`, `ADMIN` ou `PATROCINADOR` (o apoiador do bairro) |
| `STATUS` | `VARCHAR2(10)` | não | `ATIVO`, `INATIVO`, `SUSPENSO` ou `BANIDO` |
| `CRIADO_EM` | `TIMESTAMP WITH TIME ZONE` | não | |

### OT_CARTEIRA — saldo de token

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `ID` | `VARCHAR2(36)` | não | PK |
| `USUARIO_ID` | `VARCHAR2(36)` | não | FK → `OT_USUARIO`. UNIQUE: uma carteira por usuário |
| `SALDO_TOKENS` | `NUMBER(19)` | não | **Projeção** do livro-razão. `CHECK (saldo_tokens >= 0)` |

### OT_LANCAMENTO — livro-razão, append-only

A verdade sobre o saldo. `UPDATE` e `DELETE` são rejeitados pelo trigger
`TRG_OT_LANCAMENTO_IMUTAVEL`; correção é por lançamento de `ESTORNO`.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `ID` | `VARCHAR2(36)` | não | PK |
| `CARTEIRA_ID` | `VARCHAR2(36)` | não | FK → `OT_CARTEIRA` |
| `SINAL` | `VARCHAR2(7)` | não | `CREDITO` ou `DEBITO` |
| `MOTIVO` | `VARCHAR2(30)` | não | Ver tabela abaixo |
| `VALOR_TOKENS` | `NUMBER(19)` | não | Sempre positivo; o sinal está em `SINAL` |
| `MISSAO_ID` | `VARCHAR2(36)` | sim | Missão relacionada. **Sem FK**, de propósito |
| `CONTRAPARTE_CARTEIRA_ID` | `VARCHAR2(36)` | sim | FK → `OT_CARTEIRA`. Preenchida em transferência |
| `CHAVE_IDEMPOTENCIA` | `VARCHAR2(200)` | não | UNIQUE global. Repetir a operação não gera segundo lançamento |
| `SALDO_APOS_TOKENS` | `NUMBER(19)` | não | Saldo da carteira logo depois deste lançamento |
| `MENSAGEM` | `VARCHAR2(200 CHAR)` | sim | |
| `CRIADO_EM` | `TIMESTAMP WITH TIME ZONE` | não | |

| `MOTIVO` | Sinal | Efeito na economia |
|---|---|---|
| `APORTE_PATROCINADOR` | crédito | **Emite** token: credita o apoiador sem debitar ninguém |
| `BONUS` | crédito | Emissão histórica do seed |
| `FINANCIAMENTO_TRIBO` | débito | Membro põe token no pote de uma missão |
| `FINANCIAMENTO_PATROCINADOR` | débito | Apoiador põe token no pote de uma missão |
| `RECOMPENSA_MISSAO` | crédito | Executor recebe: do pote, ou emitido quando a fonte é `CUNHAGEM` |
| `ESTORNO` | crédito | Pote devolvido ao financiador |
| `TRANSFERENCIA_ENVIADA` / `_RECEBIDA` | débito / crédito | Move token entre membros da mesma tribo |
| `RESGATE` | débito | **Queima** token: debita sem creditar ninguém |

### OT_MISSAO — missão de vizinhança

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `ID` | `VARCHAR2(36)` | não | PK |
| `CRIADOR_ID` | `VARCHAR2(36)` | não | FK → `OT_USUARIO` |
| `EXECUTOR_ID` | `VARCHAR2(36)` | sim | FK → `OT_USUARIO`. Nulo enquanto ninguém aceitou |
| `CATEGORIA` | `VARCHAR2(10)` | não | `ENTREGA`, `COLETA`, `TRIBO` ou `AJUDA` |
| `TITULO` | `VARCHAR2(200 CHAR)` | não | |
| `STATUS` | `VARCHAR2(30)` | não | `RASCUNHO`, `ABERTA`, `ACEITA`, `EM_ANDAMENTO`, `AGUARDANDO_CONFIRMACAO`, `EM_DISPUTA`, `CONCLUIDA`, `CANCELADA`, `EXPIRADA` |
| `XP_RECOMPENSA` | `NUMBER(10)` | não | Congelado na criação |
| `TOKENS_RECOMPENSA` | `NUMBER(19)` | não | Congelado na criação |
| `POTE_TOKENS` | `NUMBER(19)` | não | Token depositado e ainda não pago nem estornado |
| `FONTE_POTE` | `VARCHAR2(12)` | não | `COMUNIDADE` paga do pote; `CUNHAGEM` emite na conclusão; `PATROCINADOR` é histórico |
| `COMPLEXIDADE` | `VARCHAR2(7)` | sim | `LEVE`, `MEDIA` ou `PESADA` |
| `BAIRRO`, `CIDADE`, `UF` | `VARCHAR2` | não | Local, sem coordenada |
| `JANELA_INICIO`, `JANELA_FIM` | `TIMESTAMP WITH TIME ZONE` | não | Período em que a missão pode ser feita |
| `CRIADA_EM` | `TIMESTAMP WITH TIME ZONE` | não | |
| `ACEITA_EM`, `CONCLUIDA_EM` | `TIMESTAMP WITH TIME ZONE` | sim | |
| `ESTADO_DESDE` | `TIMESTAMP WITH TIME ZONE` | não | Instante da última troca de status. Marco da varredura |

### OT_MISSAO_EVENTO — trilha de transições, append-only

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `ID` | `VARCHAR2(36)` | não | PK |
| `MISSAO_ID` | `VARCHAR2(36)` | não | FK → `OT_MISSAO` |
| `TIPO` | `VARCHAR2(30)` | não | O que aconteceu. A varredura grava `EXPIRADA`, `EXECUCAO_EXPIRADA` e `CONFIRMACAO_EXPIRADA` |
| `ATOR_ID` | `VARCHAR2(36)` | sim | Quem agiu. **Nulo = o sistema** |
| `DE_STATUS`, `PARA_STATUS` | `VARCHAR2(30)` | sim | Estado antes e depois |
| `CRIADO_EM` | `TIMESTAMP WITH TIME ZONE` | não | |

### OT_CHECKIN — leitura de GPS, append-only

É a "leitura de sensor" do domínio. A coordenada não é copiada.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `ID` | `VARCHAR2(36)` | não | PK |
| `MISSAO_ID` | `VARCHAR2(36)` | não | Missão. **Sem FK**, de propósito |
| `USUARIO_ID` | `VARCHAR2(36)` | não | FK → `OT_USUARIO` |
| `ACURACIA_M` | `NUMBER(10,2)` | não | Margem de erro informada pelo aparelho, em metros |
| `DISTANCIA_ALVO_M` | `NUMBER(10,2)` | não | Distância até o alvo, calculada pelo PostGIS |
| `METODO` | `VARCHAR2(5)` | não | `GPS` ou `QR` |
| `MOCK_DETECTADO` | `NUMBER(1)` | não | 1 quando o aparelho reportou localização simulada |
| `VELOCIDADE_IMPLICITA_KMH` | `NUMBER(10,2)` | sim | Velocidade entre este check-in e o anterior |
| `VALIDO` | `NUMBER(1)` | não | 1 = leitura aceita como prova de presença |
| `CODIGO_REJEICAO` | `VARCHAR2(40)` | sim | `LOCALIZACAO_SIMULADA`, `ACURACIA_INSUFICIENTE` ou `FORA_DO_RAIO`. Obrigatório quando `VALIDO = 0` |
| `CRIADO_EM` | `TIMESTAMP WITH TIME ZONE` | não | |

### OT_PARCEIRO — comércio do bairro

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `ID` | `VARCHAR2(36)` | não | PK |
| `NOME` | `VARCHAR2(100 CHAR)` | não | |
| `TRIBO_ID` | `VARCHAR2(36)` | sim | FK → `OT_TRIBO` |
| `BAIRRO`, `CIDADE`, `UF` | `VARCHAR2` | não | |
| `ATIVO` | `NUMBER(1)` | não | Parceiro inativo torna seus benefícios indisponíveis |
| `CRIADO_EM` | `TIMESTAMP WITH TIME ZONE` | não | |

### OT_BENEFICIO — item do catálogo de resgate

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `ID` | `VARCHAR2(36)` | não | PK |
| `PARCEIRO_ID` | `VARCHAR2(36)` | não | FK → `OT_PARCEIRO` |
| `TITULO` | `VARCHAR2(120 CHAR)` | não | |
| `DESCRICAO` | `VARCHAR2(500 CHAR)` | não | |
| `CUSTO_TOKENS` | `NUMBER(19)` | não | `CHECK (custo_tokens > 0)` |
| `TIPO` | `VARCHAR2(10)` | não | `BEM` ou `PERCENTUAL` |
| `ATIVO` | `NUMBER(1)` | não | |
| `CRIADO_EM` | `TIMESTAMP WITH TIME ZONE` | não | |

`CK_OT_BENEFICIO_SEM_REAIS` rejeita `R$` e a palavra "reais" em título e descrição. Preço em moeda
corrente publicaria uma cotação token→real, e token conversível é dinheiro (ADR 0009 §6).

### OT_RESGATE — troca de token por benefício

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `ID` | `VARCHAR2(36)` | não | PK **e** FK → `OT_LANCAMENTO`: é o id do débito que o pagou |
| `USUARIO_ID` | `VARCHAR2(36)` | não | FK → `OT_USUARIO` |
| `BENEFICIO_ID` | `VARCHAR2(36)` | não | FK → `OT_BENEFICIO` |
| `CUSTO_TOKENS` | `NUMBER(19)` | não | Custo congelado no momento do resgate |
| `CODIGO_RETIRADA` | `VARCHAR2(8)` | não | UNIQUE. Apresentado no balcão; **não é credencial** |
| `STATUS` | `VARCHAR2(10)` | não | `PENDENTE` ou `UTILIZADO` |
| `CRIADO_EM` | `TIMESTAMP WITH TIME ZONE` | não | |
| `UTILIZADO_EM` | `TIMESTAMP WITH TIME ZONE` | sim | Preenchido se, e só se, `STATUS = 'UTILIZADO'` |

### OT_ALERTA — alertas

Recebe a caixa de entrada do seed e os alertas gravados por `PRC_OT_VARRER_MISSOES_PARADAS`.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `ID` | `VARCHAR2(36)` | não | PK |
| `USUARIO_ID` | `VARCHAR2(36)` | sim | FK → `OT_USUARIO`. **Nulo = alerta operacional**, sem destinatário |
| `TIPO` | `VARCHAR2(50)` | não | Da varredura: `ESTORNO_RECEBIDO`, `MISSAO_EXPIRADA`, `MISSAO_CONCLUIDA`, `VARREDURA_FALHOU` |
| `TITULO` | `VARCHAR2(200 CHAR)` | não | |
| `CORPO` | `VARCHAR2(1000 CHAR)` | não | |
| `MISSAO_ID` | `VARCHAR2(36)` | sim | Missão a que se refere. Sem FK |
| `PRIORIDADE` | `NUMBER(1)` | não | 0 a 2. A falha de varredura grava 2 |
| `LIDO` | `NUMBER(1)` | não | |
| `CRIADO_EM` | `TIMESTAMP WITH TIME ZONE` | não | |

### OT_RELATORIO_TRIBO — saída do relatório

Gravada por `PRC_OT_RELATORIO_TRIBO`. Cada execução substitui a fotografia anterior da tribo.

| Coluna | Tipo | Nulo | Descrição |
|---|---|---|---|
| `TRIBO_ID` | `VARCHAR2(36)` | não | PK (com `USUARIO_ID`), FK → `OT_TRIBO` |
| `USUARIO_ID` | `VARCHAR2(36)` | não | PK (com `TRIBO_ID`), FK → `OT_USUARIO` |
| `HANDLE` | `VARCHAR2(50 CHAR)` | não | |
| `MISSOES_CONCLUIDAS` | `NUMBER(10)` | não | Missões que o membro executou até `CONCLUIDA` |
| `TOKENS_GANHOS` | `NUMBER(19)` | não | Soma de `RECOMPENSA_MISSAO` |
| `TOKENS_FINANCIADOS` | `NUMBER(19)` | não | Financiamentos **menos** estornos |
| `TOKENS_RESGATADOS` | `NUMBER(19)` | não | Soma de `RESGATE` |
| `SALDO_TOKENS` | `NUMBER(19)` | não | Saldo no instante do relatório |
| `GERADO_EM` | `TIMESTAMP WITH TIME ZONE` | não | |

## Triggers

| Trigger | Tabela | Efeito |
|---|---|---|
| `TRG_OT_LANCAMENTO_IMUTAVEL` | `OT_LANCAMENTO` | Rejeita `UPDATE` e `DELETE` com `ORA-20090` |
| `TRG_OT_MISSAO_EVENTO_IMUTAVEL` | `OT_MISSAO_EVENTO` | Rejeita `UPDATE` e `DELETE` com `ORA-20091` |
| `TRG_OT_CHECKIN_IMUTAVEL` | `OT_CHECKIN` | Rejeita `UPDATE` e `DELETE` com `ORA-20092` |

## Dados carregados

| Arquivo | Origem | Conteúdo |
|---|---|---|
| [`02_carga_seed.sql`](../sql/02_carga_seed.sql) | Exportado do PostgreSQL do projeto por [`dados/exportar_do_postgres.sh`](../dados/exportar_do_postgres.sh) | 4 tribos, 14 usuários, 13 carteiras, 18 lançamentos, 20 missões, 4 parceiros, 7 benefícios, 7 alertas |
| [`03_carga_cenarios.sql`](../sql/03_carga_cenarios.sql) | **Simulado**, escrito à mão | 6 missões paradas, 5 check-ins (2 válidos, 3 rejeitados), 5 financiamentos, 2 resgates |

Todo id simulado começa com `f6`. As datas do seed são gravadas como deslocamento a partir do
instante da instalação, então o banco sempre nasce com a aparência de seed recém-aplicado.
