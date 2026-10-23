# Inventario funzioni e interfaccia ADS v2 (Aut260045)

Data: 2026-10-23. Analisi in sola lettura, nessun sorgente modificato.

Stato del codice letto:

- PLC `refactor/core`, letto fra `f695dee` e `e63f246`. Con `cb84186` sono arrivati gli allarmi 67
  `CenteringModeNotSupported`, 68 `UnknownMFunction` e 69 `StateTimeout`; con `e63f246` i nomi dei passi
  e la GVL `Diag`. Nessuno dei due commit è ancora compilato in XAE. Dove sotto c'è scritto "(in corso)"
  vuol dire "committato, non compilato".
- HMI `HMI/BendingMachineHmi/BendingMachineModern`, branch `feature/ux-schede`.

`MAIN.TcPOU` cambia mentre scrivo, quindi per il PLC cito l'azione, il passo della `StateMachine` o il
numero M, non il numero di riga.

Questo documento è l'inventario previsto dal piano di refactoring, sezione "Inventario funzioni"
(`~/.claude/plans/proponimi-un-refactoring-per-reflective-cocoa.md`). Le funzioni mancanti o rotte, con
stima e priorità, sono in `BACKLOG_FUNZIONI.md`.

## Fonti e abbreviazioni

| Sigla | Documento | Come cito |
|---|---|---|
| PP | `OLD-FILE/50 - Utility/Parametri Programma.pdf` | numero di riga della tabella (1-40) |
| PI | `50 - Utility/Parametri Istruzione.pdf` | numero di campo. Solo i campi 1-5 sono propri; dal campo 3 il testo è copiato da PP ed è sfalsato, quindi per il resto cito PP |
| MO | `50 - Utility/Messaggi Operatore.pdf` | pagina 1 (E, A) o 2 (A22, T) |
| TP | `50 - Utility/Task_Process.pdf` | pagina unica: unità per task di X1-X6, L, IL/IR |
| NC1, NC2 | `50 - Utility/Note Centraggio - 1.pdf`, `- 2.pdf` | pagina (appunti a mano sul baricentro del recupero tolleranza) |
| UT | `50 - Utility/Utensili.pdf` | pagina 1-3 (dis. 7/4, 7/5, sch. 7/6) |
| CU, IN | `50 - Utility/CUrve.pdf`, `Interpoalzione.pdf` | paragrafo 12.7.x del manuale (estratti) |
| M | `OLD-FILE/10 - Manuali Originali/Montorfano 03517/Manuale03517_OCR.pdf` | paragrafo e pagina del manuale, es. §11.1.12 (11/3) |
| VCP | `TERMOWATT/DOCUMENTAZIONE/VERIFICA_COMPORTAMENTO_PLC.md` (2026-10-21) | sezione; da lì vengono anche le citazioni del manuale T332 |
| VFP | `TERMOWATT/DOCUMENTAZIONE/VERIFICA_FUNZIONI_PLC.md` (2026-10-19) | tabella |
| VCM | `docs/VERIFICA_COMANDI_MANUALI_2026-10-20.md` | sezione |
| PSB | HMI `Services/Plc/PlcSequenceBuilder.cs` | costanti M alle righe 37-78 |

Riferimenti PLC: `TYPE_PARAMETERS` = `ProgramDB.parameters`; `Rx`/`Tx` = `Ads.Rx` (`TYPE_ADSMODEL_RX`) e
`Ads.Tx` (`TYPE_ADSMODEL_TX`); `MRx`/`MTx` = `Machine.parametersRx/Tx` (`TYPE_MACHINE_RX/TX`);
`MM` = azione `MAIN.MacroManager`; `SM nnn` = passo `nnn` dell'azione `MAIN.StateMachine`; `FTP` =
`FB_FeedTablesPrep`; `A nnn` = `E_Alarm` numero `nnn`.

Destinazioni v2 (dal piano, sezione "ADS v2"): `Cfg`, `Cmd`, `Live`, `Sts` e `Diag` sono i blocchi della
GVL `Hmi`. `ProgramDB` resta. `MachineCfg` è la nuova GVL persistente. `aValve`, `aMFunc` e `aAxis` sono
le tabelle di `Machine/MachineConfig`. `.frt` vuol dire: resta nel file programma e nel generatore HMI,
senza campo ADS.

Stato:

- **OK**: il PLC la esegue come dice la fonte, oppure diversamente per una scelta già documentata.
- **rotta**: c'è nel codice ma non funziona o non fa quello che dice la fonte.
- **manca**: non c'è niente nel PLC.
- **solo HMI**: la gestiscono editor o generatore; il PLC non la vede e non deve vederla.
- **non applicabile**: l'unità non esiste su Aut260045 (nessun I/O in `GVLs/IO.TcGVL`) o la funzione
  non ha senso con questo hardware.

## 1. Parametri di programma (pagina 1/.. del programma)

