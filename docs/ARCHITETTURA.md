# Architettura del PLC Aut260045

Questo documento descrive il progetto dopo il refactoring dell'ottobre 2026 (branch `refactor/core`, fasi 1-10).

Il progetto è diviso in tre livelli:

1. **Core**: codice riutilizzabile su altre piegatrici, che non conosce la macchina.
2. **Machine**: la configurazione di Aut260045.
3. **MAIN**: tiene insieme il tutto e contiene la regia del ciclo.

## Cartelle

```text
BendingMachine/
  Core/                 riutilizzabile: niente IO, MAIN, Ads, Mach, E_Alarm (lo verifica controlli.py)
    Core_Param          dimensioni del Core (canali, assi, valvole, ingressi, eventi diagnosi)
    Axes/               FB_AxisModule: potenza, reset, jog, calibrazione, limiti di un asse
    Cycle/              E_CycleState: passi della macchina a stati del ciclo
    Diag/               FB_DiagLog e tipi della diagnosi (GVL Diag.Data)
    Hmi/                interfaccia HMI v2: tipi, comandi con ack, watchdog
    Nc/                 tabelle NC: FB_SequenceRunner, FB_FeedTableBuilder, gruppi, FB_NcChannels
    Sync/               funzioni M a tabella: FB_MFuncDispatcher, ST_MFuncDef, costruttori F_M*
    Valves/             ST_Valve, ST_Input, SetMacro, WaitMacro
  Machine/              Aut260045
    FB_MachineConfig    assi, valvole, ingressi, funzioni M, volantino: IL punto da toccare
    Mach (GVL)          tabelle compilate da FB_MachineConfig, indici degli assi, bit dei sincronismi
    E_Valve             indici delle valvole
    FB_Centering        centraggio TL/TB (usa I/O e parametri della macchina)
  GVLs/                 Hmi (interfaccia v2), Diag, Alarms, ProgramDB, IO, Safety, Machine, Size, Calibration
  DUTs/                 tipi di ProgramDB e dei parametri macchina, E_Alarm, enum della macchina
  POUs/                 MAIN, Clock, RaiseAlarm/ClearAlarms, volantino, bimanuale
```

## Un ciclo PLC (MAIN)

| Ordine | Chiamata | Cosa fa |
|---|---|---|
| 1 | `Clock`, `InitCyclic`, volantino, bimanuale | valori di riposo e ingressi dell'operatore |
| 2 | `HmiInputs` | watchdog, comandi (`Hmi.Cmd`) e valori continui (`Hmi.Live`) nelle variabili interne (`hmiStop`, `calibStart[]`, `valveForce[]`, …) |
| 3 | `SafetyManager`, `InputMapping` | sicurezza, override, eventi dei comandi, morsa in uso (`ur2InUse`) |
| 4 | `MotorStatusManager`, `ParameterWriteManager`, `DriveStatusManager` | motori, avvio della scrittura dei limiti, stato degli azionamenti |
| 5 | `fbMachineConfig` | tabelle del Core, con ID e posizioni degli assi di questo ciclo |
| 6 | `Manual` (solo in manuale) | volantino a tabella, test uscite |
| 7 | `StateMachine` | in testa i comandi agli FB (`fbSeq`, `fbCentering`, `fbNc`), poi il CASE del ciclo, gli stati forzati e il watchdog dei passi |
| 8 | `MacroManager` | `fbMFunc`: funzioni M dei canali NC, allarmi e abort che chiede, time-out dei sincronismi |
| 9 | `AlarmManager`, `DiagUpdate` | allarmi a livello e conteggi, diagnosi |
| 10 | `AxisFunctionBlocks` → `AxisModules` | un `FB_AxisModule` per asse, esiti per il ciclo dopo |
| 11 | `OutputMapping`, `HmiOutputs` | uscite fisiche, `Hmi.Cfg` / `Hmi.Sts` |

## Il ciclo automatico

