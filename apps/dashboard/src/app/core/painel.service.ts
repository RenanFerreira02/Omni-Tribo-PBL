import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, forkJoin, map } from 'rxjs';
import { API_BASE_URL } from './api.config';

/** Envelope de paginação da API. NÃO é o `Page` do Spring Data — ver `compartilhado/api/PaginaResponse`. */
export interface Pagina<T> {
  conteudo: T[];
  pagina: number;
  tamanho: number;
  totalElementos: number;
  totalPaginas: number;
  primeira: boolean;
  ultima: boolean;
}

/** Recorte de `MissaoResponse` — só os campos que este painel exibe. */
export interface Missao {
  id: string;
  titulo: string;
  status: string;
  categoria: string;
  bairro: string | null;
  cidade: string | null;
  xpRecompensa: number;
  tokensRecompensa: number;
  criadaEm: string;
}

export interface Tribo {
  id: string;
  nome: string;
  bairro: string;
  centroLat: number | null;
  centroLon: number | null;
}

/** Card de indicador. `total` alimenta a barra; nulo quando a proporção não faz sentido. */
export interface Indicador {
  chave: string;
  rotulo: string;
  valor: number;
  total: number | null;
}

/** Os quatro status que o seed produz, mais os que a operação real produz. Ordem de exibição. */
export const STATUS_EXIBIDOS = ['ABERTA', 'ACEITA', 'EM_ANDAMENTO', 'CONCLUIDA'] as const;

@Injectable({ providedIn: 'root' })
export class PainelService {
  private readonly http = inject(HttpClient);

  /**
   * Contagens por status, para os cards.
   *
   * <p><b>Por que uma requisição por status, e não uma só.</b> A API não tem endpoint de agregação
   * acessível a usuário comum: o único que resume números é `GET /admin/impacto`, restrito a ADMIN
   * por `@PreAuthorize`, e ele responde sobre o funil da ENTREGA FALIDA — não sobre missões por
   * status. Então o painel compõe.
   *
   * <p>E compõe lendo `totalElementos`, com `tamanho=1`, em vez de baixar as missões e contar em
   * JavaScript. Contar no cliente contaria a PÁGINA, não o conjunto: com mais de 100 missões o card
   * mostraria 100 para sempre, e o número erraria sem nunca dar erro. `totalElementos` é o servidor
   * contando. O `tamanho=1` existe só para não trafegar um corpo que será descartado.
   *
   * <p>Custo: 4 requisições por carga do painel, contra um teto de 300 GET/min por usuário.
   */
  contagensPorStatus(): Observable<Indicador[]> {
    const porStatus = STATUS_EXIBIDOS.map((status) =>
      this.http
        .get<Pagina<Missao>>(`${API_BASE_URL}/missoes`, {
          params: new HttpParams().set('status', status).set('tamanho', 1),
        })
        .pipe(map((pagina) => pagina.totalElementos)),
    );

    return forkJoin(porStatus).pipe(
      map((contagens) => {
        const soma = contagens.reduce((a, b) => a + b, 0);
        return STATUS_EXIBIDOS.map((status, i) => ({
          chave: status,
          rotulo: rotuloDeStatus(status),
          valor: contagens[i],
          // Denominador zero vira `null`, nunca 0% — mesma regra do painel de impacto do backend.
          // Uma barra de 0% e "não há o que dividir" são coisas diferentes.
          total: soma > 0 ? soma : null,
        }));
      }),
    );
  }

  /** Missões mais recentes. `status` vazio traz todas as visíveis. */
  missoesRecentes(status: string, quantidade = 8): Observable<Pagina<Missao>> {
    let params = new HttpParams()
      .set('tamanho', quantidade)
      .set('ordenarPor', 'CRIADA_EM')
      .set('direcao', 'DESC');
    if (status) {
      params = params.set('status', status);
    }
    return this.http.get<Pagina<Missao>>(`${API_BASE_URL}/missoes`, { params });
  }

  tribos(): Observable<Tribo[]> {
    return this.http.get<Tribo[]>(`${API_BASE_URL}/tribos`);
  }

  /**
   * Pontos de custódia ativos em volta de uma coordenada.
   *
   * <p>A API **não tem** listagem sem coordenada: `GET /pontos-custodia` exige `lat` e `lon` e
   * responde por raio, com a distância medida pelo PostGIS. Não há como pedir "todos". Por isso o
   * painel busca a partir de um centro com raio largo, e a tela diz qual centro usou — apresentar
   * o resultado como "todos os pontos" seria afirmar mais do que a resposta sustenta.
   */
  pontosCustodia(
    lat: number,
    lon: number,
    raioMetros = 20000,
    limite = 100,
  ): Observable<PontoCustodia[]> {
    return this.http.get<PontoCustodia[]>(`${API_BASE_URL}/pontos-custodia`, {
      params: new HttpParams()
        .set('lat', lat)
        .set('lon', lon)
        .set('raioMetros', raioMetros)
        .set('limite', limite),
    });
  }

  cadastrarPontoCustodia(pedido: NovoPontoCustodia): Observable<PontoCustodia> {
    return this.http.post<PontoCustodia>(`${API_BASE_URL}/pontos-custodia`, pedido);
  }
}

/** Recorte de `PontoCustodiaResponse`. `distanciaM` é nula fora da busca por raio. */
export interface PontoCustodia {
  id: string;
  codigo: string;
  tipo: string;
  apelido: string;
  lat: number;
  lon: number;
  capacidade: number;
  ocupacao: number;
  distanciaM: number | null;
}

/**
 * Corpo de `POST /api/v1/pontos-custodia`.
 *
 * <p>Sem `ocupacao` e sem `ativo`, espelhando o DTO do servidor. Não é economia de digitação: o
 * servidor descarta campo que não declara (`fail-on-unknown-properties: false`), então mandá-los
 * daqui não daria erro nenhum — só criaria a impressão, para quem lesse este arquivo, de que o
 * cliente controla a ocupação. Ele não controla, e não deve.
 */
export interface NovoPontoCustodia {
  codigo: string;
  tipo: string;
  apelido: string;
  lat: number;
  lon: number;
  capacidade: number;
  triboId?: string;
}

export const TIPOS_PONTO = ['LOJA', 'LOCKER', 'PORTARIA', 'VIZINHO'] as const;

export function rotuloDeStatus(status: string): string {
  const rotulos: Record<string, string> = {
    ABERTA: 'Abertas',
    ACEITA: 'Aceitas',
    EM_ANDAMENTO: 'Em andamento',
    AGUARDANDO_CONFIRMACAO: 'Aguardando confirmação',
    EM_DISPUTA: 'Em disputa',
    CONCLUIDA: 'Concluídas',
    CANCELADA: 'Canceladas',
    EXPIRADA: 'Expiradas',
    RASCUNHO: 'Rascunhos',
  };
  return rotulos[status] ?? status;
}
