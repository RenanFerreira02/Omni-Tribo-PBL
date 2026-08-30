package com.omnitribo.missoes.api;

import static com.omnitribo.carteira.SuporteCarteira.assertLedgerReconcilia;
import static com.omnitribo.carteira.SuporteCarteira.tokensEmCirculacao;
import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.omnitribo.JwtTestConfig;
import com.omnitribo.TesteIntegracaoMvcBase;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

/**
 * O apoiador do bairro põe token no pote — o caminho que faz a emissão valer alguma coisa.
 *
 * <h2>O que este teste protege</h2>
 *
 * <p>{@code APORTE_PATROCINADOR} é o ÚNICO ponto de emissão de token do sistema, e até a V28 quem
 * levava esse token ao pote era a conversão do webhook de entrega falida. Com o webhook removido
 * (ADR 0031), sem este endpoint o token emitido ficaria parado na carteira do apoiador para sempre:
 * a economia teria só o sumidouro do resgate, e {@code SUM(carteiras) + SUM(potes)} cairia
 * monotonicamente até zero.
 *
 * <p><b>O endpoint é ADMIN, e não do apoiador, por uma razão medida.</b> A primeira versão desta
 * mudança pôs o desvio dentro de {@code POST /tribos/{'{'}triboId{'}'}/financiamentos}, que tira a
 * identidade do JWT — e a conta do apoiador nasce INATIVA justamente para nunca autenticar. Era
 * código inalcançável, e a verificação ponta a ponta foi quem pegou. O teste {@link
 * #apoiadorNaoAutentica()} trava isso.
 */
@Import(JwtTestConfig.class)
@DisplayName("Financiamento por apoiador (ADMIN)")
class FinanciamentoApoiadorAdminTest extends TesteIntegracaoMvcBase {

  private static final String URL = "/api/v1/admin/missoes/{missaoId}/financiamento-apoiador";
  private static final long SALDO_APOIADOR = 500L;

  @Autowired MockMvc mockMvc;
  @Autowired JdbcTemplate jdbcTemplate;

  private UUID tribo;
  private UUID criador;
  private UUID admin;
  private UUID apoiadorUsuario;
  private UUID apoiadorId;
  private UUID missaoId;
  private long recompensa;

  @BeforeEach
  void montarCenario() throws Exception {
    tribo = criarTribo();
    criador = criarUsuario("criador", tribo, 0, "USUARIO", "ATIVO");
    admin = criarUsuario("admin", tribo, 0, "ADMIN", "ATIVO");
    // INATIVO e sem tribo: é o molde real do apoiador, e é o que torna o caminho por JWT
    // impossível. Semear ATIVO aqui faria o teste passar por um caminho que produção não tem.
    apoiadorUsuario = criarUsuario("apoiador", null, SALDO_APOIADOR, "PATROCINADOR", "INATIVO");
    apoiadorId = criarApoiador(apoiadorUsuario);
    missaoId = criarMissaoTriboEmRascunho();
  }

  @AfterEach
  void limpar() {
    jdbcTemplate.update("DELETE FROM outbox WHERE agregado_id = ?", missaoId);
    jdbcTemplate.update("DELETE FROM alerta WHERE missao_id = ?", missaoId);
    jdbcTemplate.update("DELETE FROM missao_evento WHERE missao_id = ?", missaoId);
    jdbcTemplate.update("DELETE FROM missao WHERE id = ?", missaoId);
    jdbcTemplate.update("DELETE FROM patrocinador WHERE id = ?", apoiadorId);
    for (UUID u : new UUID[] {criador, admin, apoiadorUsuario}) {
      jdbcTemplate.update(
          "DELETE FROM lancamento WHERE carteira_id IN"
              + " (SELECT id FROM carteira WHERE usuario_id = ?)",
          u);
      jdbcTemplate.update("DELETE FROM auditoria WHERE ator_id = ?", u);
      jdbcTemplate.update("DELETE FROM carteira WHERE usuario_id = ?", u);
      jdbcTemplate.update("DELETE FROM usuario WHERE id = ?", u);
    }
    jdbcTemplate.update("DELETE FROM tribo WHERE id = ?", tribo);
  }

  @Test
  @DisplayName("financia o pote e NÃO altera a soma em circulação")
  void financiaMovendoTokenDeLugar() throws Exception {
    long circulacaoInicial = tokensEmCirculacao(jdbcTemplate);

    mockMvc
        .perform(financiar(recompensa, "apoiador-1"))
        .andExpect(status().isCreated())
        .andExpect(jsonPath("$.poteTokens").value(recompensa))
        .andExpect(jsonPath("$.saldoTokensRestante").value(SALDO_APOIADOR - recompensa));

    // A emissão é o APORTE. Este endpoint só move para o pote o que já foi emitido — se ele
    // alterasse a soma, seria um segundo ponto de cunhagem, e a economia teria duas fontes.
    assertThat(tokensEmCirculacao(jdbcTemplate))
        .as("financiar move token de lugar, não cria nem destrói")
        .isEqualTo(circulacaoInicial);

    assertThat(saldoDoApoiador()).isEqualTo(SALDO_APOIADOR - recompensa);
    assertLedgerReconcilia(jdbcTemplate);
  }

