-- =============================================================================
-- V903 — Seed de demonstração: Cidade Líder, São Paulo (zona leste)
-- Carregado APENAS nos perfis dev e test (application-dev.yml / application-test.yml).
--
-- POR QUE ESTE ARQUIVO EXISTE: o V900 concentra tudo em Pinheiros / Vila Madalena,
-- a ~25 km daqui. Quem abre o app na zona leste vê o radar vazio, porque o radar é
-- geoespacial de verdade — ele não tem como inventar missão perto de quem procura.
-- Este seed povoa a região do CEP 08280-460 para que a demonstração seja feita com
-- o GPS ligado, e não com coordenada digitada à mão.
--
-- Ponto de referência: Rua Antônio Maria Bessa, Cidade Líder, São Paulo — SP.
-- Coordenadas: -23.55737, -46.46987 (geocodificadas via OpenStreetMap/Nominatim;
-- o ViaCEP devolve logradouro e bairro, nunca lat/lon).
-- Tudo aqui está entre 170 m e 4,1 km desse ponto, distâncias medidas com
-- ST_Distance sobre geography — nenhuma foi escrita de cabeça.
--
-- SUFIXO 9xx nos UUIDs: as linhas do V900/V902 vão de ...0001 a ...0012. A
-- faixa 9xx deixa óbvio, num SELECT qualquer, o que veio deste arquivo — e torna
-- impossível colidir com o seed anterior.
--
-- Senha de todos os usuários: Senha@123 (mesma do V900).
-- =============================================================================

-- -----------------------------------------------------------------------
-- Tribo
-- -----------------------------------------------------------------------
INSERT INTO tribo (id, nome, bairro, criada_em) VALUES
    ('aaaaaaaa-0000-0000-0000-000000000901', 'Tribo Cidade Líder', 'Cidade Líder', NOW());

-- -----------------------------------------------------------------------
-- Usuários da tribo.
--
-- Usuários NOVOS, e não realocação dos existentes, de propósito: alice, bob e carol
-- são referenciados por testes que afirmam contagem de extrato e de alertas POR
-- USUÁRIO. Mudar a tribo deles passaria por refatoração inofensiva e quebraria
-- assertion em outro módulo.
--
-- `nivel` é cache derivado de `xp` por RegraNivel (1 + floor(sqrt(xp/100))), e está
-- calculado aqui: 450 → 3, 120 → 2, 111 → 2. Gravar um nível incoerente com o XP
-- faria a exportação LGPD (que lê a coluna) divergir do perfil (que deriva) — é a
-- Pendência 4 do CLAUDE.md, e não convém alimentá-la com dado novo.
-- -----------------------------------------------------------------------
INSERT INTO usuario (id, nome, email, senha_hash, handle, tribo_id, xp, nivel, streak, rating,
                     papel, status, criado_em, atualizado_em, versao) VALUES
    ('bbbbbbbb-0000-0000-0000-000000000901',
     'Renan Ferreira',
     'renan@omnitribo.dev',
     '{bcrypt}' || crypt('Senha@123', gen_salt('bf', 10)),
     'renan',
     'aaaaaaaa-0000-0000-0000-000000000901',
     450, 3, 9, 4.9, 'USUARIO', 'ATIVO', NOW() - INTERVAL '60 days', NOW(), 0),

    ('bbbbbbbb-0000-0000-0000-000000000902',
     'Marlene Souza',
     'marlene@omnitribo.dev',
     '{bcrypt}' || crypt('Senha@123', gen_salt('bf', 10)),
     'marlene',
     'aaaaaaaa-0000-0000-0000-000000000901',
     120, 2, 2, 4.6, 'USUARIO', 'ATIVO', NOW() - INTERVAL '25 days', NOW(), 0),

    ('bbbbbbbb-0000-0000-0000-000000000903',
     'Jonas Ribeiro',
     'jonas@omnitribo.dev',
     '{bcrypt}' || crypt('Senha@123', gen_salt('bf', 10)),
     'jonas',
     'aaaaaaaa-0000-0000-0000-000000000901',
     111, 2, 4, 4.7, 'USUARIO', 'ATIVO', NOW() - INTERVAL '40 days', NOW(), 0);

