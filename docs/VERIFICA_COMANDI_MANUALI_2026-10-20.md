# Verifica comandi manuali — Aut260045 (20/10/2026)

Branch `feature/allarmi-array`. Modifiche verificate solo staticamente: va compilato in TwinCAT XAE
(Build → Check all objects) e provato in macchina, in manuale, prima di andare in produzione.

## Come funzionano

L'HMI scrive i comandi in `Ads.Rx` e accende `ForceValueEnable` solo mentre la pagina "Manuali"
(scheda Macchina) e' aperta. Il PLC li copia sulle uscite nell'azione `MAIN.Manual`, chiamata solo con
`manualMode` (stato 2000, selettore in manuale). Le uscite delle valvole bistabili hanno il Reset =
NOT Set. `OutputMapping` porta le variabili `IO.*` sulle isole SMC (`IO.smc1`, `IO.smc2`).

## Comandi uscita (Ads.Rx → IO → SMC)

| Comando HMI (pagina Manuali) | Campo Ads.Rx | Variabile IO | Uscita | Ritorno Ads.Tx / sensori |
|---|---|---|---|---|
| USE SX su/giu' | `UseLeftUpSet` | `useLeftUpSet/Reset` | smc1[0].5/.4 | `UseLeftUp`, `UseLeftDown` |
| USE DX su/giu' | `UseRightUpSet` | `useRightUpSet/Reset` | smc1[0].7/.6 | `UseRightUp`, `UseRightDown` |
| ER SX fuori/dentro | `ErLeftOutSet` | `erLeftOutSet/Reset` | smc1[0].1/.0 | `ErLeftOut`, `ErLeftIn` |
| ER DX fuori/dentro | `ErRightOutSet` | `erRightOutSet/Reset` | smc1[0].3/.2 | `ErRightOut`, `ErRightIn` |
| Supporto SX | `SupportLeftOutSet` | `supportLeftOutSet/Reset` | smc1[2].0/.1 | nessun sensore |
| Supporto DX | `SupportRightOutSet` | `supportRightOutSet/Reset` | smc1[2].2/.3 | nessun sensore |
| EP SX fuori/dentro | `EpLeftOutSet` | `epLeftOutSet/Reset` | smc1[1].0/.1 | `EpLeftOut`, `EpLeftIn` |
| EP DX fuori/dentro | `EpRightOutSet` | `epRightOutSet/Reset` | smc1[1].4/.5 | `EpRightOut`, `EpRightIn` |
| EP SX piega | `EpLeftBend` | `epLeftBend` | smc1[1].2/.3 | `EpLeftBendDown` |
| EP DX piega | `EpRightBend` | `epRightBend` | smc1[1].6/.7 | `EpRightBendDown` |
| Morsa chiusa | `ClampCloseSet` | `clampClosedSet/Reset` | smc1[2].4/.5 | nessun sensore in Ads.Tx |
| Espulsore | `ClampEjectSet` | `clampEjectSet/Reset` | smc1[2].6/.7 | nessun sensore |
| Morse centratori 1-4 | `Clamp1..4Close` | `centringClamp1..4Left` | smc2[0].0/.2/.4/.6 | micro `CenteringMicro1..4` |
| Aria centratori 1-4 esclusa | `Centering1..4AirDisable` | `centeringLeft1..4Set` | smc2[1].0/.2/.4/.6 | — |
| **Centratori su/giu'** (nuovo) | `CenteringUpSet` | `centringSet/Reset` | smc2[2].2/.3 (+ smc2[2].0 che segue `centringSet`) | — |
| **Bloccaggio centratori** (nuovo) | `CenteringClampSet` (ex `UrLock`) | `centringClampSet` | smc2[2].4 | — |
| **Estrazione supporto centraggio** (nuovo) | `CenteringOutSet` (ex `UrUnlock`) | `centeringOutSet` | smc2[2].6 | — |
| Centratore SX/DX su/giu' | `CenteringLeftUpSet`, `CenteringRightUpSet` | `centringLeftUpSet`, `centringRightUpSet` | **nessuna** | — |

Altri comandi manuali: calibrazione assi (`Start*Calibration` + quote, pagina Calibrazione) e volantino
MPG (jog dei 5 assi, pulsanti 1 e 3 per le stesse uscite, pulsante 2 = start in manuale).

## Correzioni fatte

1. `CenteringUpSet` arrivava dall'HMI ma il PLC non lo leggeva: i centratori non si potevano alzare o
   abbassare a mano. Ora `IO.centringSet := Ads.Rx.CenteringUpSet`, `IO.centringReset := NOT IO.centringSet`.
2. `CenteringUpReset` era copiato su `IO.centeringLeftReset/RightReset`, che la `StateMachine` riscrive
   a ogni ciclo con `IO.centringSet` (fondo dell'azione): comando senza effetto, tolto.
3. Bloccaggio centratori (smc2[2].4) ed estrazione supporto (smc2[2].6) non avevano comando manuale.
   Usano i campi `UrLock`/`UrUnlock`, mai letti dal PLC, rinominati `CenteringClampSet`/`CenteringOutSet`:
   stessi byte, layout ADS invariato (HMI: proprieta' alias in `ADSModel`).
4. HMI: entrando nella pagina la forzatura partiva dai valori vecchi del comando, non dalle uscite del
   momento (es. morsa chiusa in automatico, si apriva entrando nel Test I/O). Ora i comandi si
   rileggono da Ads.Tx prima di accendere `ForceValueEnable`.

## Punti aperti (da decidere)

- **Jog da HMI non funziona.** `UseLeftFw..Ur2Bw` (tasti F1-F8, PagSu/PagGiu' dell'HMI) sono copiati in
  `jog*` in `AdsRxMapping` ma nessuno li usa: gli `MC_Jog` sono comandati solo dal volantino (con il suo
  consenso `diSafetySwitch`). Prima di collegarli va deciso il consenso (uomo presente) e la velocita'.
  Nota: `jogUSERForward := UseRightBw` e `jogUSERBackward := UseRightFw` sono incrociati.
- **Centratore SX/DX su/giu'** (`IO.centringLeftUpSet`, `centringRightUpSet`): comandati da HMI e da
  MPG, pubblicati in Ads.Tx, ma non portati su nessuna uscita in `OutputMapping`. Verificare sullo schema
  se esiste la valvola (forse sono `centringSet`/`centringReset`).
- Bloccaggio centratori ed estrazione supporto non hanno ritorno in Ads.Tx: entrando nella pagina
  ripartono spenti. Se servisse, aggiungere due BOOL in fondo a `TYPE_ADSMODEL_TX` (e nell'HMI).
- Campi Ads.Rx mai letti dal PLC: `ConnectButton`, `MotorsOffButton`, `SelectBtn`, `CancelBtn`,
  `ExecutionMode`, `StepBtn`, `MotorsOvveride`, `ManualAutoMode`, `UseLeftUp/Down`, `UseRightUp/Down`,
  `ErLeftOut/In`, `ErRightOut/In`, `SupportLeftOut/In`, `SupportRightOut/In`,
  `CenteringLeftOut/CenetringLeftIn/CenteringRightOut/CenteringRightIn`, `CenteringUpDownDelay`.
  L'HMI mostra i "Movimenti centratore" (dentro/fuori) solo per i profili precedenti, non per Aut260045.
- `IO.pc1centeringLock`/`pc2centeringLock` sono scritti da `Clamp1/2Close` ma non usati.
