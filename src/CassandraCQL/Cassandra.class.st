"
I hold the socket cassandra connection
"
Class {
	#name : 'Cassandra',
	#superclass : 'Object',
	#instVars : [
		'socket',
		'username',
		'password'
	],
	#category : 'CassandraCQL-connection',
	#package : 'CassandraCQL',
	#tag : 'connection'
}

{ #category : 'converting' }
Cassandra class >> doubleToByteArray: aDouble [
    | lowWord highWord |
    lowWord := aDouble basicAt: 1.
    highWord := aDouble basicAt: 2.
    ^ ByteArray new: 8 streamContents: [ :stream |
        5 to: 8 do: [ :i |
            stream nextPut: (highWord byteAt: 9 - i)
        ].
        1 to: 4 do: [ :i |
            stream nextPut: (lowWord byteAt: 5 - i)
        ]
    ]
]

{ #category : 'converting' }
Cassandra class >> floatToByteArray: aFloat [
    | word |
    word := aFloat asIEEE32BitWord.
    ^ ByteArray new: 4 streamContents: [ :stream |
        1 to: 4 do: [ :i |
            stream nextPut: (word byteAt: 5 - i)
        ]
    ]
]

{ #category : 'connection open/close' }
Cassandra >> buildAuthResponse [ 
    | credentials stream |
    "Fixme later, does not work"
    credentials := ByteArray streamContents: [ :s |
        s nextPut: 0.
        s nextPutAll: username asByteArray.
        s nextPut: 0.
        s nextPutAll: password asByteArray ].
    
    stream := WriteStream on: (ByteArray new: 100).
    stream
        nextPutAll: (credentials size asByteArrayOfSize: 4);
        nextPutAll: credentials.
    
    ^ self buildFrame: 11 "OPCODE_AUTH_RESPONSE" withBody: stream contents
]

{ #category : 'query' }
Cassandra >> buildFrame: opcode [
    ^ self buildFrame: opcode withBody: #[].
]

{ #category : 'query' }
Cassandra >> buildFrame: opcode withBody: bodyBytes [
    | stream |
    stream := WriteStream on: (ByteArray new: 9 + bodyBytes size).
    stream
        nextPut: 4;  "Protocol version"
        nextPut: 0;  "Flags"
        nextPutAll: #[0 0];  "Stream ID"
        nextPut: opcode;
        nextPutAll: (bodyBytes size asByteArrayOfSize: 4);
        nextPutAll: bodyBytes.
    ^ stream contents.
]

{ #category : 'query' }
Cassandra >> buildOptionsFrame [
    ^ self buildFrame: 5 "OPCODE_OPTIONS" withBody: #[].
]

{ #category : 'query' }
Cassandra >> buildQueryFrame: queryString [
    | stream |
    stream := WriteStream on: (ByteArray new: 100).
    stream
        nextPutAll: (queryString size asByteArrayOfSize: 4);
        nextPutAll: queryString asByteArray;
        nextPutAll: #[0 1];  "Consistency: ONE"
        nextPut: 0;  "Flags"
        nextPut: 0.  "number of parameters"
    ^ self buildFrame: 7 "OPCODE_QUERY" withBody: stream contents.
]

{ #category : 'query' }
Cassandra >> buildStartupFrame [
    | stream |
    stream := WriteStream on: (ByteArray new: 100).
    stream
        nextPutAll: #[0 1];  "Number of options"
        nextPutAll: #[0 11]; nextPutAll: 'CQL_VERSION' asByteArray;
        nextPutAll: #[0 5]; nextPutAll: '3.3.1' asByteArray.
    ^ self buildFrame: 1 "OPCODE_STARTUP" withBody: stream contents.
]

{ #category : 'helper' }
Cassandra >> bytesToHexString: aByteArray [
    ^ String streamContents: [ :stream |
        aByteArray do: [ :byte |
            stream nextPutAll: (byte printPaddedWith: $0 to: 2 base: 16)
        ] separatedBy: [ stream nextPut: Character space ]
    ]
]

{ #category : 'binary' }
Cassandra >> checkForTimeout: startTime [

	(DateAndTime now - startTime) asSeconds > 30 ifFalse: [ ^ self ]. "30-second timeout"
	Transcript
		show: 'Timeout while receiving data';
		cr.
	self error: 'Timeout while receiving data'
]

{ #category : 'connection open/close' }
Cassandra >> connect: host port: port [

	| addr |
	[
	Transcript
		show: 'Attempting to connect to ' , host , ':' , port asString;
		cr.
	addr := NetNameResolver addressForName: host.
	socket := SocketStream openConnectionToHost: addr port: port.
	socket binary. "Set the stream to binary mode"
	socket autoFlush: true.
	Transcript
		show: 'Socket connected. Performing handshake...';
		cr.
	self performHandshake ]
		on: Error
		do: [ :error |
			Transcript
				show: 'Error connecting to ' , host , ':' , port asString , ': '
					, error messageText;
				cr.
			self error:
				'Error connecting to ' , host , ':' , port asString , ': '
				, error messageText ]
]

{ #category : 'connection open/close' }
Cassandra >> connect: host port: port username: aUsername password: aPassword [
    | addr |
    username := aUsername.
    password := aPassword.
    [
        Transcript show: 'Attempting to connect to ', host, ':', port asString; cr.
        addr := NetNameResolver addressForName: host.
        socket := SocketStream openConnectionToHost: addr port: port.
        socket binary.  "Set the stream to binary mode"
        socket autoFlush: true.
        Transcript show: 'Socket connected. Performing handshake...'; cr.
        self performHandshake.
    ] on: Error do: [ :error |
        Transcript show: 'Error connecting to ', host, ':', port asString, ': ', error messageText; cr.
        self error: 'Error connecting to ', host, ':', port asString, ': ', error messageText.
    ].
]

{ #category : 'connection open/close' }
Cassandra >> disconnect [
    socket close.
]

{ #category : 'connection open/close' }
Cassandra >> ensureSocketValid [
    (socket isNil or: [socket isConnected not])
        ifTrue: [self error: 'Socket is not connected'].
]

{ #category : 'query' }
Cassandra >> executeQuery: queryString [
    | frame response |
    frame := self buildQueryFrame: queryString.
    self sendFrame: frame.
    response := self receiveFrame.
    ^ self parseResponse: response.
]

{ #category : 'connection open/close' }
Cassandra >> handleAuthentication: authResponse [
    | authClass response |
    Transcript show: 'Authentication required'; cr.
    
    authClass := authResponse size > 9
        ifTrue: [(authResponse copyFrom: 10 to: authResponse size) asString]
        ifFalse: [''].
    Transcript show: 'Authentication class: ', authClass; cr.
    
    response := self buildAuthResponse: username password: password.
    self sendFrame: response.
    
    response := self receiveFrame.
    (self parseResponseOpcode: response) caseOf: {
        [2] -> [
            Transcript show: 'Received another AUTHENTICATE response. This is unexpected.'; cr.
            self error: 'Unexpected AUTHENTICATE response after sending credentials'.
        ].
        [3] -> [Transcript show: 'Authentication successful'; cr]. "READY"
        [0] -> [ "ERROR"
            | errorCode errorMessage |
            errorCode := response size > 13
                ifTrue: [(response copyFrom: 10 to: 13) asInteger]
                ifFalse: [0].
            errorMessage := response size > 14
                ifTrue: [(response copyFrom: 14 to: response size) asString]
                ifFalse: ['Unknown error'].
            self error: 'Authentication failed: ', errorCode asString, ' - ', errorMessage
        ]
    } otherwise: [self error: 'Unexpected response opcode for AUTH_RESPONSE: ', (self parseResponseOpcode: response) asString].
]

{ #category : 'parsing' }
Cassandra >> parseMetadata: stream [

	| flags columnCount columns type |
	"Add to this file for more data types"
	flags := (stream next: 4) asInteger.
	columnCount := (stream next: 4) asInteger.
	columns := (1 to: columnCount) collect: [ :i |
		           | nameLength name |
		           "skip keyspace, as we allready know"
		           nameLength := (stream next: 2) asInteger.
		           name := (stream next: nameLength) asString.
		           nameLength := (stream next: 2) asInteger.
		           name := (stream next: nameLength) asString.
		           nameLength := (stream next: 2) asInteger.
		           name := (stream next: nameLength) asString.
		           type := (stream next: 2) asInteger.
		           self validateResultType: type.
		           "Maps"
		           type = 16r21 ifTrue: [
			           type := { type . { (stream next: 2) asInteger . (stream next: 2) asInteger  }}].
		           "List or set"
		           (#( 16r20 16r22 ) includes: type) ifTrue: [
			           type := { type . {(stream next: 2) asInteger }}].
		           type ].

	^ columns
]

{ #category : 'parsing' }
Cassandra >> parseResponse: responseBytes [

	| stream version flags opcode length body kind columnTypes rowCount rows |
	stream := ReadStream on: responseBytes.

	"Parse header"
	version := stream next.
	flags := stream next.
	stream next: 2. "Skip stream ID"
	opcode := stream next.
	length := (stream next: 4) asInteger.

	"Parse body"
	body := stream next: length.
	stream := ReadStream on: body.

	"Ensure it's a RESULT response"
	opcode = 8 ifFalse: [ self error: 'Unexpected opcode' ].

	"Ensure it's a ROWS result"
	kind := (stream next: 4) asInteger.	
	kind = 2 ifFalse: [ self error: 'Unexpected result kind' ].

	"Parse metadata, return a list of column types"
	columnTypes := self parseMetadata: stream.

	"Parse rows"
	rowCount := (stream next: 4) asInteger.
	rows := (1 to: rowCount) collect: [ :i |
		        self parseRow: stream columns: columnTypes ].

	^ rows
]

{ #category : 'parsing' }
Cassandra >> parseResponseOpcode: responseBytes [
    ^ responseBytes at: 5.
]

{ #category : 'parsing' }
Cassandra >> parseRow: stream columns: metadata [

	^ metadata collect: [ :column |
		  | value |
		  value := self parseValue: stream type: column.
		  value ]
]

{ #category : 'parsing' }
Cassandra >> parseValue: stream type: typeCode [

	| length subType |
	"Check for compound type, like a map or list""Now moved to main branch"
	length := (stream next: 4) asInteger.
	length = -1 ifTrue: [ ^ nil ].

	typeCode = 1 ifTrue: [ ^ (stream next: length) asString ]. "ASCII"
	typeCode = 2 ifTrue: [ ^ (stream next: 8) asInteger ]. "BIGINT"
	typeCode = 3 ifTrue: [ ^ (stream next: length) asByteArray ]. "BLOB"
	typeCode = 4 ifTrue: [ ^ stream next = 1 ]. "BOOLEAN"
	typeCode = 7 ifTrue: [
		| byteArray |
		byteArray := stream next: 8.
		^ Float fromIEEE64BitWord:
			  (byteArray unsignedLongAt: 1 bigEndian: true) << 32
			  + (byteArray unsignedLongAt: 5 bigEndian: true) ]. "DOUBLE"
	typeCode = 8 ifTrue: [
		^ Float fromIEEE32Bit:
			  ((stream next: 4) unsignedLongAt: 1 bigEndian: true) ]. "FLOAT"
	typeCode = 9 ifTrue: [ ^ (stream next: 4) asInteger ]. "INT"
	typeCode = 13 ifTrue: [ ^ (stream next: length) asString ]. "VARCHAR"
	typeCode = 14 ifTrue: [
		^ DateAndTime fromUnixTime: (stream next: 8) asInteger / 1000 ]. "TIMESTAMP"
	"Maps"
	typeCode isCollection ifTrue: [
		subType := typeCode first.
		subType = 33 ifTrue: [ Transcript crShow: 'Got a map, yes' ].
		^ CassandraCollectionParser parseMap: stream typeCode: typeCode  parent: self ].
	"Default: return raw bytes, change to error later"
	^ stream next: length
]

{ #category : 'connection open/close' }
Cassandra >> performHandshake [

	| optionsFrame optionsResponse startupFrame startupResponse |
	"Send OPTIONS frame"
	optionsFrame := self buildOptionsFrame.
	self sendFrame: optionsFrame.
	(Delay forSeconds: 1) wait.

	"Receive OPTIONS response"
	optionsResponse := self receiveFrame.

	"Validate OPTIONS response"
	(self parseResponseOpcode: optionsResponse) = 6 ifFalse: [
		self error: 'Unexpected response opcode for OPTIONS' ].

	"Send STARTUP frame"
	startupFrame := self buildStartupFrame.
	self sendFrame: startupFrame.

	"Receive STARTUP response"
	startupResponse := self receiveFrame.

	"Handle STARTUP response"
	(self parseResponseOpcode: startupResponse)
		caseOf: {
				([ 3 ] -> [ self handleAuthentication: startupResponse ]). "AUTHENTICATE"
				([ 2 ] -> [
				 Transcript
					 show: 'Ready to query';
					 cr ]). "READY"
				([ 0 ] -> [ "ERROR"
				 | errorCode errorMessage |
				 errorCode := (startupResponse copyFrom: 10 to: 13) asInteger.
				 errorMessage := (startupResponse
					                  copyFrom: 14
					                  to: startupResponse size) asString.
				 self error:
					 'Server error: ' , errorCode asString , ' - ' , errorMessage ]) }
		otherwise: [ self error: 'Unexpected response opcode for STARTUP' ].


]

{ #category : 'binary' }
Cassandra >> receiveBytes: count [

	| buffer bytesRead startTime |
	buffer := ByteArray new: count.
	bytesRead := 0.
	startTime := DateAndTime now.

	[ bytesRead < count ] whileTrue: [
		self checkForTimeout: startTime.
		bytesRead := bytesRead + (self
			              receiveDataInto: buffer
			              startingAt: bytesRead + 1
			              count: count - bytesRead).
		bytesRead = count ifFalse: [
			(Delay forMilliseconds: 10) wait ] ].
	^ buffer
]

{ #category : 'accessing' }
Cassandra >> receiveDataInto: buffer startingAt: start count: count [
    | bytesRead |
    bytesRead := 0.
    
    [bytesRead < count and: [socket atEnd not]] whileTrue: [
        buffer at: start + bytesRead put: socket next.
        bytesRead := bytesRead + 1.
    ].
    
    bytesRead = 0 ifTrue: [
        socket isConnected 
            ifFalse: [self error: 'Connection closed unexpectedly'].
        "No data available right now, wait a bit"
        (Delay forMilliseconds: 10) wait.
    ].
    
    ^ bytesRead
]

{ #category : 'binary' }
Cassandra >> receiveFrame [

	| headerBytes bodyLength bodyBytes |
	[
	headerBytes := self receiveBytes: 9.
	bodyLength := (headerBytes copyFrom: 6 to: 9) asInteger.
	bodyBytes := self receiveBytes: bodyLength.
	^ headerBytes , bodyBytes ]
		on: Error
		do: [ :error |
			Transcript
				show: 'Error receiving frame: ' , error messageText;
				cr.
			self error: 'Error receiving frame: ' , error messageText ]
]

{ #category : 'binary' }
Cassandra >> sendFrame: aByteArray [

	[
	socket nextPutAll: aByteArray.
	socket flush.
 ]
		on: Error
		do: [ :error |
			Transcript
				show: 'Error sending frame: ' , error messageText;
				cr.
			self error: 'Error sending frame: ' , error messageText ]
]

{ #category : 'tests' }
Cassandra >> testConnection [
        self connect: '172.17.0.2' port: 9042 username: 'cassandra' password: 'cassandra'.

]

{ #category : 'parsing' }
Cassandra >> validateResultType: type [
"Test for non-implmented return types, throws error if needed"
(#(16r03 16r05 16r0E 16r10 16r30) includes: type) ifTrue: [ self error: 'Type in result is not implemented yet' ].
]