-- -----------------------------------------------------------------------
-- Missões.
--
-- xp_recompensa e tokens_recompensa NÃO foram inventados: saíram de
-- CalculadoraDeRecompensa com os parâmetros de app.missoes.recompensa (versao 1),
-- usando as distâncias reais entre os pontos abaixo. Valor de seed que não bate com
-- a fórmula transforma `POST /missoes/previa-recompensa` em contradição na tela —
-- a prévia diria um número e a lista, outro.
--
-- `complexidade` de ENTREGA e COLETA é DERIVADA de peso e volume (o servidor não
-- aceita declarar junto); TRIBO e AJUDA declaram, porque não movem objeto.
--
-- valor_brl é 0 em todas: ck_missao_economia (V15) exige, e BRL saiu do ciclo de
-- missões no ADR 0009.
-- -----------------------------------------------------------------------
INSERT INTO missao (id, criador_id, executor_id, categoria, titulo, descricao, status,
                    xp_recompensa, valor_brl, tokens_recompensa, complexidade, versao_formula,
                    pote_tokens, origem, destino,
                    cep, logradouro, bairro, cidade, uf,
                    raio_checkin_m, peso_kg, volume_l,
                    janela_inicio, janela_fim, criada_em, aceita_em, concluida_em, versao)
VALUES

-- ===== ENTREGA =====

-- M1 — 170 m do ponto de referência. É a que abre a lista do radar.
('dddddddd-0000-0000-0000-000000000901',
 'bbbbbbbb-0000-0000-0000-000000000001',
 NULL,
 'ENTREGA',
 'Entregar caixa de piso vinílico — 12 réguas',
 'Caixa que ficou guardada com a vizinha do 12 desde sábado, na Cidade Líder. '
 'Peso considerável para uma pessoa só: leve carrinho. Entregar na Rua Antônio Maria Bessa.',
 'ABERTA',
 132, 0.00, 44, 'MEDIA', 1, 0,
 ST_SetSRID(ST_MakePoint(-46.46850, -23.55650), 4326)::geography,  -- origem: casa da vizinha
 ST_SetSRID(ST_MakePoint(-46.46987, -23.55737), 4326)::geography,  -- destino: 170 m
 '08280460', 'Rua Antônio Maria Bessa', 'Cidade Líder', 'São Paulo', 'SP',
 50, 22.00, 45.0,
 NOW() - INTERVAL '6 hours', NOW() + INTERVAL '6 days',
 NOW() - INTERVAL '6 hours', NULL, NULL, 0),

-- M2 — 4,1 km: existe para o radar ter o que ORDENAR. Um raio com um resultado só
-- não demonstra ordenação por distância.
('dddddddd-0000-0000-0000-000000000902',
 'bbbbbbbb-0000-0000-0000-000000000001',
 NULL,
 'ENTREGA',
 'Entregar 2 sacos de argamassa AC-III',
 'Retirada na loja e entrega na padaria da esquina, que recebe para o cliente. '
 'Carga pesada — obrigatório carrinho ou dois entregadores.',
 'ABERTA',
 210, 0.00, 70, 'PESADA', 1, 0,
 ST_SetSRID(ST_MakePoint(-46.50630, -23.57260), 4326)::geography,  -- Leroy Merlin Aricanduva
 ST_SetSRID(ST_MakePoint(-46.46550, -23.55780), 4326)::geography,
 '08280000', 'Avenida Líder', 'Cidade Líder', 'São Paulo', 'SP',
 50, 40.00, 30.0,
 NOW() - INTERVAL '2 hours', NOW() + INTERVAL '9 days',
 NOW() - INTERVAL '2 hours', NULL, NULL, 0),

