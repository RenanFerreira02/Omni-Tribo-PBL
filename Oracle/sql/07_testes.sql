-- =============================================================================================
-- Omni-Tribo · PBL Fase 6 · 07_testes.sql
-- Testes das functions e procedures: caminho feliz E caminho de erro de cada uma.
--
-- Cada teste compara o resultado com um valor esperado ESCRITO À MÃO a partir dos cenários de
-- 03_carga_cenarios.sql — não com outra consulta que repetiria a mesma conta. Teste sem asserção
-- não é teste.
--
-- O script roda sobre a instalação limpa (instalar.sql) e termina em ROLLBACK, então pode ser
-- repetido. Se algum teste falhar, o bloco levanta erro e o script sai com código de falha.
--
-- Uso (a partir da pasta Oracle/sql):
--   sql usuario/senha@//oracle.fiap.com.br:1521/ORCL @07_testes.sql
-- =============================================================================================
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200
WHENEVER SQLERROR EXIT FAILURE ROLLBACK

DECLARE
    c_cidade_lider  CONSTANT VARCHAR2(36) := 'aaaaaaaa-0000-0000-0000-000000000901';
    c_pinheiros     CONSTANT VARCHAR2(36) := 'aaaaaaaa-0000-0000-0000-000000000001';
    c_renan         CONSTANT VARCHAR2(36) := 'bbbbbbbb-0000-0000-0000-000000000901';
    c_marlene       CONSTANT VARCHAR2(36) := 'bbbbbbbb-0000-0000-0000-000000000902';
    c_jonas         CONSTANT VARCHAR2(36) := 'bbbbbbbb-0000-0000-0000-000000000903';
    c_gustavo       CONSTANT VARCHAR2(36) := 'bbbbbbbb-0000-0000-0000-000000000905';
    c_apoiador      CONSTANT VARCHAR2(36) := 'bbbbbbbb-0000-0000-0000-000000000950';
    c_sistema       CONSTANT VARCHAR2(36) := '00000000-0000-0000-0000-000000000001';
    c_cafe          CONSTANT VARCHAR2(36) := '33333333-0000-0000-0000-000000000960';
    c_inativo       CONSTANT VARCHAR2(36) := '33333333-0000-0000-0000-000000000965';
    c_parc_inativo  CONSTANT VARCHAR2(36) := '33333333-0000-0000-0000-000000000966';
    c_inexistente   CONSTANT VARCHAR2(36) := '99999999-9999-9999-9999-999999999999';

    v_passou   PLS_INTEGER := 0;
    v_falhou   PLS_INTEGER := 0;

    v_n        NUMBER;
    v_n2       NUMBER;
    v_txt      VARCHAR2(600 CHAR);
    v_antes    NUMBER;
    v_depois   NUMBER;

    v_expiradas   NUMBER;
    v_concluidas  NUMBER;
    v_estornados  NUMBER;
    v_falhas      NUMBER;

    v_resgate_id   VARCHAR2(36);
    v_resgate_id2  VARCHAR2(36);
    v_codigo       VARCHAR2(8);
    v_codigo2      VARCHAR2(8);
    v_saldo        NUMBER;
    v_replay       NUMBER;
    v_membros      NUMBER;
    v_ganhos       NUMBER;

    PROCEDURE conferir (p_nome IN VARCHAR2, p_ok IN BOOLEAN, p_detalhe IN VARCHAR2 DEFAULT NULL) IS
    BEGIN
        IF p_ok THEN
            v_passou := v_passou + 1;
            DBMS_OUTPUT.PUT_LINE('  ok     ' || p_nome);
        ELSE
            -- NULL também cai aqui: comparação que deu NULL não provou nada, então não passa.
            v_falhou := v_falhou + 1;
            DBMS_OUTPUT.PUT_LINE('  FALHOU ' || p_nome
                                 || CASE WHEN p_detalhe IS NOT NULL THEN ' — ' || p_detalhe END);
        END IF;
    END conferir;

    PROCEDURE igual (p_nome IN VARCHAR2, p_obtido IN NUMBER, p_esperado IN NUMBER) IS
    BEGIN
        conferir(p_nome, p_obtido = p_esperado,
                 'esperado ' || NVL(TO_CHAR(p_esperado), 'NULL')
                 || ', obtido ' || NVL(TO_CHAR(p_obtido), 'NULL'));
    END igual;

    FUNCTION saldo_de (p_usuario IN VARCHAR2) RETURN NUMBER IS
        v NUMBER;
    BEGIN
        SELECT saldo_tokens INTO v FROM ot_carteira WHERE usuario_id = p_usuario;
        RETURN v;
    END saldo_de;

    FUNCTION status_de (p_missao IN VARCHAR2) RETURN VARCHAR2 IS
        v ot_missao.status%TYPE;
    BEGIN
        SELECT status INTO v FROM ot_missao WHERE id = p_missao;
        RETURN v;
    END status_de;

    -- Soma que a economia conserva: o que está em carteiras mais o que está em potes.
    FUNCTION total_em_circulacao RETURN NUMBER IS
        v NUMBER;
    BEGIN
        SELECT (SELECT SUM(saldo_tokens) FROM ot_carteira) + (SELECT SUM(pote_tokens) FROM ot_missao)
          INTO v FROM dual;
        RETURN v;
    END total_em_circulacao;

    FUNCTION carteiras_divergentes RETURN NUMBER IS
        v NUMBER;
    BEGIN
        SELECT COUNT(*) INTO v FROM ot_carteira WHERE fn_ot_divergencia_carteira(id) <> 0;
        RETURN v;
    END carteiras_divergentes;
