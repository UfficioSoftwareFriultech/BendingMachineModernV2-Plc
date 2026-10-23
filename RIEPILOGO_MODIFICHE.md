# Riepilogo modifiche

Questo file raccoglie le modifiche fatte al progetto. Le nuove modifiche vanno aggiunte in cima, con data, file interessati, descrizione e verifiche eseguite.

## 2026-08-04 - Riposizionamento automatico al primo pezzo di un nuovo programma

### File modificati

- `BendingMachine/POUs/MAIN.TcPOU`

### Problema

In automatico, dopo il caricamento di un nuovo programma, il primo pezzo non si
riposizionava da solo: serviva uno start in piu' rispetto ai pezzi successivi.

Causa: il caricamento del programma manda la state machine a `850` -> `800` -> `0`.
Dallo stato `0` il riposizionamento (INIT, stati 122...412) parte solo con `startCondition`,
mentre nel loop automatico viene concatenato dallo stato `410` (`state := 50` -> `122`)
senza bisogno dello start. Il primo pezzo partiva quindi da IDLE, i successivi no.

### Modifiche

- Nuove variabili in `MAIN`: `newProgramInitPending : BOOL`, `stateAtScanStart : UINT`.
- Action `StateMachine`: `stateAtScanStart := state;` prima del `CASE`. I blocchi in coda al
  `CASE` leggono `state` gia' riscritto dal ramo appena eseguito, quindi non possono sapere da
  dove veniva la macchina.
- Blocco "New program loaded from ADS": la richiesta e' armata solo se
  `stateAtScanStart = 0` (IDLE) oppure `= 500` (ciclo appena chiuso). Non viene armata quando
  `state` e' appena diventato 0 uscendo da `800` (reset dopo un abort), `820`, `2000` o `2100`.
- Stato `850`: la richiesta e' confermata solo con `autoMode`, `autoLoopMode` e
  `ejectMode <> NO_2_START`. Con `NO_2_START` il riposizionamento e' subordinato allo start
  anche a fine pezzo, quindi il comportamento resta quello di prima.
- Stato `0`: la richiesta viene consumata alla prima scansione in IDLE e porta a `state := 10`
  solo con `autoMode AND (Safety.ModoAuto1Op OR Safety.ModoAuto2Op) AND NOT drivesError AND
  allDrivesEnabled AND ProgramDB.sequence[0].active AND messageListCount = 0 AND
  Ads.Rx.NCInterpreterMode <> 1`. Il selettore e' letto a livello e non tramite `autoMode`:
  il fronte di passaggio in manuale viene scartato negli stati `>= 800`. Azzerata anche sul
  `ResetBtn`.
- Nuovo blocco di decadenza dopo i Forced States: la richiesta e' azzerata se
  `(state >= 600 AND state <> 800 AND state <> 850) OR manualMode OR NOT autoMode OR
  NOT (Safety.ModoAuto1Op OR Safety.ModoAuto2Op) OR drivesError OR NOT allDrivesEnabled`.
  Copre in particolare l'uscita in errore dello stato `800` verso `620`, dove altrimenti la
  richiesta sopravviveva fino al Reset successivo.

### Parte ADS

- Nessun campo ADS aggiunto, rinominato o spostato.

### Dipendenza

La correzione presuppone che `newProgramTrigger` si comporti da impulso. Se e' attivo il difetto
A1 di `docs/CORREZIONI_DA_FARE.md` (`newProgramPending` permanentemente TRUE), il corpo dello
stato `0` non viene mai eseguito e non funziona ne' questa correzione ne' lo start manuale.

### Verifiche

- Controllo XML di `BendingMachine/POUs/MAIN.TcPOU`: `XML OK`.
- Revisione avversariale multi-agente su quattro lenti (sintassi, logica, sicurezza, regressione)
  con refutazione indipendente di ogni rilievo. La prima passata ha fatto emergere tre difetti
  reali, tutti corretti in questa versione: richiesta non azzerata sull'uscita in errore di `800`,
  `state` letto dopo il `CASE` nell'arming, selettore letto tramite il latch `autoMode`.
- Build TwinCAT e prova su macchina: da eseguire.

## 2026-07-30 - Reset ciclo al caricamento di un nuovo programma da ADS

### File modificati

- `BendingMachine/POUs/MAIN.TcPOU`
- `docs/ADS_CONTRACT.md`

### Problema

Caricando un nuovo programma da ADS il PLC non resettava il ciclo.
`Ads.Rx.ProgramLoaded` agiva solo su `count`, e solo a programma fermo.
Restavano quindi attivi `homingDone`, `seqIdx`, gli handshake canali, i dati centratore,
gli allarmi in lista e lo stato ABORTED/STOP. In loop automatico il ciclo ripartiva
ancora con i dati precedenti, quindi il nuovo programma non partiva subito.