-- M7 — histórico concluído, para o perfil e o extrato não nascerem vazios.
('dddddddd-0000-0000-0000-000000000907',
 'bbbbbbbb-0000-0000-0000-000000000001',
 'bbbbbbbb-0000-0000-0000-000000000903',  -- executor: jonas
 'ENTREGA',
 'Entregar kit de torneira e sifão',
 'Compra que ficou na casa de um vizinho e a tribo levou até quem comprou.',
 'CONCLUIDA',
 111, 0.00, 37, 'MEDIA', 1, 0,
 ST_SetSRID(ST_MakePoint(-46.46850, -23.55650), 4326)::geography,
 ST_SetSRID(ST_MakePoint(-46.47120, -23.56020), 4326)::geography,  -- destino do trecho
 '08280460', 'Rua Antônio Maria Bessa', 'Cidade Líder', 'São Paulo', 'SP',
 50, 9.00, 25.0,
 NOW() - INTERVAL '5 days', NOW() - INTERVAL '3 days',
 NOW() - INTERVAL '5 days', NOW() - INTERVAL '4 days 20 hours', NOW() - INTERVAL '4 days', 0),

-- ===== COLETA =====

-- M3 — pote de 38 financiado pela marlene (ver lançamentos no fim do arquivo).
('dddddddd-0000-0000-0000-000000000903',
 'bbbbbbbb-0000-0000-0000-000000000902',
 NULL,
 'COLETA',
 'Coletar recicláveis do mutirão da praça',
 'Papelão e PET separados desde sábado, na praça. Levar ao ponto de coleta da Cidade Líder, '
 'que tem o contêiner da cooperativa.',
 'ABERTA',
 114, 0.00, 38, 'MEDIA', 1, 38,
 ST_SetSRID(ST_MakePoint(-46.47030, -23.56250), 4326)::geography,  -- praça, 570 m
 ST_SetSRID(ST_MakePoint(-46.46850, -23.55650), 4326)::geography,
 '08280460', 'Praça da Cidade Líder', 'Cidade Líder', 'São Paulo', 'SP',
 60, 8.00, 60.0,
 NOW() - INTERVAL '1 day', NOW() + INTERVAL '5 days',
 NOW() - INTERVAL '1 day', NULL, NULL, 0),

-- M8 — ACEITA com o renan de executor: dá ao app uma missão EM CURSO para mostrar,
-- que é o estado onde o botão de check-in aparece.
('dddddddd-0000-0000-0000-000000000908',
 'bbbbbbbb-0000-0000-0000-000000000903',
 'bbbbbbbb-0000-0000-0000-000000000901',  -- executor: renan
 'COLETA',
 'Recolher óleo de cozinha usado na escola',
 'A escola junta o óleo das famílias em garrafas PET. Recolher e levar ao ponto de coleta '
 'do bairro. Não misturar com outros resíduos.',
 'ACEITA',
 126, 0.00, 42, 'MEDIA', 1, 42,
 ST_SetSRID(ST_MakePoint(-46.48200, -23.55800), 4326)::geography,  -- escola, 1,24 km
 ST_SetSRID(ST_MakePoint(-46.46850, -23.55650), 4326)::geography,
 '08280460', 'Rua da Escola', 'Cidade Líder', 'São Paulo', 'SP',
 60, 12.00, 70.0,
 NOW() - INTERVAL '12 hours', NOW() + INTERVAL '4 days',
 NOW() - INTERVAL '12 hours', NOW() - INTERVAL '3 hours', NULL, 0),

-- ===== TRIBO ===== (declaram complexidade: não movem objeto)

('dddddddd-0000-0000-0000-000000000904',
 'bbbbbbbb-0000-0000-0000-000000000901',
 NULL,
 'TRIBO',
 'Mutirão de limpeza da praça',
 'Sábado de manhã. Levar luva e saco de lixo; a subprefeitura recolhe no fim do dia. '
 'Quanto mais gente, mais rápido termina.',
 'ABERTA',
 114, 0.00, 38, 'MEDIA', 1, 38,
 ST_SetSRID(ST_MakePoint(-46.47030, -23.56250), 4326)::geography,
 NULL,
 '08280460', 'Praça da Cidade Líder', 'Cidade Líder', 'São Paulo', 'SP',
 100, NULL, NULL,
 NOW() + INTERVAL '2 days', NOW() + INTERVAL '12 days',
 NOW() - INTERVAL '2 days', NULL, NULL, 0),

