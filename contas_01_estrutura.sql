-- ============================================================
-- CONTAS A PAGAR E A RECEBER - ESTRUTURA
--
-- RODAR NO PROJETO UNIFICADO (kmkystqgpvmzrccxvyaz).
-- Cole o arquivo INTEIRO e rode de uma vez.
--
-- ------------------------------------------------------------
-- O QUE ESTE SCRIPT CRIA
--
--   entidades          fornecedores e clientes
--   contas_bancarias   de onde o dinheiro sai / para onde entra
--   titulos            o boleto: quem, quanto, quando vence, que parcela
--   titulo_rateios     onde o dinheiro pesa: fazenda, atividade,
--                      centro de custo, competencia
--   titulo_baixas      cada pagamento feito (permite baixa parcial)
--
-- ------------------------------------------------------------
-- POR QUE TITULO E RATEIO SAO SEPARADOS
--
-- Copiado do Conag, que separa "Financeiro" de "Gerencial". Um boleto
-- unico pode pertencer a mais de uma fazenda ou atividade. Hoje o app
-- nao consegue representar isso: o lancamento tem UMA fazenda e UMA
-- atividade, entao um boleto dividido vira dois lancamentos que ninguem
-- sabe que eram o mesmo papel.
--
-- ------------------------------------------------------------
-- COMO O DINHEIRO CHEGA NO FINANCEIRO
--
-- REGIME DE CAIXA, como o app ja funciona hoje. O titulo NAO aparece no
-- Financeiro nem nos Resultados enquanto nao for pago. Ao registrar a
-- baixa, um gatilho cria um lancamento_financeiro por rateio, com
-- data = data do pagamento.
--
-- Baixa parcial reparte proporcionalmente: pagar 3.000 de um titulo de
-- 5.000 que e 60% cana e 40% pecuaria gera 1.800 e 1.200.
--
-- Nenhum dos lancamentos que ja existem e tocado. Nenhum relatorio muda.
-- ============================================================


-- ------------------------------------------------------------
-- GUARDA DE PROJETO
-- ------------------------------------------------------------
do $guarda$
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema = 'public' and table_name = 'talhoes_areas') then
    raise exception 'PROJETO ERRADO. Este script e do projeto unificado (kmkystqgpvmzrccxvyaz).';
  end if;
end
$guarda$;


-- ------------------------------------------------------------
-- QUEM PODE EXCLUIR
--
-- is_admin() so olha papel = 'admin'. O proprietario ficava de fora, o
-- que contraria a regra que o Eduardo definiu: excluir e so de admin ou
-- proprietario, em todo o app.
-- ------------------------------------------------------------
create or replace function pode_excluir() returns boolean
language sql security definer set search_path = public stable as $$
  select exists(
    select 1 from profiles
    where id = auth.uid() and ativo = true and papel in ('admin','proprietario')
  );
$$;


-- ------------------------------------------------------------
-- ENTIDADES (fornecedores e clientes)
-- ------------------------------------------------------------
create table if not exists entidades (
  id          bigint generated always as identity primary key,
  nome        text not null,
  documento   text,                       -- CPF ou CNPJ, so digitos
  papel       text not null default 'fornecedor'
                check (papel in ('fornecedor','cliente','ambos')),
  observacao  text,
  ativo       boolean not null default true,
  created_at  timestamptz not null default now(),
  criado_por  text
);

-- Um nome so, sem repetir por causa de maiuscula ou espaco sobrando.
-- Mesma protecao que os centros de custo ganharam depois de duplicarem.
create unique index if not exists uq_entidade_nome
  on entidades (lower(btrim(nome)));


-- ------------------------------------------------------------
-- CONTAS BANCARIAS
-- ------------------------------------------------------------
create table if not exists contas_bancarias (
  id          bigint generated always as identity primary key,
  nome        text not null,              -- "SICOOB 36381 - COCRED EDUARDO"
  banco       text,
  agencia     text,
  conta       text,
  ativo       boolean not null default true,
  created_at  timestamptz not null default now()
);

create unique index if not exists uq_conta_bancaria_nome
  on contas_bancarias (lower(btrim(nome)));


