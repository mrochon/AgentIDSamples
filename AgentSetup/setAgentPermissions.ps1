# NOTE: this will only do conenst, you must still define the permissions as requiredResourceAccess structure in the blueprint
Connect-Entra -Scopes 'AgentIdentityBlueprint.UpdateAuthProperties.All'
Add-EntraPermissionsToInheritToAgentIdentityBlueprintPrincipal -Scopes @("user.read","mail.read") -Roles @("https://graph.microsoft.com/mail.read","https://graph.microsoft.com/user.read.all")
