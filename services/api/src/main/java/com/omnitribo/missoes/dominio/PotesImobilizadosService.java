package com.omnitribo.missoes.dominio;

import com.omnitribo.compartilhado.api.PaginaResponse;
import com.omnitribo.missoes.api.PoteImobilizadoResponse;
import com.omnitribo.missoes.api.PotesImobilizadosResponse;
import com.omnitribo.missoes.infra.MissaoRepository;
import java.time.Instant;
import java.util.Set;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Mostra o token preso em missão que não anda.
 *
 * <h2>Por que isto existe</h2>
 *
 * <p>Token no pote de uma missão parada viola a CONSERVAÇÃO enquanto a reconciliação segue
 * respondendo {@code integro=true} — ledger e projeção batem, e o dinheiro de quem financiou está
 * imobilizado mesmo assim. O que já existia era PREVENTIVO: a varredura por prazo ({@link
 * ExpiracaoMissoesService}) e a porta de ADMIN ({@code POST /missoes/{id}/destravar}) tiram a
 * missão do limbo. Faltava o instrumento DETECTIVO: nada dizia ao administrador QUAIS missões
 * destravar.
 *
 * <p>É leitura pura. Não destrava, não estorna e não muda status: a decisão continua sendo do
 * ADMIN, missão por missão, com justificativa registrada.
 */
@Service
public class PotesImobilizadosService {

  /**
   * O que conta como "parada".
   *
   * <p>EM_DISPUTA entra, e é o caso que mais importa: os outros dois têm varredura por prazo, a
   * disputa NÃO — ela só sai por {@code resolver}, que depende de um ADMIN agir. É exatamente a
   * missão que fica presa sem que nada a mostre.
   *
   * <p>ABERTA e ACEITA ficam de fora: estão esperando, não paradas. ABERTA expira pela janela, e
   * ACEITA ainda pode ser iniciada ou desistida pelo executor.
   */
  static final Set<StatusMissao> STATUS_PARADOS =
      Set.of(
          StatusMissao.EM_ANDAMENTO, StatusMissao.AGUARDANDO_CONFIRMACAO, StatusMissao.EM_DISPUTA);

  private final MissaoRepository missaoRepository;

  public PotesImobilizadosService(MissaoRepository missaoRepository) {
    this.missaoRepository = missaoRepository;
  }

  /**
   * As duas consultas rodam na MESMA transação somente-leitura. Não é um snapshot — em READ
   * COMMITTED uma conclusão entre as duas pode deixar o total um pote à frente da lista —, e para
   * um painel de diagnóstico isso é aceito: a próxima carga corrige, e nenhuma decisão de valor é
   * tomada a partir deste número.
   */
  @Transactional(readOnly = true)
  public PotesImobilizadosResponse listar(int pagina, int tamanho) {
    Instant agora = Instant.now();
    Page<PoteImobilizadoResponse> missoes =
        missaoRepository
            .potesImobilizados(STATUS_PARADOS, PageRequest.of(pagina, tamanho))
            .map(missao -> PoteImobilizadoResponse.de(missao, agora));
    long total = missaoRepository.somarPotesImobilizados(STATUS_PARADOS);
    return new PotesImobilizadosResponse(total, PaginaResponse.de(missoes));
  }
}