-- ------------------------------------------------------------
-- TITULOS
--
-- 'situacao' e coluna gerada: nao existe como dado solto que possa
-- divergir do valor baixado. Vencido NAO fica aqui - depende da data de
-- hoje e e calculado na consulta.
-- ------------------------------------------------------------
create table if not exists titulos (
  id                bigint generated always as identity primary key,
  tipo              text not null check (tipo in ('pagar','receber')),
  entidade_id       bigint references entidades(id) on delete restrict,
  descricao         text not null,
  documento         text,                 -- numero da nota ou do boleto
  forma_pagamento   text,
  conta_bancaria_id bigint references contas_bancarias(id) on delete set null,

  valor             numeric(12,2) not null check (valor > 0),
  vencimento        date not null,

  -- parcelamento: as parcelas de uma mesma compra compartilham o grupo
  parcela           smallint not null default 1 check (parcela  >= 1),
  parcelas          smallint not null default 1 check (parcelas >= 1),
  grupo             uuid,

  -- previsao: esperado, ainda sem boleto firme
  previsao          boolean not null default false,

  cancelado         boolean not null default false,
  valor_baixado     numeric(12,2) not null default 0 check (valor_baixado >= 0),

  observacao        text,
  created_at        timestamptz not null default now(),
  criado_por        text,
  updated_at        timestamptz,
  updated_by        text,

  constraint parcela_dentro_do_total check (parcela <= parcelas),
  constraint baixa_nao_passa_do_valor check (valor_baixado <= valor),

  situacao text generated always as (
    case when cancelado                 then 'cancelado'
         when valor_baixado >= valor    then 'pago'
         when valor_baixado > 0         then 'parcial'
         else 'aberto' end
  ) stored
);

create index if not exists ix_titulos_vencimento on titulos (vencimento);
create index if not exists ix_titulos_situacao   on titulos (situacao, tipo);
create index if not exists ix_titulos_entidade   on titulos (entidade_id);
create index if not exists ix_titulos_grupo      on titulos (grupo);


-- ------------------------------------------------------------
-- RATEIOS (o "Gerencial")
--
-- competencia e 'AAAA-MM', o mesmo formato de lancamentos_financeiros.mes.
-- Ela e INDEPENDENTE do vencimento: um boleto que vence em 27/08 pode ser
-- competencia 07/2026. O Conag faz exatamente assim.
-- ------------------------------------------------------------
create table if not exists titulo_rateios (
  id              bigint generated always as identity primary key,
  titulo_id       bigint not null references titulos(id) on delete cascade,
  fazenda_id      bigint references fazendas(id) on delete set null,
  atividade       text not null check (atividade in ('graos','cana','pecuaria','geral')),
  centro_custo_id bigint not null references centros_custo(id) on delete restrict,
  competencia     text not null check (competencia ~ '^[0-9]{4}-[0-9]{2}$'),
  valor           numeric(12,2) not null check (valor > 0),
  talhao_id       bigint references talhoes(id) on delete set null,
  observacao      text
);

create index if not exists ix_rateios_titulo on titulo_rateios (titulo_id);


-- ------------------------------------------------------------
-- BAIXAS (cada pagamento)
--
-- Um titulo pode ter varias: e assim que a baixa parcial funciona.
-- ------------------------------------------------------------
create table if not exists titulo_baixas (
  id                bigint generated always as identity primary key,
  titulo_id         bigint not null references titulos(id) on delete cascade,
  data              date not null,
  valor             numeric(12,2) not null check (valor > 0),
  conta_bancaria_id bigint references contas_bancarias(id) on delete set null,
  observacao        text,
  created_at        timestamptz not null default now(),
  criado_por        text
);

create index if not exists ix_baixas_titulo on titulo_baixas (titulo_id);


-- ------------------------------------------------------------
-- LIGACAO COM O FINANCEIRO
--
-- Colunas novas e anulaveis: os 2.759 lancamentos que ja existem
-- continuam exatamente como estao, com as duas nulas.
-- ------------------------------------------------------------
alter table lancamentos_financeiros
  add column if not exists titulo_baixa_id  bigint references titulo_baixas(id)  on delete cascade,
  add column if not exists titulo_rateio_id bigint references titulo_rateios(id) on delete set null;

create index if not exists ix_lanc_baixa on lancamentos_financeiros (titulo_baixa_id);


-- ============================================================
-- O GATILHO: BAIXA VIRA LANCAMENTO
--
-- Esta e a UNICA implementacao da regra. A tela nao replica isso - ela
-- so insere em titulo_baixas e o banco faz o resto. Duas implementacoes
-- da mesma regra e como a gente perde o controle (foi assim com o custo
-- do insumo aparecendo em dois lugares).
--
-- REPARTICAO PROPORCIONAL
--
-- Baixa de 3.000 num titulo de 5.000 que e 60% cana / 40% pecuaria:
--   cana     = 3000 * 3000/5000 = 1.800,00
--   pecuaria = 3000 * 2000/5000 = 1.200,00
--
-- O ARREDONDAMENTO fecha no ultimo rateio: a soma dos lancamentos e
-- sempre igual ao valor da baixa, ate o centavo. Sem isso, 1/3 de
-- 100,00 em tres rateios geraria 99,99 e o caixa nao bateria.
-- ============================================================