('dddddddd-0000-0000-0000-000000000906',
 'bbbbbbbb-0000-0000-0000-000000000901',
 NULL,
 'TRIBO',
 'Montar canteiro da horta comunitária',
 'Chegaram as mudas e a terra. Precisamos de gente para montar os canteiros ao lado da escola.',
 'ABERTA',
 114, 0.00, 38, 'MEDIA', 1, 38,
 ST_SetSRID(ST_MakePoint(-46.48200, -23.55800), 4326)::geography,
 NULL,
 '08280460', 'Rua da Escola', 'Cidade Líder', 'São Paulo', 'SP',
 100, NULL, NULL,
 NOW() + INTERVAL '4 days', NOW() + INTERVAL '18 days',
 NOW() - INTERVAL '1 day', NULL, NULL, 0),

-- ===== AJUDA =====

('dddddddd-0000-0000-0000-000000000905',
 'bbbbbbbb-0000-0000-0000-000000000902',
 NULL,
 'AJUDA',
 'Acompanhar dona Marlene à UBS',
 'Consulta marcada de manhã. Ela anda devagar e não quer ir sozinha — o trajeto é curto, '
 'mas tem subida.',
 'ABERTA',
 60, 0.00, 20, 'LEVE', 1, 0,
 ST_SetSRID(ST_MakePoint(-46.46900, -23.54950), 4326)::geography,  -- UBS, 876 m
 NULL,
 '08280460', 'Rua Antônio Maria Bessa', 'Cidade Líder', 'São Paulo', 'SP',
 80, NULL, NULL,
 NOW() + INTERVAL '1 day', NOW() + INTERVAL '7 days',
 NOW() - INTERVAL '8 hours', NULL, NULL, 0);

-- -----------------------------------------------------------------------
-- Carteiras. Os saldos abaixo são a PROJEÇÃO; o ledger a seguir é a verdade.
-- Os dois têm de fechar, ou o endpoint de reconciliação acusa divergência no seed.
-- -----------------------------------------------------------------------
INSERT INTO carteira (id, usuario_id, saldo_brl, saldo_tokens, versao) VALUES
    ('eeeeeeee-0000-0000-0000-000000000901', 'bbbbbbbb-0000-0000-0000-000000000901', 0.00, 124, 3),
    ('eeeeeeee-0000-0000-0000-000000000902', 'bbbbbbbb-0000-0000-0000-000000000902', 0.00,  42, 2),
    ('eeeeeeee-0000-0000-0000-000000000903', 'bbbbbbbb-0000-0000-0000-000000000903', 0.00,  95, 3);

-- -----------------------------------------------------------------------
-- Lançamentos — append-only, e aqui eles carregam DUAS invariantes diferentes:
--
--   1. Reconciliação: por carteira, SUM(±valor_tokens) = saldo_tokens acima.
--      renan   200 − 38 − 38 = 124 ✓
--      marlene  80 − 38      =  42 ✓
--      jonas   100 + 37 − 42 =  95 ✓
--
--   2. Conservação do TOKEN: os potes das missões TRIBO/COLETA NÃO são cunhados —
--      saíram de carteira, por débito FINANCIAMENTO_TRIBO. Débitos de financiamento
--      38 + 38 + 38 + 42 = 156, e a soma dos potes (M3 38 + M4 38 + M6 38 + M8 42)
--      é 156. Sem esse pareamento o seed nasceria com tokens do nada, e a
--      demonstração da conservação viraria mentira — a reconciliação continuaria
--      respondendo integro=true, porque ela mede a invariante 1, não a 2.
--
-- O crédito BONUS é o bootstrap: em produção o token entra por recompensa, mas um
-- banco recém-criado não tem histórico de onde tirá-lo.
-- -----------------------------------------------------------------------
INSERT INTO lancamento (id, carteira_id, sinal, motivo, valor_brl, valor_tokens,
                        missao_id, contraparte_carteira_id, chave_idempotencia,
                        saldo_apos_brl, saldo_apos_tokens, criado_em)
