-- =============================================================================================
-- Omni-Tribo · PBL Fase 6 · 06_consultas_de_uso.sql
-- Uso prático das functions DENTRO de consultas SQL e chamada das procedures.
--
-- O script termina em ROLLBACK: o que as procedures escreverem aqui é desfeito, e o banco volta
-- ao estado da instalação. Pode ser executado quantas vezes for preciso.
--
-- Uso (a partir da pasta Oracle/sql):
--   sql usuario/senha@//oracle.fiap.com.br:1521/ORCL @06_consultas_de_uso.sql
-- =============================================================================================
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 220
SET PAGESIZE 100
SET FEEDBACK OFF

COLUMN tribo            FORMAT A22
COLUMN taxa_conclusao   FORMAT A16
COLUMN handle           FORMAT A16
COLUMN situacao         FORMAT A10
COLUMN resumo           FORMAT A150
COLUMN codigo_rejeicao  FORMAT A24
COLUMN tipo             FORMAT A20
COLUMN titulo           FORMAT A32
COLUMN corpo            FORMAT A150
COLUMN indicador        FORMAT A44
COLUMN valor            FORMAT A16

PROMPT
PROMPT == 1. Ranking de tribos pela taxa de conclusao ==
PROMPT    FN_OT_TAXA_CONCLUSAO_TRIBO na lista do SELECT e no ORDER BY.
PROMPT    "sem dado" e diferente de 0%: a tribo ainda nao encerrou missao nenhuma.
SELECT t.nome AS tribo,
       (SELECT COUNT(*) FROM ot_usuario u WHERE u.tribo_id = t.id) AS membros,
       CASE WHEN fn_ot_taxa_conclusao_tribo(t.id) IS NULL THEN 'sem dado'
            ELSE TO_CHAR(fn_ot_taxa_conclusao_tribo(t.id), 'FM990D00',
                         'NLS_NUMERIC_CHARACTERS='',.''') || ' %'
       END AS taxa_conclusao
  FROM ot_tribo t
 ORDER BY fn_ot_taxa_conclusao_tribo(t.id) DESC NULLS LAST, t.nome;

PROMPT
PROMPT == 2. Reconciliacao: carteira x livro-razao ==
PROMPT    FN_OT_DIVERGENCIA_CARTEIRA na lista do SELECT. Zero em todas = ledger integro.
SELECT u.handle,
       c.saldo_tokens,
       fn_ot_divergencia_carteira(c.id) AS divergencia,
       CASE WHEN fn_ot_divergencia_carteira(c.id) = 0 THEN 'integra' ELSE 'DIVERGE' END AS situacao
  FROM ot_carteira c
  JOIN ot_usuario  u ON u.id = c.usuario_id
 ORDER BY u.handle;

PROMPT
PROMPT    A mesma function no WHERE: so as carteiras que divergem (nenhuma linha = tudo integro).
SELECT u.handle, fn_ot_divergencia_carteira(c.id) AS divergencia
  FROM ot_carteira c
  JOIN ot_usuario  u ON u.id = c.usuario_id
 WHERE fn_ot_divergencia_carteira(c.id) <> 0;

PROMPT
PROMPT == 3. Potes imobilizados: token preso em missao que nao terminou ==
PROMPT    FN_OT_RESUMO_MISSAO formata a linha. E o diagnostico que a reconciliacao acima NAO faz:
PROMPT    todas as carteiras estao integras e, ainda assim, ha token parado aqui.
SELECT fn_ot_resumo_missao(m.id) AS resumo
  FROM ot_missao m
 WHERE m.status IN ('EM_ANDAMENTO', 'AGUARDANDO_CONFIRMACAO', 'EM_DISPUTA')
   AND m.pote_tokens > 0
 ORDER BY m.estado_desde;

PROMPT
PROMPT == 4. Leituras criticas de GPS: check-ins rejeitados por motivo ==
SELECT codigo_rejeicao,
       COUNT(*)                        AS leituras,
       ROUND(AVG(distancia_alvo_m), 1) AS distancia_media_m,
       ROUND(AVG(acuracia_m), 1)       AS acuracia_media_m
  FROM ot_checkin
 WHERE valido = 0
 GROUP BY codigo_rejeicao
 ORDER BY leituras DESC, codigo_rejeicao;

PROMPT
PROMPT == 5. A economia em numeros ==
PROMPT    FN_OT_FORMATAR_TOKENS formata cada valor. O aporte emite e o resgate queima;
PROMPT    financiamento e estorno so movem token entre carteira e pote.
SELECT 'Emitido por aporte de apoiador' AS indicador,
       fn_ot_formatar_tokens((SELECT NVL(SUM(valor_tokens), 0) FROM ot_lancamento
                               WHERE motivo = 'APORTE_PATROCINADOR')) AS valor
  FROM dual
UNION ALL
SELECT 'Pago em recompensa de missao',
       fn_ot_formatar_tokens((SELECT NVL(SUM(valor_tokens), 0) FROM ot_lancamento
                               WHERE motivo = 'RECOMPENSA_MISSAO'))
  FROM dual