BEGIN
    DBMS_OUTPUT.PUT_LINE('== Estado inicial ==');
    igual('carga deixa o ledger integro (0 carteiras divergentes)', carteiras_divergentes, 0);
    igual('Renan comeca com 56 tokens (124 - 25 - 18 - 25)', saldo_de(c_renan), 56);
    igual('apoiador comeca com 4965 tokens (5000 - 15 - 20)', saldo_de(c_apoiador), 4965);

    DBMS_OUTPUT.PUT_LINE('== FN_OT_FORMATAR_TOKENS ==');
    conferir('1234 -> "1.234 tokens"', fn_ot_formatar_tokens(1234) = '1.234 tokens',
             fn_ot_formatar_tokens(1234));
    conferir('1 -> "1 token" (singular)', fn_ot_formatar_tokens(1) = '1 token',
             fn_ot_formatar_tokens(1));
    conferir('0 -> "0 tokens"', fn_ot_formatar_tokens(0) = '0 tokens', fn_ot_formatar_tokens(0));
    conferir('NULL -> travessao, nao zero', fn_ot_formatar_tokens(NULL) = '—');

    DBMS_OUTPUT.PUT_LINE('== FN_OT_NOVO_ID ==');
    conferir('formato 8-4-4-4-12 minusculo',
             REGEXP_LIKE(fn_ot_novo_id, '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'));
    conferir('duas chamadas dao ids diferentes', fn_ot_novo_id <> fn_ot_novo_id);

    DBMS_OUTPUT.PUT_LINE('== FN_OT_TAXA_CONCLUSAO_TRIBO ==');
    igual('Pinheiros: 7 concluidas de 7 encerradas = 100', fn_ot_taxa_conclusao_tribo(c_pinheiros), 100);
    conferir('Cidade Lider sem missao encerrada -> NULL, nao 0',
             fn_ot_taxa_conclusao_tribo(c_cidade_lider) IS NULL);
    BEGIN
        v_n := fn_ot_taxa_conclusao_tribo(c_inexistente);
        conferir('tribo inexistente levanta -20010', FALSE, 'nao levantou erro');
    EXCEPTION
        WHEN OTHERS THEN
            igual('tribo inexistente levanta -20010', SQLCODE, -20010);
    END;

    DBMS_OUTPUT.PUT_LINE('== FN_OT_DIVERGENCIA_CARTEIRA ==');
    igual('carteira do Renan: divergencia 0', fn_ot_divergencia_carteira('eeeeeeee-0000-0000-0000-000000000901'), 0);
    BEGIN
        v_n := fn_ot_divergencia_carteira(c_inexistente);
        conferir('carteira inexistente levanta -20011', FALSE, 'nao levantou erro');
    EXCEPTION
        WHEN OTHERS THEN
            igual('carteira inexistente levanta -20011', SQLCODE, -20011);
    END;
    -- Corrupção simulada dentro de um savepoint: a função tem de ENXERGAR a diferença.
    SAVEPOINT sp_corrupcao;
    UPDATE ot_carteira SET saldo_tokens = saldo_tokens + 7 WHERE usuario_id = c_renan;
    igual('saldo adulterado em +7 e detectado como +7',
          fn_ot_divergencia_carteira('eeeeeeee-0000-0000-0000-000000000901'), 7);
    ROLLBACK TO sp_corrupcao;

    DBMS_OUTPUT.PUT_LINE('== FN_OT_RESUMO_MISSAO ==');
    v_txt := fn_ot_resumo_missao('f6000000-0000-0000-0000-000000000001');
    conferir('C1 mostra estado, recompensa, tempo e pote',
             v_txt = '[Em andamento] Mutirão: reforma da quadra da rua Tapes · Tribo · 120 XP + '
                     || '40 tokens · Cidade Líder/SP · há 3 dias · pote: 40 tokens', v_txt);
    v_txt := fn_ot_resumo_missao('f6000000-0000-0000-0000-000000000004');
    conferir('C4 (sem pote) nao mostra o trecho do pote', v_txt NOT LIKE '%pote:%', v_txt);
    v_txt := fn_ot_resumo_missao(c_inexistente);
    conferir('missao inexistente devolve texto, nao erro',
             v_txt = '[Missão não encontrada] ' || c_inexistente, v_txt);

    DBMS_OUTPUT.PUT_LINE('== PRC_OT_VARRER_MISSOES_PARADAS ==');
    BEGIN
        prc_ot_varrer_missoes_paradas(p_prazo_execucao_h => -1, p_expiradas => v_expiradas,
                                      p_concluidas => v_concluidas,
                                      p_tokens_estornados => v_estornados, p_falhas => v_falhas);
        conferir('prazo negativo levanta -20020', FALSE, 'nao levantou erro');
    EXCEPTION
        WHEN OTHERS THEN
            igual('prazo negativo levanta -20020', SQLCODE, -20020);
    END;

    v_antes := total_em_circulacao;
    prc_ot_varrer_missoes_paradas(p_expiradas => v_expiradas, p_concluidas => v_concluidas,
                                  p_tokens_estornados => v_estornados, p_falhas => v_falhas);
    v_depois := total_em_circulacao;

    igual('2 missoes expiradas (C1 e C3)', v_expiradas, 2);
    igual('2 missoes concluidas por prazo (C2 e C4)', v_concluidas, 2);
    igual('60 tokens estornados (25 + 15 + 20)', v_estornados, 60);
    igual('1 falha isolada (C6, pote orfao)', v_falhas, 1);

    conferir('C1 EM_ANDAMENTO vencida -> EXPIRADA',
             status_de('f6000000-0000-0000-0000-000000000001') = 'EXPIRADA');
    conferir('C2 AGUARDANDO_CONFIRMACAO vencida -> CONCLUIDA',
             status_de('f6000000-0000-0000-0000-000000000002') = 'CONCLUIDA');
    conferir('C3 ABERTA com janela vencida -> EXPIRADA',
             status_de('f6000000-0000-0000-0000-000000000003') = 'EXPIRADA');
    conferir('C4 fonte CUNHAGEM -> CONCLUIDA',
             status_de('f6000000-0000-0000-0000-000000000004') = 'CONCLUIDA');
    conferir('C5 dentro do prazo continua EM_ANDAMENTO',
             status_de('f6000000-0000-0000-0000-000000000005') = 'EM_ANDAMENTO');
    conferir('C6 que falhou continua EM_ANDAMENTO (desfeita ate o savepoint)',
             status_de('f6000000-0000-0000-0000-000000000006') = 'EM_ANDAMENTO');

    SELECT SUM(pote_tokens) INTO v_n FROM ot_missao
     WHERE id IN ('f6000000-0000-0000-0000-000000000001', 'f6000000-0000-0000-0000-000000000002',
                  'f6000000-0000-0000-0000-000000000003');
    igual('potes de C1, C2 e C3 zerados', v_n, 0);
    SELECT pote_tokens INTO v_n FROM ot_missao WHERE id = 'f6000000-0000-0000-0000-000000000005';
    igual('pote de C5 intacto (18)', v_n, 18);
    SELECT pote_tokens INTO v_n FROM ot_missao WHERE id = 'f6000000-0000-0000-0000-000000000006';
    igual('pote de C6 intacto (10)', v_n, 10);

    igual('Renan: 56 + 25 de estorno + 22 da entrega = 103', saldo_de(c_renan), 103);
    igual('apoiador recebe os DOIS estornos de volta: 5000', saldo_de(c_apoiador), 5000);
    igual('Marlene recebe a recompensa do pote: 42 + 30 = 72', saldo_de(c_marlene), 72);
    igual('Jonas nao recebe estorno de missao concluida: 50', saldo_de(c_jonas), 50);

    SELECT xp, nivel INTO v_n, v_n2 FROM ot_usuario WHERE id = c_marlene;
    igual('Marlene: XP 120 + 90 = 210', v_n, 210);
    igual('Marlene: nivel derivado de 210 XP = 2', v_n2, 2);
    SELECT xp, nivel INTO v_n, v_n2 FROM ot_usuario WHERE id = c_renan;
    igual('Renan: XP 450 + 66 = 516', v_n, 516);
    igual('Renan: nivel derivado de 516 XP = 3', v_n2, 3);

    igual('conservacao: a soma so muda pelos 22 tokens emitidos em C4', v_depois - v_antes, 22);
    igual('ledger continua integro depois da varredura', carteiras_divergentes, 0);

    SELECT COUNT(*) INTO v_n FROM ot_lancamento WHERE motivo = 'ESTORNO';
    igual('3 lancamentos de ESTORNO (um por financiamento)', v_n, 3);
    SELECT COUNT(*) INTO v_n FROM ot_missao_evento
     WHERE tipo IN ('EXPIRADA', 'EXECUCAO_EXPIRADA', 'CONFIRMACAO_EXPIRADA') AND ator_id IS NULL;
    igual('4 eventos de trilha gravados pelo sistema', v_n, 4);
    SELECT COUNT(*) INTO v_n FROM ot_alerta WHERE tipo = 'ESTORNO_RECEBIDO';
    igual('3 alertas de estorno aos financiadores', v_n, 3);
    SELECT COUNT(*) INTO v_n FROM ot_alerta WHERE tipo = 'MISSAO_EXPIRADA';
    igual('2 alertas de missao expirada aos criadores', v_n, 2);
    SELECT COUNT(*) INTO v_n FROM ot_alerta
     WHERE tipo = 'VARREDURA_FALHOU' AND missao_id = 'f6000000-0000-0000-0000-000000000006'
       AND prioridade = 2 AND corpo LIKE '%ORA-20021%';
    igual('1 alerta operacional da falha de C6, com o codigo do erro', v_n, 1);

    igual('Cidade Lider apos a varredura: 2 de 4 encerradas = 50',
          fn_ot_taxa_conclusao_tribo(c_cidade_lider), 50);

    -- Idempotência: a segunda execução não tem mais o que tratar.
    v_antes := total_em_circulacao;
    prc_ot_varrer_missoes_paradas(p_expiradas => v_expiradas, p_concluidas => v_concluidas,
                                  p_tokens_estornados => v_estornados, p_falhas => v_falhas);
    igual('segunda varredura: 0 expiradas', v_expiradas, 0);
    igual('segunda varredura: 0 concluidas', v_concluidas, 0);
    igual('segunda varredura: 0 tokens estornados', v_estornados, 0);
    igual('segunda varredura nao move token nenhum', total_em_circulacao - v_antes, 0);

    -- C2 sem a prova: a mesma missão, se não houvesse check-in válido, NÃO pode ser paga.
    SAVEPOINT sp_sem_prova;
    INSERT INTO ot_missao (id, criador_id, executor_id, categoria, titulo, status, xp_recompensa,
                           tokens_recompensa, pote_tokens, fonte_pote, bairro, cidade, uf,
                           janela_inicio, janela_fim, estado_desde)
    VALUES ('f6000000-0000-0000-0000-0000000000aa', c_jonas, c_gustavo, 'ENTREGA',
            'Sem check-in', 'AGUARDANDO_CONFIRMACAO', 30, 10, 0, 'CUNHAGEM', 'Cidade Líder',
            'São Paulo', 'SP', SYSTIMESTAMP - INTERVAL '200' HOUR, SYSTIMESTAMP + INTERVAL '1' HOUR,
            SYSTIMESTAMP - INTERVAL '100' HOUR);
    prc_ot_varrer_missoes_paradas(p_expiradas => v_expiradas, p_concluidas => v_concluidas,
                                  p_tokens_estornados => v_estornados, p_falhas => v_falhas);
    igual('sem check-in valido nao ha pagamento: 0 concluidas', v_concluidas, 0);
    igual('Gustavo continua com 0 tokens', saldo_de(c_gustavo), 0);
    ROLLBACK TO sp_sem_prova;

    DBMS_OUTPUT.PUT_LINE('== PRC_OT_RESGATAR_BENEFICIO ==');
    v_antes := total_em_circulacao;
    prc_ot_resgatar_beneficio(c_marlene, c_cafe, 'teste-cafe-1', v_resgate_id, v_codigo, v_saldo,
                              v_replay);
    igual('resgate debita o custo: 72 - 15 = 57', v_saldo, 57);
    igual('saldo gravado na carteira e o devolvido', saldo_de(c_marlene), 57);
    igual('primeira chamada nao e replay', v_replay, 0);
    conferir('codigo de retirada tem 8 caracteres sem 0, O, 1, I',
             REGEXP_LIKE(v_codigo, '^[A-HJ-NP-Z2-9]{8}$'), v_codigo);
    igual('resgate QUEIMA: a soma em circulacao cai exatamente 15', v_antes - total_em_circulacao, 15);
    SELECT COUNT(*) INTO v_n FROM ot_lancamento
     WHERE id = v_resgate_id AND motivo = 'RESGATE' AND sinal = 'DEBITO' AND valor_tokens = 15
       AND contraparte_carteira_id IS NULL AND missao_id IS NULL;
    igual('lancamento RESGATE sem contraparte e sem missao, com o id do resgate', v_n, 1);
    SELECT COUNT(*) INTO v_n FROM ot_resgate
     WHERE id = v_resgate_id AND status = 'PENDENTE' AND custo_tokens = 15;
    igual('resgate nasce PENDENTE com o custo congelado', v_n, 1);

    prc_ot_resgatar_beneficio(c_marlene, c_cafe, 'teste-cafe-1', v_resgate_id2, v_codigo2, v_saldo,
                              v_replay);
    igual('mesma chave: replay', v_replay, 1);
    conferir('replay devolve o MESMO resgate e o MESMO codigo',
             v_resgate_id2 = v_resgate_id AND v_codigo2 = v_codigo);
    igual('replay nao debita de novo: saldo segue 57', saldo_de(c_marlene), 57);

    -- A mesma chave de cliente, usada por OUTRO usuário, não pode devolver o resgate da Marlene.
    prc_ot_resgatar_beneficio(c_jonas, c_cafe, 'teste-cafe-1', v_resgate_id2, v_codigo2, v_saldo,
                              v_replay);
    conferir('chave igual de outro usuario gera resgate proprio',
             v_replay = 0 AND v_resgate_id2 <> v_resgate_id);
    igual('Jonas: 50 - 15 = 35', v_saldo, 35);

    BEGIN
        prc_ot_resgatar_beneficio(c_gustavo, c_cafe, 'teste-sem-saldo', v_resgate_id2, v_codigo2,
                                  v_saldo, v_replay);
        conferir('saldo insuficiente levanta -20033', FALSE, 'nao levantou erro');
    EXCEPTION
        WHEN OTHERS THEN
            igual('saldo insuficiente levanta -20033', SQLCODE, -20033);
    END;
    igual('saldo insuficiente nao grava nada: Gustavo segue com 0', saldo_de(c_gustavo), 0);

    BEGIN
        prc_ot_resgatar_beneficio(c_renan, c_inativo, 'teste-inativo', v_resgate_id2, v_codigo2,
                                  v_saldo, v_replay);
        conferir('beneficio inativo levanta -20031', FALSE, 'nao levantou erro');
    EXCEPTION
        WHEN OTHERS THEN
            igual('beneficio inativo levanta -20031', SQLCODE, -20031);
    END;
    BEGIN
        prc_ot_resgatar_beneficio(c_renan, c_parc_inativo, 'teste-parc', v_resgate_id2, v_codigo2,
                                  v_saldo, v_replay);
        conferir('beneficio de parceiro inativo levanta -20031', FALSE, 'nao levantou erro');
    EXCEPTION
        WHEN OTHERS THEN
            igual('beneficio de parceiro inativo levanta -20031', SQLCODE, -20031);
    END;
    BEGIN
        prc_ot_resgatar_beneficio(c_renan, c_inexistente, 'teste-inex', v_resgate_id2, v_codigo2,
                                  v_saldo, v_replay);
        conferir('beneficio inexistente levanta o MESMO -20031', FALSE, 'nao levantou erro');
    EXCEPTION
        WHEN OTHERS THEN
            igual('beneficio inexistente levanta o MESMO -20031', SQLCODE, -20031);
    END;
    BEGIN
        prc_ot_resgatar_beneficio(c_sistema, c_cafe, 'teste-sem-carteira', v_resgate_id2,
                                  v_codigo2, v_saldo, v_replay);
        conferir('usuario sem carteira levanta -20032', FALSE, 'nao levantou erro');
    EXCEPTION
        WHEN OTHERS THEN
            igual('usuario sem carteira levanta -20032', SQLCODE, -20032);
    END;
    BEGIN
        prc_ot_resgatar_beneficio(c_renan, c_cafe, NULL, v_resgate_id2, v_codigo2, v_saldo,
                                  v_replay);
        conferir('chave nula levanta -20030', FALSE, 'nao levantou erro');
    EXCEPTION
        WHEN OTHERS THEN
            igual('chave nula levanta -20030', SQLCODE, -20030);
    END;
    igual('ledger continua integro depois dos resgates', carteiras_divergentes, 0);

    DBMS_OUTPUT.PUT_LINE('== PRC_OT_RELATORIO_TRIBO ==');
    prc_ot_relatorio_tribo(c_cidade_lider, v_membros, v_ganhos);
    igual('Cidade Lider tem 3 membros ativos', v_membros, 3);
    igual('tokens ganhos pela tribo: 22 + 30 + 37 = 89', v_ganhos, 89);
    SELECT COUNT(*) INTO v_n FROM ot_relatorio_tribo WHERE tribo_id = c_cidade_lider;
    igual('3 linhas gravadas em OT_RELATORIO_TRIBO', v_n, 3);
    SELECT tokens_ganhos, tokens_financiados INTO v_n, v_n2
      FROM ot_relatorio_tribo WHERE usuario_id = c_renan;
    igual('Renan ganhou 22', v_n, 22);
    igual('Renan financiou 94 liquidos (38 + 38 + 25 + 18 - 25 de estorno)', v_n2, 94);
    SELECT tokens_resgatados, missoes_concluidas INTO v_n, v_n2
      FROM ot_relatorio_tribo WHERE usuario_id = c_marlene;
    igual('Marlene resgatou 15', v_n, 15);
    igual('Marlene concluiu 1 missao', v_n2, 1);
    prc_ot_relatorio_tribo(c_cidade_lider, v_membros, v_ganhos);
    SELECT COUNT(*) INTO v_n FROM ot_relatorio_tribo WHERE tribo_id = c_cidade_lider;
    igual('segunda execucao substitui a fotografia, nao duplica', v_n, 3);
    BEGIN
        prc_ot_relatorio_tribo(c_inexistente, v_membros, v_ganhos);
        conferir('tribo inexistente levanta -20040', FALSE, 'nao levantou erro');
    EXCEPTION
        WHEN OTHERS THEN
            igual('tribo inexistente levanta -20040', SQLCODE, -20040);
    END;

    DBMS_OUTPUT.PUT_LINE('== Regras garantidas pelo banco ==');
    BEGIN
        UPDATE ot_lancamento SET valor_tokens = 1 WHERE ROWNUM = 1;
        conferir('UPDATE em OT_LANCAMENTO e rejeitado', FALSE, 'o UPDATE passou');
    EXCEPTION
        WHEN OTHERS THEN
            igual('UPDATE em OT_LANCAMENTO e rejeitado (-20090)', SQLCODE, -20090);
    END;
    BEGIN
        DELETE FROM ot_lancamento WHERE ROWNUM = 1;
        conferir('DELETE em OT_LANCAMENTO e rejeitado', FALSE, 'o DELETE passou');
    EXCEPTION
        WHEN OTHERS THEN
            igual('DELETE em OT_LANCAMENTO e rejeitado (-20090)', SQLCODE, -20090);
    END;
    BEGIN
        DELETE FROM ot_checkin WHERE ROWNUM = 1;
        conferir('DELETE em OT_CHECKIN e rejeitado', FALSE, 'o DELETE passou');
    EXCEPTION
        WHEN OTHERS THEN
            igual('DELETE em OT_CHECKIN e rejeitado (-20092)', SQLCODE, -20092);
    END;
    BEGIN
        UPDATE ot_carteira SET saldo_tokens = -1 WHERE usuario_id = c_gustavo;
        conferir('saldo negativo e rejeitado pela CHECK', FALSE, 'o UPDATE passou');
    EXCEPTION
        WHEN OTHERS THEN
            igual('saldo negativo e rejeitado pela CHECK (ORA-02290)', SQLCODE, -2290);
    END;
    BEGIN
        INSERT INTO ot_beneficio (id, parceiro_id, titulo, descricao, custo_tokens, tipo)
        VALUES (fn_ot_novo_id, '22222222-0000-0000-0000-000000000000', 'x', 'x', 1, 'BEM');
        conferir('beneficio de parceiro inexistente e rejeitado pela FK', FALSE, 'o INSERT passou');
    EXCEPTION
        WHEN OTHERS THEN
            igual('beneficio de parceiro inexistente e rejeitado pela FK (ORA-02291)', SQLCODE, -2291);
    END;
    BEGIN
        INSERT INTO ot_beneficio (id, parceiro_id, titulo, descricao, custo_tokens, tipo)
        SELECT fn_ot_novo_id, parceiro_id, 'Vale de R$ 10', 'Desconto no caixa', 30, 'BEM'
          FROM ot_beneficio WHERE id = c_cafe;
        conferir('beneficio precificado em reais e rejeitado', FALSE, 'o INSERT passou');
    EXCEPTION
        WHEN OTHERS THEN
            igual('beneficio precificado em reais e rejeitado pela CHECK (ORA-02290)', SQLCODE, -2290);
    END;
    BEGIN
        INSERT INTO ot_beneficio (id, parceiro_id, titulo, descricao, custo_tokens, tipo)
        SELECT fn_ot_novo_id, parceiro_id, 'Cesta do mês', 'Vale 20 reais em compras', 30, 'BEM'
          FROM ot_beneficio WHERE id = c_cafe;
        conferir('"reais" na descricao tambem e rejeitado', FALSE, 'o INSERT passou');
    EXCEPTION
        WHEN OTHERS THEN
            igual('"reais" na descricao tambem e rejeitado (ORA-02290)', SQLCODE, -2290);
    END;

    ROLLBACK;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('== ' || v_passou || ' de ' || (v_passou + v_falhou)
                         || ' testes passaram · ROLLBACK feito ==');

    IF v_falhou > 0 THEN
        RAISE_APPLICATION_ERROR(-20099, v_falhou || ' teste(s) falharam.');
    END IF;
END;
/