create or replace function baixa_gera_lancamento() returns trigger
language plpgsql security definer set search_path = public as $baixa$
declare
  t            titulos%rowtype;
  r            record;
  n_rateios    int;
  i            int := 0;
  parte        numeric(12,2);
  acumulado    numeric(12,2) := 0;
  tipo_lanc    text;
begin
  select * into t from titulos where id = new.titulo_id;
  if not found then
    raise exception 'Titulo % nao existe.', new.titulo_id;
  end if;

  if t.cancelado then
    raise exception 'Titulo % esta cancelado e nao pode receber baixa.', t.id;
  end if;

  if coalesce(t.valor_baixado,0) + new.valor > t.valor + 0.001 then
    raise exception 'Baixa de % passa do saldo do titulo % (valor %, ja baixado %).',
      new.valor, t.id, t.valor, t.valor_baixado;
  end if;

  select count(*) into n_rateios from titulo_rateios where titulo_id = t.id;
  if n_rateios = 0 then
    raise exception 'Titulo % nao tem rateio. Defina ao menos onde a despesa pesa antes de dar baixa.', t.id;
  end if;

  tipo_lanc := case when t.tipo = 'pagar' then 'despesa' else 'receita' end;

  for r in
    select * from titulo_rateios where titulo_id = t.id order by id
  loop
    i := i + 1;
    if i = n_rateios then
      -- o ultimo absorve a diferenca do arredondamento
      parte := new.valor - acumulado;
    else
      parte := round(new.valor * (r.valor / t.valor), 2);
      acumulado := acumulado + parte;
    end if;

    if parte <> 0 then
      insert into lancamentos_financeiros
        (tipo, atividade, fazenda_id, centro_custo_id, descricao, valor,
         data, mes, fornecedor, observacao, talhao_id, criado_por,
         titulo_baixa_id, titulo_rateio_id)
      values
        (tipo_lanc,
         r.atividade,
         r.fazenda_id,
         r.centro_custo_id,
         t.descricao,
         parte,
         new.data,                         -- REGIME DE CAIXA: a data do pagamento
         to_char(new.data, 'YYYY-MM'),
         (select nome from entidades e where e.id = t.entidade_id),
         nullif(concat_ws(' | ',
           nullif(t.observacao,''),
           nullif(r.observacao,''),
           case when t.parcelas > 1
                then 'parcela ' || t.parcela || '/' || t.parcelas end,
           case when r.competencia <> to_char(new.data,'YYYY-MM')
                then 'competencia ' || r.competencia end), ''),
         r.talhao_id,
         new.criado_por,
         new.id,
         r.id);
    end if;
  end loop;

  update titulos
     set valor_baixado = coalesce(valor_baixado,0) + new.valor,
         updated_at    = now()
   where id = t.id;

  return new;
end
$baixa$;

drop trigger if exists trg_baixa_gera_lancamento on titulo_baixas;
create trigger trg_baixa_gera_lancamento
  after insert on titulo_baixas
  for each row execute function baixa_gera_lancamento();


-- ------------------------------------------------------------
-- DESFAZER A BAIXA
--
-- Apagar a baixa apaga os lancamentos que ela criou (o on delete cascade
-- da coluna cuida disso) e devolve o saldo ao titulo.
-- ------------------------------------------------------------
create or replace function baixa_desfeita() returns trigger
language plpgsql security definer set search_path = public as $desfaz$
begin
  update titulos
     set valor_baixado = greatest(coalesce(valor_baixado,0) - old.valor, 0),
         updated_at    = now()
   where id = old.titulo_id;
  return old;
end
$desfaz$;

drop trigger if exists trg_baixa_desfeita on titulo_baixas;
create trigger trg_baixa_desfeita
  after delete on titulo_baixas
  for each row execute function baixa_desfeita();


-- ------------------------------------------------------------
-- O RATEIO TEM QUE FECHAR COM O TITULO
--
-- Se a soma dos rateios nao bate com o valor do titulo, a baixa reparte
-- errado e o custo vai para o lugar errado - sem erro nenhum na tela.
-- Melhor barrar na hora de salvar.
-- ------------------------------------------------------------
create or replace function rateio_tem_que_fechar() returns trigger
language plpgsql security definer set search_path = public as $fecha$
declare
  id_titulo bigint := coalesce(new.titulo_id, old.titulo_id);
  soma      numeric(12,2);
  total     numeric(12,2);
begin
  select valor into total from titulos where id = id_titulo;
  if not found then return coalesce(new, old); end if;

  select coalesce(sum(valor),0) into soma from titulo_rateios where titulo_id = id_titulo;

  -- zero rateios e permitido enquanto o titulo esta sendo montado; a
  -- baixa e que exige pelo menos um.
  if soma > 0 and abs(soma - total) > 0.001 then
    raise exception 'A soma dos rateios (%) nao fecha com o valor do titulo (%).', soma, total;
  end if;

  return coalesce(new, old);
