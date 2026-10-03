-- =============================================================================================
-- Omni-Tribo · PBL Fase 6 · 01_tabelas.sql
-- Modelo físico Oracle das entidades principais do sistema.
--
-- De onde vem: é a projeção do schema PostgreSQL do projeto (services/api/.../db/migration),
-- com as mesmas regras de integridade. O que muda de um banco para o outro está em
-- Oracle/docs/DICIONARIO.md; o resumo é:
--
--   UUID            -> VARCHAR2(36)   o id original é preservado, então toda linha é rastreável
--                                     até o seed de onde saiu
--   BIGINT (token)  -> NUMBER(19)     token é INTEIRO. Nunca decimal, nunca texto
--   TIMESTAMPTZ     -> TIMESTAMP WITH TIME ZONE
--   BOOLEAN         -> NUMBER(1) + CHECK (0,1)   BOOLEAN em SQL só existe a partir do 23ai
--   enum            -> VARCHAR2 + CHECK          nunca ordinal
--   GEOGRAPHY       -> não vem                   o geoespacial continua no PostGIS
--
-- Todo objeto leva o prefixo OT_: o schema do aluno é compartilhado com outras disciplinas, e o
-- prefixo é o que permite ao 00_desinstalar.sql apagar só o que é deste projeto.
--
-- Governança: e-mail, hash de senha e coordenada de check-in NÃO sobem para cá. Esta camada é
-- analítica, e dado pessoal que não serve à análise não é copiado.
-- =============================================================================================

-- _____________________________________________________________________________________________
-- Identidade
-- _____________________________________________________________________________________________
CREATE TABLE ot_tribo (
    id         VARCHAR2(36)              NOT NULL,
    nome       VARCHAR2(100 CHAR)        NOT NULL,
    bairro     VARCHAR2(100 CHAR)        NOT NULL,
    criada_em  TIMESTAMP WITH TIME ZONE  DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_ot_tribo PRIMARY KEY (id)
);

CREATE TABLE ot_usuario (
    id         VARCHAR2(36)              NOT NULL,
    nome       VARCHAR2(100 CHAR)        NOT NULL,
    handle     VARCHAR2(50 CHAR)         NOT NULL,
    tribo_id   VARCHAR2(36),
    xp         NUMBER(19)                DEFAULT 0 NOT NULL,
    nivel      NUMBER(5)                 DEFAULT 1 NOT NULL,
    papel      VARCHAR2(20)              NOT NULL,
    status     VARCHAR2(10)              NOT NULL,
    criado_em  TIMESTAMP WITH TIME ZONE  DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_ot_usuario        PRIMARY KEY (id),
    CONSTRAINT uk_ot_usuario_handle UNIQUE (handle),
    CONSTRAINT fk_ot_usuario_tribo  FOREIGN KEY (tribo_id) REFERENCES ot_tribo (id),
    CONSTRAINT ck_ot_usuario_papel  CHECK (papel IN ('USUARIO', 'ADMIN', 'PATROCINADOR')),
    CONSTRAINT ck_ot_usuario_status CHECK (status IN ('ATIVO', 'INATIVO', 'SUSPENSO', 'BANIDO')),
    -- XP é monotônico e nunca negativo; o nível é derivado dele (1 + piso(raiz(xp/100))).
    CONSTRAINT ck_ot_usuario_xp     CHECK (xp >= 0),
    CONSTRAINT ck_ot_usuario_nivel  CHECK (nivel >= 1)
);

CREATE INDEX idx_ot_usuario_tribo ON ot_usuario (tribo_id);

-- _____________________________________________________________________________________________
-- Carteira e livro-razão
-- _____________________________________________________________________________________________
-- Só TOKEN. O saldo em reais do sistema de origem não vem: BRL está fora do ciclo de missões
-- (ADR 0009) e trazê-lo sugeriria uma cotação token->real que o projeto recusa.
CREATE TABLE ot_carteira (
    id            VARCHAR2(36)  NOT NULL,
    usuario_id    VARCHAR2(36)  NOT NULL,
    saldo_tokens  NUMBER(19)    DEFAULT 0 NOT NULL,
    CONSTRAINT pk_ot_carteira         PRIMARY KEY (id),
    CONSTRAINT uk_ot_carteira_usuario UNIQUE (usuario_id),
    CONSTRAINT fk_ot_carteira_usuario FOREIGN KEY (usuario_id) REFERENCES ot_usuario (id),
    -- A barreira final contra saldo negativo é o banco, não a procedure.
    CONSTRAINT ck_ot_carteira_saldo   CHECK (saldo_tokens >= 0)
);