UNION ALL
SELECT 'Financiado em potes (liquido de estorno)',
       fn_ot_formatar_tokens((SELECT NVL(SUM(CASE WHEN motivo = 'ESTORNO' THEN -valor_tokens
                                                  ELSE valor_tokens END), 0)
                                FROM ot_lancamento
                               WHERE motivo IN ('FINANCIAMENTO_TRIBO',
                                                'FINANCIAMENTO_PATROCINADOR', 'ESTORNO')))
  FROM dual
UNION ALL
SELECT 'Queimado em resgate de beneficio',
       fn_ot_formatar_tokens((SELECT NVL(SUM(valor_tokens), 0) FROM ot_lancamento
                               WHERE motivo = 'RESGATE'))
  FROM dual
UNION ALL
SELECT 'Hoje em carteiras',
       fn_ot_formatar_tokens((SELECT SUM(saldo_tokens) FROM ot_carteira))
  FROM dual
UNION ALL
SELECT 'Hoje em potes de missao',
       fn_ot_formatar_tokens((SELECT SUM(pote_tokens) FROM ot_missao))
  FROM dual;

PROMPT
PROMPT == 6. PRC_OT_VARRER_MISSOES_PARADAS ==
PROMPT    Prazos padrao: 48 h de execucao, 72 h de confirmacao.
DECLARE
    v_expiradas   NUMBER;
    v_concluidas  NUMBER;
    v_estornados  NUMBER;
    v_falhas      NUMBER;
BEGIN
    prc_ot_varrer_missoes_paradas(p_expiradas         => v_expiradas,
                                  p_concluidas        => v_concluidas,
                                  p_tokens_estornados => v_estornados,
                                  p_falhas            => v_falhas);
END;
/

PROMPT
PROMPT    O que a varredura deixou: as missoes dos cenarios, pela function de resumo.
SELECT fn_ot_resumo_missao(m.id) AS resumo
  FROM ot_missao m
 WHERE m.id LIKE 'f6%'
 ORDER BY m.id;

PROMPT
PROMPT    Os alertas que ela registrou.
SELECT a.tipo, NVL(u.handle, '(operacao)') AS handle, a.corpo
  FROM ot_alerta a
  LEFT JOIN ot_usuario u ON u.id = a.usuario_id
 WHERE a.tipo IN ('ESTORNO_RECEBIDO', 'MISSAO_EXPIRADA', 'VARREDURA_FALHOU')
    OR (a.tipo = 'MISSAO_CONCLUIDA' AND a.missao_id LIKE 'f6%')
 ORDER BY a.tipo, u.handle;

PROMPT
PROMPT    A taxa de conclusao da Cidade Lider depois da varredura (antes era "sem dado").
SELECT t.nome AS tribo,
       TO_CHAR(fn_ot_taxa_conclusao_tribo(t.id), 'FM990D00',
               'NLS_NUMERIC_CHARACTERS='',.''') || ' %' AS taxa_conclusao
  FROM ot_tribo t
 WHERE t.id = 'aaaaaaaa-0000-0000-0000-000000000901';

PROMPT
PROMPT == 7. PRC_OT_RESGATAR_BENEFICIO ==
PROMPT    Marlene troca 15 tokens por um cafe; a segunda chamada repete a MESMA chave.
DECLARE
    v_resgate_id  VARCHAR2(36);
    v_codigo      VARCHAR2(8);
    v_saldo       NUMBER;
    v_replay      NUMBER;
BEGIN
    FOR i IN 1 .. 2 LOOP
        prc_ot_resgatar_beneficio(p_usuario_id      => 'bbbbbbbb-0000-0000-0000-000000000902',
                                  p_beneficio_id    => '33333333-0000-0000-0000-000000000960',
                                  p_chave           => 'demo-cafe-marlene',
                                  p_resgate_id      => v_resgate_id,
                                  p_codigo_retirada => v_codigo,
                                  p_saldo_apos      => v_saldo,
                                  p_replay          => v_replay);

        DBMS_OUTPUT.PUT_LINE('chamada ' || i || ': resgate ' || v_resgate_id
                             || ' · codigo ' || v_codigo
                             || ' · saldo ' || fn_ot_formatar_tokens(v_saldo)
                             || CASE v_replay WHEN 1 THEN ' · REPLAY (nada foi debitado de novo)'
                                              ELSE ' · primeira vez' END);
    END LOOP;
END;
/

PROMPT
PROMPT == 8. PRC_OT_RELATORIO_TRIBO ==
DECLARE
    v_membros  NUMBER;
    v_ganhos   NUMBER;
BEGIN
    prc_ot_relatorio_tribo(p_tribo_id      => 'aaaaaaaa-0000-0000-0000-000000000901',
                           p_membros       => v_membros,
                           p_tokens_ganhos => v_ganhos);
END;
/

PROMPT
PROMPT    A mesma fotografia, lida da tabela que a procedure gravou.
SELECT handle, missoes_concluidas, tokens_ganhos, tokens_financiados, tokens_resgatados,
       saldo_tokens
  FROM ot_relatorio_tribo
 WHERE tribo_id = 'aaaaaaaa-0000-0000-0000-000000000901'
 ORDER BY tokens_ganhos DESC, handle;

ROLLBACK;
PROMPT
PROMPT == ROLLBACK: o banco voltou ao estado da instalacao ==
