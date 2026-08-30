package com.omnitribo.missoes.api;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;
import java.util.UUID;

/**
 * Corpo de {@code POST /api/v1/admin/missoes/{missaoId}/financiamento-apoiador}.
 *
 * @param patrocinadorId o id da RELAÇÃO de apoio, que é o que a listagem de {@code
 *     /admin/patrocinadores} devolve — não o id do usuário titular. O ADMIN escolhe o apoiador que
 *     vê na tela, e o servidor resolve o titular por trás dele
 * @param tokens quanto pôr no pote. Positivo: um lançamento de valor zero consumiria uma chave de
 *     idempotência sem mover nada, e {@code ck_lancamento_valor_nao_nulo} o recusaria
 */
public record FinanciarComoApoiadorRequest(
    @NotNull(message = "Apoiador é obrigatório") UUID patrocinadorId,
    @Positive(message = "Financiamento precisa ser de pelo menos 1 token") long tokens) {}