-- O saldo da carteira é uma PROJEÇÃO; a verdade é a soma deste livro. FN_OT_DIVERGENCIA_CARTEIRA
-- compara os dois.
CREATE TABLE ot_lancamento (
    id                       VARCHAR2(36)              NOT NULL,
    carteira_id              VARCHAR2(36)              NOT NULL,
    sinal                    VARCHAR2(7)               NOT NULL,
    motivo                   VARCHAR2(30)              NOT NULL,
    valor_tokens             NUMBER(19)                NOT NULL,
    -- Sem FK de propósito, como no sistema de origem: a carteira referencia a missão por id puro
    -- para não acoplar o módulo de carteira ao de missões.
    missao_id                VARCHAR2(36),
    contraparte_carteira_id  VARCHAR2(36),
    chave_idempotencia       VARCHAR2(200)             NOT NULL,
    saldo_apos_tokens        NUMBER(19)                NOT NULL,
    mensagem                 VARCHAR2(200 CHAR),
    criado_em                TIMESTAMP WITH TIME ZONE  DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_ot_lancamento          PRIMARY KEY (id),
    -- É esta UNIQUE que torna a operação idempotente: a segunda tentativa com a mesma chave
    -- levanta DUP_VAL_ON_INDEX em vez de debitar duas vezes.
    CONSTRAINT uk_ot_lancamento_chave    UNIQUE (chave_idempotencia),
    CONSTRAINT fk_ot_lancamento_carteira FOREIGN KEY (carteira_id) REFERENCES ot_carteira (id),
    CONSTRAINT fk_ot_lancamento_contra   FOREIGN KEY (contraparte_carteira_id)
                                         REFERENCES ot_carteira (id),
    CONSTRAINT ck_ot_lancamento_sinal    CHECK (sinal IN ('CREDITO', 'DEBITO')),
    -- Dois motivos não somam zero, e são as duas pontas do ciclo econômico: APORTE_PATROCINADOR
    -- EMITE token e RESGATE QUEIMA. Todos os outros só movem token de lugar (ADR 0027).
    CONSTRAINT ck_ot_lancamento_motivo   CHECK (motivo IN (
        'RECOMPENSA_MISSAO', 'TRANSFERENCIA_ENVIADA', 'TRANSFERENCIA_RECEBIDA',
        'FINANCIAMENTO_TRIBO', 'FINANCIAMENTO_PATROCINADOR', 'APORTE_PATROCINADOR',
        'RESGATE', 'BONUS', 'ESTORNO')),
    CONSTRAINT ck_ot_lancamento_valor    CHECK (valor_tokens > 0),
    CONSTRAINT ck_ot_lancamento_saldo    CHECK (saldo_apos_tokens >= 0)
);

CREATE INDEX idx_ot_lancamento_carteira ON ot_lancamento (carteira_id, criado_em);
CREATE INDEX idx_ot_lancamento_missao   ON ot_lancamento (missao_id, motivo);

