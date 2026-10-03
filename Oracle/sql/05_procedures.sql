-- =============================================================================================
-- Omni-Tribo · PBL Fase 6 · 05_procedures.sql
-- Procedures PL/SQL.
--
--   PRC_OT_VARRER_MISSOES_PARADAS   rotina automatizada: tira missão vencida do limbo, estorna
--                                   ou paga, e registra alertas
--   PRC_OT_RESGATAR_BENEFICIO       troca token por benefício — É A ACIONADA PELO JAVA
--   PRC_OT_RELATORIO_TRIBO          relatório resumido de tokens por membro
--
-- NENHUMA procedure faz COMMIT. A transação é de quem chama: o Java (que confirma ou desfaz
-- junto com o resto da requisição) ou o script de teste (que termina em ROLLBACK e por isso pode
-- ser repetido). Procedure que confirma por conta própria tira de quem chama a chance de desfazer.
--
-- Códigos de erro:
--   -20020  prazo inválido na varredura
--   -20021  estorno não fecha com o pote            (interno à varredura; vira alerta)
--   -20022  pote menor que a recompensa             (interno à varredura; vira alerta)
--   -20023  conclusão por prazo sem check-in válido (interno à varredura; vira alerta)
--   -20024  missão sem executor                     (interno à varredura; vira alerta)
--   -20030  chave de idempotência ausente ou longa demais
--   -20031  benefício indisponível (inexistente, inativo ou de parceiro inativo)
--   -20032  usuário sem carteira
--   -20033  saldo insuficiente
--   -20034  não foi possível gerar código de retirada único
--   -20035  conflito de concorrência — repetir a chamada com a mesma chave
--   -20040  tribo inexistente
-- =============================================================================================

