import { CommonModule } from '@angular/common';
import { Component, OnInit, inject, signal } from '@angular/core';
import { forkJoin } from 'rxjs';
import { AuthService } from '../../core/auth.service';
import { Problema, mensagemDe, paraProblema } from '../../core/problema';
import {
  Indicador,
  Missao,
  PainelService,
  Tribo,
  rotuloDeStatus,
} from '../../core/painel.service';

/** Filtro de status da lista. `''` = todas. */
interface OpcaoFiltro {
  valor: string;
  rotulo: string;
}

@Component({
  selector: 'app-home',
  imports: [CommonModule],
  templateUrl: './home.html',
  styleUrl: './home.css',
})
export class Home implements OnInit {
  private readonly painel = inject(PainelService);
  readonly auth = inject(AuthService);

  readonly indicadores = signal<Indicador[]>([]);
  readonly missoes = signal<Missao[]>([]);
  readonly tribos = signal<Tribo[]>([]);
  readonly totalNoFiltro = signal(0);

  readonly carregando = signal(true);
  readonly problema = signal<Problema | null>(null);

  readonly filtro = signal('');

  /**
   * Os filtros são a razão de o estado VAZIO ser alcançável de verdade.
   *
   * <p>O seed só produz ABERTA, ACEITA e CONCLUIDA. Sem um caminho real até uma consulta que
   * responde zero linhas, o ramo de "nenhuma missão" seria código que nunca executa — e um estado
   * vazio que ninguém nunca viu é um estado vazio que não funciona. Com o filtro, `EM_DISPUTA`
   * devolve uma página legítima e vazia, pela mesma rota que a operação real usaria.
   */
  readonly opcoes: OpcaoFiltro[] = [
    { valor: '', rotulo: 'Todas' },
    { valor: 'ABERTA', rotulo: rotuloDeStatus('ABERTA') },
    { valor: 'ACEITA', rotulo: rotuloDeStatus('ACEITA') },
    { valor: 'CONCLUIDA', rotulo: rotuloDeStatus('CONCLUIDA') },
    { valor: 'EM_DISPUTA', rotulo: rotuloDeStatus('EM_DISPUTA') },
  ];

  ngOnInit(): void {
    this.carregar();
  }

  carregar(): void {
    this.carregando.set(true);
    this.problema.set(null);

    forkJoin({
      indicadores: this.painel.contagensPorStatus(),
      missoes: this.painel.missoesRecentes(this.filtro()),
      tribos: this.painel.tribos(),
    }).subscribe({
      next: ({ indicadores, missoes, tribos }) => {
        this.indicadores.set(indicadores);
        this.missoes.set(missoes.conteudo);
        this.totalNoFiltro.set(missoes.totalElementos);
        this.tribos.set(tribos);
        this.carregando.set(false);
      },
      error: (erro) => {
        // Guarda o Problema inteiro, não a frase: a tela também mostra o traceId, e discriminar
        // depois pelo `tipo` continua possível sem reparsear nada.
        this.problema.set(paraProblema(erro));
        this.carregando.set(false);
      },
    });
  }

  trocarFiltro(valor: string): void {
    this.filtro.set(valor);
    this.carregar();
  }

  /** Largura da barra, em porcentagem. Denominador nulo devolve 0 — a barra some, e não mente. */
  larguraDaBarra(indicador: Indicador): number {
    if (indicador.total === null || indicador.total === 0) {
      return 0;
    }
    return Math.round((indicador.valor / indicador.total) * 100);
  }

  /** Classe CSS do selo de status, usada por property binding no template. */
  classeDoStatus(status: string): string {
    return 'selo selo-' + status.toLowerCase();
  }

  mensagem(problema: Problema): string {
    return mensagemDe(problema);
  }

  rotuloDoFiltroAtual(): string {
    return this.opcoes.find((o) => o.valor === this.filtro())?.rotulo ?? 'Todas';
  }
}
