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

{ #category : 'as yet unclassified' }
Cassandra >> buildAuthResponse: username password: password [
    | credentials stream |
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
        nextPutAll: #[0 0 0 1];  "Consistency: ONE"
        nextPut: 0;  "Flags"
        nextPutAll: (queryString size asByteArrayOfSize: 4);
        nextPutAll: queryString asByteArray.
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

{ #category : 'as yet unclassified' }
Cassandra >> bytesToHexString: aByteArray [
    ^ String streamContents: [ :stream |
        aByteArray do: [ :byte |
            stream nextPutAll: (byte printPaddedWith: $0 to: 2 base: 16)
        ] separatedBy: [ stream nextPut: Character space ]
    ]
]

{ #category : 'binary' }
Cassandra >> checkForTimeout: startTime [
    (DateAndTime now - startTime) asSeconds > 30 "30-second timeout"
        ifTrue: [
            Transcript show: 'Timeout while receiving data'; cr.
            self error: 'Timeout while receiving data'
        ].
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

{ #category : 'as yet unclassified' }
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
    | flags columnCount columns |
    flags := (stream next: 4) asInteger.
    columnCount := (stream next: 4) asInteger.
    columns := (1 to: columnCount) collect: [:i | 
        | nameLength name typeCode |
        nameLength := (stream next: 2) asInteger.
        name := (stream next: nameLength) asString.
        typeCode := stream next.
        Array with: name with: typeCode].
    ^ columns.
]

{ #category : 'parsing' }
Cassandra >> parseResponse: responseBytes [
    | stream version flags opcode length body kind metadata rowCount rows |
    stream := ReadStream on: responseBytes.
    
    "Parse header"
    version := stream next.
    flags := stream next.
    stream next: 2. "Skip stream ID"
    opcode := stream next.
    length := (stream next: 4) asInteger.
    
    "Ensure it's a RESULT response"
    opcode = 8 ifFalse: [self error: 'Unexpected opcode'].
    
    "Parse body"
    body := stream next: length.
    stream := ReadStream on: body.
    
    kind := (stream next: 4) asInteger.
    
    "Ensure it's a ROWS result"
    kind = 2 ifFalse: [self error: 'Unexpected result kind'].
    
    "Parse metadata"
    metadata := self parseMetadata: stream.
    
    "Parse rows"
    rowCount := (stream next: 4) asInteger.
    rows := (1 to: rowCount) collect: [:i | self parseRow: stream columns: metadata].
    
    ^ rows.
]

{ #category : 'parsing' }
Cassandra >> parseResponseOpcode: responseBytes [
    ^ responseBytes at: 5.
]

{ #category : 'parsing' }
Cassandra >> parseRow: stream columns: metadata [
    ^ metadata collect: [:column |
        | value |
        value := self parseValue: stream type: column second.
        column first -> value].
]

{ #category : 'parsing' }
Cassandra >> parseValue: stream type: typeCode [
    | length |
    length := (stream next: 4) asInteger.
    length = -1 ifTrue: [^ nil].
    
    typeCode = 1 ifTrue: [^ (stream next: length) asString]. "ASCII"
    typeCode = 2 ifTrue: [^ (stream next: 8) asInteger]. "BIGINT"
    typeCode = 3 ifTrue: [^ (stream next: length) asString]. "BLOB"
    typeCode = 4 ifTrue: [^ stream next = 1]. "BOOLEAN"
    typeCode = 5 ifTrue: [^ (stream next: 8) asFloat]. "DOUBLE"
    typeCode = 6 ifTrue: [^ (stream next: 4) asFloat]. "FLOAT"
    typeCode = 9 ifTrue: [^ (stream next: 4) asInteger]. "INT"
    typeCode = 13 ifTrue: [^ (stream next: length) asString]. "VARCHAR"
    typeCode = 14 ifTrue: [^ DateAndTime fromUnixTime: (stream next: 8) asInteger / 1000]. "TIMESTAMP"
    
    "Default: return raw bytes"
    ^ stream next: length.

]

{ #category : 'connection open/close' }
Cassandra >> performHandshake [
    | optionsFrame optionsResponse startupFrame startupResponse |
    
    "Send OPTIONS frame"
    Transcript show: 'Sending OPTIONS frame...'; cr.
    optionsFrame := self buildOptionsFrame.
    self sendFrame: optionsFrame.
    (Delay forSeconds: 1) wait.
    
    "Receive OPTIONS response"
    Transcript show: 'Waiting for OPTIONS response...'; cr.
    optionsResponse := self receiveFrame.
    Transcript show: 'Received OPTIONS response of ', optionsResponse size asString, ' bytes'; cr.
    
    "Validate OPTIONS response"
    (self parseResponseOpcode: optionsResponse) = 6
        ifFalse: [self error: 'Unexpected response opcode for OPTIONS'].
    
    "Send STARTUP frame"
    Transcript show: 'Sending STARTUP frame...'; cr.
    startupFrame := self buildStartupFrame.
    self sendFrame: startupFrame.
    
    "Receive STARTUP response"
    Transcript show: 'Waiting for STARTUP response...'; cr.
    startupResponse := self receiveFrame.
    Transcript show: 'Received STARTUP response of ', startupResponse size asString, ' bytes'; cr.
    
    "Handle STARTUP response"
    (self parseResponseOpcode: startupResponse) caseOf: {
        [3] -> [self handleAuthentication: startupResponse]. "AUTHENTICATE"
        [2] -> [Transcript show: 'Ready to query'; cr]. "READY"
        [0] -> [ "ERROR"
            | errorCode errorMessage |
            errorCode := (startupResponse copyFrom: 10 to: 13) asInteger.
            errorMessage := (startupResponse copyFrom: 14 to: startupResponse size) asString.
            self error: 'Server error: ', errorCode asString, ' - ', errorMessage
        ]
    } otherwise: [self error: 'Unexpected response opcode for STARTUP'].
    
    Transcript show: 'Handshake completed successfully'; cr.
]

{ #category : 'binary' }
Cassandra >> receiveBytes: count [
    | buffer bytesRead startTime |
    buffer := ByteArray new: count.
    bytesRead := 0.
    startTime := DateAndTime now.
    
    [ bytesRead < count ] whileTrue: [
        self checkForTimeout: startTime.
        bytesRead := bytesRead + (self receiveDataInto: buffer startingAt: bytesRead + 1 count: count - bytesRead).
        Transcript show: 'Received ', bytesRead asString, ' of ', count asString, ' bytes'; cr.
        bytesRead = count ifFalse: [
            Transcript show: 'Waiting for more data...'; cr.
            (Delay forMilliseconds: 100) wait.
        ].
    ].
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
    Transcript show: 'Attempting to receive frame...'; cr.
    [
        Transcript show: 'Reading header (9 bytes)...'; cr.
        headerBytes := self receiveBytes: 9.
        Transcript show: 'Header received: ', (self bytesToHexString: headerBytes); cr.
        bodyLength := (headerBytes copyFrom: 6 to: 9) asInteger.
        Transcript show: 'Body length: ', bodyLength asString, ' bytes'; cr.
        Transcript show: 'Reading body...'; cr.
        bodyBytes := self receiveBytes: bodyLength.
        Transcript show: 'Body received: ', (self bytesToHexString: bodyBytes); cr.
        ^ headerBytes, bodyBytes
    ] on: Error do: [ :error |
        Transcript show: 'Error receiving frame: ', error messageText; cr.
        self error: 'Error receiving frame: ', error messageText
    ].
]

{ #category : 'binary' }
Cassandra >> sendFrame: aByteArray [
    Transcript show: 'Sending frame of ', aByteArray size asString, ' bytes...'; cr.
    [
        socket nextPutAll: aByteArray.
        socket flush.
        Transcript show: 'Frame sent successfully'; cr.
    ] on: Error do: [ :error |
        Transcript show: 'Error sending frame: ', error messageText; cr.
        self error: 'Error sending frame: ', error messageText.
    ].

]

{ #category : 'tests' }
Cassandra >> testConnection [
        self connect: '172.17.0.2' port: 9042 username: 'cassandra' password: 'cassandra'.

]
