package com.omnitribo.oracle;

import java.sql.SQLException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.http.ProblemDetail;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.mvc.method.annotation.ResponseEntityExceptionHandler;

/**
 * Todo erro sai como RFC 9457 ProblemDetail.
 *
 * <p>Estender {@link ResponseEntityExceptionHandler} cobre os erros do próprio Spring MVC (corpo
 * inválido, cabeçalho ausente, validação) no mesmo formato.
 */
@RestControllerAdvice
public class TratadorDeErros extends ResponseEntityExceptionHandler {

  private static final Logger log = LoggerFactory.getLogger(TratadorDeErros.class);

  @ExceptionHandler(DataAccessException.class)
  public ResponseEntity<ProblemDetail> erroDeBanco(DataAccessException erro) {
    SQLException sql = sqlExceptionDe(erro);
    if (sql == null) {
      log.error("Falha de acesso a dados sem SQLException na cadeia: {}", erro.getClass().getName());
      sql = new SQLException("sem causa");
    }
    ProblemDetail problema = ErroOracle.traduzir(sql);
    if (problema.getStatus() >= 500) {
      // Só o código vai para o log: a mensagem do driver pode carregar valor de parâmetro.
      log.error("Falha de banco não mapeada: ORA-{}", sql.getErrorCode());
    }
    return ResponseEntity.status(problema.getStatus()).body(problema);
  }

  /**
   * Primeira {@link SQLException} da cadeia de causas.
   *
   * <p><b>Não use {@code getRootCause()} aqui.</b> O driver da Oracle pendura uma {@code
   * OracleDatabaseException} — que NÃO é {@code SQLException} — como causa da própria {@code
   * SQLException}, então a raiz da cadeia nunca é o tipo que carrega o código ORA. A primeira
   * versão deste método olhava a raiz e respondia 500 para saldo insuficiente; quem pegou foi a
   * chamada real contra o banco, não o teste unitário.
   */
  static SQLException sqlExceptionDe(Throwable erro) {
    for (Throwable causa = erro; causa != null; causa = causa.getCause()) {
      if (causa instanceof SQLException sql) {
        return sql;
      }
      if (causa.getCause() == causa) {
        break;
      }
    }
    return null;
  }
}
