IMPORT DataMgmt;
IMPORT Std;

EXPORT GenData := MODULE(DataMgmt.Common)

    /**
     * A convenience method (function macro) that returns the actual data stored
     * in a given generation.  Note that an underlying assumption here is
     * that the data is stored as a flat logical file; it will not work with
     * delimited, XML, or JSON data structures, for instance (those types of
     * structures are generally supported, just not with this function macro).
     *
     * @param   dataStorePath   The full path of the generational data store;
     *                          REQUIRED
     * @param   recLayout       The ECL RECORD structure of the data; REQUIRED
     * @param   numGeneration   An integer indicating which generation of data
     *                          to retrieve; generations are numbered starting
     *                          with 1 and increasing; OPTIONAL, defaults to 1
     *
     * @return  A dataset containing the desired generation of data.  If no
     *          data is found for any reason then an empty dataset with the
     *          given record structure is returned.
     *
     * @see     GetPath
     * @see     CurrentPath
     * @see     CurrentData
     */
    EXPORT GetData(dataStorePath, recLayout, numGeneration = 1) := FUNCTIONMACRO
        IMPORT DataMgmt;

        #UNIQUENAME(path);
        LOCAL %path% := DataMgmt.GenData.GetPath(dataStorePath, numGeneration);

        RETURN DATASET(%path%, recLayout, FLAT, OPT);
    ENDMACRO;

    /**
     * A convenience method (function macro) that returns the actual data stored
     * in the current generation.  Note that an underlying assumption here is
     * that the data is stored as a flat logical file; it will not work with
     * delimited, XML, or JSON data structures, for instance (those types of
     * structures are generally supported, just not with this function macro).
     * This is the same as calling GetData() and asking for generation 1.
     *
     * @param   dataStorePath   The full path of the generational data store;
     *                          REQUIRED
     * @param   recLayout       The ECL RECORD structure of the data; REQUIRED
     *
     * @return  A dataset containing the current generation of data.  If no
     *          data is found for any reason then an empty dataset with the
     *          given record structure is returned.
     *
     * @see     CurrentPath
     * @see     GetPath
     * @see     GetData
     */
    EXPORT CurrentData(dataStorePath, recLayout) := FUNCTIONMACRO
        IMPORT DataMgmt;

        #UNIQUENAME(path);
        LOCAL %path% := DataMgmt.GenData.CurrentPath(dataStorePath);

        RETURN DATASET(%path%, recLayout, FLAT, OPT);
    ENDMACRO;

    /**
     * Construct a path for a new logical file for the data store.  Note that
     * the returned value will have time-oriented components in it, therefore
     * callers should probably mark the returned value as INDEPENDENT if name
     * will be used more than once (say, creating the file via OUTPUT and then
     * calling WriteFile() here to store it) to avoid a recomputation of the
     * name.
     *
     * @param   dataStorePath   The full path of the generational data store;
     *                          REQUIRED
     *
     * @return  String representing a new logical subfile that may be added
     *          to the data store.
     */
    EXPORT NewSubfilePath(STRING dataStorePath) := _NewSubfilePath(dataStorePath);

    /**
     * Make the given logical file the first generation of data for the data
     * store and bump all existing generations of data to the next level.  If
     * data is stored in the last generation then it will be deleted.
     *
     * @param   dataStorePath   The full path of the generational data store;
     *                          REQUIRED
     * @param   newFilePath     The full path of the logical file to insert
     *                          into the data store as the new current
     *                          generation of data; REQUIRED
     *
     * @return  An action that inserts the given logical file into the data
     *          store.  Existing generations of data are bumped to the next
     *          generation, and any data stored in the last generation will
     *          be deleted.
     *
     * @see     WriteData
     * @see     AppendFile
     * @see     AppendData
     */
    EXPORT WriteFile(STRING dataStorePath, STRING newFilePath) := _WriteFile(dataStorePath, newFilePath);

    /**
     * Convenience method (function macro) that creates a new logical file
     * from the given data and inserts it into the data store, making it
     * the first generation of data.  All existing generations of data will
     * be bumped to the next level.  If data is stored in the last generation
     * then it will be deleted.
     *
     * @param   dataStorePath   The full path of the generational data store;
     *                          REQUIRED
     * @param   ds              The dataset to insert into the data store;
     *                          REQUIRED
     * @param   filenameSuffix  String suffix to be added to the generated
     *                          logical subfile name; use this if you intend to
     *                          call this method multiple times in a single
     *                          execution run; OPTIONAL, defaults to an
     *                          empty string.
     *
     * @return  An action that creates a new logical subfile and insert it into
     *          the data store.  Existing generations of data are bumped to the
     *          next generation, and any data stored in the last generation will
     *          be deleted.
     *
     * @see     WriteFile
     * @see     AppendFile
     * @see     AppendData
     */
    EXPORT WriteData(dataStorePath, ds, filenameSuffix = '\'\'') := FUNCTIONMACRO
        IMPORT DataMgmt;

        #UNIQUENAME(subfilePath0);
        LOCAL %subfilePath0% := DataMgmt.GenData.NewSubfilePath(dataStorePath) : INDEPENDENT;

        #UNIQUENAME(subfilePath);
        LOCAL %subfilePath% := %subfilePath0% + filenameSuffix;

        #UNIQUENAME(createSubfileAction);
        LOCAL %createSubfileAction% := OUTPUT(ds,, %subfilePath%, COMPRESSED);

        #UNIQUENAME(allActions);
        LOCAL %allActions% := ORDERED
            (
                %createSubfileAction%;
                DataMgmt.GenData.WriteFile(dataStorePath, %subfilePath%);
            );

        RETURN %allActions%;
    ENDMACRO;

    /**
     * Adds the given logical file to the first generation of data for the data
     * store.  This does not replace any existing data, nor bump any data
     * generations to another level.  The record structure of this data must
     * be the same as other data in the data store.
     *
     * @param   dataStorePath   The full path of the generational data store;
     *                          REQUIRED
     * @param   newFilePath     The full path of the logical file to append
     *                          to the current generation of data; REQUIRED
     *
     * @return  An action that appends the given logical file to the current
     *          generation of data.
     *
     * @see     AppendData
     * @see     WriteFile
     * @see     WriteData
     */
    EXPORT AppendFile(STRING dataStorePath, STRING newFilePath) := _AppendFile(dataStorePath, newFilePath);

    /**
     * Convenience method (function macro) that creates a new logical file
     * from the given data and adds it to the first generation of data for the
     * data store.  No existing data is replaced, nor is any data bumped to
     * the next level.  The record structure of this data must be the same as
     * other data in the data store.
     *
     * @param   dataStorePath   The full path of the generational data store;
     *                          REQUIRED
     * @param   ds              The dataset to added into the data store;
     *                          REQUIRED
     * @param   filenameSuffix  String suffix to be added to the generated
     *                          logical subfile name; use this if you intend to
     *                          call this method multiple times in a single
     *                          execution run; OPTIONAL, defaults to an
     *                          empty string.
     *
     * @return  An action that creates a new logical subfile and adds it to
     *          the first generation of data in the data store.
     *
     * @see     AppendFile
     * @see     WriteFile
     * @see     WriteData
     */
    EXPORT AppendData(dataStorePath, ds, filenameSuffix = '\'\'') := FUNCTIONMACRO
        IMPORT DataMgmt;

        #UNIQUENAME(subfilePath0);
        LOCAL %subfilePath0% := DataMgmt.GenData.NewSubfilePath(dataStorePath) : INDEPENDENT;

        #UNIQUENAME(subfilePath);
        LOCAL %subfilePath% := %subfilePath0% + filenameSuffix;

        #UNIQUENAME(createSubfileAction);
        LOCAL %createSubfileAction% := OUTPUT(ds,, %subfilePath%, COMPRESSED);

        #UNIQUENAME(allActions);
        LOCAL %allActions% := ORDERED
            (
                %createSubfileAction%;
                DataMgmt.GenData.AppendFile(dataStorePath, %subfilePath%);
            );

        RETURN %allActions%;
    ENDMACRO;

    /**
     * Method promotes all data associated with the first generation into the
     * second, promotes the second to the third, and so on.  The first
     * generation of data will be empty after this method completes.
     *
     * Note that if you have multiple logical files associated with a generation,
     * as via AppendFile() or AppendData(), all of those files will be deleted
     * or moved.
     *
     * @param   dataStorePath   The full path of the generational data store;
     *                          REQUIRED
     *
     * @return  An action that performs the generational promotion.
     *
     * @see     RollbackGeneration
     */
    EXPORT PromoteGeneration(STRING dataStorePath) := _PromoteGeneration(dataStorePath);

    /**
     * Method deletes all data associated with the current (first) generation of
     * data, moves the second generation of data into the first generation, then
     * repeats the process for any remaining generations.  This functionality
     * can be thought of restoring an older version of the data to the current
     * generation.
     *
     * Note that if you have multiple logical files associated with a generation,
     * as via AppendFile() or AppendData(), all of those files will be deleted
     * or moved.
     *
     * @param   dataStorePath   The full path of the generational data store;
     *                          REQUIRED
     *
     * @return  An action that performs the generational rollback.
     *
     * @see     PromoteGeneration
     */
    EXPORT RollbackGeneration(STRING dataStorePath) := _RollbackGeneration(dataStorePath);

    /**
     * Delete all data associated with the data store but leave the
     * surrounding superfile structure intact.
     *
     * @param   dataStorePath   The full path of the generational data store;
     *                          REQUIRED
     *
     * @return  An action performing the delete operations.
     */
    EXPORT ClearAll(STRING dataStorePath) := _ClearAll(dataStorePath);

    /**
     * Delete all data and structure associated with the data store.
     *
     * @param   dataStorePath   The full path of the generational data store;
     *                          REQUIRED
     *
     * @return  An action performing the delete operations.
     *
     * @see     _ClearAll
     */
    EXPORT DeleteAll(STRING dataStorePath) := _DeleteAll(dataStorePath);

    //--------------------------------------------------------------------------

    EXPORT Tests := MODULE

        SHARED dataStoreName := '~gendata::test::' + Std.System.Job.WUID();
        SHARED numGens := 5;

        SHARED subfilePath := NewSubfilePath(dataStoreName) : INDEPENDENT;

        SHARED TestRec := {INTEGER1 n};

        SHARED testInit := SEQUENTIAL
            (
                Init(dataStoreName, numGens);
                EVALUATE(NumGenerationsAvailable(dataStoreName));
                TRUE;
            );

        SHARED testInsertFile1 := FUNCTION
            ds1 := DATASET(10, TRANSFORM(TestRec, SELF.n := RANDOM()));
            ds1Path := subfilePath + '-testInsertFile1';

            RETURN SEQUENTIAL
                (
                    OUTPUT(ds1,,ds1Path);
                    WriteFile(dataStoreName, ds1Path);
                    ASSERT(DataMgmt.Common.NumGenerationsInUse(dataStoreName) = 1);
                    ASSERT(COUNT(DATASET(DataMgmt.Common.CurrentPath(dataStoreName), TestRec, FLAT, OPT)) = 10)
                );
        END;

        SHARED testInsertFile2 := FUNCTION
            ds2 := DATASET(20, TRANSFORM(TestRec, SELF.n := RANDOM()));
            ds2Path := subfilePath + '-testInsertFile2';

            RETURN SEQUENTIAL
                (
                    OUTPUT(ds2,,ds2Path);
                    WriteFile(dataStoreName, ds2Path);
                    ASSERT(DataMgmt.Common.NumGenerationsInUse(dataStoreName) = 2);
                    ASSERT(COUNT(DATASET(DataMgmt.Common.CurrentPath(dataStoreName), TestRec, FLAT, OPT)) = 20)
                );
        END;

        SHARED testAppendFile1 := FUNCTION
            ds3 := DATASET(15, TRANSFORM(TestRec, SELF.n := RANDOM()));
            ds3Path := subfilePath + '-testAppendFile1';

            RETURN SEQUENTIAL
                (
                    OUTPUT(ds3,,ds3Path);
                    AppendFile(dataStoreName, ds3Path);
                    ASSERT(DataMgmt.Common.NumGenerationsInUse(dataStoreName) = 2);
                    ASSERT(COUNT(DATASET(DataMgmt.Common.CurrentPath(dataStoreName), TestRec, FLAT, OPT)) = 35)
                );
        END;

        SHARED testPromote := SEQUENTIAL
            (
                PromoteGeneration(dataStoreName);
                ASSERT(DataMgmt.Common.NumGenerationsInUse(dataStoreName) = 3);
                ASSERT(NOT EXISTS(DATASET(DataMgmt.Common.CurrentPath(dataStoreName), TestRec, FLAT, OPT)))
            );

        SHARED testRollback1 := SEQUENTIAL
            (
                RollbackGeneration(dataStoreName);
                ASSERT(DataMgmt.Common.NumGenerationsInUse(dataStoreName) = 2);
                ASSERT(COUNT(DATASET(DataMgmt.Common.CurrentPath(dataStoreName), TestRec, FLAT, OPT)) = 35)
            );

        SHARED testRollback2 := SEQUENTIAL
            (
                RollbackGeneration(dataStoreName);
                ASSERT(DataMgmt.Common.NumGenerationsInUse(dataStoreName) = 1);
                ASSERT(COUNT(DATASET(DataMgmt.Common.CurrentPath(dataStoreName), TestRec, FLAT, OPT)) = 10)
            );

        SHARED testClearAll := SEQUENTIAL
            (
                ClearAll(dataStoreName);
                ASSERT(DataMgmt.Common.NumGenerationsInUse(dataStoreName) = 0);
            );

        SHARED testDeleteAll := SEQUENTIAL
            (
                DeleteAll(dataStoreName);
                ASSERT(NOT Std.File.SuperFileExists(dataStoreName));
            );

        EXPORT DoAll := SEQUENTIAL
            (
                testInit;
                testInsertFile1;
                testInsertFile2;
                testAppendFile1;
                testPromote;
                testRollback1;
                testRollback2;
                testClearAll;
                testDeleteAll;
            );
    END;

END;
