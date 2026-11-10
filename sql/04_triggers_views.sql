-- =====================================================================
-- Script  : 04_triggers_views.sql
-- Objetivo: normalização/auditoria via triggers e views para o APEX
-- =====================================================================

-- ---------------------------------------------------------------------
-- TRIGGERS
-- ---------------------------------------------------------------------

create or replace trigger fornecedor_biu
before insert or update on fornecedor
for each row
begin
  :new.cnpj := pkg_nf_validacao.limpar(:new.cnpj);
  :new.uf   := upper(:new.uf);

  if not pkg_nf_validacao.cnpj_valido(:new.cnpj) then
    raise_application_error(-20100,
      'CNPJ inválido: ' || pkg_nf_validacao.formatar_cnpj(:new.cnpj));
  end if;

  if inserting then
    :new.criado_por := pkg_nf_processo.usuario_atual;
  else
    :new.atualizado_em  := systimestamp;
    :new.atualizado_por := pkg_nf_processo.usuario_atual;
  end if;
end;
/

-- A chave NÃO é bloqueada aqui: se a IA ler errado, a nota precisa ser
-- gravada mesmo assim para aparecer na tela de revisão com a inconsistência.
create or replace trigger nota_fiscal_biu
before insert or update on nota_fiscal
for each row
begin
  :new.chave_acesso := pkg_nf_validacao.limpar(:new.chave_acesso);

  if inserting then
    :new.criado_por := pkg_nf_processo.usuario_atual;
  else
    :new.atualizado_em  := systimestamp;
    :new.atualizado_por := pkg_nf_processo.usuario_atual;
  end if;
end;
/

create or replace trigger nf_duplicata_biu
before insert or update on nf_duplicata
for each row
begin
  if inserting then
    :new.criado_por := pkg_nf_processo.usuario_atual;
  else
    :new.atualizado_em  := systimestamp;
    :new.atualizado_por := pkg_nf_processo.usuario_atual;
  end if;
end;
/

create or replace trigger estoque_movimento_bi
before insert on estoque_movimento
for each row
begin
  :new.criado_por := pkg_nf_processo.usuario_atual;
end;
/

-- Kardex é imutável: correção se faz com novo movimento (ajuste/estorno)
create or replace trigger estoque_movimento_bud
before update or delete on estoque_movimento
begin
  raise_application_error(-20101,
    'Movimentos de estoque não podem ser alterados ou excluídos. Use ajuste ou estorno.');
end;
/

create or replace trigger nf_documento_bi
before insert on nf_documento
for each row
begin
  :new.enviado_por   := pkg_nf_processo.usuario_atual;
  :new.tamanho_bytes := dbms_lob.getlength(:new.imagem);
end;
/

-- ---------------------------------------------------------------------
-- VIEWS
-- ---------------------------------------------------------------------

-- Contas a pagar: parcelas em aberto. CONFIRMADA = 'N' são notas ainda em
-- revisão (entram na previsão de caixa, mas não estão liberadas para pagamento).
create or replace view vw_contas_a_pagar as
select d.id                                     as duplicata_id,
       n.id                                     as nota_id,
       n.numero                                 as numero_nota,
       n.serie,
       f.razao_social                           as fornecedor,
       pkg_nf_validacao.formatar_cnpj(f.cnpj)   as cnpj,
       c.nome                                   as categoria,
       d.numero_parcela,
       d.data_vencimento,
       d.valor,
       d.data_vencimento - trunc(sysdate)       as dias_para_vencer,
       case
         when d.data_vencimento <  trunc(sysdate)     then 'VENCIDA'
         when d.data_vencimento <= trunc(sysdate) + 7 then 'VENCE_EM_7_DIAS'
         else 'A_VENCER'
       end                                      as situacao,
       case when n.status = 'APROVADA' then 'S' else 'N' end as confirmada
  from nf_duplicata      d
  join nota_fiscal       n on n.id = d.nota_id
  join fornecedor        f on f.id = n.fornecedor_id
  join categoria_despesa c on c.id = n.categoria_id
 where d.status = 'ABERTA'
   and n.status in ('EM_REVISAO', 'APROVADA');

-- Saldo de estoque com custo médio simplificado
-- (média ponderada das entradas líquidas de estorno).
create or replace view vw_estoque_saldo as
with mov as (
  select produto_id,
         sum(case when tipo in ('ENTRADA', 'AJUSTE_MAIS') then quantidade
                  else -quantidade end)                                   as saldo,
         sum(case when tipo = 'ENTRADA' then quantidade * custo_unitario
                  when tipo = 'ESTORNO' then -quantidade * custo_unitario
                  else 0 end)                                              as valor_entradas,
         sum(case when tipo = 'ENTRADA' then quantidade
                  when tipo = 'ESTORNO' then -quantidade
                  else 0 end)                                              as qtd_entradas,
         max(case when tipo = 'ENTRADA' then data_movimento end)           as ultima_entrada
    from estoque_movimento
   group by produto_id
)
select p.id                                                  as produto_id,
       p.codigo,
       p.descricao,
       p.unidade,
       p.estoque_minimo,
       nvl(m.saldo, 0)                                       as saldo,
       round(m.valor_entradas / nullif(m.qtd_entradas, 0), 4) as custo_medio,
       round(nvl(m.saldo, 0) * m.valor_entradas / nullif(m.qtd_entradas, 0), 2) as valor_em_estoque,
       case when nvl(m.saldo, 0) <= p.estoque_minimo then 'S' else 'N' end       as abaixo_minimo,
       m.ultima_entrada
  from produto p
  left join mov m on m.produto_id = p.id
 where p.ativo = 'S';

-- Despesas por mês e categoria (notas aprovadas)
create or replace view vw_despesas_mensais as
select trunc(n.data_emissao, 'MM') as mes,
       c.nome                      as categoria,
       c.tipo                      as tipo_categoria,
       count(*)                    as qtd_notas,
       sum(n.valor_total)          as valor_total
  from nota_fiscal       n
  join categoria_despesa c on c.id = n.categoria_id
 where n.status = 'APROVADA'
 group by trunc(n.data_emissao, 'MM'), c.nome, c.tipo;
