-- =============================================================================================
-- Omni-Tribo · PBL Fase 6 · 03_carga_cenarios.sql
-- DADOS SIMULADOS, escritos à mão. Nada aqui veio do sistema de origem.
--
-- Por que este arquivo existe: o seed do projeto (02_carga_seed.sql) só tem missões ABERTA,
-- ACEITA e CONCLUIDA, e nenhum check-in ou resgate. As rotinas PL/SQL precisam de missões PARADAS
-- para varrer, de leituras de GPS para julgar e de resgates para resumir. Os cenários abaixo
-- criam exatamente isso, na Tribo Cidade Líder, com os moradores que o seed já traz.
--
-- Todo id deste arquivo começa com f6 — é assim que se separa o simulado do exportado.
--
--   Cenário  Missão                         Estado inicial            O que a varredura deve fazer
--   -------  -----------------------------  ------------------------  -----------------------------
--   C1       Mutirão da quadra              EM_ANDAMENTO há 72 h      EXPIRADA; estorna 25 ao Renan
--                                           sem check-in válido       e 15 ao apoiador (2 motivos)
--   C2       Coleta de eletrônicos          AGUARDANDO_CONFIRMACAO    CONCLUIDA; paga 30 tokens e
--                                           há 96 h, com check-in     90 XP à Marlene, do pote
--   C3       Pintura do muro da escola      ABERTA, janela vencida    EXPIRADA; estorna 20 ao apoiador
--   C4       Entrega de cesta básica        AGUARDANDO_CONFIRMACAO    CONCLUIDA; EMITE 22 tokens ao
--                                           há 80 h, fonte CUNHAGEM   Renan (não há pote)
--   C5       Horta: rega da semana          EM_ANDAMENTO há 5 h       NADA — está dentro do prazo
--   C6       Missão com pote órfão          EM_ANDAMENTO há 60 h,     FALHA controlada: pote sem
--                                           pote 10 sem financiador   financiamento; gera alerta
--
-- C6 é corrupção plantada de propósito: é o caso que prova que a varredura isola a missão ruim
-- (SAVEPOINT + EXCEPTION), registra o alerta e continua com as outras.
--
-- A carga mantém o livro-razão íntegro: cada financiamento e cada resgate passa por uma rotina
-- local que debita a carteira E grava o lançamento com o saldo resultante. Assim
-- FN_OT_DIVERGENCIA_CARTEIRA devolve 0 para todas as carteiras logo após a instalação.
-- =============================================================================================
SET DEFINE OFF

