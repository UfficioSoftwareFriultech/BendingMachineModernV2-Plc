# Contratto ADS v2 — HMI ↔ PLC Aut260045

Questo documento descrive la seconda versione dell'interfaccia tra HMI e PLC, introdotta nella fase 8 del refactoring (branch `refactor/core`).

- **Unica interfaccia.** La v1 (GVL `Ads`, `TYPE_ADSMODEL_RX/TX`) è stata tolta dal PLC; il suo contratto è in [archivio/ADS_CONTRACT_V1.md](archivio/ADS_CONTRACT_V1.md). Le colonne "Al posto di (v1)" qui sotto restano come riferimento.
- **HMI scollegata.** Con il watchdog fermo (`Sts.bConnected` FALSE) il test uscite e il jog dall'HMI si spengono; override, ciclo continuo e passo-passo restano gli ultimi valori scritti in `Hmi.Live`.

I tipi sono nei file del PLC, da cui l'HMI ricava il layout:

- `BendingMachine/Core/Hmi/*.TcDUT`;
- `BendingMachine/GVLs/Hmi.TcGVL`.

## Blocchi

| Simbolo | Direzione | Quando | Tipo |
|---|---|---|---|
| `Hmi.Cfg` | PLC → HMI | alla connessione (è costante) | `ST_HmiCfg` |
| `Hmi.Sts` | PLC → HMI | a ogni scambio, **una sola lettura** | `ST_HmiSts` |
| `Hmi.Cmd` | HMI → PLC | a ogni comando | `ST_HmiCmd` |
| `Hmi.Live` | HMI → PLC | a ogni scambio | `ST_HmiLive` |
| `Hmi.Param` | HMI → PLC | quando cambiano i parametri macchina, poi comando `WriteParameters` | `ST_HmiParam` |
| `Diag.Data` | PLC → HMI | a richiesta (pagina diagnosi) | `ST_Diag` |
| `ProgramDB.parameters`, `ProgramDB.homing`, `ProgramDB.sequence` | HMI → PLC | caricamento programma, poi comando `ProgramLoaded` | invariati |

Rispetto alla v1, l'HMI non ha più bisogno di altre letture: `MAIN.<asse>`, `MAIN.in_stNciToPlc`, `Alarms.*` e `Ads.Tx` stanno tutti in `Hmi.Sts`, gli allarmi compresi.

## Comandi (`Hmi.Cmd`)

1. L'HMI scrive `eCommand` e gli argomenti (`nAxis`, `nValue`, `fValue`, `bFlag`).
2. Per ultimo incrementa `nSeq`.
3. Il PLC esegue il comando **una volta** e risponde in `Hmi.Sts.nCmdAck = nSeq`, con l'esito in `Hmi.Sts.eCmdResult`.
4. L'HMI aspetta l'ack prima di mandare il comando successivo.

Al riavvio il PLC non esegue il comando già presente: si allinea a `nSeq` e basta.

| Comando | Argomenti | Effetto | Al posto di (v1) |
|---|---|---|---|
| `Start` (1) | — | start ciclo; i rifiuti si vedono negli allarmi 63-66 e 90 | `Rx.StartBtn` (fronte) |
| `Stop` (2) | — | stop | `Rx.StopBtn` (livello) |
| `Reset` (3) | — | reset allarmi e ciclo (passi 0, 620, 719) | `Rx.ResetBtn` (livello) |
| `MotorsOn` (4) / `MotorsOff` (5) | — | motori accesi o spenti (in manuale li comanda il consenso del volantino) | `Rx.MotorsOnBtn` (commutazione) |
| `ProgramLoaded` (6) | — | nuovo programma: azzera il ciclo (passo 850) e il contapezzi a macchina ferma | `Rx.ProgramLoaded` (fronte) |
| `WriteParameters` (7) | — | copia `Hmi.Param` nei parametri macchina persistenti (`Machine.parametersRx`) e scrive i limiti software degli assi; la fine è in `Sts.bWriteParametersDone` | `Rx.WriteParameters` (fronte) + scrittura di `Machine.parametersRx` |
| `Calibrate` (8) | `nAxis`; `bFlag` = usa la quota `fValue` | calibrazione dell'asse. `InvalidArgument` se l'asse non ha calibrazione; `Rejected` se ce n'è già una in corso | `Rx.Start<asse>Calibration` + `Rx.<asse>CalibrationPosition` + `Rx.CalibrationPositionEnable` |
| `SetCount` (9) | `nValue` 0-65535 | contapezzi | scrittura diretta di `MAIN.count` |

## Valori continui (`Hmi.Live`)

