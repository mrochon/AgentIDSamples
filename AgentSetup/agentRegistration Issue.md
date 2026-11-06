
### Agent creation

```
POST https://graph.microsoft.com/beta/copilot/agentRegistrations
Authorization: Bearer {{loginAgentOperator.response.body.access_token}}
Content-Type: application/json
```
```json
{
    "id": "89f6f77f-8258-4659-8e57-f224dcef5034",
    "displayName": "MR agent created using Graph agentRegistration V4",
    "sourceCreatedDateTime": "2024-06-05T12:00:00Z",
    "sourceModifiedDateTime": "2024-06-05T12:00:00Z",
    "originatingStore": "customAgentStore",
    "createdBy": "{{$dotenv USER_OBJECT_ID}}",
    "ownerIds": ["{{$dotenv USER_OBJECT_ID}}"],
    "sourceAgentId": "mr-graph-agentRegistration-004",
    "description": "This agent wahelps users with Microsoft Graph APIs. It can construct the http calls and their payloads for any entity handled by MS Graph.",
}
```

### Using copilot/packages List

#### Call

```
GET https://graph.microsoft.com/beta/copilot/admin/catalog/packages?$filter=lastModifiedDateTime ge 2026-11-03T08:00Z&select=displayName
Authorization: Bearer {{loginAgentOperator.response.body.access_token}}
```

#### Response

Note that the $select clause had no effect. I get same response without $select.

***Problem:*** apart from displayName, there is no data linking this object with the agentRegistration object - id is different, there is no description! Therefore, even if we retrieve all agents we register using copilot/packages (LIST), we have no access to their full-text description. I tried using filter with displayName (since it does show up in both entities with same value) in desperation - no good.

```json
[
    ...
    {
      "id": "T_f9328fd3-158b-f191-dcca-5ce4acf8a416",
      "displayName": "MR agent created using Graph agentRegistration V4",
      "type": "shared",
      "shortDescription": "",
      "isBlocked": false,
      "supportedHosts": [],
      "lastModifiedDateTime": "2026-11-04T21:48:57.0900335Z",
      "publisher": "",
      "availableTo": "allowedForAll",
      "deployedTo": "acquiredForNone",
      "elementTypes": [
        "AgentMetadatas"
      ],
      "platform": "customAgentStore",
      "appId": null,
      "assetId": "2f2d1f31-08d9-42c2-b750-bc5db36dee6d",
      "version": "1.0",
      "manifestVersion": "",
      "ownerId": "59f6f77f-8258-4659-8e57-f224dcef5075",
      "agentIdentityId": null,
      "requestType": null,
      "requestStatus": null,
      "manifestId": null,
      "longDescription": null,
      "createdDateTime": "2024-06-05T12:00:00Z",
      "governanceMetadata": null
    }
    ...
]
```

### Using agentRegistration GET

#### Call
```
GET https://graph.microsoft.com/beta/copilot/agentRegistrations/89f6f77f-8258-4659-8e57-f224dcef5034
Authorization: Bearer {{loginAgentOperator.response.body.access_token}}
```

#### Response

```json
{
  "@odata.context": "https://graph.microsoft.com/beta/$metadata#copilot/agentRegistrations/$entity",
  "id": "89f6f77f-8258-4659-8e57-f224dcef5034",
  "displayName": "MR agent created using Graph agentRegistration V4",
  "ownerIds": [
    "59f6f77f-8258-4659-8e57-f224dcef5075"
  ],
  "lastPublishedBy": null,
  "sourceCreatedDateTime": "2024-06-05T12:00:00Z",
  "createdBy": "59f6f77f-8258-4659-8e57-f224dcef5075",
  "sourceLastModifiedDateTime": "2026-11-04T21:48:57.0436644Z",
  "description": "This agent wahelps users with Microsoft Graph APIs. It can construct the http calls and their payloads for any entity handled by MS Graph.",
  "agentIdentityId": null,
  "managedByAppId": null,
  "agentIdentityBlueprintId": null,
  "sourceAgentId": "mr-graph-agentRegistration-004",
  "originatingStore": "customAgentStore",
  "agentCard": null,
  "a2aAuthorization": null
}
```