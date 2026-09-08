# Sala de Internalização

O app do tablet da equipe de tradução oral: conduz a equipe por uma passagem bíblica sem mostrar texto, guarda o que ela grava e leva o que ela conta de volta ao servidor, que confere contra o Mapa de Sentido e devolve achados. Todo progresso visível é o colar.

## Language

### Estações

**Convite**:
A primeira estação da sessão, em que a voz da sala apresenta o livro (panorama) e a passagem (cena) antes de abrir a conversa.
_Avoid_: introdução, abertura, boas-vindas

**Conversa**:
A estação em que a equipe descreve a passagem em voz alta e cada elemento do Mapa de Sentido que ela toca acende uma conta do colar.
_Avoid_: contação, narração

**Ensaio**:
A estação em que a equipe grava a passagem inteira na língua materna, ouve, regrava ou mantém.
_Avoid_: rehearsal, gravação da passagem (a gravação em si é o take)

**Retrotradução**:
A estação em que a gravação do ensaio toca de volta e a equipe conta na língua-ponte, trecho por trecho, o que cada pedaço diz, até "terminei" disparar a conferência.
_Avoid_: retro (só como prefixo em código), back-translation

**Escolha**:
A estação em que a equipe escolhe a próxima passagem entre as que estão na roda.
_Avoid_: seleção, roda (a roda é a lista de passagens, não a estação)

**Fecho**:
A última estação, em que o cordão do colar fecha em círculo e a sessão termina.
_Avoid_: fim (nome antigo do enum), encerramento

### Quem fala e quem ouve

**Equipe**:
O grupo de tradutores orais que usa o tablet. É quem a sala guia e a única pessoa presente na conversa.
_Avoid_: usuário, time, team

**Guia**:
A voz da sala: a persona que fala com a equipe durante toda a sessão, com falas fixas e faladas geradas pelo servidor.
_Avoid_: narrador, facilitador (é uma pessoa, não a voz), Facilitator (prefixo herdado em código)

**Analista**:
A entidade do servidor que lê apenas o que foi contado de volta, compara com o Mapa de Sentido e devolve achados. Nunca ouve a língua materna e nunca fala com a equipe.
_Avoid_: classificador, IA de verificação, verificador

**Validador**:
A entidade do servidor que confere o rascunho de fala da Guia antes de ele ser dito à equipe e pode recusá-lo.
_Avoid_: verificador de correção (outro papel), revisor

**Verificador de correção**:
A entidade do servidor que confere se um conserto respondeu ao achado, contando o que o trecho carregava e o que a nova contagem trouxe de volta.
_Avoid_: analista, validador

**Facilitador**:
A pessoa que a sala chama quando não consegue seguir sozinha e que atende pela Mesa.
_Avoid_: guia, consultor, Facilitator (prefixo de código para a voz)

**Mesa**:
O app web do facilitador, onde ele vê as equipes, as perguntas e as salas paradas, e marca uma parada como atendida.
_Avoid_: desk, painel, dashboard

### O que se grava e se conta

**Passagem**:
O trecho bíblico sobre o qual a equipe trabalha, identificado pela perícope, com o áudio de referência e as contas do Mapa de Sentido.
_Avoid_: perícope (é o identificador da passagem, não a passagem), texto

**Sessão**:
O trabalho de uma equipe sobre uma passagem, com estado e retrato persistido que permitem retomar na estação exata em que parou.
_Avoid_: passagem, rodada

**Take**:
Uma gravação mantida pela equipe, identificada localmente pelo escopo (parte, trecho ou passagem inteira) e, depois do envio, pelo identificador do servidor.
_Avoid_: gravação (genérico demais), áudio

**Língua materna**:
A língua da equipe, na qual a passagem é gravada na Conversa e no Ensaio e que ninguém na sala precisa entender.
_Avoid_: L1, língua da equipe, materna (só como abreviação em prosa)

**Língua-ponte**:
A língua em que a equipe conta de volta o que ouviu, para que o analista possa conferir. Neste projeto, o português.
_Avoid_: L2, português (é o papel, não a língua fixa), bridge

**Trecho**:
Um pedaço da retrotradução já contado: aponta para um take do ensaio e para um intervalo de tempo dentro desse arquivo, nunca para a passagem concatenada. No servidor, o mesmo objeto chama-se segmento.
_Avoid_: chunk (a posição efêmera na lista que o analista vê), pedaço, segment (nome do lado do servidor)

**Chunk**:
A posição numerada de um trecho na lista que o analista recebe numa leitura. Existe só durante a leitura; o servidor traduz o número em segmento.
_Avoid_: trecho, segmento (os objetos persistentes)

**Colar**:
A corda de contas que é o único indicador de progresso da sala: contas acesas mostram a cobertura da conversa, contas-fantasma mostram takes mantidos.
_Avoid_: necklace, barra de progresso

**Conta**:
Um elemento do Mapa de Sentido representado no colar, que passa por não encontrada, aflorada (a Guia disse) e engajada (a equipe disse).
_Avoid_: bead, pérola, item

**Panorama**:
A fala de abertura sobre o livro inteiro, tocada uma vez antes da cena.
_Avoid_: introdução, visão geral

**Cena**:
A fala de abertura específica da passagem escolhida, que segue o panorama.
_Avoid_: convite (a estação inteira)

### Achados e consertos

**Achado**:
O resultado do analista sobre o que foi contado: falta, adição, mudança de sentido, relação errada, evento reordenado, violação de preservação, evidência insuficiente ou incerto.
_Avoid_: erro, problema, finding

**Falta com endereço**:
Um achado de falta cujo lugar (antes, dentro ou depois) cabe num trecho já contado. Vai para a tela "onde mora o erro".
_Avoid_: falta interna, missing com chunk

**Falta sem endereço**:
Um achado de falta que aponta para depois do último trecho contado. Não vira tela de correção: a equipe volta ao Ensaio para gravar o resto, mantendo takes, trechos e colar.
_Avoid_: falta externa, falta no fim, missing sem chunk

**Conserto**:
A correção de um trecho apontado por um achado, por um dos dois caminhos abaixo. Em inglês no código: mend.
_Avoid_: correção (reservado para a verificação do servidor), reparo, fix

**Caminho longo**:
O conserto que regrava a língua materna do trecho e depois reconta esse mesmo trecho na língua-ponte. É a única saída para adição, mudança de sentido e violação de preservação.
_Avoid_: refazer a parte (tela antiga), materna mais ponte

**Caminho curto**:
O conserto que só reconta o trecho na língua-ponte sobre a gravação materna que já existe.
_Avoid_: recontar só, correção simples

**Retro retomada**:
Uma retrotradução que continua de onde parou numa sessão reaberta: a reprodução recomeça no cursor e os trechos já contados voltam do servidor.
_Avoid_: retomar do zero

### A sala e as pessoas

**Sala parada**:
O estado em que a sala não consegue seguir sozinha e pede uma pessoa, insistindo em intervalos até ser atendida. É um aviso, não um teto: nada é recusado.
_Avoid_: sala travada, teto, bloqueio

**Pedir uma pessoa**:
A ação da sala de avisar que precisa de alguém, resolvida por um toque longo no círculo ou pela Mesa marcando a parada como atendida.
_Avoid_: chamar humano, SOS, needs person (nome interno)

**Mapa de Sentido**:
O conteúdo canônico da passagem contra o qual o analista compara o que foi contado, incluindo o que deliberadamente não se revela.
_Avoid_: meaning map, gabarito, texto-base