-- _____________________________________________________________________________________________
-- Missões
-- _____________________________________________________________________________________________
CREATE TABLE ot_missao (
    id                 VARCHAR2(36)              NOT NULL,
    criador_id         VARCHAR2(36)              NOT NULL,
    executor_id        VARCHAR2(36),
    categoria          VARCHAR2(10)              NOT NULL,
    titulo             VARCHAR2(200 CHAR)        NOT NULL,
    status             VARCHAR2(30)              NOT NULL,
    -- Recompensa calculada pelo servidor e CONGELADA na criação. Nenhuma rotina daqui recalcula.
    xp_recompensa      NUMBER(10)                DEFAULT 0 NOT NULL,
    tokens_recompensa  NUMBER(19)                DEFAULT 0 NOT NULL,
    -- Tokens já depositados por financiadores e ainda não pagos nem devolvidos.
    pote_tokens        NUMBER(19)                DEFAULT 0 NOT NULL,
    -- De onde sai o token da recompensa: COMUNIDADE paga do pote; CUNHAGEM emite na conclusão.
    fonte_pote         VARCHAR2(12)              DEFAULT 'CUNHAGEM' NOT NULL,
    complexidade       VARCHAR2(7),
    bairro             VARCHAR2(100 CHAR)        NOT NULL,
    cidade             VARCHAR2(100 CHAR)        NOT NULL,
    uf                 VARCHAR2(2)               NOT NULL,
    janela_inicio      TIMESTAMP WITH TIME ZONE  NOT NULL,
    janela_fim         TIMESTAMP WITH TIME ZONE  NOT NULL,
    criada_em          TIMESTAMP WITH TIME ZONE  DEFAULT SYSTIMESTAMP NOT NULL,
    aceita_em          TIMESTAMP WITH TIME ZONE,
    concluida_em       TIMESTAMP WITH TIME ZONE,
    -- Instante da última troca de status. É o marco que a varredura usa para medir abandono.
    estado_desde       TIMESTAMP WITH TIME ZONE  DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_ot_missao            PRIMARY KEY (id),
    CONSTRAINT fk_ot_missao_criador    FOREIGN KEY (criador_id)  REFERENCES ot_usuario (id),
    CONSTRAINT fk_ot_missao_executor   FOREIGN KEY (executor_id) REFERENCES ot_usuario (id),
    CONSTRAINT ck_ot_missao_categoria  CHECK (categoria IN ('ENTREGA', 'COLETA', 'TRIBO', 'AJUDA')),
    CONSTRAINT ck_ot_missao_status     CHECK (status IN (
        'RASCUNHO', 'ABERTA', 'ACEITA', 'EM_ANDAMENTO', 'AGUARDANDO_CONFIRMACAO', 'EM_DISPUTA',
        'CONCLUIDA', 'CANCELADA', 'EXPIRADA')),
    CONSTRAINT ck_ot_missao_fonte      CHECK (fonte_pote IN ('COMUNIDADE', 'PATROCINADOR', 'CUNHAGEM')),
    CONSTRAINT ck_ot_missao_complex    CHECK (complexidade IS NULL
                                              OR complexidade IN ('LEVE', 'MEDIA', 'PESADA')),
    CONSTRAINT ck_ot_missao_pote       CHECK (pote_tokens >= 0),
    CONSTRAINT ck_ot_missao_recompensa CHECK (xp_recompensa >= 0 AND tokens_recompensa >= 0)
);

CREATE INDEX idx_ot_missao_status   ON ot_missao (status, estado_desde);
CREATE INDEX idx_ot_missao_criador  ON ot_missao (criador_id);
CREATE INDEX idx_ot_missao_executor ON ot_missao (executor_id);

-- Trilha de transições. Quem mudou o quê, de qual estado para qual, e quando.
CREATE TABLE ot_missao_evento (
    id           VARCHAR2(36)              NOT NULL,
    missao_id    VARCHAR2(36)              NOT NULL,
    tipo         VARCHAR2(30)              NOT NULL,
    -- Nulo quando o ator é o SISTEMA (a varredura por prazo).
    ator_id      VARCHAR2(36),
    de_status    VARCHAR2(30),
    para_status  VARCHAR2(30),
    criado_em    TIMESTAMP WITH TIME ZONE  DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_ot_missao_evento        PRIMARY KEY (id),
    CONSTRAINT fk_ot_missao_evento_missao FOREIGN KEY (missao_id) REFERENCES ot_missao (id),
    CONSTRAINT ck_ot_missao_evento_tipo   CHECK (tipo IN (
        'PUBLICADA', 'ACEITA', 'DESISTIDA', 'INICIADA', 'CHECK_IN_REGISTRADO',
        'CONFIRMADA', 'CONTESTADA', 'DISPUTA_RESOLVIDA', 'CANCELADA', 'EXPIRADA',
        'EXECUCAO_EXPIRADA', 'CONFIRMACAO_EXPIRADA', 'DESTRAVADA_POR_ADMIN'))
);

CREATE INDEX idx_ot_missao_evento_missao ON ot_missao_evento (missao_id, criado_em);

