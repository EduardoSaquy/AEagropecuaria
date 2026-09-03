-- ===================================================================
-- AE Pecuária — animais.numero+sexo vira restrição de único de verdade
-- ===================================================================
-- Confirmado em 02/09/2026: não existe (e nunca existiu) restrição de
-- único em animais.numero -- só a lógica do app "garantia" isso, e
-- garantia errado (fundia macho e fêmea que compartilhavam número em
-- vez de criar um animal novo -- corrigido no app em eb9032f). Eduardo
-- confirmou que o rebanho real pode ter o mesmo número em sexos
-- diferentes, então a identidade de verdade é o par número+sexo.
--
-- Esse índice único é a segunda camada: mesmo que a lógica do app
-- tenha algum bug no futuro, o banco recusa duas linhas com o mesmo
-- número+sexo (comparação sem acento de caixa/espaço, igual o app já
-- faz em animalCadastrado()).
--
-- Trava antes de criar: se já existir duplicata de número+sexo hoje
-- (não deveria, mas não custa conferir), aborta em vez de tentar criar
-- um índice que vai falhar de qualquer jeito -- e avisa quantas.
-- ===================================================================

do $$
declare
  dup_count int;
begin
  if not exists (select 1 from information_schema.tables
                 where table_schema='public' and table_name='talhoes_areas') then
    raise exception 'PROJETO ERRADO - este e o banco unificado kmkystqgpvmzrccxvyaz?';
  end if;

  select count(*) into dup_count from (
    select lower(trim(numero)), sexo
      from animais
     where sexo is not null
     group by 1, 2
    having count(*) > 1
  ) x;
  if dup_count > 0 then
    raise exception 'Existem % numero+sexo duplicados em animais -- resolva antes de criar o unique (rode uma consulta filtrando por esses pares antes).', dup_count;
  end if;
end $$;

create unique index if not exists animais_numero_sexo_unique
  on animais (lower(trim(numero)), sexo)
  where sexo is not null;
-- "where sexo is not null" -- animal sem sexo definido (não deveria
-- existir hoje em diante, mas pode ter ficado de importação antiga)
-- não entra na restrição; sem isso, dois animais com o mesmo número e
-- sexo nulo já colidiriam mesmo sem ser o problema que estamos
-- fechando aqui.

select 1::numeric as ordem, 'indice animais_numero_sexo_unique criado' as item,
       case when exists (
         select 1 from pg_indexes
          where schemaname='public' and tablename='animais'
            and indexname='animais_numero_sexo_unique'
       ) then 'sim' else 'nao' end as valor,
       'OK' as situacao;
