package com.omnitribo.oracle;

import java.math.BigDecimal;
import java.util.List;

/** Resultado das functions PL/SQL usadas dentro de consultas. */
public record IndicadoresResponse(
    List<TaxaDaTribo> tribos, int carteirasDivergentes, List<String> potesImobilizados) {

  /**
   * @param taxaConclusao percentual de 0 a 100, ou {@code null} quando a tribo ainda não encerrou
   *     missão nenhuma. Nulo não é zero: é ausência de dado, e some do JSON em vez de virar 0%.
   */
  public record TaxaDaTribo(String triboId, String nome, BigDecimal taxaConclusao) {}
}
