# Cosmos DB

Delete and recreate collection to clear items.

## Indexing Policy:

{
    "indexingMode": "consistent",
    "automatic": true,
    "includedPaths": [
        {
            "path": "/*"
        }
    ],
    "excludedPaths": [
        {
            "path": "/\"_etag\"/?"
        }
    ],
    "fullTextIndexes": []
}

## Partition keys:

Current partition key: /storeId
Partitioning: Non-hierarchical

## Computed properties

[
    {
        "name": "name_of_property",
        "query": "query_to_compute_property"
    }
]

## Scale:

400 RU/s manual
Storage capacity unlimited

