# Backlog funzioni mancanti o rotte (Aut260045)

Data: 2026-10-23. Ricavato da `INVENTARIO_FUNZIONI_ADS.md`, che usa le stesse sigle delle fonti (PP, MO,
TP, NC1/2, UT, M = manuale 03517, VCP, VFP, VCM, PSB).

Qui ci sono solo le righe dell'inventario con stato **rotta** o **manca**. Per ognuna:

- cosa serve **dopo il refactoring**, cioè con `MachineConfig.aValve/aMFunc/aAxis`, `FB_Valve`,
  `FB_MFuncDispatcher`, `FB_Cycle`, `FB_FeedTableBuilder` e ADS v2 già fatti;
- una priorità proposta, da ordinare con l'utente.

Il piano di refactoring non implementa queste funzioni (sezione "Fuori da questo refactoring"). Fa
eccezione ACC, che smette di bloccare la macchina e dà l'allarme 67.

Legenda della colonna "Cosa serve":

- **Config**: righe nuove in `MachineConfig` (`aValve`, `aMFunc`, `aAxis`) o in `IoMapping`, senza toccare
  il `Core`.
- **Valvola**: una riga di `aValve` con I/O, timeout, post-delay e allarme di timeout, più le sue M in
  `aMFunc`. Serve l'hardware (elettrovalvola e sensori) e il collegamento nel tsproj.
- **Asse**: asse NC nel tsproj + `E_Axis` + riga di `aAxis` + canale o gruppo NC.
- **Core**: codice nuovo in un FB del `Core` (lavoro vero, con prova in simulazione).
- **HMI**: generatore (`PlcSequenceBuilder`), editor o pagine.
- **Dimensione**: S = meno di un giorno, M = qualche giorno, L = una settimana o più, prove in macchina
  escluse.

Priorità proposte:

- **P1**: rotta e pericolosa, oppure blocca o falsa la produzione con l'hardware di oggi.
- **P2**: funzione del manuale utile su Aut260045, con l'hardware che c'è o quasi.
- **P3**: serve hardware che oggi non c'è (nessun I/O in `GVLs/IO.TcGVL`), oppure è una comodità.

## P1: rotte, sicurezza e produzione

