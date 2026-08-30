/**
 * Endereço do backend Spring Boot.
 *
 * `localhost:8080` é o alvo de desenvolvimento e precisa estar na lista de origens permitidas do
 * servidor — `app.cors.origens-permitidas`, no perfil `dev` da API, que já inclui
 * `http://localhost:4200`. Trocar a porta do `ng serve` sem trocar a lista lá derruba o preflight,
 * e a falha aparece só no console do browser: o servidor responde e não loga nada.
 */
export const API_BASE_URL = 'http://localhost:8080/api/v1';