### Modifiche

- Nuove variabili in `MAIN`: `newProgramTrigger`, `newProgramPending`, `lastPrgName`,
  `fbNewProgramTrigger : R_TRIG`.
- `AdsRxMapping` rileva il nuovo programma sul fronte di salita di `Ads.Rx.ProgramLoaded`
  oppure sul cambio di `ProgramDB.parameters.prgName`.
- `InitOnce` allinea `lastPrgName` per non generare un reset all'avvio del PLC.
- Nuovo stato `850` nella state machine: azzera `count`, `seqIdx`, `taskIdx`, `posIdx`,
  `axisIdx`, `macroIdx`, `actionIdx`, `homingDone`, `allChannelDone`, i done/ack degli assi,
  `channelDone[]`, `syncAck[]`, i dati centratore, `startCondition` e `persistentStart`,
  poi passa allo stato `800` che cancella la lista messaggi e resetta gli assi.
- Blocco Forced States: il reset viene applicato solo a macchina ferma
  (`state = 0` oppure `state >= 600`), mai durante l'esecuzione.
- Stato `410`: se c'e' un nuovo programma pendente il ciclo termina a fine pezzo
  (`state := 500`) invece di ripartire in loop automatico con i dati vecchi.

### Parte ADS

- Nessun campo ADS aggiunto, rinominato o spostato.
- Comportamento atteso dall'HMI: `ProgramLoaded` a FALSE, scrittura di tutto `ProgramDB`,
  poi `ProgramLoaded` a TRUE.

### Verifiche

- Controllo XML di `BendingMachine/POUs/MAIN.TcPOU`: `XML OK`.
- Build TwinCAT e prova su macchina: da eseguire.

## 2026-06-02 - GVL quote standard calibrazione

### File modificati

- `BendingMachine/GVLs/Calibration.TcGVL`
- `BendingMachine/BendingMachine.plcproj`
- `BendingMachine/POUs/MAIN.TcPOU`
- `docs/ADS_CONTRACT.md`
- `docs/PROJECT_STRUCTURE.md`

### Modifiche

- Creata la GVL `Calibration`.
- Spostate le quote standard di homing diretto in variabili dedicate:
  - `Calibration.ERLHomePosition := 0`
  - `Calibration.USELHomePosition := 1200`
  - `Calibration.URHomePosition := 0`
  - `Calibration.ERRHomePosition := 0`
  - `Calibration.USERHomePosition := 1200`
- `InitCyclic` usa ora la GVL invece di valori letterali.
- L'override ADS resta prioritario quando `Ads.Rx.CalibrationPositionEnable = TRUE`.

### Verifiche

- Controllo XML di `BendingMachine/GVLs/Calibration.TcGVL`: `XML OK`.
- Controllo XML di `BendingMachine/POUs/MAIN.TcPOU`: `XML OK`.
- Controllo XML di `BendingMachine/BendingMachine.plcproj`: `XML OK`.

## 2026-06-02 - Quote calibrazione assi da ADS

### File modificati

- `BendingMachine/DUTs/TYPE_ADSMODEL_RX.TcDUT`
- `BendingMachine/POUs/MAIN.TcPOU`
- `docs/ADS_CONTRACT.md`

### Modifiche

- Aggiunti in fondo a `TYPE_ADSMODEL_RX` i nuovi campi:
  - `CalibrationPositionEnable`
  - `ERLCalibrationPosition`
  - `USELCalibrationPosition`
  - `URCalibrationPosition`
  - `ERRCalibrationPosition`
  - `USERCalibrationPosition`
- Collegate le nuove quote alla calibrazione assi prima di `MC_Home`.
- Se `CalibrationPositionEnable = FALSE`, restano valide le quote storiche interne:
  - `ERL = 0`
  - `USEL = 1200`
  - `UR = 0`
  - `ERR = 0`
  - `USER = 1200`

### Parte ADS

- Nessun campo esistente e stato rinominato o spostato.
- I nuovi campi sono stati aggiunti in fondo alla struttura RX.
- I comandi di start calibrazione esistenti restano invariati.

### Verifiche

- Controllo XML di `BendingMachine/POUs/MAIN.TcPOU`: `XML OK`.
- Controllo XML di `BendingMachine/DUTs/TYPE_ADSMODEL_RX.TcDUT`: `XML OK`.

## 2026-06-02 - Refactoring struttura MAIN e documentazione progetto

### File modificati

- `BendingMachine/POUs/MAIN.TcPOU`
- `README.md`
- `docs/ADS_CONTRACT.md`
- `docs/PROJECT_STRUCTURE.md`
- `docs/REFACTORING_2026-06-02.md`

### Modifiche

