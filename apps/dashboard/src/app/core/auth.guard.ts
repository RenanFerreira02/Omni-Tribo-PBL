import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { AuthService } from './auth.service';

/**
 * Manda para /login quem não estiver autenticado.
 *
 * Devolve `UrlTree` em vez de chamar `router.navigate()` e retornar `false`: as duas formas
 * redirecionam, mas só o `UrlTree` CANCELA a navegação em curso na mesma passada. Com
 * `navigate()` + `false` existem duas navegações concorrentes, e a barra de endereço pisca a rota
 * protegida antes de voltar.
 *
 * <p>Isto é conveniência de UI, não segurança: o guard roda no browser, onde o usuário controla
 * tudo. Quem protege os dados é o `anyRequest().authenticated()` do backend — desativar este guard
 * pelo DevTools revela telas vazias e 401, não dados.
 */
export const authGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  const router = inject(Router);

  return auth.estaAutenticado() ? true : router.createUrlTree(['/login']);
};
