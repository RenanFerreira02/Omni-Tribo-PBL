package com.omnitribo.oracle;

import java.sql.CallableStatement;
import java.sql.Types;
import java.util.List;
import org.springframework.jdbc.core.CallableStatementCallback;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

/**
 * Único ponto do Java que conhece o nome das rotinas PL/SQL.
 *
 * <p>As chamadas usam {@link CallableStatement} à mão, com parâmetros IN bindados e OUT
 * registrados — e não {@code SimpleJdbcCall} — porque o objetivo aqui é mostrar o JDBC. Nenhuma
 * string de SQL é montada por concatenação: todo valor entra por {@code ?}.
 *
 * <p>Nenhum método abre ou confirma transação. As procedures não fazem COMMIT, e quem delimita a
 * unidade de trabalho é o {@code @Transactional} do serviço que chama.
 */
@Repository
public class RotinasOracle {

  /** Notação nomeada ({@code =>}): a ordem dos {@code ?} deixa de depender da assinatura. */
  private static final String RESGATAR =
      """
      { call prc_ot_resgatar_beneficio(
          p_usuario_id      => ?,
          p_beneficio_id    => ?,
          p_chave           => ?,
          p_resgate_id      => ?,
          p_codigo_retirada => ?,
          p_saldo_apos      => ?,
          p_replay          => ?) }
      """;

  private static final String VARRER =
      """
      { call prc_ot_varrer_missoes_paradas(
          p_prazo_execucao_h    => ?,
          p_prazo_confirmacao_h => ?,
          p_expiradas           => ?,
          p_concluidas          => ?,
          p_tokens_estornados   => ?,
          p_falhas              => ?) }
      """;

  private final JdbcTemplate jdbc;

  public RotinasOracle(JdbcTemplate jdbc) {
    this.jdbc = jdbc;
  }

  public ResgateResponse resgatar(String usuarioId, String beneficioId, String chave) {
    return jdbc.execute(
        RESGATAR,
        (CallableStatementCallback<ResgateResponse>)
            cs -> {
              cs.setString(1, usuarioId);
              cs.setString(2, beneficioId);
              cs.setString(3, chave);
              cs.registerOutParameter(4, Types.VARCHAR);
              cs.registerOutParameter(5, Types.VARCHAR);
              cs.registerOutParameter(6, Types.NUMERIC);
              cs.registerOutParameter(7, Types.NUMERIC);
              cs.execute();
              // Token é inteiro: getLong, nunca getDouble.
              return new ResgateResponse(
                  cs.getString(4), cs.getString(5), cs.getLong(6), cs.getInt(7) == 1);
            });
  }

  public VarreduraResponse varrer(int prazoExecucaoHoras, int prazoConfirmacaoHoras) {
    return jdbc.execute(
        VARRER,
        (CallableStatementCallback<VarreduraResponse>)
            cs -> {
              cs.setInt(1, prazoExecucaoHoras);
              cs.setInt(2, prazoConfirmacaoHoras);
              cs.registerOutParameter(3, Types.NUMERIC);
              cs.registerOutParameter(4, Types.NUMERIC);
              cs.registerOutParameter(5, Types.NUMERIC);
              cs.registerOutParameter(6, Types.NUMERIC);
              cs.execute();
              return new VarreduraResponse(
                  cs.getInt(3), cs.getInt(4), cs.getLong(5), cs.getInt(6));
            });
  }

  /** As functions PL/SQL usadas dentro de SELECT, como qualquer função nativa do banco. */
  public IndicadoresResponse indicadores() {
    List<IndicadoresResponse.TaxaDaTribo> tribos =
        jdbc.query(
            """
            SELECT t.id, t.nome, fn_ot_taxa_conclusao_tribo(t.id) AS taxa
              FROM ot_tribo t
             ORDER BY taxa DESC NULLS LAST, t.nome
            """,
            (rs, i) ->
                new IndicadoresResponse.TaxaDaTribo(
                    rs.getString("id"), rs.getString("nome"), rs.getBigDecimal("taxa")));

    Integer divergentes =
        jdbc.queryForObject(
            "SELECT COUNT(*) FROM ot_carteira WHERE fn_ot_divergencia_carteira(id) <> 0",
            Integer.class);

    List<String> potesImobilizados =
        jdbc.queryForList(
            """
            SELECT fn_ot_resumo_missao(m.id)
              FROM ot_missao m
             WHERE m.status IN ('EM_ANDAMENTO', 'AGUARDANDO_CONFIRMACAO', 'EM_DISPUTA')
               AND m.pote_tokens > 0
             ORDER BY m.estado_desde
            """,
            String.class);

    return new IndicadoresResponse(
        tribos, divergentes == null ? 0 : divergentes, potesImobilizados);
  }
}
