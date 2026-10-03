package com.omnitribo.missoes.api;

import com.omnitribo.missoes.dominio.PotesImobilizadosService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Diagnóstico de ADMIN: token preso em missão parada.
 *
 * <p>É o par detectivo de {@code POST /missoes/{id}/destravar}. Aquele endpoint tira uma missão do
 * limbo; este diz QUAIS estão lá. Sem ele o administrador só descobria um pote imobilizado se
 * alguém reclamasse — e {@code GET /admin/carteiras/reconciliacao} continuava respondendo {@code
 * integro=true}, porque reconciliação e conservação são invariantes diferentes.
 *
 * <p>Vive em {@code missoes}, e não ao lado da reconciliação em {@code carteira}, porque o que ele
 * lê é {@code missao.pote_tokens} e {@code missao.status}: pôr o endpoint lá faria {@code carteira}
 * depender de {@code missoes.dominio}, que o ArchUnit proíbe.
 */
@RestController
@RequestMapping("/api/v1/admin/missoes")
@Tag(name = "Administração", description = "Conciliação e verificação de integridade")
@SecurityRequirement(name = "bearerAuth")
@Validated
public class PotesImobilizadosAdminController {

  private final PotesImobilizadosService potesImobilizadosService;

  public PotesImobilizadosAdminController(PotesImobilizadosService potesImobilizadosService) {
    this.potesImobilizadosService = potesImobilizadosService;
  }

  @GetMapping("/potes-imobilizados")
  @PreAuthorize("hasRole('ADMIN')")
  @Operation(
      summary = "Listar missões paradas com token no pote",
      description =
          "Missões EM_ANDAMENTO, AGUARDANDO_CONFIRMACAO ou EM_DISPUTA com pote_tokens > 0, da mais "
              + "antiga para a mais recente, e o total de tokens imobilizados. Leitura pura: não "
              + "destrava nem estorna. É o diagnóstico que a reconciliação não faz — um pote preso "
              + "deixa ledger e projeção íntegros.")
  @ApiResponses({
    @ApiResponse(responseCode = "200", description = "Potes imobilizados"),
    @ApiResponse(responseCode = "400", ref = "#/components/responses/RequisicaoInvalida"),
    @ApiResponse(responseCode = "401", ref = "#/components/responses/NaoAutenticado"),
    @ApiResponse(responseCode = "403", ref = "#/components/responses/AcessoNegado")
  })
  public PotesImobilizadosResponse listar(
      @RequestParam(defaultValue = "0") @Min(value = 0, message = "Página não pode ser negativa")
          int pagina,
      // Teto de 100, o mesmo das outras listagens: sem ele um ?tamanho=1000000 viraria uma consulta
      // sem limite contra a tabela de missões.
      @RequestParam(defaultValue = "20")
          @Min(value = 1, message = "Tamanho mínimo é 1")
          @Max(value = 100, message = "Tamanho máximo é 100")
          int tamanho) {
    return potesImobilizadosService.listar(pagina, tamanho);
  }
}