- Estratti dal corpo ciclico di `MAIN` otto blocchi in `Action` interne:
  - `AdsConnectionManager`
  - `SafetyManager`
  - `AdsRxMapping`
  - `MotorStatusManager`
  - `ParameterWriteManager`
  - `DriveStatusManager`
  - `MessageManager`
  - `AxisFunctionBlocks`
  - `OutputMapping`
- Aggiunti commenti semplici nel ciclo principale e nelle `Action` create.
- Mantenuto lo stesso ordine di esecuzione dei blocchi.
- Aggiunta documentazione della struttura progetto.
- Aggiunta documentazione del contratto ADS HMI/PLC.
- Aggiunto file dedicato con dettaglio completo del refactoring.

### Parte ADS

Non sono stati modificati:

- `BendingMachine/GVLs/Ads.TcGVL`
- `BendingMachine/DUTs/TYPE_ADSMODEL_RX.TcDUT`
- `BendingMachine/DUTs/TYPE_ADSMODEL_TX.TcDUT`
- nomi `Ads.Rx`, `Ads.Tx`, `Ads.ConnectionAlive`

### Verifiche

- Controllo XML di `BendingMachine/POUs/MAIN.TcPOU`: `XML OK`.
- Build TwinCAT completa non eseguita da shell per assenza di un comando TwinCAT/MSBuild affidabile nell'ambiente corrente.

## 2026-05-06 - Allineamento ritardo estrazione testa destra

### File modificati

- `BendingMachine/POUs/MAIN.TcPOU`

### Sezione interessata

Gestione automatica delle M-function del canale destro:

```iecst
IF in_stNciToPlc[1].HskMFuncReq = 1 THEN
    CASE in_stNciToPlc[1].HskMFuncNo OF
```

### Modifiche

- Modificata `M42 - EXTRUDE ERR`.
- Cambiato `PostDelay` da `T#500MS` a `T#100MS`.
- Modificata `M43 - EXTRACT ERR`.
- Cambiato `TimeOutTime` da `T#1500MS` a `T#2000MS`.
- Modificata `M48 - SUPPORT RIGHT OUT`.
- Cambiato `PostDelay` da `T#200MS` a `T#400MS`.
- Modificata `M49 - SUPPORT RIGHT IN`.
- Cambiato `PostDelay` da `T#200MS` a `T#400MS`.

### Causa individuata

L'estrazione sinistra `M40 - EXTRUDE L` aveva `PostDelay := T#100MS`, mentre l'estrazione destra `M42 - EXTRUDE ERR` aveva `PostDelay := T#500MS`.

Questo introduceva un ritardo aggiuntivo di circa 400 ms sul lato destro dopo il feedback `IO.erRightOut`.

Confrontando tutte le macro equivalenti sinistra/destra sono state allineate anche `M43`, `M48` e `M49` ai timer del lato sinistro.

### Verifiche

- Controllo XML del file `.TcPOU`: `XML OK`.

## 2026-05-06 - Gestione pneumatica testa destra

### File modificati

- `BendingMachine/POUs/MAIN.TcPOU`

### Sezione interessata

Gestione automatica delle M-function del canale destro:

```iecst
IF in_stNciToPlc[1].HskMFuncReq = 1 THEN
    CASE in_stNciToPlc[1].HskMFuncNo OF
```

Il canale `in_stNciToPlc[1]` corrisponde alla testa destra.

### Modifiche

- Aggiunta `M70 - EP RIGHT BEND TRACTION`.
- Aggiunta `M74 - EP RIGHT BEND RESET TRACTION RETURN`.
- Aggiunta `M72 - EP RIGHT OUT EXTRACTION UP`.
- Aggiunta `M73 - EP RIGHT IN EXTRACTION DOWN`.

### Dettaglio tecnico

`M70` usa `fbSetMacro[1]`, comanda `IO.epRightBend` e aspetta il feedback `IO.epRightBendDown`.

`M74` usa `fbSetMacro[1]` e gestisce il reset/ritorno di `IO.epRightBend`.

`M72` usa `fbSetMacro[1]`, comanda `IO.epRightOutSet`, resetta `IO.epRightOutReset` e aspetta il feedback `IO.epRightOut`.

`M73` usa `fbSetMacro[1]` e comanda il rientro del cilindro con `IO.epRightOutReset`.

### Causa individuata

Sul lato sinistro erano presenti le macro automatiche per la valvola e il cilindro pneumatico, mentre sul lato destro le uscite fisiche erano mappate ma mancavano le macro automatiche equivalenti nel canale `in_stNciToPlc[1]`.

Per questo il programma poteva avviare il movimento dell'asse destro senza aspettare la conferma del cilindro pneumatico.

### Verifiche

- Controllo XML del file `.TcPOU`: `XML OK`.
- Build TwinCAT completa non eseguita da shell perche `devenv`, `MSBuild` e `tcbuild` non risultavano disponibili nel PATH.
