# q client for DB Service

The DB Service q client provides a thin wrapper over the DB Service APIs, making it easier to connect to a running service and perform client operations from q.
Use this client to create a session, run queries, manage tables, and interact with DB Service from q.

Examples of using the client are included below. For a comprehensive list of parameters and their meanings, refer to the [KDB-X DB Service API spec](https://code.kx.com/kdb-x/services/db-service/api/dbservice.html).

### Requirements

- kdb-x
- A running DB Service instance

### kdb-x installation

`dbservice_client.q` is intended to be installed under the kdb-x module path.
While it can be loaded from any directory, we recommend installing it to `$HOME/.kx/mod/kx`.

```bash
cp dbservice_client.q ~/.kx/mod/kx/
```

Add the `QPATH` export to your `.bashrc` (or equivalent) to persist across sessions.

### Load the client
Start q and load the client:
```q
/ Load module
dbs:use`kx.dbservice_client

/ Default endpoint: http://localhost:8080
session:dbs.createSession[]

/ Explicit endpoint
session1:dbs.createSession([endpoint:"localhost:8080"])

/ Multiple DB Service instances from one q process
session2:dbs.createSession([endpoint:"localhost:8081"])
```

### Examples

This section shows common DB Service q client workflows, including table management, data import, querying, configuration export, and deleting tables.

#### Managing Tables
Use these calls to define and inspect table schemas in DB Service.

```q
// List tables (empty to begin with)
session.listTables[]

// Define columns
fxquoteCols:(([name:`trddate; colType:`date]);([name:`ts; colType:`timestamp]);([name:`sym; colType:`symbol; attrMem:`grouped; attrDisk:`parted; attrOrd:`parted]);([name:`bid; colType:`float]);([name:`ask; colType:`float]))

// Create partitioned table ('fxquote')
session.createTable([table:`fxquote; tableType:`partitioned; prtnCol:`ts; sortColsDisk:enlist`sym; sortColsOrd:enlist`sym; columns:fxquoteCols])

// List tables ('fxquote' table returned)
session.listTables[]

// Describe the 'fxquote' table
session.describeTable["fxquote"]
```

#### Importing Data
DB Service supports both `file-based` and `in-memory` ingest.
Any file you want to import must first be copied into the DB Service `imports` staging directory, for example: `~/.kx/db-service/data/imports/`

###### Import CSV
```q
// Import a CSV file into the existing 'fxquote' table
job:session.importFiles([table:"fxquote";path:"fxquote.csv.gz"])

// Check the status of the above import job
session.getImport[job`name]

// Import a parquet file into the existing 'fxquote' table
session.importFiles([table:"fxquote";path:"fxquote.parquet"])

// Import a CSV file and create the 'instruments' table automatically if it does not exist
job:session.importFiles([table:"instruments";path:"instruments.csv";createTable:1b])
```


###### Import Kdb database
```q
// Import the 'fxquote' HDB table from the root kdb+ database directory 'fxquote-hdb'
session.importKDB([table:"fxquote";path:"fxquote-hdb"])
```

###### Import JSON
Import rows directly from q without file staging.
```q
// Objects payload imported to 'instruments' table
data:([]instrumentid:77 78;sym:("USDBRL";"USDKRW");category:("EM";"EM");decimals:4 2;pipdecimals:4 2);
session.importData([table:"instruments";data])

// Rows payload imported to the 'fxquote' table
data:(("2026-01-21";"2026-01-21T10:00:00.000";"EURUSD";901.2;901.3);("2026-01-21";"2026-01-21T10:00:00.000";"EURUSD";901.2;901.3));
session.importData([table:"fxquote";data;columnNames:`trddate`ts`sym`bid`ask])

// Note: for rows payload, columnNames are required.
```

#### Querying Tables
Run structured, SQL, or q queries against DB Service.

```q
// Structured query
session.querySimple([table:"fxquote";startTS:2026.03.02D;endTS:2026.03.03D;sortCols:enlist"ts";limit:5])

// SQL query
session.querySQL([query:"SELECT * FROM instruments WHERE category LIKE 'EM'"])

// qSQL query
session.queryQ([query:"select o:first bid,h:max bid,l:min bid,c:last bid by trddate,sym from fxquote"])
```

#### Exporting Configuration
Export the active assembly configuration as YAML, for single-node DB Service deployments.

```q
// Return the assembly YAML as a string
assemblyYaml:session.exportAssembly[]

// Save the assembly YAML to a file
session.exportAssembly["assembly.yaml"]
```

#### Deleting Tables

```q
// List tables (expected: 'fxquote' and 'instruments')
session.listTables[]
```

```q
// Drop the 'fxquote' table
session.dropTable["fxquote"]
```

```q
// Drop the 'instruments' table
session.dropTable["instruments"]
```

```q
// List tables (expected: no tables)
session.listTables[]
```
