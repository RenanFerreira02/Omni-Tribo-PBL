import type { CategoriaMissao, ComplexidadeMissao } from '@/api/tipos';

/**
 * Nomes de exibição dos enums de missão.
 *
 * Um lugar só. `ROTULO_COMPLEXIDADE` vivia dentro de `app/missao/criar.tsx`, e a tela de detalhe
 * precisou do mesmo mapa para explicar de onde vem a recompensa — copiar produziria duas listas que
 * divergem no dia em que o backend ganhar um nível novo, e a divergência apareceria como duas telas
 * chamando a mesma coisa por nomes diferentes.
 *
 * `Record<Enum, string>` e não `Partial`: um valor novo no enum quebra o typecheck aqui, em vez de
 * cair como `undefined` na tela.
 */
export const ROTULO_COMPLEXIDADE: Record<ComplexidadeMissao, string> = {
  LEVE: 'Leve',
  MEDIA: 'Média',
  PESADA: 'Pesada',
};

export const COMPLEXIDADES: ComplexidadeMissao[] = ['LEVE', 'MEDIA', 'PESADA'];

/**
 * Ordem de EXIBIÇÃO das categorias — não é a ordem do enum no backend, e não precisa ser.
 *
 * A ajuda direta entre vizinhos vem primeiro porque é o que o produto é; ENTREGA fica por último
 * porque é o caso com patrocinador externo, o mais raro e o menos representativo. Antes ENTREGA
 * abria a lista, e a primeira impressão do app era a de um produto de logística.
 *
 * `CategoriaMissao` no servidor NÃO foi reordenada: o `ordinal()` de um enum persistido como String
 * não é contrato, mas mexer nele para mudar a ordem de uns chips seria risco sem retorno.
 */
export const CATEGORIAS: CategoriaMissao[] = ['AJUDA', 'TRIBO', 'COLETA', 'ENTREGA'];
