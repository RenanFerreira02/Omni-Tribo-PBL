import { HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { AuthService } from './auth.service';

/**
 * Anexa `Authorization: Bearer <token>` a toda chamada que sair daqui.
 *
 * O nome e o formato do header não são escolha nossa: o `JwtAuthFilter` do backend lê
 * `Authorization`, exige o prefixo literal `"Bearer "` e corta os 7 primeiros caracteres. Qualquer
 * outra grafia é tratada como requisição anônima e devolve 401.
 *
 * <p>Sem token, a requisição segue INALTERADA em vez de ser bloqueada aqui: o login e o refresh são
 * públicos e precisam passar. Quem decide o que é acessível é o servidor, não este interceptor —
 * bloquear no cliente só esconderia do log o 401 que o servidor daria de qualquer forma.
 */
export const authInterceptor: HttpInterceptorFn = (requisicao, proximo) => {
  const token = inject(AuthService).obterToken();

  if (!token) {
    return proximo(requisicao);
  }

  // `clone` e não mutação: HttpRequest é imutável por contrato do Angular, e mutar a instância
  // original quebraria o retry — a tentativa seguinte reusaria um objeto já alterado.
  return proximo(
    requisicao.clone({
      setHeaders: { Authorization: `Bearer ${token}` },
    }),
  );
};
