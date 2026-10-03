package com.omnitribo.oracle;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** A borda REST. Cada POST é um evento de back-end que aciona uma procedure PL/SQL. */
@RestController
@RequestMapping("/oracle")
@Validated
public class OracleController {

  private final RotinasService service;

  public OracleController(RotinasService service) {
    this.service = service;
  }

  /**
   * Resgate de benefício → {@code PRC_OT_RESGATAR_BENEFICIO}.
   *
   * <p>O cabeçalho {@code Idempotency-Key} é obrigatório, como em todo POST de valor de {@code
   * services/api}. Primeira chamada responde 201; a repetição com a mesma chave responde 200 com o
   * MESMO resgate — é a diferença de status que conta ao cliente que nada foi debitado de novo.
   */
  @PostMapping("/resgates")
  public ResponseEntity<ResgateResponse> resgatar(
      @RequestHeader("Idempotency-Key") @NotBlank @Size(max = 100) String chave,
      @Valid @RequestBody ResgateRequest pedido) {
    ResgateResponse resgate =
        service.resgatar(pedido.usuarioId(), pedido.beneficioId(), chave);
    return ResponseEntity.status(resgate.replay() ? HttpStatus.OK : HttpStatus.CREATED)
        .body(resgate);
  }

  /** Varredura de missões paradas → {@code PRC_OT_VARRER_MISSOES_PARADAS}. */
  @PostMapping("/varredura")
  public VarreduraResponse varrer(@Valid @RequestBody(required = false) VarreduraRequest pedido) {
    VarreduraRequest prazos = pedido == null ? new VarreduraRequest(null, null) : pedido;
    return service.varrer(prazos.prazoExecucao(), prazos.prazoConfirmacao());
  }

  /** As functions PL/SQL dentro de SELECT. */
  @GetMapping("/indicadores")
  public IndicadoresResponse indicadores() {
    return service.indicadores();
  }
}
