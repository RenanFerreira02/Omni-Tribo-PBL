package com.omnitribo.identidade.api;

import java.util.Optional;
import java.util.UUID;

/**
 * Porta pela qual {@code missoes} resolve o titular de carteira de um APOIADOR do bairro.
 *
 * <p>Existe pelo motivo de sempre: o ArchUnit proíbe outros módulos de alcançarem {@code
 * identidade.dominio}, onde vivem {@code Patrocinador} e o repositório dele. Só tipos da JDK na
 * assinatura — devolver a entidade aqui reprovaria o teste de arquitetura e, pior, exporia uma
 * entidade JPA a outro módulo.
 *
 * <p><b>A pergunta mudou na V28</b> (ADR 0031). Antes era "quem patrocina a transportadora deste
 * slug?", feita pelo webhook de entrega falida. O webhook saiu, e com ele o único caminho pelo qual
 * o token aportado entrava no ciclo de missões. Esta porta é o que reabre esse caminho: sem ela, o
 * token que o aporte emite ficaria parado na carteira do apoiador para sempre.
 */
public interface ConsultaPatrocinador {

  /**
   * O titular de carteira deste apoiador, se ele existir e estiver ATIVO.
   *
   * <p>{@code Optional.empty()} cobre os dois casos de uma vez — apoiador inexistente e apoio
   * desativado —, e isso é deliberado: os dois levam ao mesmo desfecho, e distingui-los não muda
   * nada para quem chama.
   *
   * <p><b>Não diz nada sobre SALDO.</b> Quem sabe se o apoiador consegue pagar é a carteira, sob
   * lock, no instante do débito — responder aqui seria uma leitura sem lock, e entre ela e o débito
   * caberia outro financiamento consumindo o mesmo saldo.
   *
   * @param patrocinadorId o id da RELAÇÃO de apoio, que é o que o ADMIN vê na listagem — não o id
   *     do usuário titular, que é justamente o que este método devolve
   */
  Optional<UUID> usuarioIdDoApoiadorAtivo(UUID patrocinadorId);
}