```text
Idle(0) --start--> StartChecks(10) --> SeqInit(110)
SeqInit --homing fatto?--> si: SeqPrepare(120)    no: HomingPrepare(122)
HomingPrepare --tabelle pronte--> HomingRun(412) --fine + start--> CenteringSelect(50)
CenteringSelect --NO--> SeqInit   --TL/TB--> Centering(55) --fatto--> SeqInit
                                                          --pezzo assente/presente--> HomingPrepare
                                  --ACC--> Abort (allarme 67)
SeqPrepare --tabelle pronte--> SeqRun(410) --tutti i canali finiti-->
    altra sequenza: SeqPrepare (seqIdx+1)
    fine pezzo: contapezzi; lotto/nuovo programma/singolo -> CycleEnd(500) -> Idle
                ciclo continuo: EJECT YES/NO_1 -> CenteringSelect, NO_2 -> WaitStartNextPiece(420)
Stop: in RUN o in preparazione -> Stop(700) -> Stopped(719) --start--> Resume(730)
      (step-on se da RUN, altrimenti reset tabelle 740/745 e ripresa dal passo memorizzato)
      in centraggio/homing/attesa start -> differito alla fine della fase
Abort(600) -> AbortDone(610) -> WaitReset(620) --reset--> Reset(800) -> Idle
```

| Dove | Cosa si trova |
|---|---|
| `Diag.Data.nSubStep` | Il passo interno di `FB_SequenceRunner` (`E_SeqStep`) o di `FB_Centering` (`E_CenteringStep`). I passi che non esistono più (60-90, 130-402) hanno numeri riservati. |
| `Diag.Data.aEvent` | Gli ultimi 64 cambi di passo, con riga e funzione M in attesa per canale e l'allarme che li ha causati. |
| `Diag.Data.stLastAbort` | L'ultimo ingresso in abort. |

## Come si estende

### Una valvola nuova

1. Un valore in `Machine/E_Valve`.
2. Una riga `Valve(...)` in `FB_MachineConfig`: uscita set, uscita reset (0 = monostabile), conferma set, conferma reset. Senza sensore la conferma è l'uscita stessa.
3. Le sue funzioni M, sempre in `FB_MachineConfig`:

   ```
   Add(F_MValve(canale, M, E_Valve.X, OUTPUT_ACTION_ENUM.SET, timeout, post-delay, allarme));
   ```
4. Un allarme di timeout nuovo in `E_Alarm` (numero mai usato), con i testi nell'HMI.

La valvola compare da sola nel test uscite dell'HMI v2 (`Hmi.Cfg.aValve`). Una funzione M che la HMI genera e che non è in tabella dà l'allarme 68, invece di fermare il canale.

### Un sincronismo nuovo tra canali

Una riga `F_MSync(canale, M, aspetta-a-1, aspetta-a-0, metti-a-1, metti-a-0, a-1-durante, a-0-durante, allarme time-out)` sui bit `Mach.SYNC_*`. Se serve un flag nuovo si aggiunge un bit.

### Un asse nuovo (es. trascinamento)

1. L'asse NC nel tsproj, con un `AXIS_REF` in MAIN collegato all'asse.
2. Un valore in `AXIS_ENUM`: è il numero che l'HMI scrive in `ProgramDB`.
3. `Mach.AX_<nome>`, poi `Axis(...)` e `AxisService(...)` in `FB_MachineConfig`:
   - nome, scala velocità, posizione del selettore del volantino;
   - parametri del jog, SoE;
   - allarmi di calibrazione e limiti.
4. Una chiamata `aAxisMod[Mach.AX_<nome>](stAxis := <asse>);` in `MAIN.AxisModules`.

Con questi passi ottiene senza altro codice:

- **dall'HMI v2**: presenza e limiti (`Hmi.Param`), jog, calibrazione, stato in `Hmi.Sts`;
- **dal volantino**: il jog sul suo selettore;
- **dalle tabelle NC**: la quota nella coordinata giusta del suo gruppo.

Per usarlo nei programmi serve anche il generatore dell'HMI (`PlcSequenceBuilder`). Se l'asse deve muoversi in un canale NC proprio, vedi il punto successivo.