DECLARE
    -- Moradores e apoiador do seed (Tribo Cidade Líder).
    c_renan     CONSTANT VARCHAR2(36) := 'bbbbbbbb-0000-0000-0000-000000000901';
    c_marlene   CONSTANT VARCHAR2(36) := 'bbbbbbbb-0000-0000-0000-000000000902';
    c_jonas     CONSTANT VARCHAR2(36) := 'bbbbbbbb-0000-0000-0000-000000000903';
    c_apoiador  CONSTANT VARCHAR2(36) := 'bbbbbbbb-0000-0000-0000-000000000950';

    c_cafe      CONSTANT VARCHAR2(36) := '33333333-0000-0000-0000-000000000960';
    c_pao       CONSTANT VARCHAR2(36) := '33333333-0000-0000-0000-000000000961';

    v_agora     TIMESTAMP WITH TIME ZONE := SYSTIMESTAMP;

    -- Debita a carteira do usuário e grava o lançamento com o saldo resultante. É o que mantém a
    -- projeção (saldo) e a verdade (ledger) batendo desde a carga.
    PROCEDURE debitar (
        p_lancamento_id  IN VARCHAR2,
        p_usuario_id     IN VARCHAR2,
        p_motivo         IN VARCHAR2,
        p_valor          IN NUMBER,
        p_missao_id      IN VARCHAR2,
        p_chave          IN VARCHAR2,
        p_quando         IN TIMESTAMP WITH TIME ZONE
    ) IS
        v_carteira_id  ot_carteira.id%TYPE;
        v_saldo        ot_carteira.saldo_tokens%TYPE;
    BEGIN
        UPDATE ot_carteira
           SET saldo_tokens = saldo_tokens - p_valor
         WHERE usuario_id = p_usuario_id
        RETURNING id, saldo_tokens INTO v_carteira_id, v_saldo;

        INSERT INTO ot_lancamento (id, carteira_id, sinal, motivo, valor_tokens, missao_id,
                                   chave_idempotencia, saldo_apos_tokens, criado_em)
        VALUES (p_lancamento_id, v_carteira_id, 'DEBITO', p_motivo, p_valor, p_missao_id,
                p_chave, v_saldo, p_quando);
    END debitar;

    PROCEDURE criar_missao (
        p_id            IN VARCHAR2,
        p_criador       IN VARCHAR2,
        p_executor      IN VARCHAR2,
        p_categoria     IN VARCHAR2,
        p_titulo        IN VARCHAR2,
        p_status        IN VARCHAR2,
        p_xp            IN NUMBER,
        p_tokens        IN NUMBER,
        p_pote          IN NUMBER,
        p_fonte         IN VARCHAR2,
        p_janela_fim    IN TIMESTAMP WITH TIME ZONE,
        p_estado_desde  IN TIMESTAMP WITH TIME ZONE
    ) IS
    BEGIN
        INSERT INTO ot_missao (id, criador_id, executor_id, categoria, titulo, status,
                               xp_recompensa, tokens_recompensa, pote_tokens, fonte_pote,
                               complexidade, bairro, cidade, uf, janela_inicio, janela_fim,
                               criada_em, aceita_em, estado_desde)
        VALUES (p_id, p_criador, p_executor, p_categoria, p_titulo, p_status,
                p_xp, p_tokens, p_pote, p_fonte,
                'MEDIA', 'Cidade Líder', 'São Paulo', 'SP',
                p_estado_desde - INTERVAL '24' HOUR, p_janela_fim,
                p_estado_desde - INTERVAL '30' HOUR,
                CASE WHEN p_executor IS NOT NULL THEN p_estado_desde - INTERVAL '2' HOUR END,
                p_estado_desde);
    END criar_missao;

    PROCEDURE checkin (
        p_id         IN VARCHAR2,
        p_missao     IN VARCHAR2,
        p_usuario    IN VARCHAR2,
        p_acuracia   IN NUMBER,
        p_distancia  IN NUMBER,
        p_mock       IN NUMBER,
        p_codigo     IN VARCHAR2,
        p_quando     IN TIMESTAMP WITH TIME ZONE
    ) IS
    BEGIN
        INSERT INTO ot_checkin (id, missao_id, usuario_id, acuracia_m, distancia_alvo_m, metodo,
                                mock_detectado, valido, codigo_rejeicao, criado_em)
        VALUES (p_id, p_missao, p_usuario, p_acuracia, p_distancia, 'GPS',
                p_mock, CASE WHEN p_codigo IS NULL THEN 1 ELSE 0 END, p_codigo, p_quando);
    END checkin;
