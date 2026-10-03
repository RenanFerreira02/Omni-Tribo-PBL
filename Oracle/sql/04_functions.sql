-- =============================================================================================
-- Omni-Tribo · PBL Fase 6 · 04_functions.sql
-- Functions PL/SQL. Todas são de LEITURA (nenhuma faz DML), então podem ser usadas dentro de
-- SELECT — os usos estão em 06_consultas_de_uso.sql.
--
--   FN_OT_TAXA_CONCLUSAO_TRIBO   indicador   % de missões da tribo que terminaram concluídas
--   FN_OT_DIVERGENCIA_CARTEIRA   indicador   saldo projetado menos a soma do livro-razão
--   FN_OT_RESUMO_MISSAO          formatada   uma linha legível descrevendo a missão
--   FN_OT_FORMATAR_TOKENS        formatada   apoio: '1.234 tokens'
--   FN_OT_NOVO_ID                apoio       gera id no formato UUID usado pelo sistema de origem
--
-- Códigos de erro desta camada (faixa -20010 a -20019):
--   -20010  tribo inexistente
--   -20011  carteira inexistente
-- =============================================================================================

-- _____________________________________________________________________________________________
-- FN_OT_NOVO_ID
-- Propósito : gerar identificador no MESMO formato dos ids exportados do PostgreSQL
--             (8-4-4-4-12, minúsculo), para que linha criada aqui e linha vinda do seed sejam
--             indistinguíveis no tipo.
-- Retorno   : VARCHAR2(36)
-- _____________________________________________________________________________________________
CREATE OR REPLACE FUNCTION fn_ot_novo_id
    RETURN VARCHAR2
IS
BEGIN
    RETURN LOWER(REGEXP_REPLACE(RAWTOHEX(SYS_GUID()),
                                '(.{8})(.{4})(.{4})(.{4})(.{12})',
                                '\1-\2-\3-\4-\5'));
END fn_ot_novo_id;
/

-- _____________________________________________________________________________________________
-- FN_OT_FORMATAR_TOKENS
-- Propósito : apresentar quantidade de token com separador de milhar e unidade.
-- Parâmetro : p_tokens IN — quantidade inteira; NULL é tratado como ausência de dado.
-- Retorno   : '1.234 tokens', '1 token' ou '—' quando não há valor.
-- Nota      : o separador é fixado na chamada. Depender do NLS da sessão faria o mesmo relatório
--             sair com ponto numa máquina e vírgula em outra.
-- _____________________________________________________________________________________________
CREATE OR REPLACE FUNCTION fn_ot_formatar_tokens (
    p_tokens IN NUMBER
) RETURN VARCHAR2
IS
BEGIN
    IF p_tokens IS NULL THEN
        RETURN '—';
    END IF;

    RETURN TRIM(TO_CHAR(p_tokens, '999G999G999G990', 'NLS_NUMERIC_CHARACTERS='',.'''))
           || CASE WHEN ABS(p_tokens) = 1 THEN ' token' ELSE ' tokens' END;
END fn_ot_formatar_tokens;
/

-- _____________________________________________________________________________________________
-- FN_OT_TAXA_CONCLUSAO_TRIBO                                              [INDICADOR]
-- Propósito : medir quanto do trabalho pedido por uma tribo chegou ao fim. É o indicador de
--             saúde do bairro: uma tribo que publica muito e conclui pouco está expirando
--             missão, e pote expirado é token que voltou sem ter remunerado ninguém.
-- Parâmetro : p_tribo_id IN — id da tribo.
-- Retorno   : percentual de 0 a 100, com duas casas, de missões CONCLUIDA sobre o total de
--             missões ENCERRADAS (CONCLUIDA + CANCELADA + EXPIRADA) cujos criadores são da tribo.
--             NULL quando a tribo ainda não encerrou missão nenhuma.
-- Por que NULL e não 0: "0% de conclusão" e "não há o que dividir" são coisas diferentes. A
--             primeira é desempenho ruim; a segunda é ausência de dado. Devolver 0 colocaria uma
--             tribo recém-criada no fim do ranking por um motivo que não é dela.
-- Por que só as encerradas: missão ainda aberta não fracassou nem deu certo; contá-la no
--             denominador puniria a tribo por ter trabalho em andamento.
-- Exceções  : -20010 se a tribo não existe. ZERO_DIVIDE é tratado e vira NULL.
-- _____________________________________________________________________________________________
CREATE OR REPLACE FUNCTION fn_ot_taxa_conclusao_tribo (
    p_tribo_id IN VARCHAR2
) RETURN NUMBER
IS
    v_existe      NUMBER;
    v_concluidas  NUMBER;
    v_encerradas  NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_existe FROM ot_tribo WHERE id = p_tribo_id;
    IF v_existe = 0 THEN
        RAISE_APPLICATION_ERROR(-20010, 'Tribo inexistente: ' || p_tribo_id);
    END IF;

    SELECT COUNT(CASE WHEN m.status = 'CONCLUIDA' THEN 1 END),
           COUNT(*)
      INTO v_concluidas, v_encerradas
      FROM ot_missao m
      JOIN ot_usuario u ON u.id = m.criador_id
     WHERE u.tribo_id = p_tribo_id
       AND m.status IN ('CONCLUIDA', 'CANCELADA', 'EXPIRADA');

    RETURN ROUND(v_concluidas / v_encerradas * 100, 2);
EXCEPTION
    WHEN ZERO_DIVIDE THEN
        -- Nenhuma missão encerrada: não há taxa a calcular.
        RETURN NULL;
END fn_ot_taxa_conclusao_tribo;
/

