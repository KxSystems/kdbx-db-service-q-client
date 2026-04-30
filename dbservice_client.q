/ dbservice_client.q
/ DB Service qClient

.kurl:use`kx.kurl

// Create a table using the provided request body.
createTable:{[endpoint;body]
	path:"/api/v0/tables/",symToString[body`table];
	.j.k last sendRequest[endpoint;`POST;path;body _ `table]
	}

// List all tables.
listTables:{[endpoint;]
	.j.k last sendRequest[endpoint;`GET;"/api/v0/tables";()]
	}

// Get details for one table.
describeTable:{[endpoint;table]
	path:"/api/v0/tables/",symToString table;
	.j.k last sendRequest[endpoint;`GET;path;()]
	}

// Drop one table.
dropTable:{[endpoint;table]
	path:"/api/v0/tables/",symToString table;
	.j.k last sendRequest[endpoint;`DELETE;path;()]
	}

// Start a file-based import job.
importFiles:{[endpoint;body]
	.j.k last sendRequest[endpoint;`POST;"/api/v0/imports/files";body]
	}

/ Start a data import job from inline payload data.
importData:{[endpoint;body]
	.j.k last sendRequest[endpoint;`POST;"/api/v0/imports/data";body]
	}

/ Start a kdb directory import job.
importKDB:{[endpoint;body]
	.j.k last sendRequest[endpoint;`POST;"/api/v0/imports/kdb";body]
	}

/ Get current status for an import job.
getImport:{[endpoint;jobId]
	path:"/api/v0/imports/",symToString jobId;
	.j.k last sendRequest[endpoint;`GET;path;()]
	}

// Cancel an import job.
cancelImport:{[endpoint;jobId]
	path:"/api/v0/imports/",symToString jobId;
	.j.k last sendRequest[endpoint;`DELETE;path;()]
	}

// Run structured/simple query endpoint.
querySimple:{[endpoint;body]
	query[endpoint;"/api/v0/query/simple";body]
	}

// Run SQL query endpoint.
querySQL:{[endpoint;body]
	if[10h~type body;body:([query:body])];
	query[endpoint;"/api/v0/query/sql";body]}

// Run q query endpoint.
queryQ:{[endpoint;body]
	if[10h~type body;body:([query:body])];
	query[endpoint;"/api/v0/query/q";body]}

// Create a projected client session bound to one endpoint.
createSession:{[endpoint]
	api:`createTable`listTables`describeTable`dropTable`importFiles`importData`importKDB`getImport`cancelImport`querySimple`querySQL`queryQ;
	api!.z.m[api]@\:normalizeRestEndpoint endpoint
	}

// Send a REST request with JSON headers/body when payload is present.
sendRequest:{[endpoint;verb;path;payload]
	url:endpoint,path;
	opts:([headers:enlist["Accept"]!enlist"application/json";max_retry_attempts:0]);
	if[not ()~payload;opts[`headers]:(`Accept;`$"Content-Type")!("application/json";"application/json");opts[`body]:.j.j payload];
	.kurl.sync(url;verb;opts)
	}

// Execute a query request and decode octet-stream response into q types.
query:{[endpoint;path;body]
	unwrap:$[`unwrap in key body;body`unwrap;1b];
	url:endpoint,path;
	headers:(`Accept;`$"Content-Type")!("application/octet-stream";"application/json");
	opts:([headers;body:.j.j body _ `unwrap;max_retry_attempts:0]);
	resp:.kurl.sync(url;`POST;opts);
	raw:last resp;
	resp[1]:-9!$[4h=type raw;raw;"x"$raw];
	$[(string first resp) like "20*";$[unwrap;last resp[1];resp[1]];last resp]
	}

// Ensure the REST endpoint has a default value and http/https prefix.
normalizeRestEndpoint:{[opts]
	endpoint:$[99h=type opts;$[`endpoint in key opts;opts`endpoint;::];opts];
	ep:$[any endpoint~/:(();::;"");"http://localhost:8080";endpoint];
	if[not any ep like/: ("http://*";"https://*");ep:"http://",ep];
	ep
	}

// Convert a symbol atom to a string
symToString:{[x]$[10h~typ:type x;x;-11h~typ;string x]}

export:([createSession])