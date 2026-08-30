import { Routes } from '@angular/router';
import { authGuard } from './core/auth.guard';
import { Admin } from './pages/admin/admin';
import { Home } from './pages/home/home';
import { Login } from './pages/login/login';

export const routes: Routes = [
  { path: '', pathMatch: 'full', redirectTo: 'home' },
  { path: 'login', component: Login, title: 'Entrar · Omni-Tribo' },
  { path: 'home', component: Home, canActivate: [authGuard], title: 'Home · Omni-Tribo' },
  { path: 'admin', component: Admin, canActivate: [authGuard], title: 'Admin · Omni-Tribo' },
  // Rota curinga por último: o Router casa na ORDEM de declaração, então um `**` acima de qualquer
  // rota real engoliria todas elas.
  { path: '**', redirectTo: 'home' },
];