-- _____________________________________________________________________________________________
-- PRC_OT_VARRER_MISSOES_PARADAS
--
-- Propósito
--   Todo estado não-terminal precisa de uma saída que não dependa de uma pessoa específica
--   aparecer. Sem esta rotina, o token de quem financiou o pote fica imobilizado para sempre
--   quando o executor ou o criador somem. No sistema de origem ela é um job agendado
--   (ExpiracaoMissoesService); aqui é a mesma regra, executada dentro do banco.
--
-- O que ela decide, por missão vencida
--   ABERTA com a janela fechada          -> EXPIRADA, e o pote volta a quem financiou
--   EM_ANDAMENTO além do prazo           -> EXPIRADA, e o pote volta a quem financiou
--   AGUARDANDO_CONFIRMACAO além do prazo -> CONCLUIDA, PAGANDO o executor
--
--   Os dois desfechos diferem de propósito. Quem abandona sem check-in não entregou nada, então
--   o dinheiro volta. Mas quando o executor já fez o check-in geolocalizado e é o CRIADOR quem
--   some, o check-in é a prova que o sistema aceita em qualquer outro caminho — punir o executor
--   pela omissão alheia seria o defeito.
--
-- Parâmetros
--   p_prazo_execucao_h     IN   horas que uma missão pode ficar EM_ANDAMENTO (padrão 48)
--   p_prazo_confirmacao_h  IN   horas que pode ficar AGUARDANDO_CONFIRMACAO (padrão 72)
--   p_agora                IN   instante de referência; parâmetro para a rotina ser testável
--   p_expiradas            OUT  quantas missões foram para EXPIRADA
--   p_concluidas           OUT  quantas foram para CONCLUIDA
--   p_tokens_estornados    OUT  total de tokens devolvidos a financiadores
--   p_falhas               OUT  quantas missões não puderam ser tratadas (cada uma gerou alerta)
--
-- Como funciona
--   1. Um cursor FOR UPDATE trava as missões vencidas, na ordem em que venceram.
--   2. Cada missão é tratada dentro de um SAVEPOINT próprio.
--   3. No estorno, um cursor INTERNO percorre os lançamentos de financiamento daquela missão —
--      dos DOIS motivos, FINANCIAMENTO_TRIBO e FINANCIAMENTO_PATROCINADOR. Esquecer um deles
--      deixaria token preso numa missão morta, com a reconciliação respondendo "íntegro".
--   4. Se o total devolvido não bate com o pote, a missão é desfeita até o savepoint, um alerta
--      VARREDURA_FALHOU é gravado e a varredura SEGUE com as demais. Uma missão corrompida não
--      pode impedir o estorno das outras.
--   5. Cada desfecho grava a trilha em OT_MISSAO_EVENTO e os alertas dos envolvidos.
--
-- Idempotência
--   Rodar duas vezes não duplica nada: a missão tratada sai do conjunto vencido, e cada
--   lançamento carrega uma chave determinística protegida por UNIQUE.
-- _____________________________________________________________________________________________
CREATE OR REPLACE PROCEDURE prc_ot_varrer_missoes_paradas (
    p_prazo_execucao_h     IN  NUMBER DEFAULT 48,
    p_prazo_confirmacao_h  IN  NUMBER DEFAULT 72,
    p_agora                IN  TIMESTAMP WITH TIME ZONE DEFAULT SYSTIMESTAMP,
    p_expiradas            OUT NUMBER,
    p_concluidas           OUT NUMBER,
    p_tokens_estornados    OUT NUMBER,
    p_falhas               OUT NUMBER
)
IS
    -- Missões vencidas. A ordem é determinística (por vencimento, depois por id) para que duas
    -- execuções sobre os mesmos dados tratem as missões na mesma sequência.
    CURSOR c_paradas IS
        SELECT m.id, m.status, m.titulo, m.criador_id, m.executor_id, m.fonte_pote,
               m.pote_tokens, m.tokens_recompensa, m.xp_recompensa
          FROM ot_missao m
         WHERE (m.status = 'ABERTA' AND m.janela_fim < p_agora)
            OR (m.status = 'EM_ANDAMENTO'
                AND m.estado_desde < p_agora - NUMTODSINTERVAL(p_prazo_execucao_h, 'HOUR'))
            OR (m.status = 'AGUARDANDO_CONFIRMACAO'
                AND m.estado_desde < p_agora - NUMTODSINTERVAL(p_prazo_confirmacao_h, 'HOUR'))
         ORDER BY m.estado_desde, m.id
           FOR UPDATE OF m.status;

    -- Quem pôs token no pote desta missão. Ordenado por carteira: travar carteiras sempre na
    -- mesma ordem é o que evita deadlock entre duas rotinas que mexem nas mesmas duas.
    CURSOR c_financiamentos (p_missao_id IN VARCHAR2) IS
        SELECT l.id, l.carteira_id, l.valor_tokens, c.usuario_id
          FROM ot_lancamento l
          JOIN ot_carteira   c ON c.id = l.carteira_id
         WHERE l.missao_id = p_missao_id
           AND l.sinal     = 'DEBITO'
           AND l.motivo   IN ('FINANCIAMENTO_TRIBO', 'FINANCIAMENTO_PATROCINADOR')
         ORDER BY l.carteira_id, l.id;

    e_estorno_nao_fecha   EXCEPTION;
    e_pote_insuficiente   EXCEPTION;
    e_sem_checkin_valido  EXCEPTION;
    e_sem_executor        EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_estorno_nao_fecha,  -20021);
    PRAGMA EXCEPTION_INIT(e_pote_insuficiente,  -20022);
    PRAGMA EXCEPTION_INIT(e_sem_checkin_valido, -20023);
    PRAGMA EXCEPTION_INIT(e_sem_executor,       -20024);

    v_devolvido  NUMBER;
    v_erro       VARCHAR2(500 CHAR);

    PROCEDURE alertar (
        p_usuario_id  IN VARCHAR2,
        p_tipo        IN VARCHAR2,
        p_titulo      IN VARCHAR2,
        p_corpo       IN VARCHAR2,
        p_missao_id   IN VARCHAR2,
        p_prioridade  IN NUMBER
    ) IS
    BEGIN
        INSERT INTO ot_alerta (id, usuario_id, tipo, titulo, corpo, missao_id, prioridade,
                               criado_em)
        VALUES (fn_ot_novo_id, p_usuario_id, p_tipo, SUBSTR(p_titulo, 1, 200),
                SUBSTR(p_corpo, 1, 1000), p_missao_id, p_prioridade, p_agora);
    END alertar;

    -- Credita uma carteira e grava o lançamento com o saldo resultante. O SELECT FOR UPDATE vem
    -- ANTES do UPDATE para que o saldo lido seja o saldo travado, não um valor de antes da fila.
    PROCEDURE creditar (
        p_carteira_id  IN VARCHAR2,
        p_motivo       IN VARCHAR2,
        p_valor        IN NUMBER,
        p_missao_id    IN VARCHAR2,
        p_chave        IN VARCHAR2,
        p_mensagem     IN VARCHAR2
    ) IS
        v_saldo  ot_carteira.saldo_tokens%TYPE;
    BEGIN
        SELECT saldo_tokens INTO v_saldo
          FROM ot_carteira
         WHERE id = p_carteira_id
           FOR UPDATE;

        v_saldo := v_saldo + p_valor;

        UPDATE ot_carteira SET saldo_tokens = v_saldo WHERE id = p_carteira_id;

        INSERT INTO ot_lancamento (id, carteira_id, sinal, motivo, valor_tokens, missao_id,
                                   chave_idempotencia, saldo_apos_tokens, mensagem, criado_em)
        VALUES (fn_ot_novo_id, p_carteira_id, 'CREDITO', p_motivo, p_valor, p_missao_id,
                p_chave, v_saldo, p_mensagem, p_agora);
    END creditar;

    -- Devolve o pote a cada financiador e confere que a soma fecha.
    FUNCTION estornar_pote (
        p_missao_id  IN VARCHAR2,
        p_titulo     IN VARCHAR2,
        p_pote       IN NUMBER
    ) RETURN NUMBER
    IS
        v_total  NUMBER := 0;
    BEGIN
        FOR r_fin IN c_financiamentos(p_missao_id) LOOP
            creditar(r_fin.carteira_id, 'ESTORNO', r_fin.valor_tokens, p_missao_id,
                     'estorno:' || p_missao_id || ':' || r_fin.id,
                     'Estorno do pote: missão encerrada sem execução');

            alertar(r_fin.usuario_id, 'ESTORNO_RECEBIDO', 'Seu financiamento voltou',
                    fn_ot_formatar_tokens(r_fin.valor_tokens) || ' devolvidos: a missão "'
                    || p_titulo || '" foi encerrada sem execução.',
                    p_missao_id, 1);

            v_total := v_total + r_fin.valor_tokens;
        END LOOP;

        -- A mesma invariante do sistema de origem: o que foi devolvido tem de ser exatamente o
        -- que estava no pote. Diferença aqui é corrupção, e seguir em frente a esconderia.
        IF v_total <> p_pote THEN
            RAISE_APPLICATION_ERROR(-20021,
                'Estorno devolveria ' || v_total || ' tokens, mas o pote tem ' || p_pote || '.');
        END IF;

        RETURN v_total;
    END estornar_pote;

    PROCEDURE expirar (r_missao IN c_paradas%ROWTYPE) IS
        v_tipo_evento  VARCHAR2(30);
    BEGIN
        IF r_missao.pote_tokens > 0 THEN
            v_devolvido := estornar_pote(r_missao.id, r_missao.titulo, r_missao.pote_tokens);
        ELSE
            v_devolvido := 0;
        END IF;

        IF r_missao.status = 'ABERTA' THEN
            v_tipo_evento := 'EXPIRADA';
        ELSE
            v_tipo_evento := 'EXECUCAO_EXPIRADA';
        END IF;

        UPDATE ot_missao
           SET status = 'EXPIRADA', pote_tokens = 0, estado_desde = p_agora
         WHERE id = r_missao.id;

        -- ator_id nulo: quem agiu foi o SISTEMA, não uma pessoa.
        INSERT INTO ot_missao_evento (id, missao_id, tipo, ator_id, de_status, para_status,
                                      criado_em)
        VALUES (fn_ot_novo_id, r_missao.id, v_tipo_evento, NULL, r_missao.status, 'EXPIRADA',
                p_agora);

        alertar(r_missao.criador_id, 'MISSAO_EXPIRADA', 'Sua missão expirou',
                '"' || r_missao.titulo || '" foi encerrada por prazo'
                || CASE WHEN r_missao.status = 'ABERTA' THEN ' sem que ninguém a aceitasse.'
                        ELSE ': a execução não foi comprovada por check-in.' END,
                r_missao.id, 1);
    END expirar;

    PROCEDURE concluir_por_prazo (r_missao IN c_paradas%ROWTYPE) IS
        v_checkins     NUMBER;
        v_carteira_id  ot_carteira.id%TYPE;
        v_novo_pote    NUMBER := r_missao.pote_tokens;
    BEGIN
        IF r_missao.executor_id IS NULL THEN
            RAISE_APPLICATION_ERROR(-20024, 'Missão aguardando confirmação sem executor.');
        END IF;

        -- Pagar sem prova seria pagar por confiança. O check-in válido é a evidência.
        SELECT COUNT(*) INTO v_checkins
          FROM ot_checkin
         WHERE missao_id = r_missao.id
           AND usuario_id = r_missao.executor_id
           AND valido = 1;

        IF v_checkins = 0 THEN
            RAISE_APPLICATION_ERROR(-20023,
                'Não há check-in válido do executor: nada prova a execução.');
        END IF;

        -- COMUNIDADE (e o valor histórico PATROCINADOR) paga do pote: o token muda de lugar.
        -- CUNHAGEM não tem pote: a conclusão emite.
        IF r_missao.fonte_pote <> 'CUNHAGEM' THEN
            IF r_missao.pote_tokens < r_missao.tokens_recompensa THEN
                RAISE_APPLICATION_ERROR(-20022,
                    'Pote tem ' || r_missao.pote_tokens || ' tokens e a recompensa é de '
                    || r_missao.tokens_recompensa || '.');
            END IF;
            v_novo_pote := r_missao.pote_tokens - r_missao.tokens_recompensa;
        END IF;

        IF r_missao.tokens_recompensa > 0 THEN
            SELECT id INTO v_carteira_id FROM ot_carteira WHERE usuario_id = r_missao.executor_id;

            creditar(v_carteira_id, 'RECOMPENSA_MISSAO', r_missao.tokens_recompensa, r_missao.id,
                     'conclusao:' || r_missao.id || ':' || r_missao.executor_id,
                     'Recompensa paga por prazo: o criador não confirmou');
        END IF;

        -- XP é monotônico e o nível é DERIVADO dele, nunca incrementado: 1 + piso(raiz(xp/100)).
        UPDATE ot_usuario
           SET xp    = xp + r_missao.xp_recompensa,
               nivel = 1 + FLOOR(SQRT((xp + r_missao.xp_recompensa) / 100))
         WHERE id = r_missao.executor_id;

        UPDATE ot_missao
           SET status = 'CONCLUIDA', pote_tokens = v_novo_pote, concluida_em = p_agora,
               estado_desde = p_agora
         WHERE id = r_missao.id;

        INSERT INTO ot_missao_evento (id, missao_id, tipo, ator_id, de_status, para_status,
                                      criado_em)
        VALUES (fn_ot_novo_id, r_missao.id, 'CONFIRMACAO_EXPIRADA', NULL, r_missao.status,
                'CONCLUIDA', p_agora);

        alertar(r_missao.executor_id, 'MISSAO_CONCLUIDA', 'Recompensa liberada',
                'O prazo de confirmação de "' || r_missao.titulo || '" venceu e seu check-in '
                || 'valeu como prova: ' || r_missao.xp_recompensa || ' XP e '
                || fn_ot_formatar_tokens(r_missao.tokens_recompensa) || '.',
                r_missao.id, 1);
    END concluir_por_prazo;
