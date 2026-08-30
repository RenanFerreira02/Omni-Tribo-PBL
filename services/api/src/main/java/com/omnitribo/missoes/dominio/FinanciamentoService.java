package com.omnitribo.missoes.dominio;

import com.omnitribo.carteira.api.FinanciamentoMissao;
import com.omnitribo.carteira.api.ResultadoFinanciamento;
import com.omnitribo.compartilhado.dominio.Auditavel;
import com.omnitribo.compartilhado.dominio.ChaveIdempotencia;
import com.omnitribo.compartilhado.dominio.RecursoNaoEncontradoException;
import com.omnitribo.compartilhado.dominio.RegraNegocioVioladaException;
import com.omnitribo.identidade.api.ConsultaAfiliacao;
import com.omnitribo.identidade.api.ConsultaPatrocinador;
import com.omnitribo.missoes.api.FinanciamentoResponse;
import com.omnitribo.missoes.infra.MissaoRepository;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Financiamento de missão comunitária: quem financia debita tokens da própria carteira e credita o
 * pote da missão.
 *
 * <p>É o que torna a economia não-fictícia. Sem ele, concluir uma missão TRIBO cunharia tokens do
 * nada e a oferta cresceria sem limite. Com ele, o token que o executor recebe é exatamente o token
 * que alguém pôs no pote — a soma (carteiras + potes) é constante ao longo de todo o ciclo de vida
 * da missão.
 *
 * <p><b>Dois financiadores possíveis, com autorizações diferentes.</b> O membro da tribo é o caso
 * normal. O APOIADOR do bairro é o caso que a V28 trouxe para cá (ADR 0031): ele é o único titular
 * que recebe emissão de token, e sem um caminho para pôr esse token num pote a emissão seria saldo
 * parado — a economia teria só o sumidouro do resgate. O caminho dele era a conversão do webhook de
 * entrega falida, que saiu junto com a extensão logística.
 */
@Service
public class FinanciamentoService {

  private static final String NAO_ENCONTRADA = "Missão não encontrada.";

  private final MissaoRepository missaoRepository;
  private final FinanciamentoMissao financiamentoMissao;
  private final ConsultaAfiliacao consultaAfiliacao;
  private final ConsultaPatrocinador consultaPatrocinador;

  public FinanciamentoService(
      MissaoRepository missaoRepository,
      FinanciamentoMissao financiamentoMissao,
      ConsultaAfiliacao consultaAfiliacao,
      ConsultaPatrocinador consultaPatrocinador) {
    this.missaoRepository = missaoRepository;
    this.financiamentoMissao = financiamentoMissao;
    this.consultaAfiliacao = consultaAfiliacao;
    this.consultaPatrocinador = consultaPatrocinador;
  }

  @Auditavel(acao = "MISSAO_FINANCIADA", entidade = "missao")
  @Transactional
  public FinanciamentoResponse financiar(
      UUID triboId, UUID missaoId, long tokens, UUID financiadorId, String chaveDoCliente) {
    return executar(triboId, missaoId, tokens, financiadorId, chaveDoCliente, false);
  }

  /**
   * ADMIN financia o pote em nome de um APOIADOR do bairro.
   *
   * <p><b>Por que este caminho existe separado, e por que ele é ADMIN.</b> O apoiador é um titular
   * de carteira que NUNCA autentica: a conta nasce com status INATIVO, e {@code
   * AutenticacaoService} recusa qualquer status diferente de ATIVO. Ele não tem — e não deve ter —
   * um JWT, então não alcança {@code POST /tribos/{'{'}triboId{'}'}/financiamentos}, que tira a
   * identidade do token. Um caminho que dependesse do JWT dele seria código inalcançável.
   *
   * <p>É coerente com o resto: o apoiador é administrado de ponta a ponta — cadastro, aporte e
   * encerramento são todos ADMIN. Sem este método, o token que o aporte emite não teria como entrar
   * no ciclo de missões e ficaria parado na carteira dele para sempre; a economia teria só o
   * sumidouro do resgate, e a soma cairia monotonicamente. Ver ADR 0031 §2.
   *
   * <p>{@code triboId} nulo, e não é omissão: o apoiador não pertence a bairro nenhum, e é
   * exatamente por isso que ele precisa de um caminho próprio em vez de uma regra de tribo
   * afrouxada para todo mundo.
   */
  @Auditavel(acao = "MISSAO_FINANCIADA_POR_APOIADOR", entidade = "missao")
  @Transactional
  public FinanciamentoResponse financiarComoApoiador(
      UUID missaoId, long tokens, UUID patrocinadorId, String chaveDoCliente) {

    // Resolve a RELAÇÃO de apoio → titular da carteira. Vazio cobre "não existe" e "apoio
    // desativado" de uma vez: os dois levam ao mesmo desfecho, e é a porta que aplica o filtro por
    // `ativo` para que um `if` esquecido aqui não aceite financiamento de um apoio encerrado.
    UUID titular =
        consultaPatrocinador
            .usuarioIdDoApoiadorAtivo(patrocinadorId)
            .orElseThrow(
                () -> new RecursoNaoEncontradoException("Apoiador não encontrado ou inativo."));

    return executar(null, missaoId, tokens, titular, chaveDoCliente, true);
  }

