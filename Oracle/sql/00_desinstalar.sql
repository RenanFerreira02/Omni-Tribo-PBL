-- =============================================================================================
-- Omni-Tribo · PBL Fase 6 · 00_desinstalar.sql
-- Remove SOMENTE os objetos deste projeto: os que começam com OT_, FN_OT_, PRC_OT_ ou TRG_OT_.
--
-- O schema do aluno é compartilhado com outras disciplinas. Este script lê o dicionário de dados
-- e apaga pelo PREFIXO — nunca um "drop tudo" — então tabela de outra matéria não é tocada.
-- Pode ser executado com o schema vazio: não encontrar nada não é erro.
-- =============================================================================================
SET SERVEROUTPUT ON

DECLARE
    v_removidos  PLS_INTEGER := 0;
BEGIN
    -- Rotinas primeiro: dependem das tabelas, e apagá-las antes evita objeto INVALID no meio.
    FOR r IN (SELECT object_name, object_type
                FROM user_objects
               WHERE object_type IN ('PROCEDURE', 'FUNCTION')
                 AND (object_name LIKE 'PRC\_OT\_%' ESCAPE '\'
                      OR object_name LIKE 'FN\_OT\_%' ESCAPE '\'))
    LOOP
        EXECUTE IMMEDIATE 'DROP ' || r.object_type || ' ' || r.object_name;
        v_removidos := v_removidos + 1;
    END LOOP;

    -- CASCADE CONSTRAINTS dispensa ordenar pelas FKs; PURGE não deixa resto na lixeira, que
    -- contaria na cota do schema. Os triggers TRG_OT_* caem junto com as tabelas.
    FOR r IN (SELECT table_name
                FROM user_tables
               WHERE table_name LIKE 'OT\_%' ESCAPE '\')
    LOOP
        EXECUTE IMMEDIATE 'DROP TABLE ' || r.table_name || ' CASCADE CONSTRAINTS PURGE';
        v_removidos := v_removidos + 1;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE(v_removidos || ' objeto(s) OT_ removido(s).');
END;
/