BEGIN
    IF p_prazo_execucao_h IS NULL OR p_prazo_execucao_h < 0
       OR p_prazo_confirmacao_h IS NULL OR p_prazo_confirmacao_h < 0
       OR p_agora IS NULL THEN
        RAISE_APPLICATION_ERROR(-20020,
            'Prazos devem ser informados em horas, sem valor negativo, e o instante de '
            || 'referência não pode ser nulo.');
    END IF;

    p_expiradas         := 0;
    p_concluidas        := 0;
    p_tokens_estornados := 0;
    p_falhas            := 0;

    FOR r_missao IN c_paradas LOOP
        -- Tudo o que esta missão escrever fica depois deste ponto; se ela falhar, só ela desfaz.
        SAVEPOINT sp_missao;

        BEGIN
            IF r_missao.status = 'AGUARDANDO_CONFIRMACAO' THEN
                concluir_por_prazo(r_missao);
                p_concluidas := p_concluidas + 1;
            ELSE
                expirar(r_missao);
                p_expiradas         := p_expiradas + 1;
                p_tokens_estornados := p_tokens_estornados + v_devolvido;
            END IF;
        EXCEPTION
            -- OTHERS de propósito, e NÃO para engolir: o erro é desfeito, contado, gravado como
            -- alerta de prioridade máxima e impresso. O que não pode acontecer é uma missão
            -- corrompida impedir o estorno de todas as que vêm depois dela.
            WHEN OTHERS THEN
                v_erro := SUBSTR(SQLERRM, 1, 500);
                ROLLBACK TO sp_missao;
                p_falhas := p_falhas + 1;

                alertar(NULL, 'VARREDURA_FALHOU', 'Missão não pôde ser destravada',
                        '"' || r_missao.titulo || '" (' || r_missao.status || '): ' || v_erro,
                        r_missao.id, 2);

                DBMS_OUTPUT.PUT_LINE('FALHA  ' || r_missao.id || '  ' || v_erro);
        END;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Varredura concluída: ' || p_expiradas || ' expirada(s), '
                         || p_concluidas || ' concluída(s) por prazo, '
                         || fn_ot_formatar_tokens(p_tokens_estornados) || ' estornados, '
                         || p_falhas || ' falha(s).');