| Simbolo e nome | Fonte | Cosa fa | Oggi nel PLC | v2 | Stato |
|---|---|---|---|---|---|
| PROGRAM / ART. (nome, articolo) | PP 1; M §11.1.4 (11/2), §11.2.2 (11/7) | Codice del pezzo, massimo 12 caratteri | `TYPE_PARAMETERS.prgName`, copiato in `Tx.programName`. Un nome nuovo resetta il ciclo (`AdsRxMapping`, `ADS_CONTRACT.md`) | `ProgramDB.parameters.prgName`; id/checksum nel comando `Cmd PROGRAM_LOADED`; nome in `Sts` | OK |
| MACHINE N° | PP 2 (nota "Non serve?"); M §11.1.3 (11/2) | Numero di macchina per la rete Bit-Bus | `machineNo`, mai letto | Esce da ProgramDB; id macchina in `Cfg` | solo HMI |
| N° OF SEQUENCES | PP 3; PI 3; M §11.1.5 (11/2), §12.2.3 (12/3) | Numero di righe del programma | `sequenceCount`, mai letto | Controllo di coerenza in `Cmd PROGRAM_LOADED`: numero di sequenze attive + checksum, rifiuto con motivo | solo HMI |
| COUNTER (contapezzi) | PP 4; M §11.1.6 (11/2), §11.2.2 d (11/7), §12.3.3 m (12/8) | Contatore che scende e ferma la macchina a zero | `pcsCounter`. Il PLC conta in su (`count += pcsCycle`, SM 410) e si ferma con l'avviso A 90 quando `count >= pcsCounter`. L'HMI corregge scrivendo `MAIN.count` | `ProgramDB.parameters.pcsCounter`, `Cmd SET_COUNT`, contapezzi in `Sts` | OK. Il verso del conteggio è diverso dal manuale: decisione aperta 1 |
| PIECE/CYCLE | PP 5; M §11.1.7 (11/3), §12.2.5 (12/3), §15.3.1 (15/5) | Pezzi per ciclo: di quanto cambia il contatore. Con il centratore dice anche quanti pezzi si caricano | `pcsCycle` (SM 410) | `ProgramDB` | OK. Il centratore non controlla il numero di pezzi (vedi area 4) |
| EJECT YES / NO 2 START / NO 1 START | PP 6; M §11.1.8 (11/3), §12.2.6 (12/3), §12.3.3 j-k (12/8); NO 1 START solo T332 (VCP "Ciclo pezzo") | Espulsione automatica, oppure fine ciclo con il pezzo da togliere a mano | `ejectMode` (`EJECT_ENUM` 0-2). SM 410 porta a 500, 50 o 420 (attesa start). Un valore sconosciuto chiude il ciclo | `ProgramDB` | OK. EJECT 3 eliminato il 2026-10-21 |
| AT / ΔT di espulsione | PP 7; M §11.1.9 (11/3), §12.2.7 (12/3) | Ritardo tra espulsione e reset del ciclo, cioè quanto restano attivi gli espulsori (decimi di s) | `deltaT` non è letto. L'HMI lo mette nell'H della M103 (PostDelay del rientro espulsore) o in una M130 del task 2. M102 tiene l'espulsore 0,5 s fissi | `ProgramDB` → H della M di espulsione in `aMFunc` | rotta: VCP "Ciclo pezzo", riga "AT di espulsione". Decisione aperta 3 |
| WEIGHT | PP 18; M §11.1.10 (11/3), §12.2.8 (12/3) | Peso del pezzo per le statistiche delle commesse | `pcWeight`, mai letto | `.frt` | solo HMI |
| USE BALANCED YES/NO | PP 11; M §11.1.11 (11/3), §12.2.9 (12/3) | Con YES le USE si aspettano a ogni operazione; con NO sono indipendenti | `useBalance` non è letto. È il generatore a mettere le M di sincronismo 60-63 e 116 | `.frt` + generatore | YES OK; NO rotta (VCP §5: pinza e UR2 anticipate, oltre 24 azioni l'HMI rifiuta) |
| USE LOCK L/R | PP 28; M §11.1.12 (11/3), §12.2.10 (12/4) | Blocca le slitte USE durante la piega (grossi diametri) | `useLockL/R` non sono letti. L'HMI genera M90/M91 (PSB:45-46, :499, :797), che non hanno un ramo in MM: oggi danno A 68 `UnknownMFunction` (prima bloccavano il canale senza allarme). Nessun I/O | Valvola `USE_LOCK_L/R` in `aValve`, M90/M91 in `aMFunc`, timeout (MO T36/T37) | manca |
| TRAN. MOV. L/R SINGLE | PP 8; M §11.1.13-14 (11/3-11/4), §12.2.11-12 (12/4) | Movimento trasversale dell'unità di piega reversibile, per piegare nei due versi | `transMovementL/R` (BOOL) non sono letti. Il generatore mette M44/45 (SX) e M46/47 (DX) al cambio di verso (VFP, riga "Movimento trasversale") | Valvola trasversale in `aValve` + M44-47 | OK |
| TRAN. MOV. DOUBLE / NO | PP 8; M §11.1.13 b-c (11/4), §12.2.11 (12/4) | DOUBLE: extracorsa per le matrici con gole. NO: niente trasversale (doppia matrice, Mod. MT) | Niente: il campo è un BOOL e l'HMI lo forza a TRUE (VFP, riga "Movimento trasversale") | Valore a 3 stati in ProgramDB; DOUBLE come seconda valvola o seconda M in `aMFunc` | manca |
| P. REF. L/R (fermo di riscontro) | PP 14; M §11.1.15 (11/4), §12.2.13 (12/4); per riga §11.2.18 | Abilita il fermo pezzi a sinistra o a destra | Nessun campo né I/O. Il flag `PieceStop` dell'HMI non arriva al PLC (`HasPlcTaskOptions=false`, VFP) | Valvola in `aValve` + M in `aMFunc` (MO T28/T29) | manca |
| HOOK L/R | PP 29 (nota "????"); M §11.1.16 (11/4), §12.2.14 (12/4), §3.2.6 (3/4) | Gancio che tiene i pezzi | `HookL/R`, con il commento "Spallamento", non letti dal PLC. L'HMI li usa per rialzare lo spallamento (M50/M48) alla riga dopo una D (PSB:150, :214, :511, :809) | Da decidere | rotta (il significato non è quello del manuale): decisione aperta 4 |
| CT / RT | PP 16-17; M §11.1.17-18 (11/4), §12.2.15 (12/4) | Tempo ciclo e tempo di attrezzaggio teorici, per le commesse | `cycTime`, `setupTime`, mai letti | `.frt` | solo HMI |
| START L/R (angolo di partenza del braccio) | PP 9; M §11.1.19 (11/4), §12.2.16 (12/4) | Angolo del braccio dopo l'azzeramento (standard 22°) | `startDegL/R` non sono letti. L'HMI li somma alle quote ER (VFP, riga "Quota, angolo") | `.frt` + generatore | solo HMI |
| START C L/R | PP 10 (nota "A spigolo??"); M §11.1.20 (11/4), §12.2.17 (12/5) | Angolo di partenza per la piega a spigolo | `startCDegL/R`: non li legge nessuno, nemmeno il generatore | `.frt` + generatore, insieme a `>` | manca |
| GUIDE ROLL L/R | PP 30; M §11.1.21 (11/5), §12.2.18 (12/5) | Abilita i rulli di spallamento apribili (pezzi profilati) | Nessun campo né I/O | Valvola + M (MO T15/T16) | manca |
| MOV. S. L/R (supporto mobile) | PP 19 (nota "Non servono per adesso?"); M §11.1.22 (11/5), §12.2.19 (12/5), cap. 17 §17.1; per riga `Z` §11.2.21 | Supporto intermedio mobile programmabile | Nessun campo. Attenzione: `SupportLeft/Right*` del PLC è lo spallamento (M48-51), non questo | Valvola + M in `aMFunc` | manca |
| RADIUS L/R, ADJ (tabelle) | PP 12; M §11.1.23 (11/5), §12.2.20 (12/5), §9.9-9.10 (9/10-9/11) | Numero della tabella raggi variabili per lato e della tabella elasticità | `radTable`, `elscTable`, mai letti | `.frt` (tabelle raggi RAD SX/DX, formato 13) | solo HMI |
| % L/R (compensazione elasticità) | PP 13; M §11.1.24 (11/5), §12.2.21 (12/5), §11.2.7 (11/8) | Percentuale che aumenta tutti i gradi reali di una testa | `elscAdjL/R`: l'HMI li somma in **gradi** all'angolo ER | `.frt` + generatore | solo HMI. Gradi o %: decisione aperta 2 |
| Pieces group counter + Open clamp | PP 21-22 | Dopo N cicli la macchina si ferma con il bloccaggio chiuso o aperto | `pcsGrpCounter`, `openClamp`, mai letti | `ProgramDB` + `FB_Cycle` (fine gruppo, stato morsa) | manca |
| Bending arm return degrees L/R | PP 23 | Gradi di ritorno del braccio prima dell'inversione; con 0 torna allo start | `returnDeg`, mai letto, nemmeno dal generatore | Generatore HMI (quota della `Return`) | manca |
| Movable bending arm | PP 20; M §11.1.32 (11/6); per riga §11.2.22 (11/11) | Braccio di piega mobile, per testa | Nessun campo né I/O | Valvola per testa + M (MO T32-T35) | manca |
| BU ON/OFF (F7, EP standard a inizio ciclo) | PP 38; M §11.1.33 (11/6) | Ogni EP ON a inizio ciclo va in posizione di piega, OFF resta abbassato | Niente: gli EP si muovono solo con le M70-74 delle righe | Flag per EP in `ProgramDB` + M di predisposizione EP | manca |
| Die movement | PP 24 (nota "Non serve") | Funzioni speciali per matrici profilate | Niente | — | non applicabile |
| Automatic piece detector, USE exit stroke | PP 25-26 | Rileva il pezzo con una corsa di uscita delle USE | Niente, nessun sensore | Ingresso + passo in `FB_Cycle` | manca |
| Feeding (alimentazione da bobina) | PP 34; M §2.2 punto 10 (2/4) | Avanzamento filo dalla bobina | Niente, nessun asse | Asse in `aAxis` (il sesto asse = trascinamento) | manca |
| LOADER, WELDING, COIL, CHANF., ROBOT, Chanfering, Welding, Robot | PP 32-37; M §11.1.25-27 (11/5), §11.1.30-31 (11/6) | Caricatore, saldatrice, ciclo da coil, smussatura, robot | Niente, nessun I/O | — | non applicabile |
| Stamping (centratore teorico) | PP 39 | Centratore teorico (in alternativa a quello meccanico, MO A16) | Niente | — | manca. Da confermare se serve: Aut260045 ha il centratore meccanico |
| Bending speed (2030/5A DS) | PP 40 | Velocità di piega per i piccoli diametri, solo su quel modello | Niente | — | non applicabile |
| Morsa del programma (CL o UR2) | M §12.3.1 (12/6), §2.1.4 (2/3) | Il programma vale per la morsa standard CL o per l'UR2; con la morsa sbagliata il controllo lo rifiuta | `normalClamp` (`ur2InUse := UR2Present AND NOT normalClamp`); asse `UR_SIM` con la morsa normale | `ProgramDB`; controllo della morsa montata al `PROGRAM_LOADED` | OK. Il controllo della morsa montata manca: `fixedClampEncode`/`mobileClampEncode` non sono letti (VCP §8) |

## 2. Funzioni di riga (pagina 2/.. e seguenti)

`TYPE_SEQUENCE`, `TYPE_TASK`, `TYPE_ACTION` e `TYPE_POSITION` restano invariati in v2. Ogni funzione
pneumatica diventa una valvola in `aValve` più le sue M in `aMFunc`, con gli stessi numeri M di oggi.

| Simbolo e nome | Fonte | Cosa fa | Oggi nel PLC | v2 | Stato |
|---|---|---|---|---|---|
| Quota USE | PI 1; M §11.2.4 (11/8) | Posizione longitudinale della testa, entro i limiti macchina | `TYPE_ACTION.pos[]` con asse USEL/USER → FTP `fEndPosX` | `ProgramDB` invariato | OK |
| Velocità USE a…o | PI 2; M §11.2.5 (11/8) | 15 velocità: "a" = 100 %, "o" = 1/15 | `TYPE_ACTION.speed`, in FTP `fVelo = speed·10` | Fattore di scala da `aAxis` invece della costante in FTP | OK |
| Tolleranza centratore ±1/2, ±1/4, ±1/6, ±1/3, ±1/8, ±3/8 | M §11.2.6 (11/8), §15.2.5 (15/4) | Frazione della tolleranza misurata da sommare alla quota USE (solo con CENTERING TB) | `centeringVerse`, `centeringAmount`. FTP: `X = pos + amount·verse·ToleranceMeasure` quando `centering >= TB`. L'HMI li copia (`ProgramShapeHost.cs:150-153`) | `ProgramDB` invariato | OK. Dettagli nell'area 4 |
| Angolo di piega | PI 3; M §11.2.7 (11/8) | Angolo del braccio, massimo circa 242° compreso START | Asse ERL/ERR → FTP `fEndPosY`, con START ed elasticità sommati dall'HMI | `ProgramDB` | OK |
| Velocità di piega a…o | PI 4; M §11.2.8 (11/9) | Come la velocità USE | `speed`, in FTP `fVelo = speed·10.8` | Scala da `aAxis` | OK |
| Senso di piega | PI 5; M §11.2.9 (11/9) | Verso l'alto o verso il basso | Segno dell'angolo; trasversale M44-47 al cambio di verso | `ProgramDB` + valvola trasversale | OK |
| T trazione persistente | M §11.2.10 (11/9), §12.5 (12/12) | Il braccio resta a fine piega fino al movimento longitudinale dopo; ignorata se la riga dopo inverte | Il generatore toglie la `Return` | `ProgramDB` | OK (VCP, riga "T") |
| E estrazione persistente | M §11.2.11 (11/9) | La testina resta abbassata fino alla fine del movimento longitudinale della riga dopo | M41 giù dopo la piega, M40 su dopo il posizionamento della riga dopo (sinistra; M42/43 a destra). Uscite `IO.erLeft/RightOut*`, A 100-103 | Valvola "estrazione SX/DX" + M40-43 | OK (tempi corretti nell'HMI il 2026-10-21, VCP "Lato HMI: fatto" 2) |
| > piega a spigolo | M §11.2.12 (11/9), §12.6 (12/13) | Routine di piega sullo spallamento (bussola + spallamento fisso) | Niente: `CornerBend` non viene generato e `startCDeg` non è letto (VFP) | Generatore + eventuale M di predisposizione | manca |
| D spallamento abbassato | M §11.2.13 (11/9); T332 p. 11/12 (VCP, riga "D") | Spallamento abbassato per la riga | M51/M49 a fine riga, M50/M48 alla riga dopo (con HOOK). Uscite `IO.supportLeft/RightOut*`, A 108-111 | Valvola "spallamento SX/DX" + M48-51 | OK per il T332; per il 03517 è diverso (VCP "Lato HMI: ancora aperto" 1) |
| C USE contemporanea all'EP | M §11.2.14 (11/10) | La piega dell'EP standard avviene durante il movimento USE | Niente | Generatore (M dell'EP fuori dal punto di sincronismo) | manca |
| I interpolazione USE-ER | M §11.2.15 a (11/10); CU/IN §12.7.3-12.7.4 | Piega con movimento USE e ER contemporanei | Azione MOVEMENT con USE+ER nello stesso gruppo NCI | `ProgramDB` | OK |
| L interpolazione 6° asse-ER | M §11.2.15 b (11/10); TP ("L - Interpolazione USE E6") | Interpolazione fra avanzamento filo ed ER sinistra | Niente: non c'è il sesto asse. Il generatore non genera azioni E6 (VFP) | Asse in `aAxis` + gruppo NC | manca |
| V asse elettrico USE | M §11.2.16 a (11/10) | Partenza e arrivo delle due USE contemporanei | Chiude solo la sequenza PLC (VFP, riga "V") | Gruppo NC a 2 assi USE, o movimenti sincroni | manca |
| W asse elettrico USE SX + 6° asse | M §11.2.16 b (11/10) | Come V, fra USE SX e sesto asse | Niente | Come V, con l'asse di trascinamento | manca |
| R raggio medio | M §11.2.17 (11/10), §12.7.2 (12/14) | Raggio medio desiderato; la macchina ne ricava lo sviluppo dalle tabelle raggio variabile | Niente: il PLC riceve quote già calcolate | `.frt` + generatore (formati 12-13) | solo HMI |
| Piega spezzata, generazione, generazione interpolata | CU §12.7.1-12.7.3 (12/13-12/15); IN §12.7.2-12.7.3 | Raggio variabile con tante pieghe piccole, con angolo persistente e spostamento, oppure con I | Niente: arrivano come righe normali | `.frt` + generatore (formati 11 e 14) | solo HMI |
| < fermo di riscontro | M §11.2.18 (11/11) | Abbassa il fermo nella riga | Niente | Valvola + M (MO T28/T29) | manca |
| G gancio tenuta pezzo | M §11.2.19 (11/11) | Toglie il gancio, attivo per tutto il ciclo, nelle righe marcate | Niente: `HookHold` non arriva al PLC (VFP) | Valvola + M (MO T21/T22) | manca |
| B spallamento bloccante | M §11.2.20 (11/11) | Interviene lo spallamento bloccante nella riga | Niente | Valvola + M (MO T30/T31) | manca |
| Z supporto mobile | M §11.2.21 (11/11) | Interviene il supporto mobile nella riga | Niente | Valvola + M | manca |
| Braccio mobile (simbolo ⇕) | M §11.2.22 (11/11) | Abilita il braccio mobile nella riga | Niente | Valvola + M (MO T32-T35) | manca |
| EP @ piega | M §11.2.23 b (11/12) | Piega dell'EP standard nella riga | M70 trazione, M74 ritorno (task 0 SX, task 1 DX), A 112/116 e 115/119. Gli ingressi `epLeft/RightBendUp/Down` non sono collegati nel tsproj (VCP "Lato PLC: fatto" 1) | Valvola "EP n trazione" + M70/M74 | rotta: senza ingressi la M70 e la M74 vanno in timeout |
| EP T trazione persistente | M §11.2.23 d (11/12) | L'EP resta in trazione | Il generatore non mette la M74 | Come sopra | OK (nel generatore) |
| EP estrazione giù / su | M §11.2.23 e, g (11/12) | Abbassa o rialza l'EP | M73 giù, M72 su, A 113-114 e 117-118. Ritorno corretto il 2026-10-21 (`epLeftIn`), non compilato | Valvola "EP n estrazione" + M72/M73 | OK (da provare in macchina) |
| EP ritardo estrazione giù / su | M §11.2.23 f, h (11/12) | Attesa in decimi di s prima dell'estrazione | Ignorato: PostDelay fissi in MM; il `delay` della macro non viene letto (VFP, riga "EP ↕") | `TYPE_MACRO.delay` letto dal dispatcher | rotta |
| EP braccio mobile, AM cambio angoli + vite 1-6 | M §11.2.23 c, i, l (11/12-11/13) | Braccio mobile dell'EP; cambio angoli meccanico | Niente | Valvola + M per il braccio; AM è meccanico | manca |
| EP numero (più EP per lato) | M §11.2.23 a (11/12) | Ogni EP ha un numero | Un solo EP per lato (M70-74 fissi per canale) | Una riga di `aValve` per EP | manca |
| AT tempo fra fine piega e operazione dopo | M §11.2.25 (11/13); §12.3.5 (12/9) | Ritardo da 0 a 99 decimi; con USE bilanciate vale il primo AT | M130 con H = AT·100 ms, fra fine piega e ritorno (generatore, VCP "Lato HMI: fatto" 3) | M130 di tipo "attesa" in `aMFunc` | OK |
| UR2 quota e velocità | M §11.2.26-27 (11/13) | Rotazione del pezzo, ±95° o ±110° | Task 2: `Positioning` UR2, oppure `UR_SIM` con la morsa normale | `ProgramDB`; limiti da `aAxis` | OK |
| S simultaneità UR2-USE | M §11.2.28 (11/14) | UR2 insieme alle USE | M80/M112 (SX) e M80/M113 (DX) dopo il posizionamento invece che prima | Sincronismo in `aMFunc` (`FB_SyncFlags`) | OK |
| Y bloccaggio pezzo | M §11.2.29 (11/14), §12.3.4 c (12/8) | Chiude la morsa nella riga | M100 chiude, M101 apre (task 2). Come ritorno usa l'uscita stessa: niente sensore, niente allarme se l'errore arriva. `IO.clampIn` e `IO.clampOpen` non sono letti (VCP §8) | Valvola "morsa" con i sensori veri + M100/M101 + timeout (MO T27) | rotta |
| H / K taglio 1 e 2 | M §11.2.30 (11/14); PP 31; F3 CUT §10.2.3 (10/4) | Unità di taglio | Niente, nessun I/O | Valvola + M (MO T13/T14) | non applicabile (senza coil né avanzamento filo) |
| F bloccaggio supplementare filo | M §11.2.31 (11/14) | Blocca il filo vicino alla raddrizzatrice | Niente | Valvola + M | non applicabile (senza avanzamento filo) |
| U semaforo attesa USE | M §11.2.32 (11/14) | Con USE non bilanciate aspetta l'ultima operazione delle due teste | M62/M61 (SX), M63/M60 (DX); chiude la sequenza | Sincronismo in `aMFunc` | OK |
| Quota e velocità 6° asse | M §11.2.33-34 (11/14-11/15) | Avanzamento filo | Niente | Asse in `aAxis` | manca |
| X1 interpolazione USE+ER+UR2 | TP (X1: USE SX - ER SX - UR2 e USE DX - ER DX - UR2); T332 p. 11/13 (VCP §1) | Tre assi in moto contemporaneo | `XYZInterpolation`: FTP scrive l'UR2 in `fEndPosX`, sopra la quota USE. L'HMI blocca il caricamento sul profilo Aut260045 (VCP "Lato HMI: fatto" 6) | `FB_FeedTableBuilder` assegna lo slot X/Y/Z dall'`axisGroup` | rotta (bloccata) |
| X2-X6 | TP | Altre terne di assi (USE SX-ER SX-USE DX, …, ER SX-ER DX-UR2) | Niente: il generatore non le produce (VFP) | Come X1 | manca |
| IL / IR interpolazione UR2-USE | TP | UR2 interpolato con la USE sinistra o destra | Come X1, in più gli assi sono nel gruppo del task 2 (VFP) | Come X1 | rotta (bloccata) |
| A, Br, M | T332 (VCP, introduzione e "Ancora da decidere") | Lettere del controllo serie 2000 | Niente | Da decidere quale manuale vale (VCP "Ancora da decidere") | manca (da decidere se servono) |

Funzioni M di servizio. Non sono nei manuali, ma servono per tenere la stessa numerazione in v2.

| M | Fonte | Cosa fa | Oggi | v2 | Stato |
|---|---|---|---|---|---|
| 60, 61, 62, 63 | PSB:41-44; MM | Sincronismo fra le USE (attesa e fatto) | MM canali 0-1, `syncAck[]`; timeout A 120-121 | `FB_SyncFlags` (set/wait/clear a maschera) | OK |
| 78, 80, 110, 112, 113, 116 | PSB:37, :39, :69-71, :74; MM | Sincronismo UR2-USE | `UR2Done`, `USEL/USER_UR2_Ack`; timeout A 122-127 | `FB_SyncFlags` | OK |
| 79, 81, 114, 115 | PSB:38, :40, :72-73 | E6 fatto/attesa; attese UR2-USE alternative | Dichiarate nell'HMI e mai generate; nessun ramo in MM | Righe di `aMFunc` solo se servono (79/81 con il sesto asse) | non applicabile |
| 54, 55, 56, 57 | PSB:59-62; MM | Trasversale su/giù senza attesa del sensore | Uscite scritte direttamente | Valvola trasversale, M di tipo "set senza attesa" | OK |
| 95, 96, 97 | PSB:63-65; MM | Attesa dello start nel passo-passo, per canale | `startCondition` | Tipo "start" in `aMFunc` | rotta: passo-passo per canale, difetto D1 di `CORREZIONI_DA_FARE.md` |
| 130 | PSB:75; MM | Attesa di H ms | `fbWaitMacro[]`; il task 2 legge ora il proprio H (VCP "Lato PLC: fatto" 4) | Tipo "attesa" | OK |
| 135 | PSB:76; MM | Numero di riga dell'editor nell'H | `lineNo1..3` → `Tx.LineNo1..3` | `Sts`, riga per canale | OK |
| 140, 150 | PSB:77-78; MM | NOP; azzeramento dei sincronismi | MM | Tipo "nop" e "clear" | OK |
| M sconosciuta | Piano, sezione "Scelte tecniche" | — | A 68 `UnknownMFunction`, Info = canale·1000 + M (in corso, non compilato). Prima il canale si bloccava senza allarme | Allarme dal dispatcher | OK (da compilare) |

## 3. Ciclo e modi

| Simbolo e nome | Fonte | Cosa fa | Oggi nel PLC | v2 | Stato |
|---|---|---|---|---|---|
| Esecuzione programma, programma caricato | M §9.4 (9/5), §12.3.1 (12/6); `ADS_CONTRACT.md` "Caricamento" | Mette un programma in esecuzione; se la macchina lavora, il cambio aspetta la fine | L'HMI scrive `ProgramDB.*` e poi dà il fronte di `Rx.ProgramLoaded`; SM 850 → 800, reset pendente se in RUN | `Cmd PROGRAM_LOADED` con conteggio sequenze + checksum e ack con motivo | OK |
| Programmare mentre la macchina lavora | M §12.2 (12/2), §9.1.2 c (9/3) | Si modifica un programma mentre ne gira un altro; quello in esecuzione non si modifica | Tutto nell'HMI; il PLC vede solo `PROGRAM_LOADED` | Come oggi | solo HMI |
| PROGRAMMA NON OK / COLLISIONE USE al caricamento | M §12.3.1 (12/6); MO A13, A14 | Programma rifiutato: quote fuori limite o morsa sbagliata | L'HMI controlla le quote (`HmiMachineLimits`); il PLC ha solo i finecorsa software NC. La morsa montata non è controllata | Rifiuto in `Cmd PROGRAM_LOADED` (`eCmdResult` con motivo) | rotta (manca la morsa; le quote solo nell'HMI) |
| AUTO / STEP (F2) | M §10.2.3 (10/4), §11.2.2 e (11/7), §12.3.3 (12/8) | Ciclo automatico o passo-passo di verifica | `Rx.NCInterpreterMode` (single block NC) + M95/96/97 | `Cmd MODE` (AUTO/STEP) + modo NC in `Live` | rotta: D1, ogni start libera solo i canali già in attesa (VCP, riga "STEP") |
| Ciclo singolo / continuo | M §12.3.5 (12/9) (AUTO in produzione); PLC `autoLoopMode` | Dopo un pezzo riparte da solo o aspetta lo start | `Rx.SignleAutoMode` → `autoLoopMode` | `Cmd SINGLE/LOOP` | OK |
| START a due mani | M §12.3.8 (12/10), §7.2.3 (7/6) | Inizio o ripresa del ciclo, con i due pulsanti insieme | `TwoHand_ReadStatus`, pulsante start, `Rx.StartBtn` (impulso) | `Cmd START` con `nCmdSeq`/ack | OK (lo start dall'HMI resta ammesso, VCP "Decisioni") |
| STOP | M §12.3.8 (12/10) | Arresto ciclo in qualsiasi momento | `Rx.StopBtn` + pulsante; `stopPending`, SM 700-745 | `Cmd STOP`; fase e `eResumeFrom` in `Sts` | OK (fasi da finire prima dello stop: VCP "Lato PLC: fatto" 6) |
| Stop memorizzato visibile | VCP "Lato PLC: ancora aperto" 7 | Durante centraggio e posizionamento lo stop si applica solo a fine fase | Non visibile dall'HMI | `Sts.ePhase` + flag stop pendente | manca |
| Ripresa dopo stop | VCP "Lato PLC: fatto" 6 (decisione 2026-10-21) | Riprende dal punto di arresto | SM 700-745, `lastState` | `FB_Cycle` `ePhase` + `eResumeFrom` | OK |
| EMERGENZA | M §12.3.8 (12/10); MO E01 | Toglie la potenza; al rilascio va rifatto l'azzeramento | Progetto Safety (TwinSAFE) + A 1 | Fuori dal refactoring (vincolo del piano) | OK |
| RESET CYCLE (F8) | M §10.2.3 (10/4); MO A01 | Resetta il ciclo; togliere il pezzo prima dello start | `Rx.ResetBtn` → SM 800 | `Cmd RESET` con ack | OK |
| Ripresa dopo reset in due start | MO A01; 09519 §2.3.2 d3 e T332 9/24 (VCP §9) | Il primo start apre la pinza, porta l'UR2 a 0 e gli ER allo start; il secondo riposiziona | Un solo start: apre la pinza mentre le USE vanno alla prima posizione | Fase dedicata in `FB_Cycle` | rotta |
| COUNT (F5) | M §10.2.3 (10/4), §11.2.2 d (11/7) | Inserisce il numero di pezzi in COUNTER | L'HMI scrive `MAIN.count` (UINT) | `Cmd SET_COUNT` | OK |
| Lotto completato | M §11.1.6 (11/2); MO A03 | La macchina si ferma a contatore zero | A 90; stop a fine pezzo, start rifiutato finché `count >= pcsCounter` (SM 10, 410) | `Sts` + allarme | OK (decisione aperta 1 sul verso) |
| REPEAT (F4) | M §10.2.3 (10/4); T332 "ripete l'ultima sequenza" (VCP, riga "REPEAT") | In STEP ripete l'ultima piega EP | Niente | `Cmd REPEAT` + `FB_SequenceRunner` | manca |
| ZERO (F6) | M §10.2.3 (10/4), §12.3.2 (12/7) | Azzeramento assi | Vedi area 7 | Vedi area 7 | Vedi area 7 |
| Sequenza del pezzo | M §12.3.4 a-m (12/8) | Carico, centraggio, bloccaggio, USE, UR2, inversione, piega, riga dopo, fine ciclo | SM 50-500, task 0-2 | `FB_Cycle` + `FB_SequenceRunner` | OK (con USE BALANCED YES: VCP "In breve") |
| Fine ciclo: morsa aperta, poi UR2 a zero | M §12.3.4 i (12/8) | Prima si rilascia il bloccaggio, poi l'UR2 torna a zero | Ordine corretto nel generatore il 2026-10-21 (VCP "Lato HMI: fatto" 4) | Generatore | OK |
| Posizionamento iniziale (INIT) | M §12.3.3 (12/8); VCP "Ciclo pezzo", riga "Inizio pezzo" | Il primo start porta le unità alla prima posizione | `ProgramDB.homing`, SM 110-412, `homingDone` | `FB_SequenceRunner` (INIT e RUN unificati) | OK |
| TIME OUT di ogni operazione | M §12.3.9 (12/10), §3.2.11 (3/5); MO T01-T53 | Dopo circa 15 s di attesa: arresto e "TIME OUT" con l'operazione; se l'anomalia passa prima, il ciclo continua | Valvole: timeout 0,5-3 s, poi abort. Attese di sincronismo: 15 s, A 120-128. Passi tecnici: A 69 `StateTimeout` dopo 10 s (in corso) | Timeout per valvola da `aValve`, watchdog di stato, M in attesa in `Sts` | OK (scelta diversa: abort subito) |
| MACCHINA IN START (attesa in corso) | M §3.2.11 (3/5) | Durante i 15 s la macchina dice cosa sta aspettando | Niente: `Tx.channelDone`/`syncAck` non li legge nessuno | Per canale: M in attesa e tempo in `Sts`; storico in `Diag` | manca |
| Gruppi di programmi | M §9.2 (9/4), §12.4 (12/10-12/11) | Sequenza di programmi con numero di esecuzioni | Niente | Decisione aperta 5 | manca |
| Commesse e statistiche | M §9.3 (9/4-9/5), cap. 26, §9.11 (9/11) | Ordini di produzione, dati statistici, peso e tempi | Niente | HMI (decisione aperta 5) | manca |
| Floppy, stampa, rete Bit-Bus | M §9.5-9.6 (9/6-9/8), cap. 13, cap. 27 | Salvataggio, stampa e rete del vecchio controllo | Niente | Backup ed export dell'HMI; nessun equivalente PLC | solo HMI |
| USE BALANCED NO | M §11.1.11 (11/3), §12.2.9 (12/3) | Teste indipendenti | Vedi area 1 | Vedi area 1 | rotta |

## 4. Centraggio (centratore automatico C2ME, capitolo 15)

| Simbolo e nome | Fonte | Cosa fa | Oggi nel PLC | v2 | Stato |
|---|---|---|---|---|---|
| CENTERING NO | PP 33; M §11.1.29 (11/6), §15.2.1 (15/3) | Centratore escluso | `CENTERING_ENUM.NO`, SM 50 → 110 | `ProgramDB` + `FB_Centering` | OK |
| CENTERING TL | M §15.2.1 (15/3), §15.3.1 (15/4) | Recupero della tolleranza sui terminali, 2 pezzi per ciclo | SM 50-80: corsa `inStroke`, ricerca `maxStroke`, `extra` | `FB_Centering` | OK |
| CENTERING TB | M §15.2.1 (15/3), §15.3.2-15.3.3 (15/5) | Recupero della tolleranza in 1-4 onde con le frazioni sulle quote USE | Come TL, più `ToleranceMeasure = MeasureL + MeasureR`; FTP sposta le quote | `FB_Centering` + `FB_FeedTableBuilder` | OK |
| CENTERING ACC | Piano ("Opzioni"), VFP, riga "Marcatura ACC" | Centraggio automatico: l'HMI calcola le frazioni dal baricentro | `CENTERING_ENUM.ACC = 3`. Prima la macchina restava ferma al passo 50; ora dà A 67 `CenteringModeNotSupported` (in corso). L'HMI converte ACC in TL (`ProgramShapeHost.cs:100-102`) | Allarme "non supportato"; poi decisione su ACC = TB con frazioni calcolate dall'HMI | manca |
| START L/R centratore | M §15.2.2 (15/3), §15.3.1 (15/4) | Posizione di partenza dei centratori | `startL/R` non sono letti dal PLC. Il generatore li usa come quota USE di homing quando `centering <> NO` (VFP, riga "Barra") | `.frt` + generatore | solo HMI |
| IN. STROKE | M §15.2.3 (15/3) | Corsa rapida di avvicinamento | `inStrokeL/R`, SM 61 | `ProgramDB` | OK |
| MAX STROKE | M §15.2.3 (15/3) | Corsa massima di ricerca; oltre: PEZZI NON OK | `maxStrokeL/R`, SM 62-65, A 62 | `ProgramDB` | OK |
| EXTRA L/R | M §15.2.4 (15/3) | Extracorsa di ritorno prima che i palpatori si abbassino | `extraL/R`, SM 76 | `ProgramDB` | OK |
| Frazioni di tolleranza per piega | M §15.2.5 (15/4), §11.2.6 (11/8), dis. 15/2-15/6 | ±1/2…±3/8 della tolleranza misurata, con TB | `TYPE_ACTION.centeringVerse/Amount` (area 2) | `ProgramDB` | OK |
| Tolleranza sulle pieghe I | VFP, riga "Piega interpolata I" | Le azioni `Interpolation` non portavano verso e quantità | Segnalato il 2026-10-19 nel generatore HMI; non ricontrollato | Generatore | rotta (da riverificare) |
| Niente tolleranza durante una T persistente | M §12.5.2 b (12/12) | La tolleranza si mette dove la T inizia, non dove continua | Niente nel PLC | Validazione nell'editor | solo HMI |
| PEZZI NON OK | M §15.3.4 (15/6); MO A05 | Pezzo assente, corto, lungo, mal posizionato, numero di pezzi diverso da PIECE/CYCLE | A 61 (pezzo già presente, SM 62), A 62 (non trovato, SM 65). Il numero di pezzi non è controllato | Allarmi uguali; controllo numero pezzi da decidere (micro `CenteringMicro1-4`) | OK (manca solo il conteggio dei pezzi) |
| Baricentro del recupero tolleranza (ACC) | NC1 p. 1-7; NC2 p. 1-3 | Trova i gruppi di pieghe con la spunta e il baricentro; correzione ½ fuori dal baricentro e ½·(1/nG)·dB vicino | HMI `Models/Programs/AutoCentering.cs` (`Calculate`, `GetBaricenter`) | `.frt` + generatore | solo HMI |
| Pieghe dopo un movimento USE senza piega | NC2 p. 4 ("IMPORTANTE") | Anche queste vanno raggruppate nel calcolo del baricentro | `AutoCentering` | Generatore | solo HMI (da verificare che il caso sia gestito) |
| Morse, aria, su/giù, bloccaggio ed estrazione centratori | M §15.1 (15/2), §15.5 (15/6); VCM, tabella | Attuatori del centratore | `IO.centringClamp1-4`, `centeringLeft/Right1-4Set`, `centringSet`, `centringClampSet`, `centeringOutSet` nella SM e in `Manual` | Valvole in `aValve` | OK |
| Centratore SX/DX su/giù | VCM "Punti aperti" | Comando del singolo centratore | `IO.centringLeft/RightUpSet` comandati ma senza uscita in `OutputMapping` | Valvola, se esiste sullo schema | rotta |
| Supporti intermedi con il centratore | M cap. 17 §17.1 | Sostengono i pezzi lunghi durante la centratura | Niente | Valvola (= supporto mobile, area 1) | manca |

## 5. Messaggi operatore (E = emergenza, A = allarme, T = time-out)

Gli allarmi v2 restano in `Alarms.Active/Info`, letti in `Sts`, con gli stessi numeri. Le valvole nuove
prendono un numero nuovo dalla configurazione.

| Codice e nome | Fonte | Cosa fa | Oggi nel PLC | v2 | Stato |
|---|---|---|---|---|---|
| E01 emergenza manuale | MO p. 1 | Pulsanti di emergenza premuti | A 1 `EmergencyStop` | Invariato | OK |
| E02 portiere aperte | MO p. 1 | Portiere posteriori aperte | A 2-3 `DoorLeft/RightOpen` | Invariato | OK |
| E03-E08 motore in sforzo (USE DX/SX, UR, 6° asse, ER DX/SX) | MO p. 1; M §12.3.7 (12/9) | L'asse non segue la quota | Errore di inseguimento NC → A 20-24 `Drive*` (Info = ErrorCode) | Errore per asse in `Sts` + allarme dall'indice in `aAxis` | OK (E06 non applicabile, niente sesto asse) |
| E09 manca filo, E10 aspo in emergenza | MO p. 1 | Avanzatore e aspo | Niente | — | non applicabile |
| E11-E16 tempo di frenatura errato | MO p. 1 | Il motore non si ferma in tempo dopo la barriera | Funzioni di sicurezza TwinSAFE; A 4-8 | Fuori dal refactoring | non applicabile |
| E17-E22 azionamento in allarme | MO p. 1 | Convertitore in allarme | A 20-24 | Allarme per asse da `aAxis` | OK (E20 non applicabile) |
| A01 eseguire il reset ciclo | MO p. 1 | Dopo un timeout o un allarme | A 60 `CycleResetRequired` | Invariato | OK |
| A02 espulsore fuori | MO p. 1 | Con l'espulsore fuori l'UR2 non ruota | Niente; A 128 copre solo il caso inverso (UR2 non a zero all'espulsione) | Interblocco UR2 + allarme nuovo | manca |
| A03 contapezzi = 0 | MO p. 1 | Inserire il numero di pezzi | A 90 `BatchCompleted` | Invariato | OK |
| A04 caricatore vuoto, A08 emergenza robot, A09-A12, A15 (incongruenze caricatore, robot, saldatrice, coil) | MO p. 1 | Caricatore, robot, saldatrice | Niente | — | non applicabile |
| A05 pezzi non OK | MO p. 1 | Centratore | A 61, 62 | Invariato | OK |
| A06 barriera intercettata | MO p. 1 | Barriera, start a due mani per ripartire | A 4 `LightCurtainNotReset` | Invariato | OK |
| A07 pressione aria insufficiente | MO p. 1 | Pressostato | A 45 `AirPressureLow` (`AlarmManager`) | Invariato | OK |
| A13 programma non OK, A14 collisione USE | MO p. 1; M §12.3.1 (12/6) | Rifiuto del programma | Area 3, riga "PROGRAMMA NON OK" | `eCmdResult` del `PROGRAM_LOADED` | rotta |
| A16 centratore con centratura teorica | MO p. 1 | Incongruenza di programmazione | Niente (non c'è il centratore teorico) | — | non applicabile |
| A17-A21 saldatrice, smussatore, robot | MO p. 1-2 | — | Niente | — | non applicabile |
| A22 NC TABLE ENTRY ERROR | MO p. 2 | Errore della tabella NC | A 200-225 `Nc*` (Info = ErrorID) | Invariati; contesto dell'abort in `Diag` | OK |
| T01-T04 estrazione DX/SX giù/su | MO p. 2 | Timeout della testina | M40-43 → A 100-103 | Allarme per valvola da `aValve` | OK. I nomi degli allarmi vanno ricontrollati: decisione aperta 6 |
| T05-T06 movimento trasversale DX/SX | MO p. 2 | Timeout del trasversale | M44-47 → A 104-107, che però si chiamano "USE salita/discesa" | Come sopra | OK (nomi incoerenti: decisione aperta 6) |
| T07 espulsione | MO p. 2 | Timeout espulsore | M102: in caso di errore concede la M senza allarme; M103 senza gestione errore | Valvola "espulsore" con timeout e allarme | rotta |
| T08-T14 caricatore, saldatrice, robot, smussatrice, taglio H/K | MO p. 2 | — | Niente | — | non applicabile |
| T15-T16 rulli di spallamento | MO p. 2 | — | Niente | Allarme della valvola nuova | manca |
| T17-T20 EP n trazione, ritorno, estrazione giù/su | MO p. 2 | — | A 112-119 (un EP per lato) | Allarme per valvola | rotta (ingressi EP non collegati, area 2) |
| T21-T22 gancio DX/SX | MO p. 2 | — | Niente | Allarme della valvola nuova | manca |
| T23-T24, T32-T35 braccio mobile/matrice EP ed ER | MO p. 2 | — | Niente | Allarme della valvola nuova | manca |
| T25-T26 spallamento DX/SX | MO p. 2 | — | M48-51 → A 108-111. Come ritorno usano l'uscita stessa (`IO.supportLeftOutSet`): niente sensore | Valvola "spallamento" | OK (senza sensore il timeout non scatta mai) |
| T27 bloccaggio pezzo | MO p. 2 | Timeout della morsa | M100/M101 senza sensore e senza allarme | Valvola "morsa" | rotta |
| T28-T29 fermo pezzo, T30-T31 spallamento bloccante | MO p. 2 | — | Niente | Allarme della valvola nuova | manca |
| T36-T37 blocco USE DX/SX | MO p. 2 | — | Niente (M90/M91 → A 68) | Allarme della valvola `USE_LOCK` | manca |
| T38 cilindro N | MO p. 2 | Timeout di un cilindro generico | Niente | Allarme per valvola (Info = indice in `aValve`) | manca |
| T39-T42 aggancio utensile alla slitta, carro utensile | MO p. 2 | Cambio attrezzatura automatico | Niente | — | non applicabile |
| T43-T50 smussatore, saldatrice | MO p. 2 | — | Niente | — | non applicabile |
| T51-T53 attesa USE L, USE R, UR2 | MO p. 2 | Timeout delle attese fra unità | A 120-127, 15 s | `FB_SyncFlags` con timeout | OK |
| Messaggi del centraggio, NC, calibrazione, quadro, M sconosciuta, passo bloccato | PLC `E_Alarm` (nessuna fonte nei manuali) | Diagnosi del controllo nuovo | A 40-45, 61-69, 91-92, 160-174, 200-225 | Invariati | OK |
| Lista messaggi `Tx.MessageList` | `TYPE_ADSMODEL_TX` (commento "obsoleto") | Vecchia coda messaggi | Scritta solo in codice commentato; sempre vuota | Eliminata | non applicabile |

## 6. Comandi manuali e test I/O

| Simbolo e nome | Fonte | Cosa fa | Oggi nel PLC | v2 | Stato |
|---|---|---|---|---|---|
| Test input | M §9.8.1 (9/10), §6.2.3 (6/7) | Stato degli ingressi | Ritorni in `Tx` (`ErLeftIn`, `UseLeftUp`, `EpLeftOut`, `CenteringMicro1-4`, …) | Ingressi rilevanti e feedback per valvola in `Sts` | OK |
| Test output SET OUT / CLR OUT | M §9.8.2 (9/10) | Forza la singola uscita; entrando si disabilitano tutte | `Rx.ForceValueEnable` + campi `*Set` → azione `Manual` (solo con il selettore in manuale) | `Live.aValveCmd[i]` (nessuno/set/reset) + abilitazione forzature | OK (diverso per scelta: le uscite non si azzerano entrando, VCP "Comandi manuali") |
| Codici segreti (C, D) | M §9.7 (9/8), §9.8 (9/9), §3.2.7 (3/5) | Proteggono parametri e test | Niente | Utenti e licenze dell'HMI | solo HMI |
| Jog assi da HMI | VCM "Punti aperti"; il 03517 non ha jog (VCP "Comandi manuali") | Movimento degli assi dai tasti dell'HMI | `Rx.UseLeftFw..Ur2Bw` copiati in `jog*` (`AdsRxMapping`) ma non arrivano agli `MC_Jog`; USE DX avanti e indietro incrociati | `Live` jog (indice asse, direzione) → `FB_AxisModule` | rotta |
| Volantino MPG | VCP "Comandi manuali", riga "Jog assi" | Jog dei 5 assi con consenso `diSafetySwitch` | `MPG_ReadStatus`, `Tx.MPGAxisSelection/Speed` | `FB_AxisModule` per indice; selezione in `Sts` | OK |
| Motori on / off | M §7.2 (7/5-7/6) (comandi elettrici); PLC | Abilita la potenza degli azionamenti | `Rx.MotorsOnBtn` (impulso), `MotorStatusManager`; `Tx.MotorsOn/MotorsEnable` | `Cmd MOTORS_ON/OFF` | OK |
| Override | PLC (non nel manuale) | Percentuale di velocità | `Rx.IpOvveride` → override canali, ridotto vicino alla pinza | `Live.override` | OK |
| Selettore manuale/automatico | PLC (SM 2000-2100) | Modo manuale dal selettore | Selettore fisico; `Tx.ManualMode` | `Sts` | OK |
| Apertura pinza a macchina ferma | VCP "Comandi manuali", ultima riga | Apre la morsa senza ciclo | Stop tenuto più di 1 s o `bimanualOpenClamp` (SM 0, 620, 719) | Invariato o `Cmd` dedicato | OK (diverso dal manuale) |
| Tabelle raggio ed elasticità con macchina in movimento | M §9.9-9.10 (9/10-9/11), §3.2.7 (3/5) | Le tabelle si tarano facendo muovere la macchina da tastiera | Niente | — | non applicabile (tabelle solo nell'HMI) |

## 7. Calibrazione, azzeramento e parametri macchina

| Simbolo e nome | Fonte | Cosa fa | Oggi nel PLC | v2 | Stato |
|---|---|---|---|---|---|
| ZERO (F6) azzeramento motori | M §10.2.3 (10/4), §12.3.2 (12/7) | Azzeramento con start a due mani: prima l'UR2, poi USE ed ER | Encoder assoluti: `Rx.Start*Calibration` → `MC_Home` `MC_Direct` sulla quota (`Calibration.*HomePosition` o `Rx.*CalibrationPosition`), cinque CASE nell'azione `Manual` (solo in manuale) | `Cmd CALIBRATE(asse, quota)` → `FB_AxisModule` | OK (diverso per scelta, VCP "Ciclo pezzo", riga "Azzeramento") |
| Ordine UR2 → USE → ER | M §12.3.2 A-B (12/7) | Ordine dell'azzeramento | Ogni asse si calibra da solo | Ordine eventuale in `aAxis` | non applicabile (encoder assoluti) |
| Calibrazione fatta / asse calibrato | PLC; M §12.3.2 C (12/7) | Verifica dopo l'azzeramento | `Tx.*CalibrationDone`, `MRx.*Calibrated`, `*CheckDone` | `Sts` per asse (calibrato) + `MachineCfg` | OK |
| Calibrazione fallita | PLC | — | A 160-164 | Allarme per asse | OK |
| Parametri macchina: limiti assi | M §9.7.1 (9/8), §3.2.3 (3/4), §11.2.4 (11/8) | Limiti di quota per asse, protetti da codice | `MRx.UseL/R…, ErL/R…, UrR Upper/LowerLimit`, scritti negli assi da `ParameterWriteManager` con `Rx.WriteParameters`; A 170-174 | `MachineCfg` per asse + `Cmd WRITE_PARAMS`; limiti anche in `Cfg` | OK |
| Presenza assi | M §12.3.2 N.B. (12/7) (UR2 assente: salta l'azzeramento UR2) | Macchina con o senza UR2 | `MRx.*Present` | `aAxis` + `MachineCfg` | OK |
| USE minima vicino alla pinza (95 / 65 mm) | VFP "Distanza minima pinza ↔ testa" | Limite software basso delle USE, secondo la morsa | Costanti `ur2USEL/RMinPosition`, `urUSEL/RMinPosition` in `MAIN`, non esposte | `aAxis` (limite per morsa) + `Cfg` | OK (non visibile all'HMI) |
| Ultima posizione nota | PLC | Posizione degli assi salvata | `MTx.last*KnownPosition` (`OutputMapping`) | `MachineCfg` | OK |
| Sirena | PLC | Esclude la sirena | `MRx.EnableSirenOverride` | `MachineCfg` | OK |
| Controllo di sforzo | M §12.3.7 (12/9) | Ferma la macchina se un asse non segue | Errore di inseguimento NC → A 20-24 | Errore per asse in `Sts` | OK |
| Salvataggio, lettura, stampa, cancellazione dei parametri | M §9.7.2-9.7.5 (9/9) | Parametri impianto su dischetto | Niente | Backup dell'HMI | solo HMI |
| Configurazione I/O | M §9.7.6-9.7.8 (9/9) | Carica la mappa degli I/O | tsproj | `IoMapping` (compilato) | non applicabile |
| Sostituzione encoder | M §6.3.1 (6/8), §6.3.5 (6/13) | Va rifatto l'azzeramento | Ricalibrazione | `Cmd CALIBRATE` | OK |
| Dati di funzionamento macchina | M §9.11 (9/11) | Statistiche per il costruttore | Niente | Contatori in `Diag` (facoltativo) | manca |

## 8. Utensili e tabelle

| Simbolo e nome | Fonte | Cosa fa | Oggi nel PLC | v2 | Stato |
|---|---|---|---|---|---|
| Diametri d / D per modello | UT p. 1 | Diametro filo e bussola ammessi per macchina (2010, 2014, 2020, 2030) | Niente | Cartelle e altezze utensili nell'HMI | solo HMI |
| Composizione attrezzatura a doppia matrice | UT p. 1-2 (dis. 7/4, 7/5) | Come si monta l'utensile | Niente | — | solo HMI |
| Calcolo del braccio Bs e angolo di avvicinamento | UT p. 3 (sch. 7/6) | `X1 = D/2 + d/2 + @`, `Bs = √(X1² − Y²)`, `tan β = Bs/X1` | Niente: il PLC riceve l'angolo già corretto | Generatore (angolo di avvicinamento) | solo HMI |
| Tabella raggio variabile | M §9.9 (9/10); PP 12 | Raggio realizzato in funzione dei gradi, per attrezzatura | `radTable` non letto | `.frt` | solo HMI |
| Tabella elasticità | M §9.10 (9/11); PP 12 | Correzione dell'angolo per materiale | `elscTable` non letto | `.frt` | solo HMI |
| Gradi teorici / reali | M §10.2.1 F8 opzione 6 (10/3), §11.2.7 (11/8) | Mostra i gradi corretti dalla % | Niente | Editor | solo HMI |
| Copia o inverti SX/DX, correzione quote | M §10.2.1 F8 opzioni 1-5 (10/3) | Strumenti di programmazione | Niente | Editor | solo HMI |
| Montaggio e regolazione attrezzatura e unità | M §7.1 (7/2-7/3), cap. 14 | Regolazioni meccaniche | Niente | — | non applicabile |
| Morsa montata (fissa o mobile) | M §12.3.1 (12/6); I/O `fixedClampEncode`, `mobileClampEncode` | Riconosce l'unità di bloccaggio montata | Ingressi dichiarati e mai letti (VCP §8) | Ingressi in `Sts` + controllo al `PROGRAM_LOADED` | manca |

## Campi v1 da eliminare

Verificati il 2026-10-23 con uno script di grep:

- PLC: ricerca `Rx.<campo>` / `Tx.<campo>` / `parametersRx.<campo>` / `parameters.<campo>`, senza
  distinguere maiuscole e minuscole (lo ST non le distingue), su tutti i `.TcPOU` e `.TcGVL` di
  `BendingMachine`.
- HMI: ricerca della proprietà corrispondente nei `.cs` e `.xaml` di
  `HMI/BendingMachineHmi/BendingMachineModern`. Sono escluse le dichiarazioni dei modelli in
  `Services/Ads/ADSService.cs` e il mapper `Services/AdsMapping/AdsModelCompactMapper.cs`.
- L'allineamento campo per campo fra `TYPE_ADSMODEL_RX/TX` e `ADSModel`/`ADSModelRx` è per posizione:
  83 campi RX e 94 TX su entrambi i lati. `CenteringClampSet`/`CenteringOutSet` dell'HMI sono alias di
  `UrLock`/`UrUnlock` e non contano.
- Script e risultato: nello scratchpad di questa sessione (`adsuse.py`, `adsuse.txt`), non salvati nel
  progetto.

### Ads.Rx (HMI → PLC) mai letti dal PLC

| Campo | Scritto dall'HMI? | Nota |
|---|---|---|
| `ConnectButton`, `MotorsOffButton`, `SelectBtn`, `CancelBtn`, `StepBtn`, `ManualAutoMode`, `MotorsOvveride` | No, solo nei modelli e nel mapper | Già elencati in VCM "Punti aperti" |
| `ExecutionMode` | No. Nell'HMI `ExecutionMode` è un enum di `ExecutionModeState.cs`; il modo viaggia in `NCInterpreterMode` + `SignleAutoMode` | — |
| `UseLeftUp/Down`, `UseRightUp/Down`, `ErLeftOut/In`, `ErRightOut/In`, `SupportLeftOut/In`, `SupportRightOut/In` | No. I nomi uguali nell'HMI sono i ritorni di `Ads.Tx` | Doppioni dei comandi `*Set` |
| `CenteringLeftOut`, `CenetringLeftIn`, `CenteringRightOut`, `CenteringRightIn` | Sì, da `TestInputOutputViewModel` per i profili precedenti; per Aut260045 la pagina non li mostra (VCM) | — |
| `CenteringUpReset` | Sì (`= !CenteringUpSet`, `TestInputOutputViewModel.cs:89`) | Il PLC usa Reset = NOT Set (VCM "Correzioni" 2) |
| `CenteringUpDownDelay` | No | Il PLC usa un TON fisso di 800 ms |

Campi che il PLC legge ma che in v2 cambiano forma:

- `StartBtn`, `StopBtn`, `ResetBtn`, `MotorsOnBtn`, `ProgramLoaded` e `WriteParameters` sono impulsi.
  Diventano `Cmd` con `nCmdSeq` e ack.
- I cinque `Start*Calibration` e le quote `*CalibrationPosition` con `CalibrationPositionEnable`
  diventano `Cmd CALIBRATE(asse, quota)`.
- I dieci bit di jog (`UseLeftFw` … `Ur2Bw`) diventano `Live` jog (asse, direzione).
- I comandi di uscita diventano `Live.aValveCmd[]`. Sono 25: i 12 campi `*Set`, `EpLeft/RightBend`,
  `Clamp1-4Close`, `Centering1-4AirDisable`, `CenteringUpSet` e i due alias.
- `WatchDog` (BOOL) diventa un contatore in `Live`.
- `IpOvveride` va in `Live`.
- `SignleAutoMode` e `NCInterpreterMode` diventano `Cmd MODE`.

### Ads.Tx (PLC → HMI) mai scritti dal PLC

| Campo | Letto dall'HMI? |
|---|---|
| `ProgramRun`, `ProgramEnable`, `ProgramStop`, `ProgramCanStop` | No |
| `MessageList[0..200]` | Sì (`OperatorMessageStore.cs:65`), ma è sempre vuota: il PLC la scrive solo in codice commentato (passo 300 e centraggio archiviato) |

### Ads.Tx scritti dal PLC ma mai letti dall'HMI

| Campo | Destinazione v2 |
|---|---|
| `PrgState` (STRING) | Enum di stato e fase in `Sts` |
| `State` | `Sts` (oggi l'HMI non lo legge; lo cita solo un commento in `AlarmCatalog.cs:18`) |
| `homingDone` | Fase del ciclo in `Sts` |
| `USELDone`, `USERDone`, `UR2Done`, `USEL_UR2_Ack`, `USER_UR2_Ack`, `UR2_USEL_Req`, `UR2_USER_Req`, `syncAck1-3`, `channelDone1-3` | `Sts` per canale (M in attesa, tempo, done) e `Diag`. I nomi uguali nell'HMI sono costanti M di `PlcSequenceBuilder`, non questi campi |
| `programIdle`, `programAborted` e gli impulsi `programIdlePulse`, `programCanExecutePulse`, `programStoppedPulse`, `programRunningPulse` | Stato del ciclo in `Sts`; il lampeggio si fa nell'HMI |
| `CenteringLeftReset`, `CenteringRightReset`, `CenteringLeftIn1`, `CenteringLeftIn2` | Feedback per valvola e ingressi in `Sts` |
| `AutoMode` | Modo in `Sts` |

Tutti gli altri campi TX sono letti dall'HMI e passano a `Sts`: `MotorsOn`, `MotorsEnable`,
`programCanExecute`, `programStopped`, `programRunning`, `programAbortedPulse`, `Count`, `LineNo1-3`,
`MPGAxisSelection/Speed`, `*CalibrationDone`, `programName`, i ritorni delle uscite e dei sensori,
`Clamp1-4Close`, `Centering1-4AirDisable`, `CenteringUp*`, `CenteringMicro1-4`, `ManualMode`,
`WriteParamtersDone`.

### Letture separate da togliere

`ADSService.cs:379-391` legge a ogni ciclo `MAIN.<asse>.NcToPlc`, `MAIN.<asse>.Status` (5 assi) e
`MAIN.in_stNciToPlc[0..2]`. In v2 queste informazioni stanno in `Sts`, che si legge in un blocco solo.

### ProgramDB.parameters (TYPE_PARAMETERS) senza uso nel PLC

Il PLC legge solo `prgName`, `pcsCounter`, `pcsCycle`, `ejectMode`, `centering`, `inStrokeL/R`,
`maxStrokeL/R`, `extraL/R` e `normalClamp` (grep su `MAIN.TcPOU` e `NC/*.TcPOU`).

| Campo | Chi lo usa | Destinazione v2 |
|---|---|---|
| `sequenceCount` | Nessuno | Controllo di coerenza nel `Cmd PROGRAM_LOADED` |
| `machineNo`, `radTable`, `elscTable`, `cycTime`, `setupTime`, `pcWeight` | Nessuno nel PLC | Solo `.frt` |
| `startDegL/R`, `elscAdjL/R`, `useBalance`, `transMovementL/R`, `startL/R` | Solo il generatore HMI | Solo `.frt` |
| `HookL/R`, `useLockL/R` | Solo il generatore HMI (M50/48, M90/91) | Si decidono con le valvole (decisione aperta 4, backlog USE LOCK) |
| `deltaT` | Il generatore lo mette nell'H di una M | `.frt`, oppure resta se la decisione aperta 3 lo vuole nel PLC |
| `startCDegL/R`, `returnDeg`, `pcsGrpCounter`, `openClamp` | Nessuno | Restano solo se si fanno le funzioni del backlog |

Nessun campo di `Machine.parametersRx/Tx` è morto: sono tutti letti o scritti in `MAIN`. In v2 passano a
`MachineCfg` per asse.