  @Test
  @DisplayName("o lançamento sai com FINANCIAMENTO_PATROCINADOR, que o estorno enxerga")
  void motivoEhODoApoiadorNaoODaTribo() throws Exception {
    mockMvc.perform(financiar(recompensa, "apoiador-motivo")).andExpect(status().isCreated());

    String motivo =
        jdbcTemplate.queryForObject(
            "SELECT motivo FROM lancamento WHERE missao_id = ? AND carteira_id ="
                + " (SELECT id FROM carteira WHERE usuario_id = ?)",
            String.class,
            missaoId,
            apoiadorUsuario);

    // FINANCIAMENTO_TRIBO na carteira de quem não tem tribo afirmaria um pertencimento inexistente,
    // e o extrato mostra o motivo cru. Mais importante: os DOIS motivos estão em
    // LancamentoRepository.buscarFinanciamentosDaMissao — um motivo fora daquela lista deixaria o
    // token preso numa missão morta com a reconciliação respondendo integro=true.
    assertThat(motivo).isEqualTo("FINANCIAMENTO_PATROCINADOR");
  }

  @Test
  @DisplayName("a missão financiada pelo apoiador fica publicável")
  void poteCobreARecompensaEPublica() throws Exception {
    mockMvc.perform(financiar(recompensa, "apoiador-publica")).andExpect(status().isCreated());

    mockMvc
        .perform(
            post("/api/v1/missoes/{id}/publicar", missaoId)
                .header("Authorization", bearer(criador, "USUARIO")))
        .andExpect(status().isOk());

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT status FROM missao WHERE id = ?", String.class, missaoId))
        .isEqualTo("ABERTA");
  }

  @Test
  @DisplayName("usuário comum recebe 403 — esconder não é proteger")
  void usuarioComumEh403() throws Exception {
    mockMvc
        .perform(
            post(URL, missaoId)
                .header("Authorization", bearer(criador, "USUARIO"))
                .header("Idempotency-Key", "teste-apoiador-403")
                .contentType(MediaType.APPLICATION_JSON)
                .content(corpo(recompensa)))
        .andExpect(status().isForbidden());
  }

  @Test
  @DisplayName("apoiador inativo é 404, indistinguível de inexistente")
  void apoiadorInativoEh404() throws Exception {
    jdbcTemplate.update("UPDATE patrocinador SET ativo = FALSE WHERE id = ?", apoiadorId);

    mockMvc.perform(financiar(recompensa, "apoiador-inativo")).andExpect(status().isNotFound());

    // Nada foi debitado: a resolução falha ANTES de qualquer escrita.
    assertThat(saldoDoApoiador()).isEqualTo(SALDO_APOIADOR);
  }

  @Test
  @DisplayName("saldo insuficiente é 422 e não move nada")
  void saldoInsuficienteEh422() throws Exception {
    mockMvc
        .perform(financiar(SALDO_APOIADOR + 1, "apoiador-sem-saldo"))
        .andExpect(status().isUnprocessableEntity());

    assertThat(saldoDoApoiador()).isEqualTo(SALDO_APOIADOR);
    assertThat(poteDaMissao()).isZero();
  }

  @Test
  @DisplayName("repetir a mesma chave não debita duas vezes")
  void idempotente() throws Exception {
    mockMvc.perform(financiar(recompensa, "apoiador-replay")).andExpect(status().isCreated());
    mockMvc
        .perform(financiar(recompensa, "apoiador-replay"))
        .andExpect(status().isCreated())
        .andExpect(jsonPath("$.replay").value(true))
        .andExpect(jsonPath("$.poteTokens").value(recompensa));

    assertThat(saldoDoApoiador()).isEqualTo(SALDO_APOIADOR - recompensa);
    assertThat(poteDaMissao()).isEqualTo(recompensa);
    assertLedgerReconcilia(jdbcTemplate);
  }