END prc_ot_varrer_missoes_paradas;
/

-- _____________________________________________________________________________________________
-- PRC_OT_RESGATAR_BENEFICIO                                    [ACIONADA PELO BACK-END JAVA]
--
-- Propósito
--   Trocar token por um benefício de parceiro do bairro. É o SUMIDOURO da economia: o
--   lançamento debita com motivo RESGATE e não credita ninguém — o token deixa de existir.
--   Sem um sumidouro, todo token emitido se acumularia para sempre.
--
-- Parâmetros
--   p_usuario_id       IN   quem resgata
--   p_beneficio_id     IN   o que está sendo resgatado
--   p_chave            IN   chave de idempotência enviada pelo cliente (até 100 caracteres)
--   p_resgate_id       OUT  id do resgate (o mesmo do lançamento de débito)
--   p_codigo_retirada  OUT  código de 8 caracteres para apresentar no balcão
--   p_saldo_apos       OUT  saldo de tokens depois da operação
--   p_replay           OUT  1 se esta chamada repetiu uma anterior; 0 se foi a primeira
--
-- Como funciona
--   1. Confere que o benefício é resgatável. Inexistente, inativo e de parceiro inativo dão o
--      MESMO erro: distinguir os três contaria a quem pergunta quais ids existem.
--   2. Trava a carteira com SELECT … FOR UPDATE. Dois resgates simultâneos do mesmo usuário
--      entram em fila aqui, e o segundo lê o saldo já debitado pelo primeiro.
--   3. Procura a chave de idempotência. Se já existe, devolve o resgate ANTERIOR sem debitar de
--      novo: é o que protege contra o toque duplo no botão e contra a retentativa de rede.
--   4. Confere o saldo e debita.
--   5. Gera o código de retirada num LOOP de até 3 tentativas.
--   6. Grava o lançamento e o resgate, com o mesmo id.
--
-- A chave é guardada como 'resgate:<usuário>:<chave do cliente>', nunca crua: a UNIQUE é global,
-- e com a chave crua o cliente que mandasse "1" receberia de volta o resgate de outra pessoa.
--
-- O código de retirada NÃO é credencial — quem autoriza a baixa é o administrador, pelo id do
-- resgate. Por isso DBMS_RANDOM basta aqui; para segredo de verdade ele não serviria.
-- _____________________________________________________________________________________________
CREATE OR REPLACE PROCEDURE prc_ot_resgatar_beneficio (
    p_usuario_id       IN  VARCHAR2,
    p_beneficio_id     IN  VARCHAR2,
    p_chave            IN  VARCHAR2,
    p_resgate_id       OUT VARCHAR2,
    p_codigo_retirada  OUT VARCHAR2,
    p_saldo_apos       OUT NUMBER,
    p_replay           OUT NUMBER
)
IS
    -- Sem 0, O, 1 e I: o código é lido em voz alta num balcão.
    c_alfabeto    CONSTANT VARCHAR2(32) := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    c_tentativas  CONSTANT PLS_INTEGER  := 3;

    v_custo        ot_beneficio.custo_tokens%TYPE;
    v_carteira_id  ot_carteira.id%TYPE;
    v_saldo        ot_carteira.saldo_tokens%TYPE;
    v_chave        ot_lancamento.chave_idempotencia%TYPE;
    v_codigo       ot_resgate.codigo_retirada%TYPE;
    v_ja_existe    NUMBER;
    v_tentativa    PLS_INTEGER := 0;
    v_agora        TIMESTAMP WITH TIME ZONE := SYSTIMESTAMP;
