# Verifica PLC e gestione allarmi — Aut260045 (20/10/2026)

Branch `feature/allarmi-array` (da `feature/morsa-per-programma`). Va compilato in TwinCAT XAE
(Build → Check all objects) prima di andare in macchina: le modifiche sono state verificate solo staticamente.

## 1. Nuova gestione allarmi

Prima: lista `Ads.Tx.MessageList[0..200]` di coppie (tipo E/A/T, codice) gestita da `AppendMessage`,
`RemoveMessage`, `ClearMessageList`. Problemi: buchi lasciati da `RemoveMessage` (conteggio troncato,
messaggi a livello duplicati e poi bloccati fino al Reset), `WHILE` di conteggio senza limite superiore,
stessi codici per guasti diversi (T5/T6 salita e discesa, T17-T20 sx e dx, A231 per 5 assi, A240 per 10
scritture, A5 per due guasti), testi con il passo sbagliato (A202, A203).

Ora:

| Oggetto | Contenuto |
|---|---|
| `DUTs/E_Alarm` | enum UINT con il numero di ogni allarme (commento = significato) |
| `GVLs/Alarms` | `Active : ARRAY[0..Size.MAX_ALARM] OF BOOL`, `Info : ARRAY[..] OF UDINT` (dettaglio), `Count`, `CountBlocking`, `StartBlockedByCabinet` |
| `GVLs/Size` | `MAX_ALARM := 255` |
| `POUs/Messages/RaiseAlarm` | attiva un allarme memorizzato con il dettaglio |
| `POUs/Messages/ClearAlarms` | Reset: azzera tutto (stato 800) |
| `MAIN.AlarmManager` | ex `MessageManager`: allarmi a livello e conteggi; chiamata **dopo** `StateMachine`/`MacroManager`, così un Reset non spegne per un ciclo gli allarmi ancora presenti |

