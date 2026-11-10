-- =====================================================================
-- Script  : 05_dados_ficticios.sql
-- Objetivo: massa de teste 100% fictícia. CNPJs e chaves são gerados
--           com DV válido pelo próprio package (nenhuma empresa real).
--           As datas são relativas a SYSDATE, então os vencimentos
--           sempre aparecem "atuais" quando você rodar o script.
-- =====================================================================

set serveroutput on

declare
  -- categorias
  c_escritorio number; c_ti number; c_limpeza number; c_software number;
  -- fornecedores
  f_papelaria number; f_technova number; f_distrib number; f_alfa number;
  l_cnpj_pap varchar2(14); l_cnpj_tec varchar2(14);
  l_cnpj_dis varchar2(14); l_cnpj_alf varchar2(14);
  -- produtos
  p_papel number; p_caneta number; p_note number; p_monitor number;
  p_deterg number; p_desinf number; p_toalha number;
  -- notas
  n1 number; n2 number; n3 number; n4 number;
  l_em1 date := trunc(sysdate) - 10;
  l_em2 date := trunc(sysdate) - 5;
  l_em3 date := trunc(sysdate) - 40;
  l_em4 date := trunc(sysdate) - 2;
  l_erros number;
  l_dup_id number;

  function cnpj(p_base varchar2) return varchar2 is
  begin
    return p_base || pkg_nf_validacao.calcular_dv_cnpj(p_base);
  end;
