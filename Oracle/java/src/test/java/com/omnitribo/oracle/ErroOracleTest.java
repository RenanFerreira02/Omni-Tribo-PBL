package com.omnitribo.oracle;

import static org.assertj.core.api.Assertions.assertThat;

import java.sql.SQLException;
import org.junit.jupiter.api.Test;
import org.springframework.http.ProblemDetail;
import org.springframework.jdbc.UncategorizedSQLException;

/**
 * A tradução de erro é a parte do Java que não precisa de banco para ser provada — e é a que
 * decide o que vaza para o cliente.
 */
class ErroOracleTest {

  /** O formato real que o driver entrega: código, mensagem e a pilha PL/SQL nas linhas seguintes. */
  private static SQLException doOracle(int codigo, String mensagem) {
    return new SQLException(
        "ORA-"
            + codigo
            + ": "
            + mensagem
            + "\nORA-06512: at \"RM555833.PRC_OT_RESGATAR_BENEFICIO\", line 71\nORA-06512: at line 1",
        "72000",
        codigo);
  }

  @Test
  void saldoInsuficienteVira422ComAMensagemDaProcedure() {
    ProblemDetail problema =
        ErroOracle.traduzir(doOracle(20033, "Saldo de 0 tokens é insuficiente."));

    assertThat(problema.getStatus()).isEqualTo(422);
    assertThat(problema.getTitle()).isEqualTo("Saldo insuficiente");
    assertThat(problema.getDetail()).isEqualTo("Saldo de 0 tokens é insuficiente.");
  }

  @Test
  void beneficioIndisponivelVira404() {
    assertThat(ErroOracle.traduzir(doOracle(20031, "Benefício indisponível.")).getStatus())
        .isEqualTo(404);
  }

  @Test
  void chaveInvalidaVira400EConflitoVira409() {
    assertThat(ErroOracle.traduzir(doOracle(20030, "x")).getStatus()).isEqualTo(400);
    assertThat(ErroOracle.traduzir(doOracle(20035, "x")).getStatus()).isEqualTo(409);
  }

  @Test
  void pilhaPlsqlENomeDoSchemaNuncaChegamAoCliente() {
    ProblemDetail problema = ErroOracle.traduzir(doOracle(20033, "Saldo insuficiente."));

    assertThat(problema.getDetail())
        .doesNotContain("ORA-")
        .doesNotContain("RM555833")
        .doesNotContain("line 71");
  }

  @Test
  void erroNaoMapeadoVira500SemMensagemDoDriver() {
    ProblemDetail problema =
        ErroOracle.traduzir(
            new SQLException("ORA-00942: table or view does not exist", "42000", 942));

    assertThat(problema.getStatus()).isEqualTo(500);
    assertThat(problema.getDetail())
        .isEqualTo("Falha ao executar a operação no banco de dados.")
        .doesNotContain("table or view");
  }

  /**
   * Regressão medida contra o Oracle real: o driver encadeia uma causa que não é SQLException
   * DEPOIS da SQLException. Procurar pela raiz devolvia 500 para toda regra de negócio.
   */
  @Test
  void achaASqlExceptionMesmoQuandoARaizDaCadeiaEOutroTipo() {
    SQLException doDriver = doOracle(20033, "Saldo insuficiente.");
    doDriver.initCause(new RuntimeException("oracle.jdbc.OracleDatabaseException"));
    UncategorizedSQLException doSpring = new UncategorizedSQLException("call", "{ call … }", doDriver);

    assertThat(doSpring.getRootCause()).isNotInstanceOf(SQLException.class);
    // O cast desfaz a ambiguidade do assertThat: SQLException também é Iterable<Throwable>.
    assertThat((Throwable) TratadorDeErros.sqlExceptionDe(doSpring)).isSameAs(doDriver);
  }

  @Test
  void cadeiaSemSqlExceptionDevolveNulo() {
    assertThat((Throwable) TratadorDeErros.sqlExceptionDe(new IllegalStateException("x"))).isNull();
  }
}
