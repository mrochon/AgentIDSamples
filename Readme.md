# Entra Agent ID REST exercises

## Description

Various Graph API calls to create agent id objects in Entra. They are in the sequence
they should be used:

- login with an application that will create the agents to get an application token with the right permissions
- create a blueprint with roles and a scope
- update the blueprint with app id uri
- create a credential for the blueprint
- use blueprint to create an agent
- assign an agent role to a user

## Setup

1. Install REST extension to support executing individual http calls

1. Register an application in Entra with the following permissions (to cover all REST calls included. In practice, you may have different applications operating on the agent ids, each with own permissions).

### Application permissions
AgentIdentityBlueprint.AddRemoveCreds.All
AgentIdentityBlueprint.Create
AgentIdentityBlueprint.DeleteRestore.All
AgentIdentityBlueprint.Read.All
AgentIdentityBlueprint.UpdateAuthProperties.All
AgentIdentityBlueprint.UpdateBranding.All
AgentIdentityBlueprintPrincipal.Create
AgentIdentityBlueprintPrincipal.DeleteRestore.All
Application.Read.All
Application.ReadWrite.All
AppRoleAssignment.ReadWrite.All

### Delegated permissions
User.Read
Permission to call the agent (agent must define a scope)


3. Update .env file with your user and the registered application details