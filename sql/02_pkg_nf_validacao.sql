-- =====================================================================
-- Script  : 02_pkg_nf_validacao.sql
-- Objetivo: regras de validação de CNPJ, chave de acesso e da nota
-- =====================================================================

create or replace package pkg_nf_validacao authid definer as

  -- Estrutura da chave de acesso da NF-e (44 posições)
  type t_chave is record (
    codigo_uf        varchar2(2),   -- 01-02  código IBGE da UF
    ano_mes          varchar2(4),   -- 03-06  AAMM da emissão
    cnpj             varchar2(14),  -- 07-20  CNPJ do emitente
    modelo           varchar2(2),   -- 21-22  55 ou 65
    serie            varchar2(3),   -- 23-25
    numero           varchar2(9),   -- 26-34
    tipo_emissao     varchar2(1),   -- 35
    codigo_numerico  varchar2(8),   -- 36-43
    dv               varchar2(1)    -- 44
  );

  -- Remove máscara (pontos, barras, espaços) e coloca em maiúsculas
  function limpar(p_texto in varchar2) return varchar2 deterministic;

  -- CNPJ (numérico ou alfanumérico)
  function calcular_dv_cnpj(p_base in varchar2) return varchar2;
  function cnpj_valido(p_cnpj in varchar2) return boolean;
  function cnpj_valido_sn(p_cnpj in varchar2) return varchar2;   -- 'S'/'N' para usar em SQL
  function formatar_cnpj(p_cnpj in varchar2) return varchar2;

  -- Chave de acesso
  function codigo_uf(p_uf in varchar2) return varchar2;
  function calcular_dv_chave(p_base in varchar2) return varchar2;
  function chave_valida(p_chave in varchar2) return boolean;
  function chave_valida_sn(p_chave in varchar2) return varchar2;
  function decompor_chave(p_chave in varchar2) return t_chave;
  function montar_chave(
    p_uf               in varchar2,
    p_data_emissao     in date,
    p_cnpj             in varchar2,
    p_modelo           in varchar2,
    p_serie            in number,
    p_numero           in number,
    p_tipo_emissao     in varchar2 default '1',
    p_codigo_numerico  in varchar2 default null
  ) return varchar2;

  -- Valida a nota inteira e grava o resultado em NF_INCONSISTENCIA.
  -- p_qtd_erros = quantidade de inconsistências com severidade ERRO.
  procedure validar_nota(p_nota_id in number, p_qtd_erros out number);

end pkg_nf_validacao;
/

