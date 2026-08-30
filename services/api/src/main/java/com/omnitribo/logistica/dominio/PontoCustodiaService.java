package com.omnitribo.logistica.dominio;

import com.omnitribo.compartilhado.api.ConsultasGeoespaciais;
import com.omnitribo.compartilhado.dominio.Auditavel;
import com.omnitribo.compartilhado.dominio.Coordenadas;
import com.omnitribo.compartilhado.dominio.RecursoNaoEncontradoException;
import com.omnitribo.compartilhado.dominio.RegraNegocioVioladaException;
import com.omnitribo.identidade.api.ConsultaTribo;
import com.omnitribo.logistica.api.CadastrarPontoCustodiaRequest;
import com.omnitribo.logistica.api.PontoCustodiaResponse;
import com.omnitribo.logistica.infra.PontoCustodiaRepository;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Leitura de pontos de custódia.
 *
 * <p><b>Este serviço é só leitura — mas {@code ocupacao} NÃO está parada.</b> A escrita existe
 * desde a F8 e mora em outro lugar: {@code EntregaFalidaService} chama {@link
 * PontoCustodia#registrarEntrada()} quando o webhook converte uma entrega falida, e {@code
 * BaixaCustodiaService} chama {@link PontoCustodia#registrarSaida()} quando a missão de retirada
 * conclui. As duas rodam sob o {@code SELECT ... FOR UPDATE} de {@code
 * PontoCustodiaRepository.buscarParaAtualizar} — sem esse lock, dois webhooks concorrentes leem a
 * mesma ocupação e ambos incrementam.
 *
 * <p>Este parágrafo já afirmou o contrário ("nada movimenta ocupacao ainda, o fluxo é da F8 e não
 * existe"), e ficou para trás quando a F8 entrou. A correção está registrada na varredura de órfãos
 * de 2026-08-20: um comentário que nega um caminho de escrita concorrente é o que autoriza a
 * próxima pessoa a mexer no lock.
 *
 * <p><b>Retificação (2026-08-29): este parágrafo dizia "a escrita NÃO deve virar endpoint", sem
 * qualificar QUAL escrita, e agora existe {@link #cadastrar}.</b> A frase continua verdadeira para
 * o que ela realmente protegia — <b>{@code ocupacao}</b>: expor ocupação a um endpoint deixaria
 * qualquer autenticado marcar a loja de um terceiro como lotada, e o cadastro abaixo por isso não
 * aceita esse campo. O que passou a existir é CADASTRO, restrito a ADMIN, que nasce com {@code
 * ocupacao = 0} e não toca no valor depois. Deixar o parágrafo como estava faria o próximo leitor
 * concluir que este arquivo não deveria ter um método de escrita, e o certo é que ele não deve ter
 * um método que escreva ocupação fora do lock.
 */
@Service
public class PontoCustodiaService {

  private static final String NAO_ENCONTRADO = "Ponto de custódia não encontrado.";
  private static final int CASAS_COORDENADA = 6;

  private final PontoCustodiaRepository pontoCustodiaRepository;
  private final ConsultasGeoespaciais consultasGeoespaciais;
  private final ConsultaTribo consultaTribo;

  public PontoCustodiaService(
      PontoCustodiaRepository pontoCustodiaRepository,
      ConsultasGeoespaciais consultasGeoespaciais,
      ConsultaTribo consultaTribo) {
    this.pontoCustodiaRepository = pontoCustodiaRepository;
    this.consultasGeoespaciais = consultasGeoespaciais;
    // Injetado pela INTERFACE, e não pela implementação: é o tipo declarado no campo que o
    // ArchUnit inspeciona. Nomear TriboService aqui compilaria e reprovaria RegrasArquiteturaTest.
    this.consultaTribo = consultaTribo;
  }

  /**
   * Cadastra um ponto de custódia. Exclusivo de ADMIN — a autorização mora no controller.
   *
   * <p>Ordem das checagens: primeiro o código duplicado, depois a tribo. As duas são independentes,
   * mas o código é o campo que o operador mais repete, e reportá-lo primeiro evita uma segunda
   * viagem quando os dois estão errados.
   *
   * <p><b>422 e não 409 nos dois casos.</b> A regra do projeto é explícita: 409 diz "não cabe NESTE
   * estado, caberia em outro" e manda a tela recarregar; 422 diz "cabe no estado, mas os dados não
   * satisfazem" e manda corrigir o campo. Um código repetido e uma tribo inexistente são dados que
   * não satisfazem — o operador troca o valor e reenvia. Devolver 409 daria ao cliente o {@code
   * type} {@code transicao-invalida}, cuja reação de UI é "recarregue a tela", que aqui não resolve
   * nada.
   */
  @Transactional
  @Auditavel(acao = "PONTO_CUSTODIA_CADASTRADO", entidade = "ponto_custodia")
  public PontoCustodiaResponse cadastrar(CadastrarPontoCustodiaRequest pedido) {
    if (pontoCustodiaRepository.existsByCodigo(pedido.codigo())) {
      throw new RegraNegocioVioladaException(
          "Já existe um ponto de custódia com o código " + pedido.codigo() + ".");
    }
    if (pedido.triboId() != null && !consultaTribo.existe(pedido.triboId())) {
      throw new RegraNegocioVioladaException("A tribo informada não existe.");
    }

    PontoCustodia novo =
        new PontoCustodia(
            pedido.codigo(),
            pedido.tipo(),
            pedido.apelido(),
            Coordenadas.ponto(pedido.lat(), pedido.lon()),
            pedido.capacidade(),
            pedido.triboId());

    // distanciaM nula: não há coordenada de referência num cadastro, e devolver 0 sugeriria
    // "está exatamente aqui" para um valor que ninguém mediu.
    return responseDe(pontoCustodiaRepository.save(novo), null);
  }

  /**
   * Ponto INATIVO responde 404, e não um corpo com {@code ativo: false}.
   *
   * <p>Uma missão antiga pode apontar para um ponto desativado, e devolvê-lo levaria o executor a
   * uma loja que não recebe mais encomenda. Some da consulta em vez de aparecer com uma flag que a
   * tela pode esquecer de ler.
   */
  @Transactional(readOnly = true)
  public PontoCustodiaResponse buscar(UUID id) {
    PontoCustodia ponto =
        pontoCustodiaRepository
            .findById(id)
            .filter(PontoCustodia::isAtivo)
            .orElseThrow(() -> new RecursoNaoEncontradoException(NAO_ENCONTRADO));
    return responseDe(ponto, null);
  }

  /**
   * Pontos ativos no raio, do mais próximo para o mais distante.
   *
   * <p>O PostGIS devolve pares (id, distância) — a rehidratação acontece aqui, com um único {@code
   * findAllById}, e a ORDEM vem do banco, não de uma reordenação em Java. Ver ADR 0007: {@code
   * ConsultasGeoespaciais} não pode conhecer os tipos deste módulo, então ela devolve o par neutro
   * e quem sabe o que é um ponto de custódia monta a resposta.
   */
  @Transactional(readOnly = true)
  public List<PontoCustodiaResponse> proximos(
      BigDecimal lat, BigDecimal lon, int raioMetros, int limite) {

    List<ConsultasGeoespaciais.AlvoProximo> alvos =
        consultasGeoespaciais.pontosCustodiaNoRaio(lat, lon, raioMetros, limite);
    if (alvos.isEmpty()) {
      return List.of();
    }

    Map<UUID, Double> distanciaPorId = new LinkedHashMap<>();
    alvos.forEach(alvo -> distanciaPorId.put(alvo.id(), alvo.distanciaM()));

    return pontoCustodiaRepository.findAllById(distanciaPorId.keySet()).stream()
        // findAllById não promete ordem; a que importa é a do PostGIS, por distância crescente.
        .sorted(Comparator.comparingDouble(p -> distanciaPorId.get(p.getId())))
        .map(p -> responseDe(p, arredondar(distanciaPorId.get(p.getId()), 2)))
        .toList();
  }

  private static PontoCustodiaResponse responseDe(PontoCustodia ponto, BigDecimal distanciaM) {
    return new PontoCustodiaResponse(
        ponto.getId(),
        ponto.getCodigo(),
        ponto.getTipo().name(),
        ponto.getApelido(),
        arredondar(Coordenadas.latitude(ponto.getPonto()).doubleValue(), CASAS_COORDENADA),
        arredondar(Coordenadas.longitude(ponto.getPonto()).doubleValue(), CASAS_COORDENADA),
        ponto.getCapacidade(),
        ponto.getOcupacao(),
        distanciaM);
  }

  private static BigDecimal arredondar(double valor, int casas) {
    return BigDecimal.valueOf(valor).setScale(casas, RoundingMode.HALF_UP);
  }
}
