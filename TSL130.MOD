MODULE TextSubstitutionLanguage;

FROM Strings IMPORT Assign, Append, Length, Pos, Insert, Delete, CompareStr;
FROM SLICE IMPORT Slice;
FROM XDOS IMPORT BlockReadCreate, BlockReadLine, BlockReadDestroy, ReadFileLine;
IMPORT Files;
FROM XString IMPORT IndexInList, Exact, UpperCase, RightTrim, Equiv, GetResponse;
FROM System IMPORT GetArg, Terminate, GetEnv;
FROM DevIO IMPORT CardErr, WriteErr, LineErr, LineOut;
FROM FileSpec IMPORT HasExt, DropExt;
FROM SYSTEM IMPORT ADR;
FROM Storage IMPORT ALLOCATE, DEALLOCATE;
FROM INSTRING IMPORT InStr;

CONST
    cMaxSubst = 50;

TYPE

    tString = ARRAY [0..50] OF CHAR;
    tShort  = ARRAY [0..80] OF CHAR;
    tSubst  = RECORD
                loc, ins : tString;
                cnf, cas : BOOLEAN;
              END;
    tProgArray = ARRAY [0..1500] OF tString;
    ptProgArray= POINTER TO tProgArray;


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
    cLines,
    cCnt        : CARDINAL;

    iBuff       : INTEGER;

    bParamFile,
    bDropOut,
    bDirty,
    bFileDefined,
    bSubstDefined,
    bDebug,
    bCase,
    bConfirm    : BOOLEAN;

    aSubst      : ARRAY [1..cMaxSubst] OF tSubst;
    pasProgram   : ptProgArray;






PROCEDURE Syntax;
BEGIN
    LineErr('Syntax:');
    LineErr('        TSL <filename[.TSL]>');

END Syntax;

PROCEDURE Error( sMsg : ARRAY OF CHAR);
BEGIN
    LineErr( sMsg);
    Terminate(2)
END Error;


PROCEDURE ClearArray;
VAR
    cCnt : CARDINAL;

BEGIN
    FOR cCnt := 1 TO cMaxSubst DO
        aSubst[cCnt].loc := '';
        aSubst[cCnt].ins := '';
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
                WriteErr("cPos=");
                CardErr( cPos,5);
                LineErr("")
            END;
            Delete(sFILE,cPos,2);
            IF bDebug THEN
                WriteErr("sFILE=");
                LineErr(sFILE)
            END;
            Insert(sParamFile,sFILE,cPos);
            IF bDebug THEN
                WriteErr("sFILE=");
                LineErr(sFILE)
            END;
        ELSE
            Delete(sFILE,cPos,2)
        END
    END;

    IF bDebug THEN
        WriteErr("sFILE=");
        LineErr(sFILE);
    END;
    bFileDefined := TRUE;
    bDirty := FALSE
END DefineFile;

PROCEDURE InsertArray( sS1, sS2 : ARRAY OF CHAR;  bB1, bB2 : BOOLEAN);
VAR nTemp : CARDINAL;
    lFlag : BOOLEAN;

BEGIN
    IF bDebug THEN
        WriteErr("Inserting ");
        WriteErr(sS1);
        WriteErr(" ");
        WriteErr(sS2);
        WriteErr(" ");
        IF bB1 THEN
            WriteErr("CONFIRM ")
        ELSE
            WriteErr("NOCONFIRM ")
        END;
        IF bB2 THEN
            WriteErr("CASE")
        ELSE
            WriteErr("NOCASE")
        END;
        LineErr("");
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

    WriteErr("NEW> ");
    LineErr(sRecord);

    IF NOT bCas THEN
        IF bDebug THEN
            LineErr("Swap: not case sensitive.")
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

    WriteErr("TSL is working on ");
    LineErr( sFILE);

    DropExt( sFILE, sTMP);
    Append ( sTMP, ".$$$");
    Files.Create(oBuff, sTMP, Files.WRITE);

    DropExt( sFILE, sBAK);
    Append( sBAK, ".BAK");

    BlockReadCreate(32767);
    BlockReadLine(iBuff, sRecord, cCnt);
    (*ReadFileLine(iBuff, sRecord, cCnt);*)
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
                    LineErr("Process: not case sensitive.")
                END;
                UpperCase( sLoc);
                UpperCase( sWorkArea);
            END;
            bDropOut := FALSE;
            cPos := 0;
            LOOP
                cPos := InStr( cPos, sWorkArea, sLoc);
                (*cPos := Pos( sLoc, sWorkArea);*)
                IF cPos > HIGH( sWorkArea) THEN
                    EXIT
                END;
                IF bCnf THEN
                    WriteErr("OLD> ");
                    LineErr( sRecord);
                    sYesNoQuit := 'Replace ';
                    Append( sYesNoQuit, sLoc);
                    Append( sYesNoQuit, ' with ');
                    Append( sYesNoQuit, sIns);
                    Append( sYesNoQuit, ' (Y/N/Q)? ');
                    bDropOut := FALSE;
                    CASE GetResponse(sYesNoQuit,"YNQ") OF
                        0 : Swap;
                        |
                        1 : ; (*EXIT;*)
                        |
                        2 : bDropOut := TRUE;
                            EXIT

                    END;
                ELSE
                    Swap

                END;
                cPos := cPos + Length(sLoc)

            END;
            IF bDropOut THEN
                cIdx := cSubstCnt+1
            END
        END;
        IF bDropOut THEN
            cCnt := 0
        ELSE
            IF bDebug THEN
                LineErr( sRecord)
            END;
            Append( sRecord, CHR(13));
            Append( sRecord, CHR(10));
            Files.Write(oBuff, ADR( sRecord), Length( sRecord), cCnt);
            (*ReadFileLine(iBuff, sRecord, cCnt);*)
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
    LineErr("TSL (Text Substitution Language) v1.3 (c) Copyright Bruce M. Axtens, 1993.");
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
        WriteErr("Could not open ");
        LineErr( sFileName);
        Terminate(1)
    END;

    bFileDefined := FALSE;
    bSubstDefined := FALSE;
    ClearArray;

    NEW(pasProgram);

    cLines := 0;
    ReadFileLine( iBuff, sRecord, cCnt);
    WHILE cCnt # 0 DO
        RightTrim(sRecord);
        IF Length(sRecord) > 0 THEN
            Assign(sRecord, pasProgram^[cLines]);
            INC( cLines)
        END;
        ReadFileLine( iBuff, sRecord, cCnt);
    END;
    Files.Close(iBuff);
    DEC( cLines);
    FOR cCnt := 0 TO cLines DO
        Assign( pasProgram^[cCnt],sRecord);
        Slice( sRecord, sSlice);
        Assign( sSlice, sKeyword);
        UpperCase( sKeyword);
        Insert(".", sKeyword, 0);
        CASE IndexInList( sKeyword, ".FILE    .SUBST   .GO      .MESSAGE .END     ",8) OF
            0 : WriteErr("Command [");
                WriteErr( sSlice);
                LineErr("] not known ")
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
            3 : Process;
                bFileDefined := FALSE;
                bSubstDefined := FALSE;
                ClearArray;
            |
            4 : LineErr( sRecord)
            |
            5 : LineErr("Processing complete.");
                Terminate(0)

        END
    END; (* FOR *)
    IF bFileDefined OR bSubstDefined THEN
        Error("GO not processed.")
    END;
    LineErr("Processing complete.");

    DISPOSE(pasProgram);

END TextSubstitutionLanguage.

