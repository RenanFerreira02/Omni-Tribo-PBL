import { HttpErrorResponse } from '@angular/common/http';

/**
 * Tradução do ProblemDetail (RFC 9457) da API para uma variante que a UI consegue reagir.
 *
 * <p><b>A discriminação é pelo campo `type`, NUNCA pelo `detail`.</b> É regra dura do projeto e o
 * espelho desta camada é `apps/mobile/src/api/erros.ts`. O motivo: `detail` é texto em português
 * voltado a humano e muda a cada revisão de copy — um `if` sobre ele quebra em silêncio. E `status`
 * sozinho é ambíguo: dois 409 daqui pedem reações opostas (transição inválida manda recarregar a
 * tela; colisão de versão manda repetir).
 *
 * <p>O catálogo canônico é `compartilhado/api/TipoProblema` no backend. Toda resposta de erro
 * carrega `type`, inclusive as que nascem na cadeia de filtros (401 e 429) — nenhuma sai como
 * `about:blank`.
 */
export type TipoProblema =
  | 'requisicaoInvalida'
  | 'naoAutenticado'
  | 'acessoNegado'
  | 'naoEncontrado'
  | 'transicaoInvalida'
  | 'conflitoConcorrencia'
  | 'regraNegocioViolada'
  | 'limiteRequisicoes'
  | 'servicoExternoIndisponivel'
  | 'erroInterno'
  /** A requisição não chegou a ter resposta: backend desligado, DNS, preflight de CORS reprovado. */
  | 'semRede'
  /** `type` fora do catálogo conhecido. Preserva o que veio sem fingir compreensão. */
  | 'desconhecido';

export interface Problema {
  tipo: TipoProblema;
  status: number;
  /** Texto do servidor. Serve para EXIBIR no 422 genérico; nunca para decidir comportamento. */
  detail: string;
  /** Liga esta resposta à linha de log do servidor. */
  traceId?: string;
  /** A URI crua, preservada para o caso `desconhecido` e para diagnóstico. */
  type: string;
}

/** Segmento final da URI do catálogo → variante. Fechado de propósito: URI nova entra aqui à mão. */
const POR_SEGMENTO: Record<string, TipoProblema> = {
  'requisicao-invalida': 'requisicaoInvalida',
  'nao-autenticado': 'naoAutenticado',
  'acesso-negado': 'acessoNegado',
  'nao-encontrado': 'naoEncontrado',
  'transicao-invalida': 'transicaoInvalida',
  'conflito-concorrencia': 'conflitoConcorrencia',
  'regra-negocio-violada': 'regraNegocioViolada',
  'limite-requisicoes': 'limiteRequisicoes',
  'servico-externo-indisponivel': 'servicoExternoIndisponivel',
  'erro-interno': 'erroInterno',
};

export function paraProblema(erro: unknown): Problema {
  if (!(erro instanceof HttpErrorResponse)) {
    return { tipo: 'desconhecido', status: 0, detail: '', type: '' };
  }

  // status 0 não é "erro do servidor": é a requisição não ter saído ou não ter voltado. Backend
  // desligado e preflight de CORS reprovado caem os dois aqui, e nenhum tem `type` para ler.
  if (erro.status === 0) {
    return { tipo: 'semRede', status: 0, detail: '', type: '' };
  }

  const corpo = erro.error as { type?: string; detail?: string; traceId?: string } | null;
  const type = corpo?.type ?? '';
  const segmento = type.substring(type.lastIndexOf('/') + 1);

  return {
    tipo: POR_SEGMENTO[segmento] ?? 'desconhecido',
    status: erro.status,
    detail: corpo?.detail ?? '',
    traceId: corpo?.traceId,
    type,
  };
}

/**
 * Frase mostrada ao usuário, escolhida pela VARIANTE.
 *
 * <p>`regraNegocioViolada` é o único caso que exibe o `detail` do servidor, e isso não contradiz a
 * regra: exibir texto é diferente de decidir comportamento a partir dele. É o 422 genérico — saldo,
 * pote, janela —, em que a tela faz sempre a mesma coisa e só o texto muda. Ver ADR 0010.
 */
export function mensagemDe(problema: Problema): string {
  switch (problema.tipo) {
    case 'semRede':
      return 'Não foi possível falar com a API. Confira se o backend está de pé em localhost:8080.';
    case 'naoAutenticado':
      return 'Sua sessão expirou. Entre novamente.';
    case 'acessoNegado':
      return 'Esta conta não tem permissão para ver estes dados.';
    case 'naoEncontrado':
      return 'O recurso pedido não existe mais.';
    case 'limiteRequisicoes':
      return 'Muitas requisições seguidas. Aguarde um minuto antes de recarregar.';
    case 'servicoExternoIndisponivel':
      return 'Um provedor externo não respondeu. O restante do painel continua válido.';
    case 'requisicaoInvalida':
      return 'O filtro enviado é inválido. Volte ao filtro "Todas".';
    case 'transicaoInvalida':
      return 'O estado mudou enquanto você olhava. Recarregue o painel.';
    case 'conflitoConcorrencia':
      return 'Outra operação alterou estes dados. Recarregue e tente de novo.';
    case 'regraNegocioViolada':
      return problema.detail || 'A operação não satisfaz uma regra de negócio.';
    case 'erroInterno':
      return 'Erro interno no servidor. O traceId abaixo liga esta tela ao log.';
    case 'desconhecido':
      return 'Não foi possível carregar o painel.';
  }
}
