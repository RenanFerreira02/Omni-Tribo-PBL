package com.omnitribo.logistica.api;

import com.omnitribo.compartilhado.api.RecursoAuditavel;
import io.swagger.v3.oas.annotations.media.Schema;
import java.math.BigDecimal;
import java.util.UUID;

/**
 * Ponto de custódia: onde uma encomenda espera.
 *
 * <p>Existe porque {@code MissaoResponse} traz {@code pontoCustodiaId} cru — o app mostrava um UUID
 * onde deveria dizer "Leroy Merlin Pinheiros".
 *
 * <p>{@code distanciaM} só vem preenchida na busca por raio; no detalhe por id é nula, porque ali
 * não há coordenada de referência para medir contra.
 */
@Schema(description = "Ponto de custódia de encomendas")
public record PontoCustodiaResponse(
    UUID id,
    @Schema(example = "PC-PINHEIROS-01") String codigo,
    @Schema(description = "LOJA, LOCKER, PORTARIA ou VIZINHO") String tipo,
    @Schema(example = "Leroy Merlin Pinheiros") String apelido,
    BigDecimal lat,
    BigDecimal lon,
    int capacidade,
    int ocupacao,
    @Schema(description = "Distância em metros; só na busca por raio") BigDecimal distanciaM)
    implements RecursoAuditavel {

  /**
   * Metade obrigatória da auditoria: sem isto, {@code AuditoriaAspecto} grava {@code entidade_id}
   * nulo e a trilha vira "alguém cadastrou um ponto" sem dizer QUAL. A outra metade é o
   * {@code @Auditavel} no método de serviço; faltar qualquer uma não quebra a compilação.
   */
  @Override
  public UUID idAuditoria() {
    return id;
  }
}
