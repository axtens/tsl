MODULE TextSubstitutionLanguage;

FROM ASCII IMPORT NUL, CR, LF, HT;
FROM Strings IMPORT Copy, Assign, Append, Length, Pos, Insert, Delete, CompareStr;
FROM SLICE IMPORT Slice;
FROM XDOS IMPORT BlockReadCreate, BlockReadDestroy, BlockReadLine, ReadFileLine;
IMPORT Files;
FROM XString IMPORT IndexInList, Exact, UpperCase,
        RightTrim, Equiv, GetResponse, LeftTrim;
FROM System IMPORT GetArg, Terminate, GetEnv;
FROM DevIO IMPORT CardOut, WriteOut, LineOut;
FROM FileSpec IMPORT HasExt, DropExt;
FROM SYSTEM IMPORT ADR;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM INLine IMPORT InLine;
FROM DEBUG IMPORT SetDebug, DebugL, DebugS, DebugC;

IMPORT Display;

    CONST
        cMaxSubst = 200;
        cMaxCheck = 200;
        xDOT      = ".";
        sVERSION  = "2.13";

    TYPE

        tString = ARRAY [0..255] OF CHAR;
        tSString= ARRAY [0..127] OF CHAR;
        tSubst  = RECORD
                    loc,
                    ins : tSString;
                    cnf,
                    cas,
                    who : BOOLEAN;
                  END;
        taSubst = ARRAY [0..cMaxSubst] OF tSubst;
        ptaSubst= POINTER TO taSubst;
        tCheck  = RECORD
                    cloc : tSString;
                    ccas,
                    cwho : BOOLEAN;
                  END;
        taCheck = ARRAY [0..cMaxSubst] OF tCheck;
        ptaCheck= POINTER TO taCheck;

    VAR
        sWordBreak,
        sParamFile,
        sFileName,
        sRecord,
        sSlice,
        sKeyword,
        sString1,
        sString2,
        sParam,
        sBAK,
        sTMP,
        sFILE       : tString;

        cScriptCnt,
        cCheckCheck,
        cSubstSubst,
        cLineCnt,
        cCheckCnt,
        cSubstCnt,
        cCnt        : CARDINAL;

        iBuff       : INTEGER;

        bShow,
        bShowTotals ,
        bShowCounter,
        bShowLineNum,
        bDuplicates,
        bCheckDefined,
        bAbort,
        bParamFile,
        bDropOut,
        bDirty,
        bFileDefined,
        bSubstDefined,
        bDebug,
        bCase,
        bConfirm    : BOOLEAN;

        aSubst      : ptaSubst;
        aCheck      : ptaCheck;





    PROCEDURE Max( cCard1, cCard2 : CARDINAL) : CARDINAL;
        BEGIN
            IF cCard1 > cCard2 THEN
                RETURN cCard1
            ELSE
                RETURN cCard2
            END
        END Max;

    PROCEDURE Syntax;
        BEGIN
            LineOut('Syntax:');
            LineOut('        TSL <filename[.TSL]> [filename]');

        END Syntax;

    PROCEDURE Error( sMsg : ARRAY OF CHAR);
        BEGIN
            WriteOut("Line ");
            CardOut(cScriptCnt,1);
            WriteOut(": ");
            LineOut( sMsg);
            Terminate(2)
        END Error;

    PROCEDURE StopRun;
        BEGIN
            DISPOSE(aSubst);
            DISPOSE(aCheck);
            Files.Close(iBuff);
            Terminate(0)
        END StopRun;

    PROCEDURE VideoOut( sLine : ARRAY OF CHAR; cStart, cLength : CARDINAL);
        VAR
            sTemp : tString;
            c     : CARDINAL;

        PROCEDURE Show;
            BEGIN
                IF Length(sTemp) > 0 THEN
                    FOR c := 0 TO Length(sTemp)-1 DO
                        Display.Write( sTemp[c])
                    END;
                END;
            END Show;

        BEGIN
            Copy(sLine,0,cStart,sTemp);
            LeftTrim(sTemp);
            Show;

            Display.displayAttr := 70H;

            Copy(sLine,cStart,cLength,sTemp);
            Show;

            Display.displayAttr := 07H;

            Copy(sLine,cStart+cLength,255,sTemp);
            Show;

            Display.displayAttr := 07H;
            Display.Write( (CR));
            Display.Write( CHAR(LF));

        END VideoOut;

    PROCEDURE KeywordArray( sKey : ARRAY OF CHAR) : CARDINAL;
        VAR
            aKeys : ARRAY [1..20] OF ARRAY [0..9] OF CHAR;
            cIdx  : CARDINAL;
        BEGIN
            aKeys[1] := "FILE      ";
            aKeys[2] := "SUBST     ";
            aKeys[3] := "GO        ";
            aKeys[4] := "MESSAGE   ";
            aKeys[5] := "END       ";
            aKeys[6] := "CHECK     ";
            aKeys[7] := "BREAKON   ";
            aKeys[8] := "DUPLICATES";
            aKeys[9] := "NOTE      ";
            aKeys[10]:= "SHOW      ";
            FOR cIdx := 1 TO 10 DO
                IF Equiv(sKey, aKeys[cIdx]) THEN
                    RETURN cIdx
                END
            END;
            RETURN 0
        END KeywordArray;


    PROCEDURE ClearArrays;
        VAR
            cCnt : CARDINAL;

        BEGIN
            FOR cCnt := 1 TO cMaxSubst DO
                aSubst^[cCnt].loc := '';
                aSubst^[cCnt].ins := '';
                aSubst^[cCnt].cnf := TRUE;
                aSubst^[cCnt].cas := TRUE;
                aSubst^[cCnt].who := FALSE
            END;
            cSubstCnt := 0;
            FOR cCnt := 1 TO cMaxCheck DO
                aCheck^[cCnt].cloc := '';
                aCheck^[cCnt].ccas := TRUE;
                aCheck^[cCnt].cwho := FALSE
            END;
            cCheckCnt := 0;
        END ClearArrays;

    PROCEDURE DefineShow( sPar : ARRAY OF CHAR);
        VAR
            cPos : CARDINAL;
            sParam: tString;
        BEGIN
            bShowTotals := FALSE;
            bShowCounter:= FALSE;
            bShowLineNum:= FALSE;
            bShow       := TRUE;

            Slice( sPar, sParam);

            WHILE sParam[0] # NUL DO

                IF Equiv( sParam, "totals") THEN
                    bShowTotals := TRUE
                END;
                IF Equiv( sParam, "linecount") THEN
                    bShowCounter:= TRUE
                END;
                IF Equiv( sParam, "linenumbers") THEN
                    bShowLineNum:= TRUE
                END;

                IF Equiv( sParam, "all") THEN
                    bShowTotals := TRUE;
                    bShowCounter:= TRUE;
                    bShowLineNum:= TRUE
                END;


                Slice( sPar, sParam);
            END;


            IF (bShowTotals OR bShowCounter OR bShowLineNum) THEN
                bShow := TRUE
            END;

            DebugS("bShow=");
            DebugC(ORD(bShow));
            DebugS(" bShowTotals=");
            DebugC(ORD(bShowTotals));
            DebugS(" bShowCounter=");
            DebugC(ORD(bShowCounter));
            DebugS(" bShowLineNum=");
            DebugC(ORD(bShowLineNum));
            DebugL("");



        END DefineShow;


    PROCEDURE DefineFile( sPar : ARRAY OF CHAR);
        VAR
            cPos : CARDINAL;
        BEGIN
            IF bFileDefined THEN
                Append(sFILE," already defined. GO probably absent.");
                Error(sFILE)
            END;
            Assign(sPar, sFILE);
            cPos := Pos("$1",sFILE);
            IF cPos <= HIGH( sFILE) THEN
               IF bParamFile THEN
                    Delete(sFILE,cPos,2);
                    Insert(sParamFile,sFILE,cPos);
                ELSE
                    Delete(sFILE,cPos,2)
                END
            END;

            bFileDefined := TRUE;
            bDirty := FALSE

        END DefineFile;

    PROCEDURE InsertSubstArray( sS1, sS2 : ARRAY OF CHAR;  bB1, bB2,bB3 : BOOLEAN);
        VAR nTemp : CARDINAL;
            lFlag : BOOLEAN;

        BEGIN

            IF cSubstCnt = 0 THEN
                Assign(sS1,aSubst^[1].loc);
                Assign(sS2,aSubst^[1].ins);
                aSubst^[1].cnf := bB1;
                aSubst^[1].cas := bB2;
                aSubst^[1].who := bB3;
                cSubstCnt := 1
            ELSE
                lFlag := FALSE;
                IF NOT bDuplicates THEN
                    FOR nTemp := 1 TO cSubstCnt DO
                        IF Exact(aSubst^[nTemp].loc, sS1) THEN
                            Assign(sS2,aSubst^[nTemp].ins);
                            aSubst^[nTemp].cnf := bB1;
                            aSubst^[nTemp].cas := bB2;
                            aSubst^[nTemp].who := bB3;
                            lFlag := TRUE
                        END
                    END;
                END;
                IF NOT lFlag THEN
                    INC(cSubstCnt);
                    Assign(sS1,aSubst^[cSubstCnt].loc);
                    Assign(sS2,aSubst^[cSubstCnt].ins);
                    aSubst^[cSubstCnt].cnf := bB1;
                    aSubst^[cSubstCnt].cas := bB2;
                    aSubst^[cSubstCnt].who := bB3;
                END
            END
        END InsertSubstArray;

    PROCEDURE InsertCheckArray( sFIND : ARRAY OF CHAR;  bCASE, bWHOLE : BOOLEAN);
        VAR nTemp : CARDINAL;
            lFlag : BOOLEAN;

        BEGIN

            IF cCheckCnt = 0 THEN
                Assign(sFIND,aCheck^[1].cloc);
                aCheck^[1].ccas := bCASE;
                aCheck^[1].cwho := bWHOLE;
                cCheckCnt := 1
            ELSE
                lFlag := FALSE;
                IF NOT bDuplicates THEN
                    FOR nTemp := 1 TO cCheckCnt DO
                        IF Exact(aCheck^[nTemp].cloc, sFIND) THEN
                            aCheck^[nTemp].ccas := bCASE;
                            aCheck^[nTemp].cwho := bWHOLE;
                            lFlag := TRUE
                        END
                    END;
                END;
                IF NOT lFlag THEN
                    INC(cCheckCnt);
                    Assign(sFIND,aCheck^[cCheckCnt].cloc);
                    aCheck^[cCheckCnt].ccas := bCASE;
                    aCheck^[cCheckCnt].cwho := bWHOLE;
                END
            END
        END InsertCheckArray;

    PROCEDURE DefineSubst( sRec : ARRAY OF CHAR);
        VAR
            sInsert,
            sDelete,
            sSliver   : tString;
            bWhole,
            bCase,
            bConfirm  : BOOLEAN;

        BEGIN
            Slice(sRec, sDelete);
            Slice(sRec, sSliver);
            IF NOT Equiv(sSliver,"with") THEN
                Error("Keyword WITH not found");
            ELSE
                bSubstDefined := TRUE;
                Slice(sRec, sInsert);
                Slice(sRec, sSliver);
                bConfirm := TRUE;
                bCase := TRUE;
                bWhole := FALSE;

                WHILE sSliver[0] # NUL DO
                    IF Equiv(sSliver,"noconfirm") THEN
                        bConfirm := FALSE
                    END;
                    IF Equiv(sSliver,"nocase") THEN
                        bCase := FALSE
                    END;
                    IF Equiv(sSliver,"whole") THEN
                        bWhole := TRUE
                    END;
                    Slice(sRec, sSliver);
                END;

                InsertSubstArray( sDelete, sInsert, bConfirm, bCase, bWhole);
            END;
        END DefineSubst;

    PROCEDURE DefineCheck( sRec : ARRAY OF CHAR);
        VAR
            sFind,
            sSliver   : tString;
            bWhole,
            bCase     : BOOLEAN;

        BEGIN
            Slice(sRec, sFind);
            Slice(sRec, sSliver);
            bCheckDefined := TRUE;
            bCase := TRUE;
            bWhole := FALSE;
            WHILE sSliver[0] # NUL DO

                IF Equiv(sSliver,"nocase") THEN
                    bCase := FALSE
                END;
                IF Equiv(sSliver,"whole") THEN
                    bWhole := TRUE
                END;
                Slice(sRec, sSliver);
            END;

            InsertCheckArray( sFind, bCase, bWhole);
        END DefineCheck;

    PROCEDURE Process;
        VAR
            oBuff,
            iBuff   : INTEGER;
            sYesNoQuit,
            sLoc,
            sIns,
            sWorkArea,
            sRecord : tString;
            cRightMargin,
            cResp,
            cPos,
            cCnt,
            cIdx    : CARDINAL;
            bFound,
            bNext,
            bWho,
            bCnf,
            bCas    : BOOLEAN;

        PROCEDURE Swap;
            BEGIN
                bDirty := TRUE;
                Delete(sRecord, cPos, Length( sLoc));
                Insert(sIns, sRecord, cPos);
                Assign( sRecord, sWorkArea);

                WriteOut("NEW> ");
                LineOut(sRecord);

                IF NOT bCas THEN
                    UpperCase( sWorkArea)
                END;
            END Swap;

        BEGIN
            IF NOT bFileDefined THEN
                Error("FILE not defined.")
            END;
            IF NOT (bSubstDefined OR bCheckDefined) THEN
                Error("No SUBSTs or CHECKs defined.")
            END;


            Files.Open(iBuff, sFILE, Files.READ);
            IF iBuff = -1 THEN
                Append(sFILE, " not found.");
                Error(sFILE)
            END;

            WriteOut("TSL is working on ");
            LineOut( sFILE);

            DropExt( sFILE, sTMP);
            Append ( sTMP, ".$$$");
            Files.Create(oBuff, sTMP, Files.WRITE);

            DropExt( sFILE, sBAK);
            Append( sBAK, ".BAK");

            cLineCnt := 0;

            BlockReadCreate(32767);
            BlockReadLine(iBuff, sRecord, cCnt);
            bDropOut := FALSE;
            bAbort := FALSE;

            cCheckCheck := 0;
            cSubstSubst := 0;

            WHILE cCnt # 0 DO

                INC(cLineCnt);

                IF (bShow AND bShowCounter) THEN
                    CardOut( cLineCnt,1);
                    WriteOut(CR);
                END;

                RightTrim( sRecord);
                Assign(sRecord, sWorkArea);
                IF bCheckDefined THEN
                    cIdx := 1;
                    LOOP
                        Assign( aCheck^[cIdx].cloc, sLoc);
                        bCas := aCheck^[cIdx].ccas;
                        bWho := aCheck^[cIdx].cwho;
                        IF NOT bCas THEN

                            UpperCase( sLoc);
                            UpperCase( sWorkArea);
                        END;

                        cPos := 0;
                        bFound := InLine( cPos, sWorkArea, sLoc, sWordBreak, bWho);

                        IF bFound THEN
                            INC(cCheckCheck);
                            WriteOut("FOUND>");

                            IF (bShow AND bShowLineNum) THEN
                                WriteOut("[");
                                CardOut(cLineCnt,5);
                                WriteOut("]")
                            END;

                            VideoOut(sRecord, cPos, Length( sLoc));
                            sYesNoQuit := "Action (C/Q/A/H)? ";
                            cResp := GetResponse(sYesNoQuit, "CQAH");
                            CASE cResp OF
                                0 : ;
                                |
                                1 : bDropOut := TRUE;
                                    EXIT
                                |
                                2 : bDropOut := TRUE;
                                    bAbort := TRUE;
                                    EXIT
                                |
                                3 : LineOut("C=continue. Q=quit file. A=abort program. H=this text.");
                            END;
                        END;
                        INC( cIdx);
                        IF cIdx > cCheckCnt THEN
                            EXIT
                        END
                    END;
                END;
                bNext := FALSE;
                IF NOT (bDropOut OR bAbort) THEN
                    FOR cIdx := 1 TO cSubstCnt DO
                        Assign( aSubst^[cIdx].loc, sLoc);
                        Assign( aSubst^[cIdx].ins, sIns);
                        bCnf := aSubst^[cIdx].cnf;
                        bCas := aSubst^[cIdx].cas;
                        bWho := aSubst^[cIdx].who;

                        IF NOT bCas THEN

                            UpperCase( sLoc);
                            UpperCase( sWorkArea);
                        END;
                        bDropOut := FALSE;
                        cPos := 0;
                        LOOP

                            DebugS("sLoc=");
                            DebugL(sLoc);
                            DebugS("sWorkArea=");
                            DebugL(sWorkArea);
                            DebugS("sWordBreak=");
                            DebugL(sWordBreak);
                            DebugS("bWho=");
                            DebugC(ORD(bWho));
                            DebugL("");
                            DebugS("bCas=");
                            DebugC(ORD(bCas));
                            DebugL("");


                            bNext := FALSE;
                            cResp := 0;
                            bFound := InLine( cPos, sWorkArea, sLoc, sWordBreak, bWho);

                            DebugS("bFound=");
                            DebugC(ORD(bFound));
                            DebugL("");

                            IF bFound THEN
                                IF bCnf THEN
                                    IF (bShow AND bShowLineNum) THEN
                                        WriteOut("[");
                                        CardOut(cLineCnt,5);
                                        WriteOut("]")
                                    ELSE
                                        WriteOut("OLD> ");
                                    END;

                                    VideoOut( sRecord, cPos, Length(sLoc));
                                    sYesNoQuit := 'Replace ';
                                    Append( sYesNoQuit, sLoc);
                                    Append( sYesNoQuit, ' with ');
                                    Append( sYesNoQuit, sIns);
                                    Append( sYesNoQuit, ' (Y/N/Q/A/H)? ');
                                    bDropOut := FALSE;
                                    cResp := GetResponse(sYesNoQuit,"YNQAH");
                                    CASE cResp OF
                                        0 : INC(cSubstSubst);
                                            Swap;
                                        |
                                        1 : ;
                                        |
                                        2 : bDropOut := TRUE;
                                            EXIT
                                        |
                                        3 : bAbort := TRUE;
                                            bDropOut := TRUE;
                                            EXIT
                                        |
                                        4 : LineOut("Y=change. N=don't change. Q=quit file. A=abort program. H=this text.");
                                    END;
                                ELSE
                                    INC( cSubstSubst);
                                    Swap

                                END;
                            ELSE
                                EXIT
                            END;
                            IF bFound THEN
                                IF cResp # 4 THEN
                                    cPos := cPos + Max(Length(sLoc),Length(sIns))
                                END
                            END;
                        END;
                        IF bDropOut THEN
                            cIdx := cSubstCnt+1
                        END
                    END;
                END;
                IF bDropOut THEN
                    cCnt := 0
                ELSE


                    Append( sRecord, CHR(13));
                    Append( sRecord, CHR(10));
                    Files.Write(oBuff, ADR( sRecord), Length( sRecord), cCnt);
                    BlockReadLine(iBuff, sRecord, cCnt);

                END;
            END;
            BlockReadDestroy;
            Files.Close(iBuff);
            Files.Close(oBuff);

            IF bDropOut THEN
                cCnt := 0;
                Files.Delete( sTMP)
            ELSE
                IF bDirty THEN
                    Files.Delete( sBAK);
                    Files.Rename(sFILE,sBAK);
                    Files.Rename(sTMP,sFILE)
                ELSE
                    Files.Delete( sTMP)
                END
            END;
            IF (bShow AND bShowTotals) THEN
                CardOut(cLineCnt,5);
                LineOut(" lines processed. ");
                CardOut(cCheckCnt,5);
                LineOut(" checks defined. ");
                CardOut(cSubstCnt,5);
                LineOut(" substs defined. ");
                CardOut(cCheckCheck,5);
                LineOut(" checks found. ");
                CardOut(cSubstSubst,5);
                LineOut(" substs confirmed.")
            END

        END Process;

