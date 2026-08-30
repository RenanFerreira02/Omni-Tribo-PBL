package com.omnitribo.notificacoes.dominio;

import com.omnitribo.compartilhado.api.ConsultasGeoespaciais;
import com.omnitribo.identidade.api.ConsultaConsentimento;
import com.omnitribo.identidade.api.ProgressaoUsuario;
import com.omnitribo.notificacoes.api.DespachoAlerta;
import com.omnitribo.notificacoes.infra.AlertaRepository;
import java.math.BigDecimal;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import tools.jackson.databind.json.JsonMapper;

/**
 * Entrega de eventos da outbox como alerta in-app. Implementação da porta {@link DespachoAlerta}.
 *
 * <p>Destino provisório e assumido como tal: nesta fase "despachar" significa gravar uma linha em
 * {@code alerta}, a caixa de entrada do app. O push real trocaria só o corpo deste despachante — o
 * contrato do drenador e o backoff não mudam, porque é exatamente essa separação que o padrão
 * outbox compra. O que NÃO se deve repetir daqui é a palavra "at-least-once": a entrega para na
 * quinta tentativa e o evento é abandonado sem aviso. Ver o javadoc de {@link
 * com.omnitribo.compartilhado.api.PublicadorEventos}, seção "O LIMITE desta garantia".
 *
 * <p>O mapper é construído aqui, sem injeção: Jackson é o 3 (tools.jackson) em todo o repositório e
 * não existe bean de ObjectMapper para injetar. Mesmo padrão de {@code
 * MissaoService.MAPPER_TRILHA}.
 */
@Service
public class DespachanteAlertaService implements DespachoAlerta {

  private static final JsonMapper MAPPER = JsonMapper.builder().build();

  private static final Logger log = LoggerFactory.getLogger(DespachanteAlertaService.class);

  /** Discriminador do alerta de missão nova publicada perto de você. */
  static final String TIPO_MISSAO_PROXIMA = "MISSAO_PROXIMA";

  private final AlertaRepository alertaRepository;
  private final ConsultasGeoespaciais consultasGeoespaciais;
  private final ConsultaConsentimento consultaConsentimento;
  private final ProgressaoUsuario progressaoUsuario;
  private final ParametrosNotificacoes parametros;

  public DespachanteAlertaService(
      AlertaRepository alertaRepository,
      // Pela INTERFACE: as três são portas de outros módulos, e é o tipo declarado aqui que o
      // ArchUnit inspeciona.
      ConsultasGeoespaciais consultasGeoespaciais,
      ConsultaConsentimento consultaConsentimento,
      ProgressaoUsuario progressaoUsuario,
      ParametrosNotificacoes parametros) {
    this.alertaRepository = alertaRepository;
    this.consultasGeoespaciais = consultasGeoespaciais;
    this.consultaConsentimento = consultaConsentimento;
    this.progressaoUsuario = progressaoUsuario;
    this.parametros = parametros;
  }

  /**
   * Traduz um evento em alerta. Tipo desconhecido lança, e isso é intencional: o evento volta para
   * a outbox com backoff em vez de ser descartado, e {@code ultimo_erro} registra o que faltou.
   * Descartar em silêncio perderia um fato que o resto do sistema já considera consumado.
   */
  @Override
  public void despachar(String tipoEvento, UUID agregadoId, String payloadJson) {
    @SuppressWarnings("unchecked")
    Map<String, Object> payload = MAPPER.readValue(payloadJson, Map.class);

    switch (tipoEvento) {
      case "MissaoConcluida" -> gravarConclusao(agregadoId, payload);
      case "MissaoPublicada" -> anunciarMissaoNova(payload);
      default ->
          throw new IllegalStateException("Nenhum despachante para o evento " + tipoEvento + ".");
    }
  }

  private void gravarConclusao(UUID missaoId, Map<String, Object> payload) {
    UUID executorId = UUID.fromString((String) payload.get("executorId"));
    boolean subiuDeNivel = Boolean.TRUE.equals(payload.get("subiuDeNivel"));

    String corpo =
        subiuDeNivel
            ? "Missão concluída e recompensa creditada. Você subiu para o nível "
                + payload.get("nivelAtual")
                + "."
            : "Missão concluída. A recompensa já está na sua carteira.";

    alertaRepository.save(
        new Alerta(
            UUID.randomUUID(),
            executorId,
            "MISSAO_CONCLUIDA",
            "Recompensa creditada",
            corpo,
            missaoId,
            Instant.now()));
  }