BEGIN
    IF p_chave IS NULL OR LENGTH(p_chave) > 100 THEN
        RAISE_APPLICATION_ERROR(-20030,
            'A chave de idempotência é obrigatória e tem no máximo 100 caracteres.');
    END IF;

    -- 1. Benefício resgatável?
    BEGIN
        SELECT b.custo_tokens
          INTO v_custo
          FROM ot_beneficio b
          JOIN ot_parceiro  p ON p.id = b.parceiro_id
         WHERE b.id = p_beneficio_id
           AND b.ativo = 1
           AND p.ativo = 1;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20031, 'Benefício indisponível.');
    END;

    -- 2. Trava a carteira.
    BEGIN
        SELECT id, saldo_tokens
          INTO v_carteira_id, v_saldo
          FROM ot_carteira
         WHERE usuario_id = p_usuario_id
           FOR UPDATE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20032, 'Carteira não encontrada.');
    END;

    -- 3. Replay?
    v_chave := 'resgate:' || p_usuario_id || ':' || p_chave;

    BEGIN
        SELECT r.id, r.codigo_retirada
          INTO p_resgate_id, p_codigo_retirada
          FROM ot_lancamento l
          JOIN ot_resgate    r ON r.id = l.id
         WHERE l.chave_idempotencia = v_chave;

        p_saldo_apos := v_saldo;
        p_replay     := 1;
        RETURN;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            NULL;  -- primeira vez com esta chave: segue para o débito
    END;

    -- 4. Saldo.
    IF v_saldo < v_custo THEN
        RAISE_APPLICATION_ERROR(-20033,
            'Saldo de ' || v_saldo || ' tokens é insuficiente para resgatar este benefício, '
            || 'que custa ' || v_custo || '.');
    END IF;

    -- 5. Código de retirada único.
    LOOP
        v_tentativa := v_tentativa + 1;

        v_codigo := NULL;
        FOR i IN 1 .. 8 LOOP
            v_codigo := v_codigo
                || SUBSTR(c_alfabeto, TRUNC(DBMS_RANDOM.VALUE(1, LENGTH(c_alfabeto) + 1)), 1);
        END LOOP;

        SELECT COUNT(*) INTO v_ja_existe FROM ot_resgate WHERE codigo_retirada = v_codigo;
        EXIT WHEN v_ja_existe = 0;

        IF v_tentativa >= c_tentativas THEN
            RAISE_APPLICATION_ERROR(-20034,
                'Não foi possível gerar código de retirada único em ' || c_tentativas
                || ' tentativas.');
        END IF;
    END LOOP;

    -- 6. Débito, lançamento e resgate. Sem contraparte e sem missão: o token é queimado.
    v_saldo      := v_saldo - v_custo;
    p_resgate_id := fn_ot_novo_id;

    UPDATE ot_carteira SET saldo_tokens = v_saldo WHERE id = v_carteira_id;

    INSERT INTO ot_lancamento (id, carteira_id, sinal, motivo, valor_tokens,
                               chave_idempotencia, saldo_apos_tokens, criado_em)
    VALUES (p_resgate_id, v_carteira_id, 'DEBITO', 'RESGATE', v_custo,
            v_chave, v_saldo, v_agora);

    INSERT INTO ot_resgate (id, usuario_id, beneficio_id, custo_tokens, codigo_retirada, status,
                            criado_em)
    VALUES (p_resgate_id, p_usuario_id, p_beneficio_id, v_custo, v_codigo, 'PENDENTE', v_agora);

    p_codigo_retirada := v_codigo;
    p_saldo_apos      := v_saldo;
    p_replay          := 0;
