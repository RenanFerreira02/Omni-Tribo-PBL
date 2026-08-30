package com.omnitribo.identidade.api;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/**
 * Corpo de {@code POST /api/v1/admin/patrocinadores}.
 *
 * <p>Sem CNPJ, sem meio de pagamento e sem dado bancário — não é omissão, é a fronteira do escopo.
 * Onboarding financeiro com validação de CNPJ e prevenção a lavagem é produto regulado; ver a seção
 * "Fora de escopo, decidido" do CLAUDE.md.
 *
 * @param slug identificador estável do apoiador, UNIQUE na tabela. O {@code Pattern} restringe ao
 *     alfabeto que o serviço normaliza (minúsculas, dígitos e hífen) para que dois cadastros do
 *     mesmo apoiador não passem pela UNIQUE só por diferença de caixa ou espaço.
 */
public record CadastrarPatrocinadorRequest(
    @NotBlank(message = "Nome é obrigatório") @Size(max = 100) String nome,
    @NotBlank(message = "Slug do apoiador é obrigatório")
        @Size(max = 50)
        @Pattern(regexp = "[a-z0-9-]+", message = "Slug aceita apenas minúsculas, dígitos e hífen")
        String slug) {}
