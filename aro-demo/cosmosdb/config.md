# Cosmos DB

You can delete and re-create the collection to clear all items.

Existing settings on the collection below in case you need them.

## Indexing Policy:

```json
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
```

## Partition keys:

- Current partition key: `/storeId`
- Partitioning: Non-hierarchical

## Computed properties

```json
[
    {
        "name": "name_of_property",
        "query": "query_to_compute_property"
    }
]
```

## Scale:

- 400 RU/s manual
- Storage capacity unlimited

