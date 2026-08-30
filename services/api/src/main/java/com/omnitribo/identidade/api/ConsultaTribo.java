package com.omnitribo.identidade.api;

import java.util.UUID;

/**
 * Porta pública de identidade para saber se uma tribo EXISTE.
 *
 * <p>Separada de {@link ConsultaAfiliacao}, que responde sobre a tribo DE UM USUÁRIO. Aqui a
 * pergunta não tem usuário nenhum: é a validação de uma chave estrangeira vinda do cliente.
 *
 * <p>Consumida por {@code logistica} no cadastro de ponto de custódia. Sem ela, `logistica` teria
 * de importar `identidade.dominio` — proibido pelo ArchUnit — ou deixar o INSERT falhar na FK, o
 * que vira {@code DataIntegrityViolationException} e sai como <b>500</b>. Um id de tribo digitado
 * errado é requisição malformada, não falha do servidor.
 *
 * <p>Devolve boolean, e não a tribo: quem pergunta só precisa decidir entre aceitar e recusar, e
 * devolver o objeto daria a `logistica` um dado de outro módulo que ela não tem por que conhecer.
 */
public interface ConsultaTribo {

  boolean existe(UUID triboId);
}
