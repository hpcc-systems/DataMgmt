IMPORT DataMgmt;
IMPORT Std;

EXPORT GenIndex := MODULE(DataMgmt.Common)

    //--------------------------------------------------------------------------
    // Internal Declarations and Functions
    //--------------------------------------------------------------------------

    SHARED ROXIE_PACKAGEMAP_NAME := 'genindex_packagemap.pkg';
    SHARED DEFAULT_ROXIE_TARGET := 'roxie';
    SHARED DEFAULT_ROXIE_PROCESS := '*';

    SHARED FilePathLayout := RECORD
        STRING      path;
    END;

    /**
     * Local helper function finds all subkeys for the given superkey
     * and creates a Roxie packagemap-compatible string citing them.  Subkeys
     * are located recursively, so embedded superkeys will be processed
     * correctly.
     *
     * @param   superkeyPath    The path to the superkey we're processing
     *
     * @return  String in Roxie packagemap format citing all subkeys that make
     *          up the superkey
     */
    SHARED SuperfilePackageMapString(STRING superkeyPath) := FUNCTION
        trimmedsuperkeyPath := TRIM(superkeyPath, LEFT, RIGHT) : GLOBAL;

        StringRec := RECORD
            STRING  s;
        END;

        // Get all subkeys referenced by the superkey, recursively
        subkeyPaths := NOTHOR(Std.File.SuperFileContents(trimmedsuperkeyPath, TRUE));

        // Create packagemap-compatible string fragments that reference the
        // subkeys
        subkeyDefinitions := PROJECT
            (
                subkeyPaths,
                TRANSFORM
                    (
                        StringRec,
                        SELF.s := '<SubFile value="~' + LEFT.name + '"/>';
                    )
            );

        // Collapse to a single string
        subkeyDefinition := Std.Str.CombineWords((SET OF STRING)SET(subkeyDefinitions, s), '');

        // Wrap the subkey declarations in a superfile tag
        superkeyDefinition := '<SuperFile id="' + trimmedsuperkeyPath + '">' + subkeyDefinition + '</SuperFile>';

        RETURN superkeyDefinition;
    END;

    /**
     * Local helper function that creates a Roxie packagemap-compatible
     * string mapping a Roxie query with the data it will use after the
     * packagemap is applied.
     *
     * @param   roxieQueryName              The name (not the ID) of the
     *                                      Roxie query
     * @param   superkeyPathList            A dataset containing a list of
     *                                      superkeys that will are referenced
     *                                      by the query
     *
     * @return  Roxie packagemap string suitable for sending to workunit
     *          services for updating the Roxie query
     */
    SHARED RoxiePackageMapString(STRING roxieQueryName,
                                 DATASET(FilePathLayout) superkeyPathList) := FUNCTION
        RefRec := RECORD
            STRING  superfileRef;
            STRING  subfileRefs;
        END;

        // Lowercase paths to assist deduplication effort
        preppedSuperkeyPathList := PROJECT
            (
                superkeyPathList,
                TRANSFORM
                    (
                        RECORDOF(LEFT),
                        SELF.path := Std.Str.ToLowerCase(LEFT.path)
                    )
            );

        // Create packagemap-compatible string fragments referencing each
        // superfile and its subfiles
        superFilePackageStrings := PROJECT
            (
                DEDUP(preppedSuperkeyPathList, ALL, WHOLE RECORD),
                TRANSFORM
                    (
                        RefRec,

                        packageID := TRIM(Std.Str.FilterOut(LEFT.path, '~'), LEFT, RIGHT);
                        packageMapString := SuperfilePackageMapString(LEFT.path);

                        SELF.superfileRef := '<Base id="' + packageID + '"/>',
                        SELF.subfileRefs := '<Package id="' + packageID + '">' + packageMapString + '</Package>'
                    )
            );

        // Collapse the string fragments
        superfileRefs := Std.Str.CombineWords((SET OF STRING)SET(superFilePackageStrings, superfileRef), '');
        subfileRefs := Std.Str.CombineWords((SET OF STRING)SET(superFilePackageStrings, subfileRefs), '');

        // Wrap the query definition (query name + its superfiles)
        queryDefinition := '<Package id="' + TRIM(roxieQueryName, LEFT, RIGHT) + '">' + superfileRefs + '</Package>';

        // Wrap the entire thing up with the right XML tag
        finalDefinition := '<RoxiePackages>' + queryDefinition + subfileRefs + '</RoxiePackages>';

        RETURN finalDefinition;
    END;

    /**
     * Creates and applies a new packagemap for the given Roxie query and
     * associated superfiles.
     *
     * Note that this function requires HPCC 6.0.0 or later to succeed.
     *
     * This function returns a value but will likely often need to be called
     * in an action context, such as within a SEQUENTIAL set of commands
     * that includes superfile management.  You can wrap the call to this
     * function in an EVALUATE() to allow that construct to work.
     *
     * @param   roxieQueryName              The name (not the ID) of the Roxie
     *                                      query
     * @param   dataStorePath               The full path to the superkey we
     *                                      will be processing
     * @param   espURL                      The full URL to the ESP service,
     *                                      which is the same as the URL used
     *                                      for ECL Watch
     * @param   roxieTargetName             The name of the target Roxie that
     *                                      will receive the new packagemap
     * @param   roxieProcessName            The name of the specific Roxie
     *                                      process to target
     *
     * @return  A numeric code indicating success (zero = success).
     */
    SHARED UpdateRoxieSuperkeys(STRING roxieQueryName,
                                STRING dataStorePath,
                                STRING espURL,
                                STRING roxieTargetName,
                                STRING roxieProcessName) := FUNCTION
        superkeyPathList := DATASET([CurrentPath(dataStorePath)], FilePathLayout);
        newPackage := RoxiePackageMapString(roxieQueryName, superkeyPathList);
        espHost := REGEXREPLACE('/+$', espURL, '');
        packagePartName := roxieQueryName + '-' + REGEXREPLACE('\\W+', dataStorePath, '-') + '-package.part';

        StatusRec := RECORD
            INTEGER     code            {XPATH('Code')};
            STRING      description     {XPATH('Description')};
        END;

        addPartToPackageMapResponse := SOAPCALL
            (
                espHost + '/WsPackageProcess/',
                'AddPartToPackageMap',
                {
                    STRING      targetCluster               {XPATH('Target')} := roxieTargetName;
                    STRING      targetProcess               {XPATH('Process')} := roxieProcessName;
                    STRING      packageMapID                {XPATH('PackageMap')} := ROXIE_PACKAGEMAP_NAME;
                    STRING      partName                    {XPATH('PartName')} := packagePartName;
                    STRING      packageMapData              {XPATH('Content')} := newPackage;
                    BOOLEAN     deletePreviousPackagePart   {XPATH('DeletePrevious')} := TRUE;
                    STRING      daliIP                      {XPATH('DaliIp')} := Std.System.Thorlib.DaliServer();
                },
                StatusRec,
                XPATH('AddPartToPackageMapResponse/status')
            );

        activatePackageResponse := SOAPCALL
            (
                espHost + '/WsPackageProcess/',
                'ActivatePackage',
                {
                    STRING      targetCluster               {XPATH('Target')} := roxieTargetName;
                    STRING      targetProcess               {XPATH('Process')} := roxieProcessName;
                    STRING      packageMapID                {XPATH('PackageMap')} := ROXIE_PACKAGEMAP_NAME;
                },
                StatusRec,
                XPATH('ActivatePackageResponse/status')
            );

        finalResponse := IF
            (
                addPartToPackageMapResponse.code = 0,
                activatePackageResponse,
                addPartToPackageMapResponse
            );

        RETURN WHEN(finalResponse.code, ASSERT(finalResponse.code = 0, 'Error while updating packagemap: ' + (STRING)finalResponse.code + '; (' + Std.Str.CombineWords([roxieQueryName, dataStorePath, espURL, roxieTargetName, roxieProcessName], ',') + ')', FAIL));
    END;

    //--------------------------------------------------------------------------
    // Exported Functions
    //--------------------------------------------------------------------------

    /**
     * Construct a path for a new index for the index store.  Note that
     * the returned value will have time-oriented components in it, therefore
     * callers should probably mark the returned value as INDEPENDENT if name
     * will be used more than once (say, creating the index via BUILD and then
     * calling WriteIndexFile() here to store it) to avoid a recomputation of
     * the name.
     *
     * @param   dataStorePath   The full path of the generational index store;
     *                          REQUIRED
     *
     * @return  String representing a new index that may be added to the
     *          index store.
     */
    EXPORT NewSubkeyPath(STRING dataStorePath) := _NewSubfilePath(dataStorePath);

    /**
     * Function simply updates the given Roxie query with the indexes that
     * reside in the current generation of the index store.  This may useful
     * for rare cases where the Roxie query is redeployed and the references
     * to the current index store are lost, or if the index store contents are
     * manipulated outside of these functions and you tell the Roxie query
     * about the changes, or if you have several Roxie queries that reference
     * an index store and you want to update them independently.
     *
     * Because some versions of HPCC have had difficulty dealing with same-
     * named index files being repeatedly inserted and removed from a Roxie
     * query, it is highly recommended that you name index files uniquely by
     * using this function or one like it.
     *
     * @param   dataStorePath           The full path of the generational data
     *                                  store; REQUIRED
     * @param   roxieQueryName          The name of the Roxie query to update
     *                                  with the new index information; REQUIRED
     * @param   espURL                  The URL to the ESP service on the
     *                                  cluster, which is the same URL as used
     *                                  for ECL Watch; REQUIRED
     * @param   roxieTargetName         The name of the Roxie cluster to send
     *                                  the information to; OPTIONAL, defaults
     *                                  to 'roxie'
     * @param   roxieProcessName        The name of the specific Roxie process
     *                                  to target; OPTIONAL, defaults to '*'
     *                                  (all processes)
     *
     * @return  An action that updates the given Roxie query with the contents
     *          of the current generation of indexes.
     */
    EXPORT UpdateRoxie(STRING dataStorePath,
                       STRING roxieQueryName,
                       STRING espURL,
                       STRING roxieTargetName = DEFAULT_ROXIE_TARGET,
                       STRING roxieProcessName = DEFAULT_ROXIE_PROCESS) := FUNCTION
        updateRoxieAction := EVALUATE(UpdateRoxieSuperkeys(roxieQueryName, dataStorePath, espURL, roxieTargetName, roxieProcessName));

        RETURN IF(roxieQueryName != '', updateRoxieAction);
    END;

    /**
     * Make the given index the first generation of index for the index store,
     * bump all existing generations of data to the next level, then update
     * the given Roxie query with references to the new index.  Any indexes
     * stored in the last generation will be deleted.
     *
     * @param   dataStorePath           The full path of the generational data
     *                                  store; REQUIRED
     * @param   newIndexPath            The full path of the new index to insert
     *                                  into the index store as the new current
     *                                  generation of data; REQUIRED
     * @param   roxieQueryName          The name of the Roxie query to update
     *                                  with the new index information; REQUIRED
     * @param   espURL                  The URL to the ESP service on the
     *                                  cluster, which is the same URL as used
     *                                  for ECL Watch; REQUIRED
     * @param   roxieTargetName         The name of the Roxie cluster to send
     *                                  the information to; OPTIONAL, defaults
     *                                  to 'roxie'
     * @param   roxieProcessName        The name of the specific Roxie process
     *                                  to target; OPTIONAL, defaults to '*'
     *                                  (all processes)
     *
     * @return  An action that inserts the given index into the index store.
     *          Existing generations of indexes are bumped to the next
     *          generation, and any index stored in the last generation will
     *          be deleted.
     *
     * @see     AppendIndexFile
     */
    EXPORT WriteIndexFile(STRING dataStorePath,
                          STRING newIndexPath,
                          STRING roxieQueryName,
                          STRING espURL,
                          STRING roxieTargetName = DEFAULT_ROXIE_TARGET,
                          STRING roxieProcessName = DEFAULT_ROXIE_PROCESS) := FUNCTION
        updateRoxieAction := UpdateRoxie(dataStorePath, roxieQueryName, espURL, roxieTargetName, roxieProcessName);
        promoteAction := _WriteFile(dataStorePath, newIndexPath);
        allActions := SEQUENTIAL
            (
                promoteAction;
                IF(roxieQueryName != '', updateRoxieAction);
            );

        RETURN allActions;
    END;

    /**
     * Adds the given index to the first generation of indexes for the data
     * store.  This does not replace any existing index, nor bump any index
     * generations to another level.  The record structure of this index must
     * be the same as other indexes in the index store.
     *
     * @param   dataStorePath           The full path of the generational data
     *                                  store; REQUIRED
     * @param   newIndexPath            The full path of the new index to append
     *                                  to the current generation of indexes;
     *                                  REQUIRED
     * @param   roxieQueryName          The name of the Roxie query to update
     *                                  with the new index information; REQUIRED
     * @param   espURL                  The URL to the ESP service on the
     *                                  cluster, which is the same URL as used
     *                                  for ECL Watch; REQUIRED
     * @param   roxieTargetName         The name of the Roxie cluster to send
     *                                  the information to; OPTIONAL, defaults
     *                                  to 'roxie'
     * @param   roxieProcessName        The name of the specific Roxie process
     *                                  to target; OPTIONAL, defaults to '*'
     *                                  (all processes)
     *
     * @return  An action that appends the given index to the current
     *          generation of indexes.
     *
     * @see     WriteIndexFile
     */
    EXPORT AppendIndexFile(STRING dataStorePath,
                           STRING newIndexPath,
                           STRING roxieQueryName,
                           STRING espURL,
                           STRING roxieTargetName = DEFAULT_ROXIE_TARGET,
                           STRING roxieProcessName = DEFAULT_ROXIE_PROCESS) := FUNCTION
        updateRoxieAction := UpdateRoxie(dataStorePath, roxieQueryName, espURL, roxieTargetName, roxieProcessName);
        promoteAction := _AppendFile(dataStorePath, newIndexPath);
        allActions := SEQUENTIAL
            (
                promoteAction;
                IF(roxieQueryName != '', updateRoxieAction);
            );

        RETURN allActions;
    END;

    /**
     * Method deletes all indexes associated with the current (first) generation
     * of data, moves the second generation of indexes into the first
     * generation, then repeats the process for any remaining generations.  This
     * functionality can be thought of as restoring an older version of the
     * index to the current generation.
     *
     * Note that if you have multiple indexes associated with a generation,
     * as via AppendIndexFile(), all of those indexes will be deleted
     * or moved.
     *
     * @param   dataStorePath           The full path of the generational data
     *                                  store; REQUIRED
     * @param   roxieQueryName          The name of the Roxie query to update
     *                                  with the new index information; REQUIRED
     * @param   espURL                  The URL to the ESP service on the
     *                                  cluster, which is the same URL as used
     *                                  for ECL Watch; REQUIRED
     * @param   roxieTargetName         The name of the Roxie cluster to send
     *                                  the information to; OPTIONAL, defaults
     *                                  to 'roxie'
     * @param   roxieProcessName        The name of the specific Roxie process
     *                                  to target; OPTIONAL, defaults to '*'
     *                                  (all processes)
     *
     * @return  An action that performs the generational rollback.
     */
    EXPORT RollbackGeneration(STRING dataStorePath,
                              STRING roxieQueryName,
                              STRING espURL,
                              STRING roxieTargetName = DEFAULT_ROXIE_TARGET,
                              STRING roxieProcessName = DEFAULT_ROXIE_PROCESS) := FUNCTION
        updateRoxieAction := UpdateRoxie(dataStorePath, roxieQueryName, espURL, roxieTargetName, roxieProcessName);
        rollbackAction := _RollbackGeneration(dataStorePath);
        allActions := SEQUENTIAL
            (
                rollbackAction;
                IF(roxieQueryName != '', updateRoxieAction);
            );

        RETURN allActions;
    END;

    /**
     * Delete all indexes associated with the index store but leave the
     * surrounding superfile structure intact.
     *
     * @param   dataStorePath           The full path of the generational data
     *                                  store; REQUIRED
     * @param   roxieQueryName          The name of the Roxie query to update
     *                                  with the new index information; REQUIRED
     * @param   espURL                  The URL to the ESP service on the
     *                                  cluster, which is the same URL as used
     *                                  for ECL Watch; REQUIRED
     * @param   roxieTargetName         The name of the Roxie cluster to send
     *                                  the information to; OPTIONAL, defaults
     *                                  to 'roxie'
     * @param   roxieProcessName        The name of the specific Roxie process
     *                                  to target; OPTIONAL, defaults to '*'
     *                                  (all processes)
     *
     * @return  An action performing the delete operations.
     */
    EXPORT ClearAll(STRING dataStorePath,
                    STRING roxieQueryName,
                    STRING espURL,
                    STRING roxieTargetName = DEFAULT_ROXIE_TARGET,
                    STRING roxieProcessName = DEFAULT_ROXIE_PROCESS) := FUNCTION
        tempSuperfilePath := dataStorePath + '::' + Std.System.Job.WUID();
        subkeysToDelete := PROJECT
            (
                NOTHOR(Std.File.SuperFileContents(dataStorePath, TRUE)),
                TRANSFORM
                    (
                        {
                            STRING  owner,
                            STRING  subkey
                        },
                        SELF.subkey := '~' + LEFT.name,
                        SELF.owner := '~' + Std.File.LogicalFileSuperOwners(SELF.subkey)[1].name
                    )
            );
        addSubkeysToTempSuperfileAction := NOTHOR
            (
                APPLY
                    (
                        subkeysToDelete,
                        Std.File.AddSuperFile(tempSuperfilePath, subkey)
                    )
            );
        removeOldSubkeysAction := NOTHOR
            (
                APPLY
                    (
                        subkeysToDelete,
                        Std.File.RemoveSuperFile(owner, subkey)
                    )
            );
        deleteTempSuperfileAction := NOTHOR(Std.File.DeleteSuperFile(tempSuperfilePath, TRUE));
        updateRoxieAction := UpdateRoxie(dataStorePath, roxieQueryName, espURL, roxieTargetName, roxieProcessName);
        allActions := SEQUENTIAL
            (
                addSubkeysToTempSuperfileAction;
                removeOldSubkeysAction;
                IF(roxieQueryName != '', updateRoxieAction);
                deleteTempSuperfileAction;
            );

        RETURN allActions;
    END;

    /**
     * Delete all indexes and structure associated with the index store.
     *
     * @param   dataStorePath           The full path of the generational data
     *                                  store; REQUIRED
     * @param   roxieQueryName          The name of the Roxie query to update
     *                                  with the new index information; REQUIRED
     * @param   espURL                  The URL to the ESP service on the
     *                                  cluster, which is the same URL as used
     *                                  for ECL Watch; REQUIRED
     * @param   roxieTargetName         The name of the Roxie cluster to send
     *                                  the information to; OPTIONAL, defaults
     *                                  to 'roxie'
     * @param   roxieProcessName        The name of the specific Roxie process
     *                                  to target; OPTIONAL, defaults to '*'
     *                                  (all processes)
     *
     * @return  An action performing the delete operations.
     */
    EXPORT DeleteAll(STRING dataStorePath,
                     STRING roxieQueryName,
                     STRING espURL,
                     STRING roxieTargetName = DEFAULT_ROXIE_TARGET,
                     STRING roxieProcessName = DEFAULT_ROXIE_PROCESS) := FUNCTION
        clearAction := ClearAll(dataStorePath, roxieQueryName, espURL, roxieTargetName, roxieProcessName);
        deleteAction := _DeleteAll(dataStorePath);
        allActions := SEQUENTIAL
            (
                clearAction;
                deleteAction;
            );

        RETURN allActions;
    END;

    //--------------------------------------------------------------------------

    EXPORT Tests := MODULE

        SHARED indexStoreName := '~genindex::test::' + Std.System.Job.WUID() : INDEPENDENT;
        SHARED numGens := 3;

        SHARED subkeyPath := NewSubkeyPath(indexStoreName) : INDEPENDENT;

        SHARED TestRec := {INTEGER1 n};
        SHARED TestIDX(DATASET(TestRec) ds, STRING path) := INDEX(ds, {n}, {}, path);
        SHARED CurrentIDX := INDEX({TestRec.n}, {}, DataMgmt.Common.CurrentPath(indexStoreName), OPT);

        SHARED testInit := SEQUENTIAL
            (
                Init(indexStoreName, numGens);
                ASSERT(DataMgmt.Common.NumGenerationsAvailable(indexStoreName) = numGens);
                TRUE;
            );

        SHARED testInsertFile1 := FUNCTION
            ds1 := DATASET(10, TRANSFORM(TestRec, SELF.n := RANDOM()));
            idx1Path := subkeyPath + '-testInsertFile1';
            idx1 := TestIDX(ds1, idx1Path);

            RETURN SEQUENTIAL
                (
                    BUILD(idx1);
                    WriteIndexFile(indexStoreName, idx1Path, '', '');
                    ASSERT(DataMgmt.Common.NumGenerationsInUse(indexStoreName) = 1);
                    ASSERT(COUNT(CurrentIDX) = 10)
                );
        END;

        SHARED testInsertFile2 := FUNCTION
            ds2 := DATASET(20, TRANSFORM(TestRec, SELF.n := RANDOM()));
            idx2Path := subkeyPath + '-testInsertFile2';
            idx2 := TestIDX(ds2, idx2Path);

            RETURN SEQUENTIAL
                (
                    BUILD(idx2);
                    WriteIndexFile(indexStoreName, idx2Path, '', '');
                    ASSERT(DataMgmt.Common.NumGenerationsInUse(indexStoreName) = 2);
                    ASSERT(COUNT(CurrentIDX) = 20)
                );
        END;

        SHARED testAppendFile1 := FUNCTION
            ds3 := DATASET(15, TRANSFORM(TestRec, SELF.n := RANDOM()));
            idx3Path := subkeyPath + '-testAppendFile1';
            idx3 := TestIDX(ds3, idx3Path);

            RETURN SEQUENTIAL
                (
                    BUILD(idx3);
                    AppendIndexFile(indexStoreName, idx3Path, '', '');
                    ASSERT(DataMgmt.Common.NumGenerationsInUse(indexStoreName) = 2);
                    ASSERT(COUNT(CurrentIDX) = 35)
                );
        END;

        SHARED testRollback1 := SEQUENTIAL
            (
                RollbackGeneration(indexStoreName, '', '');
                ASSERT(DataMgmt.Common.NumGenerationsInUse(indexStoreName) = 1);
                ASSERT(COUNT(CurrentIDX) = 10)
            );

        SHARED testRollback2 := SEQUENTIAL
            (
                RollbackGeneration(indexStoreName, '', '');
                ASSERT(DataMgmt.Common.NumGenerationsInUse(indexStoreName) = 0);
                ASSERT(NOT EXISTS(CurrentIDX))
            );

        SHARED testClearAll := SEQUENTIAL
            (
                ClearAll(indexStoreName, '', '');
                ASSERT(DataMgmt.Common.NumGenerationsInUse(indexStoreName) = 0);
            );

        SHARED testDeleteAll := SEQUENTIAL
            (
                DeleteAll(indexStoreName, '', '');
                ASSERT(NOT Std.File.SuperFileExists(indexStoreName));
            );

        EXPORT DoAll := SEQUENTIAL
            (
                testInit;
                testInsertFile1;
                testInsertFile2;
                testAppendFile1;
                testRollback1;
                testRollback2;
                testClearAll;
                testDeleteAll;
            );
    END;

END;
