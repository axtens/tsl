MODULE TextSubstitutionLanguage;

FROM ASCII IMPORT NUL, CR, LF;
FROM Strings IMPORT Copy, Assign, Append, Length, Pos, Insert, Delete, CompareStr;
FROM SLICE IMPORT Slice;
FROM XDOS IMPORT BlockReadCreate, BlockReadLine, BlockReadDestroy, ReadFileLine;
IMPORT Files;
FROM XString IMPORT IndexInList, Exact, UpperCase,
        RightTrim, Equiv, GetResponse, LeftTrim;
FROM System IMPORT GetArg, Terminate, GetEnv;
FROM DevIO IMPORT CardOut, WriteOut, LineOut;
FROM FileSpec IMPORT HasExt, DropExt;
FROM SYSTEM IMPORT ADR;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM INSTRING IMPORT InStr;
IMPORT Display;

    CONST
        cMaxSubst = 200;
        cMaxCheck = 200;
        xDOT      = ".";

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

        cCheckCnt,
        cSubstCnt,
        cCnt        : CARDINAL;

        iBuff       : INTEGER;

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

    PROCEDURE DebugS( s : ARRAY OF CHAR);
        BEGIN
            IF bDebug THEN
                WriteOut( s)
            END
        END DebugS;

    PROCEDURE DebugL( s : ARRAY OF CHAR);
        BEGIN
            IF bDebug THEN
                LineOut( s)
            END
        END DebugL;

    PROCEDURE DebugC( c1, c2 : CARDINAL);
        BEGIN
            IF bDebug THEN
                CardOut( c1, c2)
            END
        END DebugC;

    PROCEDURE InLine( cFrom : CARDINAL; sTarget, sFind : ARRAY OF CHAR; bWholeWord : BOOLEAN) : CARDINAL;
        VAR
            cLeft,
            cRight,
            cPos,
            cSav : CARDINAL;
            sTemp : ARRAY [0..255] OF CHAR;
            bLeftIsSpace,
            bRightIsSpace : BOOLEAN;
        BEGIN
            cSav := HIGH( sTarget);
            Copy(sTarget, cFrom, 256, sTemp);
            cPos := Pos( sFind, sTemp);
            IF cPos > HIGH( sTemp) THEN
                cPos := cSav + 10
            ELSE
                cPos := cPos + cFrom
            END;
            IF bWholeWord AND (cPos # (cSav + 10)) THEN

                DebugS("sTarget=");
                DebugL(sTarget);
                DebugS("sFind=");
                DebugL(sFind);
                DebugS("InLine =>");


                bRightIsSpace := FALSE;
                bLeftIsSpace := FALSE;

                cRight := cPos + Length( sFind);
                cLeft := cPos - 1;

                DebugC( cLeft, 5);
                DebugC( cRight,5);


                IF cPos > 0 THEN
                    DebugC( ORD( sTarget[cLeft]),5);
                ELSE
                    DebugC( ORD( sTarget[cPos]),5);
                END;
                DebugC( ORD( sTarget[cRight]),5);
                DebugL("");

                IF sTarget[cRight] = NUL THEN
                    bRightIsSpace := TRUE
                ELSE
                    IF IsIn( sTarget[cRight], sWordBreak) THEN
                        bRightIsSpace := TRUE
                    END;
                END;

                IF cPos = 0 THEN
                    bLeftIsSpace := TRUE
                ELSE
                    IF IsIn( sTarget[cLeft], sWordBreak) THEN
                        bLeftIsSpace := TRUE
                    END;
                END;
                IF (bLeftIsSpace AND bRightIsSpace) THEN
                    cPos := cPos
                ELSE
                    cPos := cSav + 10
                END;

            END;

            RETURN cPos
        END InLine;



    PROCEDURE Syntax;
        BEGIN
            LineOut('Syntax:');
            LineOut('        TSL <filename[.TSL]> [filename ...]');

        END Syntax;

    PROCEDURE Error( sMsg : ARRAY OF CHAR);
        BEGIN
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

    PROCEDURE IsIn( sFind, sIn : ARRAY OF CHAR) : BOOLEAN;
        VAR
            c : CARDINAL;
        BEGIN
            c := Pos( sFind , sIn);

            DebugS("IsIn => ");
            DebugS(sFind);
            DebugS("==>");
            DebugS(sIn);
            DebugS(" @ ");
            DebugC( c,5);
            DebugL("");

            RETURN (NOT (c > HIGH( sIn)))
        END IsIn;

    PROCEDURE KeywordArray( sKey : ARRAY OF CHAR) : CARDINAL;
        VAR
            aKeys : ARRAY [1..20] OF tString;
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
            FOR cIdx := 1 TO 8 DO
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

                    DebugS("cPos=");
                    DebugC(cPos,5);
                    DebugL("");

                    Delete(sFILE,cPos,2);

                    DebugS("sFILE=");
                    DebugL(sFILE);

                    Insert(sParamFile,sFILE,cPos);


                    DebugS("sFILE=");
                    DebugL(sFILE)

                ELSE
                    Delete(sFILE,cPos,2)
                END
            END;

            DebugS("sFILE=");
            DebugL(sFILE);

            bFileDefined := TRUE;
            bDirty := FALSE

        END DefineFile;

    PROCEDURE InsertSubstArray( sS1, sS2 : ARRAY OF CHAR;  bB1, bB2,bB3 : BOOLEAN);
        VAR nTemp : CARDINAL;
            lFlag : BOOLEAN;

        BEGIN

            DebugS("Inserting ");
            DebugS(sS1);
            DebugS(" ");
            DebugS(sS2);
            IF bB1 THEN
                DebugS(" CONFIRM")
            ELSE
                DebugS(" NOCONFIRM")
            END;
            IF bB2 THEN
                DebugS(" CASE")
            ELSE
                DebugS(" NOCASE")
            END;
            IF bB3 THEN
                DebugS(" WHOLE")
            ELSE
                DebugS(" NOWHOLE")
            END;
            DebugL("");

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

            DebugS("Checking ");
            DebugS(sFIND);
            IF bCASE THEN
                DebugS(" CASE")
            ELSE
                DebugS(" NOCASE")
            END;
            IF bWHOLE THEN
                DebugS(" WHOLE")
            ELSE
                DebugS(" NOWHOLE")
            END;
            DebugL("");

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
                IF Equiv(sSliver,"noconfirm") THEN
                    bConfirm := FALSE
                END;
                IF Equiv(sSliver,"nocase") THEN
                    bCase := FALSE
                END;
                IF Equiv(sSliver,"whole") THEN
                    bWhole := TRUE
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

            IF Equiv(sSliver,"nocase") THEN
                bCase := FALSE
            END;
            IF Equiv(sSliver,"whole") THEN
                bWhole := TRUE
            END;
            Slice(sRec, sSliver);
            IF Equiv(sSliver,"nocase") THEN
                bCase := FALSE
            END;
            IF Equiv(sSliver,"whole") THEN
                bWhole := TRUE
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

                    DebugL("Swap: not case sensitive.");

                    UpperCase( sWorkArea)
                END;
            END Swap;

        BEGIN
            IF NOT bFileDefined THEN
                Error("FILE not defined.")
            END;
            IF NOT bSubstDefined THEN
                Error("No SUBSTs defined.")
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

            BlockReadCreate(32767);
            BlockReadLine(iBuff, sRecord, cCnt);
            bDropOut := FALSE;
            bAbort := FALSE;
            WHILE cCnt # 0 DO
                RightTrim( sRecord);
                Assign(sRecord, sWorkArea);
                IF bCheckDefined THEN
                    cIdx := 1;
                    LOOP
                        Assign( aCheck^[cIdx].cloc, sLoc);
                        bCas := aCheck^[cIdx].ccas;
                        bWho := aCheck^[cIdx].cwho;
                        IF NOT bCas THEN

                            DebugL("Process: Check not case sensitive.");

                            UpperCase( sLoc);
                            UpperCase( sWorkArea);
                        END;
                        cPos := 0;
                        cPos := InLine( cPos, sWorkArea, sLoc, bWho);
                        IF cPos <= HIGH( sWorkArea) THEN
                            WriteOut("FOUND>");
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

                        DebugS("sLoc=");
                        DebugL(sLoc);
                        DebugS("sIns=");
                        DebugL(sIns);
                        IF bCnf THEN DebugL("CONFIRM") ELSE DebugL("NOCONFIRM") END;
                        IF bCas THEN DebugL("CASE") ELSE DebugL("NOCASE") END;
                        IF bWho THEN DebugL("WHOLE") ELSE DebugL("NOWHOLE") END;

                        IF NOT bCas THEN

                            DebugL("Process: Subst not case sensitive.");

                            UpperCase( sLoc);
                            UpperCase( sWorkArea);
                        END;
                        bDropOut := FALSE;
                        cPos := 0;
                        LOOP

                            DebugS("cPos in LOOP =");
                            DebugC( cPos, 1);
                            DebugL("");

                            bNext := FALSE;
                            cResp := 0;
                            cPos := InLine( cPos, sWorkArea, sLoc, bWho);

                            DebugS("cPos after InLine =");
                            DebugC( cPos, 1);
                            DebugL("");

                            IF cPos <= HIGH( sWorkArea) THEN
                                IF bCnf THEN
                                    WriteOut("OLD> ");
                                    VideoOut( sRecord, cPos, Length(sLoc));
                                    sYesNoQuit := 'Replace ';
                                    Append( sYesNoQuit, sLoc);
                                    Append( sYesNoQuit, ' with ');
                                    Append( sYesNoQuit, sIns);
                                    Append( sYesNoQuit, ' (Y/N/Q/A/H)? ');
                                    bDropOut := FALSE;
                                    cResp := GetResponse(sYesNoQuit,"YNQAH");
                                    CASE cResp OF
                                        0 : Swap;
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
                                    Swap

                                END;
                            ELSE
                                DebugL("Not Found.");
                                EXIT
                            END;
                            IF cResp # 4 THEN
                                cPos := cPos + Length(sLoc)
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

                    DebugS("After swapping=");
                    DebugL( sRecord);

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
            END

        END Process;

BEGIN
    bDuplicates := FALSE;
    bAbort := FALSE;
    sWordBreak := " ";
    LineOut("TSL (Text Substitution Language) v1.A (c) Copyright Bruce M. Axtens, 1993.");
    GetEnv("TSL$DBG",sParam);
    bDebug := Equiv(sParam,"ON");

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
    ClearArrays;

    ReadFileLine( iBuff, sRecord, cCnt);
    WHILE cCnt # 0 DO
        RightTrim(sRecord);

        DebugS("INPUT! sRecord=");
        DebugL(sRecord);

        Slice( sRecord, sSlice);
        Assign( sSlice, sKeyword);

        DebugS("sKeyword=");
        DebugL(sKeyword);

        UpperCase( sKeyword);
        CASE KeywordArray( sKeyword) OF

            0 : IF sKeyword[0] # NUL THEN
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
                    StopRun
                END;
                bFileDefined := FALSE;
                bSubstDefined := FALSE;
                bCheckDefined := FALSE;
                ClearArrays;
            |
            4 : LineOut( sRecord)
            |
            5 : LineOut("Processing complete.");
                StopRun;
            |
            6 : DefineCheck( sRecord)
            |
            7 : Append( sWordBreak, sRecord);
                DebugS("sWordBreak now =");
                DebugL( sWordBreak)
            |
            8 : bDuplicates := Equiv(sRecord,"on")

        END;
        ReadFileLine( iBuff, sRecord, cCnt)
    END;

    IF bFileDefined OR bSubstDefined THEN
        Error("GO not processed.")
    END;
    LineOut("Processing complete.");
    StopRun;


END TextSubstitutionLanguage.