  private FinanciamentoResponse executar(
      UUID triboId,
      UUID missaoId,
      long tokens,
      UUID financiadorId,
      String chaveDoCliente,
      boolean comoApoiador) {

    Instant agora = Instant.now();

    // LOCK PRIMEIRO, e a missão é a primeira da ordem global: missao → carteira. Financiar e
    // concluir disputam exatamente estas duas linhas; se o financiamento travasse a carteira antes,
    // as duas operações na mesma missão poderiam se travar mutuamente.
    Missao missao =
        missaoRepository
            .buscarParaAtualizar(missaoId)
            .orElseThrow(() -> new RecursoNaoEncontradoException(NAO_ENCONTRADA));

    String chave = ChaveIdempotencia.financiamento(financiadorId, missaoId, chaveDoCliente);

    // AUTORIZAÇÃO PRIMEIRO, antes até da sondagem. Sondar antes devolveria o pote e a recompensa da
    // missão a quem não é da tribo — é a mesma razão pela qual o check-in autoriza antes de sondar.
    // Para o apoiador não há o que autorizar AQUI: o ADMIN foi autorizado na borda, e o titular já
    // veio resolvido de um apoio ATIVO — é a resolução que faz o papel da autorização, e ela
    // acontece antes de qualquer leitura da missão.
    if (!comoApoiador) {
      validarAutorizacao(triboId, missao, financiadorId);
    }

    // LOCK (carteira) → SONDA → VALIDA → ESCREVE, que é a ordem canônica do projeto.
    //
    // A sondagem vinha DEPOIS das validações, e por isso o retry de um financiamento que completou
    // o pote recebia 422 ("pote ficaria acima da recompensa") em vez do replay: na segunda chamada
    // o pote já estava cheio pela primeira. O valor nunca duplicou — o débito segue barrado pela
    // sondagem sob lock —, mas o cliente via um erro para uma operação bem-sucedida, e não tinha
    // como distinguir isso de uma falha real. Mesmo defeito se a missão tivesse sido cancelada
    // entre a chamada original e o retry.
    Optional<ResultadoFinanciamento> replay = financiamentoMissao.sondar(financiadorId, chave);
    if (replay.isPresent()) {
      return new FinanciamentoResponse(
          missao.getId(),
          missao.getPoteTokens(),
          missao.getTokensRecompensa(),
          replay.get().saldoTokensRestante(),
          true);
    }

    // Regras de ESTADO só depois da sondagem: elas descrevem se a operação cabe AGORA, e um replay
    // não é uma operação nova.
    validarEstado(missao);
    validarTeto(missao, tokens);

    // Motivo do lançamento decidido pelo TIPO de financiador: FINANCIAMENTO_TRIBO na carteira de um
    // apoiador afirmaria um pertencimento que não existe — ele não tem tribo —, e o extrato e a
    // exportação LGPD mostram o motivo cru. Os DOIS motivos estão em
    // LancamentoRepository.buscarFinanciamentosDaMissao, então o estorno de missão cancelada ou
    // expirada devolve o token aos dois financiadores sem nenhuma alteração.
    ResultadoFinanciamento debito =
        comoApoiador
            ? financiamentoMissao
                .debitarPatrocinador(financiadorId, missaoId, tokens, chave, agora)
                // VAZIO aqui é saldo insuficiente. O contrato da porta devolve valor porque o
                // chamador original (o webhook, removido na V28) precisava GRAVAR a recusa; neste
                // caminho quem chama é uma requisição HTTP, e a tradução correta é 422 — a mesma
                // que `debitar` produz sozinho para o membro da tribo.
                .orElseThrow(
                    () ->
                        new RegraNegocioVioladaException(
                            "Saldo insuficiente para financiar " + tokens + " tokens."))
            : financiamentoMissao.debitar(financiadorId, missaoId, tokens, chave, agora);

    // Só credita o pote se o débito de fato aconteceu. Num replay, o pote já recebeu na primeira
    // chamada — creditar de novo duplicaria tokens que saíram da carteira uma vez só, e a
    // conservação quebraria exatamente no caminho que ela existe para proteger.
    if (!debito.replay()) {
      missao.creditarPote(tokens);
      missaoRepository.save(missao);
    }

    return new FinanciamentoResponse(
        missao.getId(),
        missao.getPoteTokens(),
        missao.getTokensRecompensa(),
        debito.saldoTokensRestante(),
        debito.replay());
  }

