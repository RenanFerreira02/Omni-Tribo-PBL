import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { ApplicationConfig, provideBrowserGlobalErrorListeners } from '@angular/core';
import { provideRouter } from '@angular/router';
import { authInterceptor } from './core/auth.interceptor';
import { routes } from './app.routes';

/**
 * Sem `provideZoneChangeDetection` e sem zone.js — e isso foi MEDIDO, não presumido.
 *
 * <p>O projeto nasceu com `ng new --zoneless=false`, zone.js nos polyfills e
 * `provideZoneChangeDetection({eventCoalescing:true})` nos providers. Mesmo assim, mutar um campo do
 * componente de dentro de um `setTimeout` OU de um `.then()` não re-renderizava nada: o estado ficava
 * correto no objeto e o DOM parado no valor anterior. NgZone não estava dirigindo change detection.
 *
 * <p>O sintoma no navegador era "a tela fica em Carregando… para sempre", sem erro no console e com
 * a requisição respondendo 200 — o pior formato possível de falha, porque tudo parece certo.
 *
 * <p>A saída não é reanimar o zone.js: é depender de algo que funciona nos dois modos. Estado que
 * muda em callback assíncrono vive em `signal()`, e escrever num signal notifica o agendador de
 * change detection do Angular diretamente, com ou sem zona. Os campos ligados a `[(ngModel)]`
 * continuam campos comuns: quem os altera é o usuário digitando, e um event listener de template
 * agenda CD por conta própria.
 */
export const appConfig: ApplicationConfig = {
  providers: [
    provideBrowserGlobalErrorListeners(),
    provideRouter(routes),
    provideHttpClient(withInterceptors([authInterceptor])),
  ],
};