end
$fecha$;

drop trigger if exists trg_rateio_fecha on titulo_rateios;
create constraint trigger trg_rateio_fecha
  after insert or update or delete on titulo_rateios
  deferrable initially deferred
  for each row execute function rateio_tem_que_fechar();


-- ============================================================
-- PERMISSOES
--
-- REGRA COMBINADA: quem mexe em contas a pagar precisa das DUAS coisas -
-- ja enxergar o financeiro E ter a chave nova 'contas'. Assim ninguem
-- ganha acesso as contas sem antes ter o financeiro, nem por descuido.
--
-- EXCLUIR e so de admin ou proprietario, em qualquer das tabelas novas.
-- ============================================================

alter table entidades         enable row level security;
alter table contas_bancarias  enable row level security;
alter table titulos           enable row level security;
alter table titulo_rateios    enable row level security;
alter table titulo_baixas     enable row level security;

do $rls$
declare
  ve   text := '(is_admin() or (tem_permissao(''matriz_financeiro'',''visualizar'') and tem_permissao(''contas'',''visualizar'')))';
  edita text := '(is_admin() or (tem_permissao(''matriz_financeiro'',''visualizar'') and tem_permissao(''contas'',''editar'')))';
  t    text;
begin
  foreach t in array array['entidades','contas_bancarias','titulos','titulo_rateios','titulo_baixas'] loop
    execute format('drop policy if exists "ve %1$s"     on %1$I', t);
    execute format('drop policy if exists "cria %1$s"   on %1$I', t);
    execute format('drop policy if exists "altera %1$s" on %1$I', t);
    execute format('drop policy if exists "exclui %1$s" on %1$I', t);

    execute format('create policy "ve %1$s"     on %1$I for select using (%2$s)', t, ve);
    execute format('create policy "cria %1$s"   on %1$I for insert with check (%2$s)', t, edita);
    execute format('create policy "altera %1$s" on %1$I for update using (%2$s) with check (%2$s)', t, edita);
    -- excluir: so admin ou proprietario
    execute format('create policy "exclui %1$s" on %1$I for delete using (pode_excluir())', t);
  end loop;

  raise notice 'RLS aplicada nas cinco tabelas novas.';
end
$rls$;

-- O anon nao toca em nada disso. As tabelas tem CPF/CNPJ de fornecedor e
-- conta bancaria; nao podem ficar legiveis pela chave publica.
do $revoga$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on entidades, contas_bancarias, titulos, titulo_rateios, titulo_baixas from anon;
  end if;
end
$revoga$;


-- ============================================================
-- SEMENTE: FORNECEDORES QUE JA EXISTEM
--
-- 450 lancamentos ja tem fornecedor digitado, em 129 nomes diferentes.
-- Em vez de comecar do zero, viram entidades - assim o autocompletar da
-- tela nova ja nasce com o que voce usa.
-- ============================================================
insert into entidades (nome, papel, criado_por)
select distinct on (lower(btrim(fornecedor)))
       btrim(fornecedor),
       'fornecedor',
       'migracao'
from lancamentos_financeiros
where fornecedor is not null
  and btrim(fornecedor) <> ''
order by lower(btrim(fornecedor)), id
on conflict do nothing;


-- ============================================================
-- CONFERENCIA
-- ============================================================

-- 1. as cinco tabelas existem, com RLS ligada
select c.relname as tabela,
       case when c.relrowsecurity then 'RLS ligada' else '*** RLS DESLIGADA ***' end as seguranca,
       (select count(*) from pg_policies p
         where p.schemaname='public' and p.tablename=c.relname) as politicas
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname='public'
  and c.relname in ('entidades','contas_bancarias','titulos','titulo_rateios','titulo_baixas')
order by 1;

-- 2. so admin/proprietario exclui
select tablename as tabela,
       case when qual like '%pode_excluir%' then 'so admin ou proprietario'
            else '*** EXCLUSAO ABERTA DEMAIS ***' end as exclusao
from pg_policies
where schemaname='public' and cmd='DELETE'
  and tablename in ('entidades','contas_bancarias','titulos','titulo_rateios','titulo_baixas')
order by 1;

-- 3. o financeiro nao mudou
select count(*) as lancamentos, round(sum(valor),2) as total,
       count(*) filter (where titulo_baixa_id is not null) as vindos_de_titulo
from lancamentos_financeiros;

-- 4. fornecedores importados
select count(*) as entidades_criadas from entidades;
