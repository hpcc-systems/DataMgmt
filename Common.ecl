IMPORT DataMgmt;
IMPORT Std;

EXPORT Common := MODULE, VIRTUAL

    //--------------------------------------------------------------------------
    // Internal to this module
    //--------------------------------------------------------------------------

    SHARED DEFAULT_GENERATION_CNT := 3; // Update Init() docs if changed
    SHARED MIN_GENERATION_CNT := 2;
    SHARED SUPERFILE_SUFFIX := 'gen_';
    SHARED SUBFILE_SUFFIX := 'file_';

    SHARED _BuildSuperfilePathPrefix(STRING parent) := Std.Str.ToLowerCase(parent) + '::' + SUPERFILE_SUFFIX;

    SHARED _BuildSuperfilePath(STRING parent, UNSIGNED1 generationNum) := _BuildSuperfilePathPrefix(parent) + generationNum;

    SHARED _BuildSubfilePath(STRING parent) := Std.Str.ToLowerCase(parent) + '::' + SUBFILE_SUFFIX + Std.System.Job.WUID() + '-' + (STRING)Std.Date.CurrentTimestamp();

    SHARED _CreateSuperfilePathDS(STRING parent, UNSIGNED1 numGenerations) := DATASET
        (
            numGenerations,
            TRANSFORM
                (
                    {
                        UNSIGNED1   n, // Generation number
                        STRING      f  // Superfile path
                    },
                    SELF.n := COUNTER,
                    SELF.f := _BuildSuperfilePath(parent, COUNTER)
                )
        );

    SHARED _CreateSuperfilePathSet(STRING parent, UNSIGNED1 numGenerations) := SET(_CreateSuperfilePathDS(parent, numGenerations), f);

    SHARED _NumGenerationsAvailable(STRING dataStorePath) := FUNCTION
        generationPattern := _BuildSuperfilePathPrefix(REGEXREPLACE('^~', dataStorePath, '')) + '*';
        foundGenerationPaths := NOTHOR(Std.File.LogicalFileList(generationPattern, FALSE, TRUE));
        expectedPaths := _CreateSuperfilePathDS(REGEXREPLACE('^~', dataStorePath, ''), COUNT(foundGenerationPaths));
        joinedPaths := JOIN(foundGenerationPaths, expectedPaths, LEFT.name = RIGHT.f);
        numJoinedPaths := COUNT(joinedPaths) : INDEPENDENT;
        numExpectedPaths := COUNT(expectedPaths) : INDEPENDENT;
        isSame := numJoinedPaths = numExpectedPaths;
        isNumGenerationsValid := numJoinedPaths >= MIN_GENERATION_CNT;

        RETURN WHEN(numJoinedPaths, ASSERT(isSame AND isNumGenerationsValid, 'Invalid structure: Unexpected superfile structure found for ' + dataStorePath, FAIL));
    END;

    //--------------------------------------------------------------------------
    // Declarations and functions
    //--------------------------------------------------------------------------

    /**
     * Function initializes the superfile structure needed to support
     * generational data management methods.
     *
     * @param   dataStorePath   The full path of the generational data store
     *                          that will be created; REQUIRED
     * @param   numGenerations  The number of generations to maintain; OPTIONAL,
     *                          defaults to 3.
     *
     * @return  An action that performs the necessary steps to create the
     *          superfile structure.
     *
     * @see     DoesExist
     */
    EXPORT Init(STRING dataStorePath, UNSIGNED1 numGenerations = DEFAULT_GENERATION_CNT) := FUNCTION
        clampedGenerations := MAX(MIN_GENERATION_CNT, numGenerations);
        generationPaths := _CreateSuperfilePathDS(dataStorePath, clampedGenerations);
        createParentAction := Std.File.CreateSuperFile(dataStorePath);
        createGenerationsAction := NOTHOR(APPLY(generationPaths, Std.File.CreateSuperFile(f)));
        appendGenerationsAction := NOTHOR(APPLY(generationPaths, Std.File.AddSuperFile(dataStorePath, f)));

        RETURN ORDERED
            (
                createParentAction;
                createGenerationsAction;
                Std.File.StartSuperFileTransaction();
                appendGenerationsAction;
                Std.File.FinishSuperFileTransaction();
            );
    END;

    /**
     * A simple test of whether the top-level superfile supporting this
     * structure actually exists or not.
     *
     * @param   dataStorePath   The full path of the generational data store;
     *                          REQUIRED
     *
     * @return  A boolean indicating presence of the superfile.
     *
     * @see     Init
     */
    EXPORT DoesExist(STRING dataStorePath) := Std.File.SuperFileExists(dataStorePath);

    /**
     * Returns the number of generations of data that could be tracked by
     * the data store referenced by the argument.  The data stored must
     * already be initialized.
     *
     * @param   dataStorePath   The full path of the generational data store;
     *                          REQUIRED
     *
     * @return  An integer representing the total number of data generations
     *          that could be tracked by the data store
     *
     * @see     Init
     * @see     NumGenerationsInUse
     */
    EXPORT NumGenerationsAvailable(STRING dataStorePath) := FUNCTION
        numGens := _NumGenerationsAvailable(dataStorePath) : INDEPENDENT;

        RETURN numGens;
    END;

    /**
     * Returns the number of generations of data that are actually in use.
     * The data store must already be initialized.
     *
     * @param   dataStorePath   The full path of the generational data store;
     *                          REQUIRED
     *
     * @return  An integer representing the total number of data generations
     *          that are actually being used (those that have data)
     *
     * @see     Init
     * @see     NumGenerationsAvailable
     */
    EXPORT NumGenerationsInUse(STRING dataStorePath) := FUNCTION
        numPartitions := NumGenerationsAvailable(dataStorePath);
        generationPaths := _CreateSuperfilePathDS(dataStorePath, numPartitions);
        generationsUsed := NOTHOR
            (
                PROJECT
                    (
                        generationPaths,
                        TRANSFORM
                            (
                                {
                                    RECORDOF(LEFT),
                                    BOOLEAN     hasFiles
                                },
                                SELF.hasFiles := Std.File.GetSuperFileSubCount(LEFT.f) > 0,
                                SELF := LEFT
                            )
                    )
            );

        RETURN MAX(generationsUsed(hasFiles), n);
    END;

    /**
     * Returns the full path to the superfile containing the given generation
     * of data.  The returned value would be suitable for use in a DATASET()
     * declaration or a function that requires a file path.
     *
     * @param   dataStorePath   The full path of the generational data store;
     *                          REQUIRED
     * @param   numGeneration   An integer indicating which generation of data
     *                          to build a path for; generations are numbered
     *                          starting with 1 and increasing; OPTIONAL,
     *                          defaults to 1
     *
     * @return  String containing the full path to the superfile containing
     *          the desired generation of data.  Will return an empty string
     *          if the requested generation is beyond the number of available
     *          generations.
     *
     * @see     GetData
     * @see     CurrentPath
     * @see     CurrentData
     */
    EXPORT GetPath(STRING dataStorePath, UNSIGNED1 numGeneration = 1) := _BuildSuperfilePath(dataStorePath, numGeneration);

    /**
     * Returns the full path to the superfile containing the current generation
     * of data.  The returned value would be suitable for use in a DATASET()
     * declaration or a function that requires a file path.  This is the same
     * as calling GetPath() and asking for generation 1.
     *
     * @param   dataStorePath   The full path of the generational data store;
     *                          REQUIRED
     *
     * @return  String containing the full path to the superfile containing
     *          the current generation of data.
     *
     * @see     CurrentData
     * @see     GetPath
     * @see     GetData
     */
    EXPORT CurrentPath(STRING dataStorePath) := GetPath(dataStorePath, 1);

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
    EXPORT _NewSubfilePath(STRING dataStorePath) := _BuildSubfilePath(dataStorePath);

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
    SHARED _WriteFile(STRING dataStorePath, STRING newFilePath) := FUNCTION
        numPartitions := NumGenerationsAvailable(dataStorePath);
        superfileSet := _CreateSuperfilePathSet(dataStorePath, numPartitions);
        promoteAction := Std.File.PromoteSuperFileList(superfileSet, addHead := newFilePath, delTail := TRUE);

        RETURN promoteAction;
    END;

    /**
     * Adds the given logical file to the first generation of data for the data
     * store.  This does not replace any existing data, nor bump any data
     * generations to another level.  The record structure of this data must
     * be the same as other data in the data store.
     *
     * If the data store does not exist then it is created with default
     * parameters.
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
    SHARED _AppendFile(STRING dataStorePath, STRING newFilePath) := FUNCTION
        receivingSuperfilePath := CurrentPath(dataStorePath);
        insertSubfileAction := Std.File.AddSuperFile(receivingSuperfilePath, newFilePath);
        allActions := SEQUENTIAL
            (
                Std.File.StartSuperFileTransaction();
                insertSubfileAction;
                Std.File.FinishSuperFileTransaction();
            );

        RETURN allActions;
    END;

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
     */
    SHARED _RollbackGeneration(STRING dataStorePath) := FUNCTION
        numPartitions := NumGenerationsAvailable(dataStorePath);
        superfileSet := _CreateSuperfilePathSet(dataStorePath, numPartitions);
        promoteAction := Std.File.PromoteSuperFileList(superfileSet, reverse := TRUE, delTail := TRUE);

        RETURN promoteAction;
    END;

    /**
     * Delete all data associated with the data store but leave the
     * surrounding superfile structure intact.
     *
     * @param   dataStorePath   The full path of the generational data store;
     *                          REQUIRED
     *
     * @return  An action performing the delete operations.
     *
     * @see     DeleteAll
     */
    SHARED _ClearAll(STRING dataStorePath) := FUNCTION
        subfilesToDelete := PROJECT
            (
                NOTHOR(Std.File.SuperFileContents(dataStorePath, TRUE)),
                TRANSFORM
                    (
                        {
                            STRING  owner,
                            STRING  subfile
                        },
                        SELF.subfile := '~' + LEFT.name,
                        SELF.owner := '~' + Std.File.LogicalFileSuperOwners(SELF.subfile)[1].name
                    )
            );
        removeSubfilesAction := NOTHOR(APPLY(subfilesToDelete, Std.File.RemoveSuperFile(owner, subfile, del := TRUE)));

        RETURN removeSubfilesAction;
    END;

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
    EXPORT _DeleteAll(STRING dataStorePath) := SEQUENTIAL
        (
            _ClearAll(dataStorePath);
            NOTHOR(Std.File.DeleteSuperFile(dataStorePath, TRUE));
        );

END;
