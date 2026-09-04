([sync]):use`kx.kurl

PREFIX:"/api/v0/"

// @desc Extracts a string/symbol value from a provided dictionary key. If the input object
// is not a dictionary, it is expected to be a string or a symbol and is returned as is.
// @param k {symbol}             Lookup key.
// @param x {dict|string|symbol} Input object.
// @return  {string|symbol}      Extracted value.
getKey:{[k;x]
	$[99h<>type x;x;
		not k in key x;'"Missing '",string[k],"'";
		(t:type v:x k)in 10 -11h;v;
		'typeErr["'",string[k],"'";t;10 -11h]]
	}

// Table containing API definitions, with the following columns:
// - name      {symbol}            API name.
// - method    {symbol}            HTTP method, one of 'GET', 'POST' or 'DELETE'.
// - path      {string}            Base API path (follows host/port and PREFIX, may be followed by the output of 'suffixFn').
// - argTypes  {short|short[]|()}  Accepted API argument types (if empty, the type check is skipped).
// - suffixFn  {fn|boolean}        Function applied to the API argument returning the suffix string appended to 'path' (no suffix if 0b).
// - bodyFn    {fn|boolean}        Function applied to the API argument returning the object converted to JSON request body (no request body if 0b).
// - isQuery   {boolean}           Indicates if the request is a table data query.
// - raw       {boolean}           Indicates the response body is returned as-is (e.g. YAML) rather than parsed as JSON, using an 'application/yaml' Accept header. If the API argument is a string, the raw response is also saved to that local file path.
API:flip
	(`name;           `method; `path;             `argTypes;  `suffixFn;    `bodyFn;    `isQuery; `raw)!
	flip( /--------------------------------------------------------------------------------------------
	(`createTable;    `POST;   "tables";          99h;        getKey`table; _[;`table]; 0b;       0b);
	(`listTables;     `GET;    "tables";          ();         0b;           0b;         0b;       0b);
	(`describeTable;  `GET;    "tables";          99 10 -11h; getKey`table; 0b;         0b;       0b);
	(`dropTable;      `DELETE; "tables";          99 10 -11h; getKey`table; 0b;         0b;       0b);
	(`importFiles;    `POST;   "imports/files";   99h;        0b;           ::;         0b;       0b);
	(`importData;     `POST;   "imports/data";    99h;        0b;           ::;         0b;       0b);
	(`importKDB;      `POST;   "imports/kdb";     99h;        0b;           ::;         0b;       0b);
	(`getImport;      `GET;    "imports";         99 10 -11h; getKey`jobId; 0b;         0b;       0b);
	(`cancelImport;   `DELETE; "imports";         99 10 -11h; getKey`jobId; 0b;         0b;       0b);
	(`deleteRows;     `POST;   "deletes";         99h;        0b;           ::;         0b;       0b);
	(`getDelete;      `GET;    "deletes";         99 10 -11h; getKey`jobId; 0b;         0b;       0b);
	(`cancelDelete;   `DELETE; "deletes";         99 10 -11h; getKey`jobId; 0b;         0b;       0b);
	(`querySimple;    `POST;   "query/simple";    99h;        0b;           ::;         1b;       0b);
	(`querySQL;       `POST;   "query/sql";       10 99h;     0b;           ::;         1b;       0b);
	(`queryQ;         `POST;   "query/q";         10 99h;     0b;           ::;         1b;       0b);
	(`queryPreview;   `POST;   "query/preview";   10 99h;     0b;           ::;         1b;       0b);
	(`exportAssembly; `GET;    "config/assembly"; ();         0b;           0b;         0b;       1b))

// @desc Request handler. The last argument is projected by 'createSession' when it generates each API.
// @param endpoint {string}  Endpoint host/port.
// @param api      {dict}    A row from the API definition table.
// @param arg      {any}     API argument.
// @return         {any}     Formatted API response (see 'formatResp' for details).
request:{[endpoint;api;arg]
	([method;path;argTypes;suffixFn;bodyFn;isQuery;raw]):api;
	if[count argTypes; / If arg type check is enabled
		if[not(t:type arg)in argTypes;'typeErr["argument";t;argTypes]]];
	if[isQuery;
		if[10h=type arg;arg:([query:arg])]; / Wrap if the query is provided as a string
		unwrap:not 0b~arg`unwrap; / Determine if the header should be included in the response
		arg _:`unwrap]; / Drop the key that is only relevant for the client
	suffix:$[suffixFn~0b;""; / Generate the path suffix if applicable
		1b~first r:@[(1b;)suffixFn@;arg;::];"/",$[-11h=type s;string;]s:last r;
		'r]; / Re-throw the caught error here to avoid a debug session
	if[99h=type arg;
		if[`assembly in key arg; / Move assembly specification to the suffix
			t:type a:arg`assembly;
			suffix,:"?assembly=",$[10h=t;a;-11h=t;string a;'typeErr["'assembly'";t;10 -11h]];
			arg _:`assembly]];
	url:endpoint,PREFIX,path,suffix; / Construct the full request URL
	headers:([Accept:"application/",$[isQuery;"octet-stream";raw;"yaml";"json"]]); / Binary payload for queries, YAML for raw responses, JSON otherwise
	if[b:not 0b~bodyFn;headers[`$"Content-Type"]:"application/json"]; / Request payload (if applicable) is JSON
	opts:([headers;max_retry_attempts:0]),$[b;([body:.j.j bodyFn arg]);()];
	(status;body):@[sync;(url;method;opts);{'"Unable to send request (",string[x]," ",y,"): ",z}[method;url]]; / Send request
	res:formatResp[status;body;isQuery;raw;unwrap];
	if[raw and(string status)like"20*";
		if[10h=type arg;hsym[`$arg]1:res]]; / Optionally save a successful raw response to a local file
	res
	}

// @desc Generates an error message for an unexpected object type.
// @param n {string}        Name of the checked object.
// @param t {short}         Type of the checked object.
// @param x {short|short[]} Expected types.
// @return  {string}        Error message.
typeErr:{[n;t;x]"Unexpected ",n," type (",string[t],"h), must be ",$[1=count x;"";"one of "],.Q.s1 x}

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
					99h<>type r:d 1;([status;error:.Q.s1 r]); / Return stringified parsed payload as error if it has unexpected type
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
// @return   {dict}  Request handlers (projections of 'request').
createSession:{
	e:$[10h=t:type x;x;99h<>t;::;`endpoint in key x;x`endpoint;::]; / Extract endpoint from the argument
	endpoint:$[e~(::);"http://localhost:8080"; / Use default endpoint if not provided
		any e like/:("http://*";"https://*");e;"http://",e]; / Ensure prefix
	API[`name]!request[endpoint]@'API
	}

export:([createSession])