EXCEPTION
    -- Só chega aqui se outra sessão gravou o mesmo código de retirada entre a checagem e o
    -- INSERT. A trava da carteira já impede que isto venha da chave de idempotência.
    WHEN DUP_VAL_ON_INDEX THEN
        RAISE_APPLICATION_ERROR(-20035,
            'Conflito de concorrência no resgate. Repita a chamada com a mesma chave.');
END prc_ot_resgatar_beneficio;
/

-- _____________________________________________________________________________________________
-- PRC_OT_RELATORIO_TRIBO
--
-- Propósito
--   Gerar o resumo de movimentação de token por membro de uma tribo: quanto cada um GANHOU
--   executando missão, quanto FINANCIOU do próprio bolso, quanto RESGATOU em benefício e quanto
--   tem hoje. Responde à pergunta que a tese do produto faz — o cuidado está circulando ou
--   está parado na carteira de poucos?
--
-- Parâmetros
--   p_tribo_id        IN   tribo a resumir
--   p_membros         OUT  quantos membros entraram no relatório
--   p_tokens_ganhos   OUT  total de tokens ganhos pela tribo em recompensa de missão
--
-- Como funciona
--   Um cursor EXPLÍCITO (OPEN / FETCH / EXIT WHEN / CLOSE) percorre os membros ativos. Para cada
--   um, a procedure soma os lançamentos por motivo, grava uma linha em OT_RELATORIO_TRIBO e
--   imprime a linha formatada por DBMS_OUTPUT. A fotografia anterior da tribo é substituída.
--
--   O financiamento é LÍQUIDO de estorno: token que voltou não foi, no fim, financiado.
--
-- Exceções
--   -20040 se a tribo não existe. Qualquer erro no meio fecha o cursor antes de propagar.
-- _____________________________________________________________________________________________
CREATE OR REPLACE PROCEDURE prc_ot_relatorio_tribo (
    p_tribo_id       IN  VARCHAR2,
    p_membros        OUT NUMBER,
    p_tokens_ganhos  OUT NUMBER
)
IS
    CURSOR c_membros IS
        SELECT u.id AS usuario_id, u.handle, u.nivel, c.id AS carteira_id,
               NVL(c.saldo_tokens, 0) AS saldo_tokens
          FROM ot_usuario  u
          LEFT JOIN ot_carteira c ON c.usuario_id = u.id
         WHERE u.tribo_id = p_tribo_id
           AND u.status   = 'ATIVO'
         ORDER BY u.handle;

    r_membro       c_membros%ROWTYPE;
    v_nome_tribo   ot_tribo.nome%TYPE;
    v_concluidas   NUMBER;
    v_ganhos       NUMBER;
    v_financiados  NUMBER;
    v_resgatados   NUMBER;
    v_agora        TIMESTAMP WITH TIME ZONE := SYSTIMESTAMP;
