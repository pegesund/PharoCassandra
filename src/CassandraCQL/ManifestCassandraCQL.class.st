"
Please describe the package using the class comment of the included manifest class. The manifest class also includes other additional metadata for the package. These meta data are used by other tools such as the SmalllintManifestChecker and the critics Browser
"
Class {
	#name : 'ManifestCassandraCQL',
	#superclass : 'PackageManifest',
	#category : 'CassandraCQL-Manifest',
	#package : 'CassandraCQL',
	#tag : 'Manifest'
}

{ #category : 'code-critics' }
ManifestCassandraCQL class >> ruleBadMessageRule2V1FalsePositive [

	<ignoreForCoverage>
	^ #(#(#(#RGPackageDefinition #(#CassandraCQL)) #'2024-06-22T16:34:02.609405+02:00') )
]

{ #category : 'code-critics' }
ManifestCassandraCQL class >> ruleCascadedNextPutAllsRuleV1FalsePositive [

	<ignoreForCoverage>
	^ #(#(#(#RGPackageDefinition #(#CassandraCQL)) #'2024-06-22T16:33:50.799104+02:00') )
]

{ #category : 'code-critics' }
ManifestCassandraCQL class >> ruleLiteralArrayContainsCommaRuleV1FalsePositive [

	<ignoreForCoverage>
	^ #(#(#(#RGMethodDefinition #(#Cassandra #validateResultType: #false)) #'2024-06-23T13:08:30.590546+02:00') )
]

{ #category : 'code-critics' }
ManifestCassandraCQL class >> ruleLongMethodsRuleV1FalsePositive [

	<ignoreForCoverage>
	^ #(#(#(#RGPackageDefinition #(#CassandraCQL)) #'2024-06-22T16:44:06.982558+02:00') )
]

{ #category : 'code-critics' }
ManifestCassandraCQL class >> ruleReNotOptimizedIfRuleV1FalsePositive [

	<ignoreForCoverage>
	^ #(#(#(#RGMethodDefinition #(#Cassandra #parseMetadata: #false)) #'2024-06-23T13:29:40.512478+02:00') )
]