| Campo | Significato | Al posto di (v1) |
|---|---|---|
| `nWatchdog` | Da incrementare almeno ogni secondo. Fermo per 3 s = v2 scollegata (`Sts.bConnected`). | `Rx.WatchDog` (alternato) |
| `fOverride` | override 0-100 % | `Rx.IpOvveride` |
| `bLoopMode` | ciclo continuo | `Rx.SignleAutoMode` |
| `nNcMode` | 1 = passo-passo | `Rx.NCInterpreterMode` |
| `nJogAxis`, `nJogDirection` | Jog dell'asse (indice di `Cfg.aAxis`), +1 o -1. Valgono solo in manuale e a ciclo fermo. | `Rx.*Fw/Bw`, che in v1 **non erano collegati** |
| `bForceOutputs`, `aValveForce[v]` | Test uscite: la valvola `v` va a "set" (TRUE) o "reset" (FALSE). Vale solo in manuale. | `Rx.ForceValueEnable` + i 25 campi `Rx.*Set` / `Clamp*Close` / `Centering*AirDisable` |

## Configurazione (`Hmi.Cfg`)

- `nInterfaceVersion = 2`, `sMachine`.
- Capacità di `ProgramDB`: `nMaxSequence`, `nMaxTask`, `nMaxAction`, `nMaxPosition`, `nMaxMacro`, `nMaxAxisInGroup`.
  - Il generatore dell'HMI deve usare questi valori, non costanti proprie.
  - Oggi valgono 100, 3, 24, 8, 8, 8.
- `aAxis[1..16]`: l'indice è il valore di `AXIS_ENUM` usato in `ProgramDB`. Per ogni asse: `bDefined`, `sName`, `nOption` (posizione del selettore del volantino).
- `aValve[1..32]`: per ogni valvola `bDefined`, `sName`, `nOption` (1 = bistabile). L'indice è `E_Valve`.
- `aInput[1..32]`: sensori, con `bDefined` e `sName`.

La pagina "Manuali" dell'HMI si costruisce da questi elenchi. Una valvola, un asse o un sensore nuovo nel PLC compare nell'HMI senza modifiche all'HMI.

## Stato (`Hmi.Sts`)

- **Comando**: `nCmdAck`, `eCmdResult`, `bConnected`.
- **Ciclo**:
  - `nState` (`E_CycleState`), `nSubStep`, `eCycleEndReason`;
  - `bIdle`, `bCanExecute`, `bRunning`, `bStopped`, `bAborted`, `bHomingDone`;
  - `bManualMode`, `bAutoMode`, `bMotorsOn`, `bMotorsEnable`, `bLimitsWriting`, `bWriteParametersDone`;
  - `nCount`, `nSeqIdx`, `sProgramName`, `aLineNo[0..2]`, `aChannelDone[0..2]`.
- **Volantino**: `nMpgSelector`, `nMpgSpeed`.
- **Assi**, `aAxis[i]`:
  - `fActPos`, `fActVelo`, `nErrorCode`, `bEnabled`, `bMoving`, `bInUse`;
  - `nCalibrationStep`, `bCalibrated` (impulso di 500 ms), `bLimitsBusy`, `fLastKnownPos`.
- **Valvole**, `aValve[v]`: `bSet`, `bReset`, `bFbSet`, `bFbReset`.
- **Ingressi**: `aInput[n]`.
- **Allarmi**: `aAlarmActive[0..255]` e `aAlarmInfo[0..255]`. Sono la copia di `Alarms.Active/Info`, con gli stessi numeri e lo stesso catalogo dell'HMI.

## Parametri macchina (`Hmi.Param`)

- `bEnableSirenOverride`.
- `aAxis[i]` per asse: `bPresent`, `bCalibrated`, `bCheckDone`, `fUpperLimit`, `fLowerLimit`.

Diventano effettivi solo con il comando `WriteParameters`. Oggi il PLC li copia nei campi per nome di `Machine.parametersRx`, che è persistente, per i 5 assi esistenti. Un asse nuovo avrà i suoi campi in `Hmi.Param` dal primo giorno; la copia persistente per indice è nel backlog.

## Cosa sparisce rispetto alla v1

- `Tx.MessageList[0..200]`: era sempre vuoto.
- `Tx.PrgState` come stringa: c'è `nState`.
- Gli impulsi `*Pulse`.
- I campi per asse e per valvola con nome fisso: ora sono elenchi indicizzati.
- I campi mai usati: `SelectBtn`, `CancelBtn`, `StepBtn`, `ExecutionMode`, `ConnectButton`, `MotorsOffButton`, `MotorsOvveride`, `ManualAutoMode`, i jog `*Up/*Down/*Out/*In` duplicati, `CenteringUpReset`, `CenteringUpDownDelay`.

Le funzioni dei manuali e dove stanno nella v2 sono in [INVENTARIO_FUNZIONI_ADS.md](INVENTARIO_FUNZIONI_ADS.md).

## Decisioni ancora aperte

Non cambiano il contratto. Sono in [BACKLOG_FUNZIONI.md](BACKLOG_FUNZIONI.md):

- contapezzi in avanti o all'indietro;
- elasticità in % o in gradi;
- significato di ΔT;
- HOOK;
- gruppi di programmi;
- nomi degli allarmi 104-107.