BEGIN
    BEGIN
        SELECT nome INTO v_nome_tribo FROM ot_tribo WHERE id = p_tribo_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20040, 'Tribo inexistente: ' || p_tribo_id);
    END;

    p_membros       := 0;
    p_tokens_ganhos := 0;

    DELETE FROM ot_relatorio_tribo WHERE tribo_id = p_tribo_id;

    DBMS_OUTPUT.PUT_LINE('Relatório de tokens — ' || v_nome_tribo);
    DBMS_OUTPUT.PUT_LINE(RPAD('membro', 14) || LPAD('nível', 6) || LPAD('missões', 9)
                         || LPAD('ganhou', 9) || LPAD('financiou', 11) || LPAD('resgatou', 10)
                         || LPAD('saldo', 8));
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 67, '-'));

    OPEN c_membros;
    LOOP
        FETCH c_membros INTO r_membro;
        EXIT WHEN c_membros%NOTFOUND;

        SELECT COUNT(*) INTO v_concluidas
          FROM ot_missao
         WHERE executor_id = r_membro.usuario_id
           AND status      = 'CONCLUIDA';

        -- Membro sem carteira (o administrador, por exemplo) entra com tudo zerado.
        SELECT NVL(SUM(CASE WHEN motivo = 'RECOMPENSA_MISSAO' THEN valor_tokens END), 0),
               NVL(SUM(CASE WHEN motivo IN ('FINANCIAMENTO_TRIBO', 'FINANCIAMENTO_PATROCINADOR')
                            THEN valor_tokens
                            WHEN motivo = 'ESTORNO' THEN -valor_tokens END), 0),
               NVL(SUM(CASE WHEN motivo = 'RESGATE' THEN valor_tokens END), 0)
          INTO v_ganhos, v_financiados, v_resgatados
          FROM ot_lancamento
         WHERE carteira_id = r_membro.carteira_id;

        INSERT INTO ot_relatorio_tribo (tribo_id, usuario_id, handle, missoes_concluidas,
                                        tokens_ganhos, tokens_financiados, tokens_resgatados,
                                        saldo_tokens, gerado_em)
        VALUES (p_tribo_id, r_membro.usuario_id, r_membro.handle, v_concluidas,
                v_ganhos, v_financiados, v_resgatados, r_membro.saldo_tokens, v_agora);

        DBMS_OUTPUT.PUT_LINE(RPAD('@' || r_membro.handle, 14) || LPAD(r_membro.nivel, 6)
                             || LPAD(v_concluidas, 9) || LPAD(v_ganhos, 9)
                             || LPAD(v_financiados, 11) || LPAD(v_resgatados, 10)
                             || LPAD(r_membro.saldo_tokens, 8));

        p_membros       := p_membros + 1;
        p_tokens_ganhos := p_tokens_ganhos + v_ganhos;
    END LOOP;
    CLOSE c_membros;

    DBMS_OUTPUT.PUT_LINE(RPAD('-', 67, '-'));
    IF p_membros = 0 THEN
        DBMS_OUTPUT.PUT_LINE('Tribo sem membro ativo.');
    ELSE
        DBMS_OUTPUT.PUT_LINE(p_membros || ' membro(s) · '
                             || fn_ot_formatar_tokens(p_tokens_ganhos)
                             || ' ganhos em recompensa de missão.');
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        -- Cursor explícito não fecha sozinho quando a exceção sai do bloco.
        IF c_membros%ISOPEN THEN
            CLOSE c_membros;
        END IF;
        RAISE;
END prc_ot_relatorio_tribo;
/