BEGIN
    WriteOut("TSL (Text Substitution Language) v");
    WriteOut(sVERSION);
    LineOut(" (c) Copyright Bruce M. Axtens, 1993.");

    bShowTotals := FALSE;
    bShowCounter:= FALSE;
    bShowLineNum:= FALSE;
    bShow       := FALSE;
    bDuplicates := FALSE;

    cCheckCheck := 0;
    cSubstSubst := 0;
    cLineCnt    := 0;

    bAbort := FALSE;
    sWordBreak := " ";     (* SPACE *)
    Append(sWordBreak,HT); (* TAB *)
    GetEnv("TSL$DBG",sParam);
    bDebug := Equiv(sParam,"ON");
    SetDebug(bDebug);
    GetArg( sFileName, cCnt);
    IF cCnt = 0 THEN
        Syntax;
        Terminate(0)
    END;

    GetArg( sParam, cCnt);
    IF cCnt # 0 THEN
        sParamFile := sParam;
        bParamFile := TRUE
    ELSE
        bParamFile := FALSE
    END;

    IF NOT HasExt( sFileName) THEN
        Append( sFileName, ".TSL")
    END;

    Files.Open(iBuff,sFileName,Files.READ);
    IF iBuff = -1 THEN
        WriteOut("Could not open ");
        LineOut( sFileName);
        Terminate(1)
    END;

    NEW(aSubst);
    NEW(aCheck);

    bFileDefined := FALSE;
    bSubstDefined := FALSE;
    bCheckDefined := FALSE;
    cScriptCnt := 0;
    ClearArrays;
    ReadFileLine( iBuff, sRecord, cCnt);
    WHILE cCnt # 0 DO
        INC( cScriptCnt);

        RightTrim(sRecord);


        Slice( sRecord, sSlice);
        Assign( sSlice, sKeyword);


        UpperCase( sKeyword);
        CASE KeywordArray( sKeyword) OF

            0 : IF sKeyword[0] # NUL THEN
                    WriteOut("Line ");
                    CardOut(cScriptCnt,1);
                    WriteOut(": ");
                    WriteOut("Command [");
                    WriteOut( sKeyword);
                    LineOut("] not known ")
                END
            |
            1 : Slice( sRecord, sSlice);
                DefineFile( sSlice)
            |
            2 : DefineSubst( sRecord);

            |
            3 : bAbort := FALSE;
                Process;
                IF bAbort THEN
                    LineOut("Entire processing aborted.");
                    StopRun
                END;
                IF bDropOut THEN
                    LineOut("Quitting current file.")
                ELSE
                    LineOut("Processing complete.")
                END;
                bFileDefined := FALSE;
                bSubstDefined := FALSE;
                bCheckDefined := FALSE;
                ClearArrays;
            |
            4 : LineOut( sRecord)
            |
            5 : WriteOut("End of Script ");
                WriteOut(sFileName);
                LineOut(".");
                StopRun;
            |
            6 : DefineCheck( sRecord)
            |
            7 : Append( sWordBreak, sRecord);
            |
            8 : bDuplicates := Equiv(sRecord,"on")
            |
            9 : ; (* ignore a NOTE line *)
            |
            10: DefineShow( sRecord);

        END;
        ReadFileLine( iBuff, sRecord, cCnt)
    END;

    IF bFileDefined OR bSubstDefined THEN
        Error("GO not processed.")
    END;
    StopRun


END TextSubstitutionLanguage.

