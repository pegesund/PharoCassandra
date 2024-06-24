"
Test cassandra features.

It supposes a running cassandra, answering on standard Cassandra port.

The ip is hardcoded to 172.17.0.2 which is the ip on my local docker. Change the function 'getTestIp' in this class to change.

Easiest way to test is to run a docker like described here https://opensource.docs.scylladb.com/stable/operating-scylla/procedures/tips/best-practices-scylla-on-docker.html

docker run --name some-scylla -d scylladb/scylla
"
Class {
	#name : 'CassandraTest',
	#superclass : 'TestCase',
	#category : 'CassandraCQL-Tests-Integration',
	#package : 'CassandraCQL-Tests',
	#tag : 'Integration'
}

{ #category : 'connection' }
CassandraTest class >> getTestIp [
 ^ '172.17.0.2'
]

{ #category : 'tests' }
CassandraTest >> testReadDictionary [
"this tests that map type is read correctly from the binary stream"
	| cassandra data findEntry |
	cassandra := Cassandra new.
	cassandra connect: self class getTestIp port: 9042.

	data := cassandra executeQuery:
		        'SELECT * FROM system_schema.keyspaces'.

	findEntry := [ :name |
	             data
		             detect: [ :entry | entry first = name ]
		             ifNone: [ nil ] ].
	"Assert that 'system_auth' exists with correct strategy and replication factor"
	self assert: ((findEntry value: 'system_auth') notNil and: [
			 (findEntry value: 'system_auth') second = true and: [
				 ((findEntry value: 'system_auth') third at: 'class')
				 = 'org.apache.cassandra.locator.SimpleStrategy' and: [
					 ((findEntry value: 'system_auth') third at: 'replication_factor')
					 = '1' ] ] ]).

	"Assert that 'system_schema' exists with correct strategy"
	self assert: ((findEntry value: 'system_schema') notNil and: [
			 (findEntry value: 'system_schema') second = true and: [
				 ((findEntry value: 'system_schema') third at: 'class')
				 = 'org.apache.cassandra.locator.LocalStrategy' ] ])
]