-- _____________________________________________________________________________________________
-- FN_OT_DIVERGENCIA_CARTEIRA                                              [INDICADOR]
-- Propósito : reconciliar uma carteira. O saldo em OT_CARTEIRA é uma projeção mantida a cada
--             movimento; a verdade é a soma do livro-razão OT_LANCAMENTO. Esta função devolve a
--             diferença entre os dois.
-- Parâmetro : p_carteira_id IN — id da carteira.
-- Retorno   : saldo projetado MENOS a soma do ledger (créditos − débitos).
--             0  = carteira íntegra
--             >0 = a carteira mostra token que o ledger não explica
--             <0 = o ledger registra token que a carteira não mostra
-- Limite    : isto é RECONCILIAÇÃO, não conservação. Uma carteira pode estar íntegra enquanto um
--             pote fica preso numa missão parada — quem trata disso é PRC_OT_VARRER_MISSOES_PARADAS.
-- Exceções  : -20011 se a carteira não existe (NO_DATA_FOUND traduzido).
-- _____________________________________________________________________________________________
CREATE OR REPLACE FUNCTION fn_ot_divergencia_carteira (
    p_carteira_id IN VARCHAR2
) RETURN NUMBER
IS
    v_saldo_projetado  ot_carteira.saldo_tokens%TYPE;
    v_soma_ledger      NUMBER;
BEGIN
    SELECT saldo_tokens
      INTO v_saldo_projetado
      FROM ot_carteira
     WHERE id = p_carteira_id;

    -- Carteira sem lançamento soma NULL; NVL faz dela zero, que é o saldo de quem nunca movimentou.
    SELECT NVL(SUM(CASE sinal WHEN 'CREDITO' THEN valor_tokens ELSE -valor_tokens END), 0)
      INTO v_soma_ledger
      FROM ot_lancamento
     WHERE carteira_id = p_carteira_id;

    RETURN v_saldo_projetado - v_soma_ledger;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20011, 'Carteira inexistente: ' || p_carteira_id);
END fn_ot_divergencia_carteira;
/

-- _____________________________________________________________________________________________
-- FN_OT_RESUMO_MISSAO                                                     [DADOS FORMATADOS]
-- Propósito : descrever uma missão em uma linha legível, para listagem, relatório e alerta.
--             Junta o que está espalhado em colunas: estado, título, categoria, recompensa,
--             local, há quanto tempo está no estado atual e quanto há no pote.
-- Parâmetro : p_missao_id IN — id da missão.
-- Retorno   : texto no formato
--               [Em andamento] Mutirão da quadra · Tribo · 120 XP + 40 tokens ·
--               Cidade Líder/SP · há 3 dias · pote: 40 tokens
--             Para id desconhecido devolve '[Missão não encontrada] <id>' em vez de levantar
--             erro: a função é usada em colunas de SELECT, e uma linha órfã não deve derrubar a
--             consulta inteira.
-- Exceções  : NO_DATA_FOUND tratado (ver acima). Nenhuma outra é engolida.
-- _____________________________________________________________________________________________
CREATE OR REPLACE FUNCTION fn_ot_resumo_missao (
    p_missao_id IN VARCHAR2
) RETURN VARCHAR2
IS
    v_missao     ot_missao%ROWTYPE;
    v_estado     VARCHAR2(40);
    v_categoria  VARCHAR2(20);
    v_tempo      VARCHAR2(40);
    v_parado     INTERVAL DAY(9) TO SECOND;
    v_dias       NUMBER;
    v_horas      NUMBER;
    v_resumo     VARCHAR2(600 CHAR);
BEGIN
    SELECT * INTO v_missao FROM ot_missao WHERE id = p_missao_id;

    v_estado := CASE v_missao.status
                    WHEN 'RASCUNHO'               THEN 'Rascunho'
                    WHEN 'ABERTA'                 THEN 'Aberta'
                    WHEN 'ACEITA'                 THEN 'Aceita'
                    WHEN 'EM_ANDAMENTO'           THEN 'Em andamento'
                    WHEN 'AGUARDANDO_CONFIRMACAO' THEN 'Aguardando confirmação'
                    WHEN 'EM_DISPUTA'             THEN 'Em disputa'
                    WHEN 'CONCLUIDA'              THEN 'Concluída'
                    WHEN 'CANCELADA'              THEN 'Cancelada'
                    WHEN 'EXPIRADA'               THEN 'Expirada'
                    ELSE v_missao.status
                END;

    v_categoria := INITCAP(v_missao.categoria);

    v_parado := SYSTIMESTAMP - v_missao.estado_desde;
    v_dias   := EXTRACT(DAY FROM v_parado);
    v_horas  := EXTRACT(HOUR FROM v_parado);

    IF v_dias >= 2 THEN
        v_tempo := 'há ' || v_dias || ' dias';
    ELSIF v_dias = 1 THEN
        v_tempo := 'há 1 dia';
    ELSIF v_horas >= 1 THEN
        v_tempo := 'há ' || v_horas || ' h';
    ELSE
        v_tempo := 'há menos de 1 h';
    END IF;

    v_resumo := '[' || v_estado || '] ' || v_missao.titulo
                || ' · ' || v_categoria
                || ' · ' || v_missao.xp_recompensa || ' XP + '
                || fn_ot_formatar_tokens(v_missao.tokens_recompensa)
                || ' · ' || v_missao.bairro || '/' || v_missao.uf
                || ' · ' || v_tempo;

    -- O pote só interessa quando há token parado nele.
    IF v_missao.pote_tokens > 0 THEN
        v_resumo := v_resumo || ' · pote: ' || fn_ot_formatar_tokens(v_missao.pote_tokens);
    END IF;

    RETURN v_resumo;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RETURN '[Missão não encontrada] ' || p_missao_id;
END fn_ot_resumo_missao;
/
