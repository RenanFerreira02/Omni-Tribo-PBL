import { HttpClient } from '@angular/common/http';
import { Injectable, inject, signal } from '@angular/core';
import { Observable, tap } from 'rxjs';
import { API_BASE_URL } from './api.config';

/** Resposta de POST /auth/login e /auth/refresh. */
export interface LoginResponse {
  accessToken: string;
  refreshToken: string;
  tipoToken: string;
  expiresIn: number;
}

/** Resposta de GET /auth/me — resolvida só dos claims do JWT, sem consulta ao banco. */
export interface Usuario {
  id: string;
  email: string;
  papel: string;
}

@Injectable({ providedIn: 'root' })
export class AuthService {
  private readonly http = inject(HttpClient);

  /**
   * Token em MEMÓRIA, e nada em `localStorage`.
   *
   * A consequência não é neutra e está no README, não escondida aqui: recarregar a aba perde a
   * sessão e o usuário volta para /login. É o preço aceito. O navegador não tem equivalente ao
   * `armazenamentoSeguro.ts` do app mobile — `localStorage` é legível por qualquer script que
   * execute nesta origem, então um XSS levaria o refresh de 30 dias junto, e não só o access de 15
   * minutos.
   */
  private readonly accessToken = signal<string | null>(null);
  // `refreshToken` continua campo comum de propósito: nenhum template o lê, então torná-lo signal
  // só adicionaria cerimônia sem nenhum consumidor reativo.
  private refreshToken: string | null = null;

  /**
   * Signal, e não campo comum: quem escreve aqui é o callback de `carregarUsuario()`, e o cabeçalho
   * do app lê o valor. Escrita em signal notifica o agendador de change detection; escrita em campo
   * comum, fora de um evento de template, não notifica ninguém.
   */
  readonly usuario = signal<Usuario | null>(null);

  login(email: string, senha: string): Observable<LoginResponse> {
    return this.http
      .post<LoginResponse>(`${API_BASE_URL}/auth/login`, { email, senha })
      .pipe(
        tap((resposta) => {
          this.accessToken.set(resposta.accessToken);
          this.refreshToken = resposta.refreshToken;
        }),
      );
  }

  /** Perfil do autenticado. Chamado depois do login para saber se o papel é ADMIN. */
  carregarUsuario(): Observable<Usuario> {
    return this.http
      .get<Usuario>(`${API_BASE_URL}/auth/me`)
      .pipe(tap((usuario) => this.usuario.set(usuario)));
  }

  /**
   * Encerra a sessão no servidor e localmente.
   *
   * A limpeza local roda nos DOIS desfechos: se o POST falhar (rede caída, token já expirado), o
   * usuário ainda tem de sair daqui. Sair só no sucesso deixaria a aba autenticada por causa de uma
   * falha de rede — exatamente o caso em que sair importa mais.
   */
  logout(): Observable<void> {
    const corpo = { refreshToken: this.refreshToken ?? '' };
    return new Observable<void>((observador) => {
      this.http.post<void>(`${API_BASE_URL}/auth/logout`, corpo).subscribe({
        next: () => {
          this.limpar();
          observador.next();
          observador.complete();
        },
        error: () => {
          this.limpar();
          observador.next();
          observador.complete();
        },
      });
    });
  }

  private limpar(): void {
    this.accessToken.set(null);
    this.refreshToken = null;
    this.usuario.set(null);
  }

  /** Lido pelo interceptor a cada requisição. */
  obterToken(): string | null {
    return this.accessToken();
  }

  /**
   * Signal e não campo comum porque o CABEÇALHO lê isto: a barra de navegação aparece e some
   * conforme a sessão. Com campo comum, entrar não faria os links surgirem até a próxima
   * navegação — e sair os deixaria na tela depois da sessão já ter acabado.
   */
  estaAutenticado(): boolean {
    return this.accessToken() !== null;
  }
}
