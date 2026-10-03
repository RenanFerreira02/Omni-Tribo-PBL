package com.omnitribo.oracle;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;

/**
 * Corpo de {@code POST /oracle/resgates}.
 *
 * <p><b>Limitação declarada:</b> aqui o {@code usuarioId} vem do corpo porque esta demonstração
 * não tem autenticação. No sistema real ({@code services/api}) a identidade vem SEMPRE do JWT, e
 * um endpoint que aceitasse o usuário pelo corpo deixaria qualquer um resgatar em nome de outro.
 */
public record ResgateRequest(
    @NotNull @Pattern(regexp = FORMATO_ID, message = "deve ser um id no formato UUID")
        String usuarioId,
    @NotNull @Pattern(regexp = FORMATO_ID, message = "deve ser um id no formato UUID")
        String beneficioId) {

  static final String FORMATO_ID =
      "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$";
}
