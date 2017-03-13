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

Index files that are used by Roxie are managed by the GenIndex module in this
bundle.  While Thor also uses index files, Roxie's use of indexes complicate
data management somewhat.  The GenIndex module exposes easy-to-use (or perhaps
easier-to-use) methods for updating the indexes referenced by Roxie without
taking any Roxie query offline.

## Requirements

The code included in this bundle is written entirely in ECL.  No extra plugins
or third party tools are required, though functions from the Std library
(included with the platform) are used.  HPCC 6.0.0 or later is required.

###License and Version
This software is licensed under the Apache v2 license.  A link to the license,
as well as the current version of this software, can be found in the
[Bundle.ecl](https://github.com/hpcc-systems/DataPatterns/blob/master/Bundle.ecl)
file.

## Installation

To install a bundle to your development machine, use the ecl command line tool:

	ecl bundle install https://github.com/dcamper/DataMgmt.git

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
      * Writing data
         * [WriteIndexFile](#genindex_writeindexfile)
         * [AppendIndexFile](#genindex_appendindexfile)
      * Reading data
         * [CurrentPath](#genindex_currentpath)
         * [GetPath](#genindex_getpath)
      * Introspection
         * [DoesExist](#genindex_doesexist)
         * [NumGenerationsAvailable](#genindex_numgenerationsavailable)
         * [NumGenerationsInUse](#genindex_numgenerationsInUse)
      * Managing data
         * [RollbackGeneration](#genindex_rollbackgeneration)
         * [ClearAll](#genindex_clearall)
         * [DeleteAll](#genindex_deleteall)
      * Other
         * [NewSubkeyPath](#genindex_newsubkeypath)
         * [UpdateRoxie](#genindex_updateroxie)
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
`WriteData(dataStorePath, ds, filenameSuffix = '\'\'') := FUNCTIONMACRO`

Convenience method (function macro) that creates a new flat file from the
given data and inserts it into the data store, making it the first generation of
data. All existing generations of data will be bumped to the next level. If data
is stored in the last generation then it will be deleted.

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
`AppendData(dataStorePath, ds, filenameSuffix = '\'\'') := FUNCTIONMACRO`

Convenience method (function macro) that creates a new flat file from the
given data and adds it to the first generation of data for the data store. No
existing data is replaced, nor is any data bumped to the next level. The record
structure of this data must be the same as other data in the data store.

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
execute the tests, run the following code in Thor:

	IMPORT DataMgmt;
	
	DataMgmt.GenData.Tests.DoAll;

If any test fails you will see an error message at runtime.  Note that if a test
fails there is a possibility that superfiles and/or logical files have been left
on your cluster.  You can locate them for manual removal by searching for
`gendata::test::*` in ECL Watch.  If all tests pass then the created superfiles
and logical files will be removed automatically.


<a name="genindex_overview"></a>
## GenIndex: Overview

Generations of index files for Roxie behave a lot like generations of data used
by Thor.  Both use containers ("superfiles" or "superkeys") to wrap individual
files ("datasets" or "indexes").  Most of the concepts presented in GenData's
[overview section](#gendata_overview) are applicable to GenIndex as well.  The
biggest difference between this GenIndex module and the GenData module, other
than terminology, is the ability to update live Roxie queries that reference the
indexes without taking the queries offline.

Updating live Roxie queries is performed by sending packagemaps to the Roxie
server.  A packagemap is an XML document that provides a reference to the
contents of a superkey used in a query that overrides the original definition
within that query.  If you apply a packagemap at just the right time while
updating data you can seamlessly update a running query with no loss of data or
downtime.  Further information regarding packagemaps can be found in the Roxie
manual, available in the download section of https://hpccsystems.com.

When GenIndex updates a Roxie query it **always** references the current
generation, even if there are no indexes there.  It will never update a query so
that it references an older version of the data.

A note about naming your index files:  Roxie queries lock their index files and
cache certain information about each of them, with the cached information found
by keying off of the index's full path.  Some versions of HPCC do not correctly
manage that cached information (specifically, cached information is not always
deleted in a timely manner).  If a query references an index file with a certain
name, and then that index file is deleted and recreated with the same name
(updating the Roxie query at each step), you might then see an error like the
following the next time you execute the query:

	Error:    System error: -1: Graph graph1[1], detach: Cannot remove file testing::index_cache::idx as owned by SuperFile(s): testing::index_cache (0, 0), -1, 

The easiest workaround for this is to avoid the problem:  Do not reuse index
file paths.  GenIndex provides a `NewSubkeyPath()` function for generating
unique index paths and it can be used to avoid this problem.  There is an
additional step to take when using that function, however:  paths created by
`NewSubkeyPath()` have a time component in them so you have to take care to
'freeze' the return value.  The easiest way to do that is to mark the return
value as INDEPENDENT like this:

	subkeyPath := DataMgmt.GenIndex.NewSubkeyPath('~my_index_store') : INDEPENDENT;

That works fine if you're creating one index file, but if you're creating more
than one index in a single job then you will need to make the path unique
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

The following superkey structure will be created (indented to show the
relationship):

	my_index_store
		my_index_store::gen_1
		my_index_store::gen_2
		my_index_store::gen_3
		my_index_store::gen_4
		my_index_store::gen_5

Let's create a Roxie query that finds the maximum value of a number stored in
the index store:

	IMPORT DataMgmt;

	#WORKUNIT('name', 'genindex_test');

	SampleRec := {UNSIGNED4 n};
	
	idx := INDEX
		(
			{SampleRec.n},
			{},
			DataMgmt.GenIndex.CurrentPath('~my_index_store'),
			OPT
		);

	OUTPUT(MAX(idx, n), NAMED('MaxValue'));
	OUTPUT(COUNT(idx), NAMED('RecCount'));

If you compile and publish that code you'll have a Roxie query named
'genindex_test' that accepts no parameters and returns the maximum value stored
in the index store as well as the number of records found.  Within the INDEX
declaration, note that the path for the data points to the superkey representing
the "current generation" of data.  This query works as-is, even without data,
because of the OPT keyword in the INDEX declaration.  You can use the
`CurrentPath()` function in this way even before actually creating the index
store.

To add an index to the index store you first have to build it.  Here is some code
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
	MakeIndexPath(UNSIGNED1 x) := subkeyPrefix + '-' + (STRING)x;

Build one index file using the code above:

	idxPath1 := MakeIndexPath(1);
	idx1 := INDEX(MakeData(1), {n}, {}, idxPath1);
	BUILD(idx1);

Use `WriteIndexFile()` to make that index the current generation:

	DataMgmt.GenIndex.WriteIndexFile
		(
			'~my_index_store',			// Path to the index store
			idxPath1,					// Path to new index file
			'genindex_test',			// Name of Roxie query to update
			'http://localhost:8010'		// URL to ESP service (ECL Watch)
		);

The index store now looks something like the following:

	my_index_store
		my_index_store::gen_1
		    my_index_store::file_w20170213-080526-1486994727334834-1
		my_index_store::gen_2
		my_index_store::gen_3
		my_index_store::gen_4
		my_index_store::gen_5

If you rerun the Roxie query now it should respond with '99' (or some other
number just below 100) and a record count of 100.  Let's update the query's
data, replacing what is in the current generation with 200 random numbers up to
a maximum value of 200:

	idxPath2 := MakeIndexPath(2);
	idx2 := INDEX(MakeData(2), {n}, {}, idxPath2);
	BUILD(idx2);
	DataMgmt.GenIndex.WriteIndexFile
		(
			'~my_index_store',			// Path to the index store
			idxPath2,					// Path to new index file
			'genindex_test',			// Name of Roxie query to update
			'http://localhost:8010'		// URL to ESP service (ECL Watch)
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

Rerunning the Roxie query should return a value that is almost 200 and a record
count of 200.

You can also append data to the current generation, just like with GenData,
using `AppendIndexFile()`:

	idxPath3 := MakeIndexPath(3);
	idx3 := INDEX(MakeData(3), {n}, {}, idxPath3);
	BUILD(idx3);
	DataMgmt.GenIndex.AppendIndexFile
		(
			'~my_index_store',			// Path to the index store
			idxPath3,					// Path to new index file
			'genindex_test',			// Name of Roxie query to update
			'http://localhost:8010'		// URL to ESP service (ECL Watch)
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

Running the Roxie query should return a value that is almost 300 and a record
count of 500.

You can roll back data as well, just like with GenData:

	DataMgmt.GenIndex.RollbackGeneration
		(
			'~my_index_store',			// Path to the index store
			'genindex_test',			// Name of Roxie query to update
			'http://localhost:8010'		// URL to ESP service (ECL Watch)
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

The functions discussed above as well as some additional introspective and
management functions are described below.

<a name="genindex_api"></a>
## GenIndex API


<a name="genindex_init"></a>
`Init(STRING indexStorePath, UNSIGNED1 numGenerations = 3) := FUNCTION`

Function initializes the superkey structure needed to support generational index
management methods.

 * **Parameters:**
   * `indexStorePath` — The full path of the generational index store that will be created; REQUIRED
   * `numGenerations` — The number of generations to maintain; OPTIONAL, defaults to 3.
 * **Returns:** An action that performs the necessary steps to create the superkey structure.
 * **See also:** [DoesExist](#genindex_doesexist)
 * **Example:**

 		DataMgmt.GenIndex.Init('~my_index_store', 5);

___

<a name="genindex_writeindexfile"></a>
`WriteIndexFile(STRING indexStorePath, STRING newIndexPath, STRING roxieQueryName, STRING espURL, STRING roxieTargetName = 'roxie', STRING roxieProcessName = '*') := FUNCTION`

Make the given index the first generation of index for the index store, bump all
existing generations of data to the next level, then update the given Roxie
query with references to the new index. Any indexes stored in the last
generation will be deleted.

 * **Parameters:**
   * `indexStorePath` — The full path of the index store; must match the original argument to `Init()`; REQUIRED
   * `newIndexPath` — The full path of the new index to insert into the index store as the new current generation of data; REQUIRED
   * `roxieQueryName` — The name of the Roxie query to update with the new index information; REQUIRED
   * `espURL` — The URL to the ESP service on the cluster, which is the same URL as used for ECL Watch; REQUIRED
   * `roxieTargetName` — The name of the Roxie cluster to send the information to; OPTIONAL, defaults to 'roxie'
   * `roxieProcessName` — The name of the specific Roxie process to target; OPTIONAL, defaults to '*' (all processes)
 * **Returns:** An action that inserts the given index into the index store. Existing generations of indexes are bumped to the next generation, and any index stored in the last generation will be deleted.
 * **See also:**
   * [AppendIndexFile](#genindex_appendindexfile)
   * [NewSubkeyPath](#genindex_newsubkeypath)

___

<a name="genindex_appendindexfile"></a>
`AppendIndexFile(STRING indexStorePath, STRING newIndexPath, STRING roxieQueryName, STRING espURL, STRING roxieTargetName = 'roxie', STRING roxieProcessName = '*') := FUNCTION`

Adds the given index to the first generation of indexes for the index store.
This does not replace any existing index, nor bump any index generations to
another level. The record structure of this index must be the same as other
indexes in the index store.

 * **Parameters:**
   * `indexStorePath` — The full path of the index store; must match the original argument to `Init()`; REQUIRED
   * `newIndexPath` — The full path of the new index to append to the current generation of indexes; REQUIRED
   * `roxieQueryName` — The name of the Roxie query to update with the new index information; REQUIRED
   * `espURL` — The URL to the ESP service on the cluster, which is the same URL as used for ECL Watch; REQUIRED
   * `roxieTargetName` — The name of the Roxie cluster to send the information to; OPTIONAL, defaults to 'roxie'
   * `roxieProcessName` — The name of the specific Roxie process to target; OPTIONAL, defaults to '*' (all processes)
 * **Returns:** An action that appends the given index to the current generation of indexes.
 * **See also:**
   * [WriteIndexFile](#genindex_writeindexfile)
   * [NewSubkeyPath](#genindex_newsubkeypath)

___

<a name="genindex_currentpath"></a>
`CurrentPath(STRING indexStorePath) := FUNCTION`

Returns the full path to the superkey containing the current generation of data.
The returned value would be suitable for use in an INDEX() declaration or a
function that requires a file path. This is the same as calling GetPath() and
asking for generation 1.

 * **Parameters:** `indexStorePath` — The full path of the index store; must match the original argument to `Init()`; REQUIRED
 * **Returns:** String containing the full path to the superkey containing the current generation of data.
 * **See also:** [GetPath](#genindex_getpath)
 * **Example:**

		firstGenPath := DataMgmt.GenIndex.CurrentPath('~my_index_store');

___

<a name="genindex_getpath"></a>
`GetPath(STRING indexStorePath, UNSIGNED1 numGeneration = 1) := FUNCTION`

Returns the full path to the superkey containing the given generation of data.
The returned value would be suitable for use in an INDEX() declaration or a
function that requires a file path.

 * **Parameters:**
   * `indexStorePath` — The full path of the index store; must match the original argument to `Init()`; REQUIRED
   * `numGeneration` — An integer indicating which generation of data to build a path for; generations are numbered starting with 1 and increasing, with older generations having higher numbers; OPTIONAL, defaults to 1
 * **Returns:** String containing the full path to the superkey containing the desired generation of data.
 * **See also:** [CurrentPath](#genindex_currentpath)
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
store referenced by the argument. The index store must already be initialized.

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
store must already be initialized.

 * **Parameters:** `indexStorePath` — The full path of the index store; must match the original argument to `Init()`; REQUIRED
 * **Returns:** An integer representing the total number of data generations that are actually being used (those that have data)
 * **See also:**
   * [Init](#genindex_init)
   * [NumGenerationsAvailable](#genindex_numgenerationsavailable)
 * **Example:**

		generationsUsed := DataMgmt.GenIndex.NumGenerationsInUse('~my_index_store');

___

<a name="genindex_rollbackgeneration"></a>
`RollbackGeneration(STRING indexStorePath, STRING roxieQueryName, STRING espURL, STRING roxieTargetName = 'roxie', STRING roxieProcessName = '*') := FUNCTION`

Method deletes all indexes associated with the current (first) generation of
data, moves the second generation of indexes into the first generation, then
repeats the process for any remaining generations. This functionality can be
thought of as restoring an older version of the index to the current generation.

Note that if you have multiple indexes associated with a generation, as via
AppendIndexFile(), all of those indexes will be deleted or moved.

 * **Parameters:**
   * `indexStorePath` — The full path of the index store; must match the original argument to `Init()`; REQUIRED
   * `roxieQueryName` — The name of the Roxie query to update with the new index information; REQUIRED
   * `espURL` — The URL to the ESP service on the cluster, which is the same URL as used for ECL Watch; REQUIRED
   * `roxieTargetName` — The name of the Roxie cluster to send the information to; OPTIONAL, defaults to 'roxie'
   * `roxieProcessName` — The name of the specific Roxie process to target; OPTIONAL, defaults to '*' (all processes)
 * **Returns:** An action that performs the generational rollback.

___

<a name="genindex_clearall"></a>
`ClearAll(STRING indexStorePath, STRING roxieQueryName, STRING espURL, STRING roxieTargetName = 'roxie', STRING roxieProcessName = '*') := FUNCTION`

Delete all indexes associated with the index store but leave the surrounding
superkey structure intact.

 * **Parameters:**
   * `indexStorePath` — The full path of the index store; must match the original argument to `Init()`; REQUIRED
   * `roxieQueryName` — The name of the Roxie query to update with the new index information; REQUIRED
   * `espURL` — The URL to the ESP service on the cluster, which is the same URL as used for ECL Watch; REQUIRED
   * `roxieTargetName` — The name of the Roxie cluster to send the information to; OPTIONAL, defaults to 'roxie'
   * `roxieProcessName` — The name of the specific Roxie process to target; OPTIONAL, defaults to '*' (all processes)
 * **Returns:** An action performing the delete operations.
 * **See also:**
   * [DeleteAll](#genindex_deleteall)
 
___
<a name="genindex_deleteall"></a>
`DeleteAll(STRING indexStorePath, STRING roxieQueryName, STRING espURL, STRING roxieTargetName = 'roxie', STRING roxieProcessName = '*') := FUNCTION`

Delete all indexes and structure associated with the index store.

 * **Parameters:**
   * `indexStorePath` — The full path of the index store; must match the original argument to `Init()`; REQUIRED
   * `roxieQueryName` — The name of the Roxie query to update with the new index information; REQUIRED
   * `espURL` — The URL to the ESP service on the cluster, which is the same URL as used for ECL Watch; REQUIRED
   * `roxieTargetName` — The name of the Roxie cluster to send the information to; OPTIONAL, defaults to 'roxie'
   * `roxieProcessName` — The name of the specific Roxie process to target; OPTIONAL, defaults to '*' (all processes)
 * **Returns:** An action performing the delete operations.
 * **See also:**
   * [ClearAll](#genindex_clearall)

___

<a name="genindex_newsubkeypath"></a>
`NewSubkeyPath(STRING indexStorePath) := FUNCTION`

Construct a path for a new index for the index store.  Note that the returned
value will have time-oriented components in it, therefore callers should
probably mark the returned value as INDEPENDENT if name will be used more than
once (say, creating the index via BUILD and then calling WriteIndexFile() here
to store it) to avoid a recomputation of the name.

Because some versions of HPCC have had difficulty dealing with same-named index
files being repeatedly inserted and removed from a Roxie query, it is highly
recommended that you name index files uniquely by using this function or one
like it.

 * **Parameters:** `indexStorePath` — The full path of the index store; must match the original argument to `Init()`; REQUIRED
 * **Returns:** String representing a new index that may be added to the index store.
 * **See also:**
   * [WriteIndexFile](#genindex_writeindexfile)
   * [AppendIndexFile](#genindex_appendindexfile)
 * **Example:**

		myPath := DataMgmt.GenIndex.NewSubkeyPath('~my_index_store');

___

<a name="genindex_updateroxie"></a>
`UpdateRoxie(STRING indexStorePath, STRING roxieQueryName, STRING espURL, STRING roxieTargetName = 'roxie', STRING roxieProcessName = '*') := FUNCTION`

Function simply updates the given Roxie query with the indexes that reside in
the current generation of the index store. This may useful for rare cases where
the Roxie query is redeployed and the references to the current index store are
lost, or if the index store contents are manipulated outside of these functions
and you tell the Roxie query about the changes, or if you have several Roxie
queries that reference an index store and you want to update them independently.

 * **Parameters:**
   * `indexStorePath` — The full path of the generational index store; REQUIRED
   * `roxieQueryName` — The name of the Roxie query to update with the new index information; REQUIRED
   * `espURL` — The URL to the ESP service on the cluster, which is the same URL as used for ECL Watch; REQUIRED
   * `roxieTargetName` — The name of the Roxie cluster to send the information to; OPTIONAL, defaults to 'roxie'
   * `roxieProcessName` — The name of the specific Roxie process to target; OPTIONAL, defaults to '*' (all processes)
 * **Returns:** An action that updates the given Roxie query with the contents of the current generation of indexes.

<a name="genindex_examples"></a>
## GenIndex Example Code

Roxie query used for these examples.  Compile and publish this code with Roxie
as a target:

	IMPORT DataMgmt;

	#WORKUNIT('name', 'genindex_test');

	SampleRec := {UNSIGNED4 n};
	idx1 := INDEX({SampleRec.n}, {}, DataMgmt.GenIndex.CurrentPath('~GenIndex::my_test'), OPT);

	OUTPUT(MAX(idx1, n), NAMED('IDX1MaxValue'));
	OUTPUT(COUNT(idx1), NAMED('IDX1RecCount'));

Preamble code used to build the data for these examples (which should all be
executed under Thor).  Note that after each step you can run the Roxie query to
view the results, which should reflect the contents of the current generation of
indexes.

	INDEX_STORE := '~GenIndex::my_test';
	ROXIE_QUERY := 'genindex_test';
	ESP_URL := 'http://localhost:8010'; // Put the URL to your ECL Watch here

	subkeyPrefix := DataMgmt.GenIndex.NewSubkeyPath(INDEX_STORE) : INDEPENDENT;
	MakeIndexPath(UNSIGNED1 x) := subkeyPrefix + '-' + (STRING)x;

	SampleRec := {UNSIGNED4 n};
	MakeData(UNSIGNED1 x) := DISTRIBUTE(DATASET(100 * x, TRANSFORM(SampleRec, SELF.n := RANDOM() % (100 * x))));

Initializing the index store with the default number of generations:

	DataMgmt.GenIndex.Init(DATA_STORE);

Introspection:

	OUTPUT(DataMgmt.GenIndex.DoesExist(DATA_STORE), NAMED('DoesExist'));
	OUTPUT(DataMgmt.GenIndex.NumGenerationsAvailable(DATA_STORE), NAMED('NumGenerationsAvailable'));
	OUTPUT(DataMgmt.GenIndex.NumGenerationsInUse(DATA_STORE), NAMED('NumGenerationsInUse'));
	OUTPUT(DataMgmt.GenIndex.CurrentPath(DATA_STORE), NAMED('CurrentPath'));
	OUTPUT(DataMgmt.GenIndex.GetPath(DATA_STORE, 2), NAMED('PreviousPath'));

Create a new index file and make it the current generation of indexes:

	ds1 := MakeData(1);
	path1 := MakeIndexPath(1);
	idx1 := INDEX(ds1, {n}, {}, path1);
	BUILD(idx1);
	DataMgmt.GenIndex.WriteIndexFile(INDEX_STORE, path1, ROXIE_QUERY, ESP_URL);

Create another index file and append it to the current generation:

	ds2 := MakeData(2);
	path2 := MakeIndexPath(2);
	idx2 := INDEX(ds2, {n}, {}, path2);
	BUILD(idx2);
	DataMgmt.GenIndex.AppendIndexFile(INDEX_STORE, path2, ROXIE_QUERY, ESP_URL);

Create a third index file, making it the current generation and bumping the
others to a previous generation:

	ds3 := MakeData(3);
	path3 := MakeIndexPath(3);
	idx3 := INDEX(ds3, {n}, {}, path3);
	BUILD(idx3);
	DataMgmt.GenIndex.WriteIndexFile(INDEX_STORE, path3, ROXIE_QUERY, ESP_URL);

Roll back that last `WriteIndexFile()`:

	DataMgmt.GenIndex.RollbackGeneration(INDEX_STORE, ROXIE_QUERY, ESP_URL);

Clear out all the data:

	DataMgmt.GenIndex.ClearAll(INDEX_STORE, ROXIE_QUERY, ESP_URL);

Physically delete the index store and all of its indexes:

	DataMgmt.GenIndex.DeleteAll(INDEX_STORE, ROXIE_QUERY, ESP_URL);

<a name="genindex_testing"></a>
## GenIndex Testing

Basic testing of the GenIndex module is embedded within the module itself.  To
execute the tests, run the following code in Thor:

	IMPORT DataMgmt;
	
	DataMgmt.GenIndex.Tests.DoAll;

These are basic tests only and really only ensure that the superkey and index
file management is working correctly.  No Roxie query is deployed or tested.

If any test fails you will see an error message at runtime.  Note that if a test
fails there is a possibility that superkeys and/or index files have been left on
your cluster.  You can locate them for manual removal by searching for
`genindex::test::*` in ECL Watch.  If all tests pass then the created superkeys
and indexes will be removed automatically.
