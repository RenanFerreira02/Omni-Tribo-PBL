package com.omnitribo.compartilhado.api;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.model;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.view;

import com.omnitribo.JwtTestConfig;
import com.omnitribo.TesteIntegracaoMvcBase;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Import;
import org.springframework.test.web.servlet.MockMvc;

/**
 * Página de status renderizada no servidor.
 *
 * <p>O teste afirma sobre o HTML RENDERIZADO, e não só sobre o model. Um template que não resolve —
 * nome de view errado, expressão Thymeleaf inválida, atributo ausente — passaria por uma assertion
 * de model e quebraria no browser. Renderizar é o que este teste existe para provar.
 */
/*
 * O @Import é de CACHE DE CONTEXTO, não de necessidade: esta página é anônima e não usa JWT nenhum.
 *
 * Ele está aqui porque a chave do cache de contexto do Spring inclui a lista de @Import, e uma
 * combinação inédita cria um contexto NOVO — com o HikariPool inteiro junto. O consumo da suíte é
 * (nº de contextos × 40) contra max_connections=500, mais os pools avulsos que os testes de
 * permissão abrem sem fechar; medido, a suíte já roda com 18 pools. Sem este import a classe ficava
 * sozinha numa chave própria, o total passava de 500, e quem quebrava era MigracaoTest — com
 * SQLSTATE 53300 (too_many_connections) no lugar do 42501 que ele espera. O sintoma acusa o teste
 * ERRADO e não menciona conexão nenhuma.
 *
 * Ou seja: não remova este import por estar "sem uso". Ver ContainerConfig.
 */
@Import(JwtTestConfig.class)
@DisplayName("Página de status (Thymeleaf)")
class StatusPaginaTest extends TesteIntegracaoMvcBase {

  @Autowired MockMvc mockMvc;

  @Test
  void responde_html_sem_autenticacao_e_resolve_o_template() throws Exception {
    mockMvc
        .perform(get("/status"))
        // Anônima de propósito: a API autentica por Bearer, e exigir JWT tornaria a página
        // inalcançável no browser. Se alguém remover o permitAll, este teste vira 401 e avisa.
        .andExpect(status().isOk())
        .andExpect(content().contentTypeCompatibleWith("text/html"))
        .andExpect(view().name("status"));
  }

  @Test
  void mostra_nome_versao_perfil_e_banco_conectado() throws Exception {
    mockMvc
        .perform(get("/status"))
        .andExpect(status().isOk())
        .andExpect(content().string(org.hamcrest.Matchers.containsString("omnitribo-api")))
        // A versão vem do pom por filtragem de recurso do parent. Afirmar o número exato prenderia
        // o teste à versão; afirmar o rótulo e a ausência do token não substituído é o que importa:
        // se a filtragem parar de funcionar, "@project.version@" chega cru à página.
        .andExpect(content().string(org.hamcrest.Matchers.containsString("Versão")))
        .andExpect(
            content()
                .string(
                    org.hamcrest.Matchers.not(
                        org.hamcrest.Matchers.containsString("@project.version@"))))
        // O contexto de teste roda com o perfil `test` ativo.
        .andExpect(content().string(org.hamcrest.Matchers.containsString("test")))
        // Testcontainers está de pé durante a suíte, então a sonda tem de dizer conectado.
        .andExpect(content().string(org.hamcrest.Matchers.containsString("conectado")))
        .andExpect(model().attribute("bancoOk", true));
  }

  @Test
  void conta_as_migrations_aplicadas_pelo_flyway() throws Exception {
    mockMvc
        .perform(get("/status"))
        .andExpect(status().isOk())
        .andExpect(content().string(org.hamcrest.Matchers.containsString("Migrations aplicadas")))
        // Afirma sobre o VALOR RENDERIZADO, com regex, e não sobre a ausência da frase de
        // fallback. A primeira versão deste teste procurava a ausência de "não apurado" no corpo —
        // e
        // casava com um COMENTÁRIO HTML do template, não com o dado. Assertion que pode casar com a
        // explicação em vez do valor não mede nada, e passa a verde pelo motivo errado.
        //
        // O número exato cresce a cada migration nova, então o que se afirma é a FORMA: inteiro
        // positivo. É o bastante para reprovar o -1 que apareceria se a contagem viesse de um
        // SELECT
        // que `omnitribo_app` não tem permissão de fazer.
        .andExpect(
            content()
                .string(
                    org.hamcrest.Matchers.matchesPattern(
                        "(?s).*Migrations aplicadas</dt>\\s*<dd>[1-9][0-9]*</dd>.*")))
        .andExpect(
            model()
                .attribute(
                    "migracoes",
                    org.hamcrest.Matchers.allOf(
                        org.hamcrest.Matchers.instanceOf(Integer.class),
                        org.hamcrest.Matchers.greaterThan(0))));
  }

  /**
   * Nenhum fragmento de comentário do template pode chegar ao browser.
   *
   * <p>Existe porque aconteceu: um comentário de parser do Thymeleaf que continha os próprios
   * delimitadores de fechamento no meio do texto foi encerrado ali, e metade da explicação saiu
   * como conteúdo visível na página. Os dados estavam certos e a página estava suja — e os testes
   * anteriores, que afirmavam sobre a PRESENÇA de valores, passaram sem ver.
   */
  @Test
  void nao_vaza_comentario_do_template_para_a_saida() throws Exception {
    mockMvc
        .perform(get("/status"))
        .andExpect(status().isOk())
        .andExpect(
            content().string(org.hamcrest.Matchers.not(org.hamcrest.Matchers.containsString("*/"))))
        .andExpect(
            content()
                .string(org.hamcrest.Matchers.not(org.hamcrest.Matchers.containsString("<!--/"))));
    // Só os DELIMITADORES são procurados. Uma primeira versão deste teste também proibia a palavra
    // "Thymeleaf" no corpo — e reprovava por causa do rodapé, que diz "demonstração de Spring MVC +
    // Thymeleaf" de propósito. Assertion que proíbe conteúdo legítimo não detecta vazamento: só
    // impede a página de se explicar.
  }

  @Test
  void nao_expoe_formulario_nem_menu() throws Exception {
    // A página é demonstração e não deve virar segunda interface administrativa. Se alguém
    // acrescentar um <form> aqui, este teste reprova e obriga a decisão a ser consciente.
    mockMvc
        .perform(get("/status"))
        .andExpect(status().isOk())
        .andExpect(
            content()
                .string(org.hamcrest.Matchers.not(org.hamcrest.Matchers.containsString("<form"))))
        .andExpect(
            content()
                .string(org.hamcrest.Matchers.not(org.hamcrest.Matchers.containsString("<nav"))));
  }
}
