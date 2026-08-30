package com.omnitribo.compartilhado.api;

import edu.umd.cs.findbugs.annotations.SuppressFBWarnings;
import org.flywaydb.core.Flyway;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.core.env.Environment;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

/**
 * Página única de status, renderizada no SERVIDOR com Spring MVC + Thymeleaf.
 *
 * <h2>Por que esta página existe, e por que ela não cresce</h2>
 *
 * <p><b>Ela existe para demonstrar Spring MVC com renderização no servidor — Parte 2 do enunciado —
 * e nada mais.</b> A interface administrativa deste projeto é o dashboard Angular em {@code
 * apps/dashboard}, que consome a API REST: é lá que ficam listagem, cadastro de ponto de custódia e
 * indicadores de impacto. Nada de administração deve ser acrescentado aqui.
 *
 * <p>Consequência prática para quem for mexer: se você veio adicionar um formulário, um menu ou uma
 * segunda página, o lugar é o dashboard. Duas interfaces administrativas para o mesmo sistema
 * divergem — e a que tiver menos uso é a que vai ficar mentindo primeiro.
 *
 * <h2>Três decisões que parecem arbitrárias e não são</h2>
 *
 * <p><b>1. A contagem de migrations vem da API do Flyway, não de um {@code SELECT} na {@code
 * flyway_schema_history}.</b> A aplicação conecta como {@code omnitribo_app}, que <b>não tem
 * permissão de leitura naquela tabela</b> — {@code permission denied for table
 * flyway_schema_history}, verificado. O Flyway tem datasource próprio, com credencial própria, e é
 * ele quem consegue ler o histórico. A alternativa seria conceder {@code SELECT} ao usuário da
 * aplicação, o que afrouxaria o isolamento que a verificação de 2026-08-11 introduziu de propósito.
 *
 * <p><b>2. A página não tem CSS.</b> A CSP da cadeia principal é {@code default-src 'none'}, que é
 * a política certa para uma API que só devolve JSON. {@code style-src} recai sobre ela, então um
 * bloco {@code <style>} seria recusado pelo browser e a página chegaria com 200 e sem estilo —
 * sintoma que só aparece no console do DevTools. Foi o mesmo problema que obrigou o Swagger UI a
 * ter cadeia própria. Uma página de status não vale uma exceção de CSP, então ela usa HTML
 * semântico e o estilo default do browser.
 *
 * <p><b>3. {@code @Profile("!prod")}.</b> A página anuncia perfil ativo e versão sem exigir
 * autenticação — em produção isso é reconhecimento de graça para quem estiver sondando, e ela não
 * serve a nenhum operador, já que {@code /actuator/health} responde essa pergunta melhor. Mesma
 * política do springdoc, que {@code application-prod.yml} desliga.
 */
@Controller
@Profile("!prod")
public class StatusController {

  private static final Logger log = LoggerFactory.getLogger(StatusController.class);

  private final Environment ambiente;
  private final JdbcTemplate jdbcTemplate;
  private final Flyway flyway;

  @Value("${app.info.nome}")
  private String nome;

  @Value("${app.info.versao}")
  private String versao;

  // EI_EXPOSE_REP2: JdbcTemplate e Flyway são singletons do container — injetados, não passados
  // por um chamador que possa mutá-los depois. Mesmo caso e mesma justificativa do RateLimitFilter
  // em SecurityConfig. Cópia defensiva de um bean Spring não faria sentido: quebraria a injeção.
  @SuppressFBWarnings("EI_EXPOSE_REP2")
  public StatusController(Environment ambiente, JdbcTemplate jdbcTemplate, Flyway flyway) {
    this.ambiente = ambiente;
    this.jdbcTemplate = jdbcTemplate;
    this.flyway = flyway;
  }

  @GetMapping("/status")
  public String status(Model model) {
    model.addAttribute("nome", nome);
    model.addAttribute("versao", versao);

    String[] ativos = ambiente.getActiveProfiles();
    model.addAttribute("perfil", ativos.length == 0 ? "default" : String.join(", ", ativos));

    boolean bancoOk = bancoRespondendo();
    model.addAttribute("bancoOk", bancoOk);
    // A contagem só faz sentido se o banco respondeu; -1 sinaliza "não apurado" e o template o
    // traduz, em vez de exibir 0 — que seria indistinguível de "nenhuma migration aplicada".
    model.addAttribute("migracoes", bancoOk ? migracoesAplicadas() : -1);

    return "status";
  }

  /** Sonda o banco pela conexão que a APLICAÇÃO usa — é essa que importa para quem lê a página. */
  private boolean bancoRespondendo() {
    try {
      jdbcTemplate.queryForObject("SELECT 1", Integer.class);
      return true;
    } catch (org.springframework.dao.DataAccessException e) {
      // warn e não error: banco fora do ar é o fato que a página existe para mostrar, não um
      // incidente da página. Registrar como error fabricaria alarme sobre uma leitura de status.
      log.warn("Banco não respondeu à sonda de /status", e);
      return false;
    }
  }

  private int migracoesAplicadas() {
    try {
      return flyway.info().applied().length;
    } catch (RuntimeException e) {
      log.warn("Não foi possível ler o histórico de migrations", e);
      return -1;
    }
  }
}
