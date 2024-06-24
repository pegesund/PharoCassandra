"
Please describe the package using the class comment of the included manifest class. The manifest class also includes other additional metadata for the package. These meta data are used by other tools such as the SmalllintManifestChecker and the critics Browser
"
Class {
	#name : 'ManifestCassandraCQLTests',
	#superclass : 'PackageManifest',
	#category : 'CassandraCQL-Tests-Manifest',
	#package : 'CassandraCQL-Tests',
	#tag : 'Manifest'
}

{ #category : 'code-critics' }
ManifestCassandraCQLTests class >> ruleCodeCruftLeftInMethodsRuleV1FalsePositive [

	<ignoreForCoverage>
	^ #(#(#(#RGPackageDefinition #(#'Cassandra-Tests')) #'2024-06-24T20:22:38.293627+02:00') )
]

{ #category : 'code-critics' }
ManifestCassandraCQLTests class >> ruleEqualsTrueRuleV1FalsePositive [

	<ignoreForCoverage>
	^ #(#(#(#RGClassDefinition #(#CassandraTest)) #'2024-06-24T20:39:10.962089+02:00') )
]
