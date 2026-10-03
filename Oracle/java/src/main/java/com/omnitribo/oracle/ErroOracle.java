package com.omnitribo.oracle;

import java.sql.SQLException;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;

/**
 * Traduz o erro levantado pelo PL/SQL em resposta HTTP.
 *
 * <p>As procedures usam {@code RAISE_APPLICATION_ERROR} com códigos na faixa -20000, e cada código
 * é uma REGRA DE NEGÓCIO conhecida — por isso a mensagem delas pode ir ao cliente. Qualquer outro
 * erro do banco (ORA-00942, ORA-12541, constraint…) é falha nossa e responde 500 com texto
 * genérico: mensagem de driver, nome de tabela e pilha {@code ORA-06512} nunca saem daqui.
 */
final class ErroOracle {

  private record Regra(HttpStatus status, String titulo) {}

  /** Um código por regra. Ver o cabeçalho de {@code Oracle/sql/05_procedures.sql}. */
  private static final Map<Integer, Regra> REGRAS =
      Map.of(
          20020, new Regra(HttpStatus.BAD_REQUEST, "Prazo inválido"),
          20030, new Regra(HttpStatus.BAD_REQUEST, "Chave de idempotência inválida"),
          20031, new Regra(HttpStatus.NOT_FOUND, "Benefício indisponível"),
          20032, new Regra(HttpStatus.NOT_FOUND, "Carteira não encontrada"),
          20033, new Regra(HttpStatus.UNPROCESSABLE_ENTITY, "Saldo insuficiente"),
          20035, new Regra(HttpStatus.CONFLICT, "Conflito de concorrência"));

  private ErroOracle() {}

  static ProblemDetail traduzir(SQLException erro) {
    Regra regra = REGRAS.get(erro.getErrorCode());
    if (regra == null) {
      ProblemDetail interno =
          ProblemDetail.forStatusAndDetail(
              HttpStatus.INTERNAL_SERVER_ERROR, "Falha ao executar a operação no banco de dados.");
      interno.setTitle("Erro interno");
      return interno;
    }
    ProblemDetail problema =
        ProblemDetail.forStatusAndDetail(regra.status(), mensagemDeNegocio(erro));
    problema.setTitle(regra.titulo());
    return problema;
  }

  /**
   * Fica só com o texto que a procedure escreveu.
   *
   * <p>O driver entrega {@code "ORA-20033: Saldo de 0 tokens…\nORA-06512: at "RM…"} — o prefixo com
   * o código e, da segunda linha em diante, a pilha de chamadas com o nome do schema. Os dois são
   * detalhe interno.
   */
  static String mensagemDeNegocio(SQLException erro) {
    String bruta = erro.getMessage() == null ? "" : erro.getMessage();
    String primeiraLinha = bruta.lines().findFirst().orElse("").trim();
    return primeiraLinha.replaceFirst("^ORA-\\d{5}:\\s*", "");
  }
}
