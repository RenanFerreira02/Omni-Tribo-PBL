-- =============================================================================================
-- Omni-Tribo · PBL Fase 6 · instalar.sql
-- Instala a camada Oracle do zero: remove a instalação anterior, cria as tabelas, carrega os
-- dados, compila functions e procedures, e termina conferindo o resultado.
--
-- Uso (a partir da pasta Oracle/sql, com SQLcl ou SQL*Plus):
--   sql usuario/senha@//oracle.fiap.com.br:1521/ORCL @instalar.sql
--
-- É repetível: rodar de novo devolve o banco ao estado inicial dos cenários.
-- =============================================================================================
SET DEFINE OFF
SET SERVEROUTPUT ON SIZE UNLIMITED
SET SQLBLANKLINES ON
SET LINESIZE 200
SET PAGESIZE 100
WHENEVER SQLERROR EXIT FAILURE ROLLBACK

PROMPT
PROMPT == Servidor ==
SELECT banner FROM v$version WHERE ROWNUM = 1;

PROMPT == 00 · removendo instalacao anterior ==
@@00_desinstalar.sql

PROMPT == 01 · tabelas ==
@@01_tabelas.sql

PROMPT == 02 · carga do seed do projeto ==
SET FEEDBACK OFF
@@02_carga_seed.sql
SET FEEDBACK ON

PROMPT == 03 · carga dos cenarios simulados ==
@@03_carga_cenarios.sql

PROMPT == 04 · functions ==
@@04_functions.sql

PROMPT == 05 · procedures ==
@@05_procedures.sql

PROMPT
PROMPT == Objetos instalados (todos devem estar VALID) ==
COLUMN object_name FORMAT A34
COLUMN object_type FORMAT A12
COLUMN status      FORMAT A8
SELECT object_type, object_name, status
  FROM user_objects
 WHERE object_name LIKE 'OT\_%' ESCAPE '\'
    OR object_name LIKE 'FN\_OT\_%' ESCAPE '\'
    OR object_name LIKE 'PRC\_OT\_%' ESCAPE '\'
    OR object_name LIKE 'TRG\_OT\_%' ESCAPE '\'
 ORDER BY DECODE(object_type, 'TABLE', 1, 'TRIGGER', 2, 'FUNCTION', 3, 'PROCEDURE', 4, 5),
          object_name;

PROMPT == Erros de compilacao (nenhuma linha = nenhum erro) ==
COLUMN name FORMAT A34
COLUMN text FORMAT A100
SELECT name, line, text
  FROM user_errors
 WHERE name LIKE '%OT\_%' ESCAPE '\'
 ORDER BY name, sequence;

PROMPT == Linhas carregadas ==
SELECT 'OT_TRIBO' AS tabela, COUNT(*) AS linhas FROM ot_tribo
UNION ALL SELECT 'OT_USUARIO',       COUNT(*) FROM ot_usuario
UNION ALL SELECT 'OT_CARTEIRA',      COUNT(*) FROM ot_carteira
UNION ALL SELECT 'OT_LANCAMENTO',    COUNT(*) FROM ot_lancamento
UNION ALL SELECT 'OT_MISSAO',        COUNT(*) FROM ot_missao
UNION ALL SELECT 'OT_MISSAO_EVENTO', COUNT(*) FROM ot_missao_evento
UNION ALL SELECT 'OT_CHECKIN',       COUNT(*) FROM ot_checkin
UNION ALL SELECT 'OT_PARCEIRO',      COUNT(*) FROM ot_parceiro
UNION ALL SELECT 'OT_BENEFICIO',     COUNT(*) FROM ot_beneficio
UNION ALL SELECT 'OT_RESGATE',       COUNT(*) FROM ot_resgate
UNION ALL SELECT 'OT_ALERTA',        COUNT(*) FROM ot_alerta;

PROMPT == Instalacao concluida ==
