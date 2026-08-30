import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { API_BASE_URL } from '../../core/api.config';
import { AuthService } from '../../core/auth.service';
import {
  NovoPontoCustodia,
  PainelService,
  PontoCustodia,
  TIPOS_PONTO,
  Tribo,
} from '../../core/painel.service';
import { Problema, mensagemDe, paraProblema } from '../../core/problema';

/** Recorte de `ImpactoResponse` — mantido da fase anterior, exibido abaixo do cadastro. */
export interface Impacto {
  geradoEm: string;
  entregasFalidas: {
    recebidas: number;
    convertidas: number;
    pendentes: number;
    recusadasPontoLotado: number;
    recusadasSemPatrocinio: number;
    taxaConversao: number | null;
  };
  tokens: {
    aportados: number;
    emCarteiras: number;
    emPotes: number;
    emCirculacao: number;
    resgatados: number;
  };
}

export interface Indicador {
  rotulo: string;
  valor: number;
}

/** Erro por campo do formulário. Chave = nome do campo, igual ao do DTO do servidor. */
type ErrosCampo = Partial<Record<keyof FormularioPonto, string>>;

/**
 * Modelo do formulário.
 *
 * <p><b>Os três numéricos são `number | null`, e isso não é preferência de estilo.</b> Um
 * `<input type="number">` ligado por `[(ngModel)]` entrega ao modelo um NÚMERO, não a string
 * digitada — e `null` quando o campo está vazio. Tipá-los como `string` compilava (o valor inicial
 * era `''`) e explodia em execução no primeiro `.trim()`, dentro do handler de submit: o formulário
 * simplesmente não reagia ao botão Salvar, sem erro visível na tela. O tipo agora descreve o que o
 * Angular realmente coloca ali.
 */
interface FormularioPonto {
  codigo: string;
  tipo: string;
  apelido: string;
  lat: number | null;
  lon: number | null;
  capacidade: number | null;
  triboId: string;
}

/** Centro da listagem. A API não tem "listar todos" — ver `PainelService.pontosCustodia`. */
const CENTRO_LAT = -23.56;
const CENTRO_LON = -46.65;
const RAIO_M = 20000;

@Component({
  selector: 'app-admin',
  // FormsModule pelo [(ngModel)]; CommonModule pelo *ngIf/*ngFor. Standalone exige os dois AQUI.
  imports: [CommonModule, FormsModule],
  templateUrl: './admin.html',
  styleUrl: './admin.css',
})
export class Admin implements OnInit {
  private readonly http = inject(HttpClient);
  private readonly painel = inject(PainelService);
  readonly auth = inject(AuthService);

  readonly centroLat = CENTRO_LAT;
  readonly centroLon = CENTRO_LON;
  readonly raioKm = RAIO_M / 1000;
  readonly tipos = TIPOS_PONTO;

  // ---------- listagem ----------
  readonly pontos = signal<PontoCustodia[]>([]);
  readonly carregandoPontos = signal(true);
  readonly problemaLista = signal<Problema | null>(null);

  // ---------- formulário ----------
  readonly formAberto = signal(false);
  readonly salvando = signal(false);
  readonly sucesso = signal<string | null>(null);
  readonly problemaForm = signal<Problema | null>(null);
  readonly errosCampo = signal<ErrosCampo>({});
  readonly tribos = signal<Tribo[]>([]);

  /** Campos comuns, não signals: quem os escreve é o usuário digitando, via [(ngModel)]. */
  form: FormularioPonto = Admin.formVazio();

  // ---------- impacto (mantido da fase anterior) ----------
  readonly impacto = signal<Impacto | null>(null);
  readonly funil = signal<Indicador[]>([]);
  readonly tokens = signal<Indicador[]>([]);

  private static formVazio(): FormularioPonto {
    return {
      codigo: '',
      tipo: 'LOJA',
      apelido: '',
      lat: null,
      lon: null,
      capacidade: null,
      triboId: '',
    };
  }

  ngOnInit(): void {
    this.carregarPontos();
    this.painel.tribos().subscribe({
      next: (tribos) => this.tribos.set(tribos),
      // Falha ao carregar tribos não bloqueia o cadastro: o campo é opcional. O select fica vazio
      // e o formulário continua submetível sem tribo.
      error: () => this.tribos.set([]),
    });
    this.http.get<Impacto>(`${API_BASE_URL}/admin/impacto`).subscribe({
      next: (impacto) => {
        this.impacto.set(impacto);
        this.funil.set([
          { rotulo: 'Recebidas', valor: impacto.entregasFalidas.recebidas },
          { rotulo: 'Convertidas em missão', valor: impacto.entregasFalidas.convertidas },
          { rotulo: 'Pendentes', valor: impacto.entregasFalidas.pendentes },
          { rotulo: 'Recusadas — ponto lotado', valor: impacto.entregasFalidas.recusadasPontoLotado },
          {
            rotulo: 'Recusadas — sem patrocínio',
            valor: impacto.entregasFalidas.recusadasSemPatrocinio,
          },
        ]);
        this.tokens.set([
          { rotulo: 'Aportados', valor: impacto.tokens.aportados },
          { rotulo: 'Em carteiras', valor: impacto.tokens.emCarteiras },
          { rotulo: 'Em potes', valor: impacto.tokens.emPotes },
          { rotulo: 'Em circulação', valor: impacto.tokens.emCirculacao },
          { rotulo: 'Resgatados (queimados)', valor: impacto.tokens.resgatados },
        ]);
      },
      error: () => this.impacto.set(null),
    });
  }

