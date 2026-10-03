package com.omnitribo.oracle;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Delimita a transação de cada evento de back-end.
 *
 * <p>As procedures PL/SQL não fazem COMMIT. É o {@code @Transactional} daqui que confirma quando o
 * método retorna e desfaz quando a procedure levanta erro — o mesmo arranjo de {@code
 * services/api}, onde a transação é sempre de quem chama.
 */
@Service
public class RotinasService {

  private final RotinasOracle rotinas;

  public RotinasService(RotinasOracle rotinas) {
    this.rotinas = rotinas;
  }

  @Transactional
  public ResgateResponse resgatar(String usuarioId, String beneficioId, String chave) {
    return rotinas.resgatar(usuarioId, beneficioId, chave);
  }

  @Transactional
  public VarreduraResponse varrer(int prazoExecucaoHoras, int prazoConfirmacaoHoras) {
    return rotinas.varrer(prazoExecucaoHoras, prazoConfirmacaoHoras);
  }

  @Transactional(readOnly = true)
  public IndicadoresResponse indicadores() {
    return rotinas.indicadores();
  }
}