-- _____________________________________________________________________________________________
-- Check-in: a "leitura de sensor" do domínio (GPS do aparelho do executor)
-- _____________________________________________________________________________________________
-- A coordenada NÃO vem. Fica o que a análise precisa: a que distância do alvo, com qual acurácia,
-- e se a leitura foi aceita.
CREATE TABLE ot_checkin (
    id                        VARCHAR2(36)              NOT NULL,
    missao_id                 VARCHAR2(36)              NOT NULL,
    usuario_id                VARCHAR2(36)              NOT NULL,
    acuracia_m                NUMBER(10,2)              NOT NULL,
    distancia_alvo_m          NUMBER(10,2)              NOT NULL,
    metodo                    VARCHAR2(5)               NOT NULL,
    mock_detectado            NUMBER(1)                 DEFAULT 0 NOT NULL,
    velocidade_implicita_kmh  NUMBER(10,2),
    valido                    NUMBER(1)                 NOT NULL,
    codigo_rejeicao           VARCHAR2(40),
    criado_em                 TIMESTAMP WITH TIME ZONE  DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_ot_checkin          PRIMARY KEY (id),
    CONSTRAINT fk_ot_checkin_usuario  FOREIGN KEY (usuario_id) REFERENCES ot_usuario (id),
    CONSTRAINT ck_ot_checkin_metodo   CHECK (metodo IN ('GPS', 'QR')),
    CONSTRAINT ck_ot_checkin_mock     CHECK (mock_detectado IN (0, 1)),
    CONSTRAINT ck_ot_checkin_valido   CHECK (valido IN (0, 1)),
    CONSTRAINT ck_ot_checkin_codigo   CHECK (codigo_rejeicao IS NULL OR codigo_rejeicao IN (
        'LOCALIZACAO_SIMULADA', 'ACURACIA_INSUFICIENTE', 'FORA_DO_RAIO')),
    -- Leitura aceita não tem motivo de rejeição, e leitura rejeitada sempre tem.
    CONSTRAINT ck_ot_checkin_coerente CHECK (
        (valido = 1 AND codigo_rejeicao IS NULL) OR (valido = 0 AND codigo_rejeicao IS NOT NULL))
);

CREATE INDEX idx_ot_checkin_missao ON ot_checkin (missao_id, valido);

-- _____________________________________________________________________________________________
-- Parceiros, benefícios e resgate (o sumidouro do token)
-- _____________________________________________________________________________________________
CREATE TABLE ot_parceiro (
    id         VARCHAR2(36)              NOT NULL,
    nome       VARCHAR2(100 CHAR)        NOT NULL,
    tribo_id   VARCHAR2(36),
    bairro     VARCHAR2(100 CHAR)        NOT NULL,
    cidade     VARCHAR2(100 CHAR)        NOT NULL,
    uf         VARCHAR2(2)               NOT NULL,
    ativo      NUMBER(1)                 DEFAULT 1 NOT NULL,
    criado_em  TIMESTAMP WITH TIME ZONE  DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_ot_parceiro       PRIMARY KEY (id),
    CONSTRAINT fk_ot_parceiro_tribo FOREIGN KEY (tribo_id) REFERENCES ot_tribo (id),
    CONSTRAINT ck_ot_parceiro_ativo CHECK (ativo IN (0, 1))
);

CREATE TABLE ot_beneficio (
    id            VARCHAR2(36)              NOT NULL,
    parceiro_id   VARCHAR2(36)              NOT NULL,
    titulo        VARCHAR2(120 CHAR)        NOT NULL,
    descricao     VARCHAR2(500 CHAR)        NOT NULL,
    custo_tokens  NUMBER(19)                NOT NULL,
    tipo          VARCHAR2(10)              NOT NULL,
    ativo         NUMBER(1)                 DEFAULT 1 NOT NULL,
    criado_em     TIMESTAMP WITH TIME ZONE  DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_ot_beneficio          PRIMARY KEY (id),
    CONSTRAINT fk_ot_beneficio_parceiro FOREIGN KEY (parceiro_id) REFERENCES ot_parceiro (id),
    CONSTRAINT ck_ot_beneficio_custo    CHECK (custo_tokens > 0),
    CONSTRAINT ck_ot_beneficio_tipo     CHECK (tipo IN ('BEM', 'PERCENTUAL')),
    CONSTRAINT ck_ot_beneficio_ativo    CHECK (ativo IN (0, 1)),
    -- Benefício se expressa em BEM ou PERCENTUAL, nunca em reais: preço em moeda corrente
    -- publicaria uma cotação token->real implícita, e token conversível é dinheiro (ADR 0009 §6).
    CONSTRAINT ck_ot_beneficio_sem_reais CHECK (
        NOT REGEXP_LIKE(titulo,    'R\$|(^|[^[:alpha:]])reais?([^[:alpha:]]|$)', 'i')
        AND NOT REGEXP_LIKE(descricao, 'R\$|(^|[^[:alpha:]])reais?([^[:alpha:]]|$)', 'i'))
);

CREATE INDEX idx_ot_beneficio_parceiro ON ot_beneficio (parceiro_id);

