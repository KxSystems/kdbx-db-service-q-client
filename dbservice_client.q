([sync]):use`kx.kurl

PREFIX:"/api/v0/"

// Table containing API definitions, with the following columns:
// - name      {symbol}              API name.
// - method    {symbol}              HTTP method, one of 'GET', 'POST' or 'DELETE'.
// - path      {string}              Base API path (follows host/port and PREFIX, may be followed by the output of 'suffixFn').
// - reqArgs   {symbol|symbol[]|()}  Names of the required (positional) arguments, used to construct the full argument dictionary.
// - suffixFn  {fn|boolean}          Function applied to the first required argument returning the suffix string appended to 'path' (no suffix if 0b).
// - bodyFn    {fn|boolean}          Function converting the full argument dictionary to JSON request body (no request body if 0b).
// - isQuery   {boolean}             Indicates if the request is a table data query.
// - raw       {boolean}             Indicates the response body is returned as-is (e.g. YAML) rather than parsed as JSON, using an 'application/yaml' Accept header.
//                                   If the API argument is a string, the raw response is also saved to that local file path.
API:flip
	(`name;           `method; `path;             `reqArgs;      `suffixFn; `bodyFn;    `isQuery; `raw)!
	flip( /---------------------------------------------------------------------------------------------
	(`createTable;    `POST;   "tables";          `table;        ::;        _[;`table]; 0b;       0b);
	(`listTables;     `GET;    "tables";          ();            0b;        0b;         0b;       0b);
	(`describeTable;  `GET;    "tables";          `table;        ::;        0b;         0b;       0b);
	(`dropTable;      `DELETE; "tables";          `table;        ::;        0b;         0b;       0b);
	(`importFiles;    `POST;   "imports/files";   `table`path;   0b;        ::;         0b;       0b);
	(`importData;     `POST;   "imports/data";    `table`data;   0b;        ::;         0b;       0b);
	(`importKDB;      `POST;   "imports/kdb";     `path;         0b;        ::;         0b;       0b);
	(`getImport;      `GET;    "imports";         `jobId;        ::;        0b;         0b;       0b);
	(`cancelImport;   `DELETE; "imports";         `jobId;        ::;        0b;         0b;       0b);
	(`deleteRows;     `POST;   "deletes";         `table`filter; 0b;        ::;         0b;       0b);
	(`getDelete;      `GET;    "deletes";         `jobId;        ::;        0b;         0b;       0b);
	(`cancelDelete;   `DELETE; "deletes";         `jobId;        ::;        0b;         0b;       0b);
	(`querySimple;    `POST;   "query/simple";    `table;        0b;        ::;         1b;       0b);
	(`querySQL;       `POST;   "query/sql";       `query;        0b;        ::;         1b;       0b);
	(`queryQ;         `POST;   "query/q";         `query;        0b;        ::;         1b;       0b);
	(`queryPreview;   `POST;   "query/preview";   `table;        0b;        ::;         1b;       0b);
	(`exportAssembly; `GET;    "config/assembly"; ();            0b;        0b;         0b;       1b))

// @desc Request handler. The first two arguments are filled by 'createSession' when it generates each API.
// The last argument is provided by the user (as separate function parameters) at request API call time.
// @param endpoint {string}  Endpoint host/port.
// @param api      {dict}    A row from the API definition table.
// @param params   {list}    List of parameters provided by the user.
// @return         {any}     Formatted API response (see 'formatResp' for details).
request:{[endpoint;api;params]
	([method;path;reqArgs;suffixFn;bodyFn;isQuery;raw]):api;
	arg:getArgDict[reqArgs,:();params];
	if[isQuery;
		unwrap:$[`unwrap in key arg;arg`unwrap;1b]; / Determine if the header should be dropped (default) from the successful response
		arg _:`unwrap]; / Drop the key that is only relevant for the client
	str:{$[10h=t:type y;y;-11h=t;string y;typeErr[x;t;10 -11h]]}; / Returns 'y' converted to a string or throws a type error message with description 'x'
	suffix:$[suffixFn~0b;"";"/",str["first parameter (",string[reqArgs 0],")"]suffixFn params 0]; / Generate the path suffix if applicable
	if[`assembly in key arg; / Move assembly specification to the suffix
		suffix,:"?assembly=",str["'assembly'"]arg`assembly;
		arg _:`assembly];
	url:endpoint,PREFIX,path,suffix; / Construct the full request URL
	headers:([Accept:"application/",$[isQuery;"octet-stream";raw;"yaml";"json"]]); / Binary payload for queries, YAML for raw responses, JSON otherwise
	if[b:not 0b~bodyFn;headers[`$"Content-Type"]:"application/json"]; / Request payload (if applicable) is JSON
	opts:([headers;max_retry_attempts:0]),$[b;([body:.j.j bodyFn arg]);()];
	(status;body):@[sync;(url;method;opts);{'"Unable to send request (",string[x]," ",y,"): ",z}[method;url]]; / Send request
	res:formatResp[status;body;isQuery;raw;unwrap];
	if[raw and(string status)like"20*";
		if[`path in key arg;hsym[`$str["'path'"]arg`path]1:res]]; / Optionally save a successful raw response to a local file
	res
	}

