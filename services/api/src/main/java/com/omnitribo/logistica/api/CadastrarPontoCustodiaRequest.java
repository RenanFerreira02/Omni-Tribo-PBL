package com.omnitribo.logistica.api;

import com.omnitribo.logistica.dominio.TipoPontoCustodia;
import jakarta.validation.constraints.DecimalMax;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Positive;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;
import java.util.UUID;

/**
 * Corpo de {@code POST /api/v1/admin/pontos-custodia}.
 *
 * <h2>Por que não existe campo {@code ocupacao} aqui</h2>
 *
 * <p><b>Ausência deliberada, e é a decisão mais importante deste DTO.</b> {@code ocupacao} é
 * escrita exclusivamente por dois caminhos internos, os dois sob o {@code SELECT ... FOR UPDATE} de
 * {@code PontoCustodiaRepository.buscarParaAtualizar}: {@code EntregaFalidaService} incrementa
 * quando o webhook converte uma entrega falida, e {@code BaixaCustodiaService} decrementa quando a
 * missão de retirada conclui. Aceitar o valor do cliente daria a quem chama o poder de reescrever,
 * por fora do lock, o número que aquele lock existe para proteger — e o efeito seria invisível: a
 * única constraint da coluna é {@code NOT NULL}, então um ponto acima da capacidade não acusa nada.
 *
 * <p>Todo ponto nasce com {@code ocupacao = 0}, que é também o default da coluna (V21).
 *
 * <p>{@code ativo} também não vem do cliente: um ponto nasce ativo. Desativar é outra operação, com
 * outra semântica (ponto inativo some das consultas — ver {@code PontoCustodiaService.buscar}), e
 * não foi pedida.
 *
 * @param codigo identificador operacional, único no sistema. O {@code Pattern} espelha o formato
 *     que o seed usa ({@code PC-PINHEIROS-01}) e evita que espaço ou minúscula produzam dois
 *     códigos que um humano leria como o mesmo. Duplicata é recusada com 422 pelo serviço — a
 *     UNIQUE {@code uk_ponto_custodia_codigo} é a barreira final, não a primeira.
 * @param triboId opcional. Quando vem, precisa existir: a FK do banco recusaria de qualquer forma,
 *     mas como {@code DataIntegrityViolationException}, que sai como 500. Ver {@code
 *     ConsultaTribo}.
 */
public record CadastrarPontoCustodiaRequest(
    @NotBlank(message = "Código é obrigatório")
        @Size(max = 20, message = "Código tem no máximo 20 caracteres")
        @Pattern(
            regexp = "[A-Z0-9-]+",
            message = "Código aceita apenas maiúsculas, dígitos e hífen")
        String codigo,
    @NotNull(message = "Tipo é obrigatório") TipoPontoCustodia tipo,
    @NotBlank(message = "Apelido é obrigatório")
        @Size(max = 100, message = "Apelido tem no máximo 100 caracteres")
        String apelido,
    // Mesmos limites de PontoCustodiaFiltroRequest: um ponto que não pode ser BUSCADO por uma
    // coordenada não deveria poder ser CRIADO com ela.
    @NotNull(message = "Latitude é obrigatória")
        @DecimalMin(value = "-90.0", message = "Latitude fora do intervalo")
        @DecimalMax(value = "90.0", message = "Latitude fora do intervalo")
        BigDecimal lat,
    @NotNull(message = "Longitude é obrigatória")
        @DecimalMin(value = "-180.0", message = "Longitude fora do intervalo")
        @DecimalMax(value = "180.0", message = "Longitude fora do intervalo")
        BigDecimal lon,
    @NotNull(message = "Capacidade é obrigatória")
        @Positive(message = "Capacidade deve ser maior que zero")
        @Max(value = 10000, message = "Capacidade máxima é 10000")
        Integer capacidade,
    UUID triboId) {}
