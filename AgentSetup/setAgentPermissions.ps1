Connect-Entra -Scopes 'AgentIdentityBlueprint.UpdateAuthProperties.All'
Add-EntraPermissionsToInheritToAgentIdentityBlueprintPrincipal -Scopes @("user.read","mail.read") -Roles @("https://graph.microsoft.com/mail.read","https://graph.microsoft.com/user.read.all")