begin
  -- -------------------------------------------------------------------
  -- Categorias
  -- -------------------------------------------------------------------
  insert into categoria_despesa (nome, tipo) values ('Material de escritório', 'MERCADORIA') returning id into c_escritorio;
  insert into categoria_despesa (nome, tipo) values ('Equipamentos de TI',     'MERCADORIA') returning id into c_ti;
  insert into categoria_despesa (nome, tipo) values ('Material de limpeza',    'MERCADORIA') returning id into c_limpeza;
  insert into categoria_despesa (nome, tipo) values ('Software e licenças',    'SERVICO')    returning id into c_software;
  insert into categoria_despesa (nome, tipo) values ('Frete e transporte',     'SERVICO');
  insert into categoria_despesa (nome, tipo) values ('Despesas gerais',        'DESPESA_GERAL');

  -- -------------------------------------------------------------------
  -- Fornecedores (o último usa o novo CNPJ alfanumérico)
  -- -------------------------------------------------------------------
  l_cnpj_pap := cnpj('112223330001');
  l_cnpj_tec := cnpj('457812960001');
  l_cnpj_dis := cnpj('903456120001');
  l_cnpj_alf := cnpj('12ABC34501DE');

  insert into fornecedor (cnpj, razao_social, nome_fantasia, uf, email, prazo_padrao_dias)
  values (l_cnpj_pap, 'Papelaria Horizonte Ltda', 'Horizonte Papéis', 'SP', 'financeiro@horizonte.exemplo', 30)
  returning id into f_papelaria;

  insert into fornecedor (cnpj, razao_social, nome_fantasia, uf, email, prazo_padrao_dias)
  values (l_cnpj_tec, 'TechNova Equipamentos de Informática S.A.', 'TechNova', 'MG', 'cobranca@technova.exemplo', 30)
  returning id into f_technova;

  insert into fornecedor (cnpj, razao_social, nome_fantasia, uf, email, prazo_padrao_dias)
  values (l_cnpj_dis, 'Distribuidora Rio Claro Ltda', 'Rio Claro Limpeza', 'PR', 'vendas@rioclaro.exemplo', 30)
  returning id into f_distrib;

  insert into fornecedor (cnpj, razao_social, nome_fantasia, uf, email, prazo_padrao_dias)
  values (l_cnpj_alf, 'Alfa Serviços Digitais Ltda', 'Alfa Digital', 'SP', 'contas@alfa.exemplo', 7)
  returning id into f_alfa;

  -- -------------------------------------------------------------------
  -- Produtos e de-para com o código de cada fornecedor
  -- -------------------------------------------------------------------
  insert into produto (codigo, descricao, unidade, ncm, estoque_minimo) values ('P001', 'Papel A4 resma 500 folhas',  'UN', '48025610', 20) returning id into p_papel;
  insert into produto (codigo, descricao, unidade, ncm, estoque_minimo) values ('P002', 'Caneta esferográfica azul',  'UN', '96081000', 50) returning id into p_caneta;
  insert into produto (codigo, descricao, unidade, ncm, estoque_minimo) values ('P003', 'Notebook 15" i7 16GB',       'UN', '84713012', 1)  returning id into p_note;
  insert into produto (codigo, descricao, unidade, ncm, estoque_minimo) values ('P004', 'Monitor LED 24"',            'UN', '85285200', 2)  returning id into p_monitor;
  insert into produto (codigo, descricao, unidade, ncm, estoque_minimo) values ('P005', 'Detergente neutro 500ml',    'UN', '34022000', 20) returning id into p_deterg;
  insert into produto (codigo, descricao, unidade, ncm, estoque_minimo) values ('P006', 'Desinfetante 2L',            'UN', '38089419', 10) returning id into p_desinf;
  insert into produto (codigo, descricao, unidade, ncm, estoque_minimo) values ('P007', 'Papel toalha pacote',        'UN', '48182000', 10) returning id into p_toalha;

  insert into produto_fornecedor (produto_id, fornecedor_id, codigo_no_fornecedor, descricao_no_fornecedor, fator_conversao)
  values (p_papel,   f_papelaria, 'PAP-A4-500',  'PAPEL SULFITE A4 75G RESMA 500FLS', 1);
  -- fornecedor vende em CAIXA com 12; a empresa controla em UNIDADE
  insert into produto_fornecedor (produto_id, fornecedor_id, codigo_no_fornecedor, descricao_no_fornecedor, fator_conversao)
  values (p_caneta,  f_papelaria, 'CAN-AZ-CX12', 'CANETA ESF AZUL CX C/12', 12);
  insert into produto_fornecedor (produto_id, fornecedor_id, codigo_no_fornecedor, descricao_no_fornecedor)
  values (p_note,    f_technova,  'NB-I7-16',    'NOTEBOOK 15.6 CORE I7 16GB SSD 512');
  insert into produto_fornecedor (produto_id, fornecedor_id, codigo_no_fornecedor, descricao_no_fornecedor)
  values (p_monitor, f_technova,  'MON-24',      'MONITOR 24 POL FULL HD');
  insert into produto_fornecedor (produto_id, fornecedor_id, codigo_no_fornecedor, descricao_no_fornecedor)
  values (p_deterg,  f_distrib,   'DET500',      'DETERGENTE NEUTRO 500ML');
  insert into produto_fornecedor (produto_id, fornecedor_id, codigo_no_fornecedor, descricao_no_fornecedor)
  values (p_desinf,  f_distrib,   'DESIN2L',     'DESINFETANTE LAVANDA 2L');
  insert into produto_fornecedor (produto_id, fornecedor_id, codigo_no_fornecedor, descricao_no_fornecedor)
  values (p_toalha,  f_distrib,   'PTOALHA',     'PAPEL TOALHA INTERFOLHA PCT');

  -- -------------------------------------------------------------------
  -- NF 1 - Papelaria: correta, vai ser aprovada (gera estoque)
  -- -------------------------------------------------------------------
  insert into nota_fiscal (fornecedor_id, categoria_id, chave_acesso, serie, numero, data_emissao,
                           natureza_operacao, valor_produtos, valor_frete, valor_total, status)
  values (f_papelaria, c_escritorio,
          pkg_nf_validacao.montar_chave('SP', l_em1, l_cnpj_pap, '55', 1, 1520),
          1, 1520, l_em1, 'Venda de mercadoria', 451.50, 25.00, 476.50, 'RASCUNHO')
  returning id into n1;

  insert into nf_item (nota_id, nr_item, codigo_produto, descricao, ncm, cfop, unidade, quantidade, valor_unitario, valor_total)
  values (n1, 1, 'PAP-A4-500', 'PAPEL SULFITE A4 75G RESMA 500FLS', '48025610', '5102', 'UN', 10, 32.90, 329.00);
  insert into nf_item (nota_id, nr_item, codigo_produto, descricao, ncm, cfop, unidade, quantidade, valor_unitario, valor_total)
  values (n1, 2, 'CAN-AZ-CX12', 'CANETA ESF AZUL CX C/12', '96081000', '5102', 'CX', 5, 24.50, 122.50);

  insert into nf_imposto (nota_id, tipo, base_calculo, aliquota, valor) values (n1, 'ICMS', 451.50, 18, 81.27);
  insert into nf_duplicata (nota_id, numero_parcela, data_vencimento, valor) values (n1, 1, l_em1 + 30, 476.50);

  -- -------------------------------------------------------------------
  -- NF 2 - TechNova: 3 parcelas, desconto e IPI (somam no total)
  -- -------------------------------------------------------------------
  insert into nota_fiscal (fornecedor_id, categoria_id, chave_acesso, serie, numero, data_emissao,
                           natureza_operacao, valor_produtos, valor_desconto, valor_total, status)
  values (f_technova, c_ti,
          pkg_nf_validacao.montar_chave('MG', l_em2, l_cnpj_tec, '55', 2, 88231),
          2, 88231, l_em2, 'Venda de mercadoria', 11680.00, 180.00, 12075.00, 'RASCUNHO')
  returning id into n2;

  insert into nf_item (nota_id, nr_item, codigo_produto, descricao, ncm, cfop, unidade, quantidade, valor_unitario, valor_total)
  values (n2, 1, 'NB-I7-16', 'NOTEBOOK 15.6 CORE I7 16GB SSD 512', '84713012', '6102', 'UN', 2, 4590.00, 9180.00);
  insert into nf_item (nota_id, nr_item, codigo_produto, descricao, ncm, cfop, unidade, quantidade, valor_unitario, valor_total)
  values (n2, 2, 'MON-24', 'MONITOR 24 POL FULL HD', '85285200', '6102', 'UN', 2, 1250.00, 2500.00);

  insert into nf_imposto (nota_id, tipo, base_calculo, aliquota, valor) values (n2, 'IPI',  11500.00, 5, 575.00);
  insert into nf_imposto (nota_id, tipo, base_calculo, aliquota, valor) values (n2, 'ICMS', 11500.00, 12, 1380.00);

  insert into nf_duplicata (nota_id, numero_parcela, data_vencimento, valor) values (n2, 1, l_em2 + 30, 4025.00);
  insert into nf_duplicata (nota_id, numero_parcela, data_vencimento, valor) values (n2, 2, l_em2 + 60, 4025.00);
  insert into nf_duplicata (nota_id, numero_parcela, data_vencimento, valor) values (n2, 3, l_em2 + 90, 4025.00);

  -- -------------------------------------------------------------------
  -- NF 3 - Distribuidora: "lida pela IA" com erro proposital
  --        (IA leu a duplicata como 980,00 em vez de 890,00)
  -- -------------------------------------------------------------------
  insert into nota_fiscal (fornecedor_id, categoria_id, chave_acesso, serie, numero, data_emissao,
                           natureza_operacao, valor_produtos, valor_total, status, origem)
  values (f_distrib, c_limpeza,
          pkg_nf_validacao.montar_chave('PR', l_em3, l_cnpj_dis, '55', 1, 4410),
          1, 4410, l_em3, 'Venda de mercadoria', 890.00, 890.00, 'RASCUNHO', 'IA')
  returning id into n3;

  insert into nf_item (nota_id, nr_item, codigo_produto, descricao, unidade, quantidade, valor_unitario, valor_total)
  values (n3, 1, 'DET500',  'DETERGENTE NEUTRO 500ML',     'UN', 50, 4.80, 240.00);
  insert into nf_item (nota_id, nr_item, codigo_produto, descricao, unidade, quantidade, valor_unitario, valor_total)
  values (n3, 2, 'DESIN2L', 'DESINFETANTE LAVANDA 2L',     'UN', 40, 9.50, 380.00);
  insert into nf_item (nota_id, nr_item, codigo_produto, descricao, unidade, quantidade, valor_unitario, valor_total)
  values (n3, 3, 'PTOALHA', 'PAPEL TOALHA INTERFOLHA PCT', 'UN', 30, 9.00, 270.00);

  insert into nf_duplicata (nota_id, numero_parcela, data_vencimento, valor) values (n3, 1, l_em3 + 30, 980.00);

  -- -------------------------------------------------------------------
  -- NF 4 - Alfa (CNPJ alfanumérico): serviço, não gera estoque, vence em 5 dias
  -- -------------------------------------------------------------------
  insert into nota_fiscal (fornecedor_id, categoria_id, chave_acesso, serie, numero, data_emissao,
                           natureza_operacao, valor_produtos, valor_total, status)
  values (f_alfa, c_software,
          pkg_nf_validacao.montar_chave('SP', l_em4, l_cnpj_alf, '55', 1, 312),
          1, 312, l_em4, 'Licenciamento de software', 2400.00, 2400.00, 'RASCUNHO')
  returning id into n4;

  insert into nf_item (nota_id, nr_item, codigo_produto, descricao, unidade, quantidade, valor_unitario, valor_total)
  values (n4, 1, 'LIC-ERP-ANUAL', 'LICENCA ANUAL SISTEMA DE GESTAO', 'UN', 1, 2400.00, 2400.00);

  insert into nf_duplicata (nota_id, numero_parcela, data_vencimento, valor) values (n4, 1, trunc(sysdate) + 5, 2400.00);

  -- -------------------------------------------------------------------
  -- Fluxo: revisão -> aprovação -> estoque -> pagamento -> saída
  -- -------------------------------------------------------------------
  pkg_nf_processo.aprovar_nota(n1);
  pkg_nf_processo.aprovar_nota(n2);
  pkg_nf_processo.aprovar_nota(n4);

  -- NF 3 fica em revisão com a inconsistência registrada
  pkg_nf_processo.enviar_para_revisao(n3);
  select count(*) into l_erros from nf_inconsistencia where nota_id = n3 and severidade = 'ERRO';
  dbms_output.put_line('NF 4410 em revisão com ' || l_erros || ' erro(s).');

  -- paga a 1ª parcela da TechNova antecipadamente via PIX
  select id into l_dup_id from nf_duplicata where nota_id = n2 and numero_parcela = 1;
  pkg_nf_processo.registrar_pagamento(l_dup_id, trunc(sysdate), null, 'PIX');

  -- consumo interno de papel
  pkg_nf_processo.registrar_saida(p_papel, 3, 'Requisição do setor financeiro');

  commit;
  dbms_output.put_line('Dados fictícios carregados com sucesso.');
end;
/
