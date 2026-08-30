package com.omnitribo.identidade.infra;

import com.omnitribo.identidade.dominio.Patrocinador;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface PatrocinadorRepository extends JpaRepository<Patrocinador, UUID> {

  boolean existsBySlug(String slug);

  /**
   * Resolve o id da relação de apoio → {@code usuario_id} do titular, se o apoio estiver ATIVO.
   *
   * <p>Projeção escalar de propósito, e a razão é a mesma de {@code
   * CarteiraRepository.buscarIdPorUsuario}: o resultado é usado logo em seguida para travar a
   * carteira daquele titular com {@code SELECT ... FOR UPDATE}. Materializar entidade alguma aqui
   * evita qualquer chance de envenenar o persistence context no caminho de valor.
   *
   * <p>O filtro por {@code ativo} mora na QUERY e não no chamador: apoio encerrado precisa produzir
   * exatamente o mesmo desfecho de apoiador inexistente, e deixar a distinção para fora é convidar
   * um {@code if} esquecido a aceitar financiamento de um apoio que acabou.
   */
  @Query(
      """
      select p.usuarioId from Patrocinador p
      where p.id = :patrocinadorId
        and p.ativo = true
      """)
  Optional<UUID> buscarUsuarioIdAtivo(@Param("patrocinadorId") UUID patrocinadorId);
}
