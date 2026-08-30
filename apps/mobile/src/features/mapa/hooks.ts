import { useQuery } from '@tanstack/react-query';

import type { ErroApi } from '@/api/erros';
import { buscarClima, buscarEnderecoPorCep, buscarTribo } from '@/api/lugares';
import type { ClimaResponse, EnderecoResponse, TriboResponse } from '@/api/tipos';

export const chavesLugares = {
  tribo: (id: string) => ['tribos', id] as const,
  clima: (lat: number, lon: number) => ['clima', lat.toFixed(2), lon.toFixed(2)] as const,
  cep: (cep: string) => ['enderecos', cep] as const,
};

/** Só o detalhe traz o centro geográfico — é ele que o mapa usa quando não há localização. */
export function useTribo(id: string | null | undefined) {
  return useQuery<TriboResponse, ErroApi>({
    queryKey: chavesLugares.tribo(id ?? 'nenhuma'),
    enabled: Boolean(id),
    queryFn: () => buscarTribo(id!),
    staleTime: 15 * 60_000,
  });
}

/**
 * Clima do card do mapa.
 *
 * `retry: false` porque o modo de falha esperado é o provedor externo fora do ar (503), e insistir
 * três vezes contra um serviço que caiu só atrasa a tela. Quem consome renderiza o card apenas
 * quando há `data`, então qualquer falha — 503, rede, timeout — simplesmente **esconde o card**, sem
 * precisar ramificar por tipo. Clima ausente não é erro de produto.
 *
 * (O comentário anterior dizia que o consumidor verificava `erro.tipo`. Não verifica, e não precisa:
 * a ausência de `data` já é a condição certa. Descrever um mecanismo que não existe faz quem lê
 * procurar um `if` que nunca vai achar.)
 *
 * O servidor já cacheia 10 min por célula de ~1,1 km; repetir isso aqui evita ida à rede ao voltar
 * para a aba.
 */
export function useClima(coordenada: { lat: number; lon: number } | null) {
  return useQuery<ClimaResponse, ErroApi>({
    queryKey: coordenada ? chavesLugares.clima(coordenada.lat, coordenada.lon) : ['clima', 'sem'],
    enabled: coordenada !== null,
    queryFn: () => buscarClima(coordenada!.lat, coordenada!.lon),
    retry: false,
    staleTime: 10 * 60_000,
  });
}

/**
 * CEP → endereço. Quem chama passa o CEP JÁ com debounce de 500 ms.
 *
 * `enabled` só com 8 dígitos: sem isso, cada tecla intermediária viraria uma requisição que o
 * servidor recusaria com 400.
 */
export function useEnderecoPorCep(cep: string) {
  const completo = /^\d{8}$/.test(cep);

  return useQuery<EnderecoResponse, ErroApi>({
    queryKey: chavesLugares.cep(cep),
    enabled: completo,
    queryFn: () => buscarEnderecoPorCep(cep),
    retry: false,
    // CEP não muda. O servidor cacheia sem TTL; aqui o mesmo, dentro da sessão.
    staleTime: Infinity,
  });
}
