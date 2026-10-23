# Correzioni da fare — AUT260023

Data analisi: 2026-07-31
File analizzato: `BendingMachine/POUs/MAIN.TcPOU` (4521 righe), `BendingMachine/POUs/NC/FB_FeedTablesPrep.TcPOU`, DUT e GVL collegate.

Questo documento raccoglie i difetti individuati e la correzione proposta per ciascuno.
Nessuna modifica e' ancora stata applicata al codice.

I numeri di riga si riferiscono al file cosi' com'e' oggi: vanno riverificati dopo la prima modifica.

## Indice

- [Stato delle verifiche](#stato-delle-verifiche)
- [A — Ciclo automatico che si ferma e torna a IDLE (causa confermata)](#a--ciclo-automatico-che-si-ferma-e-torna-a-idle-causa-confermata)
- [B — Meccanismo di start: impulso invece di memoria](#b--meccanismo-di-start-impulso-invece-di-memoria)
- [C — Pulsante di stop e ripresa](#c--pulsante-di-stop-e-ripresa)
- [D — Modalita' passo-passo](#d--modalita-passo-passo)
- [E — Difetti latenti](#e--difetti-latenti)
- [Decisioni aperte](#decisioni-aperte)
- [Verifiche da fare in macchina](#verifiche-da-fare-in-macchina)
- [Riepilogo](#riepilogo)

## Stato delle verifiche

| Sintomo | Stato |
|---|---|
| In scarico automatico ogni tanto il ciclo non riparte da solo | **Causa confermata** — vedi A1 |
| Quando si ferma va allo stato 0 | **Confermato in macchina**: `autoLoopMode` TRUE, transizione da 410 |
| `newProgramPending` resta TRUE | **Confermato in macchina** |
| Dopo lo stop il programma non ricomincia da dove si era fermato | **Cause individuate**, da confermare in macchina — vedi C |
| Passo-passo non esegue un passo alla volta | **Causa individuata** — vedi D1 |

Nota metodo: la causa in A1 e' stata ottenuta per eliminazione. In tutto `MAIN` esistono solo tre righe che scrivono `State := 500` (3921, 3927, 3943), tutte nello stato 410, e lo stato 500 fa solo `state := 0`. Con `autoLoopMode = TRUE` verificato in macchina la riga 3943 e' esclusa; con `ejectMode = YES` la riga 3921 viene sovrascritta da `state := 50`. Resta solo la 3927.

## A — Ciclo automatico che si ferma e torna a IDLE (causa confermata)

### A1 — `newProgramTrigger` resta permanentemente TRUE

**Priorita': 1 (blocca la produzione)**

File: `BendingMachine/POUs/MAIN.TcPOU`, azione `AdsRxMapping`, righe 446-452.

```iecst
fbNewProgramTrigger(CLK := Ads.Rx.ProgramLoaded);

newProgramTrigger := fbNewProgramTrigger.Q OR (ProgramDB.parameters.prgName <> lastPrgName);

IF newProgramTrigger THEN
	lastPrgName := ProgramDB.parameters.prgName;
END_IF
```

**Problema.** `newProgramPending` viene azzerata solo nello stato 850 (riga 4137), ma il blocco di coda della state machine la riarma nello stesso ciclo PLC (righe 4266-4268). Se resta TRUE significa che `newProgramTrigger` e' permanentemente TRUE. Dei due termini, `fbNewProgramTrigger.Q` e' un `R_TRIG` e puo' durare una sola scansione: resta quindi il confronto `prgName <> lastPrgName`, che non torna mai uguale nonostante l'assegnazione sotto.

Causa tipica: `ProgramDB.parameters.prgName` non contiene il terminatore nullo (l'HMI scrive 24 byte pieni). L'assegnazione forza il terminatore su `lastPrgName`, il confronto successivo legge la sorgente oltre i 24 byte finendo nei campi adiacenti di `TYPE_PARAMETERS` e risulta sempre diverso. Da verificare in esadecimale, ma non cambia la correzione.

**Effetto.** `newProgramPending` sempre armata. A fine pezzo lo stato 410 prende il ramo di riga 3927 (`IF newProgramPending THEN State := 500`), che e' valutato **prima** dell'`ELSIF autoLoopMode`, quindi vince sempre. Il ciclo chiude, va a 500 e poi a 0. Da 0 il blocco di riga 4273 manda a 850 e poi a 800, che cancella la lista messaggi: l'arresto e' silenzioso e senza traccia.

**Correzione.** Rilevare il nuovo programma solo sul fronte di `ProgramLoaded`, che e' anche il protocollo gia' concordato con l'HMI e documentato in `RIEPILOGO_MODIFICHE.md` (`ProgramLoaded` a FALSE, scrittura di `ProgramDB`, poi `ProgramLoaded` a TRUE).

```iecst
// Un nuovo programma e' considerato caricato solo sul fronte di salita di ProgramLoaded.
// Il confronto su prgName e' stato rimosso: restava permanentemente diverso e teneva
// newProgramPending sempre armata, chiudendo il loop automatico alla fine di ogni pezzo.
fbNewProgramTrigger(CLK := Ads.Rx.ProgramLoaded);

newProgramTrigger := fbNewProgramTrigger.Q;

IF newProgramTrigger THEN
	lastPrgName := ProgramDB.parameters.prgName;   // mantenuto solo come informazione diagnostica
END_IF
```

**Rischio.** Basso. Se l'HMI non rispetta il protocollo su `ProgramLoaded`, il caricamento di un nuovo programma non resetta piu' il ciclo: da concordare con chi sviluppa l'HMI prima del collaudo.

**Verifica.** In watch: `newProgramPending` deve restare FALSE per tutta la produzione. Il ciclo automatico deve incatenare i pezzi senza tornare a 0.

### A2 — Il reset "nuovo programma" scavalca ABORTED e STOP

**Priorita': 2**

File: `MAIN.TcPOU`, riga 4273.

```iecst
IF newProgramPending AND (state = 0 OR state >= 600) AND state <> 800 AND state <> 820 THEN
	state := 850;
END_IF
```

**Problema.** Il commento sopra dice "solo a programma fermo", ma `state >= 600` comprende 600/610/620 (ABORTED), 700/719/730 (STOP) e 900-920 (passaggio a manuale). Da 900 il salto avviene addirittura prima di `ItpEStopEx` e del clear dei gruppi (stati 905/910), lasciando i canali NCI in uno stato non pulito.

**Effetto.** Un abort o uno stop non aspettano piu' il reset dell'operatore: vanno a 850, poi a 800, che cancella la lista messaggi. L'allarme che aveva causato l'arresto sparisce prima di poter essere letto.

**Correzione.** Restringere la condizione allo stato 0.

```iecst
IF newProgramPending AND state = 0 THEN
	state := 850;
END_IF
```

**Rischio.** Basso. Un abort o uno stop continueranno a richiedere il reset, che e' il comportamento corretto.

### A3 — Chiusura ciclo per nuovo programma senza traccia

**Priorita': 3**

File: `MAIN.TcPOU`, righe 3924-3928 (stato 410) e 4102 (stato 800).

**Problema.** Quando il ciclo viene chiuso perche' e' arrivato un nuovo programma non resta nessuna informazione: lo stato 800 esegue `fbClearMessageList`.

**Correzione.** Aggiungere un campo in fondo a `TYPE_ADSMODEL_TX` (per non spostare i campi esistenti) che segnali l'evento, oppure una `stopReason : UINT` scritta nei tre rami di uscita dello stato 410 e nei punti in cui il blocco Forced States devia lo stato. Utile anche come strumento diagnostico permanente.

**Rischio.** Nullo sulla logica di moto. Richiede allineamento del `.tmc` e dell'HMI se si aggiunge un campo ADS.

### A4 — `seqIdx` non azzerato nel ramo del loop automatico

**Priorita': 2**

File: `MAIN.TcPOU`, stato 410, righe 3929-3941.

**Problema.** Gli altri due rami dello stesso `IF` fanno `seqIdx := 0` (righe 3928 e 3944), il `CASE ProgramDB.parameters.ejectMode` no.

**Effetto.** Il ri-azzeramento che segue gira con `seqIdx` posizionato oltre l'ultima sequenza attiva. Gli stati 140 e 202 leggono `ProgramDB.sequence[seqIdx]` e preparano la feed table dell'homing con `stGeoStart` non aggiornato. L'indice viene poi corretto dallo stato 110, ma troppo tardi.

**Correzione.** Aggiungere `seqIdx := 0;` nei tre rami del `CASE` (righe 3932, 3936, 3940).

**Rischio.** Basso.

## B — Meccanismo di start: impulso invece di memoria

### B1 — `startCondition` dura una sola scansione

**Priorita': 1 (e' la causa comune di piu' sintomi)**

File: `MAIN.TcPOU`, righe 889 (azione `InitCyclic`) e 2868-2876 (azione `StateMachine`).

```iecst
// InitCyclic, riga 889 — eseguita a ogni scansione (chiamata da MAIN riga 317)
startCondition := FALSE;

// StateMachine, righe 2868-2876
IF manualMode THEN
	IF stMpgEncoder.xbutton2RTrigger THEN
		startCondition := TRUE;
	END_IF
ELSIF autoMode THEN
	IF startTriggerOut OR stTwoHandControl.xStartRTrigger OR stTwoHandControl.xTwoHandRTrigger OR persistentStart THEN
		startCondition := TRUE;
	END_IF
END_IF
```

**Problema.** `InitCyclic` gira a ogni ciclo PLC da 1 ms e azzera `startCondition`. Le tre sorgenti che la settano sono tutte fronti (`R_TRIG`). La quarta, `persistentStart`, e' dichiarata a riga 21 e **non viene mai messa a TRUE in tutto il progetto**: e' solo azzerata alle righe 4104 e 4172. Era evidentemente pensata proprio per tenere lo start memorizzato, ma non e' mai stata collegata.

Risultato: `startCondition` vale TRUE per **un solo millisecondo**, quello in cui cade il fronte del pulsante.

**Effetto.** Ogni consumatore vede il consenso solo se si trova nella condizione giusta esattamente in quel millisecondo. Se non lo e', la pressione viene persa in silenzio. I consumatori sono:

| Punto | Righe | Cosa succede se l'impulso si perde |
|---|---|---|
| Stato 0 → 10 | 2882 | lo start non fa partire il ciclo |
| Stato 412 → 50 | 3990 | la macchina resta in INIT dopo l'azzeramento |
| Stato 719 → 730 | 4080 | la ripresa dopo lo stop non avviene |
| Macro M95 / M96 / M97 | 1140, 1437, 1496 | il canale non riceve il consenso e resta fermo |
| Attese centraggio | 2980, 3168, 3607, 3740 | la fase di centraggio non avanza |

**Correzione.** Trasformare la richiesta di start in una memoria, consumata esplicitamente. Usare `persistentStart`, che e' gia' dichiarata, oppure introdurre `startRequest : BOOL`.

```iecst
// StateMachine, sostituisce il blocco 2868-2876
IF manualMode THEN
	IF stMpgEncoder.xbutton2RTrigger THEN
		startRequest := TRUE;
	END_IF
ELSIF autoMode THEN
	IF startTriggerOut OR stTwoHandControl.xStartRTrigger
	   OR stTwoHandControl.xTwoHandRTrigger OR stepTriggerOut THEN
		startRequest := TRUE;
	END_IF
END_IF

startCondition := startRequest;
```

`startRequest` va azzerata:

- nel punto in cui viene effettivamente consumata (stati 0, 412, 719, consenso M95/96/97, attese centraggio);
- sempre negli stati 700 (stop), 600 (abort), 800 (reset) e 850 (nuovo programma), per non trascinare un consenso vecchio oltre un arresto.

Da valutare anche un tempo massimo di validita' (per esempio 30 s), per evitare che una pressione dimenticata faccia ripartire la macchina molto dopo.

**Rischio.** Medio-alto: e' il consenso al movimento. Va collaudato in sicurezza, a velocita' ridotta, verificando in particolare che dopo uno stop o un abort la memoria risulti azzerata.

**Nota.** Questa singola correzione risolve, o rende affidabili, i punti C6 (ripresa dopo stop), D1 (passo-passo) e le attese di centraggio.

## C — Pulsante di stop e ripresa

Comportamento atteso confermato: lo stop **non** deve fermare gli assi durante il centraggio o durante una piega. Deve bloccare al termine del passo in corso, e la ripresa deve continuare da li'.

Flusso attuale:

```
qualsiasi stato tra 1 e 599
  │  Ads.Rx.StopBtn (livello) OR stTwoHandControl.xStopRTrigger (fronte)   [4281]
  ▼
700   lastState := state [4282] ; homingDone := FALSE [4055] ; ItpEStopEx sui 3 canali
  ▼
719   ResetBtn → 800 → 0  |  stop tenuto >1 s → apre il bloccaggio  |  start → 730
  ▼
730   ItpStepOnAfterEStopEx sui 3 canali
  ▼
410   RUN
```

### C1 — La ripresa torna sempre a 410, qualunque fosse lo stato

**Priorita': 1**

File: `MAIN.TcPOU`, righe 100 (dichiarazione), 4282 (unica scrittura), 4092 (stato 730).

**Problema.** `lastState := state` viene scritto e **non e' mai riletto**: nessuna lettura in tutto il POU. Lo stato 730 fa `state := 410` fisso.

Il danno nasce combinando questo con `channelDone[]`, azzerato solo negli stati 400, 402 e 850:

- stop durante la fase **RUN** → `channelDone[]` sono quelli in accumulo, la ripresa a 410 e' corretta;
- stop durante il **cambio sequenza** (120→130→150→200→210→400), il **centraggio** (55-90 / 300-355) o l'**INIT** (122-412) → `channelDone[0..2]` valgono ancora TRUE dalla sequenza precedente. Alla ripresa lo stato 410 entra subito nel ramo di riga 3909, incrementa `seqIdx` e **salta la sequenza che non era ancora stata eseguita**, oppure chiude il ciclo.

**Effetto.** E' il sintomo "non ricomincia da dove si era fermato". Spiega anche perche' capita spesso ma non sempre: dipende da dove cade la pressione dello stop.

**Osservazione in macchina (2026-07-31).** In automatico, dopo stop e successivo start, il ciclo esegue **un riposizionamento** invece di riprendere. Corrisponde al percorso: 730 → 410 con `channelDone[]` gia' tutti TRUE → `seqIdx := seqIdx + 1` → nessuna sequenza attiva oltre quella corrente → ramo del loop automatico → `state := 50` → `homingDone` e' appena stato messo a FALSE dalla riga 3910 → `state := 122` → esecuzione di `ProgramDB.homing`, cioe' il riposizionamento delle unita' alla quota di partenza del ciclo. Se invece la sequenza interrotta non era l'ultima, il salto va a 120 e la macchina **esegue la sequenza successiva saltando quella interrotta**.

**Perche' capita in modo casuale.** Concorrono due meccanismi:

1. I tre canali non finiscono insieme la loro parte di sequenza, quindi al momento dello stop `channelDone[]` puo' essere gia' parzialmente TRUE. Inoltre nella finestra fra una sequenza e l'altra (stati 120, 130, 150, 200, 210, 400) sono TRUE tutti e tre, perche' vengono azzerati solo allo stato 400, subito prima di rientrare in 410. Gli stati 120 e 130 usano FB basati su ADS, quindi quella finestra dura millisecondi o decine di millisecondi per ogni sequenza.
2. Lo stato 730 non aspetta la fine dello step-on (vedi [C2](#c2--gli-stati-700-e-730-non-aspettano-la-fine-dei-fb-nci)): passa a 410 gia' alla prima scansione, quando lo step-on e' appena stato comandato e i canali sono ancora in stato di E-stop. Lo stato 410 comincia subito a campionare `fbFeedTable[i].bChannelDone` su canali non ancora ripartiti. Il risultato dipende da quante scansioni impiegano i canali a riprendere: e' una corsa temporale, da cui la casualita'.

La libreria `Tc2_NCI` e' presente solo in forma compilata (`_Libraries/Beckhoff Automation GmbH/Tc2_NCI/3.3.19.0/Tc2_NCI.compiled-library-ge33`), quindi il comportamento esatto di `bChannelDone` dopo un E-stop non e' verificabile da sorgente. Il difetto dimostrabile resta comunque il primo: allo stato 410 raggiunto da 730 il test di fine sequenza viene valutato su `channelDone[]` mai riazzerati.

**Indicatore diagnostico immediato.** Quando avviene il riposizionamento indesiderato, `Ads.Tx.Count` risulta incrementato (riga 3917): la macchina ha concluso il pezzo che invece era ancora in lavorazione. E' il modo piu' rapido per confermare il fenomeno dall'HMI, insieme a `Ads.Tx.channelDone1/2/3`.

**Ordine consigliato.** Applicare prima [C2](#c2--gli-stati-700-e-730-non-aspettano-la-fine-dei-fb-nci) e [C3](#c3--fbiptsteponaftereestopextimeout-non-e-mai-assegnato), che sono a rischio basso o nullo e tolgono la parte casuale del problema. Solo dopo intervenire su C1, che richiede la decisione sul comportamento di ripresa.

**Correzione proposta** (richiede conferma, vedi [Decisioni aperte](#decisioni-aperte)):

- `lastState = 410` → step-on NCI e ritorno a 410, come oggi;
- `lastState <> 410` → niente step-on: reset dei canali con `itpResetEx2` (come gia' fa lo stato 820) e ripartenza dalla **preparazione della sequenza corrente**, cioe' stato 120 **senza** incrementare `seqIdx`. Lo stato 400 riazzera `channelDone[]`, quindi il problema di fondo sparisce.

**Rischio.** Alto: cambia come la macchina riprende il movimento. Collaudo obbligatorio a velocita' ridotta, provando lo stop in ogni fase del ciclo.

### C2 — Gli stati 700 e 730 non aspettano la fine dei FB NCI

**Priorita': 1**

File: `MAIN.TcPOU`, righe 4056-4063 (stato 700), 4087-4093 (stato 730). FB chiamati alle righe 501-507 (`AxisFunctionBlocks`).

**Problema.** `fbItpEStopEx[i]` e `fbIptStepOnAfterEStopEx[i]` sono chiamati in `AxisFunctionBlocks`, cioe' **dopo** `StateMachine()` nell'ordine di esecuzione di `MAIN` (riga 334, poi riga 338). Gli stati 700 e 730 impostano solo `.bExecute := TRUE` e poi leggono `.bBusy` nella stessa scansione, quando quell'uscita ha ancora il valore della scansione precedente, cioe' FALSE. Il test `IF NOT bBusy ...` risulta vero subito e lo stato avanza al primo ciclo, senza aspettare nulla.

Che si tratti di un difetto e non di una scelta lo dimostra lo **stato 905** (righe 4189-4196), che fa la stessa operazione chiamando il FB inline:

```iecst
905:
	FOR i:=0 TO 2 DO
		fbItpEStopEx[i](sNciToPlc := in_stNciToPlc[i], bExecute := TRUE);
	END_FOR

	IF NOT fbItpEStopEx[0].bBusy AND NOT fbItpEStopEx[1].bBusy AND NOT fbItpEStopEx[2].bBusy THEN
		state := 910;
	END_IF
```

Stesso schema usato per `fbClearGroup` negli stati 55 e 910. Gli stati 700 e 730 sono gli unici due che non lo seguono.

**Effetto.** Si entra in 719 quando l'E-stop e' appena partito, non quando e' finito. Si esce da 730 senza sapere se lo step-on e' riuscito. Se l'operatore preme start subito, lo step-on viene richiesto su canali non ancora in stato di E-stop.

**Correzione.** Chiamare i FB inline in 700 e 730, come nello stato 905.

**Rischio.** Basso: allinea questi due stati al pattern gia' usato altrove nello stesso file.

### C3 — `fbIptStepOnAfterEStopEx[i].tTimeOut` non e' mai assegnato

**Priorita': 1 (verifica rapidissima)**

File: `MAIN.TcPOU`, `InitCyclic`, righe 734-738.

**Problema.** Tutti gli altri FB NCI del progetto ricevono un timeout: `fbItpEStopEx` T#500MS (726, 729, 732), `itpResetEx2` T#500MS (808, 811, 814), `fbClearInterpolationGroup` T#100MS. Per `fbIptStepOnAfterEStopEx` vengono impostati solo i tre `bExecute := FALSE`, il timeout resta al default della dichiarazione.

**Effetto da verificare.** Se online risulta `T#0S`, lo step-on va in `bErr`, lo stato 730 salta a 620 (ABORTED) con messaggio 219 e la ripresa fallisce sempre.

**Correzione.** Aggiungere in `InitCyclic`:

```iecst
fbIptStepOnAfterEStopEx[0].tTimeOut			:= T#500MS;
fbIptStepOnAfterEStopEx[1].tTimeOut			:= T#500MS;
fbIptStepOnAfterEStopEx[2].tTimeOut			:= T#500MS;
```

**Rischio.** Nullo.

### C4 — `Ads.Rx.StopBtn` letto a livello e non a fronte

**Priorita': 2**

File: `MAIN.TcPOU`, riga 4281.

**Problema.** Se l'HMI non riazzera il bit dopo la pressione, la sequenza e': 700 → 719 → start → 730 → 410 e, nella stessa scansione, il blocco Forced States rivede `StopBtn` ancora TRUE (410 e' < 600) e rimanda a 700. La macchina sembra ripartire e si rimette subito in stop.

Il pulsante fisico usa `stTwoHandControl.xStopRTrigger`, che e' un fronte, quindi non ha il problema: se il sintomo compare solo con lo stop da HMI, e' questo.

**Correzione.** Aggiungere un `R_TRIG` su `Ads.Rx.StopBtn` in `AdsRxMapping` e usare il fronte nel blocco Forced States.

**Rischio.** Basso. Da verificare che l'HMI non si aspetti il comportamento a livello per un mantenimento dello stop.

### C5 — `homingDone := FALSE` nello stato 700

**Priorita': 2**

File: `MAIN.TcPOU`, riga 4055.

**Problema.** Dopo uno stop `homingDone` viene azzerata anche se poi si riprende regolarmente.

**Effetto.** Se dopo lo stop l'operatore fa Reset invece di riprendere (719 → 800 → 0), il successivo start passa dallo stato 110 con `homingDone` FALSE, quindi 122 e **ri-azzeramento completo**: le unita' tornano alla posizione iniziale e il pezzo in lavorazione e' perso. Altra strada per lo stesso sintomo.

**Correzione.** Non azzerare `homingDone` nello stato 700. Se serve, azzerarla solo sul percorso che porta davvero al reset (stato 800).

**Rischio.** Medio: incide su quando la macchina rifa' l'azzeramento. Da collaudare.

### C6 — La ripresa da 719 dipende dall'impulso di start

Vedi [B1](#b1--startcondition-dura-una-sola-scansione). Se la pressione cade mentre lo stato 700 sta ancora eseguendo l'E-stop, viene persa e la macchina resta in 719.

## D — Modalita' passo-passo

Il passo-passo non usa il single-block nativo NCI, ma dei **marcatori M95 / M96 / M97** iniettati nella feed table.

File: `BendingMachine/POUs/NC/FB_FeedTablesPrep.TcPOU`, riga 120.

```iecst
IF (stNciMFuncHsk[taskIdx].nMFunc <> 95 AND stNciMFuncHsk[taskIdx].nMFunc <> 96 AND stNciMFuncHsk[taskIdx].nMFunc <> 97)
   OR Ads.Rx.NCInterpreterMode = E_ItpSingleBlockMode.ItpSingleBlockNck THEN
	... aggiunge HParam + MFuncHsk alla tabella
END_IF
```

- modalita' continua → M95/96/97 vengono **scartate**, il programma fila;
- modalita' passo → vengono **inserite**, e ogni canale si ferma sulla propria M aspettando il consenso del PLC.

Il consenso e' in `MacroManager`: M95 canale 0 (riga 1140), M96 canale 1 (riga 1437), M97 canale 2 (riga 1496).

### D1 — I tre canali vengono liberati separatamente

**Priorita': 1**

**Problema.** Il consenso e' condizionato solo a `startCondition`, che dura una scansione (vedi [B1](#b1--startcondition-dura-una-sola-scansione)). I tre canali arrivano alla propria M in momenti diversi, perche' hanno traiettorie di lunghezza diversa. Alla pressione dello start ricevono il consenso **solo i canali che in quel millisecondo hanno gia' `HskMFuncReq = 1`**; gli altri perdono l'impulso e restano fermi.

**Effetto.** Premi start, parte il canale 0 da solo; premi di nuovo, parte il canale 1; e cosi' via. Gli assi si desincronizzano e il passo non viene eseguito come passo.

**Nota.** La protezione corretta era gia' scritta ed e' commentata, alle righe 1138-1139, 1435-1436 e 1494-1495:

```iecst
//IF Ads.Rx.NCInterpreterMode = E_ItpSingleBlockMode.ItpSingleBlockNck THEN
	//IF in_stNciToPlc[1].HskMFuncNo = 96 AND in_stNciToPlc[2].HskMFuncNo = 97 THEN
		IF startCondition THEN
			out_stPlcToNci[0].MFuncGranted := 1;
		END_IF
	//END_IF
```

Va comunque completata: testava solo `HskMFuncNo` senza `HskMFuncReq`, e `HskMFuncNo` e' significativo solo quando c'e' una richiesta pendente.

**Correzione.** Calcolare una volta per scansione, in `MacroManager` prima dei tre `CASE`:

```iecst
syncPointReady :=
	(NOT ProgramDB.sequence[seqIdx].task[0].active OR channelDone[0] OR
		(in_stNciToPlc[0].HskMFuncReq = 1 AND in_stNciToPlc[0].HskMFuncNo = 95)) AND
	(NOT ProgramDB.sequence[seqIdx].task[1].active OR channelDone[1] OR
		(in_stNciToPlc[1].HskMFuncReq = 1 AND in_stNciToPlc[1].HskMFuncNo = 96)) AND
	(NOT ProgramDB.sequence[seqIdx].task[2].active OR channelDone[2] OR
		(in_stNciToPlc[2].HskMFuncReq = 1 AND in_stNciToPlc[2].HskMFuncNo = 97));
```

e poi, su ogni canale:

```iecst
95:
	IF syncPointReady AND startRequest THEN
		out_stPlcToNci[0].MFuncGranted := 1;
	END_IF
```

I termini `NOT task[i].active` e `channelDone[i]` servono perche' un canale non usato dalla sequenza, o che ha gia' finito la sua tabella, non deve bloccare gli altri.

`startRequest` va azzerata quando tutti i consensi necessari sono stati dati, cosi' che una pressione corrisponda a un passo.

**Rischio.** Medio-alto: e' il consenso al movimento in modalita' passo. Collaudo a velocita' ridotta.

### D2 — `Ads.Rx.StepBtn` e `Ads.Rx.ExecutionMode` non sono usati

**Priorita': 2**

File: `BendingMachine/DUTs/TYPE_ADSMODEL_RX.TcDUT`, righe 15-16.

**Problema.** I due campi sono dichiarati e **non compaiono in nessun POU**. Il pulsante di passo dell'HMI non fa niente: in modalita' passo si avanza con lo START normale.

**Correzione.** Collegare `StepBtn` come sorgente aggiuntiva di `startRequest`. Chiarire con chi sviluppa l'HMI a cosa serviva `ExecutionMode`: molto probabilmente e' il selettore continuo/passo che dovrebbe pilotare `NCInterpreterMode`.

**Rischio.** Basso. Nessuna modifica alla struttura ADS: i campi esistono gia'.

### D3 — `intItpSingleBlock` e' codice morto

**Priorita': 4**

File: `MAIN.TcPOU`, riga 283 (dichiarazione), righe 740-750 (`InitCyclic`).

**Problema.** `ARRAY[0..2] OF ItpSingleBlock` viene dichiarato e i suoi ingressi riazzerati a ogni scansione, ma **il FB non e' mai chiamato**. Il single-block nativo NCI non viene mai attivato. Chi legge il codice pensa il contrario.

**Correzione.** Rimuovere la dichiarazione e le righe di `InitCyclic`, oppure usarlo davvero al posto dei marcatori M95/96/97 (scelta piu' invasiva, non necessaria).

**Rischio.** Nullo se si rimuove.

### D4 — Lo stato 412 richiede lo start anche in scarico automatico

**Priorita': 3**

File: `MAIN.TcPOU`, righe 3910, 3990-3992, e blocco commentato 3995-4006.

**Problema.** Nello stato 410 la riga 3910 esegue `homingDone := FALSE` a ogni completamento di sequenza, compreso quello che innesca il riavvio automatico. Lo stato 50 prende quindi sempre il ramo `ELSE state := 122`, cioe' il ri-azzeramento completo. Al termine, lo stato 412 esce solo con `IF startCondition`, senza distinguere `ejectMode`.

Il blocco commentato alle righe 3995-4006 mostra che l'intenzione originale era fare in 412 lo stesso `CASE ejectMode` che c'e' in 410.

**Effetto.** Anche in modalita' `EJECT_ENUM.YES`, che per definizione dovrebbe essere completamente automatica, dopo ogni pezzo serve una pressione di start.

**Correzione proposta.** Non ripristinare il blocco commentato cosi' com'e', perche' renderebbe automatica anche la prima partenza da IDLE. Meglio un flag dedicato: `autoRestartPending` settato nello stato 410 sul ramo del loop automatico e consumato in 412 (`IF startCondition OR autoRestartPending`), azzerato negli stati 0, 500, 600, 700, 800, 850 e 900.

**Rischio.** Alto: introduce un movimento senza azione dell'operatore. Da decidere e collaudare con attenzione.

## E — Difetti latenti

Non causano i sintomi segnalati, ma sono errori reali trovati durante l'analisi.

### E1 — Lettura fuori dai limiti dell'array `task`

**Priorita': 2**

File: `MAIN.TcPOU`, righe 3360, 3381, 3402, 3439, 3899, 3963.

```iecst
WHILE ProgramDB.sequence[seqIdx].task[taskIdx].active AND taskIdx < Size.MAX_TASK DO
```

L'array e' `task : ARRAY[0..Size.MAX_TASK-1]`, cioe' `[0..2]`. La condizione **indicizza prima di verificare il limite**: con tutti e tre i task attivi si legge `task[3]`, fuori dai limiti. Senza la valutazione short-circuit (non attiva per default in TwinCAT) l'accesso avviene davvero e legge memoria adiacente.

**Correzione.** Invertire i due termini in tutte e sei le occorrenze:

```iecst
WHILE taskIdx < Size.MAX_TASK AND ProgramDB.sequence[seqIdx].task[taskIdx].active DO
```

`FB_FeedTablesPrep.TcPOU` (righe 35 e 47) ha gia' l'ordine corretto e puo' fare da riferimento.

### E2 — `axisIdx` non riazzerato dentro i cicli sui task

**Priorita': 2**

File: `MAIN.TcPOU`, righe 3403 (stato 200) e 3444 (stato 202).

Il `WHILE` interno sugli assi parte con il valore di `axisIdx` lasciato dal task o dalla sequenza precedente, perche' l'azzeramento avviene solo nello stato 110. Di fatto solo il task 0 della prima sequenza dopo il 110 calcola davvero `stGeoStart`; per i task 1 e 2 restano i valori precedenti.

**Correzione.** `axisIdx := 0;` all'inizio di ogni iterazione del `WHILE` esterno sui task.

### E3 — `channelDone[]` richiede sempre tutti e tre gli indici

**Priorita': 3**

File: `MAIN.TcPOU`, righe 3909 e 3973.

Il test e' `IF channelDone[0] AND channelDone[1] AND channelDone[2]`, ma i `WHILE` che riempiono l'array iterano solo sui task **attivi**. Se una sequenza, o `ProgramDB.homing`, usa meno di tre task, la macchina resta bloccata per sempre nello stato 410 o 412.

**Correzione.** Considerare done anche i canali il cui task non e' attivo.

### E4 — `CENTERING_ENUM.ACC` non gestito

**Priorita': 3**

File: `MAIN.TcPOU`, stato 50, righe 2918-2927. `CENTERING_ENUM` (`DUTs/CENTERING_ENUM.TcDUT`) ha quattro valori: `NO`, `TL`, `TB`, `ACC`. Il `CASE` ne gestisce tre. Con `centering = ACC` nessun ramo assegna lo stato e la macchina resta bloccata nello stato 50.

**Correzione.** Aggiungere il ramo `ACC`, oppure un `ELSE` che segnali l'anomalia con un messaggio.

### E5 — Logica della spia di start sempre vera, e blocco duplicato

**Priorita': 3**

File: `MAIN.TcPOU`, azione `OutputMapping`, righe 2380-2390.

```iecst
IF autoMode AND NOT messageListCount>0 THEN
	IO.spiaPulsanteStart := NOT programRunning;
ELSE
	IO.spiaPulsanteStart := FALSE;
END_IF
```

Due problemi:

1. In IEC 61131-3 `NOT` ha precedenza piu' alta degli operatori di confronto, quindi l'espressione e' `(NOT messageListCount) > 0`. `messageListCount` e' `UINT` (riga 119), quindi `NOT` e' un complemento **bit a bit**: con 0 messaggi da' 65535, con 1 messaggio 65534, e cosi' via. La condizione e' **sempre vera** salvo il caso `messageListCount = 65535`. La spia di start quindi non si spegne mai quando ci sono messaggi in lista.
2. Lo stesso blocco e' scritto due volte identico (2380-2384 e 2386-2390).

**Correzione.** Scrivere `IF autoMode AND messageListCount = 0 THEN` e rimuovere il blocco duplicato. La riga 2393 (`IO.turretRed := (autoMode AND messageListCount>0);`) e' invece corretta e conferma l'intenzione.

### E6 — Ultima azione di ogni task mai eseguita

**Priorita': 4**

File: `FB_FeedTablesPrep.TcPOU`, riga 49.

```iecst
WHILE actionIdx < Size.MAX_ACTION AND sequence^.task[taskIdx].actions[actionIdx].active DO
```

`actions` e' `ARRAY[0..Size.MAX_ACTION]`, cioe' 24 elementi (`[0..23]`), ma il ciclo si ferma a `actionIdx = 22`. L'elemento 23 non viene mai elaborato: un programma che usasse 24 azioni perderebbe silenziosamente l'ultima.

**Correzione.** Usare `actionIdx <= Size.MAX_ACTION`, oppure dichiarare `actions : ARRAY[0..Size.MAX_ACTION-1]` allineandosi a come e' dichiarato `task`.

### E7 — `ProgramDB.parameters.deltaT` non usato

**Priorita': 4**

File: `DUTs/TYPE_PARAMETERS.TcDUT`, riga 28. Il parametro e' documentato come "Ritardo tra espulsione e reset ciclo (in decimi di secondo)" ma non compare in nessun POU. Il ritardo effettivo dell'espulsione arriva dal parametro H della macro M103 (`MAIN.TcPOU` riga 1565).

**Correzione.** Collegarlo, oppure rimuoverlo dalla struttura e dall'HMI per non lasciare un parametro che non fa niente.

## Decisioni aperte

Servono prima di scrivere il codice.

1. **C1 — ripresa dopo stop fuori dalla fase RUN.** Confermi la logica proposta (`lastState = 410` → step-on e ritorno a 410; altrimenti reset canali e ripartenza dalla preparazione della sequenza corrente, stato 120 senza incrementare `seqIdx`), oppure preferisci che fuori dalla fase RUN lo stop imponga sempre il reset esplicito dell'operatore?

2. **D1 — cosa e' un "passo".** Il passo e' il singolo blocco tra due M95/96/97 cosi' come lo inserisce il programma pezzo, oppure una pressione deve corrispondere a una riga/istruzione come la vede l'operatore sull'HMI? Nel secondo caso non basta correggere il consenso: va rivisto anche dove `FB_FeedTablesPrep` inserisce i marcatori.

3. **D4 — riavvio automatico senza start.** In `ejectMode = YES` la macchina deve incatenare i pezzi senza nessuna pressione, oppure va bene che chieda uno start dopo il ri-azzeramento?

4. **Contapezzi.** Oggi non ferma la macchina in loop automatico: la riga 3921 (`State := 500` + messaggio 3) viene sovrascritta dal `CASE ejectMode` alle righe 3929-3941, e il messaggio 3 resta in lista senza che nessuno lo rimuova (accende la torretta rossa e spegne la spia di start). Correggerlo **cambia il comportamento in produzione**: va deciso apposta se il contapezzi deve fermare la macchina.

5. **B1 — scadenza della richiesta di start.** Introdurre un tempo massimo di validita' della memoria di start, e in caso quale.

## Verifiche da fare in macchina

| Cosa | Dove | Serve per |
|---|---|---|
| `ProgramDB.parameters.prgName` e `MAIN.lastPrgName` **in esadecimale** | watch | confermare la causa di A1 (terminatore nullo mancante) |
| `fbIptStepOnAfterEStopEx[0].tTimeOut`, `.bErr`, `.nErrID` | watch | C3 |
| `Ads.Tx.State` **nell'istante dello stop** | watch / trace | C1: capire se lo stop cade in RUN o in una fase di transizione |
| `Ads.Tx.channelDone1/2/3` dopo lo stop | watch | C1 |
| `Ads.Rx.StopBtn` dopo il rilascio del pulsante HMI | watch | C4 |
| Comparsa del messaggio 219 | lista messaggi | C2 / C3 |
| `ProgramDB.parameters.ejectMode` | watch | conferma che il modo impostato sia davvero `YES` (0) |

## Da chiarire con chi sviluppa l'HMI

- `Ads.Rx.ProgramLoaded` viene ripulsato durante il ciclo? Dopo la correzione A1 il reset ciclo dipende solo da quel fronte.
- `ProgramDB.parameters.prgName` viene scritta con il terminatore nullo?
- A cosa dovevano servire `Ads.Rx.StepBtn` e `Ads.Rx.ExecutionMode` (vedi D2).
- `Ads.Rx.StopBtn` viene riazzerato dopo la pressione (vedi C4)?

## Riepilogo

| ID | Descrizione | Priorita' | Rischio | Decisione |
|---|---|---|---|---|
| A1 | `newProgramTrigger` sempre TRUE per il confronto su `prgName` | 1 | Basso | no |
| A2 | Reset nuovo programma scavalca ABORTED e STOP | 2 | Basso | no |
| A3 | Chiusura ciclo per nuovo programma senza traccia | 3 | Nullo | no |
| A4 | `seqIdx` non azzerato nel ramo loop automatico | 2 | Basso | no |
| B1 | `startCondition` impulso invece di memoria | 1 | Medio-alto | si (punto 5) |
| C1 | Ripresa dopo stop sempre a 410, `lastState` mai letto | 1 | Alto | si (punto 1) |
| C2 | Stati 700 e 730 non aspettano i FB NCI | 1 | Basso | no |
| C3 | `fbIptStepOnAfterEStopEx.tTimeOut` non assegnato | 1 | Nullo | no |
| C4 | `Ads.Rx.StopBtn` letto a livello | 2 | Basso | no |
| C5 | `homingDone := FALSE` nello stato 700 | 2 | Medio | no |
| D1 | M95/96/97 liberate separatamente per canale | 1 | Medio-alto | si (punto 2) |
| D2 | `StepBtn` e `ExecutionMode` non usati | 2 | Basso | no |
| D3 | `intItpSingleBlock` codice morto | 4 | Nullo | no |
| D4 | Stato 412 richiede start anche in scarico automatico | 3 | Alto | si (punto 3) |
| E1 | Lettura fuori limiti su `task[taskIdx]` | 2 | Basso | no |
| E2 | `axisIdx` non riazzerato nei cicli sui task | 2 | Basso | no |
| E3 | `channelDone[]` richiede sempre tre canali | 3 | Basso | no |
| E4 | `CENTERING_ENUM.ACC` non gestito | 3 | Basso | no |
| E5 | Spia di start sempre accesa, blocco duplicato | 3 | Nullo | no |
| E6 | Ultima azione di ogni task mai eseguita | 4 | Basso | no |
| E7 | `deltaT` non usato | 4 | Nullo | no |

**Ordine di intervento suggerito.** Prima A1 e C3, che sono a rischio nullo o basso e possono sbloccare subito la produzione. Poi C2, A2, A4, E1, E2, E5, che sono correzioni chiuse senza decisioni da prendere. Infine B1, C1, D1 e D4, che toccano il consenso al movimento e vanno collaudati in sicurezza dopo aver chiuso le decisioni aperte.
