-- =====================================================================
-- Script  : 03_pkg_nf_processo.sql
-- Objetivo: ciclo de vida da nota (revisão, aprovação, cancelamento),
--           integração com estoque e baixa de pagamentos
-- =====================================================================

create or replace package pkg_nf_processo authid definer as

  -- Usuário do APEX quando houver sessão; senão, o usuário do banco
  function usuario_atual return varchar2;

  -- Saldo atual de um produto (soma do kardex)
  function saldo_produto(p_produto_id in number) return number;

  -- Vincula itens da nota aos produtos internos pelo de-para (PRODUTO_FORNECEDOR).
  -- Retorna quantos itens continuam sem produto.
  function vincular_produtos(p_nota_id in number) return number;

  procedure enviar_para_revisao(p_nota_id in number);

  -- Valida; se não houver ERRO, aprova e dá entrada no estoque (categoria MERCADORIA)
  procedure aprovar_nota(p_nota_id in number);

  procedure rejeitar_nota(p_nota_id in number, p_motivo in varchar2);

  -- Estorna o estoque e cancela as parcelas em aberto
  procedure cancelar_nota(p_nota_id in number, p_motivo in varchar2);

  procedure registrar_pagamento(
    p_duplicata_id    in number,
    p_data_pagamento  in date     default trunc(sysdate),
    p_valor_pago      in number   default null,   -- null = valor da parcela
    p_forma_pagamento in varchar2 default 'BOLETO'
  );

  procedure registrar_saida(
    p_produto_id  in number,
    p_quantidade  in number,
    p_observacao  in varchar2 default null
  );

end pkg_nf_processo;
/