  carregarPontos(): void {
    this.carregandoPontos.set(true);
    this.problemaLista.set(null);
    this.painel.pontosCustodia(CENTRO_LAT, CENTRO_LON, RAIO_M).subscribe({
      next: (pontos) => {
        this.pontos.set(pontos);
        this.carregandoPontos.set(false);
      },
      error: (erro) => {
        this.problemaLista.set(paraProblema(erro));
        this.carregandoPontos.set(false);
      },
    });
  }

  abrirFormulario(): void {
    this.form = Admin.formVazio();
    this.errosCampo.set({});
    this.problemaForm.set(null);
    this.sucesso.set(null);
    this.formAberto.set(true);
  }

  cancelar(): void {
    this.formAberto.set(false);
    this.errosCampo.set({});
    this.problemaForm.set(null);
  }

  /**
   * Validação NO CLIENTE, espelhando `CadastrarPontoCustodiaRequest`.
   *
   * <p><b>Ela não substitui a do servidor, e não é a barreira de nada.</b> É conveniência de
   * digitação: evita uma ida ao servidor para dizer o que já dá para ver no formulário. Quem decide
   * é o backend — `@NotBlank`, `@Pattern`, `@Size`, `@DecimalMin/Max`, `@Positive` no DTO, mais as
   * regras que só ele consegue verificar (código duplicado, tribo existente) e, no fim,
   * `uk_ponto_custodia_codigo` no banco. Qualquer uma destas linhas pode ser burlada pelo DevTools
   * em dois segundos; nenhuma das do servidor pode.
   *
   * <p>Consequência prática: NÃO afrouxamos nada aqui para o formulário "funcionar". Se este espelho
   * divergir do DTO, o sintoma correto é um 400 que a tela exibe por campo — não uma regra relaxada.
   */
  private validar(): ErrosCampo {
    const e: ErrosCampo = {};
    const f = this.form;

    if (!f.codigo.trim()) {
      e.codigo = 'Código é obrigatório';
    } else if (f.codigo.length > 20) {
      e.codigo = 'Código tem no máximo 20 caracteres';
    } else if (!/^[A-Z0-9-]+$/.test(f.codigo)) {
      e.codigo = 'Código aceita apenas maiúsculas, dígitos e hífen';
    }

    if (!f.tipo) {
      e.tipo = 'Tipo é obrigatório';
    }

    if (!f.apelido.trim()) {
      e.apelido = 'Apelido é obrigatório';
    } else if (f.apelido.length > 100) {
      e.apelido = 'Apelido tem no máximo 100 caracteres';
    }

    if (f.lat === null || Number.isNaN(f.lat)) {
      e.lat = 'Latitude é obrigatória';
    } else if (f.lat < -90 || f.lat > 90) {
      e.lat = 'Latitude fora do intervalo';
    }

    if (f.lon === null || Number.isNaN(f.lon)) {
      e.lon = 'Longitude é obrigatória';
    } else if (f.lon < -180 || f.lon > 180) {
      e.lon = 'Longitude fora do intervalo';
    }

    if (f.capacidade === null || Number.isNaN(f.capacidade)) {
      e.capacidade = 'Capacidade é obrigatória';
    } else if (!Number.isInteger(f.capacidade) || f.capacidade <= 0) {
      e.capacidade = 'Capacidade deve ser maior que zero';
    } else if (f.capacidade > 10000) {
      e.capacidade = 'Capacidade máxima é 10000';
    }

    return e;
  }

  salvar(): void {
    this.sucesso.set(null);
    this.problemaForm.set(null);

    const erros = this.validar();
    this.errosCampo.set(erros);
    if (Object.keys(erros).length > 0) {
      return;
    }

    const pedido: NovoPontoCustodia = {
      codigo: this.form.codigo.trim(),
      tipo: this.form.tipo,
      apelido: this.form.apelido.trim(),
      lat: this.form.lat as number,
      lon: this.form.lon as number,
      capacidade: this.form.capacidade as number,
    };
    if (this.form.triboId) {
      pedido.triboId = this.form.triboId;
    }

    this.salvando.set(true);
    this.painel.cadastrarPontoCustodia(pedido).subscribe({
      next: (criado) => {
        this.salvando.set(false);
        this.formAberto.set(false);
        this.sucesso.set(`Ponto ${criado.codigo} — ${criado.apelido} — cadastrado.`);
        // Item 4 do escopo: a listagem se atualiza sem recarregar a página. Recarrega do SERVIDOR
        // em vez de empurrar o objeto na lista local: o ponto novo pode estar fora do raio da
        // consulta, e inseri-lo à mão mostraria na tela algo que a consulta não devolveria.
        this.carregarPontos();
      },
      error: (erro) => {
        this.salvando.set(false);
        const problema = paraProblema(erro);
        this.problemaForm.set(problema);
        // 400 do Bean Validation traz `errors[{campo, mensagem}]`, prontos para marcar o campo.
        const corpo = erro?.error as { errors?: { campo: string; mensagem: string }[] } | null;
        if (corpo?.errors?.length) {
          const porCampo: ErrosCampo = {};
          for (const item of corpo.errors) {
            porCampo[item.campo as keyof FormularioPonto] = item.mensagem;
          }
          this.errosCampo.set(porCampo);
        }
      },
    });
  }

  ocupacaoPercentual(ponto: PontoCustodia): number {
    if (ponto.capacidade <= 0) {
      return 0;
    }
    return Math.round((ponto.ocupacao / ponto.capacidade) * 100);
  }

  /** Classe do selo de lotação — usada por property binding. */
  classeDeLotacao(ponto: PontoCustodia): string {
    const pct = this.ocupacaoPercentual(ponto);
    if (pct >= 100) {
      return 'lotacao lotacao-cheio';
    }
    return pct >= 80 ? 'lotacao lotacao-quase' : 'lotacao lotacao-ok';
  }

  mensagem(problema: Problema): string {
    return mensagemDe(problema);
  }
}
