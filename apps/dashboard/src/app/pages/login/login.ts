import { CommonModule } from '@angular/common';
import { Component, inject, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from '../../core/auth.service';

@Component({
  selector: 'app-login',
  // Standalone: os dois imports abaixo são OBRIGATÓRIOS e a falta deles não parece o que é.
  // Sem CommonModule, `*ngIf` é lido como atributo desconhecido e o bloco simplesmente NUNCA
  // renderiza — sem erro em tempo de execução. Sem FormsModule, `[(ngModel)]` vira erro de
  // template dizendo que `ngModel` não é propriedade de `input`, que não menciona formulário
  // nenhum. Em NgModule isto ficava no módulo; em standalone é por componente.
  imports: [CommonModule, FormsModule],
  templateUrl: './login.html',
  styleUrl: './login.css',
})
export class Login {
  private readonly auth = inject(AuthService);
  private readonly router = inject(Router);

  // Campos comuns, não signals: `[(ngModel)]` faz two-way binding contra propriedade, e digitar
  // dispara um event listener do Angular, que agenda change detection sozinho.
  email = '';
  senha = '';

  // Lidos por interpolação no template.
  readonly titulo = 'Omni-Tribo';
  readonly ambiente = 'desenvolvimento local';

  // Signals: são escritos de dentro de callbacks de HTTP. Campo comum aqui não re-renderiza.
  readonly carregando = signal(false);
  readonly erro = signal<string | null>(null);

  entrar(): void {
    this.carregando.set(true);
    this.erro.set(null);

    this.auth.login(this.email, this.senha).subscribe({
      next: () => {
        // Só navega DEPOIS de saber quem entrou: /home mostra o papel, e navegar antes deixaria a
        // tela montar com `usuario` nulo e piscar o conteúdo ao chegar a resposta.
        this.auth.carregarUsuario().subscribe({
          next: () => {
            this.carregando.set(false);
            this.router.navigate(['/home']);
          },
          error: () => {
            this.carregando.set(false);
            this.erro.set('Entrou, mas não foi possível carregar o perfil.');
          },
        });
      },
      error: (resposta) => {
        this.carregando.set(false);
        this.erro.set(this.mensagemDe(resposta));
      },
    });
  }

  /**
   * Traduz a falha para uma frase.
   *
   * Discrimina pelo `type` do RFC 9457, que é contrato estável, e NUNCA pelo `detail` — aquele é
   * texto em português voltado a humano e muda a cada revisão de copy do servidor. O status 0 é o
   * caso que mais confunde: não é credencial errada, é a requisição não ter saído (backend fora do
   * ar, ou preflight de CORS reprovado).
   */
  private mensagemDe(resposta: { status?: number; error?: { type?: string } }): string {
    if (resposta.status === 0) {
      return 'Não foi possível falar com a API. Confira se o backend está de pé na porta 8080.';
    }
    if (resposta.error?.type?.endsWith('/limite-requisicoes')) {
      return 'Muitas tentativas seguidas. Aguarde um minuto e tente de novo.';
    }
    if (resposta.status === 401) {
      return 'E-mail ou senha incorretos.';
    }
    return 'Não foi possível entrar. Tente novamente.';
  }
}