BEGIN
    -- C1 — execução abandonada, pote financiado por membro E por apoiador.
    criar_missao('f6000000-0000-0000-0000-000000000001', c_marlene, c_jonas, 'TRIBO',
                 'Mutirão: reforma da quadra da rua Tapes', 'EM_ANDAMENTO', 120, 40, 40,
                 'COMUNIDADE', v_agora + INTERVAL '48' HOUR, v_agora - INTERVAL '72' HOUR);
    debitar('f6000000-0000-0000-0001-000000000001', c_renan, 'FINANCIAMENTO_TRIBO', 25,
            'f6000000-0000-0000-0000-000000000001', 'cenario-c1-fin-renan',
            v_agora - INTERVAL '100' HOUR);
    debitar('f6000000-0000-0000-0001-000000000002', c_apoiador, 'FINANCIAMENTO_PATROCINADOR', 15,
            'f6000000-0000-0000-0000-000000000001', 'cenario-c1-fin-apoiador',
            v_agora - INTERVAL '99' HOUR);
    -- Jonas tentou o check-in a 430 m do alvo: leitura rejeitada não conta como presença.
    checkin('f6000000-0000-0000-0002-000000000001', 'f6000000-0000-0000-0000-000000000001',
            c_jonas, 12.5, 430.0, 0, 'FORA_DO_RAIO', v_agora - INTERVAL '70' HOUR);

    -- C2 — criador sumiu depois do check-in válido. O executor tem de receber.
    criar_missao('f6000000-0000-0000-0000-000000000002', c_renan, c_marlene, 'COLETA',
                 'Coletar eletrônicos velhos do condomínio', 'AGUARDANDO_CONFIRMACAO', 90, 30, 30,
                 'COMUNIDADE', v_agora + INTERVAL '24' HOUR, v_agora - INTERVAL '96' HOUR);
    debitar('f6000000-0000-0000-0001-000000000003', c_jonas, 'FINANCIAMENTO_TRIBO', 30,
            'f6000000-0000-0000-0000-000000000002', 'cenario-c2-fin-jonas',
            v_agora - INTERVAL '120' HOUR);
    checkin('f6000000-0000-0000-0002-000000000002', 'f6000000-0000-0000-0000-000000000002',
            c_marlene, 8.0, 14.2, 0, NULL, v_agora - INTERVAL '96' HOUR);

    -- C3 — publicada e nunca aceita; a janela fechou há 6 horas.
    criar_missao('f6000000-0000-0000-0000-000000000003', c_renan, NULL, 'TRIBO',
                 'Mutirão: pintar o muro da escola', 'ABERTA', 114, 20, 20,
                 'COMUNIDADE', v_agora - INTERVAL '6' HOUR, v_agora - INTERVAL '50' HOUR);
    debitar('f6000000-0000-0000-0001-000000000004', c_apoiador, 'FINANCIAMENTO_PATROCINADOR', 20,
            'f6000000-0000-0000-0000-000000000003', 'cenario-c3-fin-apoiador',
            v_agora - INTERVAL '49' HOUR);

    -- C4 — ENTREGA criada por pessoa: fonte CUNHAGEM, sem pote. A conclusão emite.
    criar_missao('f6000000-0000-0000-0000-000000000004', c_jonas, c_renan, 'ENTREGA',
                 'Entregar cesta básica à dona Neusa', 'AGUARDANDO_CONFIRMACAO', 66, 22, 0,
                 'CUNHAGEM', v_agora + INTERVAL '24' HOUR, v_agora - INTERVAL '80' HOUR);
    checkin('f6000000-0000-0000-0002-000000000003', 'f6000000-0000-0000-0000-000000000004',
            c_renan, 6.5, 9.8, 0, NULL, v_agora - INTERVAL '80' HOUR);

    -- C5 — em andamento há só 5 horas. A varredura NÃO pode tocar nela.
    criar_missao('f6000000-0000-0000-0000-000000000005', c_marlene, c_jonas, 'TRIBO',
                 'Horta comunitária: rega da semana', 'EM_ANDAMENTO', 54, 18, 18,
                 'COMUNIDADE', v_agora + INTERVAL '72' HOUR, v_agora - INTERVAL '5' HOUR);
    debitar('f6000000-0000-0000-0001-000000000005', c_renan, 'FINANCIAMENTO_TRIBO', 18,
            'f6000000-0000-0000-0000-000000000005', 'cenario-c5-fin-renan',
            v_agora - INTERVAL '20' HOUR);

    -- C6 — CORRUPÇÃO PLANTADA: pote de 10 sem nenhum lançamento de financiamento por trás.
    criar_missao('f6000000-0000-0000-0000-000000000006', c_marlene, c_jonas, 'COLETA',
                 'Missão com pote órfão (cenário de falha)', 'EM_ANDAMENTO', 30, 10, 10,
                 'COMUNIDADE', v_agora + INTERVAL '24' HOUR, v_agora - INTERVAL '60' HOUR);

    -- Leituras críticas avulsas, para a análise de check-ins rejeitados.
    checkin('f6000000-0000-0000-0002-000000000004', 'f6000000-0000-0000-0000-000000000005',
            c_jonas, 9.0, 22.0, 1, 'LOCALIZACAO_SIMULADA', v_agora - INTERVAL '4' HOUR);
    checkin('f6000000-0000-0000-0002-000000000005', 'f6000000-0000-0000-0000-000000000005',
            c_jonas, 180.0, 35.0, 0, 'ACURACIA_INSUFICIENTE', v_agora - INTERVAL '3' HOUR);

    -- Dois resgates passados: um já retirado no balcão, um ainda pendente.
    debitar('f6000000-0000-0000-0001-000000000006', c_jonas, 'RESGATE', 15, NULL,
            'cenario-resgate-jonas-cafe', v_agora - INTERVAL '40' HOUR);
    INSERT INTO ot_resgate (id, usuario_id, beneficio_id, custo_tokens, codigo_retirada, status,
                            criado_em, utilizado_em)
    VALUES ('f6000000-0000-0000-0001-000000000006', c_jonas, c_cafe, 15, 'CAFE7K2M', 'UTILIZADO',
            v_agora - INTERVAL '40' HOUR, v_agora - INTERVAL '38' HOUR);

    debitar('f6000000-0000-0000-0001-000000000007', c_renan, 'RESGATE', 25, NULL,
            'cenario-resgate-renan-pao', v_agora - INTERVAL '10' HOUR);
    INSERT INTO ot_resgate (id, usuario_id, beneficio_id, custo_tokens, codigo_retirada, status,
                            criado_em)
    VALUES ('f6000000-0000-0000-0001-000000000007', c_renan, c_pao, 25, 'PAO4T9XQ', 'PENDENTE',
            v_agora - INTERVAL '10' HOUR);

    COMMIT;
END;
/
