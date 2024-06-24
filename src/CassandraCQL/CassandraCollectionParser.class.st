"
I am a helper to parse collections in binary format.
"
Class {
	#name : 'CassandraCollectionParser',
	#superclass : 'Object',
	#category : 'CassandraCQL-parsing',
	#package : 'CassandraCQL',
	#tag : 'parsing'
}

{ #category : 'parsing' }
CassandraCollectionParser class >> parseMap: stream typeCode: typeCode parent: cassandra [

	| keyType valueType dict |
	keyType := typeCode second first.
	valueType := typeCode second second.
	dict := Dictionary new.
	(stream next: 4) asInteger timesRepeat: [
		dict
			at: (cassandra parseValue: stream type: keyType)
			put: (cassandra parseValue: stream type: valueType) ].
	^ dict
]
