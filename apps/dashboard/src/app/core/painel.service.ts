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
   * de missões: o único endpoint que resume números é `GET /admin/carteiras/reconciliacao`, restrito
   * a ADMIN, e ele responde sobre a integridade do ledger — não sobre missões por status. Então o
   * painel compõe. (Havia um `GET /admin/impacto`, sobre o funil da entrega falida; saiu com a
   * extensão logística — ver ADR 0031.)
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
          // Denominador zero vira `null`, nunca 0%. Uma barra de 0% e "não há o que dividir" são
          // coisas diferentes, e a segunda não é desempenho ruim: é ausência de dado.
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
   * Catálogo de benefícios em volta de uma coordenada.
   *
   * <p>A API **não tem** listagem sem recorte: `GET /beneficios` exige proximidade (`lat`, `lon`,
   * `raioMetros`) OU `triboId`, nunca os dois. Não há como pedir "todos". Por isso o painel busca a
   * partir de um centro com raio largo, e a tela diz qual centro usou — apresentar o resultado como
   * "todos os benefícios" seria afirmar mais do que a resposta sustenta.
   *
   * <p>Só benefício ATIVO de parceiro ATIVO volta daqui, e a distância é medida pelo PostGIS a cada
   * consulta: ela depende de onde está quem pergunta, então nunca vem de coluna.
   */
  beneficios(
    lat: number,
    lon: number,
    raioMetros = 20000,
    tamanho = 100,
  ): Observable<Pagina<Beneficio>> {
    return this.http.get<Pagina<Beneficio>>(`${API_BASE_URL}/beneficios`, {
      params: new HttpParams()
        .set('lat', lat)
        .set('lon', lon)
        .set('raioMetros', raioMetros)
        .set('tamanho', tamanho),
    });
  }

  cadastrarBeneficio(pedido: NovoBeneficio): Observable<Beneficio> {
    return this.http.post<Beneficio>(`${API_BASE_URL}/admin/beneficios`, pedido);
  }

  /** Integridade do ledger contra a projeção de saldo. Só ADMIN — 403 para usuário comum. */
  reconciliacao(): Observable<Reconciliacao> {
    return this.http.get<Reconciliacao>(`${API_BASE_URL}/admin/carteiras/reconciliacao`);
  }
}

/** Recorte de `BeneficioResponse`. `distanciaM` é nula no recorte por tribo. */
export interface Beneficio {
  id: string;
  titulo: string;
  descricao: string;
  custoTokens: number;
  tipo: string;
  parceiroId: string;
  parceiroNome: string;
  bairro: string | null;
  distanciaM: number | null;
}

/**
 * Corpo de `POST /api/v1/admin/beneficios`.
 *
 * <p>Sem `ativo` e sem preço em moeda corrente, espelhando o DTO do servidor. A ausência do preço em
 * reais não é esquecimento: um benefício anunciado como "R$ 10 de desconto" por 30 tokens publica
 * uma COTAÇÃO implícita, e token conversível em moeda corrente é dinheiro — com KYC e enquadramento
 * regulatório junto (ADR 0009 §6). O servidor recusa com 400, e `ck_beneficio_sem_reais` (V24) é a
 * barreira final.
 */
export interface NovoBeneficio {
  parceiroId: string;
  titulo: string;
  descricao: string;
  custoTokens: number;
  tipo: string;
}

/** Recorte de `ReconciliacaoResponse`. */
export interface Reconciliacao {
  carteirasVerificadas: number;
  integro: boolean;
  divergencias: { carteiraId: string; saldoProjetado: number; somaLedger: number }[];
}

export const TIPOS_BENEFICIO = ['BEM', 'PERCENTUAL'] as const;

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
