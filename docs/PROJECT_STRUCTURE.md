# Struttura progetto

## Soluzione principale

Aprire:

```text
BendingMachine.sln
```

La solution principale include:

- `BendingMachine.tsproj`: progetto TwinCAT system manager.
- `BendingMachine/BendingMachine.plcproj`: progetto PLC.
- `BendingMachine.Safety/BendingMachine.Safety.splcproj`: progetto Safety.
- `BendingMachine.DriveManager/BendingMachine.DriveManager.tcdmproj`: Drive Manager.

## PLC

```text
BendingMachine/
  Core/       Codice riutilizzabile (assi, tabelle NC, funzioni M, diagnosi, interfaccia HMI v2).
  Machine/    Configurazione di Aut260045 (FB_MachineConfig) e centraggio.
  DUTs/       Tipi di ProgramDB e dei parametri macchina, E_Alarm, enum della macchina.
  GVLs/       Variabili globali (Hmi, Diag, Alarms, ProgramDB, IO, Safety, ...).
  POUs/       MAIN, Clock, allarmi, volantino, bimanuale.
```

La descrizione completa dei livelli, del ciclo PLC, della macchina a stati e di come aggiungere assi, valvole e funzioni M è in [ARCHITETTURA.md](ARCHITETTURA.md).

### Aree importanti

- `Machine/FB_MachineConfig.TcPOU`: assi, valvole, ingressi, funzioni M e volantino. È il punto da toccare per estendere la macchina.
- `POUs/MAIN.TcPOU`: regia del ciclo (`StateMachine`), ingressi e stato dell'HMI (`HmiInputs`, `HmiOutputs`) e mappatura degli assi (`AxisModules`).
- `GVLs/Hmi.TcGVL` e `Core/Hmi`: interfaccia HMI v2, l'unica ([ADS_CONTRACT_V2.md](ADS_CONTRACT_V2.md)).
- `GVLs/Diag.TcGVL` e `Core/Diag`: diagnosi del ciclo.
- `DUTs/E_Alarm.TcDUT`: numeri degli allarmi; i testi sono nell'HMI.
- `GVLs/Calibration.TcGVL`: quote standard per la calibrazione degli assi.

## Safety

```text
BendingMachine.Safety/
```

Contiene gruppi Safety, alias device e GVL Safety.
Non modificare senza validazione Safety TwinCAT.

## Drive Manager

```text
BendingMachine.DriveManager/
```

Contiene la configurazione drive AX e il progetto Drive Manager.

## Documentazione

```text
docs/
  ARCHITETTURA.md               livelli, ciclo, estensioni, verifiche, punti aperti
  ADS_CONTRACT_V2.md            interfaccia HMI v2 (l'unica)
  INVENTARIO_FUNZIONI_ADS.md    funzioni dei manuali e dove stanno nella v2
  BACKLOG_FUNZIONI.md           funzioni mancanti o rotte, decisioni aperte
  archivio/                     codice e documenti tolti e conservati (centraggio non usato, contratto ADS v1)
  CORREZIONI_DA_FARE.md, VERIFICA_*.md, REFACTORING_2026-06-02.md   storico
```