create or replace package body pkg_nf_validacao as

  c_tolerancia constant number := 0.05;   -- diferença aceitável por arredondamento

  -- -------------------------------------------------------------------
  -- Privadas
  -- -------------------------------------------------------------------

  -- Valor de cada caractere no cálculo do DV: ASCII - 48.
  -- '0'..'9' => 0..9 | 'A' => 17, 'B' => 18 ... (regra do CNPJ alfanumérico)
  function valor_caractere(p_char in varchar2) return pls_integer is
  begin
    return ascii(p_char) - 48;
  end valor_caractere;

  -- Módulo 11 com pesos 2..9 da direita para a esquerda.
  -- O mesmo algoritmo serve para os DVs do CNPJ e para o DV da chave de acesso.
  function mod11(p_texto in varchar2) return varchar2 is
    l_soma  pls_integer := 0;
    l_peso  pls_integer := 2;
    l_resto pls_integer;
  begin
    for i in reverse 1 .. length(p_texto) loop
      l_soma := l_soma + valor_caractere(substr(p_texto, i, 1)) * l_peso;
      l_peso := case when l_peso = 9 then 2 else l_peso + 1 end;
    end loop;

    l_resto := mod(l_soma, 11);
    return case when l_resto < 2 then '0' else to_char(11 - l_resto) end;
  end mod11;

  procedure registrar(
    p_nota_id    in number,
    p_regra      in varchar2,
    p_severidade in varchar2,
    p_mensagem   in varchar2
  ) is
  begin
    insert into nf_inconsistencia (nota_id, regra, severidade, mensagem)
    values (p_nota_id, p_regra, p_severidade, substr(p_mensagem, 1, 1000));
  end registrar;

  -- -------------------------------------------------------------------
  -- CNPJ
  -- -------------------------------------------------------------------

  function limpar(p_texto in varchar2) return varchar2 deterministic is
  begin
    return upper(regexp_replace(p_texto, '[^0-9A-Za-z]', ''));
  end limpar;

  function calcular_dv_cnpj(p_base in varchar2) return varchar2 is
    l_base varchar2(20) := limpar(p_base);
    l_dv1  varchar2(1);
  begin
    if l_base is null or not regexp_like(l_base, '^[0-9A-Z]{12}$') then
      raise_application_error(-20001, 'Base do CNPJ deve ter 12 caracteres (0-9, A-Z): ' || p_base);
    end if;

    l_dv1 := mod11(l_base);
    return l_dv1 || mod11(l_base || l_dv1);
  end calcular_dv_cnpj;

  function cnpj_valido(p_cnpj in varchar2) return boolean is
    l_cnpj varchar2(20) := limpar(p_cnpj);
  begin
    if l_cnpj is null or not regexp_like(l_cnpj, '^[0-9A-Z]{12}[0-9]{2}$') then
      return false;
    end if;

    -- 00000000000000, 11111111111111 ... passam no cálculo, mas são inválidos
    if replace(l_cnpj, substr(l_cnpj, 1, 1)) is null then
      return false;
    end if;

    return substr(l_cnpj, 13, 2) = calcular_dv_cnpj(substr(l_cnpj, 1, 12));
  end cnpj_valido;

  function cnpj_valido_sn(p_cnpj in varchar2) return varchar2 is
  begin
    return case when cnpj_valido(p_cnpj) then 'S' else 'N' end;
  end cnpj_valido_sn;

  function formatar_cnpj(p_cnpj in varchar2) return varchar2 is
    l_cnpj varchar2(20) := limpar(p_cnpj);
  begin
    if length(l_cnpj) <> 14 then
      return p_cnpj;
    end if;
    return substr(l_cnpj, 1, 2) || '.' || substr(l_cnpj, 3, 3) || '.' ||
           substr(l_cnpj, 6, 3) || '/' || substr(l_cnpj, 9, 4) || '-' ||
           substr(l_cnpj, 13, 2);
  end formatar_cnpj;

  -- -------------------------------------------------------------------
  -- Chave de acesso
  -- -------------------------------------------------------------------

  function codigo_uf(p_uf in varchar2) return varchar2 is
  begin
    return case upper(p_uf)
      when 'RO' then '11' when 'AC' then '12' when 'AM' then '13' when 'RR' then '14'
      when 'PA' then '15' when 'AP' then '16' when 'TO' then '17' when 'MA' then '21'
      when 'PI' then '22' when 'CE' then '23' when 'RN' then '24' when 'PB' then '25'
      when 'PE' then '26' when 'AL' then '27' when 'SE' then '28' when 'BA' then '29'
      when 'MG' then '31' when 'ES' then '32' when 'RJ' then '33' when 'SP' then '35'
      when 'PR' then '41' when 'SC' then '42' when 'RS' then '43' when 'MS' then '50'
      when 'MT' then '51' when 'GO' then '52' when 'DF' then '53'
    end;
  end codigo_uf;

  function calcular_dv_chave(p_base in varchar2) return varchar2 is
    l_base varchar2(60) := limpar(p_base);
  begin
    if l_base is null or not regexp_like(l_base, '^[0-9A-Z]{43}$') then
      raise_application_error(-20002, 'Base da chave deve ter 43 caracteres.');
    end if;
    return mod11(l_base);
  end calcular_dv_chave;

  function chave_valida(p_chave in varchar2) return boolean is
    l_chave varchar2(60) := limpar(p_chave);
  begin
    if l_chave is null or not regexp_like(l_chave, '^[0-9A-Z]{43}[0-9]$') then
      return false;
    end if;
    return substr(l_chave, 44, 1) = calcular_dv_chave(substr(l_chave, 1, 43));
  end chave_valida;

  function chave_valida_sn(p_chave in varchar2) return varchar2 is
  begin
    return case when chave_valida(p_chave) then 'S' else 'N' end;
  end chave_valida_sn;

  function decompor_chave(p_chave in varchar2) return t_chave is
    l_chave varchar2(60) := limpar(p_chave);
    l_r     t_chave;
  begin
    if length(l_chave) <> 44 then
      raise_application_error(-20003, 'Chave de acesso deve ter 44 posições.');
    end if;

    l_r.codigo_uf       := substr(l_chave,  1, 2);
    l_r.ano_mes         := substr(l_chave,  3, 4);
    l_r.cnpj            := substr(l_chave,  7, 14);
    l_r.modelo          := substr(l_chave, 21, 2);
    l_r.serie           := substr(l_chave, 23, 3);
    l_r.numero          := substr(l_chave, 26, 9);
    l_r.tipo_emissao    := substr(l_chave, 35, 1);
    l_r.codigo_numerico := substr(l_chave, 36, 8);
    l_r.dv              := substr(l_chave, 44, 1);
    return l_r;
  end decompor_chave;

  function montar_chave(
    p_uf               in varchar2,
    p_data_emissao     in date,
    p_cnpj             in varchar2,
    p_modelo           in varchar2,
    p_serie            in number,
    p_numero           in number,
    p_tipo_emissao     in varchar2 default '1',
    p_codigo_numerico  in varchar2 default null
  ) return varchar2 is
    l_base varchar2(60);
  begin
    l_base := codigo_uf(p_uf)
           || to_char(p_data_emissao, 'YYMM')
           || limpar(p_cnpj)
           || lpad(p_modelo, 2, '0')
           || lpad(to_char(p_serie), 3, '0')
           || lpad(to_char(p_numero), 9, '0')
           || p_tipo_emissao
           || nvl(p_codigo_numerico,
                  lpad(to_char(trunc(dbms_random.value(0, 100000000))), 8, '0'));

    return l_base || calcular_dv_chave(l_base);
  end montar_chave;

  -- -------------------------------------------------------------------
  -- Validação completa da nota
  -- -------------------------------------------------------------------

  procedure validar_nota(p_nota_id in number, p_qtd_erros out number) is
    l_nota          nota_fiscal%rowtype;
    l_cnpj_forn     fornecedor.cnpj%type;
    l_tipo_cat      categoria_despesa.tipo%type;
    l_chave         t_chave;
    l_qtd_itens     pls_integer;
    l_soma_itens    number;
    l_sem_produto   pls_integer;
    l_imp_somam     number;
    l_total_calc    number;
    l_qtd_dup       pls_integer;
    l_soma_dup      number;
    l_menor_venc    date;
    l_duplicadas    pls_integer;
  begin
    select * into l_nota from nota_fiscal where id = p_nota_id;
    select cnpj into l_cnpj_forn from fornecedor where id = l_nota.fornecedor_id;
    select tipo into l_tipo_cat from categoria_despesa where id = l_nota.categoria_id;

    delete from nf_inconsistencia where nota_id = p_nota_id;

    -- R01 - CNPJ do fornecedor
    if not cnpj_valido(l_cnpj_forn) then
      registrar(p_nota_id, 'CNPJ_INVALIDO', 'ERRO',
        'CNPJ do fornecedor ' || formatar_cnpj(l_cnpj_forn) || ' é inválido.');
    end if;

    -- R02 - Chave de acesso e coerência com o cabeçalho
    if l_nota.chave_acesso is null then
      registrar(p_nota_id, 'CHAVE_AUSENTE', 'ALERTA', 'Nota sem chave de acesso.');
    elsif not chave_valida(l_nota.chave_acesso) then
      registrar(p_nota_id, 'CHAVE_DV', 'ERRO',
        'Dígito verificador da chave de acesso não confere (possível erro de leitura).');
    else
      l_chave := decompor_chave(l_nota.chave_acesso);

      if l_chave.cnpj <> l_cnpj_forn then
        registrar(p_nota_id, 'CHAVE_CNPJ', 'ERRO',
          'CNPJ da chave (' || formatar_cnpj(l_chave.cnpj) || ') difere do fornecedor ('
          || formatar_cnpj(l_cnpj_forn) || ').');
      end if;
      if to_number(l_chave.numero) <> l_nota.numero then
        registrar(p_nota_id, 'CHAVE_NUMERO', 'ERRO',
          'Número na chave (' || to_number(l_chave.numero) || ') difere do informado ('
          || l_nota.numero || ').');
      end if;
      if to_number(l_chave.serie) <> l_nota.serie then
        registrar(p_nota_id, 'CHAVE_SERIE', 'ERRO', 'Série da chave difere da informada.');
      end if;
      if l_chave.modelo <> l_nota.modelo then
        registrar(p_nota_id, 'CHAVE_MODELO', 'ERRO', 'Modelo da chave difere do informado.');
      end if;
      if l_chave.ano_mes <> to_char(l_nota.data_emissao, 'YYMM') then
        registrar(p_nota_id, 'CHAVE_DATA', 'ERRO',
          'Ano/mês da chave (' || l_chave.ano_mes || ') difere da data de emissão.');
      end if;
    end if;

    -- R03 - Datas
    if l_nota.data_emissao > trunc(sysdate) then
      registrar(p_nota_id, 'EMISSAO_FUTURA', 'ERRO', 'Data de emissão está no futuro.');
    end if;
    if l_nota.data_entrada < l_nota.data_emissao then
      registrar(p_nota_id, 'ENTRADA_ANTES_EMISSAO', 'ERRO',
        'Data de entrada é anterior à emissão.');
    end if;

    -- R04 - Itens
    select count(*), nvl(sum(valor_total), 0), count(case when produto_id is null then 1 end)
      into l_qtd_itens, l_soma_itens, l_sem_produto
      from nf_item
     where nota_id = p_nota_id;

    if l_qtd_itens = 0 then
      registrar(p_nota_id, 'SEM_ITENS', 'ALERTA', 'Nota sem itens cadastrados.');
    elsif abs(l_soma_itens - l_nota.valor_produtos) > c_tolerancia then
      registrar(p_nota_id, 'SOMA_ITENS', 'ERRO',
        'Soma dos itens (' || to_char(l_soma_itens, 'FM999G999G990D00')
        || ') difere do valor dos produtos ('
        || to_char(l_nota.valor_produtos, 'FM999G999G990D00') || ').');
    end if;

    if l_tipo_cat = 'MERCADORIA' and l_sem_produto > 0 then
      registrar(p_nota_id, 'ITEM_SEM_PRODUTO', 'ERRO',
        l_sem_produto || ' item(ns) sem vínculo com produto do estoque.');
    end if;

    -- R05 - Total = produtos - desconto + frete + outras + IPI + ICMS-ST
    select nvl(sum(valor), 0)
      into l_imp_somam
      from nf_imposto
     where nota_id = p_nota_id
       and tipo in ('IPI', 'ICMS_ST');

    l_total_calc := l_nota.valor_produtos - l_nota.valor_desconto + l_nota.valor_frete
                  + l_nota.valor_outras + l_imp_somam;

    if abs(l_total_calc - l_nota.valor_total) > c_tolerancia then
      registrar(p_nota_id, 'TOTAL_CALCULADO', 'ERRO',
        'Total calculado (' || to_char(l_total_calc, 'FM999G999G990D00')
        || ') difere do total da nota ('
        || to_char(l_nota.valor_total, 'FM999G999G990D00') || ').');
    end if;

    -- R06 - Duplicatas (contas a pagar)
    select count(*), nvl(sum(valor), 0), min(data_vencimento)
      into l_qtd_dup, l_soma_dup, l_menor_venc
      from nf_duplicata
     where nota_id = p_nota_id
       and status <> 'CANCELADA';

    if l_qtd_dup = 0 then
      registrar(p_nota_id, 'SEM_VENCIMENTO', 'ERRO', 'Nota a pagar sem nenhuma duplicata/vencimento.');
    else
      if abs(l_soma_dup - l_nota.valor_total) > c_tolerancia then
        registrar(p_nota_id, 'SOMA_DUPLICATAS', 'ERRO',
          'Soma das duplicatas (' || to_char(l_soma_dup, 'FM999G999G990D00')
          || ') difere do total da nota ('
          || to_char(l_nota.valor_total, 'FM999G999G990D00') || ').');
      end if;
      if l_menor_venc < l_nota.data_emissao then
        registrar(p_nota_id, 'VENCIMENTO_ANTERIOR', 'ERRO',
          'Existe vencimento anterior à data de emissão.');
      end if;
    end if;

    -- R07 - Possível lançamento em duplicidade (mesmo fornecedor, valor e data)
    select count(*)
      into l_duplicadas
      from nota_fiscal
     where fornecedor_id = l_nota.fornecedor_id
       and valor_total   = l_nota.valor_total
       and data_emissao  = l_nota.data_emissao
       and id           <> l_nota.id
       and status not in ('CANCELADA', 'REJEITADA');

    if l_duplicadas > 0 then
      registrar(p_nota_id, 'POSSIVEL_DUPLICIDADE', 'ALERTA',
        'Já existe nota do mesmo fornecedor com mesmo valor e data de emissão.');
    end if;

    select count(*)
      into p_qtd_erros
      from nf_inconsistencia
     where nota_id = p_nota_id
       and severidade = 'ERRO';

  exception
    when no_data_found then
      raise_application_error(-20010, 'Nota ' || p_nota_id || ' não encontrada.');
  end validar_nota;

end pkg_nf_validacao;
/