  /**
   * Fan-out geográfico: avisa quem está perto que há uma missão nova no bairro.
   *
   * <p><b>O gatilho mudou na V28</b> (ADR 0031). Este fan-out era disparado pela conversão de uma
   * entrega falida — o único evento que o alcançava —, e com a extensão logística removida ele
   * passou a ouvir {@code MissaoPublicada}: agora TODA missão publicada anuncia o bairro, que é o
   * comportamento que o produto social sempre descreveu. Os três filtros abaixo não mudaram.
   *
   * <p><b>Quem é "perto" sem que o usuário tenha coordenada.</b> A tabela {@code usuario} não tem
   * coluna geográfica. O raio é medido do ponto de custódia até o CENTRO DERIVADO de cada tribo, e
   * notifica os membros dela — granularidade de bairro, não de pessoa. É a decisão do ADR 0020, não
   * uma limitação a corrigir: notificar por tribo não exige armazenar onde ninguém está.
   *
   * <p><b>Três filtros, e cada um recusa por um motivo diferente.</b> Consentimento é permissão;
   * nível mínimo é a Regra de Elegibilidade por Reputação do challenge — não adianta anunciar uma
   * missão que a pessoa levaria 422 ao tentar aceitar; teto por hora é respeito ao canal.
   */
  private void anunciarMissaoNova(Map<String, Object> payload) {
    UUID missaoId = UUID.fromString((String) payload.get("missaoId"));
    BigDecimal lat = new BigDecimal(String.valueOf(payload.get("lat")));
    BigDecimal lon = new BigDecimal(String.valueOf(payload.get("lon")));
    // Vem do payload, e não de uma consulta a `missoes`: a outbox existe justamente para o
    // despachante não depender do módulo que publicou o fato.
    String titulo = String.valueOf(payload.getOrDefault("titulo", "Missão nova"));
    long tokens = ((Number) payload.getOrDefault("tokensRecompensa", 0)).longValue();

    List<UUID> tribos =
        consultasGeoespaciais
            .tribosNoRaio(lat, lon, parametros.raioAlertaMetros(), parametros.tribosPorEvento())
            .stream()
            .map(ConsultasGeoespaciais.AlvoProximo::id)
            .toList();

    if (tribos.isEmpty()) {
      // Nenhuma tribo com centro derivado no raio. Acontece de verdade — tribo sem missão nem ponto
      // não tem centro —, e não é erro: lançar devolveria o evento à outbox para tentar de novo, e
      // as cinco tentativas fracassariam igual.
      log.debug("Missão {} sem tribo no raio de {} m", missaoId, parametros.raioAlertaMetros());
      return;
    }

    // Os DOIS consentimentos: NOTIFICACAO porque é uma notificação, LOCALIZACAO porque a decisão de
    // enviar usou a posição da tribo da pessoa. Exigir só o primeiro trataria a inferência
    // geográfica como se não fosse uso de dado de localização.
    List<UUID> comConsentimento =
        consultaConsentimento.usuariosComConsentimento(
            tribos, List.of(ConsultaConsentimento.NOTIFICACAO, ConsultaConsentimento.LOCALIZACAO));

    // Segundo filtro: reputação. Anunciar a missão a quem não alcança o nível mínimo seria prometer
    // o que o servidor recusa com 422 no toque seguinte. Hoje nenhuma missão exige nível — o único
    // caminho que gravava nivel_minimo > 1 saiu na V28 —, então o filtro passa todo mundo; ele
    // continua aqui porque é o par do gate em MissaoService.validarNivelParaAceitar, e os dois
    // precisam sair ou entrar juntos.
    int nivelMinimo = ((Number) payload.getOrDefault("nivelMinimo", 1)).intValue();
    List<UUID> destinatarios =
        progressaoUsuario.filtrarPorNivelMinimo(comConsentimento, nivelMinimo);

    Instant agora = Instant.now();
    Instant umaHoraAtras = agora.minus(Duration.ofHours(1));
    int enviados = 0;

    for (UUID destinatario : destinatarios) {
      // Deduplicação antes do teto, e não depois: um redespacho da outbox não pode consumir a cota
      // de quem já foi avisado, senão uma falha transitória de infraestrutura silencia
      // notificações legítimas pela hora seguinte.
      if (alertaRepository.existsByUsuarioIdAndTipoAndMissaoId(
          destinatario, TIPO_MISSAO_PROXIMA, missaoId)) {
        continue;
      }
      // Teto por hora. Existia um carve-out para risco ALTO, e ele saiu com o modelo que produzia a
      // faixa (V28): sem produtor de PRIORIDADE_ALTA, o teto próprio seria um caminho que nenhum
      // alerta percorre. A coluna alerta.prioridade fica, e todo alerta nasce NORMAL.
      if (alertaRepository.countByUsuarioIdAndCriadoEmAfter(destinatario, umaHoraAtras)
          >= parametros.alertasPorHora()) {
        continue;
      }

      alertaRepository.save(
          new Alerta(
              UUID.randomUUID(),
              destinatario,
              TIPO_MISSAO_PROXIMA,
              "Missão nova pertinho de você",
              titulo + " — receba " + tokens + " tokens mais XP ao concluir.",
              missaoId,
              agora,
              Alerta.PRIORIDADE_NORMAL));
      enviados++;
    }

    log.info(
        "Missão {}: {} alertas enviados de {} candidatos em {} tribos",
        missaoId,
        enviados,
        destinatarios.size(),
        tribos.size());
  }
}
