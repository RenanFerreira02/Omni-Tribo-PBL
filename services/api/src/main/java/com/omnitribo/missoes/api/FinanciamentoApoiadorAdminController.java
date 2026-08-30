package com.omnitribo.missoes.api;

import com.omnitribo.missoes.dominio.FinanciamentoService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/**
 * ADMIN põe token de um APOIADOR do bairro no pote de uma missão comunitária.
 *
 * <h2>Por que este endpoint existe, e por que ele é ADMIN</h2>
 *
 * <p>O apoiador é um titular de carteira que <b>nunca autentica</b>: a conta nasce com status
 * INATIVO, e {@code AutenticacaoService} recusa qualquer status diferente de ATIVO. Ele não tem — e
 * não deve ter — um JWT, então não alcança {@code POST /tribos/{triboId}/financiamentos}, que tira
 * a identidade do token. Um caminho que dependesse do JWT dele seria código inalcançável, e foi
 * exatamente esse o defeito que a verificação ponta a ponta pegou.
 *
 * <p>É coerente com o resto: o apoiador é administrado de ponta a ponta — cadastro, aporte e
 * encerramento são todos ADMIN, em {@code /admin/patrocinadores}.
 *
 * <p><b>Sem este endpoint a economia não fecha.</b> {@code APORTE_PATROCINADOR} é o único ponto de
 * emissão de token do sistema, e até a V28 quem levava esse token ao pote era a conversão do
 * webhook de entrega falida. Com o webhook removido (ADR 0031), o token emitido ficaria parado na
 * carteira do apoiador para sempre: a economia teria só o sumidouro do resgate, e a soma cairia
 * monotonicamente até zero.
 *
 * <h2>Por que ele vive em {@code missoes} e não em {@code identidade}</h2>
 *
 * <p>O recurso MUTADO é {@code missao.pote_tokens} — o path diz isso. O apoiador entra como
 * parâmetro, resolvido pela porta {@code ConsultaPatrocinador}; pôr o endpoint junto do cadastro
 * faria {@code identidade} depender de {@code missoes.dominio}, que o ArchUnit proíbe.
 */
@RestController
@RequestMapping("/api/v1/admin/missoes")
@Tag(name = "Financiamento", description = "Financiamento comunitário do pote de missões")
@SecurityRequirement(name = "bearerAuth")
@Validated
public class FinanciamentoApoiadorAdminController {

  private final FinanciamentoService financiamentoService;

  public FinanciamentoApoiadorAdminController(FinanciamentoService financiamentoService) {
    this.financiamentoService = financiamentoService;
  }

  @PostMapping("/{missaoId}/financiamento-apoiador")
  @ResponseStatus(HttpStatus.CREATED)
  @PreAuthorize("hasRole('ADMIN')")
  @Operation(
      summary = "Financiar o pote com token de um apoiador do bairro",
      description =
          "Debita a carteira do apoiador e credita o pote da missão, com motivo "
              + "FINANCIAMENTO_PATROCINADOR. NÃO emite token: é o aporte que emite, e este endpoint "
              + "apenas move para o pote o que já foi emitido — a soma SUM(carteiras) + SUM(potes) "
              + "não muda aqui. Idempotente pelo header Idempotency-Key.")
  @ApiResponses({
    @ApiResponse(responseCode = "201", description = "Pote atualizado"),
    @ApiResponse(responseCode = "400", ref = "#/components/responses/RequisicaoInvalida"),
    @ApiResponse(responseCode = "401", ref = "#/components/responses/NaoAutenticado"),
    @ApiResponse(responseCode = "403", ref = "#/components/responses/AcessoNegado"),
    @ApiResponse(responseCode = "404", ref = "#/components/responses/NaoEncontrado"),
    @ApiResponse(responseCode = "422", ref = "#/components/responses/RegraNegocioViolada")
  })
  public FinanciamentoResponse financiar(
      @PathVariable UUID missaoId,
      @Valid @RequestBody FinanciarComoApoiadorRequest corpo,
      // required=true faz a ausência virar 400 pelo próprio framework. O @Size não protege o banco
      // — a coluna guarda um sha256 de tamanho fixo — e sim o cliente de si mesmo: uma chave vazia
      // ou constante o prenderia para sempre no replay da primeira operação que ele fez.
      @RequestHeader("Idempotency-Key") @NotBlank @Size(min = 8, max = 200) String chaveDoCliente) {

    return financiamentoService.financiarComoApoiador(
        missaoId, corpo.tokens(), corpo.patrocinadorId(), chaveDoCliente);
  }
}
