## DataMgmt Bundle

This HPCC bundle offers concrete methods that encapsulate a generational data
management strategy.  A generational strategy means that you want to retain
older versions (generations) of data for some period of time while you continue
to work with current data, but you want to be able to roll back to an older
version of the data if needed.

Files used by Thor are managed with the GenData module in this bundle.  With
only a few exceptions, all ECL file types (flat, XML, delimited, JSON, and index
files) are supported by all of the functions in the GenData module.  There are
only two requirements:  1) all files use the same record layout, and 2) all
files are of the same file type.

Index files that are used by ROXIE are managed by the GenIndex module in this
bundle.  While Thor also uses index files, ROXIE's use of indexes complicate
data management somewhat.  The GenIndex module exposes easy-to-use (or perhaps
easier-to-use) methods for updating the indexes referenced by ROXIE without
taking any ROXIE query offline.

## Requirements

The code included in this bundle is written entirely in ECL.  No extra plugins
or third party tools are required, though functions from the Std library
(included with the platform) are used.  HPCC 6.0.0 or later is required.

## License and Version
This software is licensed under the Apache v2 license.  A link to the license,
as well as the current version of this software, can be found in the
[Bundle.ecl](Bundle.ecl)
file.

## Installation

To install a bundle to your development machine, use the ecl command line tool:

	ecl bundle install https://github.com/hpcc-systems/DataMgmt.git

For complete details, see the Client Tools Manual, available in the download
section of https://hpccsystems.com.

Note that is possible to use this code without installing it as a bundle.  To do
so, simply make it available within your IDE and just ignore the Bundle.ecl
file. With the Windows IDE, the DataMgmt directory must not be a top-level item
in your repository list; it needs to be installed one level below the top level,
such as within your "My Files" folder.

