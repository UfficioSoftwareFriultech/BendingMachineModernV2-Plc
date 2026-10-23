# Contratto ADS HMI

> **Archivio.** La v1 è stata tolta dal PLC (GVL `Ads`, `TYPE_ADSMODEL_RX/TX`): l'HMI usa solo la v2,
> descritta in [ADS_CONTRACT_V2.md](../ADS_CONTRACT_V2.md). Questo documento resta come riferimento storico.

> **Interfaccia v1.** Dal 2026-10-23 (branch `refactor/core`) il PLC espone anche la v2 (GVL `Hmi`, [ADS_CONTRACT_V2.md](ADS_CONTRACT_V2.md)).
> La v1 resta attiva e invariata nel layout. Cosa cambia per l'HMI:
> - `Size.MAX_*` sono il numero di elementi: il PLC legge 24 azioni, 8 posizioni e 8 macro (layout di ProgramDB invariato);
> - ci sono nuovi allarmi: 67, 68, 69;
> - con la v2 collegata, i valori continui della v1 (override, modi, test uscite) vengono ignorati.


## Regola principale

L'HMI comunica tramite il GVL:

```iecst
Ads.Rx : TYPE_ADSMODEL_RX;
Ads.Tx : TYPE_ADSMODEL_TX;
Ads.ConnectionAlive : BOOL;
```

Questi nomi e tipi sono considerati contratto pubblico.
Non rinominare, spostare o cambiare tipo ai campi senza aggiornare anche l'HMI.

## File da proteggere

- `BendingMachine/GVLs/Ads.TcGVL`
- `BendingMachine/DUTs/TYPE_ADSMODEL_RX.TcDUT`
- `BendingMachine/DUTs/TYPE_ADSMODEL_TX.TcDUT`

## RX, HMI verso PLC

`TYPE_ADSMODEL_RX` contiene:

- handshake: `WatchDog`, `ConnectButton`;
- comandi macchina: `MotorsOnBtn`, `MotorsOffButton`, `StartBtn`, `StopBtn`, `ResetBtn`, `CancelBtn`;
- modalita e step: `ExecutionMode`, `StepBtn`, `SignleAutoMode`, `ManualAutoMode`, `NCInterpreterMode`, `ProgramLoaded`;
- override: `MotorsOvveride`, `IpOvveride`;
- jog assi: `UseLeftFw`, `UseLeftBw`, `UseRightFw`, `UseRightBw`, `ErLeftFw`, `ErLeftBw`, `ErRightFw`, `ErRightBw`, `Ur2Fw`, `Ur2Bw`;
- comandi pneumatici/manuali: uscite USE, ER, supporti, centering, clamp, EP; `CenteringClampSet` e `CenteringOutSet` (ex `UrLock`/`UrUnlock`, stessi byte) comandano bloccaggio centratori ed estrazione supporto. Elenco completo in `VERIFICA_COMANDI_MANUALI_2026-10-20.md`;
- calibrazioni: `StartERLCalibration`, `StartUSELCalibration`, `StartURCalibration`, `StartERRCalibration`, `StartUSERCalibration`;
- quote calibrazione opzionali: `CalibrationPositionEnable`, `ERLCalibrationPosition`, `USELCalibrationPosition`, `URCalibrationPosition`, `ERRCalibrationPosition`, `USERCalibrationPosition`;
- forzature e parametri: `ForceValueEnable`, `WriteParameters`.

## Quote calibrazione da ADS

I campi di quota calibrazione sono stati aggiunti in fondo a `TYPE_ADSMODEL_RX` per non cambiare l'ordine dei campi ADS esistenti.

Le quote standard sono definite nella GVL `Calibration`:

- `Calibration.ERLHomePosition`
- `Calibration.USELHomePosition`
- `Calibration.URHomePosition`
- `Calibration.ERRHomePosition`
- `Calibration.USERHomePosition`

Uso previsto:

- `CalibrationPositionEnable = FALSE`: il PLC usa le quote standard della GVL `Calibration`.
  - `ERL = 0`
  - `USEL = 1200`
  - `UR = 0`
  - `ERR = 0`
  - `USER = 1200`
- `CalibrationPositionEnable = TRUE`: il PLC usa la quota ricevuta da ADS per l'asse che viene calibrato.

Campi:

- `ERLCalibrationPosition`
- `USELCalibrationPosition`
- `URCalibrationPosition`
- `ERRCalibrationPosition`
- `USERCalibrationPosition`

Il comando di avvio resta quello esistente, per esempio `StartERLCalibration`.
La quota viene applicata subito prima di eseguire `MC_Home` in modalita `MC_Direct`.

## Caricamento di un nuovo programma

Quando l'HMI scrive un nuovo programma in `ProgramDB`, il PLC esegue un reset del ciclo.

Il nuovo programma viene riconosciuto in due modi, in OR fra loro:

- fronte di salita di `Ads.Rx.ProgramLoaded`;
- cambio di `ProgramDB.parameters.prgName`.

La seconda condizione serve solo come rete di sicurezza, se l'HMI lascia `ProgramLoaded`
sempre a TRUE. Il modo previsto resta il primo: l'HMI porta `ProgramLoaded` a FALSE,
scrive tutto `ProgramDB` (parametri, `homing`, `sequence`) e solo alla fine lo porta a TRUE.

Comportamento del PLC:

- se la macchina e' ferma, il ciclo viene resettato subito (stato 850, poi il reset
  standard 800): azzerati contapezzi, indici sequenza, `homingDone`, handshake canali,
  dati centratore, e cancellata la lista messaggi;
- se la macchina sta eseguendo, il reset resta pendente: il ciclo in corso viene portato
  a termine e non riparte in loop automatico con i dati vecchi, poi si applica il reset.

Dopo il reset la macchina e' in IDLE con `homingDone = FALSE`, quindi il primo start
esegue la sequenza di INIT del nuovo programma e il successivo avvia il ciclo.

## TX, PLC verso HMI

`TYPE_ADSMODEL_TX` contiene:

- stato programma: `PrgState`, `State`, `Count`, linee NC, stati idle/running/stopped/aborted;
- consenso motori e programma: `MotorsOn`, `MotorsEnable`, `ProgramRun`, `ProgramEnable`, `ProgramStop`, `ProgramCanStop`;
- completamenti e handshake: `homingDone`, `USELDone`, `USERDone`, `UR2Done`, `channelDone*`, `syncAck*`;
- feedback calibrazione assi;
- feedback pneumatici/manuali;
- feedback ingressi e micro;
- modalita attiva: `ManualMode`, `AutoMode`;
- scrittura parametri: `WriteParamtersDone`;
- messaggi HMI: `MessageList`.

`Count` e' solo la copia di `MAIN.count`, riscritta a ogni ciclo. Per azzerare o correggere il
contapezzi l'HMI scrive direttamente `MAIN.count` (UINT). Con `pcsCounter` > 0 e `count` >= `pcsCounter`
il PLC ferma la macchina a fine pezzo con l'avviso 90 (lotto completato) e rifiuta lo start finche'
`MAIN.count` non torna sotto `pcsCounter`.

## Refactoring consentito

Sono consentiti refactoring interni solo se:

- i campi ADS esistenti non vengono rinominati, rimossi o riordinati;
- eventuali nuovi campi vengono aggiunti in fondo alla struttura interessata;
- i simboli pubblici restano uguali;
- `Ads.Rx` e `Ads.Tx` continuano a essere valorizzati nello stesso ciclo logico;
- la build TwinCAT e la prova HMI confermano che i simboli sono ancora disponibili.
