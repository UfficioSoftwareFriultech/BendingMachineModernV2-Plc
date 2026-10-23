# BendingMachine

Progetto TwinCAT 3 per macchina piegafilo Montorfano (Aut260045).

## Apertura progetto

Aprire `BendingMachine.sln` dalla radice del repository.

## Moduli principali

- `BendingMachine`: progetto PLC, diviso in `Core` (riutilizzabile) e `Machine` (configurazione di questa macchina).
- `BendingMachine.Safety`: progetto TwinSAFE/Safety.
- `BendingMachine.DriveManager`: configurazione drive.
- `docs`: documentazione tecnica. Punto di partenza: `docs/ARCHITETTURA.md`.

## Contratto ADS

L'HMI usa solo l'interfaccia v2: GVL `Hmi`, descritta in `docs/ADS_CONTRACT_V2.md` (profilo ADS 6 dell'HMI).
La v1 (`Ads.Rx`, `Ads.Tx`) è stata tolta; il suo contratto resta in `docs/archivio/ADS_CONTRACT_V1.md` come riferimento storico.

Prima di modificare il contratto leggere il documento.

## Estendere la macchina

Assi, valvole, ingressi, funzioni M e volantino si configurano in `BendingMachine/Machine/FB_MachineConfig.TcPOU`. La guida è in `docs/ARCHITETTURA.md`, sezione "Come si estende".