- **A livello**: sicurezza, azionamenti, quadro elettrico, climatizzatore e termostato. Rientrano da soli.
- **Memorizzati**: tutto il resto. Restano fino al Reset. I quattro "start rifiutato" si azzerano anche a ogni nuovo tentativo di start.
- `Info`: ErrorID NC/azionamento oppure numero della funzione M, così l'HMI mostra il dettaglio senza bisogno di codici diversi.
- `Ads.Tx.MessageList` resta nel DUT ma non viene più scritto: il layout ADS non cambia (l'HMI usa la stessa struct anche per le altre macchine).
- L'HMI legge `Alarms.Active` e `Alarms.Info`. I testi (titolo, causa, rimedio in IT/EN/RO) restano solo nell'HMI, con chiavi `Ui.Alarm.<numero>.*`.

### Cambi di comportamento
- **Nuovo interblocco start**: con un allarme quadro elettrico attivo (40-45: fusibile, magnetotermici, pressione aria) lo start viene rifiutato con l'allarme 66.
- **Nuovi allarmi** da ingressi che prima venivano ignorati (TRUE = guasto, come indicato): 40-45 e 92. Più gli errori dei gruppi TwinSAFE (5-8) e l'errore di homing di UR2 (162), che prima non dava messaggio.
  **Da verificare sullo schema alla messa in servizio**: se un ingresso fosse NC, l'allarme resterebbe sempre attivo e lo start bloccato. Si corregge in `AlarmManager` con un `NOT`.
- **Torretta rossa**: accesa con un allarme bloccante in qualunque modo, anche in manuale. Prima si accendeva solo in automatico, con qualunque messaggio. Gli avvisi (63-66, 90-99) non la accendono.
- **Spia start**: spenta con allarmi bloccanti. Prima `NOT messageListCount>0` era un NOT bit a bit, quindi quasi sempre vero, e il blocco era scritto due volte.

## 2. Tabella vecchi → nuovi codici

| Nuovo | Nome `E_Alarm` | Vecchio | Note |
|---|---|---|---|
| 1 | EmergencyStop | E1 | |
| 2 / 3 | DoorLeftOpen / DoorRightOpen | E2 | separati |
| 4 | LightCurtainNotReset | A26 | |
| 5-8 | SafetyMainGroupError, SafetyGroupLeft/Right/UrError | — | nuovi (FBErr/ComErr/OtherErr dei gruppi) |
| 20-24 | DriveErl / Usel / Ur2 / Err / User | E22 / E18 / E19 / E21 / E17 | Info = ErrorCode NC |
| 40-45 | FuseTripped, BreakerLeftAxis, BreakerRightAxis, BreakerUr2, BreakerChiller, AirPressureLow | — | nuovi |
| 60 | CycleResetRequired | A1 | |
| 61 / 62 | CenteringPartAlreadyPresent / CenteringPartNotFound | A5 | separati (passo 62 / passo 65) |
| 63 / 64 / 65 | StartDriveError / StartMotorsOff / StartNoProgram | A23 / A25 / A24 | |
| 66 | StartCabinetAlarm | — | nuovo interblocco |
| 90 | BatchCompleted | A3 | il vecchio testo "CONTAPEZZI = 0" era sbagliato |
| 91 | ChillerAlarm | A241 | ora a livello, prima ri-aggiunto a ogni ciclo e tolto solo col Reset |
| 92 | CabinetOverTemperature | — | nuovo |
| 100-103 | ErLeftUp/Down, ErRightUp/Down | T4/T3, T2/T1 | Info = M40-M43 |
| 104-107 | UseLeftUp/Down, UseRightUp/Down | T6, T5 | separati salita/discesa |
| 108-111 | SupportLeftOut/In, SupportRightOut/In | T26, T25 | |
| 112-119 | EpLeft/Right Bend, Out, In, BendReturn | T17, T20, T19, T18 | separati sx/dx |
| 160-164 | HomingErl … HomingUser | A231 | per asse, Info = ErrorID |
| 170-174 | ParamWriteErl … ParamWriteUser | A240 | per asse, Info = ErrorID |
| 200-205 | NcCentering… (passi 55, 61, 65, 67, 72, 76) | A200-A204 | 67 e 72 separati |
| 206-209 | NcClearGroups(Init), NcBuildGroups(Init) | A205-A208 | |
| 210-215 | NcFeedTableReset(Init), Prep(Init), Start(Init) | A209-A214 | |
| 216 / 217 | NcFeedTableRun / RunInit | A215 / A216 | |
| 218-220 | NcAbort / NcStop / NcStepOn | A217-A219 | |
| 221 | NcResetAxes | A220 | A221 (stato 820) eliminato: stato non raggiunto da nessuna transizione |
| 222-224 | NcManualEStop / ClearGroup / ResetAxes | A222-A224 | |

## 3. Bug corretti

1. **Start bloccato dopo la prima scrittura parametri** (regressione di `e24b179`). Lo stato 70 di `ParameterWriteManager` non tornava a 0, mentre lo stato 0 richiede `writeParamterState = 0`. In più `WriteParamtersDone` non tornava mai FALSE, quindi l'HMI (`MachineParametersViewModel.WriteParametersDone`, che aspetta FALSE → TRUE) andava in timeout di 30 s dalla seconda scrittura in poi. Ora `Done := FALSE` nello stato 10 e `writeParamterState := 0` nello stato 70.
2. **Errori NC dei passi 150, 140, 200 e 202 senza effetto**: dopo `state := 600` c'era `state := 200/202/210/212`, che lo sovrascriveva. Ora la transizione è nel ramo ELSE.
3. **Condizioni d'errore sbagliate**:
   - passi 905 e 910: `bErr[0] AND NOT bErr[1] AND NOT bErr[2]` diventa OR dei tre canali;
   - passo 300: `[0] OR [0] OR [0]` diventa `[0] OR [1] OR [2]`;
   - passo 310: il controllo dell'errore USEL in un moto solo USER diventa USER;
   - `FB_BuildGroups`: `[1]` ripetuto diventa `[2]`.
4. Spia start e torretta (vedi sopra).

## 4. Punti aperti (non modificati)

| Punto | Dove | Effetto | Proposta |
|---|---|---|---|
| M73 (EP rientro) usa il sensore `epLeftOut`/`epRightOut` | MacroManager, canali 0 e 1 | `SetMacro` aspetta sempre feedback TRUE: con EP fuori la macro finisce subito senza muovere, con EP dentro va in timeout (114/118) | usare `IO.epLeftIn` / `IO.epRightIn` (gli ingressi esistono) |
| M74 (EP ritorno trazione) usa come feedback l'uscita `epLeftBend` | idem | o finisce senza resettare l'uscita o va sempre in timeout (115/119) | usare `IO.epLeftBendUp` / `IO.epRightBendUp` |
| M48-M51 (spallamenti) usano l'uscita comandata come feedback | idem | non possono andare in timeout (108-111 non scattano mai) | servono sensori, se presenti |
| M47 concede la funzione M e va in abort insieme | canale 1 | comportamento ambiguo | togliere `MFuncGranted` nel ramo errore |
| M100/M101/M103 senza gestione errore; M102 in errore concede la M senza messaggio | canale 2 | ciclo fermo senza allarme / errore nascosto | aggiungere timeout e allarme |
| Nessun ELSE per funzioni M sconosciute | MacroManager | l'NC resta in attesa | ELSE con allarme e abort |
| TON `fb*DatumTimeOut` mai chiamati, segnali Datum non collegati | Manual | i rami datum timeout delle calibrazioni (Info = 0) non scattano mai | chiamare i TON o togliere i rami |
| Stati 300-355 non raggiunti da nessuna transizione; blocco commentato in fondo alla macchina a stati | StateMachine | codice morto (convertito ai nuovi allarmi solo per compilare) | eliminare |
| Lotto completato (90) in auto-loop: `State := 500` sovrascritto dal `CASE ejectMode` | stato 410 | la macchina non si ferma a fine lotto | decidere il comportamento voluto |
| Abort/stop (600/700) leggono `bBusy`/`bErr` di FB chiamate più avanti nel ciclo | 600, 700 | possibile avanzamento al primo ciclo | chiamare le FB prima del test |
| `Safety.Run` a 5 Hz con gruppo TwinSAFE in errore; errori delle singole FB TwinSAFE non mappati (`mapDiag="false"`) | SafetyManager, progetto Safety | diagnostica limitata ai bit di gruppo (allarmi 5-8) | da rivedere con il progetto safety |
| `*SafetyReset`, `*CommErrorAck`, `*OutErr` non collegati nel tsproj | Safety.TcGVL | scritture/letture senza effetto | collegare o togliere |
| UPS, `MC_Power`, `fbSoEReset`, perdita connessione ADS senza allarme | — | guasti non segnalati | eventuali allarmi futuri (numeri liberi: 9-19, 25-39, 46-59, 67-89, 93-99, 120-159, 165-169, 175-199, 225-255) |
