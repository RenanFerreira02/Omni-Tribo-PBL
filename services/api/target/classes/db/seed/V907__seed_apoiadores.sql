-- =============================================================================
-- V907 — Apoiadores do bairro e as duas pessoas notificáveis (perfis dev e test)
--
-- Substitui a V904 e a V905, apagadas junto com a extensão logística (ADR 0031).
-- O que aquelas duas tinham de LOGÍSTICA morreu com elas: o ponto de custódia
-- lotado, as encomendas que o ocupavam e o casamento do slug com o cabeçalho
-- X-Transportadora do webhook.
--
-- O que sobreviveu está aqui, e sobreviveu porque nunca foi sobre logística:
--
--   1. Os APOIADORES. A carteira de patrocinador é o único ponto de emissão de
--      token do sistema (APORTE_PATROCINADOR, ADR 0024). Sem uma linha semeada,
--      dev e test nascem sem nenhuma fonte de token e a demonstração do ciclo
--      "aporte → pote → executor → resgate" não tem de onde começar.
--
--   2. FERNANDA e GUSTAVO. A V902 deixou a Alice com NOTIFICACAO revogada e o Bob
--      sem decisão nenhuma — bom para provar que não notificamos quem recusou,
--      inútil para provar que notificamos quem aceitou. Os dois são o par
--      controlado: mesma tribo, mesmos consentimentos vigentes, e a ÚNICA variável
--      diferente é o nível (400 xp → 3 contra 0 xp → 1). Sem esse par, um teste de
--      "não notifica quem não pode aceitar" passaria por acidente.
--
-- Faixa 900+ pela razão de sempre, e aqui ela é dupla: garante que roda depois de
-- todo o schema E depois dos outros seeds, o que a seção 4 exige.
-- =============================================================================

-- -----------------------------------------------------------------------
-- 1. Os titulares das carteiras de apoio.
--
-- Status INATIVO é a trava, e é o mesmo molde do usuário-sistema: o
-- AutenticacaoService recusa qualquer status diferente de ATIVO, então nenhuma
-- senha autentica estas contas e nenhum token é emitido para elas. O senha_hash
-- não tem forma de Argon2 e por isso não casa com nada; a coluna é NOT NULL e
-- precisa de algum valor.
--
-- tribo_id NULL: apoiador não pertence a bairro nenhum. Até a V28 isso o impedia
-- de financiar qualquer missão, porque FinanciamentoService exigia afiliação —
-- quem financiava por ele era a conversão do webhook. Sem o webhook, é o próprio
-- apoiador que financia, e a ausência de tribo virou o desvio explícito de
-- autorização em vez de um caminho separado. Ver ADR 0031 §4.
--
-- DOIS apoiadores, um por perfil, porque este seed roda em dev E em test e as
-- duas suítes não devem disputar o mesmo saldo.
-- -----------------------------------------------------------------------
INSERT INTO usuario (id, nome, email, senha_hash, handle, papel, status, xp, nivel)
VALUES ('bbbbbbbb-0000-0000-0000-000000000950',
        'Apoiador Bairro Dev',
        'apoiador@bairro-dev.local',
        'CONTA-DE-APOIADOR-SEM-SENHA',
        'apoiador_dev',
        'PATROCINADOR',
        'INATIVO',
        0,
        1),
       ('bbbbbbbb-0000-0000-0000-000000000951',
        'Apoiador Bairro Teste',
        'apoiador@bairro-teste.local',
        'CONTA-DE-APOIADOR-SEM-SENHA',
        'apoiador_teste',
        'PATROCINADOR',
        'INATIVO',
        0,
        1);

INSERT INTO patrocinador (id, usuario_id, slug, nome, ativo, criado_em)
VALUES ('77777777-0000-0000-0000-000000000950',
        'bbbbbbbb-0000-0000-0000-000000000950',
        'apoiador-dev',
        'Apoiador Bairro Dev',
        TRUE,
        NOW()),
       ('77777777-0000-0000-0000-000000000951',
        'bbbbbbbb-0000-0000-0000-000000000951',
        'apoiador-teste',
        'Apoiador Bairro Teste',
        TRUE,
        NOW());

-- -----------------------------------------------------------------------
-- 2. Carteira e aporte.
--
-- O par carteira + lançamento é OBRIGATORIAMENTE coerente, não decorativo:
-- MigracaoTest.soma_do_ledger_igual_ao_saldo_de_cada_carteira_semeada varre TODA
-- carteira e exige que a soma do ledger bata com saldo_tokens. Semear 5.000 sem
-- lançamento reprovaria o teste — e reprovaria com razão, porque saldo positivo
-- sem origem é a corrupção mais grave que a reconciliação existe para achar.
--
-- APORTE_PATROCINADOR é o único motivo que credita sem debitar contraparte. Aqui
-- ele representa o aporte que, em produção, entra pelo endpoint ADMIN.
-- -----------------------------------------------------------------------
INSERT INTO carteira (id, usuario_id, saldo_brl, saldo_tokens, versao) VALUES
    ('eeeeeeee-0000-0000-0000-000000000950',
     'bbbbbbbb-0000-0000-0000-000000000950',
     0.00, 5000, 1),
    ('eeeeeeee-0000-0000-0000-000000000951',
     'bbbbbbbb-0000-0000-0000-000000000951',
     0.00, 5000, 1);

INSERT INTO lancamento (id, carteira_id, sinal, motivo, valor_brl, valor_tokens,
                        missao_id, contraparte_carteira_id, chave_idempotencia,
                        saldo_apos_brl, saldo_apos_tokens, criado_em)
