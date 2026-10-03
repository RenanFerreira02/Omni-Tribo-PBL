package com.omnitribo.missoes.api;

import com.omnitribo.missoes.dominio.CategoriaMissao;
import com.omnitribo.missoes.dominio.FontePote;
import com.omnitribo.missoes.dominio.Missao;
import com.omnitribo.missoes.dominio.StatusMissao;
import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

/**
 * Uma missão parada com token no pote.
 *
 * <p>Recorte deliberadamente estreito de {@code MissaoResponse}: só o que o administrador precisa
 * para decidir se destrava. Endereço, coordenada e descrição ficam de fora — quem quiser o resto
 * tem o {@code missaoId} para {@code GET /missoes/{id}}.
 *
 * @param horasNoEstado horas inteiras desde a última transição, calculadas pelo servidor. Vem
 *     pronto porque o relógio que decide a varredura por prazo é o do servidor: o cliente
 *     calculando com o próprio relógio mostraria "vencida" uma missão que a varredura ainda não
 *     considera vencida.
 */
public record PoteImobilizadoResponse(
    UUID missaoId,
    String titulo,
    StatusMissao status,
    CategoriaMissao categoria,
    FontePote fontePote,
    long poteTokens,
    long tokensRecompensa,
    Instant estadoDesde,
    long horasNoEstado) {

  public static PoteImobilizadoResponse de(Missao missao, Instant agora) {
    return new PoteImobilizadoResponse(
        missao.getId(),
        missao.getTitulo(),
        missao.getStatus(),
        missao.getCategoria(),
        missao.getFontePote(),
        missao.getPoteTokens(),
        missao.getTokensRecompensa(),
        missao.getEstadoDesde(),
        // max(0): um estadoDesde levemente à frente do relógio da aplicação (relógios do banco e da
        // JVM não são o mesmo) viraria -1 hora na tela.
        Math.max(0, Duration.between(missao.getEstadoDesde(), agora).toHours()));
  }
}
