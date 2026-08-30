package com.omnitribo.carteira.api;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

/**
 * Porta de débito de tokens para financiar uma missão.
 *
 * <p>Só o DÉBITO na carteira do financiador mora aqui. O crédito no pote é feito por {@code
 * missoes} na mesma transação, sobre a linha da missão que ela já travou — a carteira nunca toca a
 * tabela {@code missao}, o que mantém a dependência entre os módulos numa direção só.
 */
public interface FinanciamentoMissao {

  /**
   * Trava a carteira do financiador e sonda a chave de idempotência, SEM escrever nada.
   *
   * <p><b>Existe para consertar a ordem.</b> A sondagem morava dentro de {@link #debitar}, ou seja,
   * DEPOIS das validações de estado da missão. Consequência concreta: o retry de rede de um
   * financiamento que completou o pote encontrava o pote já cheio, batia no teto e recebia
   * <b>422</b> em vez do replay que o contrato promete. Mesma coisa se a missão tivesse sido
   * cancelada nesse meio-tempo. O valor nunca era duplicado — o débito continuava barrado pela
   * sondagem sob lock —, mas o cliente recebia um erro para uma operação que já tinha dado certo, e
   * é impossível distinguir isso de uma falha real.
   *
   * <p>A ordem canônica do projeto é <b>adquira os locks → sonde → valide → escreva</b>, e é o que
   * {@code SaqueService}, {@code TransferenciaService} e {@code CreditoRecompensaService} já
   * faziam. Só o financiamento destoava.
   *
   * @return o resultado do lançamento anterior quando a chave já existe; vazio quando é a primeira
   *     vez e o chamador deve seguir para {@link #debitar}
   */
  Optional<ResultadoFinanciamento> sondar(UUID financiadorId, String chaveIdempotencia);

  /**
   * Debita tokens do financiador, na transação do chamador.
   *
   * <p>Trava a carteira do financiador com {@code PESSIMISTIC_WRITE}. O chamador já segura o lock
   * da missão: ordem global {@code missao} → {@code carteira}. Financiar e concluir disputam as
   * mesmas duas linhas, e é essa ordem que impede as duas operações de se travarem mutuamente.
   *
   * <p>Saldo insuficiente resulta em {@code RegraNegocioVioladaException} (422) ANTES de qualquer
   * escrita.
   *
   * @return saldo e id do lançamento, com {@code replay = true} se a chave já existia
   */
  ResultadoFinanciamento debitar(
      UUID financiadorId, UUID missaoId, long tokens, String chaveIdempotencia, Instant agora);

  /**
   * Debita o APOIADOR do bairro para financiar o pote de uma missão comunitária.
   *
   * <p>Método separado de {@link #debitar}, e não um parâmetro de motivo, porque o motivo é um tipo
   * de {@code carteira.dominio} e {@code missoes} não pode importá-lo — a regra do ArchUnit é
   * direcional. O lançamento sai com {@code FINANCIAMENTO_PATROCINADOR}, que o estorno enxerga por
   * {@code LancamentoRepository.buscarFinanciamentosDaMissao}.
   *
   * <p><b>Saldo insuficiente devolve VAZIO, não lança</b>, e desde a V28 é o CHAMADOR quem decide o
   * que fazer com o vazio. O chamador original era o webhook de entrega falida, onde a recusa
   * precisava ser GRAVADA — a encomenda já estava na loja, e lançar abortaria a transação junto com
   * o registro. Aquele caminho saiu com a extensão logística (ADR 0031); hoje quem chama é {@code
   * FinanciamentoService}, atendendo uma requisição HTTP, e ele traduz o vazio em 422. O contrato
   * segue devolvendo valor em vez de lançar porque é o que mantém a decisão com quem tem contexto
   * para tomá-la.
   *
   * <p>Trava a carteira do apoiador com {@code PESSIMISTIC_WRITE}. O chamador já segura o lock da
   * missão: ordem global {@code missao} → {@code carteira}, a mesma de {@link #debitar}.
   *
   * @param tokens deve ser positivo. Recompensa zero não chama este método — um lançamento de valor
   *     zero consumiria uma chave de idempotência sem mover nada, e {@code
   *     ck_lancamento_valor_nao_nulo} o recusaria.
   * @return o resultado do débito, ou vazio quando o saldo não cobre {@code tokens}
   */
  Optional<ResultadoFinanciamento> debitarPatrocinador(
      UUID apoiadorUsuarioId, UUID missaoId, long tokens, String chaveIdempotencia, Instant agora);
}
