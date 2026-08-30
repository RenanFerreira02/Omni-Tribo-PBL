import { seg } from './caminho';
import { cliente } from './cliente';
import type { ClimaResponse, EnderecoResponse, TriboResponse } from './tipos';
import { climaResponseSchema, enderecoResponseSchema, triboResponseSchema } from '@/schemas';
import { validarEmDev } from '@/schemas/validar';

/** Tribos, clima e CEP — tudo que responde "onde". */

/** Só o detalhe traz o centro geográfico; a lista o omite para não virar N+1 no servidor. */
export async function buscarTribo(id: string): Promise<TriboResponse> {
  const { data } = await cliente.get<TriboResponse>(`/tribos/${seg(id)}`);
  return validarEmDev(triboResponseSchema, data, `GET /tribos/${id}`);
}

/**
 * Clima do card do mapa.
 *
 * Provedor fora do ar responde **503** com `type` `servico-externo-indisponivel`. O tratamento é
 * ESCONDER o card — quem chama trata pelo `tipo` do erro, nunca exibindo "erro inesperado" por uma
 * degradação prevista.
 */
export async function buscarClima(lat: number, lon: number): Promise<ClimaResponse> {
  const { data } = await cliente.get<ClimaResponse>('/clima', { params: { lat, lon } });
  return validarEmDev(climaResponseSchema, data, 'GET /clima');
}

/**
 * CEP → endereço, para preencher o formulário de missão.
 *
 * Conveniência, não fonte de verdade: o endereço que vale é o que o usuário confirmou e que viaja
 * no corpo da criação. CEP inexistente é **404**; provedor fora do ar é **503** — e as duas coisas
 * pedem reações opostas do usuário.
 */
export async function buscarEnderecoPorCep(cep: string): Promise<EnderecoResponse> {
  const { data } = await cliente.get<EnderecoResponse>(`/enderecos/${seg(cep)}`);
  return validarEmDev(enderecoResponseSchema, data, `GET /enderecos/${cep}`);
}
