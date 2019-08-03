MODULE TextSubstitutionLanguage;

FROM ASCII IMPORT NUL;
FROM Strings IMPORT Assign, Append, Length, Pos, Insert, Delete, CompareStr;
FROM SLICE IMPORT Slice;
FROM XDOS IMPORT BlockReadCreate, BlockReadLine, BlockReadDestroy, ReadFileLine;
IMPORT Files;
FROM XString IMPORT IndexInList, Exact, UpperCase, RightTrim, Equiv, GetResponse;
FROM System IMPORT GetArg, Terminate, GetEnv;
FROM DevIO IMPORT CardOut, WriteOut, LineOut;
FROM FileSpec IMPORT HasExt, DropExt;
FROM SYSTEM IMPORT ADR;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM INSTRING IMPORT InStr;

    CONST
        cMaxSubst = 100;
        xDOT      = ".";

    TYPE

        tString = ARRAY [0..255] OF CHAR;
        tSubst  = RECORD
                    loc, ins : tString;
                    cnf, cas : BOOLEAN;
                  END;
        taSubst = ARRAY [0..cMaxSubst] OF tSubst;
        ptaSubst= POINTER TO taSubst;

    VAR
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

        cSubstCnt,
        cCnt        : CARDINAL;

        iBuff       : INTEGER;

        bAbort,
        bParamFile,
        bDropOut,
        bDirty,
        bFileDefined,
        bSubstDefined,
        bDebug,
        bCase,
        bConfirm    : BOOLEAN;

        paSubst      : ptaSubst;






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
            Files.Close(iBuff);
            Terminate(0)
        END StopRun;


    PROCEDURE ClearArray;
        VAR
            cCnt : CARDINAL;

        BEGIN
            FOR cCnt := 1 TO cMaxSubst DO
                aSubst[cCnt].loc := '';
                aSubst^[cCnt].ins := '';
                aSubst[cCnt].cnf := TRUE;
                aSubst[cCnt].cas := TRUE;
            END;
            cSubstCnt := 0;
        END ClearArray;

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
                    IF bDebug THEN
                        WriteOut("cPos=");
                        CardOut( cPos,5);
                        LineOut("")
                    END;
                    Delete(sFILE,cPos,2);
                    IF bDebug THEN
                        WriteOut("sFILE=");
                        LineOut(sFILE)
                    END;
                    Insert(sParamFile,sFILE,cPos);
                    IF bDebug THEN
                        WriteOut("sFILE=");
                        LineOut(sFILE)
                    END;
                ELSE
                    Delete(sFILE,cPos,2)
                END
            END;

            IF bDebug THEN
                WriteOut("sFILE=");
                LineOut(sFILE);
            END;
            bFileDefined := TRUE;
            bDirty := FALSE
        END DefineFile;

    PROCEDURE InsertArray( sS1, sS2 : ARRAY OF CHAR;  bB1, bB2 : BOOLEAN);
        VAR nTemp : CARDINAL;
            lFlag : BOOLEAN;

        BEGIN
            IF bDebug THEN
                WriteOut("Inserting ");
                WriteOut(sS1);
                WriteOut(" ");
                WriteOut(sS2);
                WriteOut(" ");
                IF bB1 THEN
                    WriteOut("CONFIRM ")
                ELSE
                    WriteOut("NOCONFIRM ")
                END;
                IF bB2 THEN
                    WriteOut("CASE")
                ELSE
                    WriteOut("NOCASE")
                END;
                LineOut("");
            END;

            IF cSubstCnt = 0 THEN

                Assign(sS1,aSubst[1].loc);
                Assign(sS2,aSubst[1].ins);
                aSubst[1].cnf := bB1;
                aSubst[1].cas := bB2;
                cSubstCnt := 1
            ELSE
                lFlag := FALSE;
                FOR nTemp := 1 TO cSubstCnt DO
                    IF Exact(aSubst[nTemp].loc, sS1) THEN
                        Assign(sS2,aSubst[nTemp].ins);
                        aSubst[nTemp].cnf := bB1;
                        aSubst[nTemp].cas := bB2;
                        lFlag := TRUE
                    END
                END;
                IF NOT lFlag THEN
                    INC(cSubstCnt);
                    Assign(sS1,aSubst[cSubstCnt].loc);
                    Assign(sS2,aSubst[cSubstCnt].ins);
                    aSubst[cSubstCnt].cnf := bB1;
                    aSubst[cSubstCnt].cas := bB2;
                END
            END
        END InsertArray;




    PROCEDURE Process;
        VAR
            oBuff,
            iBuff   : INTEGER;
            sYesNoQuit,
            sLoc,
            sIns,
            sWorkArea,
            sRecord : tString;
            cResp,
            cPos,
            cCnt,
            cIdx    : CARDINAL;
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
                    IF bDebug THEN
                        LineOut("Swap: not case sensitive.")
                    END;
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
            WHILE cCnt # 0 DO
                RightTrim( sRecord);
                Assign(sRecord, sWorkArea);
                FOR cIdx := 1 TO cSubstCnt DO
                    Assign( aSubst[cIdx].loc, sLoc);
                    Assign( aSubst[cIdx].ins, sIns);
                    bCnf := aSubst[cIdx].cnf;
                    bCas := aSubst[cIdx].cas;
                    IF NOT bCas THEN
                        IF bDebug THEN
                            LineOut("Process: not case sensitive.")
                        END;
                        UpperCase( sLoc);
                        UpperCase( sWorkArea);
                    END;
                    bDropOut := FALSE;
                    cPos := 0;
                    LOOP
                        cPos := InStr( cPos, sWorkArea, sLoc);
                        IF cPos > HIGH( sWorkArea) THEN
                            EXIT
                        END;
                        IF bCnf THEN
                            WriteOut("OLD> ");
                            LineOut( sRecord);
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
                        IF cResp # 4 THEN
                            cPos := cPos + Length(sLoc)
                        END;
                    END;
                    IF bDropOut THEN
                        cIdx := cSubstCnt+1
                    END
                END;
                IF bDropOut THEN
                    cCnt := 0
                ELSE
                    IF bDebug THEN
                        LineOut( sRecord)
                    END;
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
    bAbort := FALSE;
    LineOut("TSL (Text Substitution Language) v1.4disk (c) Copyright Bruce M. Axtens, 1993.");
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

    bFileDefined := FALSE;
    bSubstDefined := FALSE;
    ClearArray;

    ReadFileLine( iBuff, sRecord, cCnt);
    WHILE cCnt # 0 DO
        RightTrim(sRecord);
        IF sRecord[0] = NUL THEN
            sRecord[0] := xDOT
        END;
        IF bDebug THEN
            WriteOut("sRecord=");
            LineOut(sRecord);
        END;
        Slice( sRecord, sSlice);
        Assign( sSlice, sKeyword);
        IF bDebug THEN
            WriteOut("sKeyword=");
            LineOut(sKeyword);
        END;
        UpperCase( sKeyword);
        Insert(".", sKeyword, 0);
        IF bDebug THEN
            WriteOut("sKeyword=");
            LineOut(sKeyword);
        END;
        CASE IndexInList( sKeyword, ".FILE    .SUBST   .GO      .MESSAGE .END     ",8) OF
            0 : IF sKeyword[1] # xDOT THEN
                    WriteOut("Command [");
                    WriteOut( sSlice);
                    LineOut("] not known ")
                END
            |
            1 : Slice( sRecord, sSlice);
                DefineFile( sSlice)
            |
            2 : Slice(sRecord, sString1);
                Slice(sRecord, sSlice);
                IF NOT Equiv(sSlice,"with") THEN
                    Error("Keyword WITH not found");
                ELSE
                    bSubstDefined := TRUE;
                    Slice(sRecord, sString2);
                    Slice(sRecord, sSlice);
                    bConfirm := TRUE;
                    bCase := TRUE;

                    IF Equiv(sSlice,"noconfirm") THEN
                        bConfirm := FALSE
                    END;
                    IF Equiv(sSlice,"nocase") THEN
                        bCase := FALSE
                    END;
                    Slice(sRecord, sSlice);
                    IF Equiv(sSlice,"noconfirm") THEN
                        bConfirm := FALSE
                    END;
                    IF Equiv(sSlice,"nocase") THEN
                        bCase := FALSE
                    END;
                    InsertArray( sString1, sString2, bConfirm, bCase);
                END;
            |
            3 : bAbort := FALSE;
                Process;
                IF bAbort THEN
                    StopRun
                END;
                bFileDefined := FALSE;
                bSubstDefined := FALSE;
                ClearArray;
            |
            4 : LineOut( sRecord)
            |
            5 : LineOut("Processing complete.");
                StopRun;


        END;
        ReadFileLine( iBuff, sRecord, cCnt)
    END;

    IF bFileDefined OR bSubstDefined THEN
        Error("GO not processed.")
    END;
    LineOut("Processing complete.");
    StopRun;


END TextSubstitutionLanguage.

