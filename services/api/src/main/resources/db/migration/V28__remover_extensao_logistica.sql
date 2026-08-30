-- =============================================================================
-- V28 — Remoção da extensão logística (ADR 0031)
--
-- O produto passa a ser só o eixo social: missões de vizinhança, tribo, XP,
-- token comunitário e resgate em benefício de parceiro. Sai o ciclo da entrega
-- falida inteiro — webhook de transportadora, ponto de custódia e o modelo de
-- previsão de risco que existia para calibrar a recompensa daquelas missões.
--
-- POR QUE UMA MIGRATION NOVA, e não apagar a V6/V21/V22/V23:
-- aquelas migrations já foram aplicadas em todo banco que existe. Reescrevê-las
-- daria "Migration checksum mismatch" em máquina antiga e passaria em clone novo
-- — divergência que o CI nunca reproduz, porque lá o banco nasce do zero. É a
-- mesma armadilha registrada na V20:20-25 e na V21:18-28. O histórico fica: ele
-- é o registro de que a extensão existiu, e de quando.
--
-- O QUE NÃO É APAGADO, e o motivo de cada um, está na seção 3.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. As duas tabelas do eixo logístico.
--
-- entrega_falida PRIMEIRO: ela tem FK para ponto_custodia (V6:34), e a ordem
-- inversa falharia com "cannot drop table ponto_custodia because other objects
-- depend on it". Sem CASCADE de propósito — CASCADE apagaria em silêncio
-- qualquer dependência que este arquivo não previu, e a falha barulhenta é
-- preferível numa migration que remove dado.
--
-- Índices, CHECKs e GRANTs das duas caem junto com elas; não precisam de linha
-- própria.
-- -----------------------------------------------------------------------------
DROP TABLE entrega_falida;
DROP TABLE ponto_custodia;

-- -----------------------------------------------------------------------------
-- 2. As colunas de missao que só o webhook escrevia.
--
-- faixa_risco (V22:79) e ponto_custodia_id (V3:27) nasceram para a missão de
-- retirada e nunca tiveram outro escritor: missão criada por humano deixava as
-- duas nulas. Sem o webhook, elas seriam colunas permanentemente nulas, que é
-- pior que ausência — quem lê o schema supõe que existe um caminho que as
-- preenche.
--
-- ck_missao_faixa_risco cai junto com a coluna que ele restringe.
-- -----------------------------------------------------------------------------
ALTER TABLE missao DROP COLUMN faixa_risco;
ALTER TABLE missao DROP COLUMN ponto_custodia_id;

-- -----------------------------------------------------------------------------
-- 3. O que FICA, e por quê.
--
-- 3a. missao.multiplicador_risco (V16:51) fica, e fica SEM campo JPA
-- correspondente — `ddl-auto: validate` não reclama de coluna que nenhuma
-- entidade mapeia.
--
-- A diferença para as duas colunas da seção 2 é que esta EXPLICA DADO ANTIGO: a
-- recompensa em token de uma missão de retirada concluída foi multiplicada por
-- este número, e sem ele não há resposta para "este crédito estava certo quando
-- foi feito?". É a mesma razão pela qual o projeto congela versao_formula em vez
-- de recalcular: recalibrar não reescreve o passado. Apagá-la apagaria a única
-- explicação de valores que já foram creditados.
-- -----------------------------------------------------------------------------
COMMENT ON COLUMN missao.multiplicador_risco IS
  'HISTÓRICO. Multiplicador de risco congelado na criação das missões de retirada, quando a '
  'extensão logística existia (V16/V22). Nenhum código escreve esta coluna desde a V28 (ADR 0031); '
  'ela permanece porque é o que explica a recompensa em token das missões já concluídas.';

-- 3b. fonte_pote mantém os três valores no CHECK (V23:154). PATROCINADOR passa a
-- ser valor exclusivamente histórico: nenhuma missão nova nasce com ele, porque
-- quem o produzia era a conversão do webhook. Tirá-lo do CHECK exigiria reescrever
-- as linhas antigas para um valor que não descreve como aquele pote foi formado.
COMMENT ON COLUMN missao.fonte_pote IS
  'De onde sai o token que a missão paga. COMUNIDADE (financiada por membros ou por apoiador) e '
  'CUNHAGEM (ENTREGA criada por humano) são os valores vivos. PATROCINADOR é HISTÓRICO desde a '
  'V28: era a missão de retirada financiada na conversão do webhook de transportadora (ADR 0031).';

-- 3c. alerta.prioridade (V22:96) e idx_alerta_usuario_prioridade ficam. A coluna
-- é do módulo de notificações, não do de logística; o que sai é o único produtor
-- de PRIORIDADE_ALTA, que era a faixa de risco. Todo alerta passa a nascer com
-- prioridade normal, e a coluna continua sendo o lugar certo caso outra regra de
-- priorização apareça.

-- -----------------------------------------------------------------------------
-- 4. Patrocinador deixa de ser transportadora.
--
-- A tabela sobrevive porque APORTE_PATROCINADOR é o ÚNICO ponto de emissão de
-- token do sistema (V23, ADR 0024). Remover o patrocinador junto com a logística
-- deixaria a economia só com o sumidouro (RESGATE, ADR 0027): o token sairia de
-- circulação no resgate e nada a reporia — a soma cairia monotonicamente até zero.
--
-- O que muda é o SIGNIFICADO da relação, e a coluna precisa dizer a verdade:
-- transportadora_slug casava com o cabeçalho X-Transportadora do webhook, que não
-- existe mais. Vira `slug`, identificador do apoiador do bairro que aporta.
--
-- RENAME e não DROP+ADD: as linhas existentes têm slug, e um DROP apagaria a
-- identidade de patrocinadores que já têm lançamento no ledger apontando para a
-- carteira deles. A UNIQUE uk_patrocinador_slug acompanha a coluna renomeada sem
-- precisar ser recriada.
-- -----------------------------------------------------------------------------
ALTER TABLE patrocinador RENAME COLUMN transportadora_slug TO slug;

COMMENT ON COLUMN patrocinador.slug IS
  'Identificador estável do apoiador, em minúsculas. Era transportadora_slug e casava com o '
  'cabeçalho X-Transportadora do webhook removido na V28 (ADR 0031); hoje é só chave de negócio.';

COMMENT ON TABLE patrocinador IS
  'Apoiador do bairro: o titular de carteira que recebe aporte de token (APORTE_PATROCINADOR, o '
  'único ponto de emissão do sistema) e financia o pote de missões comunitárias. Até a V28 era a '
  'relação comercial com uma transportadora, e o financiamento acontecia dentro da conversão da '
  'entrega falida — ver ADR 0024 e a retificação do ADR 0031.';
