package com.omnitribo.missoes.api;

import com.omnitribo.compartilhado.api.PaginaResponse;

/**
 * Diagnóstico de potes imobilizados.
 *
 * @param totalTokens soma dos potes de TODAS as missões paradas, não só os da página. É o número
 *     que responde "quanto token está preso agora"; somar a página no cliente responderia outra
 *     pergunta e erraria sem nunca dar erro.
 * @param missoes a página pedida, da mais antiga para a mais recente.
 */
public record PotesImobilizadosResponse(
    long totalTokens, PaginaResponse<PoteImobilizadoResponse> missoes) {}