// @desc Constructs the full argument dictionary from the list of required and optional parameters.
// @param reqArgs {symbol[]} Names of the required (positional) arguments.
// @param params  {list}     Parameters provided by the user, either conforming to 'reqArgs' or with one additional
//                           last element, which is expected to be a dictionary containing the optional parameters.
// @return        {dict}     Dictionary containing required and optional parameters.
getArgDict:{[reqArgs;params]
	chk:{$[11h=t:type key x;x;typeErr["optional parameter key";t;11h]]}; / Returns the optional parameter dict after checking that it is keyed by symbols
	(p;r):count each(params;reqArgs);
	$[not p in r+0 1;'"Unexpected number of parameters (",string[p],"), must be ",string[r],$[r;" (",(", "sv string reqArgs),")";""]," + 1 optional";
		p=r;reqArgs!params; / No optional parameter dict passed
		0=count o:last params;reqArgs!1_params; / No values passed in the optional parameter (accept untyped empty list or dict)
		r=0;$[99h=type o;chk o;([])]; / If there are no required parameters, ignore the passed parameter unless it is a dict
		99h<>t:type o;typeErr["optional parameter";t;99h]; / Optional parameters must be passed in a dict
		(reqArgs!-1_params),chk o] / Combine required and optional parameters
	}

// @desc Throws an error for an unexpected object type.
// @param n {string}        Name of the checked object.
// @param t {short}         Type of the checked object.
// @param x {short|short[]} Expected types.
typeErr:{[n;t;x]'"Unexpected ",n," type (",string[t],"h), must be ",$[1=count x;"";"one of "],.Q.s1 x}

// @desc Formats an API response.
// @param status   {int}      Response status code.
// @param body     {string}   Response body.
// @param isQuery  {boolean}  Indicates if the request is a table data query.
// @param raw      {boolean}  Indicates the response body is returned as-is (e.g. YAML) on success, rather than parsed as JSON.
// @param unwrap   {boolean}  Indicates if the header should be stripped from the query response (unused if 'isQuery'=0b).
// @return         {any}      Formatted API response. In the case of an error, this is a dictionary with entries
//                            'status' (int), 'error' (string) and  'details' (string, optional).
//                            For a successfully processed table query ('isQuery'=1b), the result object
//                            (typically a table) is returned either directly or, if 'unwrap'=0b was included
//                            in the request, as the second element of a pair, where the first element
//                            is the query response header dictionary.
formatResp:{[status;body;isQuery;raw;unwrap]
	success:(s:string status)like"20*";
	if[not 10h=t:type body;'"Unexpected response payload type(",string[t],"h), status=",s," body=",.Q.s1 body];
	$[isQuery;
		$[success;
			[ / Query response has success status (may still have an error-type query response payload)
				res:@[-9!"x"$;body;{'"Unable to deserialize binary query response (",y,"): ",x}body];
				$[99h=type r:formatQueryResp[status;res];r;unwrap;r 1;r]]; / Return the error dict or success response (header optionally stripped)
			[ / Query response has error status
				$[first d:@[{(0b;-9!"x"$x)};body;1b];([status;error:body]); / Return raw response string as error if it could not be deserialized
					$[first r:@[{(0b;formatQueryResp . x)};(status;d 1);1b];([status;error:.Q.s1 d 1]); / Return stringified deserialized payload as error if formatting it failed
					r 1]]]]; / Return a properly formatted error response
		$[success;
			[ / Regular request response has success status
				$[raw;body;@[.j.k;body;{'"Unable to parse JSON response (",y,"): ",x}body]]]; / Return the body as-is for a raw response, otherwise parsed JSON
			[ / Regular request response has error status
				$[first d:@[{(0b;.j.k x)};body;1b];([status;error:body]); / Return raw response string as error if it could not be parsed
					99h<>t:type r:d 1;([status;error:$[t=10h;;.Q.s1]r]); / Return stringified parsed payload as error if it has unexpected type
					formatErrResp[status;r]]]]] / Return a properly formatted error response
	}

// @desc Formats a table query response.
// @param status            {int}              Response status code.
// @param (header;payload)  {(dict;any)}       Response header and payload from the query.
// @return                  {(dict;any)|dict}  Unchanged response header and payload (success case) or an error dictionary.
formatQueryResp:{[status;(header;payload)]
	if[0h=header`rc;:(header;payload)];
	error:$[`ai in key header;header`ai;"DB-Service query failed"];
	d:`corr`logCorr`version`rcvTS`http`api`agg`refVintage`rc`ac`ai`limitApplied; / Fields included in 'details' entry
	([status;error]),$[count details:(d inter key header)#header;([details]);()]
	}

// @desc Formats an error response for a regular (non-table-query) request.
// @param status  {int}   Response status code.
// @param body    {dict}  Response body.
// @return        {dict}  Error dictionary with entries 'status' (int), 'error' (string) and 'details' (string, optional).
formatErrResp:{[status;body]
	error:$[ / Select the appropriate error information entry
		any p:(f:`error`text`message)in k:key body;body f p?1b;
		`errors in k;"; "sv body`errors;
		.Q.s1 body];
	details:$[count d:k except`error`text`message`errors`code`name; / Optional error details
		([details:$[d~enlist`details;body`details;d#body]]);()];
	([status;error]),details
	}

// @public
// @desc Creates a client session by generating the request handlers for each defined API and a given endpoint.
// @param x  {any}   Endpoint host/port info. Can be provided directly as a string, or as a dictionary with a string 'endpoint' entry.
//                   If empty or null, the default http://localhost:8080 is used.
// @return   {dict}  Request handlers (projections of 'request' composed with 'enlist' for variadic syntax).
createSession:{
	e:$[10h=t:type x;x;99h<>t;::;`endpoint in key x;x`endpoint;::]; / Extract endpoint from the argument
	endpoint:$[e~(::);"http://localhost:8080"; / Use default endpoint if not provided
		any e like/:("http://*";"https://*");e;"http://",e]; / Ensure prefix
	API[`name]!{('[@[x y;;{'x}];enlist])}[request endpoint]each API / Re-throw errors to avoid debug session
	}

export:([createSession])