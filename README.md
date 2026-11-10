# Gerenciamento de Estoque e Notas Fiscais

Sistema em **Oracle Database + PL/SQL + Oracle APEX** para o cadastro de notas fiscais de entrada (notas a pagar), com controle de:

- 💰 **Contas a pagar**: parcelas, vencimentos e baixa de pagamentos
- 📦 **Estoque**: entradas geradas pela aprovação da nota, saídas, estorno e custo médio
- 📊 **Despesas**: total por categoria e por mês

O objetivo final é agilizar o cadastro: o usuário **tira uma foto da nota** e uma **IA** extrai os dados (fornecedor, itens, valores e vencimentos), que passam por validação automática e revisão humana antes de entrar no sistema.

> Projeto de estudo. Todos os dados são fictícios.

## Tecnologias
- Oracle Database 21c XE (com migração planejada para 23ai)
- PL/SQL: packages, triggers, controle de concorrência e transações
- Oracle APEX
- IA multimodal para leitura de imagens (etapa 8)
- ORDS / REST (etapa 10)

## Destaques técnicos
- Validação de **CNPJ**, incluindo o novo formato **alfanumérico**, e da **chave de acesso da NF-e** (módulo 11)
- 7 regras de conferência da nota: soma dos itens, total com IPI/ST, duplicatas × total, coerência da chave com o cabeçalho, datas e duplicidade
- Ciclo de vida da nota: `RASCUNHO → EM_REVISAO → APROVADA / REJEITADA / CANCELADA`
- Estoque no modelo **kardex** (imutável): saldo calculado pelos movimentos, com estorno em vez de exclusão
- Rateio de frete, IPI e desconto no custo dos itens, e conversão de unidade (CX → UN) pelo de-para por fornecedor
- `SELECT ... FOR UPDATE` para evitar aprovação dupla e estoque negativo

## Progresso
| Etapa | Tema | Status |
|---|---|---|
| 1 | Modelagem e tabelas | ⏳ em andamento |
| 2 | PL/SQL de validação | ⬜ |
| 3 | Processo e transações | ⬜ |
| 4 | Triggers e views | ⬜ |
| 5 | Dados fictícios e consultas | ⬜ |
| 6 | Aplicativo APEX | ⬜ |
| 7 | Foto da nota (PWA) | ⬜ |
| 8 | IA lendo a nota | ⬜ |
| 9 | Processamento assíncrono e workflow | ⬜ |
| 10 | REST, Vector Search, particionamento | ⬜ |

O detalhe de cada etapa está em [ROTEIRO.md](ROTEIRO.md), e o registro do aprendizado em [DIARIO.md](DIARIO.md).

## Estrutura
```
sql/
  01_tabelas.sql            tabelas, constraints e índices
  02_pkg_nf_validacao.sql   CNPJ, chave de acesso e regras da nota
  03_pkg_nf_processo.sql    aprovação, estoque, pagamento e cancelamento
  04_triggers_views.sql     auditoria e views de contas a pagar, estoque e despesas
  05_dados_ficticios.sql    massa de teste
  99_remover.sql            remove tudo para recomeçar
```

## Como executar
No SQL Developer ou SQLcl, conectado ao seu schema, rode os scripts de `sql/` na ordem `01 → 05`.
