-- =====================================================================
-- Script  : 99_remover.sql
-- Objetivo: apaga TODOS os objetos do projeto para recomeçar do zero.
--           Use quando quiser rodar as etapas de novo.
-- =====================================================================

begin
  for v in (select view_name from user_views
             where view_name in ('VW_CONTAS_A_PAGAR','VW_ESTOQUE_SALDO','VW_DESPESAS_MENSAIS')) loop
    execute immediate 'drop view ' || v.view_name;
  end loop;

  for t in (select table_name from user_tables
             where table_name in ('NF_LOG','ESTOQUE_MOVIMENTO','NF_INCONSISTENCIA','NF_IMPOSTO',
                                  'NF_DUPLICATA','NF_ITEM','NOTA_FISCAL','NF_DOCUMENTO',
                                  'PRODUTO_FORNECEDOR','PRODUTO','CATEGORIA_DESPESA','FORNECEDOR')) loop
    execute immediate 'drop table ' || t.table_name || ' cascade constraints purge';
  end loop;

  for p in (select object_name from user_objects
             where object_type = 'PACKAGE'
               and object_name in ('PKG_NF_PROCESSO','PKG_NF_VALIDACAO')) loop
    execute immediate 'drop package ' || p.object_name;
  end loop;
end;
/
