package com.omnitribo.identidade.dominio;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.Locale;
import java.util.UUID;

/**
 * O apoiador do bairro: o titular de carteira que recebe aporte de token e financia o pote de
 * missões comunitárias.
 *
 * <p>Até a V28 esta linha era a relação comercial com uma TRANSPORTADORA, e o slug casava com o
 * cabeçalho {@code X-Transportadora} do webhook de entrega falida. O webhook saiu (ADR 0031); a
 * tabela ficou, porque o aporte que ela sustenta é o ÚNICO ponto de emissão de token do sistema —
 * sem ele a economia teria só o sumidouro do resgate e a soma cairia até zero.
 *
 * <p>Vive em {@code identidade} porque é uma extensão de {@code usuario}, tabela que este módulo
 * possui. O {@code slug} continua sendo chave de negócio e continua UNIQUE: é por ele que se
 * reconhece o mesmo apoiador entre cadastros, e duas linhas com o mesmo slug tornariam a resolução
 * não determinística.
 */
@Entity
@Table(name = "patrocinador")
public class Patrocinador {

  @Id
  @Column(updatable = false, nullable = false)
  private UUID id;

  @Column(name = "usuario_id", nullable = false, updatable = false, unique = true)
  private UUID usuarioId;

  @Column(name = "slug", nullable = false, updatable = false, length = 50)
  private String slug;

  @Column(nullable = false, length = 100)
  private String nome;

  @Column(nullable = false)
  private boolean ativo;

  @Column(name = "criado_em", nullable = false, updatable = false)
  private Instant criadoEm;

  protected Patrocinador() {}

  public Patrocinador(UUID id, UUID usuarioId, String slug, String nome, Instant criadoEm) {
    this.id = id;
    this.usuarioId = usuarioId;
    // Normalizado na ENTRADA, num ponto só: a UNIQUE do banco é sensível a caixa, e "Apoiador-Dev"
    // criaria um segundo apoiador para o mesmo bairro sem que a constraint reclamasse.
    this.slug = slug.toLowerCase(Locale.ROOT);
    this.nome = nome;
    this.ativo = true;
    this.criadoEm = criadoEm;
  }

  /**
   * Encerra o patrocínio sem apagar a linha.
   *
   * <p>Os lançamentos deste apoiador continuam no ledger apontando para a carteira dele; apagar a
   * relação deixaria o extrato sem explicação. Inativo deixa de receber aporte e volta a ser um
   * titular comum para o financiamento — que, sem tribo, é o mesmo que não poder financiar.
   */
  public void desativar() {
    this.ativo = false;
  }

  public void reativar() {
    this.ativo = true;
  }

  public UUID getId() {
    return id;
  }

  public UUID getUsuarioId() {
    return usuarioId;
  }

  public String getSlug() {
    return slug;
  }

  public String getNome() {
    return nome;
  }

  public boolean isAtivo() {
    return ativo;
  }

  public Instant getCriadoEm() {
    return criadoEm;
  }
}
