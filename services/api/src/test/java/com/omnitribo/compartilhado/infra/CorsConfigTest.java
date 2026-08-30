package com.omnitribo.compartilhado.infra;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.options;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.omnitribo.TesteIntegracaoMvcBase;
import org.hamcrest.Matchers;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.test.web.servlet.MockMvc;

/**
 * Contrato de CORS: o que o browser precisa ver no preflight, e o que ele NÃO pode ver quando a
 * origem não está na lista.
 *
 * <p><b>Por que MockMvc e não TestRestTemplate.</b> O que está sob teste são cabeçalhos de resposta
 * e o status de uma requisição que nunca chega a controller nenhum — o {@code CorsFilter} do Spring
 * Security resolve o preflight e devolve. {@code TesteIntegracaoMvcBase} existe exatamente para
 * inspecionar header, e a configuração de CORS entra pela cadeia de segurança ({@code
 * SecurityConfig.filterChain} → {@code .cors(...)}), que é a cadeia que o MockMvc monta. Um filtro
 * auto-registrado por {@code @Component} não estaria aqui; este não é um deles.
 *
 * <p><b>Por que o preflight não leva JWT.</b> O browser manda o OPTIONS de propósito sem {@code
 * Authorization} — a especificação de Fetch proíbe credencial no preflight. Se este teste passasse
 * um token, ele estaria medindo um fluxo que nenhum browser executa, e a regressão que ele existe
 * para pegar (preflight caindo em 401 antes do CorsFilter) ficaria invisível.
 *
 * <p>As origens vêm de {@code application-test.yml} — {@code http://localhost:4200} e {@code
 * http://localhost:8081}. Nada aqui depende de valor escrito em classe.
 */
class CorsConfigTest extends TesteIntegracaoMvcBase {

  private static final String ORIGEM_PERMITIDA = "http://localhost:4200";
  private static final String ORIGEM_ESTRANHA = "https://atacante.example.com";

  /** Rota autenticada de propósito: é a que o dashboard chama, e é a que provaria o 401. */
  private static final String ROTA = "/api/v1/missoes";

  @Autowired MockMvc mockMvc;

  @Test
  void preflight_de_origem_permitida_responde_com_os_cabecalhos_que_o_browser_exige()
      throws Exception {
    mockMvc
        .perform(
            options(ROTA)
                .header("Origin", ORIGEM_PERMITIDA)
                .header("Access-Control-Request-Method", "GET")
                .header("Access-Control-Request-Headers", "Authorization"))
        // 200 e NÃO 401: o preflight é resolvido pelo CorsFilter antes de qualquer autenticação.
        // Se um dia ele passar a exigir token, este assert quebra — e quebra antes do dashboard.
        .andExpect(status().isOk())
        .andExpect(header().string("Access-Control-Allow-Origin", ORIGEM_PERMITIDA))
        .andExpect(header().string("Access-Control-Allow-Methods", Matchers.containsString("GET")))
        .andExpect(
            header()
                .string("Access-Control-Allow-Headers", Matchers.containsString("Authorization")))
        // Sem credencial: a API é Bearer, não cookie. Um `true` aqui, combinado com uma origem
        // refletida, é a receita clássica de vazamento de sessão — por isso é assertion, não
        // comentário.
        .andExpect(header().doesNotExist("Access-Control-Allow-Credentials"));
  }

  /**
   * O header que o dashboard precisa para POSTar, e cuja ausência era invisível: sem ele o browser
   * reprova o preflight e a requisição real nunca sai, sem status nem log do lado do servidor.
   */
  @Test
  void preflight_permite_o_header_de_idempotencia_exigido_pelos_posts_de_valor() throws Exception {
    mockMvc
        .perform(
            options("/api/v1/carteira/transferencias")
                .header("Origin", ORIGEM_PERMITIDA)
                .header("Access-Control-Request-Method", "POST")
                .header("Access-Control-Request-Headers", "Authorization, Idempotency-Key"))
        .andExpect(status().isOk())
        .andExpect(
            header()
                .string(
                    "Access-Control-Allow-Headers", Matchers.containsString("Idempotency-Key")));
  }

  @Test
  void preflight_de_origem_nao_permitida_e_recusado_e_nao_devolve_allow_origin() throws Exception {
    mockMvc
        .perform(
            options(ROTA)
                .header("Origin", ORIGEM_ESTRANHA)
                .header("Access-Control-Request-Method", "GET"))
        .andExpect(status().isForbidden())
        // O assert que importa: sem este header o browser bloqueia a leitura da resposta. Afirmar
        // só o status deixaria passar uma configuração que recusa E ecoa a origem.
        .andExpect(header().doesNotExist("Access-Control-Allow-Origin"));
  }

  /**
   * A requisição SIMPLES também é barrada, não só o preflight.
   *
   * <p>Vale um teste próprio porque são caminhos diferentes no {@code CorsFilter}: um {@code GET}
   * cross-origin sem header customizado não gera preflight nenhum, e uma configuração que só
   * tratasse OPTIONS deixaria a resposta sair com corpo e sem {@code Allow-Origin} — o servidor
   * teria executado a consulta para uma origem estranha, e só o browser estaria descartando o
   * resultado.
   */
  @Test
  void requisicao_simples_de_origem_nao_permitida_tambem_e_recusada() throws Exception {
    mockMvc
        .perform(get(ROTA).header("Origin", ORIGEM_ESTRANHA))
        .andExpect(status().isForbidden())
        .andExpect(header().doesNotExist("Access-Control-Allow-Origin"));
  }
}
