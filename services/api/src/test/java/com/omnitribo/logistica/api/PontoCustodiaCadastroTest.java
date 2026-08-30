package com.omnitribo.logistica.api;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.omnitribo.JwtTestConfig;
import com.omnitribo.TesteIntegracaoMvcBase;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;

/**
 * Cadastro de ponto de custódia — o primeiro caminho de ESCRITA do recurso.
 *
 * <p>Até esta fase um ponto só nascia por migration de seed. O que estes testes protegem não é o
 * caminho feliz: é o conjunto de coisas que o cliente NÃO pode fazer por aqui — mexer em {@code
 * ocupacao}, repetir um código, apontar para uma tribo inexistente ou cadastrar sem ser ADMIN.
 */
@Import(JwtTestConfig.class)
@DisplayName("Cadastro de ponto de custódia (ADMIN)")
class PontoCustodiaCadastroTest extends TesteIntegracaoMvcBase {

  private static final UUID ADMIN = UUID.fromString("bbbbbbbb-0000-0000-0000-000000000001");
  private static final UUID ALICE = UUID.fromString("bbbbbbbb-0000-0000-0000-000000000002");

  private static final String BASE = "/api/v1/pontos-custodia";

  /** Prefixo exclusivo destes testes, para a limpeza não tocar em ponto de seed. */
  private static final String PREFIXO = "TST-CAD-";

  @Autowired MockMvc mockMvc;
  @Autowired JdbcTemplate jdbcTemplate;

  @AfterEach
  void limparPontosDoTeste() {
    jdbcTemplate.update("DELETE FROM ponto_custodia WHERE codigo LIKE ?", PREFIXO + "%");
  }

  private static String bearer(UUID usuario, String papel) {
    return "Bearer " + JwtTestConfig.gerarTokenValido(usuario, usuario + "@omnitribo.dev", papel);
  }

  private static String corpo(Map<String, Object> campos) {
    return JSON.writeValueAsString(campos);
  }

  private static Map<String, Object> valido(String codigo) {
    return Map.of(
        "codigo", codigo,
        "tipo", "LOJA",
        "apelido", "Depósito de teste",
        "lat", "-23.5640",
        "lon", "-46.6934",
        "capacidade", 25);
  }

  @Test
  void admin_cadastra_e_o_ponto_nasce_vazio_e_ativo() throws Exception {
    mockMvc
        .perform(
            post(BASE)
                .header("Authorization", bearer(ADMIN, "ADMIN"))
                .contentType(MediaType.APPLICATION_JSON)
                .content(corpo(valido(PREFIXO + "001"))))
        .andExpect(status().isCreated())
        .andExpect(jsonPath("$.codigo").value(PREFIXO + "001"))
        .andExpect(jsonPath("$.apelido").value("Depósito de teste"))
        .andExpect(jsonPath("$.tipo").value("LOJA"))
        .andExpect(jsonPath("$.capacidade").value(25))
        // As duas assertions que importam: o ponto nasce VAZIO e a distância é nula, porque num
        // cadastro não existe coordenada de referência contra a qual medir.
        .andExpect(jsonPath("$.ocupacao").value(0))
        .andExpect(jsonPath("$.distanciaM").doesNotExist());

    Map<String, Object> gravado =
        jdbcTemplate.queryForMap(
            "SELECT ocupacao, ativo, ST_Y(ponto::geometry) AS lat, ST_X(ponto::geometry) AS lon"
                + " FROM ponto_custodia WHERE codigo = ?",
            PREFIXO + "001");
    assertThat(gravado.get("ocupacao")).isEqualTo(0);
    assertThat(gravado.get("ativo")).isEqualTo(true);
    // lon = X e lat = Y: trocar a ordem é o erro clássico de PostGIS e põe o ponto no oceano.
    assertThat((Double) gravado.get("lat"))
        .isCloseTo(-23.5640, org.assertj.core.data.Offset.offset(1e-6));
    assertThat((Double) gravado.get("lon"))
        .isCloseTo(-46.6934, org.assertj.core.data.Offset.offset(1e-6));
  }

  @Test
  void ocupacao_enviada_pelo_cliente_e_ignorada_e_nao_vira_400() throws Exception {
    // `fail-on-unknown-properties: false` é decisão de segurança do projeto: campo que o DTO não
    // declara é silenciosamente descartado. É a proteção contra mass assignment, e este teste é o
    // que impede alguém de "endurecer" isso para 400 e, no caminho, aceitar o campo.
    Map<String, Object> comOcupacao =
        Map.of(
            "codigo",
            PREFIXO + "002",
            "tipo",
            "LOCKER",
            "apelido",
            "Locker de teste",
            "lat",
            "-23.5640",
            "lon",
            "-46.6934",
            "capacidade",
            10,
            "ocupacao",
            9999,
            "ativo",
            false);

    mockMvc
        .perform(
            post(BASE)
                .header("Authorization", bearer(ADMIN, "ADMIN"))
                .contentType(MediaType.APPLICATION_JSON)
                .content(corpo(comOcupacao)))
        .andExpect(status().isCreated())
        .andExpect(jsonPath("$.ocupacao").value(0));

    Integer ocupacao =
        jdbcTemplate.queryForObject(
            "SELECT ocupacao FROM ponto_custodia WHERE codigo = ?", Integer.class, PREFIXO + "002");
    assertThat(ocupacao).isZero();
  }