-- O id do resgate é o MESMO do lançamento que o debitou: os dois nascem na mesma transação, e é
-- por esse id que um replay reencontra o resgate anterior.
CREATE TABLE ot_resgate (
    id               VARCHAR2(36)              NOT NULL,
    usuario_id       VARCHAR2(36)              NOT NULL,
    beneficio_id     VARCHAR2(36)              NOT NULL,
    -- Custo CONGELADO no momento do resgate; o benefício pode mudar de preço depois.
    custo_tokens     NUMBER(19)                NOT NULL,
    -- Não é credencial: quem autoriza a baixa é o ADMIN, pelo id.
    codigo_retirada  VARCHAR2(8)               NOT NULL,
    status           VARCHAR2(10)              NOT NULL,
    criado_em        TIMESTAMP WITH TIME ZONE  DEFAULT SYSTIMESTAMP NOT NULL,
    utilizado_em     TIMESTAMP WITH TIME ZONE,
    CONSTRAINT pk_ot_resgate           PRIMARY KEY (id),
    CONSTRAINT uk_ot_resgate_codigo    UNIQUE (codigo_retirada),
    CONSTRAINT fk_ot_resgate_usuario   FOREIGN KEY (usuario_id)   REFERENCES ot_usuario (id),
    CONSTRAINT fk_ot_resgate_beneficio FOREIGN KEY (beneficio_id) REFERENCES ot_beneficio (id),
    CONSTRAINT fk_ot_resgate_lanc      FOREIGN KEY (id)           REFERENCES ot_lancamento (id),
    CONSTRAINT ck_ot_resgate_custo     CHECK (custo_tokens > 0),
    CONSTRAINT ck_ot_resgate_status    CHECK (status IN ('PENDENTE', 'UTILIZADO')),
    CONSTRAINT ck_ot_resgate_coerente  CHECK (
        (status = 'UTILIZADO' AND utilizado_em IS NOT NULL)
        OR (status = 'PENDENTE' AND utilizado_em IS NULL))
);

CREATE INDEX idx_ot_resgate_usuario ON ot_resgate (usuario_id, criado_em);

-- _____________________________________________________________________________________________
-- Saídas das rotinas PL/SQL
-- _____________________________________________________________________________________________
-- Alertas gravados pelas procedures. usuario_id nulo = alerta operacional, sem destinatário.
CREATE TABLE ot_alerta (
    id          VARCHAR2(36)              NOT NULL,
    usuario_id  VARCHAR2(36),
    tipo        VARCHAR2(50)              NOT NULL,
    titulo      VARCHAR2(200 CHAR)        NOT NULL,
    corpo       VARCHAR2(1000 CHAR)       NOT NULL,
    missao_id   VARCHAR2(36),
    prioridade  NUMBER(1)                 DEFAULT 0 NOT NULL,
    lido        NUMBER(1)                 DEFAULT 0 NOT NULL,
    criado_em   TIMESTAMP WITH TIME ZONE  DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT pk_ot_alerta            PRIMARY KEY (id),
    CONSTRAINT fk_ot_alerta_usuario    FOREIGN KEY (usuario_id) REFERENCES ot_usuario (id),
    CONSTRAINT ck_ot_alerta_prioridade CHECK (prioridade BETWEEN 0 AND 2),
    CONSTRAINT ck_ot_alerta_lido       CHECK (lido IN (0, 1))
);

CREATE INDEX idx_ot_alerta_usuario ON ot_alerta (usuario_id, lido);

-- Fotografia gerada por PRC_OT_RELATORIO_TRIBO. Cada execução substitui a anterior da tribo.
CREATE TABLE ot_relatorio_tribo (
    tribo_id            VARCHAR2(36)              NOT NULL,
    usuario_id          VARCHAR2(36)              NOT NULL,
    handle              VARCHAR2(50 CHAR)         NOT NULL,
    missoes_concluidas  NUMBER(10)                NOT NULL,
    tokens_ganhos       NUMBER(19)                NOT NULL,
    tokens_financiados  NUMBER(19)                NOT NULL,
    tokens_resgatados   NUMBER(19)                NOT NULL,
    saldo_tokens        NUMBER(19)                NOT NULL,
    gerado_em           TIMESTAMP WITH TIME ZONE  NOT NULL,
    CONSTRAINT pk_ot_relatorio_tribo         PRIMARY KEY (tribo_id, usuario_id),
    CONSTRAINT fk_ot_relatorio_tribo_tribo   FOREIGN KEY (tribo_id)   REFERENCES ot_tribo (id),
    CONSTRAINT fk_ot_relatorio_tribo_usuario FOREIGN KEY (usuario_id) REFERENCES ot_usuario (id)
);

