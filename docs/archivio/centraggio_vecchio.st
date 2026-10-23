// Codice di centraggio tolto da MAIN.StateMachine nella fase 6 del refactoring (2026-10-23, branch refactor/core).
// Nessuna transizione del ciclo portava a questi passi: il centraggio in uso e' quello dei passi 55-90.
// Si conserva qui (e nella storia git) perche' il commento originale chiedeva di non eliminarlo.
//
// Blocco A: centraggio TL commentato e passi 300-355 (secondo centraggio TL, codice vivo ma irraggiungibile).
	(*********************** TL centering **********************)
	(*
	300:
		Ads.Tx.PrgState := 'CENTERING';
		
		FOR i:=0 TO 2 DO
			fbClearGroup[i](
				nGroupId:=i+7,
				bExecute:=TRUE,
				tTimeOut:=T#100MS );
		END_FOR
		
		IF (NOT fbClearGroup[0].bBusy) AND (NOT fbClearGroup[1].bBusy) AND (NOT fbClearGroup[2].bBusy) THEN
			fbClearGroup[0]( bExecute:=FALSE );
			fbClearGroup[1]( bExecute:=FALSE );
			fbClearGroup[2]( bExecute:=FALSE );
			state := 305;
			//IO.centeringLeftReset := FALSE;
			//IO.centeringRightReset := FALSE;
		END_IF
		
		IF fbClearGroup[0].bErr OR fbClearGroup[1].bErr OR fbClearGroup[2].bErr THEN
			fbAppendMessage(MType := MESSAGE_TYPE_ENUM.Allarm, Code := 200, MessageList := ADR(Ads.Tx.MessageList));
			state := E_CycleState.Abort;
		END_IF
		
	(*************** Set USER centering parameters ***************)  
	305:
		USERStrokeInPosition := USER.NcToPlc.ActPos - ProgramDB.parameters.inStrokeR;
		fbMoveUSERAbsolute( Axis:= USER, Execute:= FALSE);
		fbMoveUSERAbsolute.Position := USERStrokeInPosition;
		fbMoveUSERAbsolute.Velocity := USEMoveSpeed;
		
		state := 310;
		
	(*************** Execute USER centering ***************) 
	
	310:
		fbMoveUSERAbsolute.Execute := TRUE;
		state := 315;
		
	(*************** Centering switch case ***************) 
	315:
		CASE ProgramDB.parameters.pcsCycle OF
			1:
				IF IO.centering1LeftIn THEN
					centeringUSERValues[0] := USER.NcToPlc.ActPos;
					state := 320;
				END_IF
			2:
				IF IO.centering1LeftIn THEN
					centeringUSERValues[0] := USER.NcToPlc.ActPos;
				END_IF
				
				IF IO.centering2LeftIn THEN
					centeringUSERValues[1] := USER.NcToPlc.ActPos;
				END_IF
				
				IF IO.centering1LeftIn AND IO.centering2LeftIn THEN
					state := 320;
				END_IF
			3:
				IF IO.centering1LeftIn THEN
					centeringUSERValues[0] := USER.NcToPlc.ActPos;
				END_IF
				
				IF IO.centering2LeftIn THEN
					centeringUSERValues[1] := USER.NcToPlc.ActPos;
				END_IF
				
				IF IO.centering3LeftIn THEN
					centeringUSERValues[2] := USER.NcToPlc.ActPos;
				END_IF
				
				IF IO.centering1LeftIn AND IO.centering2LeftIn AND IO.centering3LeftIn THEN
					state := 320;
				END_IF
		END_CASE
	*)
	
	(******************* Clear groups for centering *******************)  
	300:
		Ads.Tx.PrgState := 'CENTERING';
		
		FOR i:=0 TO 2 DO
			fbClearGroup[i](
				nGroupId:=i+7,
				bExecute:=TRUE,
				tTimeOut:=T#100MS );
		END_FOR
		
		IF (NOT fbClearGroup[0].bBusy) AND (NOT fbClearGroup[1].bBusy) AND (NOT fbClearGroup[2].bBusy) THEN
			fbClearGroup[0]( bExecute:=FALSE );
			fbClearGroup[1]( bExecute:=FALSE );
			fbClearGroup[2]( bExecute:=FALSE );
			state := 305;
			//IO.centeringLeftReset := FALSE;
			//IO.centeringRightReset := FALSE;
		END_IF
		
		IF fbClearGroup[0].bErr OR fbClearGroup[1].bErr OR fbClearGroup[2].bErr THEN
			RaiseAlarm(Id := E_Alarm.NcCenteringClearGroup, Info := MAX(fbClearGroup[0].nErrId, fbClearGroup[1].nErrId, fbClearGroup[2].nErrId));
			state := E_CycleState.Abort;
		END_IF
	
	(*************** Prepare fast in stroke movement ***************)  
	305:	
		USERStrokeInPosition := USER.NcToPlc.ActPos - ProgramDB.parameters.inStrokeR;
		fbMoveUSERAbsolute( Axis:= USER, Execute:= FALSE);
		state := 310;
		
	(*************** Execute fast in stroke ***************) 
	310:
		fbMoveUSERAbsolute.Position := USERStrokeInPosition;
		fbMoveUSERAbsolute.Velocity := USEMoveSpeed;
		fbMoveUSERAbsolute.Execute := TRUE;
			
		IF fbMoveUSERAbsolute.Done  THEN
			IF startCondition OR Ads.Rx.NCInterpreterMode <> 1 THEN
				state := 315;
			END_IF
		END_IF
		
		IF IO.centering1LeftIn OR IO.centering2LeftIn OR IO.centering3LeftIn THEN
			state := 315;
		END_IF
		
		IF fbMoveUSERAbsolute.Error THEN
			RaiseAlarm(Id := E_Alarm.NcCenteringApproach, Info := fbMoveUSERAbsolute.ErrorID);
			state := E_CycleState.Abort;
		END_IF
	
	(*************** Evaluation after in stroke ***************) 
	315:	
		IF IO.centering1LeftIn OR IO.centering2LeftIn OR IO.centering3LeftIn THEN
			RaiseAlarm(Id := E_Alarm.CenteringPartAlreadyPresent);
			state := E_CycleState.CenteringFailed;
		ELSE
			state := 320;
		END_IF
		
	(*************** Prepare max stroke movement ***************) 
	320:	
		USERStartPosition := USER.NcToPlc.ActPos;
		USERMaxStrokePosition := USERStartPosition - ProgramDB.parameters.maxStrokeR;
		state := 325;
		
	(*************** Execute max stroke movement ***************) 
	325:	
		fbMoveUSERAbsolute.Position := USERMaxStrokePosition;
		fbMoveUSERAbsolute.Velocity := USESearchSpeed;
		fbMoveUSERAbsolute.Execute := TRUE;
		fbMoveUSERAbsolute.Options.IgnorePositionMonitoring := TRUE;
	
		IF fbMoveUSERAbsolute.Done THEN
			RaiseAlarm(Id := E_Alarm.CenteringPartNotFound);
			state := E_CycleState.CenteringFailed;
		END_IF
		
		CASE ProgramDB.parameters.pcsCycle OF
			1:
				IF IO.centering1LeftIn THEN
					IO.centringClamp1Left := TRUE;
					IO.centeringLeft1Set := TRUE;
					CenteringUSERValues[0] := USER.NcToPlc.ActPos;
					state := 335;
				END_IF
			2:
				IF IO.centering1LeftIn THEN
					IO.centringClamp1Left := TRUE;
					IO.centeringLeft1Set := TRUE;
					CenteringUSERValues[0] := USER.NcToPlc.ActPos;
				END_IF
				
				IF IO.centering2LeftIn THEN
					IO.centringClamp2Left := TRUE;
					IO.centeringLeft2Set := TRUE;
					CenteringUSERValues[1] := USER.NcToPlc.ActPos;
				END_IF
				
				IF IO.centering1LeftIn AND IO.centering2LeftIn THEN
					state := 335;
				END_IF
			3:
				IF IO.centering1LeftIn THEN
					IO.centringClamp1Left := TRUE;
					IO.centeringLeft1Set := TRUE;
					CenteringUSERValues[0] := USER.NcToPlc.ActPos;
				END_IF
				
				IF IO.centering2LeftIn THEN
					IO.centringClamp2Left := TRUE;
					IO.centeringLeft2Set := TRUE;
					CenteringUSERValues[1] := USER.NcToPlc.ActPos;
				END_IF
				
				IF IO.centering3LeftIn THEN
					IO.centringClamp3Left := TRUE;
					IO.centeringLeft3Set := TRUE;
					CenteringUSERValues[2] := USER.NcToPlc.ActPos;
				END_IF
				
				IF IO.centering1LeftIn AND IO.centering2LeftIn AND IO.centering3LeftIn THEN
					state := 335;
				END_IF
			4:
				IF IO.centering1LeftIn THEN
					IO.centringClamp1Left := TRUE;
					IO.centeringLeft1Set := TRUE;
					CenteringUSERValues[0] := USER.NcToPlc.ActPos;
				END_IF
				
				IF IO.centering2LeftIn THEN
					IO.centringClamp2Left := TRUE;
					IO.centeringLeft2Set := TRUE;
					CenteringUSERValues[1] := USER.NcToPlc.ActPos;
				END_IF
				
				IF IO.centering3LeftIn THEN
					IO.centringClamp3Left := TRUE;
					IO.centeringLeft3Set := TRUE;
					CenteringUSERValues[2] := USER.NcToPlc.ActPos;
				END_IF
				
				IF IO.centering4LeftIn THEN
					IO.centringClamp4Left := TRUE;
					IO.centeringLeft4Set := TRUE;
					CenteringUSERValues[3] := USER.NcToPlc.ActPos;
				END_IF
				
				IF IO.centering1LeftIn AND IO.centering2LeftIn AND IO.centering3LeftIn  AND IO.centering4LeftIn THEN
					state := 335;
				END_IF
		
		END_CASE
		
		IF fbMoveUSERAbsolute.Error  THEN
			RaiseAlarm(Id := E_Alarm.NcCenteringSearch, Info := fbMoveUSERAbsolute.ErrorID);
			state := E_CycleState.Abort;
		END_IF
	
	(*************** Stop execution if centering input ***************) 
	335:
		fbUSELStop.Execute := TRUE;
		fbUSERStop.Execute := TRUE;
		IO.clampClosedReset := FALSE;
		IO.clampClosedSet := TRUE;
		
		fbTlCenteringClampsDelay.IN := TRUE;
		
		IF fbUSELStop.Done AND fbUSERStop.Done AND fbTlCenteringClampsDelay.Q THEN
			IF startCondition OR Ads.Rx.NCInterpreterMode <> 1 THEN
				state := 340;
			END_IF
		END_IF
		
		IF fbUSELStop.Error OR fbUSERStop.Error THEN
			RaiseAlarm(Id := E_Alarm.NcCenteringStop, Info := MAX(fbUSELStop.ErrorID, fbUSERStop.ErrorID));
			state := E_CycleState.Abort;
		END_IF
	
		(*************** Set Use positions and block piece ***************) 
	340:
		USELEndPosition := USEL.NcToPlc.ActPos;
		USEREndPosition := USER.NcToPlc.ActPos;
		
		USELExtraPosition := USEL.NcToPlc.ActPos + ProgramDB.parameters.extraL;
		USERExtraPosition := USER.NcToPlc.ActPos + ProgramDB.parameters.extraR;
		
		IO.centringClamp1Left := FALSE;
		IO.centringClamp2Left := FALSE;
		IO.centringClamp3Left := FALSE;
		IO.centringClamp4Left := FALSE;
		
		state := 343;
		
	343:
		fbTlCenteringClampsDelay.IN := TRUE;
		
		IF fbTlCenteringClampsDelay.Q THEN
			state := 345;
		END_IF

	(*************** Move USE outwards after trigger ***************) 
	345:
		fbMoveUSELAbsolute.Execute := TRUE;
		fbMoveUSELAbsolute.Position := USELExtraPosition;
		fbMoveUSELAbsolute.Velocity := USEMoveSpeed;
		
		fbMoveUSERAbsolute.Execute := TRUE;
		fbMoveUSERAbsolute.Position := USERExtraPosition;
		fbMoveUSERAbsolute.Velocity := USEMoveSpeed;
		
		IF fbMoveUSELAbsolute.Done AND fbMoveUSERAbsolute.Done THEN
			state := 350;
		END_IF
		
		IF fbMoveUSELAbsolute.Error OR fbMoveUSERAbsolute.Error  THEN
			RaiseAlarm(Id := E_Alarm.NcCenteringExtra, Info := MAX(fbMoveUSELAbsolute.ErrorID, fbMoveUSERAbsolute.ErrorID));
			state := E_CycleState.Abort;
		END_IF
	
	(*************** Reset centering units ***************) 
	350:
		IO.centringSet := FALSE;
		IO.centringReset := TRUE;
		IO.centringLeftUpSet := FALSE;
		IO.centringLeftUpReset := TRUE;
		IO.centringRightUpSet := FALSE;
		IO.centringRightUpReset := TRUE;
		IO.centringClamp1Left := FALSE;
		IO.centringClamp2Left := FALSE;
		IO.centringClamp3Left := FALSE;
		IO.centringClamp4Left := FALSE;
		IO.centeringLeft1Set := FALSE;
		IO.centeringLeft2Set := FALSE;
		IO.centeringLeft3Set := FALSE;
		IO.centeringLeft4Set := FALSE;
		IO.centringClampSet := FALSE;

		fbCenteringUpDownDelay.IN := TRUE;
		
		IF fbCenteringUpDownDelay.Q THEN
			state := 355;
		END_IF
		
	(*************** Reset USE positions ***************) 
	355:
		fbCenteringUpDownDelay.IN := FALSE;
		IF ProgramDB.parameters.centering = CENTERING_ENUM.TB THEN
			MeasureL := USELStartPosition - USELEndPosition;
			MeasureR := USERStartPosition - USEREndPosition;
			
			ToleranceMeasure := MeasureL + MeasureR;
		END_IF
		
		state := E_CycleState.SeqInit;
		
		

// Blocco B: "centraggio rispetto ai terminali calcolato", era gia' commentato.
(******************* CENTRAGGIO RISPETTO AI TERMINALI CALCOLATO (FA FIXARE), NON ELIMINARE POTREBBE TORNARE UTILE *******************)  
(*
	(******************* Clear groups for centering *******************)  
	300:
		Ads.Tx.PrgState := 'CENTERING';
		
		FOR i:=0 TO 2 DO
			fbClearGroup[i](
				nGroupId:=i+7,
				bExecute:=TRUE,
				tTimeOut:=T#100MS );
		END_FOR
		
		IF (NOT fbClearGroup[0].bBusy) AND (NOT fbClearGroup[1].bBusy) AND (NOT fbClearGroup[2].bBusy) THEN
			fbClearGroup[0]( bExecute:=FALSE );
			fbClearGroup[1]( bExecute:=FALSE );
			fbClearGroup[2]( bExecute:=FALSE );
			state := 305;
			//IO.centeringLeftReset := FALSE;
			//IO.centeringRightReset := FALSE;
		END_IF
		
		IF fbClearGroup[0].bErr OR fbClearGroup[1].bErr OR fbClearGroup[2].bErr THEN
			fbAppendMessage(MType := MESSAGE_TYPE_ENUM.Allarm, Code := 200, MessageList := ADR(Ads.Tx.MessageList));
			state := E_CycleState.Abort;
		END_IF
	
	(*************** Prepare fast in stroke movement ***************)  
	305:	
		USERStrokeInPosition := USER.NcToPlc.ActPos - ProgramDB.parameters.inStrokeR;
		fbMoveUSERAbsolute( Axis:= USER, Execute:= FALSE);
		state := 310;
		
	(*************** Execute fast in stroke ***************) 
	310:
		fbMoveUSERAbsolute.Position := USERStrokeInPosition;
		fbMoveUSERAbsolute.Velocity := USEMoveSpeed;
		fbMoveUSERAbsolute.Execute := TRUE;
			
		IF fbMoveUSERAbsolute.Done  THEN
			IF startCondition OR Ads.Rx.NCInterpreterMode <> 1 THEN
				state := 315;
			END_IF
		END_IF
		
		IF IO.centering1LeftIn OR IO.centering2LeftIn OR IO.centering3LeftIn THEN
			state := 315;
		END_IF
		
		IF fbMoveUSELAbsolute.Error OR fbMoveUSERAbsolute.Error  THEN
			fbAppendMessage(MType := MESSAGE_TYPE_ENUM.Allarm, Code := 201, MessageList := ADR(Ads.Tx.MessageList));
			state := E_CycleState.Abort;
		END_IF
	
	(*************** Evaluation after in stroke ***************) 
	315:	
		IF IO.centering1LeftIn OR IO.centering2LeftIn OR IO.centering3LeftIn THEN
			fbAppendMessage(MType := MESSAGE_TYPE_ENUM.Allarm, Code := 5, MessageList := ADR(Ads.Tx.MessageList));
			state := E_CycleState.CenteringFailed;
		ELSE
			state := 320;
		END_IF
		
	(*************** Prepare max stroke movement ***************) 
	320:	
		USERStartPosition := USER.NcToPlc.ActPos;
		USERMaxStrokePosition := USERStartPosition - ProgramDB.parameters.maxStrokeR;
		state := 325;
		
	(*************** Execute max stroke movement ***************) 
	325:	
		fbMoveUSERAbsolute.Position := USERMaxStrokePosition;
		fbMoveUSERAbsolute.Velocity := USESearchSpeed;
		fbMoveUSERAbsolute.Execute := TRUE;
		fbMoveUSERAbsolute.Options.IgnorePositionMonitoring := TRUE;
	
		IF fbMoveUSERAbsolute.Done  THEN
			fbAppendMessage(MType := MESSAGE_TYPE_ENUM.Allarm, Code := 5, MessageList := ADR(Ads.Tx.MessageList));
			state := E_CycleState.CenteringFailed;
		END_IF
		
		CASE ProgramDB.parameters.pcsCycle OF
			1:
				IF IO.centering1LeftIn THEN
					IO.centringClamp1Left := TRUE;
					IO.centeringLeft1Set := TRUE;
					CenteringUSERValues[0] := USER.NcToPlc.ActPos;
					state := 335;
				END_IF
			2:
				IF IO.centering1LeftIn THEN
					IO.centringClamp1Left := TRUE;
					IO.centeringLeft1Set := TRUE;
					CenteringUSERValues[0] := USER.NcToPlc.ActPos;
					state := 330;
				END_IF
				
				IF IO.centering2LeftIn THEN
					IO.centringClamp2Left := TRUE;
					IO.centeringLeft2Set := TRUE;
					CenteringUSERValues[1] := USER.NcToPlc.ActPos;
					state := 330;
				END_IF
				
				IF IO.centering1LeftIn AND IO.centering2LeftIn THEN
					state := 335;
				END_IF
			3:
				IF IO.centering1LeftIn THEN
					IO.centringClamp1Left := TRUE;
					IO.centeringLeft1Set := TRUE;
					CenteringUSERValues[0] := USER.NcToPlc.ActPos;
					state := 330;
				END_IF
				
				IF IO.centering2LeftIn THEN
					IO.centringClamp2Left := TRUE;
					IO.centeringLeft2Set := TRUE;
					CenteringUSERValues[1] := USER.NcToPlc.ActPos;
					state := 330;
				END_IF
				
				IF IO.centering3LeftIn THEN
					IO.centringClamp3Left := TRUE;
					IO.centeringLeft3Set := TRUE;
					CenteringUSERValues[2] := USER.NcToPlc.ActPos;
					state := 330;
				END_IF
				
				IF IO.centering1LeftIn AND IO.centering2LeftIn AND IO.centering3LeftIn THEN
					state := 335;
				END_IF
			4:
				IF IO.centering1LeftIn THEN
					IO.centringClamp1Left := TRUE;
					IO.centeringLeft1Set := TRUE;
					CenteringUSERValues[0] := USER.NcToPlc.ActPos;
					state := 330;
				END_IF
				
				IF IO.centering2LeftIn THEN
					IO.centringClamp2Left := TRUE;
					IO.centeringLeft2Set := TRUE;
					CenteringUSERValues[1] := USER.NcToPlc.ActPos;
					state := 330;
				END_IF
				
				IF IO.centering3LeftIn THEN
					IO.centringClamp3Left := TRUE;
					IO.centeringLeft3Set := TRUE;
					CenteringUSERValues[2] := USER.NcToPlc.ActPos;
					state := 330;
				END_IF
				
				IF IO.centering4LeftIn THEN
					IO.centringClamp4Left := TRUE;
					IO.centeringLeft4Set := TRUE;
					CenteringUSERValues[3] := USER.NcToPlc.ActPos;
					state := 330;
				END_IF
				
				IF IO.centering1LeftIn AND IO.centering2LeftIn AND IO.centering3LeftIn  AND IO.centering4LeftIn THEN
					state := 335;
				END_IF
		
		END_CASE
		
		IF fbMoveUSERAbsolute.Error  THEN
			fbAppendMessage(MType := MESSAGE_TYPE_ENUM.Allarm, Code := 202, MessageList := ADR(Ads.Tx.MessageList));
			state := E_CycleState.Abort;
		END_IF
		
	(*************** Execute max stroke movement ***************) 
	330:
		state := 325;
		//fbCenteringClampsDelay.IN := TRUE;
		
		//IF fbCenteringClampsDelay.Q THEN
		//	state := 325;
		//END_IF
		
	
	(*************** Stop execution if centering input ***************) 
	335:
		fbUSELStop.Execute := TRUE;
		fbUSERStop.Execute := TRUE;
		IO.centringClamp1Left := FALSE;
		IO.centringClamp2Left := FALSE;
		IO.centringClamp3Left := FALSE;
		IO.centringClamp4Left := FALSE;
		
		IF (fbUSELStop.Done AND fbUSERStop.Done)THEN
			IF startCondition OR Ads.Rx.NCInterpreterMode <> 1 THEN
				state := 340;
			END_IF
		END_IF
		
		IF fbUSELStop.Error OR fbUSERStop.Error  THEN
			fbAppendMessage(MType := MESSAGE_TYPE_ENUM.Allarm, Code := 203, MessageList := ADR(Ads.Tx.MessageList));
			state := E_CycleState.Abort;
		END_IF
		
	
	(*************** Length calculations ***************) 
	340:
		CASE ProgramDB.parameters.pcsCycle OF
			1:
				centeringMeasures[0].length := USEL.NcToPlc.ActPos + centeringUSERValues[0] + 357.0 + 362.0 - 18.0; //USER, USEL, filetto resistenza
			2:
				centeringMeasures[0].length := USEL.NcToPlc.ActPos + centeringUSERValues[0] + 357.0 + 362.0 - 18.0;
				centeringMeasures[1].length := USEL.NcToPlc.ActPos + centeringUSERValues[0] + 357.0 + 362.0 - 18.0;
			3:
				centeringMeasures[0].length := USEL.NcToPlc.ActPos + centeringUSERValues[0] + 357.0 + 362.0 - 18.0;
				centeringMeasures[1].length := USEL.NcToPlc.ActPos + centeringUSERValues[0] + 357.0 + 362.0 - 18.0;
				centeringMeasures[2].length := USEL.NcToPlc.ActPos + centeringUSERValues[0] + 357.0 + 362.0 - 18.0;
			4:
				centeringMeasures[0].length := USEL.NcToPlc.ActPos + centeringUSERValues[0] + 357.0 + 362.0 - 18.0;
				centeringMeasures[1].length := USEL.NcToPlc.ActPos + centeringUSERValues[0] + 357.0 + 362.0 - 18.0;
				centeringMeasures[2].length := USEL.NcToPlc.ActPos + centeringUSERValues[0] + 357.0 + 362.0 - 18.0;
				centeringMeasures[3].length := USEL.NcToPlc.ActPos + centeringUSERValues[0] + 357.0 + 362.0 - 18.0;
		END_CASE
		
		state := 345;
		
	(*************** Move USEL outwards ***************) 
	345:
		fbCenteringClampsDelay.IN := TRUE;
		IO.clampClosedReset := FALSE;
		IO.clampClosedSet := TRUE;
		
		IF fbCenteringClampsDelay.Q THEN
			state := 347;
		END_IF
		
	347:
		IF ProgramDB.parameters.maxStrokeL = 0 THEN
			fbMoveUSELAbsolute.Position := USEL.NcToPlc.ActPos + 15;
		ELSE
			fbMoveUSELAbsolute.Position := USEL.NcToPlc.ActPos + ProgramDB.parameters.maxStrokeL;
		END_IF
		
		fbMoveUSELAbsolute.Velocity := USEMoveSpeed;
		fbMoveUSELAbsolute.Execute := TRUE;
		
		IF fbMoveUSELAbsolute.Done THEN
			IO.clampClosedReset := TRUE;
			IO.clampClosedSet := FALSE;
			state := 350;
		END_IF;
		
	(*************** Set air pressure ***************) 
	350:	
		IO.centeringLeft1Set := FALSE;
		IO.centeringLeft2Set := FALSE;
		IO.centeringLeft3Set := FALSE;
		IO.centeringLeft4Set := FALSE;
		
		state := 355;
		
	(*************** Clamp the longest piece ***************) 
	355:
		centeringHighestMeasure := centeringMeasures[0].length;
		actCenteringHighestMeasure := centeringMeasures[0].length;
		
		FOR i := 0 TO 3 DO
			IF centeringMeasures[i].length > centeringHighestMeasure AND NOT centeringMeasures[i].clamped THEN
				centeringHighestMeasure := centeringMeasures[i].length;
				actCenteringHighestMeasure := centeringMeasures[i].length;
			END_IF
			IF centeringMeasures[i].clamped THEN
				centeredItemsCount := centeredItemsCount + 1;
			END_IF
		END_FOR
		
		longestPieceRxPos := USER.NcToPlc.ActPos;
		
		IF centeringMeasures[0].length = centeringHighestMeasure THEN
			IO.centringClamp1Left := TRUE;
			centeringMeasures[0].clamped := TRUE;
			IO.centringClamp1Left := TRUE;
		ELSIF centeringMeasures[1].length = centeringHighestMeasure THEN
			IO.centringClamp1Left := TRUE;
			centeringMeasures[1].clamped := TRUE;
			IO.centringClamp2Left := TRUE;
		ELSIF centeringMeasures[2].length = centeringHighestMeasure THEN
			IO.centringClamp1Left := TRUE;
			centeringMeasures[2].clamped := TRUE;
			IO.centringClamp3Left := TRUE;
		ELSIF centeringMeasures[3].length = centeringHighestMeasure THEN
			IO.centringClamp1Left := TRUE;
			centeringMeasures[3].clamped := TRUE;
			IO.centringClamp4Left := TRUE;
		END_IF
		
		state := 360;
		
	(*************** Select the piece to center ***************) 
	360:
		centeredItemsCount := 0;
		
		FOR i := 0 TO 3 DO
			IF centeringMeasures[i].length > actCenteringHighestMeasure AND NOT centeringMeasures[i].clamped THEN
				actCenteringHighestMeasure := centeringMeasures[i].length;
			END_IF
			IF centeringMeasures[i].clamped THEN
				centeredItemsCount := centeredItemsCount + 1;
			END_IF
		END_FOR
		
		IF centeringMeasures[0].length = centeringHighestMeasure AND NOT centeringMeasures[0].clamped THEN
			actCenteringPieceIdx := 0;
		ELSIF centeringMeasures[1].length = centeringHighestMeasure AND NOT centeringMeasures[0].clamped THEN
			actCenteringPieceIdx := 1;
		ELSIF centeringMeasures[2].length = centeringHighestMeasure AND NOT centeringMeasures[0].clamped THEN
			actCenteringPieceIdx := 2;
		ELSIF centeringMeasures[3].length = centeringHighestMeasure AND NOT centeringMeasures[0].clamped THEN
			actCenteringPieceIdx := 3;
		END_IF
		
		state := 365;
		
		IF centeredItemsCount = ProgramDB.parameters.pcsCycle THEN
			state := 370;
		END_IF
		
	(*************** Center the piece ***************) 
	365:
		movementPosition := USER.NcToPlc.ActPos - (centeringHighestMeasure - actCenteringHighestMeasure) / 2 - 18;
		
		fbMoveUSELAbsolute.Position := movementPosition;
		fbMoveUSELAbsolute.Velocity := USEMoveSpeed;
		fbMoveUSELAbsolute.Execute := TRUE;
		
		IF (fbMoveUSELAbsolute.Done) THEN
			CASE actCenteringPieceIdx OF
				0:
					IO.centringClamp1Left := TRUE;
					IO.centeringLeft1Set := TRUE;
					centeringMeasures[0].clamped := TRUE;
				1:
					IO.centringClamp2Left := TRUE;
					IO.centeringLeft2Set := TRUE;
					centeringMeasures[1].clamped := TRUE;	
				2:
					IO.centringClamp3Left := TRUE;
					IO.centeringLeft3Set := TRUE;
					centeringMeasures[2].clamped := TRUE;
				3:
					IO.centringClamp4Left := TRUE;
					IO.centeringLeft4Set := TRUE;
					centeringMeasures[3].clamped := TRUE;
			END_CASE
			
			state := 360;
		END_IF
		
	(*************** Move USER to safe position ***************) 
	370:
		movementPosition := USEL.NcToPlc.ActPos - (longestPieceRxPos - USER.NcToPlc.ActPos);
		fbMoveUSERAbsolute.Position := longestPieceRxPos + 20;
		fbMoveUSERAbsolute.Velocity := USEMoveSpeed;
		fbMoveUSERAbsolute.Execute := TRUE;
		
		IF fbMoveUSERAbsolute.Done THEN
			state := 375;
		END_IF
		
	(*************** Center the pieces ***************) 
	375:
		fbMoveUSELAbsolute.Position := movementPosition;
		fbMoveUSELAbsolute.Velocity := USEMoveSpeed;
		fbMoveUSELAbsolute.Execute := TRUE;
		
		IF fbMoveUSELAbsolute.Done THEN
			state := 380;
		END_IF
		
	(*************** Set Use positions and block piece ***************) 
	380: 
		USELEndPosition := USEL.NcToPlc.ActPos;
		USEREndPosition := USER.NcToPlc.ActPos;
		
		USELExtraPosition := USEL.NcToPlc.ActPos + ProgramDB.parameters.extraL;
		USERExtraPosition := USER.NcToPlc.ActPos + ProgramDB.parameters.extraR;
		
		IO.clampClosedReset := FALSE;
		IO.clampClosedSet := TRUE;
		
		state := 385;

	(*************** Move USE outwards after trigger ***************) 
	385:
		fbMoveUSELAbsolute.Execute := TRUE;
		fbMoveUSELAbsolute.Position := USELExtraPosition;
		fbMoveUSELAbsolute.Velocity := USEMoveSpeed;
		
		fbMoveUSERAbsolute.Execute := TRUE;
		fbMoveUSERAbsolute.Position := USERExtraPosition;
		fbMoveUSERAbsolute.Velocity := USEMoveSpeed;
		
		IF fbMoveUSELAbsolute.Done AND fbMoveUSERAbsolute.Done THEN
			state := 390;
		END_IF
		
		IF fbMoveUSELAbsolute.Error OR fbMoveUSERAbsolute.Error  THEN
			fbAppendMessage(MType := MESSAGE_TYPE_ENUM.Allarm, Code := 204, MessageList := ADR(Ads.Tx.MessageList));
			state := E_CycleState.Abort;
		END_IF
	
	(*************** Reset centering units ***************) 
	390:
		IO.centringSet := FALSE;
		IO.centringReset := TRUE;
		IO.centringLeftUpSet := FALSE;
		IO.centringLeftUpReset := TRUE;
		IO.centringRightUpSet := FALSE;
		IO.centringRightUpReset := TRUE;
		IO.centringClamp1Left := FALSE;
		IO.centringClamp2Left := FALSE;
		IO.centringClamp3Left := FALSE;
		IO.centringClamp4Left := FALSE;
		state := 395;

	(*************** Reset USE positions ***************) 
	395:
		IF ProgramDB.parameters.centering = CENTERING_ENUM.TB THEN
			MeasureL := USELStartPosition - USELEndPosition;
			MeasureR := USERStartPosition - USEREndPosition;
			
			ToleranceMeasure := MeasureL + MeasureR;
		END_IF
		
		state := E_CycleState.SeqInit;
*)