create or replace package body pkg_nf_processo as

  -- -------------------------------------------------------------------
  -- Privadas
  -- -------------------------------------------------------------------

  -- Lê a nota travando a linha: evita duas pessoas aprovando ao mesmo tempo
  function travar_nota(p_nota_id in number) return nota_fiscal%rowtype is
    l_nota nota_fiscal%rowtype;
  begin
    select * into l_nota from nota_fiscal where id = p_nota_id for update;
    return l_nota;
  exception
    when no_data_found then
      raise_application_error(-20010, 'Nota ' || p_nota_id || ' não encontrada.');
  end travar_nota;

  procedure log(p_nota_id in number, p_etapa in varchar2, p_mensagem in varchar2,
                p_nivel in varchar2 default 'INFO') is
  begin
    insert into nf_log (nota_id, etapa, nivel, mensagem)
    values (p_nota_id, p_etapa, p_nivel, p_mensagem);
  end log;

  -- -------------------------------------------------------------------
  -- Públicas
  -- -------------------------------------------------------------------

  function usuario_atual return varchar2 is
  begin
    return coalesce(sys_context('APEX$SESSION', 'APP_USER'), user);
  end usuario_atual;

  function saldo_produto(p_produto_id in number) return number is
    l_saldo number;
  begin
    select nvl(sum(case when tipo in ('ENTRADA', 'AJUSTE_MAIS') then quantidade
                        else -quantidade end), 0)
      into l_saldo
      from estoque_movimento
     where produto_id = p_produto_id;
    return l_saldo;
  end saldo_produto;

  function vincular_produtos(p_nota_id in number) return number is
    l_sem_produto number;
  begin
    update nf_item i
       set i.produto_id = (
             select pf.produto_id
               from produto_fornecedor pf
               join nota_fiscal n on n.fornecedor_id = pf.fornecedor_id
              where n.id = i.nota_id
                and pf.codigo_no_fornecedor = i.codigo_produto)
     where i.nota_id = p_nota_id
       and i.produto_id is null
       and exists (
             select 1
               from produto_fornecedor pf
               join nota_fiscal n on n.fornecedor_id = pf.fornecedor_id
              where n.id = i.nota_id
                and pf.codigo_no_fornecedor = i.codigo_produto);

    select count(*) into l_sem_produto
      from nf_item
     where nota_id = p_nota_id
       and produto_id is null;

    return l_sem_produto;
  end vincular_produtos;

  procedure enviar_para_revisao(p_nota_id in number) is
    l_nota  nota_fiscal%rowtype := travar_nota(p_nota_id);
    l_erros number;
  begin
    if l_nota.status <> 'RASCUNHO' then
      raise_application_error(-20021, 'Só notas em RASCUNHO podem ir para revisão.');
    end if;

    pkg_nf_validacao.validar_nota(p_nota_id, l_erros);

    update nota_fiscal set status = 'EM_REVISAO' where id = p_nota_id;
    log(p_nota_id, 'REVISAO', 'Enviada para revisão com ' || l_erros || ' erro(s).');
  end enviar_para_revisao;

  procedure aprovar_nota(p_nota_id in number) is
    l_nota        nota_fiscal%rowtype := travar_nota(p_nota_id);
    l_tipo_cat    categoria_despesa.tipo%type;
    l_erros       number;
    l_impostos    number;
    l_rateio      number;     -- valor a distribuir no custo dos itens
    l_qtd_estoque number;
    l_custo_item  number;
    l_data_mov    date;
    l_qtd_mov     pls_integer := 0;
  begin
    if l_nota.status not in ('RASCUNHO', 'EM_REVISAO') then
      raise_application_error(-20022,
        'Nota está ' || l_nota.status || ' e não pode ser aprovada.');
    end if;

    -- tenta vincular itens antes de validar
    l_erros := vincular_produtos(p_nota_id);

    pkg_nf_validacao.validar_nota(p_nota_id, l_erros);
    if l_erros > 0 then
      raise_application_error(-20020,
        'Nota possui ' || l_erros || ' inconsistência(s) do tipo ERRO. Corrija antes de aprovar.');
    end if;

    select tipo into l_tipo_cat from categoria_despesa where id = l_nota.categoria_id;
    l_data_mov := nvl(l_nota.data_entrada, trunc(sysdate));

    if l_tipo_cat = 'MERCADORIA' then
      -- Custo de aquisição = valor do item + rateio proporcional de
      -- frete + outras despesas + IPI + ICMS-ST - desconto
      select nvl(sum(valor), 0) into l_impostos
        from nf_imposto
       where nota_id = p_nota_id and tipo in ('IPI', 'ICMS_ST');

      l_rateio := l_nota.valor_frete + l_nota.valor_outras + l_impostos - l_nota.valor_desconto;

      for r in (
        select i.id, i.produto_id, i.quantidade, i.valor_total,
               nvl(pf.fator_conversao, 1) as fator
          from nf_item i
          left join produto_fornecedor pf
            on pf.fornecedor_id        = l_nota.fornecedor_id
           and pf.codigo_no_fornecedor = i.codigo_produto
           and pf.produto_id           = i.produto_id
         where i.nota_id = p_nota_id
         order by i.nr_item
      ) loop
        l_qtd_estoque := r.quantidade * r.fator;   -- ex.: 5 CX x 12 = 60 UN
        l_custo_item  := r.valor_total
                       + case when l_nota.valor_produtos > 0
                              then l_rateio * r.valor_total / l_nota.valor_produtos
                              else 0 end;

        insert into estoque_movimento
          (produto_id, tipo, quantidade, custo_unitario, data_movimento, nf_item_id, observacao)
        values
          (r.produto_id, 'ENTRADA', l_qtd_estoque, round(l_custo_item / l_qtd_estoque, 4),
           l_data_mov, r.id, 'Entrada NF ' || l_nota.numero || '/' || l_nota.serie);

        l_qtd_mov := l_qtd_mov + 1;
      end loop;
    end if;

    update nota_fiscal
       set status       = 'APROVADA',
           data_entrada = l_data_mov,
           aprovado_em  = systimestamp,
           aprovado_por = usuario_atual
     where id = p_nota_id;

    log(p_nota_id, 'APROVACAO', 'Nota aprovada. Movimentos de estoque: ' || l_qtd_mov || '.');
  end aprovar_nota;

  procedure rejeitar_nota(p_nota_id in number, p_motivo in varchar2) is
    l_nota nota_fiscal%rowtype := travar_nota(p_nota_id);
  begin
    if l_nota.status not in ('RASCUNHO', 'EM_REVISAO') then
      raise_application_error(-20023, 'Só notas em rascunho/revisão podem ser rejeitadas.');
    end if;
    if trim(p_motivo) is null then
      raise_application_error(-20024, 'Informe o motivo da rejeição.');
    end if;

    update nota_fiscal
       set status     = 'REJEITADA',
           observacao = substr(observacao || chr(10) || 'Rejeitada: ' || p_motivo, 1, 4000)
     where id = p_nota_id;

    log(p_nota_id, 'REJEICAO', p_motivo);
  end rejeitar_nota;

  procedure cancelar_nota(p_nota_id in number, p_motivo in varchar2) is
    l_nota  nota_fiscal%rowtype := travar_nota(p_nota_id);
    l_pagas number;
  begin
    if l_nota.status = 'CANCELADA' then
      raise_application_error(-20025, 'Nota já está cancelada.');
    end if;
    if trim(p_motivo) is null then
      raise_application_error(-20024, 'Informe o motivo do cancelamento.');
    end if;

    select count(*) into l_pagas
      from nf_duplicata
     where nota_id = p_nota_id and status = 'PAGA';

    if l_pagas > 0 then
      raise_application_error(-20026,
        'Nota possui ' || l_pagas || ' parcela(s) paga(s). Estorne os pagamentos antes.');
    end if;

    -- Estorno de estoque: trava os produtos e confere se ainda há saldo
    for r in (
      select m.id, m.produto_id, m.quantidade, m.custo_unitario, p.descricao
        from estoque_movimento m
        join nf_item i  on i.id = m.nf_item_id
        join produto p  on p.id = m.produto_id
       where i.nota_id = p_nota_id
         and m.tipo = 'ENTRADA'
         and not exists (select 1 from estoque_movimento e
                          where e.movimento_origem_id = m.id)
       order by m.produto_id
         for update of p.id
    ) loop
      if saldo_produto(r.produto_id) < r.quantidade then
        raise_application_error(-20027,
          'Saldo insuficiente para estornar "' || r.descricao
          || '": parte da mercadoria já saiu do estoque.');
      end if;

      insert into estoque_movimento
        (produto_id, tipo, quantidade, custo_unitario, movimento_origem_id, observacao)
      values
        (r.produto_id, 'ESTORNO', r.quantidade, r.custo_unitario, r.id,
         'Cancelamento NF ' || l_nota.numero || ': ' || p_motivo);
    end loop;

    update nf_duplicata set status = 'CANCELADA'
     where nota_id = p_nota_id and status = 'ABERTA';

    update nota_fiscal
       set status     = 'CANCELADA',
           observacao = substr(observacao || chr(10) || 'Cancelada: ' || p_motivo, 1, 4000)
     where id = p_nota_id;

    log(p_nota_id, 'CANCELAMENTO', p_motivo);
  end cancelar_nota;

  procedure registrar_pagamento(
    p_duplicata_id    in number,
    p_data_pagamento  in date     default trunc(sysdate),
    p_valor_pago      in number   default null,
    p_forma_pagamento in varchar2 default 'BOLETO'
  ) is
    l_dup         nf_duplicata%rowtype;
    l_status_nota nota_fiscal.status%type;
  begin
    select * into l_dup from nf_duplicata where id = p_duplicata_id for update;
    select status into l_status_nota from nota_fiscal where id = l_dup.nota_id;

    if l_status_nota <> 'APROVADA' then
      raise_application_error(-20030, 'Só é possível pagar parcelas de notas APROVADAS.');
    end if;
    if l_dup.status <> 'ABERTA' then
      raise_application_error(-20031, 'Parcela não está em aberto (status ' || l_dup.status || ').');
    end if;

    update nf_duplicata
       set status          = 'PAGA',
           data_pagamento  = p_data_pagamento,
           valor_pago      = nvl(p_valor_pago, l_dup.valor),
           forma_pagamento = p_forma_pagamento
     where id = p_duplicata_id;

    log(l_dup.nota_id, 'PAGAMENTO',
        'Parcela ' || l_dup.numero_parcela || ' paga em ' || to_char(p_data_pagamento, 'DD/MM/YYYY'));
  exception
    when no_data_found then
      raise_application_error(-20032, 'Parcela ' || p_duplicata_id || ' não encontrada.');
  end registrar_pagamento;

  procedure registrar_saida(
    p_produto_id  in number,
    p_quantidade  in number,
    p_observacao  in varchar2 default null
  ) is
    l_descricao produto.descricao%type;
    l_saldo     number;
  begin
    if p_quantidade is null or p_quantidade <= 0 then
      raise_application_error(-20040, 'Quantidade deve ser maior que zero.');
    end if;

    -- O FOR UPDATE serializa saídas do mesmo produto: duas sessões
    -- não conseguem consumir o mesmo saldo ao mesmo tempo.
    select descricao into l_descricao from produto where id = p_produto_id for update;

    l_saldo := saldo_produto(p_produto_id);
    if l_saldo < p_quantidade then
      raise_application_error(-20041,
        'Saldo insuficiente de "' || l_descricao || '": disponível ' || l_saldo
        || ', solicitado ' || p_quantidade || '.');
    end if;

    insert into estoque_movimento (produto_id, tipo, quantidade, observacao)
    values (p_produto_id, 'SAIDA', p_quantidade, p_observacao);
  exception
    when no_data_found then
      raise_application_error(-20042, 'Produto ' || p_produto_id || ' não encontrado.');
  end registrar_saida;

end pkg_nf_processo;
/
