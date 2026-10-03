#!/usr/bin/env bash
# Gera Oracle/sql/02_carga_seed.sql a partir do seed do PostgreSQL do projeto.
#
# Por que exportar em vez de inventar massa: o modelo Oracle passa a representar o MESMO bairro
# que o sistema usa em dev (Cidade Líder, Pinheiros, Vila Madalena, Jardim América), com os mesmos
# ids. Uma linha em OT_MISSAO é rastreável até o INSERT de services/api/.../db/seed.
#
# O arquivo gerado é commitado: quem instala no Oracle NÃO precisa do Postgres.
#
# Três decisões que o script toma, e por quê:
#
#   1. Data vira DESLOCAMENTO, não literal. O seed do Postgres grava datas relativas a now(); se
#      elas fossem congeladas aqui, uma instalação feita meses depois veria todas as janelas
#      vencidas e a varredura expiraria o seed inteiro. Cada timestamp sai como
#      SYSTIMESTAMP + NUMTODSINTERVAL(<segundos>, 'SECOND'), então o banco sempre nasce com a
#      aparência de "seed recém-aplicado".
#   2. E-mail, hash de senha e coordenada NÃO são exportados (ver Oracle/docs/DICIONARIO.md).
#   3. Lançamento sem token (só BRL) não vem: BRL está fora do ciclo de missões.
#
# Uso:
#   bash Oracle/dados/exportar_do_postgres.sh > Oracle/sql/02_carga_seed.sql
#
# O banco de origem precisa estar com TODAS as migrations aplicadas (V28 e seed V907). Por padrão
# o script fala com um container; aponte PSQL para outro alvo se precisar:
#   PSQL="psql -h localhost -U omnitribo -d omnitribo" bash Oracle/dados/exportar_do_postgres.sh
set -euo pipefail

PSQL="${PSQL:-podman exec -i omnitribo-export psql -U omnitribo -d omnitribo}"

consultar() {
  $PSQL -X -At -v ON_ERROR_STOP=1 -c "$1"
}

# Literal de texto anulável.
txt() { echo "coalesce(quote_literal(($1)::text), 'NULL')"; }
# Timestamp como deslocamento em segundos a partir do instante da instalação.
ts() {
  echo "case when $1 is null then 'NULL' else 'SYSTIMESTAMP + NUMTODSINTERVAL(' || round(extract(epoch from ($1) - now()))::bigint || ', ''SECOND'')' end"
}
# Booleano como 0/1.
bool() { echo "case when $1 then '1' else '0' end"; }

versao=$(consultar "select max(version::int) from flyway_schema_history where version::int < 900")
seed=$(consultar "select max(version::int) from flyway_schema_history")

cat <<CABECALHO
-- =============================================================================================
-- Omni-Tribo · PBL Fase 6 · 02_carga_seed.sql
-- ARQUIVO GERADO por Oracle/dados/exportar_do_postgres.sh — não edite à mão.
-- Origem: PostgreSQL do projeto, schema V${versao}, seed V${seed}.
--
-- Toda data é um deslocamento a partir do instante da instalação; ver o cabeçalho do script.
-- =============================================================================================
SET DEFINE OFF

CABECALHO

echo "-- ot_tribo"
consultar "select 'INSERT INTO ot_tribo (id, nome, bairro, criada_em) VALUES ('
  || $(txt id) || ', ' || $(txt nome) || ', ' || $(txt bairro) || ', ' || $(ts criada_em) || ');'
  from tribo order by id"

echo
echo "-- ot_usuario (sem e-mail e sem hash de senha)"
consultar "select 'INSERT INTO ot_usuario (id, nome, handle, tribo_id, xp, nivel, papel, status, criado_em) VALUES ('
  || $(txt id) || ', ' || $(txt nome) || ', ' || $(txt handle) || ', ' || $(txt tribo_id) || ', '
  || xp || ', ' || nivel || ', ' || $(txt papel) || ', ' || $(txt status) || ', ' || $(ts criado_em) || ');'
  from usuario order by id"

echo
echo "-- ot_carteira (só token)"
consultar "select 'INSERT INTO ot_carteira (id, usuario_id, saldo_tokens) VALUES ('
  || $(txt id) || ', ' || $(txt usuario_id) || ', ' || saldo_tokens || ');'
  from carteira order by id"

echo
echo "-- ot_lancamento"
consultar "select 'INSERT INTO ot_lancamento (id, carteira_id, sinal, motivo, valor_tokens, missao_id, contraparte_carteira_id, chave_idempotencia, saldo_apos_tokens, mensagem, criado_em) VALUES ('
  || $(txt id) || ', ' || $(txt carteira_id) || ', ' || $(txt sinal) || ', ' || $(txt motivo) || ', '
  || valor_tokens || ', ' || $(txt missao_id) || ', ' || $(txt contraparte_carteira_id) || ', '
  || $(txt chave_idempotencia) || ', ' || saldo_apos_tokens || ', ' || $(txt mensagem) || ', '
  || $(ts criado_em) || ');'
  from lancamento where valor_tokens > 0 order by criado_em, id"