-- _____________________________________________________________________________________________
-- Append-only
-- _____________________________________________________________________________________________
-- No PostgreSQL de origem a regra é um REVOKE UPDATE, DELETE sobre o usuário da aplicação. Aqui o
-- dono das tabelas e quem executa são o mesmo usuário, e não dá para revogar privilégio do dono —
-- então a regra vira trigger. Correção de lançamento é por ESTORNO, nunca por UPDATE.
CREATE OR REPLACE TRIGGER trg_ot_lancamento_imutavel
    BEFORE UPDATE OR DELETE ON ot_lancamento
BEGIN
    RAISE_APPLICATION_ERROR(-20090,
        'OT_LANCAMENTO e append-only: corrija por ESTORNO, nunca por UPDATE ou DELETE.');
END;
/

CREATE OR REPLACE TRIGGER trg_ot_missao_evento_imutavel
    BEFORE UPDATE OR DELETE ON ot_missao_evento
BEGIN
    RAISE_APPLICATION_ERROR(-20091, 'OT_MISSAO_EVENTO e append-only: a trilha nao e reescrita.');
END;
/

CREATE OR REPLACE TRIGGER trg_ot_checkin_imutavel
    BEFORE UPDATE OR DELETE ON ot_checkin
BEGIN
    RAISE_APPLICATION_ERROR(-20092, 'OT_CHECKIN e append-only: a leitura registrada nao muda.');
END;
/

-- _____________________________________________________________________________________________
-- Documentação no dicionário de dados (aparece em USER_TAB_COMMENTS e no SQL Developer)
-- _____________________________________________________________________________________________
COMMENT ON TABLE ot_tribo           IS 'Tribo: a comunidade de um bairro. Transferencia de token so acontece dentro dela.';
COMMENT ON TABLE ot_usuario         IS 'Morador. Sem e-mail e sem hash de senha: esta camada e analitica e nao copia credencial.';
COMMENT ON TABLE ot_carteira        IS 'Saldo de token por usuario. E uma PROJECAO do livro-razao OT_LANCAMENTO.';
COMMENT ON TABLE ot_lancamento      IS 'Livro-razao de token, append-only. A soma por carteira tem de bater com OT_CARTEIRA.SALDO_TOKENS.';
COMMENT ON TABLE ot_missao          IS 'Missao de vizinhanca. Recompensa congelada na criacao; so o estado CONCLUIDA credita.';
COMMENT ON TABLE ot_missao_evento   IS 'Trilha append-only das transicoes de estado da missao.';
COMMENT ON TABLE ot_checkin         IS 'Leitura de GPS do executor, sem a coordenada. E a prova de presenca que a conclusao por prazo aceita.';
COMMENT ON TABLE ot_parceiro        IS 'Comercio do bairro que oferece beneficio em troca de token.';
COMMENT ON TABLE ot_beneficio       IS 'Item do catalogo de resgate. Nunca precificado em reais.';
COMMENT ON TABLE ot_resgate         IS 'Troca de token por beneficio. E o SUMIDOURO: o token debitado nao vai para ninguem.';
COMMENT ON TABLE ot_alerta          IS 'Alertas gravados pelas procedures PL/SQL (estorno, pagamento por prazo, falha de varredura).';
COMMENT ON TABLE ot_relatorio_tribo IS 'Saida de PRC_OT_RELATORIO_TRIBO: resumo de tokens por membro da tribo.';

COMMENT ON COLUMN ot_missao.pote_tokens     IS 'Tokens depositados por financiadores, ainda nao pagos nem estornados.';
COMMENT ON COLUMN ot_missao.fonte_pote      IS 'COMUNIDADE paga do pote; CUNHAGEM emite na conclusao; PATROCINADOR e historico.';
COMMENT ON COLUMN ot_missao.estado_desde    IS 'Instante da ultima troca de status. Marco da varredura por prazo.';
COMMENT ON COLUMN ot_lancamento.chave_idempotencia IS 'UNIQUE global. Repetir a operacao com a mesma chave nao gera segundo lancamento.';
COMMENT ON COLUMN ot_lancamento.missao_id   IS 'Id puro, sem FK, de proposito: carteira nao depende de missoes.';
COMMENT ON COLUMN ot_resgate.id             IS 'Igual ao id do lancamento de debito que o originou.';