## Table of Contents

  * [General Theory of Operations](#general_theory)
  * GenData
    * [Overview](#gendata_overview)
    * [API](#gendata_api)
      * Initializing
         * [Init](#gendata_init)
      * Writing data
         * [WriteData](#gendata_writedata)
         * [WriteFile](#gendata_writefile)
         * [AppendData](#gendata_appenddata)
         * [AppendFile](#gendata_appendfile)
      * Reading data
         * [CurrentData](#gendata_currentdata)
         * [GetData](#gendata_getdata)
         * [CurrentPath](#gendata_currentpath)
         * [GetPath](#gendata_getpath)
      * Introspection
         * [DoesExist](#gendata_doesexist)
         * [NumGenerationsAvailable](#gendata_numgenerationsavailable)
         * [NumGenerationsInUse](#gendata_numgenerationsInUse)
      * Managing data
         * [PromoteGeneration](#gendata_promotegeneration)
         * [RollbackGeneration](#gendata_rollbackgeneration)
         * [ClearAll](#gendata_clearall)
         * [DeleteAll](#gendata_deleteall)
      * Other
         * [NewSubfilePath](#gendata_newsubfilepath)
    * [Example Code](#gendata_examples)
    * [Testing](#gendata_testing)
  * GenIndex
    * [Overview](#genindex_overview)
    * [API](#genindex_api)
      * Initializing
         * [Init](#genindex_init)
         * [InitROXIEPackageMap](#genindex_initroxiepackagemap)
      * Writing data
         * [WriteSubkey](#genindex_writesubkey)
         * [AppendSubkey](#genindex_appendsubkey)
      * Reading data
         * [VirtualSuperkeyPath](#genindex_virtualsuperkeypath)
         * [CurrentPath](#genindex_currentpath)
         * [GetPath](#genindex_getpath)
      * Introspection
         * [DoesExist](#genindex_doesexist)
         * [NumGenerationsAvailable](#genindex_numgenerationsavailable)
         * [NumGenerationsInUse](#genindex_numgenerationsInUse)
      * Managing data
         * [PromoteGeneration](#genindex_promotegeneration)
         * [RollbackGeneration](#genindex_rollbackgeneration)
         * [ClearAll](#genindex_clearall)
         * [DeleteAll](#genindex_deleteall)
      * Other
         * [NewSubkeyPath](#genindex_newsubkeypath)
         * [UpdateROXIE](#genindex_updateroxie)
         * [WaitForDaliUpdate](#genindex_waitfordaliupdate)
         * [RemoveROXIEPackageMap](#genindex_removeroxiepackagemap)
         * [DeleteManagedROXIEPackageMap](#genindex_deletemanagedroxiepackagemap)
    * [Example Code](#genindex_examples)
    * [Testing](#genindex_testing)

<a name="general_theory"></a>
## General Theory of Operations

A "data store" consists of a superfile containing one sub-superfile for every
generation of data that will be managed.  The path of the top-level superfile is
the same as the one provided to the `Init()` method, and the number of
generations is set by an optional argument to `Init()`.  An example may help;
given:

	DataMgmt.GenData.Init('~my_data_store', 5);

The following superfile structure will be created (indented to show the
relationship):

	my_data_store
	    my_data_store::gen_1
	    my_data_store::gen_2
	    my_data_store::gen_3
	    my_data_store::gen_4
	    my_data_store::gen_5

The "current" or "first" generation of data is represented by the
`my_data_store::gen_1` superfile.  The next oldest is represented by the
`my_data_store::gen_2` superfile, and so on.

You can track up to 255 generations of data.  The recommended minimum is three
generations, which is the default.  Three is a good minimum number, as it works
under the assumption that you always want to have a backup of your data (two
generations) and you may have to occasionally roll back to a previous version so
you need one additional generation in reserve.  The absolute minimum is two
generations.

Note that the top-level superfile includes all sub-superfile generations as
immediate children.  This hierarchy provides an easy way to access everything in
the data store (via the top-level superfile) or all of the data for a single
generation (via one of the sub-superfiles).

All of the data stored within a single generation (a sub-superfile) must be of
the same ECL file type and have the same record structure if you want to be able
to actually use the data, such as with a DATASET declaration.  Strictly
speaking, if you never attempt to load data from multiple generations
simultaneously, such as with a temporary superfile construct, then you are free
to change files types or record structures **between** generations.  You should
be careful doing this, however, as it means synchronizing the code to read a
generation with that generation's visibility (e.g. if you change a record
structure and the code using it then need to roll back the changes, you would
have to roll back both the data and code simultaneously).  It would probably be
better to set up different data stores instead, if you are faced with a
situation where the record layouts or indexes change.

Both GenData and GenIndex use the same overall superfile structure and actually
share quite a bit of the code.  The GenData code tends to refer to the structure
as "superfiles" while the GenIndex code refers to the same structure as
"superkeys" but that is simply a convention that matches the ECL documentation.

<a name="gendata_overview"></a>
## GenData: Overview

The first step is creating a data store to work with.  Using the example from
the Theory of Operations:

	DataMgmt.GenData.Init('~my_data_store', 5);

This sets up a data store that tracks up to five data generations.  If you
omitted the '5' argument then three generations will be set up for you.  The
name of the data store (~my\_data\_store) will be required for all subsequent
access.

The easiest way to add data to the data store is to use the `WriteData()`
function macro.  A new Thor compressed flat file will be created with a
unique name, then appended to the superfile representing the first generation of
data (`my_data_store::gen_1` in this example).  Any existing data that was
appended to `my_data_store::gen_1` will be moved to `my_data_store::gen_2` and
so on down the line, and any data stored in the superfile representing the last
generation of data (`my_data_store::gen_5`) will be physically deleted from the
cluster.

Example:

	MyRecLayout := { STRING name, UNSIGNED1 age };
	newData := DATASET([{'Bill', 35}], MyRecLayout);
	DataMgmt.GenData.WriteData('~my_data_store', newData);

This would result in something like the following (indented to show the
relationship):

	my_data_store
	    my_data_store::gen_1
	        my_data_store::file_w20170213-080526-1486994727334834-1
	    my_data_store::gen_2
	    my_data_store::gen_3
	    my_data_store::gen_4
	    my_data_store::gen_5

Doing the same thing again would result in something like this:

	my_data_store
	    my_data_store::gen_1
	        my_data_store::file_w20170213-080526-1486994727334834-2
	    my_data_store::gen_2
	        my_data_store::file_w20170213-080526-1486994727334834-1
	    my_data_store::gen_3
	    my_data_store::gen_4
	    my_data_store::gen_5

If a compressed flat file is not appropriate for your needs, you can create
the file yourself and then use the `WriteFile()` function to insert it into the
data store.  `WriteFile()` is nearly a drop-in replacement for ECL's OUTPUT
function (when it is used to create a new flat file).  GenData exposes the
function `NewSubfilePath()` if you want to create paths like those shown in the
examples, but you don't have to; you can use your own paths.

Note regarding the use of `NewSubfilePath()`:  Paths created by this function
have a time component in them so you have to take care to 'freeze' the return
value.  The easiest way to do that is to mark the return value as INDEPENDENT
like this:

	subfilePath := DataMgmt.GenData.NewSubfilePath('~my_data_store') : INDEPENDENT;

That works fine if you're creating one logical file, but if you're creating more
than one file in a single job then you will need to make the path unique
**after** you generate it, like this:

	subfilePrefix := DataMgmt.GenData.NewSubfilePath('~my_data_store') : INDEPENDENT;
	subfilePath1 := subfilePrefix + '-1';
	subfilePath2 := subfilePrefix + '-2';

In that example we just appended a -1 or -2 to the generated path, but that is
enough to make it unique.

ECL's superfile mechanism allows you to store more than one logical subfile
within the same superfile and access everything as if it was a single file. 
GenData allows that as well, via the `AppendData()` and `AppendFile()` exported
functions.  These functions append to only the first generation superfile and do
not "bump" data from one generation to another.  Using our previous example,
here is what the structure may look like after an `AppendData()` call:

	my_data_store
	    my_data_store::gen_1
	        my_data_store::file_w20170213-080526-1486994727334834-2
	        my_data_store::file_w20170213-080526-1486994727334834-3
	    my_data_store::gen_2
	        my_data_store::file_w20170213-080526-1486994727334834-1
	    my_data_store::gen_3
	    my_data_store::gen_4
	    my_data_store::gen_5


Don't create too many subfiles within a single generation, though, or
performance will suffer.

Accessing whatever the "current data" is in the data store is easy:  Use the
`CurrentData()` function macro, passing in the ECL record structure.  Example:

	myCurrentData := DataMgmt.GenData.CurrentData('~my_data_store', MyRecLayout);

Assuming the previous example, myCurrentData would then reference the contents
of both logical subfiles
`my_data_store::file_w20170213-080526-1486994727334834-2` and
`my_data_store::file_w20170213-080526-1486994727334834-3`.

What really happens under the covers is a simple DATASET reference is created
using the record structure you provided and the path to the first generation
superfile.  Note that the DATASET is assumed to be a Thor flat file; if you
are storing a different type of file (e.g. delimited) that requires a different
DATASET definition, you can get the path to the first generation superfile and
build the DATASET yourself:

	myCurrentPath := DataMgmt.GenData.CurrentPath('~my_data_store');
	myData := DATASET(myCurrentPath, MyRecLayout, CSV(SEPARATOR('\t')));

The module also exports `GetData()` and `GetPath()` methods for accessing
arbitrary generations of data, if you need access to them (perhaps for
comparison purposes).

If you ever need to promote all of your current data to the next generation
but leave the first generation empty, you can use the exported
`PromoteGeneration()` for that purpose.

Sometimes you have to roll back your data store and restore a previous
generation of data.  The exported `RollbackGeneration()` function does just
that.  Internally, what happens is that anything in the first
generation superfile is deleted, then everything in the second
generation superfile is moved to the first, and so on.  After the operation is
complete the last generation is guaranteed to be empty.

The functions discussed above as well as some additional introspective and
management functions are described below.


<a name="gendata_api"></a>
## GenData API

<a name="gendata_init"></a>
`Init(STRING dataStorePath, UNSIGNED1 numGenerations = 3) := FUNCTION`

Function initializes the superfile structure needed to support generational data
management methods.

 * **Parameters:**
   * `dataStorePath` — The full path of the generational data store that will be created; REQUIRED
   * `numGenerations` — The number of generations to maintain; OPTIONAL, defaults to 3.
 * **Returns:** An action that performs the necessary steps to create the superfile structure.
 * **See also:** [DoesExist](#gendata_doesexist)
 * **Example:**

 		DataMgmt.GenData.Init('~my_data_store', 5);

___

<a name="gendata_writedata"></a>
`WriteData(STRING dataStorePath, VIRTUAL DATASET ds, STRING filenameSuffix = '') := FUNCTION`

Convenience method that creates a new flat file from the given data and inserts
it into the data store, making it the first generation of data. All existing
generations of data will be bumped to the next level. If data is stored in the
last generation then it will be deleted.

 * **Parameters:**
   * `dataStorePath` — The full path of the data store; must match the original argument to `Init()`; REQUIRED
   * `ds` — The dataset to insert into the data store; REQUIRED
   * `filenameSuffix` — String suffix to be added to the generated logical subfile name; use this if you intend to call this method multiple times in a single execution run; OPTIONAL, defaults to an empty string.
   * **Returns:** An action that creates a new flat subfile and insert it into the data store.  Existing generations of data are bumped to the next generation, and any data stored in the last generation will be deleted.
 * **See also:**
   * [WriteFile](#gendata_writefile)
   * [AppendFile](#gendata_appendfile)
   * [AppendData](#gendata_appenddata)
 * **Example:**

	    ds1 := DATASET(100, TRANSFORM({UNSIGNED4 n}, SELF.n := RANDOM()));
	    DataMgmt.GenData.WriteData('~my_data_store', ds1);

___

<a name="gendata_writefile"></a>
`WriteFile(STRING dataStorePath, STRING newFilePath) := FUNCTION`

Make the given logical file the first generation of data for the data store and
bump all existing generations of data to the next level. If data is stored in
the last generation then it will be deleted.

 * **Parameters:**
   * `dataStorePath` — The full path of the data store; must match the original argument to `Init()`; REQUIRED
   * `newFilePath` — The full path of the logical file to insert into the data store as the new current generation of data; REQUIRED
 * **Returns:** An action that inserts the given logical file into the data store.  Existing generations of data are bumped to the next generation, and any data stored in the last generation will be deleted.
 * **See also:**
   * [WriteData](#gendata_writedata)
   * [AppendFile](#gendata_appendfile)
   * [AppendData](#gendata_appenddata)
   * [NewSubfilePath](#gendata_newsubfilepath)
 * **Example:**

	    OUT_PATH1 := '~my_file1';
	    OUTPUT(ds1,,OUT_PATH1);
	    DataMgmt.GenData.WriteFile('~my_data_store', OUT_PATH1);

___

<a name="gendata_appenddata"></a>
`AppendData(STRING dataStorePath, VIRTUAL DATASET ds, STRING filenameSuffix = '') := FUNCTION`

Convenience method that creates a new flat file from the given data and adds it
to the first generation of data for the data store. No existing data is
replaced, nor is any data bumped to the next level. The record structure of this
data must be the same as other data in the data store.

 * **Parameters:**
   * `dataStorePath` — The full path of the data store; must match the original argument to `Init()`; REQUIRED
   * `ds` — The dataset to added into the data store; REQUIRED
   * `filenameSuffix` — String suffix to be added to the generated logical subfile name; use this if you intend to call this method multiple times in a single execution run; OPTIONAL, defaults to an empty string.
 * **Returns:** An action that creates a new flat subfile and adds it to the first generation of data in the data store.
 * **See also:**
   * [AppendFile](#gendata_appendfile)
   * [WriteFile](#gendata_writefile)
   * [WriteData](#gendata_writedata)
 * **Example:**

	    ds3 := DATASET(300, TRANSFORM({UNSIGNED4 n}, SELF.n := RANDOM()));
	    DataMgmt.GenData.AppendData('~my_data_store', ds3);

___

<a name="gendata_appendfile"></a>
`AppendFile(STRING dataStorePath, STRING newFilePath) := FUNCTION`

Adds the given logical file to the first generation of data for the data store.
This does not replace any existing data, nor bump any data generations to
another level. The record structure of this data must be the same as other data
in the data store.

 * **Parameters:**
   * `dataStorePath` — The full path of the data store; must match the original argument to `Init()`; REQUIRED
   * `newFilePath` — The full path of the logical file to append to the current generation of data; REQUIRED
 * **Returns:** An action that appends the given logical file to the current generation of data.
 * **See also:**
   * [AppendData](#gendata_appenddata)
   * [WriteFile](#gendata_writefile)
   * [WriteData](#gendata_writedata)
   * [NewSubfilePath](#gendata_newsubfilepath)
 * **Example:**

	    OUT_PATH2 := '~my_file2';
	    OUTPUT(ds3,,OUT_PATH2);
	    DataMgmt.GenData.AppendFile('~my_data_store', OUT_PATH2);

___

<a name="gendata_currentdata"></a>
`CurrentData(dataStorePath, recLayout) := FUNCTIONMACRO`

A convenience method (function macro) that returns the actual data stored in the
current generation. Note that an underlying assumption here is that the data is
stored as a flat logical file; it will not work with delimited, XML, or JSON
data structures, for instance (those types of structures are generally
supported, just not with this function macro). This is the same as calling
GetData() and asking for generation 1.

 * **Parameters:**
   * `dataStorePath` — The full path of the data store; must match the original argument to `Init()`; REQUIRED
   * `recLayout` — The ECL RECORD structure of the data; REQUIRED
 * **Returns:** A dataset containing the current generation of data.  If no data is found for any reason then an empty dataset with thegiven record structure is returned.
 * **See also:**
   * [GetData](#gendata_getdata)
   * [CurrentPath](#gendata_currentpath)
   * [GetPath](#gendata_getpath)
 * **Example:**
 
	    MyRecLayout := { STRING name, UNSIGNED1 age };
	    firstGenData := DataMgmt.GenData.CurrentData('~my_data_store', MyRecLayout);

___

<a name="gendata_getdata"></a>
`GetData(dataStorePath, recLayout, numGeneration = 1) := FUNCTIONMACRO`

A convenience method (function macro) that returns the actual data stored in a
given generation. Note that an underlying assumption here is that the data is
stored as a flat logical file; it will not work with delimited, XML, or JSON
data structures, for instance (those types of structures are generally
supported, just not with this function macro).

 * **Parameters:**
   * `dataStorePath` — The full path of the data store; must match the original argument to `Init()`; REQUIRED
   * `recLayout` — The ECL RECORD structure of the data; REQUIRED
   * `numGeneration` — An integer indicating which generation of data to retrieve; generations are numbered starting with 1 and increasing, with older generations having higher numbers; OPTIONAL, defaults to 1
 * **Returns:** A dataset containing the desired generation of data.  If no data is found for any reason then an empty dataset with the given record structure is returned.
 * **See also:**
   * [CurrentData](#gendata_currentdata)
   * [GetPath](#gendata_getpath)
   * [CurrentPath](#gendata_currentpath)
 * **Example:**

	    MyRecLayout := { STRING name, UNSIGNED1 age };
	    firstGenData := DataMgmt.GenData.GetData('~my_data_store', MyRecLayout, 1);

___

<a name="gendata_currentpath"></a>
`CurrentPath(STRING dataStorePath) := FUNCTION`

Returns the full path to the superfile containing the current generation of
data. The returned value would be suitable for use in a DATASET() declaration or
a function that requires a file path. This is the same as calling GetPath() and
asking for generation 1.

 * **Parameters:** `dataStorePath` — The full path of the data store; must match the original argument to `Init()`; REQUIRED
 * **Returns:** String containing the full path to the superfile containing the current generation of data.
 * **See also:**
   * [CurrentData](#gendata_currentdata)
   * [GetPath](#gendata_getpath)
   * [GetData](#gendata_getdata)
 * **Example:**

	    firstGenPath := DataMgmt.GenData.CurrentPath('~my_data_store');

___

<a name="gendata_getpath"></a>
`GetPath(STRING dataStorePath, UNSIGNED1 numGeneration = 1) := FUNCTION`

Returns the full path to the superfile containing the given generation of data.
The returned value would be suitable for use in a DATASET() declaration or a
function that requires a file path.

 * **Parameters:**
   * `dataStorePath` — The full path of the data store; must match the original argument to `Init()`; REQUIRED
   * `numGeneration` — An integer indicating which generation of data to build a path for; generations are numbered starting with 1 and increasing, with older generations having higher numbers; OPTIONAL, defaults to 1
 * **Returns:** String containing the full path to the superfile containing the desired generation of data.
 * **See also:**
   * [GetData](#gendata_getdata)
   * [CurrentPath](#gendata_currentpath)
   * [CurrentData](#gendata_currentdata)
 * **Example:**

	    secondGenPath := DataMgmt.GenData.GetPath('~my_data_store', 2);

___

<a name="gendata_doesexist"></a>
`DoesExist(STRING dataStorePath) := FUNCTION`

A simple test of whether the top-level superfile supporting this structure
actually exists or not.

 * **Parameters:** `dataStorePath` — The full path of the data store; must match the original argument to `Init()`; REQUIRED
 * **Returns:** A boolean indicating presence of the superfile.
 * **See also:** [Init](#gendata_init)
 * **Example:**

	    doesExist := DataMgmt.GenData.DoesExist('~my_data_store');

___

<a name="gendata_numgenerationsavailable"></a>
`NumGenerationsAvailable(STRING dataStorePath) := FUNCTION`

Returns the number of generations of data that could be tracked by the data
store referenced by the argument. The data store must already be initialized.

 * **Parameters:** `dataStorePath` — The full path of the data store; must match the original argument to `Init()`; REQUIRED
 * **Returns:** An integer representing the total number of data generations that could be tracked by the data store
 * **See also:**
   * [Init](#gendata_init)
   * [NumGenerationsInUse](#gendata_numgenerationsinuse)
 * **Example:**

	    generationCount := DataMgmt.GenData.NumGenerationsAvailable('~my_data_store');

___

<a name="gendata_numgenerationsinuse"></a>
`NumGenerationsInUse(STRING dataStorePath) := FUNCTION`

Returns the number of generations of data that are actually in use. The data
store must already be initialized.

 * **Parameters:** `dataStorePath` — The full path of the data store; must match the original argument to `Init()`; REQUIRED
 * **Returns:** An integer representing the total number of data generations that are actually being used (those that have data)
 * **See also:**
   * [Init](#gendata_init)
   * [NumGenerationsAvailable](#gendata_numgenerationsavailable)
 * **Example:**

	    generationsUsed := DataMgmt.GenData.NumGenerationsInUse('~my_data_store');

___

<a name="gendata_promotegeneration"></a>
`PromoteGeneration(STRING dataStorePath) := FUNCTION`

Method promotes all data associated with the first generation into the second,
promotes the second to the third, and so on.  The first generation of data will
be empty after this method completes.

Note that if you have multiple logical files associated with a generation, as
via AppendFile() or AppendData(), all of those files will be deleted or moved.

 * **Parameters:** `dataStorePath` — The full path of the data store; must match the original argument to `Init()`; REQUIRED
 * **Returns:** An action that performs the generational promotion.
 * **See also:**
   * [RollbackGeneration](#gendata_rollbackgeneration)
 * **Example:**

	    DataMgmt.GenData.PromoteGeneration('~my_data_store');

___

<a name="gendata_rollbackgeneration"></a>
`RollbackGeneration(STRING dataStorePath) := FUNCTION`

Method deletes all data associated with the current (first) generation of data,
moves the second generation of data into the first generation, then repeats the
process for any remaining generations. This functionality can be thought of
restoring an older version of the data to the current generation.

Note that if you have multiple logical files associated with a generation, as
via AppendFile() or AppendData(), all of those files will be deleted or moved.

 * **Parameters:** `dataStorePath` — The full path of the data store; must match the original argument to `Init()`; REQUIRED
 * **Returns:** An action that performs the generational rollback.
 * **See also:**
   * [PromoteGeneration](#gendata_promotegeneration)
 * **Example:**

	    DataMgmt.GenData.RollbackGeneration('~my_data_store');

___

<a name="gendata_clearall"></a>
`ClearAll(STRING dataStorePath) := FUNCTION`

Delete all data associated with the data store but leave the surrounding
superfile structure intact.

 * **Parameters:** `dataStorePath` — The full path of the data store; must match the original argument to `Init()`; REQUIRED
 * **Returns:** An action performing the delete operations.
 * **See also:**
   * [DeleteAll](#gendata_deleteall)
 * **Example:**

	    DataMgmt.GenData.ClearAll('~my_data_store');

___

<a name="gendata_deleteall"></a>
`DeleteAll(STRING dataStorePath) := FUNCTION`

Delete all data and structure associated with the data store.

 * **Parameters:** `dataStorePath` — The full path of the data store; must match the original argument to `Init()`; REQUIRED
 * **Returns:** An action performing the delete operations.
 * **See also:**
   * [ClearAll](#gendata_clearall)
 * **Example:**

	    DataMgmt.GenData.DeleteAll('~my_data_store');

___

<a name="gendata_newsubfilepath"></a>
`NewSubfilePath(STRING dataStorePath) := FUNCTION`

Construct a path for a new logical file for the data store. Note that the
returned value will have time-oriented components in it, therefore callers
should probably mark the returned value as INDEPENDENT if name will be used more
than once (say, creating the file via OUTPUT and then calling WriteFile() here
to store it) to avoid a recomputation of the name.

 * **Parameters:** `dataStorePath` — The full path of the data store; must match the original argument to `Init()`; REQUIRED
 * **Returns:** String representing a new logical subfile that may be added to the data store.
 * **See also:**
   * [WriteFile](#gendata_writefile)
   * [AppendFile](#gendata_appendfile)
 * **Example:**

	    myPath := DataMgmt.GenData.NewSubfilePath('~my_data_store');

<a name="gendata_examples"></a>
## GenData Example Code

Preamble code used throughout these examples (which should all be executed in
Thor):

	IMPORT DataMgmt;

	// Full path to the data store
	DATA_STORE := '~GenData::my_test';

	// Creating a unique name for new logical files
	subfilePrefix := DataMgmt.GenData.NewSubfilePath(DATA_STORE) : INDEPENDENT;
	MakeFilePath(UNSIGNED1 x) := subfilePrefix + '-' + (STRING)x;

	// Creating sample data
	SampleRec := {UNSIGNED4 n};
	MakeData(UNSIGNED1 x) := DISTRIBUTE(DATASET(100 * x, TRANSFORM(SampleRec, SELF.n := RANDOM() % (100 * x))));

Initializing the data store with the default number of generations:

	DataMgmt.GenData.Init(DATA_STORE);

Introspection:

	OUTPUT(DataMgmt.GenData.DoesExist(DATA_STORE), NAMED('DoesExist'));
	OUTPUT(DataMgmt.GenData.NumGenerationsAvailable(DATA_STORE), NAMED('NumGenerationsAvailable'));
	OUTPUT(DataMgmt.GenData.NumGenerationsInUse(DATA_STORE), NAMED('NumGenerationsInUse'));
	OUTPUT(DataMgmt.GenData.CurrentPath(DATA_STORE), NAMED('CurrentPath'));
	OUTPUT(DataMgmt.GenData.GetPath(DATA_STORE, 2), NAMED('PreviousPath'));

Given one dataset, write it to the data store and make it the current generation
of data, then show the result:

	ds1 := MakeData(1);
	DataMgmt.GenData.WriteData(DATA_STORE, ds1);
	OUTPUT(DataMgmt.GenData.CurrentData(DATA_STORE, SampleRec), NAMED('InitialWrite'), ALL);

Append two more datasets to the current generation and show the result:

	ds2 := MakeData(2);
	DataMgmt.GenData.AppendData(DATA_STORE, ds2, '-1');
	ds3 := MakeData(3);
	DataMgmt.GenData.AppendData(DATA_STORE, ds3, '-2');
	OUTPUT(DataMgmt.GenData.CurrentData(DATA_STORE, SampleRec), NAMED('AfterAppend'), ALL);

Create a logical file and write it to the data store, making it the current
generation of data, then show the result:

	outfilePath := MakeFilePath(4);
	ds4 := MakeData(4);
	OUTPUT(ds4,,outfilePath,OVERWRITE,COMPRESSED);
	DataMgmt.GenData.WriteFile(DATA_STORE, outfilePath);
	OUTPUT(DataMgmt.GenData.CurrentData(DATA_STORE, SampleRec), NAMED('WriteFile'), ALL);

Roll back that last write and show the result:

	DataMgmt.GenData.RollbackGeneration(DATA_STORE);
	OUTPUT(DataMgmt.GenData.CurrentData(DATA_STORE, SampleRec), NAMED('AfterRollback'), ALL);

Clear out all the data and show the result:

	DataMgmt.GenData.ClearAll(DATA_STORE);
	OUTPUT(DataMgmt.GenData.CurrentData(DATA_STORE, SampleRec), NAMED('AfterClear'), ALL);

Physically delete the data store and all of its data:

	DataMgmt.GenData.DeleteAll(DATA_STORE);

<a name="gendata_testing"></a>
## GenData Testing

Basic testing of the GenData module is embedded within the module itself.  To
execute the tests, run the following code in hThor (using Thor may cause
failures to be ignored in some versions of HPCC):

	IMPORT DataMgmt;
	
	DataMgmt.GenData.Tests.DoAll;

Failing tests may appear at runtime or as a message in the workunit.  If the
test appears to run successfully, check the workunit in ECL Watch to make sure
no error messages appear.  You may see a number of informational messages
relating to superfile transactions, which are normal.  Note that if a test
fails there is a possibility that superfiles and/or logical files have been left
on your cluster.  You can locate them for manual removal by searching for
`gendata::test::*` in ECL Watch.  If all tests pass then the created superfiles
and logical files will be removed automatically.


<a name="genindex_overview"></a>
## GenIndex: Overview

Generations of index files for ROXIE behave a lot like generations of data used
by Thor.  Both use containers ("superfiles" or "superkeys") to collect individual
files ("subfiles" or "subkeys").  Most of the concepts presented in GenData's
[overview section](#gendata_overview) are applicable to GenIndex as well.  The
biggest difference between this GenIndex module and the GenData module, other
than terminology, is the ability to update live ROXIE queries that reference the
superkeys without taking the queries offline.

Updating live ROXIE queries is performed by sending packagemaps to the ROXIE
server.  A packagemap is an XML document that provides a reference to the
contents of a superkey used in a query that overrides the original definition
within that query.  If you apply a packagemap at just the right time while
updating data you can seamlessly update a running query with no loss of data or
downtime.  Further information regarding packagemaps can be found in the ROXIE
manual, available in the download section of https://hpccsystems.com.

**IMPORTANT:**  Packagemaps work by providing new superkey-to-subkey mappings to
ROXIE via Dali.  A key point in this new mapping is that the superkey referenced
in the mapping does not have to physically exist.  Indeed, the only way to avoid
problems with file locks -- which prevent the live updating we are trying to
acheive -- is to use these "virtual superkeys" as the containers.  You can call
GenIndex's `VirtualSuperkeyPath()` function to obtain the (surprise!) virtual
superkey path for the current generation of data.  That virtual superkey path is
what you reference within the ROXIE code.  There is a physical superkey as well,
used to manage the generational data store and to provide Thor a handle to the
data if it needs it.  GenIndex takes care of mapping physical superkey content
changes to the virtual superkey, updating Dali and therefore ROXIE in the
process.

When GenIndex updates a virtual superkey in Dali, it **always** references the
current generation, even if there are no indexes there.  It will never update a
virtual superkey so that it references an older version of the data.

GenIndex supports the idea of a single ROXIE query referencing multiple index
stores, or multiple ROXIE queries referencing a single index store.  All you
need to do is call `InitROXIEPackageMap()` with the name of the query and the
complete list of index store paths it references as a SET OF STRING value. 
GenIndex will take care of creating a base packagemap (to map the query to a set
of data packages, one per index store) and then one data package for every index
store referenced.  If you have multiple queries, call `InitROXIEPackageMap()`
for each of them.

A note about naming your subkeys:  ROXIE queries lock their subkeys and
cache certain information about each of them, with the cached information found
by keying off of the subkey's full path.  Some versions of HPCC do not correctly
manage that cached information (specifically, cached information is not always
deleted in a timely manner).  If a query references a subkey with a certain
name, and then that subkey is deleted and recreated with the same name
(updating Dali at each step), you might then see an error like the
following the next time you execute the query:

	Different version of .::test_index_1 already loaded: sizes = 32768 32768 Date = 2017-02-14T17:08:22 2017-02-14T16:59:28

The easiest workaround for this is to avoid the problem:  Do not reuse subkey
paths.  GenIndex provides a `NewSubkeyPath()` function for generating unique
subkey paths and it can be used to avoid this problem.  There is an additional
step to take when using that function, however:  paths created by
`NewSubkeyPath()` have a time component in them so you have to take care to
'freeze' the return value.  The easiest way to do that is to mark the return
value as INDEPENDENT like this:

	subkeyPath := DataMgmt.GenIndex.NewSubkeyPath('~my_index_store') : INDEPENDENT;

That works fine if you're creating one subkey, but if you're creating more
than one subkey in a single job then you will need to make the path unique
**after** you generate it, like this:

	subkeyPrefix := DataMgmt.GenIndex.NewSubkeyPath('~my_index_store') : INDEPENDENT;
	subkeyPath1 := subkeyPrefix + '-1';
	subkeyPath2 := subkeyPrefix + '-2';

In that example we just appended a -1 or -2 to the generated path, but that is
enough to make it unique.

Now, on to some high-level examples.

The first step is creating an index store to work with.  Similar to the example
in GenData:

	DataMgmt.GenIndex.Init('~my_index_store', 5);

This sets up an index store that tracks up to five data generations.  If you
omitted the '5' argument then three generations will be set up for you.  The
name of the index store (~my\_index\_store) will be required for all subsequent
access.

The following physical superkey structure will be created (indented to show the
relationship):

	my_index_store
	    my_index_store::gen_1
	    my_index_store::gen_2
	    my_index_store::gen_3
	    my_index_store::gen_4
	    my_index_store::gen_5

Let's create a ROXIE query that finds the maximum value of a number stored in
the index store:

	IMPORT DataMgmt;

	#WORKUNIT('name', 'genindex_test');

	SampleRec := {UNSIGNED4 n};
	
	idx := INDEX
	    (
	        {SampleRec.n},
	        {},
	        DataMgmt.GenIndex.VirtualSuperkeyPath('~my_index_store'),
	        OPT
	    );

	OUTPUT(MAX(idx, n), NAMED('MaxValue'));
	OUTPUT(COUNT(idx), NAMED('RecCount'));

If you compile and publish that code you'll have a ROXIE query named
'genindex_test' that accepts no parameters and returns the maximum value stored
in the index store as well as the number of records found.  Within the INDEX
declaration, note that the path for the data points to the virtual superkey
representing the "current generation" of data.  This query works as-is, even
without data, because of the OPT keyword in the INDEX declaration.  You can use
the `VirtualSuperkeyPath()` function in this way even before actually creating
the index store.

We are still missing one piece, though:  The packagemap that provides a live,
updatable mapping between the virtual superkey and the actual subkeys.  Here is
how you define that:

	InitROXIEPackageMap
		(
			genindex_test,              // ROXIE query's name
			['~my_index_store'],        // Set of index stores used by the query
			'http://localhost:8010'     // URL to ESP service (ECL Watch)
		);

To add a subkey to the index store you first have to build it.  Here is some code
that gives us the means to create new indexes with identical record structures
but slightly different content:

	SampleRec := {UNSIGNED4 n};
	
	MakeData(UNSIGNED1 x) := DISTRIBUTE
	    (
	        DATASET
	            (
	                100 * x,
	                TRANSFORM
	                    (
	                        SampleRec,
	                        SELF.n := RANDOM() % (100 * x)
	                    )
	            )
	    );
	
	subkeyPrefix := DataMgmt.GenIndex.NewSubkeyPath('~my_index_store') : INDEPENDENT;
	MakeSubkeyPath(UNSIGNED1 x) := subkeyPrefix + '-' + (STRING)x;

Build one subkey using the code above:

	idxPath1 := MakeSubkeyPath(1);
	idx1 := INDEX(MakeData(1), {n}, {}, idxPath1);
	BUILD(idx1);

Use `WriteSubkey()` to make that subkey the current generation:

	DataMgmt.GenIndex.WriteSubkey
	    (
	        '~my_index_store',          // Path to the index store
	        idxPath1,                   // Path to new subkey
	        'http://localhost:8010'     // URL to ESP service (ECL Watch)
	    );

The index store now looks something like the following:

	my_index_store
	    my_index_store::gen_1
	        my_index_store::file_w20170213-080526-1486994727334834-1
	    my_index_store::gen_2
	    my_index_store::gen_3
	    my_index_store::gen_4
	    my_index_store::gen_5

If you rerun the ROXIE query now it should respond with '99' (or some other
number just below 100) and a record count of 100.  Let's update the query's
data, replacing what is in the current generation with 200 random numbers up to
a maximum value of 200:

	idxPath2 := MakeSubkeyPath(2);
	idx2 := INDEX(MakeData(2), {n}, {}, idxPath2);
	BUILD(idx2);
	DataMgmt.GenIndex.WriteSubkey
	    (
	        '~my_index_store',          // Path to the index store
	        idxPath2,                   // Path to new subkey
	        'http://localhost:8010'     // URL to ESP service (ECL Watch)
	    );

The index store now looks something like this:

	my_index_store
	    my_index_store::gen_1
	        my_index_store::file_w20170213-080526-1486994727334834-2
	    my_index_store::gen_2
	        my_index_store::file_w20170213-080526-1486994727334834-1
	    my_index_store::gen_3
	    my_index_store::gen_4
	    my_index_store::gen_5

Rerunning the ROXIE query should return a value that is almost 200 and a record
count of 200.

You can also append data to the current generation, just like with GenData,
using `AppendSubkey()`:

	idxPath3 := MakeSubkeyPath(3);
	idx3 := INDEX(MakeData(3), {n}, {}, idxPath3);
	BUILD(idx3);
	DataMgmt.GenIndex.AppendSubkey
	    (
	        '~my_index_store',          // Path to the index store
	        idxPath3,                   // Path to new subkey
	        'http://localhost:8010'     // URL to ESP service (ECL Watch)
	    );

The index store now looks something like:

	my_index_store
	    my_index_store::gen_1
	        my_index_store::file_w20170213-080526-1486994727334834-2
	        my_index_store::file_w20170213-080526-1486994727334834-3
	    my_index_store::gen_2
	        my_index_store::file_w20170213-080526-1486994727334834-1
	    my_index_store::gen_3
	    my_index_store::gen_4
	    my_index_store::gen_5

Running the ROXIE query should return a value that is almost 300 and a record
count of 500.

You can roll back data as well, just like with GenData:

	DataMgmt.GenIndex.RollbackGeneration
	    (
	        '~my_index_store',          // Path to the index store
	        'http://localhost:8010'     // URL to ESP service (ECL Watch)
	    );

Resulting in an index store containing:

	my_index_store
	    my_index_store::gen_1
	        my_index_store::file_w20170213-080526-1486994727334834-1
	    my_index_store::gen_2
	    my_index_store::gen_3
	    my_index_store::gen_4
	    my_index_store::gen_5

Running the query again will show the original result.

A good style of ECL coding is to define the index only once and reuse the
definition everywhere for both creating new subkeys and for referencing the
superkey containing those subkeys.  One way of doing that is:

	SampleRec := {UNSIGNED4 n};
	
	myIndexDef(STRING path = DataMgmt.GenIndex.VirtualSuperkeyPath('~my_index_store')) := INDEX
	    (
	        {SampleRec.n},
	        {},
	        path,
	        OPT
	    );
	
	// Create a subkey
	myData := MakeData(1)
	idxPath1 := MakeSubkeyPath(1);
	BUILD(myIndexDef(idxPath1), myData); // Explicitly provide the subkey path
	
	// Reference the superkey from ROXIE
	myROXIEIndex := myIndexDef(); // Default path is the virtual superkey
	
	// Reference the physical superkey from Thor
	myThorIndex := myIndexDef(DataMgmt.GenIndex.CurrentPath('~my_index_store'));

The functions discussed above as well as some additional introspective and
management functions are described below.

<a name="genindex_api"></a>
## GenIndex API


<a name="genindex_init"></a>
`Init(STRING indexStorePath, UNSIGNED1 numGenerations = 3) := FUNCTION`

Function initializes the physical superkey structure needed to support
generational index management methods.

 * **Parameters:**
   * `indexStorePath` — The full path of the generational index store that will be created; REQUIRED
   * `numGenerations` — The number of generations to maintain; OPTIONAL, defaults to 3.
 * **Returns:** An action that performs the necessary steps to create the physical superkey structure.
 * **See also:** [DoesExist](#genindex_doesexist)
 * **Example:**

 		DataMgmt.GenIndex.Init('~my_index_store', 5);

___

<a name="genindex_initroxiepackagemap"></a>
`InitROXIEPackageMap(STRING roxieQueryName, SET OF STRING indexStorePaths, STRING espURL = DEFAULT_ESP_URL, STRING roxieTargetName = 'roxie', STRING roxieProcessName = '*') := FUNCTION`

Function that creates, or recreates, all packagemaps needed that will allow a
ROXIE query to access the current generation of data in one or more index stores
via virtual superkeys.  This function is generally called after Init() is called
to create the superkey structure within the index store.  Most other GenIndex
functions rely on this function to have been called beforehand.

 * **Parameters:**
   * `roxieQueryName` — The name of the ROXIE query to update with the new index information; REQUIRED
   * `indexStorePaths` — A SET OF STRING value containing full paths for every index store that roxieQueryName will reference; REQUIRED
   * `espURL` — The URL to the ESP service on the cluster, which is the same URL as used for ECL Watch; set to an empty string to prevent ROXIE from being updated; OPTIONAL, defaults to either an empty string (on < 7.0 clusters) or to an ESP process found from Std.File.GetEspURL() (on >= 7.0 clusters)
   * `roxieTargetName` — The name of the ROXIE cluster to send the information to; OPTIONAL, defaults to 'roxie'
   * `roxieProcessName` — The name of the specific ROXIE process to target; OPTIONAL, defaults to '*' (all processes)
 * **Returns:** An ACTION that performs all packagemap initializations via web service calls.
 * **Example:**

 		DataMgmt.GenIndex.InitROXIEPackageMap
 			(
 				'my_roxie_query',
 				['~my_index_store'],
 				'http://127.0.0.1:8010'
 			);

___

<a name="genindex_writesubkey"></a>
`WriteSubkey(STRING indexStorePath, STRING newSubkey, STRING espURL = DEFAULT_ESP_URL, STRING roxieTargetName = 'roxie', STRING roxieProcessName = '*', UNSIGNED2 daliDelayMilliseconds = 300) := FUNCTION`

Make the given subkey the first generation of index for the index store,
bump all existing generations of subkeys to the next level, then update
the associated data package with the contents of the first generation.
Any subkeys stored in the last generation will be deleted.

This function assumes that a base packagemap for queries using this
index store has already been created, such as with InitROXIEPackageMap().

 * **Parameters:**
   * `indexStorePath` — The full path of the index store; must match the original argument to `Init()`; REQUIRED
   * `newSubkey` — The full path of the new subkey to insert into the index store as the new current generation of data; REQUIRED
   * `espURL` — The URL to the ESP service on the cluster, which is the same URL as used for ECL Watch; set to an empty string to prevent ROXIE from being updated; OPTIONAL, defaults to either an empty string (on < 7.0 clusters) or to an ESP process found from Std.File.GetEspURL() (on >= 7.0 clusters)
   * `roxieTargetName` — The name of the ROXIE cluster to send the information to; OPTIONAL, defaults to 'roxie'
   * `roxieProcessName` — The name of the specific ROXIE process to target; OPTIONAL, defaults to '*' (all processes)
   * `daliDelayMilliseconds` — Delay in milliseconds to pause execution; OPTIONAL, defaults to 300
 * **Returns:** An action that inserts the given subkey into the index store. Existing generations of subkeys are bumped to the next generation, and any subkey(s) stored in the last generation will be deleted.
 * **See also:**
   * [AppendSubkey](#genindex_appendsubkey)
   * [NewSubkeyPath](#genindex_newsubkeypath)

___

<a name="genindex_appendsubkey"></a>
`AppendSubkey(STRING indexStorePath, STRING newSubkey, STRING espURL = DEFAULT_ESP_URL, STRING roxieTargetName = 'roxie', STRING roxieProcessName = '*') := FUNCTION`

Adds the given subkey to the first generation of subkeys for the index store. 
This does not replace any existing subkey, nor bump any subkey generations to
another level.  The record structure of the new subkey must be the same as the
other subkeys in the index store.

This function assumes that a base packagemap for queries using this index store
has already been created, such as with InitROXIEPackageMap().

 * **Parameters:**
   * `indexStorePath` — The full path of the index store; must match the original argument to `Init()`; REQUIRED
   * `newSubkey` — The full path of the new subkey to append to the current generation of subkeys; REQUIRED
   * `espURL` — The URL to the ESP service on the cluster, which is the same URL as used for ECL Watch; set to an empty string to prevent ROXIE from being updated; OPTIONAL, defaults to either an empty string (on < 7.0 clusters) or to an ESP process found from Std.File.GetEspURL() (on >= 7.0 clusters)
   * `roxieTargetName` — The name of the ROXIE cluster to send the information to; OPTIONAL, defaults to 'roxie'
   * `roxieProcessName` — The name of the specific ROXIE process to target; OPTIONAL, defaults to '*' (all processes)
 * **Returns:** An action that appends the given subkey to the current generation of subkeys.
 * **See also:**
   * [WriteSubkey](#genindex_writesubkey)
   * [NewSubkeyPath](#genindex_newsubkeypath)

___

<a name="genindex_virtualsuperkeypath"></a>
`VirtualSuperkeyPath(STRING indexStorePath) := FUNCTION`

Return a virtual superkey path that references the current generation of data
managed by an index store.  ROXIE queries should use virtual superkeys when
accessing indexes in order to always read the most up to date data.

 * **Parameters:** `indexStorePath` — The full path of the index store; must match the original argument to `Init()`; REQUIRED
 * **Returns:** A STRING that can be used by ROXIE queries to access the current generation of data within an index store.
 * **See also:**
 	*	[CurrentPath](#genindex_currentpath)
 	*	[GetPath](#genindex_getpath)
 * **Example:**

	    idxPath := VirtualSuperkeyPath('~my_index_store');

___

<a name="genindex_currentpath"></a>
`CurrentPath(STRING indexStorePath) := FUNCTION`

Returns the full path to the physical superkey containing the current generation
of data.  The returned value would be suitable for use in a Thor function that
requires a file path, but it should not be used by ROXIE;
`VirtualSuperkeyPath()` should be called instead.

This function is the equivalent of calling `GetPath()` with `numGeneration = 1`.

 * **Parameters:** `indexStorePath` — The full path of the index store; must match the original argument to `Init()`; REQUIRED
 * **Returns:** String containing the full path to the superkey containing the current generation of data.
 * **See also:**
 	*	[VirtualSuperkeyPath](#genindex_virtualsuperkeypath)
 	*	[GetPath](#genindex_getpath)
 * **Example:**

	    firstGenPath := DataMgmt.GenIndex.CurrentPath('~my_index_store');

___

<a name="genindex_getpath"></a>
`GetPath(STRING indexStorePath, UNSIGNED1 numGeneration = 1) := FUNCTION`

Returns the full path to the superkey containing the given generation of data.
The returned value would be suitable for use in a Thor function that requires a
file path, but it should not be used by ROXIE.

 * **Parameters:**
   * `indexStorePath` — The full path of the index store; must match the original argument to `Init()`; REQUIRED
   * `numGeneration` — An integer indicating which generation of data to build a path for; generations are numbered starting with 1 and increasing, with older generations having higher numbers; OPTIONAL, defaults to 1
 * **Returns:** String containing the full path to the superkey containing the desired generation of data.
 * **See also:**
 	*	[VirtualSuperkeyPath](#genindex_virtualsuperkeypath)
 	*	[CurrentPath](#genindex_currentpath)
 * **Example:**

	    secondGenPath := DataMgmt.GenIndex.GetPath('~my_index_store', 2);

___

<a name="genindex_doesexist"></a>
`DoesExist(STRING indexStorePath) := FUNCTION`

A simple test of whether the top-level superkey supporting this structure
actually exists or not.

 * **Parameters:** `indexStorePath` — The full path of the index store; must match the original argument to `Init()`; REQUIRED
 * **Returns:** A boolean indicating presence of the superkey.
 * **See also:** [Init](#genindex_init)
 * **Example:**

	    doesExist := DataMgmt.GenIndex.DoesExist('~my_index_store');

___

<a name="genindex_numgenerationsavailable"></a>
`NumGenerationsAvailable(STRING indexStorePath) := FUNCTION`

Returns the number of generations of data that could be tracked by the index
store referenced by the argument. The index store must already be initialized
via `Init()`.

 * **Parameters:** `indexStorePath` — The full path of the index store; must match the original argument to `Init()`; REQUIRED
 * **Returns:** An integer representing the total number of data generations that could be tracked by the index store
 * **See also:**
   * [Init](#genindex_init)
   * [NumGenerationsInUse](#genindex_numgenerationsinuse)
 * **Example:**

	    generationCount := DataMgmt.GenIndex.NumGenerationsAvailable('~my_index_store');

___

<a name="genindex_numgenerationsinuse"></a>
`NumGenerationsInUse(STRING indexStorePath) := FUNCTION`

Returns the number of generations of data that are actually in use. The index
store must already be initialized via `Init()`.

 * **Parameters:** `indexStorePath` — The full path of the index store; must match the original argument to `Init()`; REQUIRED
 * **Returns:** An integer representing the total number of data generations that are actually being used (those that have data)
 * **See also:**
   * [Init](#genindex_init)
   * [NumGenerationsAvailable](#genindex_numgenerationsavailable)
 * **Example:**

	    generationsUsed := DataMgmt.GenIndex.NumGenerationsInUse('~my_index_store');

___

<a name="genindex_promotegeneration"></a>
`PromoteGeneration(STRING indexStorePath, STRING espURL = DEFAULT_ESP_URL, STRING roxieTargetName = 'roxie', STRING roxieProcessName = '*', UNSIGNED2 daliDelayMilliseconds = 300) := FUNCTION`

Method promotes all subkeys associated with the first generation into the
second, promotes the second to the third, and so on.  The first generation of
subkeys will be empty after this method completes.

Note that if you have multiple subkeys associated with a generation, as via
AppendSubkey(), all of those subkeys will be deleted or moved as appropriate.

This function assumes that a base packagemap for queries using this index store
has already been created, such as with InitROXIEPackageMap().

 * **Parameters:**
   * `indexStorePath` — The full path of the index store; must match the original argument to `Init()`; REQUIRED
   * `espURL` — The URL to the ESP service on the cluster, which is the same URL as used for ECL Watch; set to an empty string to prevent ROXIE from being updated; OPTIONAL, defaults to either an empty string (on < 7.0 clusters) or to an ESP process found from Std.File.GetEspURL() (on >= 7.0 clusters)
   * `roxieTargetName` — The name of the ROXIE cluster to send the information to; OPTIONAL, defaults to 'roxie'
   * `roxieProcessName` — The name of the specific ROXIE process to target; OPTIONAL, defaults to '*' (all processes)
   * `daliDelayMilliseconds` — Delay in milliseconds to pause execution; OPTIONAL, defaults to 300
 * **Returns:** An action that performs the generational promotion.
 * **See also:**
   * [RollbackGeneration](#genindex_rollbackgeneration)

___

<a name="genindex_rollbackgeneration"></a>
`RollbackGeneration(STRING indexStorePath, STRING espURL = DEFAULT_ESP_URL, STRING roxieTargetName = 'roxie', STRING roxieProcessName = '*', UNSIGNED2 daliDelayMilliseconds = 300) := FUNCTION`

Method deletes all subkeys associated with the current (first) generation, moves
the second generation of subkeys into the first generation, then repeats the
process for any remaining generations.  This functionality can be thought of as
restoring older version of subkeys to the current generation.

Note that if you have multiple subkeys associated with a generation, as via
AppendSubkey(), all of those subkeys will be deleted or moved as appropriate.

This function assumes that a base packagemap for queries using this index store
has already been created, such as with InitROXIEPackageMap().

 * **Parameters:**
   * `indexStorePath` — The full path of the index store; must match the original argument to `Init()`; REQUIRED
   * `espURL` — The URL to the ESP service on the cluster, which is the same URL as used for ECL Watch; set to an empty string to prevent ROXIE from being updated; OPTIONAL, defaults to either an empty string (on < 7.0 clusters) or to an ESP process found from Std.File.GetEspURL() (on >= 7.0 clusters)
   * `roxieTargetName` — The name of the ROXIE cluster to send the information to; OPTIONAL, defaults to 'roxie'
   * `roxieProcessName` — The name of the specific ROXIE process to target; OPTIONAL, defaults to '*' (all processes)
   * `daliDelayMilliseconds` — Delay in milliseconds to pause execution; OPTIONAL, defaults to 300
 * **Returns:** An action that performs the generational rollback.
 * **See also:**
   * [PromoteGeneration](#genindex_promotegeneration)

___

<a name="genindex_clearall"></a>
`ClearAll(STRING indexStorePath, STRING espURL = DEFAULT_ESP_URL, STRING roxieTargetName = 'roxie', STRING roxieProcessName = '*', UNSIGNED2 daliDelayMilliseconds = 300) := FUNCTION`

Delete all subkeys associated with the index store, from all generations, but
leave the surrounding superkey structure intact.

This function assumes that a base packagemap for queries using this index store
has already been created, such as with InitROXIEPackageMap().

 * **Parameters:**
   * `indexStorePath` — The full path of the index store; must match the original argument to `Init()`; REQUIRED
   * `espURL` — The URL to the ESP service on the cluster, which is the same URL as used for ECL Watch; set to an empty string to prevent ROXIE from being updated; OPTIONAL, defaults to either an empty string (on < 7.0 clusters) or to an ESP process found from Std.File.GetEspURL() (on >= 7.0 clusters)
   * `roxieTargetName` — The name of the ROXIE cluster to send the information to; OPTIONAL, defaults to 'roxie'
   * `roxieProcessName` — The name of the specific ROXIE process to target; OPTIONAL, defaults to '*' (all processes)
   * `daliDelayMilliseconds` — Delay in milliseconds to pause execution; OPTIONAL, defaults to 300
 * **Returns:** An action performing the delete operations.
 * **See also:**
   * [DeleteAll](#genindex_deleteall)
 
___
<a name="genindex_deleteall"></a>
`DeleteAll(STRING indexStorePath, STRING espURL = DEFAULT_ESP_URL, STRING roxieTargetName = 'roxie', STRING roxieProcessName = '*') := FUNCTION`

Delete generational index store and all referenced subkeys.  This function also
updates the associated packagemap so that it references no subkeys.

This function assumes that a base packagemap for queries using this index store
has already been created, such as with InitROXIEPackageMap().

 * **Parameters:**
   * `indexStorePath` — The full path of the index store; must match the original argument to `Init()`; REQUIRED
   * `espURL` — The URL to the ESP service on the cluster, which is the same URL as used for ECL Watch; set to an empty string to prevent ROXIE from being updated; OPTIONAL, defaults to either an empty string (on < 7.0 clusters) or to an ESP process found from Std.File.GetEspURL() (on >= 7.0 clusters)
   * `roxieTargetName` — The name of the ROXIE cluster to send the information to; OPTIONAL, defaults to 'roxie'
   * `roxieProcessName` — The name of the specific ROXIE process to target; OPTIONAL, defaults to '*' (all processes)
 * **Returns:** An action performing the delete operations.
 * **See also:**
   * [ClearAll](#genindex_clearall)

___

<a name="genindex_newsubkeypath"></a>
`NewSubkeyPath(STRING indexStorePath) := FUNCTION`

Construct a path for a new subkey for the index store.  Note that the returned
value will have time-oriented components in it, therefore callers should
probably mark the returned value as INDEPENDENT if name will be used more than
once (say, creating the index via BUILD and then calling WriteSubkey() to store
it) to avoid a recomputation of the name.

Because some versions of HPCC have had difficulty dealing with same-named index
files being repeatedly inserted and removed from a ROXIE query, it is highly
recommended that you name index files uniquely by using this function or one
like it.

 * **Parameters:** `indexStorePath` — The full path of the index store; must match the original argument to `Init()`; REQUIRED
 * **Returns:** String representing the path to a new subkey that may be added to the index store.
 * **See also:**
   * [WriteSubkey](#genindex_writesubkey)
   * [AppendSubkey](#genindex_appendsubkey)
 * **Example:**

	    myPath := DataMgmt.GenIndex.NewSubkeyPath('~my_index_store');

___

<a name="genindex_updateROXIE"></a>
`UpdateROXIE(STRING indexStorePath, STRING espURL = DEFAULT_ESP_URL, STRING roxieTargetName = 'roxie', STRING roxieProcessName = '*') := FUNCTION`

Function updates the data package associated with the current generation of the
given index store.  The current generation's file contents are used to create
the data package.

This function assumes that a base packagemap for queries using this index store
has already been created, such as with InitROXIEPackageMap().

 * **Parameters:**
   * `indexStorePath` — The full path of the generational index store; REQUIRED
   * `espURL` — The URL to the ESP service on the cluster, which is the same URL as used for ECL Watch; set to an empty string to prevent ROXIE from being updated; OPTIONAL, defaults to either an empty string (on < 7.0 clusters) or to an ESP process found from Std.File.GetEspURL() (on >= 7.0 clusters)
   * `ROXIETargetName` — The name of the ROXIE cluster to send the information to; OPTIONAL, defaults to 'roxie'
   * `roxieProcessName` — The name of the specific ROXIE process to target; OPTIONAL, defaults to '*' (all processes)
 * **Returns:** An action that updates the given ROXIE query with the contents of the current generation of indexes.

___

<a name="genindex_waitfordaliupdate"></a>
`WaitForDaliUpdate(UNSIGNED2 daliDelayMilliseconds = 300) := FUNCTION`

Exported helper function that can be used to delay processing while Dali is
updating its internal database after an update.  This is particularly important
when dealing with locked files.  The default value of 300 (milliseconds) is appropriate for fast, local clusters.  A longer delay may be required when executing in cloud environments or in clusters with slow or congested networks.  Note that several other GenIndex functions accept an optional `daliDelayMilliseconds` argument and they may need to be adjusted as well.

 * **Parameters:**
   * `daliDelayMilliseconds` — Delay in milliseconds to pause execution; OPTIONAL, defaults to 300

 * **Returns:** An action that simply sleeps for a short while.

___

<a name="genindex_removeroxiepackagemap"></a>
`RemoveROXIEPackageMap(STRING roxieQueryName, SET OF STRING indexStorePaths, STRING espURL = DEFAULT_ESP_URL, STRING roxieTargetName = 'roxie') := FUNCTION`

Function that removes all packagemaps used for the given ROXIE query and all
referenced index stores.

 * **Parameters:**
   * `roxieQueryName` — The name of the ROXIE query; REQUIRED
   * `indexStorePaths` — A SET OF STRING value containing full paths for every index store that roxieQueryName will reference; REQUIRED
   * `espURL` — The URL to the ESP service on the cluster, which is the same URL as used for ECL Watch; set to an empty string to prevent ROXIE from being updated; OPTIONAL, defaults to either an empty string (on < 7.0 clusters) or to an ESP process found from Std.File.GetEspURL() (on >= 7.0 clusters)
   * `roxieTargetName` — The name of the ROXIE cluster to send the information to; OPTIONAL, defaults to 'roxie'
 * **Returns:** An ACTION that performs all packagemap removals via web service calls.

___

<a name="genindex_deletemanagedroxiepackagemap"></a>
`DeleteManagedROXIEPackageMap(STRING espURL = DEFAULT_ESP_URL, STRING roxieTargetName = 'roxie', STRING roxieProcessName = '*') := FUNCTION`

Function removes all packagemaps maintained by this bundle.

 * **Parameters:**
   * `espURL` — The URL to the ESP service on the cluster, which is the same URL as used for ECL Watch; set to an empty string to prevent ROXIE from being updated; OPTIONAL, defaults to either an empty string (on < 7.0 clusters) or to an ESP process found from Std.File.GetEspURL() (on >= 7.0 clusters)
   * `roxieTargetName` — The name of the ROXIE cluster to send the information to; OPTIONAL, defaults to 'roxie'
   * `roxieProcessName` — The name of the specific ROXIE process to target; OPTIONAL, defaults to '*' (all processes)
 * **Returns:** An ACTION that performs removes the packagemap maintained by this bundle via web service calls.

<a name="genindex_examples"></a>
## GenIndex Example Code

ROXIE query used for these examples.  Compile and publish this code with ROXIE
as a target:

	IMPORT DataMgmt;

	#WORKUNIT('name', 'genindex_test');

	SampleRec := {UNSIGNED4 n};
	idx1 := INDEX
		(
			{SampleRec.n},
			{},
			DataMgmt.GenIndex.VirtualSuperkeyPath('~GenIndex::my_test'),
			OPT
		);

	OUTPUT(MAX(idx1, n), NAMED('IDX1MaxValue'));
	OUTPUT(COUNT(idx1), NAMED('IDX1RecCount'));

Preamble code -- code that should appear before all other code in the following
examples -- used to build the data for these examples, all of which should be
executed under Thor.  Note that after each step you can run the ROXIE query to
view the results, which should reflect the contents of the current generation of
indexes.

	INDEX_STORE := '~genindex::my_test';
	ROXIE_QUERY := 'genindex_test';
	ESP_URL := 'http://localhost:8010'; // Put the URL to your ECL Watch here

	subkeyPrefix := DataMgmt.GenIndex.NewSubkeyPath(INDEX_STORE) : INDEPENDENT;
	MakeSubkeyPath(UNSIGNED1 x) := subkeyPrefix + '-' + (STRING)x;

	SampleRec := {UNSIGNED4 n};
	MakeData(UNSIGNED1 x) := DISTRIBUTE
		(
			DATASET
				(
					100 * x,
					TRANSFORM
						(
							SampleRec,
							SELF.n := RANDOM() % (100 * x)
						)
				)
		);

Initializing the index store with the default number of generations:

	DataMgmt.GenIndex.Init(INDEX_STORE);

Creating the base packagemap:

	DataMgmt.GenIndex.InitROXIEPackageMap
		(
			ROXIE_QUERY,
			[INDEX_STORE],
			ESP_URL
		);

Introspection:

	OUTPUT(DataMgmt.GenIndex.DoesExist(INDEX_STORE), NAMED('DoesExist'));
	OUTPUT(DataMgmt.GenIndex.NumGenerationsAvailable(INDEX_STORE), NAMED('NumGenerationsAvailable'));
	OUTPUT(DataMgmt.GenIndex.NumGenerationsInUse(INDEX_STORE), NAMED('NumGenerationsInUse'));
	OUTPUT(DataMgmt.GenIndex.CurrentPath(INDEX_STORE), NAMED('CurrentPath'));
	OUTPUT(DataMgmt.GenIndex.GetPath(INDEX_STORE, 2), NAMED('PreviousPath'));

Create a new index file and make it the current generation of indexes:

	ds1 := MakeData(1);
	path1 := MakeSubkeyPath(1);
	idx1 := INDEX(ds1, {n}, {}, path1);
	BUILD(idx1);
	DataMgmt.GenIndex.WriteSubkey(INDEX_STORE, path1, ROXIE_QUERY, ESP_URL);

Create another index file and append it to the current generation:

	ds2 := MakeData(2);
	path2 := MakeSubkeyPath(2);
	idx2 := INDEX(ds2, {n}, {}, path2);
	BUILD(idx2);
	DataMgmt.GenIndex.AppendSubkey(INDEX_STORE, path2, ROXIE_QUERY, ESP_URL);

Create a third index file, making it the current generation and bumping the
others to a previous generation:

	ds3 := MakeData(3);
	path3 := MakeSubkeyPath(3);
	idx3 := INDEX(ds3, {n}, {}, path3);
	BUILD(idx3);
	DataMgmt.GenIndex.WriteSubkey(INDEX_STORE, path3, ROXIE_QUERY, ESP_URL);

Roll back that last `WriteSubkey()`:

	DataMgmt.GenIndex.RollbackGeneration(INDEX_STORE, ROXIE_QUERY, ESP_URL);

Clear out all the data:

	DataMgmt.GenIndex.ClearAll(INDEX_STORE, ROXIE_QUERY, ESP_URL);

Physically delete the index store and all of its indexes:

	DataMgmt.GenIndex.DeleteAll(INDEX_STORE, ROXIE_QUERY, ESP_URL);

<a name="genindex_testing"></a>
## GenIndex Testing

Basic testing of the GenIndex module is embedded within the module itself.  To
execute the tests, run the following code in hThor (using Thor may cause
failures to be ignored in some versions of HPCC):

	IMPORT DataMgmt;
	
	DataMgmt.GenIndex.Tests().DoAll;
	
	// Supply an empty string as an argument to prevent package map creation
	// on ROXIE
	// DataMgmt.GenIndex.Tests('').DoAll;
	
If the full URL to an ECL Watch is used instead of an empty string, packagemap
manipulations will be tested along with superkey manipulations.  If an empty
string is used, as in this example, only superkey management will be tested.

Failing tests may appear at runtime or as a message in the workunit.  If the
test appears to run successfully, check the workunit in ECL Watch to make sure
no error messages appear.  You may see a number of informational messages
relating to superfile transactions, which are normal.  Note that if a test
fails there is a possibility that superfiles and/or logical files have been left
on your cluster.  You can locate them for manual removal by searching for
`genindex::test::*` in ECL Watch.  If all tests pass then the created superkeys
and subkeys will be removed automatically.