  /**
   * Quem pode financiar esta missão. Roda ANTES da sondagem de idempotência.
   *
   * <p>Era metade de um {@code validarEscopo} único, e a separação não é cosmética: é ela que põe a
   * autorização antes da sondagem e as regras de estado depois, replicando a ordem {@code 403 →
   * sondagem → 409/422 → gravação} já sancionada para o check-in. Sondar antes de autorizar
   * devolveria pote e recompensa da missão a quem não é da tribo.
   *
   * <p>O {@code triboId} do path não é decorativo: ele é o escopo declarado pelo cliente, e
   * conferir que ele bate com a tribo real do financiador impede que alguém financie por uma tribo
   * à qual não pertence só trocando a URL.
   */
  private void validarAutorizacao(UUID triboId, Missao missao, UUID financiadorId) {
    Optional<UUID> triboFinanciador = consultaAfiliacao.triboDe(financiadorId);
    if (triboFinanciador.isEmpty() || !triboFinanciador.get().equals(triboId)) {
      throw new RegraNegocioVioladaException("Você não pertence a esta tribo.");
    }

    if (!consultaAfiliacao.mesmaTribo(financiadorId, missao.getCriadorId())) {
      throw new RegraNegocioVioladaException(
          "Missão pertence a outra tribo e não pode ser financiada por você.");
    }
  }

  /**
   * Se a missão aceita financiamento no estado em que está. Roda DEPOIS da sondagem.
   *
   * <p>Depois porque estas regras descrevem se a operação cabe AGORA, e um replay não é uma
   * operação nova: recusar o retry de um financiamento que já aconteceu, porque a missão foi
   * cancelada enquanto isso, entrega um erro para algo que deu certo.
   */
  private static void validarEstado(Missao missao) {
    // Espelha `Missao.fontePote`: quem paga do pote é financiável, quem cunha não é. Testar a FONTE
    // em vez de listar categorias tira daqui a chance de as duas regras divergirem — foi o que
    // quase
    // aconteceu quando AJUDA mudou de lado (ADR 0025): incluí-la só no construtor e esquecer esta
    // lista a deixaria impublicável E infinanciável ao mesmo tempo, sem nenhum erro apontando a
    // causa. A missão exigiria pote para publicar e recusaria todo financiamento que o formasse.
    if (missao.getFontePote() == FontePote.CUNHAGEM) {
      throw new RegraNegocioVioladaException(
          "Missão de categoria " + missao.getCategoria() + " não aceita financiamento em tokens.");
    }

    // PATROCINADOR é fonte HISTÓRICA desde a V28: nenhuma missão nova nasce com ela, porque quem a
    // produzia era a conversão do webhook de entrega falida. As linhas antigas continuam no banco,
    // e
    // continuam recusando financiamento pelo mesmo motivo de sempre — nasceram com o pote completo,
    // e um aporte por cima bateria em validarTeto ("pote ficaria acima da recompensa").
    //
    // Note que APOIADOR financiando uma missão COMUNIDADE não passa por aqui: a fonte da missão
    // continua COMUNIDADE, porque fonte_pote diz de onde o pote SAI para o executor, não quem o
    // encheu.
    if (missao.getFontePote() == FontePote.PATROCINADOR) {
      throw new RegraNegocioVioladaException(
          "Missão com pote financiado na criação não aceita financiamento novo.");
    }

    // Financiar depois de concluída, cancelada ou expirada seria pôr token num pote que já não
    // paga ninguém — no melhor caso vira estorno, no pior fica preso.
    if (missao.getStatus().ehTerminal()) {
      throw new RegraNegocioVioladaException("Missão em estado terminal não aceita financiamento.");
    }

    // Rascunho É financiável, e por qualquer membro da tribo — não é descuido. Publicar missão
    // comunitária exige pote cobrindo a recompensa, então o financiamento acontece necessariamente
    // ANTES da publicação, e restringi-lo ao criador obrigaria uma pessoa só a bancar 100% da
    // missão, matando o co-financiamento que é o propósito da moeda comunitária.
    //
    // O que fecha o risco de token preso não é proibir aqui, é a transição RASCUNHO --CANCELAR-->
    // CANCELADA, que dá ao criador uma saída que estorna o pote (ver StatusMissao).
  }

  /**
   * O pote não pode passar da recompensa.
   *
   * <p>A conclusão debita exatamente {@code tokensRecompensa} do pote, e {@code CONCLUIDA} é
   * terminal — sobra no pote ficaria presa para sempre, porque o estorno só roda em CANCELADA e
   * EXPIRADA. Recusar o excedente na entrada é mais simples e mais honesto que estornar resíduo na
   * saída: o financiador descobre na hora que aquele token não é necessário, em vez de descobrir
   * depois que ele sumiu.
   */
  private static void validarTeto(Missao missao, long tokens) {
    long depois = missao.getPoteTokens() + tokens;
    if (depois > missao.getTokensRecompensa()) {
      throw new RegraNegocioVioladaException(
          "Pote ficaria com "
              + depois
              + " tokens, acima da recompensa de "
              + missao.getTokensRecompensa()
              + ". Faltam apenas "
              + (missao.getTokensRecompensa() - missao.getPoteTokens())
              + ".");
    }
  }
}