  @Test
  void codigo_repetido_responde_422_e_nao_500_da_unique() throws Exception {
    mockMvc
        .perform(
            post(BASE)
                .header("Authorization", bearer(ADMIN, "ADMIN"))
                .contentType(MediaType.APPLICATION_JSON)
                .content(corpo(valido(PREFIXO + "003"))))
        .andExpect(status().isCreated());

    mockMvc
        .perform(
            post(BASE)
                .header("Authorization", bearer(ADMIN, "ADMIN"))
                .contentType(MediaType.APPLICATION_JSON)
                .content(corpo(valido(PREFIXO + "003"))))
        // 422 e não 409: o dado não satisfaz, e a tela corrige o campo em vez de recarregar.
        .andExpect(status().isUnprocessableEntity())
        .andExpect(
            jsonPath("$.type").value("https://omnitribo.dev/problemas/regra-negocio-violada"))
        .andExpect(jsonPath("$.traceId").exists());
  }

  @Test
  void tribo_inexistente_responde_422_e_nao_500_da_foreign_key() throws Exception {
    Map<String, Object> comTriboFantasma =
        Map.of(
            "codigo", PREFIXO + "004",
            "tipo", "PORTARIA",
            "apelido", "Portaria de teste",
            "lat", "-23.5640",
            "lon", "-46.6934",
            "capacidade", 5,
            "triboId", UUID.randomUUID().toString());

    mockMvc
        .perform(
            post(BASE)
                .header("Authorization", bearer(ADMIN, "ADMIN"))
                .contentType(MediaType.APPLICATION_JSON)
                .content(corpo(comTriboFantasma)))
        .andExpect(status().isUnprocessableEntity())
        .andExpect(
            jsonPath("$.type").value("https://omnitribo.dev/problemas/regra-negocio-violada"));

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT count(*) FROM ponto_custodia WHERE codigo = ?",
                Integer.class,
                PREFIXO + "004"))
        .isZero();
  }

  @Test
  void usuario_comum_recebe_403_e_nada_e_gravado() throws Exception {
    mockMvc
        .perform(
            post(BASE)
                .header("Authorization", bearer(ALICE, "USUARIO"))
                .contentType(MediaType.APPLICATION_JSON)
                .content(corpo(valido(PREFIXO + "005"))))
        .andExpect(status().isForbidden())
        .andExpect(jsonPath("$.type").value("https://omnitribo.dev/problemas/acesso-negado"));

    assertThat(
            jdbcTemplate.queryForObject(
                "SELECT count(*) FROM ponto_custodia WHERE codigo = ?",
                Integer.class,
                PREFIXO + "005"))
        .isZero();
  }

  @Test
  void anonimo_recebe_401() throws Exception {
    mockMvc
        .perform(
            post(BASE)
                .contentType(MediaType.APPLICATION_JSON)
                .content(corpo(valido(PREFIXO + "006"))))
        .andExpect(status().isUnauthorized());
  }

  @Test
  void campos_invalidos_respondem_400_com_o_campo_apontado() throws Exception {
    Map<String, Object> ruim =
        Map.of(
            "codigo", "minusculo com espaço",
            "tipo", "LOJA",
            "apelido", "",
            "lat", "-999",
            "lon", "-46.6934",
            "capacidade", 0);

    mockMvc
        .perform(
            post(BASE)
                .header("Authorization", bearer(ADMIN, "ADMIN"))
                .contentType(MediaType.APPLICATION_JSON)
                .content(corpo(ruim)))
        .andExpect(status().isBadRequest())
        .andExpect(jsonPath("$.type").value("https://omnitribo.dev/problemas/requisicao-invalida"))
        // `errors` é o que permite a tela marcar o campo — sem ele o formulário só teria uma frase.
        .andExpect(jsonPath("$.errors").isArray())
        .andExpect(jsonPath("$.errors[?(@.campo == 'codigo')]").exists())
        .andExpect(jsonPath("$.errors[?(@.campo == 'apelido')]").exists())
        .andExpect(jsonPath("$.errors[?(@.campo == 'lat')]").exists())
        .andExpect(jsonPath("$.errors[?(@.campo == 'capacidade')]").exists());
  }
}