VALUES
    -- renan
    ('ffffffff-0000-0000-0000-000000000901',
     'eeeeeeee-0000-0000-0000-000000000901',
     'CREDITO', 'BONUS', 0.00, 200, NULL, NULL, 'seed-cl-renan-bonus',
     0.00, 200, NOW() - INTERVAL '30 days'),

    ('ffffffff-0000-0000-0000-000000000902',
     'eeeeeeee-0000-0000-0000-000000000901',
     'DEBITO', 'FINANCIAMENTO_TRIBO', 0.00, 38,
     'dddddddd-0000-0000-0000-000000000904', NULL, 'seed-cl-renan-fin-m4',
     0.00, 162, NOW() - INTERVAL '2 days'),

    ('ffffffff-0000-0000-0000-000000000903',
     'eeeeeeee-0000-0000-0000-000000000901',
     'DEBITO', 'FINANCIAMENTO_TRIBO', 0.00, 38,
     'dddddddd-0000-0000-0000-000000000906', NULL, 'seed-cl-renan-fin-m6',
     0.00, 124, NOW() - INTERVAL '1 day'),

    -- marlene
    ('ffffffff-0000-0000-0000-000000000904',
     'eeeeeeee-0000-0000-0000-000000000902',
     'CREDITO', 'BONUS', 0.00, 80, NULL, NULL, 'seed-cl-marlene-bonus',
     0.00, 80, NOW() - INTERVAL '20 days'),

    ('ffffffff-0000-0000-0000-000000000905',
     'eeeeeeee-0000-0000-0000-000000000902',
     'DEBITO', 'FINANCIAMENTO_TRIBO', 0.00, 38,
     'dddddddd-0000-0000-0000-000000000903', NULL, 'seed-cl-marlene-fin-m3',
     0.00, 42, NOW() - INTERVAL '1 day'),

    -- jonas
    ('ffffffff-0000-0000-0000-000000000906',
     'eeeeeeee-0000-0000-0000-000000000903',
     'CREDITO', 'BONUS', 0.00, 100, NULL, NULL, 'seed-cl-jonas-bonus',
     0.00, 100, NOW() - INTERVAL '35 days'),

    ('ffffffff-0000-0000-0000-000000000907',
     'eeeeeeee-0000-0000-0000-000000000903',
     'CREDITO', 'RECOMPENSA_MISSAO', 0.00, 37,
     'dddddddd-0000-0000-0000-000000000907', NULL, 'seed-cl-jonas-m7',
     0.00, 137, NOW() - INTERVAL '4 days'),

    ('ffffffff-0000-0000-0000-000000000908',
     'eeeeeeee-0000-0000-0000-000000000903',
     'DEBITO', 'FINANCIAMENTO_TRIBO', 0.00, 42,
     'dddddddd-0000-0000-0000-000000000908', NULL, 'seed-cl-jonas-fin-m8',
     0.00, 95, NOW() - INTERVAL '12 hours');

-- -----------------------------------------------------------------------
-- Alertas do renan — a aba de notificações não nasce vazia na demonstração.
-- Um lido e dois não lidos, para o contador e o ponto de "não lido" terem o que mostrar.
-- -----------------------------------------------------------------------
INSERT INTO alerta (id, usuario_id, tipo, titulo, corpo, missao_id, lido, criado_em) VALUES
    ('99999999-0000-0000-0000-000000000901',
     'bbbbbbbb-0000-0000-0000-000000000901',
     'MISSAO_PROXIMA',
     'Nova missão a 170 m de você',
     'Uma entrega guardada aqui perto acabou de virar missão da tribo.',
     'dddddddd-0000-0000-0000-000000000901', FALSE, NOW() - INTERVAL '6 hours'),

    ('99999999-0000-0000-0000-000000000902',
     'bbbbbbbb-0000-0000-0000-000000000901',
     'MISSAO_ACEITA',
     'Você aceitou uma coleta',
     'Recolher óleo de cozinha usado na escola. Faça o check-in ao chegar no local.',
     'dddddddd-0000-0000-0000-000000000908', FALSE, NOW() - INTERVAL '3 hours'),

    ('99999999-0000-0000-0000-000000000903',
     'bbbbbbbb-0000-0000-0000-000000000901',
     'FINANCIAMENTO_CONFIRMADO',
     'Seu financiamento entrou no pote',
     '38 tokens foram destinados ao mutirão de limpeza da praça.',
     'dddddddd-0000-0000-0000-000000000904', TRUE, NOW() - INTERVAL '2 days');