echo
echo "-- ot_missao (sem coordenada)"
consultar "select 'INSERT INTO ot_missao (id, criador_id, executor_id, categoria, titulo, status, xp_recompensa, tokens_recompensa, pote_tokens, fonte_pote, complexidade, bairro, cidade, uf, janela_inicio, janela_fim, criada_em, aceita_em, concluida_em, estado_desde) VALUES ('
  || $(txt id) || ', ' || $(txt criador_id) || ', ' || $(txt executor_id) || ', ' || $(txt categoria) || ', '
  || $(txt titulo) || ', ' || $(txt status) || ', ' || xp_recompensa || ', ' || tokens_recompensa || ', '
  || pote_tokens || ', ' || $(txt fonte_pote) || ', ' || $(txt complexidade) || ', ' || $(txt bairro) || ', '
  || $(txt cidade) || ', ' || $(txt uf) || ', ' || $(ts janela_inicio) || ', ' || $(ts janela_fim) || ', '
  || $(ts criada_em) || ', ' || $(ts aceita_em) || ', ' || $(ts concluida_em) || ', ' || $(ts estado_desde) || ');'
  from missao order by id"

echo
echo "-- ot_missao_evento"
consultar "select 'INSERT INTO ot_missao_evento (id, missao_id, tipo, ator_id, de_status, para_status, criado_em) VALUES ('
  || $(txt id) || ', ' || $(txt missao_id) || ', ' || $(txt tipo) || ', ' || $(txt ator_id) || ', '
  || $(txt de_status) || ', ' || $(txt para_status) || ', ' || $(ts criado_em) || ');'
  from missao_evento order by criado_em, id"

echo
echo "-- ot_checkin (sem coordenada)"
consultar "select 'INSERT INTO ot_checkin (id, missao_id, usuario_id, acuracia_m, distancia_alvo_m, metodo, mock_detectado, velocidade_implicita_kmh, valido, codigo_rejeicao, criado_em) VALUES ('
  || $(txt id) || ', ' || $(txt missao_id) || ', ' || $(txt usuario_id) || ', ' || acuracia_m || ', '
  || distancia_alvo_m || ', ' || $(txt metodo) || ', ' || $(bool mock_detectado) || ', '
  || coalesce(velocidade_implicita_kmh::text, 'NULL') || ', ' || $(bool valido) || ', '
  || $(txt codigo_rejeicao) || ', ' || $(ts criado_em) || ');'
  from checkin order by criado_em, id"

echo
echo "-- ot_parceiro (sem coordenada)"
consultar "select 'INSERT INTO ot_parceiro (id, nome, tribo_id, bairro, cidade, uf, ativo, criado_em) VALUES ('
  || $(txt id) || ', ' || $(txt nome) || ', ' || $(txt tribo_id) || ', ' || $(txt bairro) || ', '
  || $(txt cidade) || ', ' || $(txt uf) || ', ' || $(bool ativo) || ', ' || $(ts criado_em) || ');'
  from parceiro order by id"

echo
echo "-- ot_beneficio"
consultar "select 'INSERT INTO ot_beneficio (id, parceiro_id, titulo, descricao, custo_tokens, tipo, ativo, criado_em) VALUES ('
  || $(txt id) || ', ' || $(txt parceiro_id) || ', ' || $(txt titulo) || ', ' || $(txt descricao) || ', '
  || custo_tokens || ', ' || $(txt tipo) || ', ' || $(bool ativo) || ', ' || $(ts criado_em) || ');'
  from beneficio order by id"

echo
echo "-- ot_resgate"
consultar "select 'INSERT INTO ot_resgate (id, usuario_id, beneficio_id, custo_tokens, codigo_retirada, status, criado_em, utilizado_em) VALUES ('
  || $(txt id) || ', ' || $(txt usuario_id) || ', ' || $(txt beneficio_id) || ', ' || custo_tokens || ', '
  || $(txt codigo_retirada) || ', ' || $(txt status) || ', ' || $(ts criado_em) || ', ' || $(ts utilizado_em) || ');'
  from resgate order by criado_em, id"

echo
echo "-- ot_alerta (a caixa de entrada do seed)"
consultar "select 'INSERT INTO ot_alerta (id, usuario_id, tipo, titulo, corpo, missao_id, prioridade, lido, criado_em) VALUES ('
  || $(txt id) || ', ' || $(txt usuario_id) || ', ' || $(txt tipo) || ', ' || $(txt titulo) || ', '
  || $(txt 'left(corpo, 1000)') || ', ' || $(txt missao_id) || ', ' || prioridade || ', ' || $(bool lido) || ', '
  || $(ts criado_em) || ');'
  from alerta order by criado_em, id"

echo
echo "COMMIT;"
