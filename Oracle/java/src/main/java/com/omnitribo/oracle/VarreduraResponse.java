package com.omnitribo.oracle;

/**
 * Parâmetros OUT de {@code PRC_OT_VARRER_MISSOES_PARADAS}.
 *
 * @param falhas missões que não puderam ser tratadas. Cada uma foi desfeita isoladamente e gerou
 *     um alerta {@code VARREDURA_FALHOU} em {@code OT_ALERTA}; a varredura seguiu com as demais.
 */
public record VarreduraResponse(int expiradas, int concluidas, long tokensEstornados, int falhas) {}
