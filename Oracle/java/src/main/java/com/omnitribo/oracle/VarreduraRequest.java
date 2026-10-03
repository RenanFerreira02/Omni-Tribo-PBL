package com.omnitribo.oracle;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;

/**
 * Corpo opcional de {@code POST /oracle/varredura}. Campo ausente usa o prazo do sistema de
 * origem ({@code app.missoes.expiracao.prazo-*}: 48 h de execução, 72 h de confirmação).
 */
public record VarreduraRequest(
    @Min(0) @Max(8760) Integer prazoExecucaoHoras,
    @Min(0) @Max(8760) Integer prazoConfirmacaoHoras) {

  static final int PRAZO_EXECUCAO_PADRAO = 48;
  static final int PRAZO_CONFIRMACAO_PADRAO = 72;

  int prazoExecucao() {
    return prazoExecucaoHoras == null ? PRAZO_EXECUCAO_PADRAO : prazoExecucaoHoras;
  }

  int prazoConfirmacao() {
    return prazoConfirmacaoHoras == null ? PRAZO_CONFIRMACAO_PADRAO : prazoConfirmacaoHoras;
  }
}