| # | Funzione | Fonte | Stato | Cosa serve dopo il refactoring | Dim. | Perché P1 |
|---|---|---|---|---|---|---|
| 1 | Y bloccaggio pezzo: morsa senza sensore né allarme | M §11.2.29 (11/14); MO T27; VCP §8 | rotta | **Config**: riga `aValve` "morsa" con ritorno da `IO.clampIn`/`IO.clampOpen` invece dell'uscita stessa, timeout e allarme nuovo; M100/M101 in `aMFunc`. Prima va verificato sullo schema quale ingresso vuol dire "chiusa". **HMI**: testo dell'allarme | S | Oggi il ciclo prosegue dopo 0,3 s anche con la morsa aperta e piega un pezzo non bloccato |
| 2 | Espulsore: M102 senza allarme, M103 senza gestione dell'errore | MO T07; VCP "Lato PLC: ancora aperto" 1 | rotta | **Config**: riga `aValve` "espulsore" con timeout e allarme; M102/M103 in `aMFunc`. Per il tempo di espulsione vedi decisione 3 | S | Un espulsore bloccato oggi non ferma il ciclo |
| 3 | A02 espulsore fuori: interblocco della rotazione UR2 | MO A02 (p. 1) | manca | **Config**: condizione di consenso dell'UR2 in `aAxis` (blocco se il feedback "espulsore fuori" è attivo) + allarme nuovo. **Core**: `FB_AxisModule` deve gestire un consenso di movimento da config (serve comunque, vedi 16). Vale anche in manuale | S | Rotazione dell'UR2 con l'astina fuori: rottura meccanica |
| 4 | Morsa montata diversa da quella del programma | M §12.3.1 (12/6); MO A13; VCP §8 | manca | **Config**: `fixedClampEncode`/`mobileClampEncode` in `IoMapping` e in `Sts`. **Core**: `FB_HmiCommandHandler` rifiuta il `PROGRAM_LOADED` (e lo start) se `normalClamp` non corrisponde alla morsa letta. **HMI**: motivo del rifiuto | S | Con la morsa sbagliata cambiano USE minima (95/65 mm) e uso dell'UR2: possibile collisione |
| 5 | Ripresa dopo reset in due start | MO A01; 09519 §2.3.2 d3 e T332 9/24 (VCP §9) | rotta | **Core**: fase "scarico pezzo" in `FB_Cycle` dopo il reset (primo start: morsa aperta, UR2 a 0, ER allo start; secondo start: riposizionamento USE). **HMI**: messaggio "togliere il pezzo, poi start" | M | Oggi le teste si muovono con il pezzo libero ancora in macchina |
| 6 | Passo-passo (STEP) per canale: difetto D1 | M §10.2.3 F2 (10/4), §12.3.3 (12/8); VCP, riga "STEP" | rotta | **Core**: in `FB_SequenceRunner` uno start libera un passo per tutti i canali insieme, non solo quelli già in attesa su M95/96/97 (tipo "start" del dispatcher). **HMI**: nessuna | M | Il ciclo di verifica di un programma nuovo non si comporta come il manuale |
| 7 | USE BALANCED NO | M §11.1.11 (11/3), §12.2.9 (12/3); VCP §5 | rotta | Da decidere (VCP "Ancora da decidere"). Subito: **HMI** blocca NO sul profilo Aut260045 (S). Per supportarlo: **HMI**, generatore con un sincronismo UR2/morsa per riga anche senza bilanciamento (M); **Config**: capacità `MAX_ACTION` letta da `Cfg` | S / M | Pinza e UR2 cambiano prima delle pieghe delle righe precedenti: pezzo sbagliato |
| 8 | Stop memorizzato e attese non visibili ("MACCHINA IN START") | M §3.2.11 (3/5); VCP "Lato PLC: ancora aperto" 7 | manca | **Core**: già nel piano (`Sts.ePhase`, M in attesa per canale, tempo di attesa, `Diag`). **HMI**: pagina diagnosi (sessione separata) | S (con v2) | L'operatore non sa perché la macchina è ferma né che lo stop è stato preso |
| 9 | ACC centraggio automatico | Piano ("Options/FB_Centering"); VFP, riga "Marcatura ACC"; NC1, NC2 | manca (allarme 67 in corso) | Se si sceglie la strada consigliata (l'HMI calcola le frazioni, il PLC esegue come TB): **Core**, una riga in `FB_Centering` (ACC uguale a TB nella misura e nello spostamento). **HMI**: smettere di convertire ACC in TL (`ProgramShapeHost.cs:100-102`) e scrivere le frazioni di `AutoCentering` nelle azioni. Strada alternativa, ricerca del baricentro nel PLC: L, sconsigliata | S + M HMI | Il campo è nell'editor e oggi produce un programma che non parte |

## P2: funzioni del manuale utili con l'hardware di Aut260045

| # | Funzione | Fonte | Stato | Cosa serve dopo il refactoring | Dim. | Note |
|---|---|---|---|---|---|---|
| 10 | Contapezzi che scala fino a zero | M §11.1.6 (11/2), §12.3.3 m (12/8); PP 4 | rotta (semantica) | Decisione 1. Con la proposta (conteggio in su + obiettivo) non serve niente nel PLC; **HMI** mostra "mancano N" | S | — |
| 11 | ΔT di espulsione | PP 7; M §11.1.9 (11/3), §12.2.7 (12/3); VCP "Ciclo pezzo" | rotta | Decisione 3. **Config**: M102 di tipo "set, tieni per H ms, poi reset" in `aMFunc`, oppure M102 + M130 + M103. **HMI**: generatore mette ΔT·100 nell'H | S | — |
| 12 | HOOK L/R | PP 29; M §11.1.16 (11/4), §12.2.14 (12/4) | rotta (significato) | Decisione 4. **HMI**: generatore (rialzo dello spallamento slegato da HOOK) + nome del campo | S | — |
| 13 | X1, IL, IR (UR2 interpolato) | TP; T332 p. 11/13 (VCP §1) | rotta (bloccata) | **Core**: `FB_FeedTableBuilder` assegna lo slot X/Y/Z dall'`axisGroup` (già previsto nella fase 6 del piano); IL/IR non devono riusare nel task 2 gli assi del task 0/1. **HMI**: togliere il blocco `SupportsUr2Interpolation=false` e mappare X1/IL/IR nell'host (VFP). Semantica in `X1_INTERPOLAZIONE_UR2.md` | M | 7 programmi del corpus usano X1 |
| 14 | EP standard: ingressi, ritardi, più EP per lato | M §11.2.23 (11/11-11/13), §11.1.33 (11/6); MO T17-T20 | rotta | **Config**: collegare `epLeft/RightBendUp/Down` nel tsproj (o togliere il feedback se i sensori non esistono); una riga `aValve` per EP. **Core**: il dispatcher legge `TYPE_MACRO.delay` per i ritardi di estrazione. **HMI**: il generatore usa `EpNumber`, i ritardi e BU ON/OFF | M | Nessun programma del corpus usa l'EP: si fa prima del primo uso |
| 15 | REPEAT (F4) | M §10.2.3 (10/4); T332 (VCP, riga "REPEAT") | manca | **Core**: `Cmd REPEAT` in `FB_HmiCommandHandler`; `FB_SequenceRunner` riesegue l'ultima sequenza (T332) o l'ultima piega EP (03517). **HMI**: pulsante in STEP | M | Da scegliere quale dei due significati |
| 16 | Jog degli assi da HMI | VCM "Punti aperti" | rotta | **Core**: `FB_AxisModule` con jog per indice da `Live` (già nel piano, fase 7). **Config**: velocità di jog e consenso in `aAxis`. Prima va deciso il consenso "uomo presente" (VCM) | S (con fase 7) | Il volantino funziona; i tasti dell'HMI no. Da coprire nell'analisi dei rischi |
| 17 | Tolleranza TB sulle pieghe interpolate I | VFP, riga "Piega interpolata I"; M §15.2.5 (15/4) | rotta (da riverificare) | **HMI**: le azioni `Interpolation` devono portare `centeringVerse/Amount`, oppure l'editor deve avvisare. Il PLC (FTP/`FB_FeedTableBuilder`) li applica già | S | Prima di tutto va ricontrollato sul codice HMI di oggi |
| 18 | Piece/cycle e pezzi caricati nel centratore | M §15.3.1 (15/5), §15.3.4 (15/6) | manca | **Core**: in `FB_Centering`, controllo dei micro `CenteringMicro1-4` contro `pcsCycle`, con l'allarme "pezzi non OK" esistente (A 61/62 o nuovo) | S | Va verificato che i micro dicano davvero quanti pezzi ci sono |
| 19 | Centratore SX/DX su/giù senza uscita | VCM "Punti aperti" | rotta | **Config**: riga `aValve` se la valvola esiste sullo schema; altrimenti **HMI** toglie i comandi | S | — |
| 20 | Programma rifiutato con il motivo (quote, morsa, capacità) | M §12.3.1 (12/6); MO A13, A14 | rotta | **Core**: `eCmdResult` del `PROGRAM_LOADED` (già nel piano, fase 8) con limiti da `aAxis` e capacità da `Size`. **HMI**: messaggio | S (con v2) | Oggi il PLC scarta in silenzio quello che supera le capacità |
| 21 | Gruppi di programmi | M §9.2 (9/4), §12.4 (12/10-12/11) | manca | Decisione 5. Con la proposta: **HMI** (elenco programmi × esecuzioni, caricamento del successivo a fine lotto); **Core** niente, basta "lotto completato" in `Sts` | M | — |

## P3: serve hardware che oggi non c'è, oppure è una comodità

Per tutte le funzioni che richiedono un attuatore nuovo, il lavoro PLC dopo il refactoring è lo stesso:
una riga di `aValve` con il suo allarme di timeout, le M in `aMFunc` e due righe di `IoMapping`. Il resto
è nel generatore HMI. Senza hardware l'HMI deve tenere il campo bloccato, perché oggi un programma con
USE LOCK YES genera M90/M91 e ferma la macchina con l'allarme 68.

| # | Funzione | Fonte | Stato | Cosa serve dopo il refactoring | Dim. |
|---|---|---|---|---|---|
| 22 | USE LOCK L/R (M90/M91) | PP 28; M §11.1.12 (11/3), §12.2.10 (12/4); MO T36/T37 | manca | **Valvola** "blocco USE SX/DX" + M90/M91 (le genera già l'HMI, PSB:45-46). **HMI**: bloccare il campo finché la valvola non c'è | S + hardware |
| 23 | P.REF / `<` fermo di riscontro | PP 14; M §11.1.15 (11/4), §11.2.18 (11/11); MO T28/T29 | manca | **Valvola** per lato + M nuove in `aMFunc`. **HMI**: generatore (flag `PieceStop`, oggi scartato da `HasPlcTaskOptions=false`) | S + hardware |
| 24 | G gancio tenuta pezzi | M §11.2.19 (11/11), §3.2.6 (3/4); MO T21/T22 | manca | **Valvola** per lato + M; attivo per il ciclo, tolto nelle righe con G. **HMI**: generatore. Dipende dalla decisione 4 | S + hardware |
| 25 | GUIDE ROLL (rulli di spallamento apribili) | PP 30; M §11.1.21 (11/5), §12.2.18 (12/5); MO T15/T16 | manca | **Valvola** per lato + M. **HMI**: generatore | S + hardware |
| 26 | B spallamento bloccante | M §11.2.20 (11/11); MO T30/T31 | manca | **Valvola** per lato + M. **HMI**: generatore | S + hardware |
| 27 | Z / MOV.S supporto mobile | PP 19; M §11.1.22 (11/5), §11.2.21 (11/11), cap. 17 | manca | **Valvola** per lato + M. **HMI**: generatore | S + hardware |
| 28 | Braccio mobile (ER ed EP) | PP 20; M §11.1.32 (11/6), §11.2.22 (11/11), §11.2.23 c (11/12); MO T23/T24, T32-T35 | manca | **Valvola** per testa + M. **HMI**: generatore | S + hardware |
| 29 | BU ON/OFF: predisposizione EP a inizio ciclo | M §11.1.33 (11/6); PP 38 | manca | **Config**: flag per EP in `ProgramDB` + M di predisposizione nell'INIT. **HMI**: finestra F7 e generatore | S (dopo 14) |
| 30 | TRAN. MOV. DOUBLE e NO | PP 8; M §11.1.13 (11/3-11/4), §12.2.11 (12/4) | manca | DOUBLE: **valvola** dell'extracorsa + M. NO: **HMI**, il generatore non mette M44-47. Il campo diventa a 3 valori in `ProgramDB` | S + hardware |
| 31 | Sesto asse / avanzamento filo, L, W, quota e velocità E6 | M §11.2.15 b, §11.2.16 b (11/10), §11.2.33-34 (11/14-11/15); TP; PP 34 | manca | **Asse** di trascinamento in `aAxis` (è la prova di estendibilità della fase 10 del piano) + gruppo NC con l'ER SX per L; M79/M81 in `aMFunc`. **HMI**: colonna E6 nel generatore | L + hardware |
| 32 | X2-X6 | TP | manca | **Core**: come 13. **HMI**: generatore (oggi `interpolationToken=false`, VFP) | M (dopo 13) |
| 33 | V asse elettrico USE | M §11.2.16 a (11/10) | manca | **Core**: gruppo NC con le due USE, oppure partenza e arrivo sincroni in `FB_SequenceRunner`. **HMI**: generatore | M |
| 34 | `>` piega a spigolo + START C | M §11.2.12 (11/9), §12.6 (12/13), §11.1.20 (11/4), §12.2.17 (12/5) | manca | **HMI**: generatore (routine di spigolo e angolo di partenza C). **Config**: nessuna, se non servono attuatori. Serve l'attrezzatura bussola + spallamento fisso | M |
| 35 | C: EP durante il movimento USE | M §11.2.14 (11/10) | manca | **HMI**: generatore (M dell'EP prima del punto di sincronismo USE) | S (dopo 14) |
| 36 | Pieces group counter + Open clamp | PP 21-22 | manca | **Core**: in `FB_Cycle`, fermo dopo N cicli con la morsa nello stato scelto. Campi in `ProgramDB` | S |
| 37 | Return degrees del braccio | PP 23 | manca | **HMI**: generatore (quota della `Return` prima dell'inversione) | S |
| 38 | Rilevatore automatico pezzo + corsa di uscita USE | PP 25-26 | manca | Ingresso in `IoMapping` + passo in `FB_Cycle` | M + hardware |
| 39 | Commesse e statistiche, dati di funzionamento | M §9.3 (9/4-9/5), cap. 26, §9.11 (9/11) | manca | Decisione 5: **HMI** (tempi da `Sts`/`Diag`, peso, CT/RT nel `.frt`); contatori di funzionamento in `Diag` | M |
| 40 | Centratura teorica (Stamping) | PP 39; MO A16 | manca | Da confermare se serve: Aut260045 ha il centratore meccanico | — |
| 41 | Lettere A, Br, M del T332 | VCP, introduzione e "Ancora da decidere" | manca | Prima va deciso quale manuale vale per la macchina Thermowatt (03517 o T332) | — |

Sono fuori dal backlog perché **non applicabili** su Aut260045 (nessun I/O, vedi l'inventario):
caricatore, saldatrice, robot, smussatrice, coil, taglio H/K e bloccaggio filo F (senza avanzamento filo),
die movement, bending speed 2030/5A DS, cambio utensile automatico (MO T39-T42). Se un giorno si monta
l'avanzamento filo (31), H/K e F diventano righe P3 come le altre valvole.

## Decisioni aperte del piano

Non bloccano le fasi 1-7 del refactoring; servono prima di chiudere il layout ADS v2 (fase 8). Per
ognuna c'è una proposta, da confermare con l'utente.

### 1. Contapezzi: in su fino al lotto o a scalare fino a zero

- **Manuale.** M §11.1.6 (11/2), §12.3.3 m (12/8), PP 4: il contatore è decrementale, scende di
  PIECE/CYCLE a ogni ciclo e a zero ferma la macchina (MO A03).
- **Oggi.** `count` sale di `pcsCycle` fino a `pcsCounter`. Il 2026-10-21 si è deciso: a lotto completato
  la macchina si ferma con l'avviso 90, e l'operatore azzera o corregge i pezzi (VCP "Decisioni").
- **Proposta.** Tenere il conteggio in su nel PLC (`Sts.count` = pezzi fatti, `ProgramDB.pcsCounter` =
  obiettivo, `Cmd SET_COUNT` = correzione dei pezzi fatti). L'HMI mostra anche "mancano N", come il
  COUNTER del manuale.
- **Perché.** I pezzi fatti servono comunque per i tempi e le commesse. Correggere un valore "fatti" è più
  chiaro che correggere un "rimanenti". Non cambia niente di quanto deciso il 2026-10-21.

### 2. Elasticità in percentuale o in gradi

- **Manuale.** M §11.1.24 (11/5), §12.2.21 (12/5), §11.2.7 (11/8): percentuale che aumenta tutti i gradi
  reali della testa.
- **Oggi.** `elscAdjL/R` è sommato in gradi dall'HMI (etichetta "° Adj"). Il 2026-10-21 si è deciso
  "gradi"; lo usa 1 programma su 102.
- **Proposta.** Confermare i gradi. In v2 il campo esce comunque dall'ADS e resta solo nel `.frt` e nel
  generatore, quindi la scelta non tocca il PLC. Se un giorno servisse la %, si aggiunge all'editor senza
  toccare il PLC.

### 3. ΔT di espulsione

- **Fonti.** PP 7 e M §11.1.9 (11/3) dicono "ritardo tra espulsione e reset ciclo". M §12.2.7 (12/3) dice
  "prolungamento del tempo in cui gli organi espulsori restano attivi". Le due frasi dicono la stessa
  cosa: l'espulsore resta fuori più a lungo, poi rientra e il ciclo si resetta.
- **Oggi.** M102 tiene l'espulsore fuori 0,5 s fissi. L'HMI mette il ΔT nell'H della M103, che il PLC usa
  come PostDelay **dopo** il rientro. Con EJECT diverso da YES lo mette in una M130 del task 2.
- **Proposta.** ΔT = tempo **in più** con l'espulsore fuori: espulsore fuori, 0,5 s + ΔT·100 ms, rientro,
  reset del ciclo. Nella config v2 la M102 diventa di tipo "set, tieni per H ms, poi reset", oppure
  resta M102 + M130 + M103. Si cambia solo il generatore HMI. Con EJECT diverso da YES il ΔT non ha
  effetto.

### 4. HOOK: gancio tenuta pezzi o spallamento

- **Manuale.** M §11.1.16 (11/4), §12.2.14 (12/4), §3.2.6 (3/4), §11.2.19 (G per riga, 11/11), MO T21/T22:
  è il **gancio tenuta pezzi**, un'unità opzionale a parte. Anche PP 29 lo descrive così, con "????".
- **Oggi.** Il commento in `TYPE_PARAMETERS` dice "Spallamento". L'HMI usa `HookL/R` per decidere se
  rialzare lo spallamento (M50/M48) alla riga dopo una D (PSB:150, :214, :511, :809). Aut260045 non ha
  I/O per un gancio.
- **Proposta.** HOOK = gancio, come nel manuale. Il rialzo dello spallamento dopo una D non dipende più
  da HOOK: va sempre fatto prima del posizionamento della riga dopo, a meno che anche quella abbia D.
  `HookL/R` resta per una futura valvola "gancio" (backlog 24).
- **Da chiarire con l'utente.** Sulla macchina vera lo spallamento va rialzato sempre? Se oggi qualcuno
  usa HOOK per tenerlo giù, cambia il comportamento dei programmi esistenti: vanno cercati nel corpus
  quelli con HOOK YES e D.

### 5. Gruppi di programmi e commesse: HMI o PLC

- **Manuale.** M §9.2 (9/4), §12.4 (12/10-12/11): un gruppo è un elenco di programmi, ciascuno con il suo
  numero di esecuzioni, ripetuto N volte. M §9.3 (9/4-9/5), cap. 26: commesse con dati statistici.
- **Oggi.** Non c'è niente, né nell'HMI né nel PLC.
- **Proposta.** Tutto nell'HMI. Il PLC tiene un solo programma in `ProgramDB` (100 sequenze); metterne
  diversi vorrebbe dire moltiplicare l'area più grande dell'ADS. L'HMI carica il programma successivo con
  `PROGRAM_LOADED` quando il PLC segnala il lotto completato. Il PLC applica già il cambio a fine pezzo
  se arriva mentre lavora (`ADS_CONTRACT.md`, "Caricamento"). In v2 servono solo l'evento "lotto
  completato" e l'ack del `PROGRAM_LOADED`, già previsti.

### 6. Nomi degli allarmi 104-107 e delle M40/41

- **Manuale.** MO p. 2: T01-T04 sono i timeout di **estrazione** (testina giù/su), T05-T06 quelli del
  **movimento trasversale**.
- **Oggi.**
  - M40/41 (SX) e M42/43 (DX) comandano `IO.erLeft/RightOut*`. Il generatore le chiama
    `ExtrudeL/ExtractL` e le usa per la E, cioè l'estrazione (PSB:47-50). Gli allarmi 100-103 si
    chiamano "ER salita/discesa".
  - M44/45 (SX) e M46/47 (DX) comandano `IO.useLeft/RightUp*`. Il generatore le chiama `ERLUp/ERLDown`
    e le usa al cambio di verso, cioè il trasversale (PSB:51-54). Gli allarmi 104-107 si chiamano "USE
    salita/discesa".
  - I nomi degli I/O (`erLeftOut`, `useLeftUp`) e quelli degli allarmi non corrispondono alle funzioni.
- **Proposta.** Verificare sullo schema pneumatico quale valvola fa cosa. Poi correggere, mantenendo
  i numeri:
  - i nomi e i testi degli allarmi: 100-103 "estrazione SX/DX giù/su", 104-107 "trasversale SX/DX";
  - i nomi delle valvole in `aValve` e di `IoMapping`;
  - i commenti del `MacroManager`, finché esiste.
- **Effetti.** Non cambia nessun numero M né il layout ADS. Nell'HMI cambiano solo i testi (`Alarms.*.xaml`,
  `AlarmCatalog.cs`).

### Altre decisioni collegate (da VCP "Ancora da decidere")

- **Quale manuale vale per la macchina Thermowatt**: 03517/09519 o T332. Decide come funziona D (backlog,
  nota alla riga D dell'inventario) e se le lettere A, X1-X6, Br, M, IL/IR sono funzioni vere (13, 32,
  41).
- **USE BALANCED NO**: vietarlo o supportarlo (backlog 7).