VALUES
    ('ffffffff-0000-0000-0000-000000000950',
     'eeeeeeee-0000-0000-0000-000000000950',
     'CREDITO', 'APORTE_PATROCINADOR', 0.00, 5000,
     NULL, NULL,
     'seed-aporte-apoiador-dev',
     0.00, 5000,
     NOW()),
    ('ffffffff-0000-0000-0000-000000000951',
     'eeeeeeee-0000-0000-0000-000000000951',
     'CREDITO', 'APORTE_PATROCINADOR', 0.00, 5000,
     NULL, NULL,
     'seed-aporte-apoiador-teste',
     0.00, 5000,
     NOW());

-- -----------------------------------------------------------------------
-- 3. Fernanda e Gustavo — o par que separa consentimento de reputação.
--
-- Vinham da V904. Continuam aqui porque nada neles era logístico: são a fixture
-- do fan-out de notificação, que sobrevive à remoção — o alerta de missão nova
-- para a tribo continua existindo.
--
-- Fernanda: Tribo Pinheiros, xp 400 → nível 3 pela curva de RegraNivel.
-- Gustavo: mesma tribo, mesmos consentimentos, xp 0 → nível 1. A única variável
-- diferente é o nível, e é isso que faz dele um controle e não mais uma linha.
-- -----------------------------------------------------------------------
INSERT INTO usuario (id, nome, email, senha_hash, handle, tribo_id, xp, nivel,
                     streak, rating, papel, status, criado_em, atualizado_em, versao) VALUES
    ('bbbbbbbb-0000-0000-0000-000000000904',
     'Fernanda Lima',
     'fernanda@omnitribo.dev',
     '{bcrypt}' || crypt('Senha@123', gen_salt('bf', 10)),
     'fernanda',
     'aaaaaaaa-0000-0000-0000-000000000001',
     400, 3, 4, 4.9, 'USUARIO', 'ATIVO', NOW(), NOW(), 0),

    ('bbbbbbbb-0000-0000-0000-000000000905',
     'Gustavo Nunes',
     'gustavo@omnitribo.dev',
     '{bcrypt}' || crypt('Senha@123', gen_salt('bf', 10)),
     'gustavo',
     'aaaaaaaa-0000-0000-0000-000000000001',
     0, 1, 0, 0.0, 'USUARIO', 'ATIVO', NOW(), NOW(), 0);

INSERT INTO carteira (id, usuario_id, saldo_brl, saldo_tokens, versao) VALUES
    ('eeeeeeee-0000-0000-0000-000000000904',
     'bbbbbbbb-0000-0000-0000-000000000904', 0.00, 0, 0),
    ('eeeeeeee-0000-0000-0000-000000000905',
     'bbbbbbbb-0000-0000-0000-000000000905', 0.00, 0, 0);

-- Os consentimentos vigentes. Concedidos em datas distintas de propósito: a
-- consulta resolve o estado atual por DISTINCT ON (tipo) ORDER BY criado_em DESC,
-- e datas iguais tornariam o teste cego a um erro de ordenação.
INSERT INTO consentimento (id, usuario_id, tipo, concedido, versao_texto, ip, criado_em) VALUES
    ('dddddddd-0904-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000904',
     'TERMOS',      TRUE, '2026-08-01', NULL, NOW() - INTERVAL '40 days'),
    ('dddddddd-0904-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000904',
     'LOCALIZACAO', TRUE, '2026-08-01', NULL, NOW() - INTERVAL '40 days'),
    ('dddddddd-0904-0000-0000-000000000003', 'bbbbbbbb-0000-0000-0000-000000000904',
     'NOTIFICACAO', TRUE, '2026-08-01', NULL, NOW() - INTERVAL '35 days'),

    ('dddddddd-0905-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000905',
     'TERMOS',      TRUE, '2026-08-01', NULL, NOW() - INTERVAL '10 days'),
    ('dddddddd-0905-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000905',
     'LOCALIZACAO', TRUE, '2026-08-01', NULL, NOW() - INTERVAL '10 days'),
    ('dddddddd-0905-0000-0000-000000000003', 'bbbbbbbb-0000-0000-0000-000000000905',
     'NOTIFICACAO', TRUE, '2026-08-01', NULL, NOW() - INTERVAL '10 days');

-- -----------------------------------------------------------------------
-- 4. Backfill de missao.fonte_pote — a segunda passada.
--
-- A V23 já fez este mesmo UPDATE, e ele NÃO basta: os seeds rodam DEPOIS dela
-- (faixa 900+ é a última) e inserem missões com lista de colunas explícita, sem
-- fonte_pote. Toda missão TRIBO/COLETA semeada pegou o DEFAULT 'CUNHAGEM' e, sem
-- esta correção, a conclusão delas passaria a CUNHAR token enquanto o pote
-- financiado ficaria preso para sempre — quebrando a conservação justamente nas
-- duas categorias onde ela já valia.
--
-- Editar os seeds para incluir a coluna resolveria em clone novo e derrubaria todo
-- banco de dev existente com "Migration checksum mismatch", um erro que o CI nunca
-- reproduz porque lá o banco nasce do zero.
--
-- Idempotente e inócuo em clone novo: nas linhas que a V23 já corrigiu, o UPDATE
-- não muda nada.
-- -----------------------------------------------------------------------
UPDATE missao SET fonte_pote = 'COMUNIDADE'
 WHERE categoria IN ('TRIBO', 'COLETA')
   AND fonte_pote <> 'COMUNIDADE';

-- As ENTREGAs semeadas ficam como CUNHAGEM, que é a verdade histórica: foram
-- criadas quando ENTREGA cunhava na conclusão. Marcá-las como COMUNIDADE faria a
-- conclusão delas falhar com 422 por pote insuficiente — elas não têm pote.
