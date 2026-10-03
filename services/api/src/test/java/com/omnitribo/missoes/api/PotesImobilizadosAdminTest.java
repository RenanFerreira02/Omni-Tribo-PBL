package com.omnitribo.missoes.api;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.omnitribo.JwtTestConfig;
import com.omnitribo.TesteIntegracaoMvcBase;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Import;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import tools.jackson.databind.JsonNode;

/**
 * O diagnóstico de potes imobilizados.
 *
 * <h2>O que este teste protege</h2>
 *
 * <p>Token preso em missão parada viola a conservação enquanto a reconciliação responde {@code
 * integro=true}. Até este endpoint, nada mostrava esses potes — e já houve uma consulta com esse
 * propósito que ninguém chamava, removida como órfã. Os testes abaixo provam que a consulta TEM
 * chamador e que o recorte é o certo: parada com token entra; esperando, vazia ou encerrada não.
 *
 * <p>O banco de teste é compartilhado com o seed e com as outras classes, então nenhuma asserção
 * supõe a lista vazia nem um total absoluto: tudo é medido sobre as missões que ESTA classe criou,
 * por id, e o total é conferido como DIFERENÇA.
 */
@Import(JwtTestConfig.class)
@DisplayName("Potes imobilizados (ADMIN)")
class PotesImobilizadosAdminTest extends TesteIntegracaoMvcBase {

  private static final String URL = "/api/v1/admin/missoes/potes-imobilizados";

  @Autowired MockMvc mockMvc;
  @Autowired JdbcTemplate jdbcTemplate;

  private UUID tribo;
  private UUID admin;
  private UUID usuario;
  private final List<UUID> missoes = new ArrayList<>();

  @BeforeEach
  void montarCenario() {
    tribo = UUID.randomUUID();
    jdbcTemplate.update(
        "INSERT INTO tribo (id, nome, bairro, criada_em) VALUES (?, ?, ?, NOW())",
        tribo,
        "Tribo Parada " + tribo.toString().substring(0, 8),
        "Bairro Parado");
    admin = criarUsuario("admin", "ADMIN");
    usuario = criarUsuario("vizinho", "USUARIO");
  }

  @AfterEach
  void limpar() {
    for (UUID missao : missoes) {
      jdbcTemplate.update("DELETE FROM missao WHERE id = ?", missao);
    }
    for (UUID u : new UUID[] {admin, usuario}) {
      jdbcTemplate.update("DELETE FROM auditoria WHERE ator_id = ?", u);
      jdbcTemplate.update("DELETE FROM usuario WHERE id = ?", u);
    }
    jdbcTemplate.update("DELETE FROM tribo WHERE id = ?", tribo);
  }

  @Test
  @DisplayName("lista os três estados parados com token no pote, do mais antigo para o mais novo")
  void listaParadasComPoteEmOrdemDeAntiguidade() throws Exception {
    UUID recente = criarMissao("EM_ANDAMENTO", 18, 5);
    UUID antiga = criarMissao("EM_DISPUTA", 40, 200);
    UUID intermediaria = criarMissao("AGUARDANDO_CONFIRMACAO", 30, 96);

    JsonNode conteudo = listar().get("missoes").get("conteudo");

    assertThat(posicaoDe(conteudo, antiga))
        .as("a disputa parada há mais tempo vem antes")
        .isNotNegative()
        .isLessThan(posicaoDe(conteudo, intermediaria));
    assertThat(posicaoDe(conteudo, intermediaria)).isLessThan(posicaoDe(conteudo, recente));

    JsonNode linha = conteudo.get(posicaoDe(conteudo, antiga));
    assertThat(linha.get("status").asString()).isEqualTo("EM_DISPUTA");
    assertThat(linha.get("poteTokens").asLong()).isEqualTo(40);
    assertThat(linha.get("fontePote").asString()).isEqualTo("COMUNIDADE");
    // 200 horas atrás, com folga de uma hora para a virada do relógio entre o INSERT e a leitura.
    assertThat(linha.get("horasNoEstado").asLong()).isBetween(199L, 201L);
  }

  @Test
  @DisplayName("não lista missão esperando, sem pote ou encerrada")
  void naoListaOQueNaoEstaImobilizado() throws Exception {
    UUID abertaComPote = criarMissao("ABERTA", 38, 300);
    UUID aceitaComPote = criarMissao("ACEITA", 42, 300);
    UUID paradaSemPote = criarMissao("EM_ANDAMENTO", 0, 300);
    UUID concluida = criarMissao("CONCLUIDA", 0, 300);
    UUID expirada = criarMissao("EXPIRADA", 0, 300);
    UUID parada = criarMissao("EM_ANDAMENTO", 25, 300);

    JsonNode conteudo = listar().get("missoes").get("conteudo");

    assertThat(posicaoDe(conteudo, parada)).as("o controle positivo aparece").isNotNegative();
    for (UUID fora : List.of(abertaComPote, aceitaComPote, paradaSemPote, concluida, expirada)) {
      assertThat(posicaoDe(conteudo, fora))
          .as("missão %s não é pote imobilizado", fora)
          .isEqualTo(-1);
    }
  }

