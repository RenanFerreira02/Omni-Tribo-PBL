package com.omnitribo.oracle;

/**
 * Parâmetros OUT de {@code PRC_OT_RESGATAR_BENEFICIO}.
 *
 * @param replay {@code true} quando a chamada repetiu uma anterior com a mesma chave de
 *     idempotência: o resgate devolvido é o primeiro, e nada foi debitado de novo.
 */
public record ResgateResponse(
    String resgateId, String codigoRetirada, long saldoTokens, boolean replay) {}