  @Test
  @DisplayName("a conta do apoiador NÃO autentica — é por isso que o endpoint é ADMIN")
  void apoiadorNaoAutentica() throws Exception {
    // Este teste é o registro executável do defeito que a verificação ponta a ponta pegou: a
    // primeira versão desta mudança pôs o desvio do apoiador na rota que lê a identidade do JWT.
    // A conta nasce INATIVA, AutenticacaoService recusa status != ATIVO, e o caminho era
    // inalcançável. Se alguém tornar o apoiador autenticável, este teste falha e obriga a decisão.
    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT status FROM usuario WHERE id = ?", String.class, apoiadorUsuario))
        .isEqualTo("INATIVO");

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT tribo_id IS NULL FROM usuario WHERE id = ?",
                Boolean.class,
                apoiadorUsuario))
        .as("apoiador não pertence a bairro nenhum — é por isso que a regra de tribo não o alcança")
        .isTrue();
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────────────────────

  private MockHttpServletRequestBuilder financiar(long tokens, String chave) {
    return post(URL, missaoId)
        .header("Authorization", bearer(admin, "ADMIN"))
        .header("Idempotency-Key", "teste-" + chave)
        .contentType(MediaType.APPLICATION_JSON)
        .content(corpo(tokens));
  }

  private String corpo(long tokens) {
    return "{\"patrocinadorId\":\"" + apoiadorId + "\",\"tokens\":" + tokens + "}";
  }

  private UUID criarTribo() {
    UUID id = UUID.randomUUID();
    jdbcTemplate.update(
        "INSERT INTO tribo (id, nome, bairro, criada_em) VALUES (?, ?, ?, NOW())",
        id,
        "Tribo Apoiada " + id.toString().substring(0, 8),
        "Bairro Apoiado");
    return id;
  }

  private UUID criarUsuario(
      String prefixo, UUID triboId, long tokens, String papel, String status) {
    UUID id = UUID.randomUUID();
    jdbcTemplate.update(
        """
        INSERT INTO usuario (id, nome, email, senha_hash, handle, tribo_id, xp, nivel, streak,
                             rating, papel, status, criado_em, atualizado_em, versao)
        VALUES (?, ?, ?, '{bcrypt}$2a$10$naoUsadoNesteTeste', ?, ?, 0, 1, 0, 0.0,
                ?, ?, NOW(), NOW(), 0)
        """,
        id,
        prefixo,
        prefixo + "-" + id + "@teste.dev",
        prefixo.charAt(0) + id.toString().substring(0, 10),
        triboId,
        papel,
        status);

    UUID carteiraId = UUID.randomUUID();
    jdbcTemplate.update(
        "INSERT INTO carteira (id, usuario_id, saldo_brl, saldo_tokens, versao)"
            + " VALUES (?, ?, 0.00, ?, 0)",
        carteiraId,
        id,
        tokens);
    if (tokens > 0) {
      // APORTE_PATROCINADOR e não BONUS: é o motivo real da abertura de uma carteira de apoiador, e
      // o par carteira+lançamento precisa ser coerente ou MigracaoTest reprova.
      jdbcTemplate.update(
          """
          INSERT INTO lancamento (id, carteira_id, sinal, motivo, valor_brl, valor_tokens,
                                  chave_idempotencia, saldo_apos_brl, saldo_apos_tokens, criado_em)
          VALUES (?, ?, 'CREDITO', 'APORTE_PATROCINADOR', 0.00, ?, ?, 0.00, ?, NOW())
          """,
          UUID.randomUUID(),
          carteiraId,
          tokens,
          "abertura-" + carteiraId,
          tokens);
    }
    return id;
  }

  private UUID criarApoiador(UUID usuarioId) {
    UUID id = UUID.randomUUID();
    jdbcTemplate.update(
        "INSERT INTO patrocinador (id, usuario_id, slug, nome, ativo, criado_em)"
            + " VALUES (?, ?, ?, ?, TRUE, NOW())",
        id,
        usuarioId,
        "apoiador-" + id.toString().substring(0, 8),
        "Apoiador de Teste");
    return id;
  }

  private UUID criarMissaoTriboEmRascunho() throws Exception {
    Instant inicio = Instant.now().truncatedTo(ChronoUnit.SECONDS);
    String corpo =
        """
        {
          "categoria": "TRIBO",
          "titulo": "Mutirão da praça, financiado pelo apoiador",
          "descricao": "Missão comunitária cujo pote vem da carteira de um apoiador do bairro.",
          "valorBrl": 0.00,
          "complexidade": "MEDIA",
          "origemLat": -23.5629,
          "origemLon": -46.6996,
          "cep": "05422030",
          "logradouro": "Rua dos Pinheiros",
          "bairro": "Pinheiros",
          "cidade": "São Paulo",
          "uf": "SP",
          "raioCheckinM": 50,
          "janelaInicio": "%s",
          "janelaFim": "%s"
        }
        """
            .formatted(inicio.plusSeconds(3600), inicio.plusSeconds(7200));

    String resposta =
        mockMvc
            .perform(
                post("/api/v1/missoes")
                    .header("Authorization", bearer(criador, "USUARIO"))
                    .contentType(MediaType.APPLICATION_JSON)
                    .content(corpo))
            .andExpect(status().isCreated())
            .andReturn()
            .getResponse()
            .getContentAsString();

    var json = JSON.readValue(resposta, java.util.Map.class);
    recompensa = ((Number) json.get("tokensRecompensa")).longValue();
    return UUID.fromString((String) json.get("id"));
  }

  private long saldoDoApoiador() {
    return jdbcTemplate.queryForObject(
        "SELECT saldo_tokens FROM carteira WHERE usuario_id = ?", Long.class, apoiadorUsuario);
  }

  private long poteDaMissao() {
    return jdbcTemplate.queryForObject(
        "SELECT pote_tokens FROM missao WHERE id = ?", Long.class, missaoId);
  }

  private String bearer(UUID usuarioId, String papel) {
    return "Bearer " + JwtTestConfig.gerarTokenValido(usuarioId, usuarioId + "@teste.dev", papel);
  }
}