  @Test
  @DisplayName("o total soma todos os potes parados, não só os da página")
  void totalEhDoConjuntoENaoDaPagina() throws Exception {
    long antes = listar().get("totalTokens").asLong();

    criarMissao("EM_ANDAMENTO", 25, 60);
    criarMissao("AGUARDANDO_CONFIRMACAO", 30, 90);
    criarMissao("ABERTA", 99, 60); // não conta: está esperando, não parada

    assertThat(listar().get("totalTokens").asLong() - antes).isEqualTo(55);

    // Página de um item: o total continua sendo o do conjunto inteiro.
    JsonNode umPorPagina = JSON.readTree(chamar(admin, "ADMIN", "?tamanho=1"));
    assertThat(umPorPagina.get("missoes").get("conteudo").size()).isEqualTo(1);
    assertThat(umPorPagina.get("totalTokens").asLong() - antes).isEqualTo(55);
    assertThat(umPorPagina.get("missoes").get("totalElementos").asLong()).isGreaterThanOrEqualTo(2);
  }

  @Test
  @DisplayName("usuário comum recebe 403")
  void usuarioComumEh403() throws Exception {
    mockMvc
        .perform(get(URL).header("Authorization", bearer(usuario, "USUARIO")))
        .andExpect(status().isForbidden());
  }

  @Test
  @DisplayName("sem token recebe 401")
  void anonimoEh401() throws Exception {
    mockMvc.perform(get(URL)).andExpect(status().isUnauthorized());
  }

  @Test
  @DisplayName("tamanho acima do teto e página negativa são 400")
  void paginacaoInvalidaEh400() throws Exception {
    mockMvc
        .perform(get(URL + "?tamanho=101").header("Authorization", bearer(admin, "ADMIN")))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.type").exists());
    mockMvc
        .perform(get(URL + "?pagina=-1").header("Authorization", bearer(admin, "ADMIN")))
        .andExpect(status().isBadRequest());
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────────────────────

  private JsonNode listar() throws Exception {
    return JSON.readTree(chamar(admin, "ADMIN", "?tamanho=100"));
  }

  private String chamar(UUID quem, String papel, String query) throws Exception {
    return mockMvc
        .perform(get(URL + query).header("Authorization", bearer(quem, papel)))
        .andExpect(status().isOk())
        .andReturn()
        .getResponse()
        .getContentAsString(java.nio.charset.StandardCharsets.UTF_8);
  }

  /** Índice da missão na lista, ou -1 se não está nela. */
  private static int posicaoDe(JsonNode conteudo, UUID missaoId) {
    for (int i = 0; i < conteudo.size(); i++) {
      if (missaoId.toString().equals(conteudo.get(i).get("missaoId").asString())) {
        return i;
      }
    }
    return -1;
  }

  private String bearer(UUID usuarioId, String papel) {
    return "Bearer " + JwtTestConfig.gerarTokenValido(usuarioId, usuarioId + "@teste.dev", papel);
  }

  private UUID criarUsuario(String prefixo, String papel) {
    UUID id = UUID.randomUUID();
    jdbcTemplate.update(
        """
        INSERT INTO usuario (id, nome, email, senha_hash, handle, tribo_id, xp, nivel, streak,
                             rating, papel, status, criado_em, atualizado_em, versao)
        VALUES (?, ?, ?, '{bcrypt}$2a$10$naoUsadoNesteTeste', ?, ?, 0, 1, 0, 0.0,
                ?, 'ATIVO', NOW(), NOW(), 0)
        """,
        id,
        prefixo,
        prefixo + "-" + id + "@teste.dev",
        prefixo.charAt(0) + id.toString().substring(0, 10),
        tribo,
        papel);
    return id;
  }

  /**
   * Missão gravada direto no estado pedido.
   *
   * <p>INSERT em vez de percorrer o ciclo pela API: o que este teste mede é o RECORTE da consulta,
   * e chegar a EM_DISPUTA pela API exigiria aceite, início, check-in e contestação — seis chamadas
   * por missão para testar um {@code WHERE}. O pote entra sem lançamento de financiamento por trás
   * pelo mesmo motivo; a conservação não está em avaliação aqui, e a missão é apagada no fim.
   */
  private UUID criarMissao(String status, long pote, int horasNoEstado) {
    UUID id = UUID.randomUUID();
    jdbcTemplate.update(
        """
        INSERT INTO missao (id, criador_id, executor_id, categoria, titulo, descricao, status,
                            xp_recompensa, valor_brl, tokens_recompensa, origem, cep, logradouro,
                            bairro, cidade, uf, raio_checkin_m, janela_inicio, janela_fim,
                            criada_em, pote_tokens, estado_desde, fonte_pote, versao)
        VALUES (?, ?, ?, 'TRIBO', ?, 'Missão de teste de pote imobilizado.', ?,
                30, 0.00, 10,
                ST_SetSRID(ST_MakePoint(-46.6996, -23.5629), 4326)::geography,
                '05422030', 'Rua dos Pinheiros', 'Pinheiros', 'São Paulo', 'SP', 50,
                NOW() - INTERVAL '20 days', NOW() + INTERVAL '20 days', NOW() - INTERVAL '20 days',
                ?, NOW() - (? * INTERVAL '1 hour'), 'COMUNIDADE', 0)
        """,
        id,
        admin,
        usuario,
        "Parada " + status + " " + id.toString().substring(0, 8),
        status,
        pote,
        horasNoEstado);
    missoes.add(id);
    return id;
  }
}