### Un canale NC in più

- `Core_Param.MAX_CHANNEL`.
- Il canale NCI nel tsproj, con i collegamenti di `MAIN.in_stNciToPlc` / `out_stPlcToNci`, che diventano `ARRAY[0..MAX_CHANNEL-1]`.
- `Size.MAX_TASK`, insieme all'HMI.

I FB del Core girano già su `MAX_CHANNEL` canali.

### Capacità dei programmi

In `Size` ogni `MAX_*` è il numero di elementi. Cambiarli cambia il layout di `ProgramDB`; l'HMI v2 li legge da `Hmi.Cfg`.

## Verifiche senza TwinCAT

Le cartelle sono sotto `TERMOWATT\_verifica_plc`.

| Strumento | Cosa verifica |
|---|---|
| `statico\controlli.py <BendingMachine>` | XML, BOM e CRLF, GUID unici, `.plcproj` completo, nomi dei passi esistenti, il Core che non usa la macchina. |
| `statico\inutilizzati.py <BendingMachine>` | Variabili di MAIN, POU e DUT senza riferimenti. |
| `macrotable\` | La tabella delle funzioni M di `FB_MachineConfig` è identica al vecchio `MacroManager` (54 funzioni). |
| `trace\` | Registrazione delle tracce sul runtime con assi simulati e confronto prima/dopo. Va usato in XAE. |
| `plcsim\` | Simulatore Python dei canali e delle funzioni M sui programmi del corpus. |

## Punti aperti

- **Compilazione e prove.** Il codice non è ancora stato compilato in XAE né provato. Va fatto in ordine:
  1. compilazione;
  2. tracce in simulazione (`trace\LEGGIMI.md`);
  3. prove in macchina a velocità ridotta.
- **GeoStart.** Il GeoStart scritto prima di riempire le tabelle viene cancellato dal reset della tabella, come nel codice di prima. Va verificato sul runtime da dove partono le tabelle NC.
- **`Safety.ERLDatumExecute`.** Non si azzera mai: era così anche prima, perché la riga di reset era commentata. Va verificato sullo schema safety.
- **HMI v1 tolta.** `Ads`, `TYPE_ADSMODEL_*`, `TYPE_MESSAGE_ITEM`, `MESSAGE_TYPE_ENUM`, `AdsConnectionManager` e la parte v1 di `HmiInputs`, `OutputMapping` e `DriveStatusManager` non ci sono più: il PLC parla solo con il profilo 6 dell'HMI. Il banco tracce (`_verifica_plc\trace`) usa ancora `Ads.Rx/Tx` e va portato sulla v2.
- **Parametri macchina.** Sono ancora i campi per nome di `Machine.parametersRx/Tx`, che è persistente. Una copia persistente per indice d'asse (`MachineCfg.aAxis`) serve quando arriva un asse nuovo.
- **Regia del ciclo.** `MAIN.StateMachine` (avvio, stop, ripresa, reset, modi) è ancora nella macchina, non nel Core. Con la v1 tolta i suoi ingressi sono tutti variabili interne: si può spostare in `FB_Cycle` del Core.
- **Funzioni mancanti o rotte** (ACC, USE LOCK M90/M91, X1-X6, …): sono in [BACKLOG_FUNZIONI.md](BACKLOG_FUNZIONI.md).

## Libreria del Core

Quando il Core è stabile, per estrarlo in una libreria:

1. Nuovo progetto libreria TwinCAT `FT_BendingCore`: si copiano `Core/` e i tipi che usa (`TYPE_SEQUENCE`, `TYPE_TASK`, `TYPE_ACTION`, `TYPE_POSITION`, `TYPE_MACRO`, `AXIS_ENUM`, `ACTION_ENUM`, `OUTPUT_*`, `CENTERING_ENUM`, `Size`).
2. `Core_Param` diventa la parameter list della libreria.
3. Aut260045 referenzia la libreria e cancella `Core/`.

La regola "il Core non usa la macchina" (controllata da `controlli.py`) è ciò che rende possibile il passaggio senza modifiche.
