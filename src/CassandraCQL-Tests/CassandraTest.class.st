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

	| cassandra res |
	cassandra := Cassandra new.
	cassandra connect: self class getTestIp port: 9042.

	res := cassandra executeQuery:
		       'SELECT * FROM system_schema.keyspaces'.
	Transcript crShow: (res asString).
]
