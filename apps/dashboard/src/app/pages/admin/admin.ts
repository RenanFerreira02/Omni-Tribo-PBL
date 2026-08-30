import { CommonModule } from '@angular/common';
import { Component, OnInit, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { AuthService } from '../../core/auth.service';
import {
  Beneficio,
  NovoBeneficio,
  PainelService,
  Reconciliacao,
  TIPOS_BENEFICIO,
} from '../../core/painel.service';
import { Problema, mensagemDe, paraProblema } from '../../core/problema';

export interface Indicador {
  rotulo: string;
  valor: string;
}

/** Erro por campo do formulário. Chave = nome do campo, igual ao do DTO do servidor. */
type ErrosCampo = Partial<Record<keyof FormularioBeneficio, string>>;

/**
 * Modelo do formulário.
 *
 * <p><b>`custoTokens` é `number | null`, e isso não é preferência de estilo.</b> Um
 * `<input type="number">` ligado por `[(ngModel)]` entrega ao modelo um NÚMERO, não a string
 * digitada — e `null` quando o campo está vazio. Tipá-lo como `string` compila (o valor inicial é
 * `''`) e explode em execução no primeiro `.trim()`, dentro do handler de submit: o formulário
 * simplesmente não reage ao botão Salvar, sem erro visível na tela. O tipo descreve o que o Angular
 * realmente coloca ali.
 */
interface FormularioBeneficio {
  parceiroId: string;
  titulo: string;
  descricao: string;
  custoTokens: number | null;
  tipo: string;
}

/** Centro da listagem. A API não tem "listar todos" — ver `PainelService.beneficios`. */
const CENTRO_LAT = -23.56;
const CENTRO_LON = -46.65;
const RAIO_M = 20000;

/**
 * Reprova qualquer menção a moeda corrente, espelhando o `@Pattern` do DTO.
 *
 * <p>`\b` em volta de `reais?` evita reprovar "realmente" e "realeza"; `i` torna a comparação
 * insensível a caixa; `s` faz `.` casar quebra de linha, senão uma descrição multilinha escaparia.
 */
const MENCIONA_REAIS = /(R\$|\breais?\b)/is;

@Component({
  selector: 'app-admin',
  // FormsModule pelo [(ngModel)]; CommonModule pelo *ngIf/*ngFor. Standalone exige os dois AQUI.
  imports: [CommonModule, FormsModule],
  templateUrl: './admin.html',
  styleUrl: './admin.css',
})
export class Admin implements OnInit {
  private readonly painel = inject(PainelService);
  readonly auth = inject(AuthService);

  readonly centroLat = CENTRO_LAT;
  readonly centroLon = CENTRO_LON;
  readonly raioKm = RAIO_M / 1000;
  readonly tipos = TIPOS_BENEFICIO;

  // ---------- listagem ----------
  readonly beneficios = signal<Beneficio[]>([]);
  readonly carregandoBeneficios = signal(true);
  readonly problemaLista = signal<Problema | null>(null);

  // ---------- formulário ----------
  readonly formAberto = signal(false);
  readonly salvando = signal(false);
  readonly sucesso = signal<string | null>(null);
  readonly problemaForm = signal<Problema | null>(null);
  readonly errosCampo = signal<ErrosCampo>({});

  /**
   * Parceiros disponíveis para o select, derivados do próprio catálogo.
   *
   * <p>Não há endpoint de listagem de parceiros — o catálogo é a única resposta que os nomeia, e ela
   * já traz `parceiroId` e `parceiroNome` em cada item. Derivar daqui em vez de pedir um endpoint
   * novo mantém a tela dentro da superfície que a API realmente expõe.
   */
  readonly parceiros = signal<{ id: string; nome: string }[]>([]);

  /** Campos comuns, não signals: quem os escreve é o usuário digitando, via [(ngModel)]. */
  form: FormularioBeneficio = Admin.formVazio();

  // ---------- integridade do ledger ----------
  readonly reconciliacao = signal<Reconciliacao | null>(null);
  readonly indicadores = signal<Indicador[]>([]);

  private static formVazio(): FormularioBeneficio {
    return { parceiroId: '', titulo: '', descricao: '', custoTokens: null, tipo: 'BEM' };
  }

  ngOnInit(): void {
    this.carregarBeneficios();
    this.painel.reconciliacao().subscribe({
      next: (dados) => {
        this.reconciliacao.set(dados);
        this.indicadores.set([
          { rotulo: 'Carteiras verificadas', valor: String(dados.carteirasVerificadas) },
          { rotulo: 'Divergências', valor: String(dados.divergencias.length) },
          { rotulo: 'Ledger íntegro', valor: dados.integro ? 'sim' : 'NÃO' },
        ]);
      },
      // 403 para quem não é ADMIN. Não é erro de tela: é a autorização funcionando, e o painel
      // simplesmente não mostra a seção. Esconder NÃO é proteger — quem protege é o @PreAuthorize.
      error: () => this.reconciliacao.set(null),
    });
  }

  carregarBeneficios(): void {
    this.carregandoBeneficios.set(true);
    this.problemaLista.set(null);
    this.painel.beneficios(CENTRO_LAT, CENTRO_LON, RAIO_M).subscribe({
      next: (pagina) => {
        this.beneficios.set(pagina.conteudo);
        const porId = new Map<string, string>();
        for (const b of pagina.conteudo) {
          porId.set(b.parceiroId, b.parceiroNome);
        }
        this.parceiros.set([...porId].map(([id, nome]) => ({ id, nome })));
        this.carregandoBeneficios.set(false);
      },
      error: (erro) => {
        this.problemaLista.set(paraProblema(erro));
        this.carregandoBeneficios.set(false);
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
   * Validação NO CLIENTE, espelhando `CadastrarBeneficioRequest`.
   *
   * <p><b>Ela não substitui a do servidor, e não é a barreira de nada.</b> É conveniência de
   * digitação: evita uma ida ao servidor para dizer o que já dá para ver no formulário. Quem decide
   * é o backend — `@NotBlank`, `@Pattern`, `@Size`, `@Positive` no DTO, mais as regras que só ele
   * consegue verificar (parceiro existente e ativo) e, no fim, `ck_beneficio_sem_reais` no banco.
   * Qualquer uma destas linhas pode ser burlada pelo DevTools em dois segundos; nenhuma das do
   * servidor pode.
   *
   * <p>Consequência prática: NÃO afrouxamos nada aqui para o formulário "funcionar". Se este espelho
   * divergir do DTO, o sintoma correto é um 400 que a tela exibe por campo — não uma regra relaxada.
   */
  private validar(): ErrosCampo {
    const e: ErrosCampo = {};
    const f = this.form;

    if (!f.parceiroId) {
      e.parceiroId = 'Parceiro é obrigatório';
    }

    if (!f.titulo.trim()) {
      e.titulo = 'Título é obrigatório';
    } else if (f.titulo.length > 120) {
      e.titulo = 'Título tem no máximo 120 caracteres';
    } else if (MENCIONA_REAIS.test(f.titulo)) {
      e.titulo = 'Benefício não pode ser anunciado em reais: use um BEM ou um PERCENTUAL';
    }

    if (!f.descricao.trim()) {
      e.descricao = 'Descrição é obrigatória';
    } else if (f.descricao.length > 500) {
      e.descricao = 'Descrição tem no máximo 500 caracteres';
    } else if (MENCIONA_REAIS.test(f.descricao)) {
      e.descricao = 'Benefício não pode ser anunciado em reais: use um BEM ou um PERCENTUAL';
    }

    if (f.custoTokens === null || Number.isNaN(f.custoTokens)) {
      e.custoTokens = 'Custo em tokens é obrigatório';
    } else if (!Number.isInteger(f.custoTokens) || f.custoTokens <= 0) {
      e.custoTokens = 'Custo em tokens deve ser positivo';
    }

    if (!f.tipo) {
      e.tipo = 'Tipo é obrigatório';
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

    const pedido: NovoBeneficio = {
      parceiroId: this.form.parceiroId,
      titulo: this.form.titulo.trim(),
      descricao: this.form.descricao.trim(),
      custoTokens: this.form.custoTokens as number,
      tipo: this.form.tipo,
    };

    this.salvando.set(true);
    this.painel.cadastrarBeneficio(pedido).subscribe({
      next: (criado) => {
        this.salvando.set(false);
        this.formAberto.set(false);
        this.sucesso.set(
          `Benefício "${criado.titulo}" cadastrado por ${criado.custoTokens} tokens.`,
        );
        // A listagem se atualiza sem recarregar a página. Recarrega do SERVIDOR em vez de empurrar
        // o objeto na lista local: o benefício novo pode estar fora do raio da consulta, e
        // inseri-lo à mão mostraria na tela algo que a consulta não devolveria.
        this.carregarBeneficios();
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
            porCampo[item.campo as keyof FormularioBeneficio] = item.mensagem;
          }
          this.errosCampo.set(porCampo);
        }
      },
    });
  }

  /** Classe do selo de tipo — usada por property binding. */
  classeDeTipo(beneficio: Beneficio): string {
    return beneficio.tipo === 'PERCENTUAL' ? 'lotacao lotacao-quase' : 'lotacao lotacao-ok';
  }

  mensagem(problema: Problema): string {
    return mensagemDe(problema);
  }
}
