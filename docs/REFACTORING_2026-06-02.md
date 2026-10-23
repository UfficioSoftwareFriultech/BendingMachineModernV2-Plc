# Refactoring 2026-06-02

## Obiettivo

Rendere il progetto TwinCAT 3 piu leggibile e manutenibile senza modificare:

- contratto ADS usato dall'HMI;
- nomi delle variabili pubbliche ADS;
- strutture `TYPE_ADSMODEL_RX` e `TYPE_ADSMODEL_TX`;
- GVL `Ads`;
- logica funzionale della macchina;
- mapping I/O, Safety, Drive e NC.

## File modificati

- `BendingMachine/POUs/MAIN.TcPOU`
- `README.md`
- `RIEPILOGO_MODIFICHE.md`
- `docs/PROJECT_STRUCTURE.md`
- `docs/ADS_CONTRACT.md`
- `docs/REFACTORING_2026-06-02.md`

## Refactoring PLC

Nel programma `MAIN` sono stati estratti otto blocchi ciclici in `Action` interne allo stesso POU.
Le `Action` usano le stesse variabili del programma, quindi non introducono nuovi parametri, nuove strutture dati o nuovi simboli ADS.

### Nuove Action

- `AdsConnectionManager`
  - Contiene la macchina a stati `adsState`.
  - Gestisce `Ads.ConnectionAlive`.
  - Usa ancora `Ads.Rx.WatchDog` e `fbConnectionAliveTimeOut`.

- `SafetyManager`
  - Contiene la gestione ciclica dei segnali Safety.
  - Mantiene inalterati comandi, reset, ack e lampeggi.

- `AdsRxMapping`
  - Contiene il mapping iniziale da `Ads.Rx` verso variabili interne.
  - Mantiene inalterati trigger, override, jog, comandi calibrazione e `writeParametersTrigger`.

- `MotorStatusManager`
  - Aggiorna timer stato motori e richiesta `motorsOn`.
  - Mantiene la gestione manuale tramite safety switch MPG.

- `ParameterWriteManager`
  - Contiene la macchina a stati `writeParamterState`.
  - Scrive i limiti software assi ricevuti dai parametri HMI.

- `DriveStatusManager`
  - Calcola `allDrivesEnabled` e `drivesError`.
  - Aggiorna `Ads.Tx.MotorsOn` e `Ads.Tx.MotorsEnable`.

- `MessageManager`
  - Gestisce messaggi di emergenza verso `Ads.Tx.MessageList`.
  - Aggiorna `messageListCount`.
  - Mantiene documentata la sezione allarmi calibrazione disabilitata.

- `AxisFunctionBlocks`
  - Raggruppa le chiamate cicliche ai FB assi, NCI, macro, timer e letture parametri.

- `OutputMapping`
  - Contiene la mappatura finale delle uscite digitali.
  - Contiene la valorizzazione ciclica di `Ads.Tx`.
  - Mantiene inalterati feedback HMI, feedback I/O e aggiornamento posizioni note.

### Corpo principale

Il corpo principale di `MAIN` richiama ora i blocchi nello stesso ordine precedente:

```iecst
AdsConnectionManager();
SafetyManager();
AdsRxMapping();
MotorStatusManager();
ParameterWriteManager();
DriveStatusManager();
MessageManager();
```

La mappatura finale e richiamata a fine ciclo, nello stesso punto dove prima era scritto il blocco esteso:

```iecst
AxisFunctionBlocks();
OutputMapping();
```

Sono stati aggiunti commenti semplici nelle sezioni principali del ciclo per chiarire il ruolo di ogni blocco.

## Cosa non e stato modificato

- `BendingMachine/GVLs/Ads.TcGVL`
- `BendingMachine/DUTs/TYPE_ADSMODEL_RX.TcDUT`
- `BendingMachine/DUTs/TYPE_ADSMODEL_TX.TcDUT`
- `BendingMachine.tsproj`
- `BendingMachine/BendingMachine.plcproj`
- `BendingMachine.Safety`
- `BendingMachine.DriveManager`
- cartella `250083`
- `_Boot`

## Nota su `250083`

La cartella `250083` contiene una copia del progetto con file non identici alla copia principale.
Non e stata modificata per evitare di duplicare cambiamenti su una possibile snapshot storica o variante macchina.

## Verifiche eseguite

- Parsing XML di `BendingMachine/POUs/MAIN.TcPOU`: OK.
- Controllo manuale dei punti ADS refactorizzati:
  - `Ads.Rx.WatchDog`;
  - `Ads.ConnectionAlive`;
  - mapping `Ads.Rx.*`;
  - mapping `Ads.Tx.*`;
  - trigger da HMI;
  - output `Ads.Tx.*` non modificati.
  - parsing XML dopo il secondo passaggio di refactoring.

## Verifiche non eseguite

- Build completa TwinCAT non eseguita da shell: l'ambiente corrente non espone un comando TwinCAT/MSBuild affidabile per compilare il progetto PLC.
- Test runtime macchina non eseguiti.
