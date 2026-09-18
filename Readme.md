# Microsoft Agent ID from first principles — the protocol mechanics underneath the toolkit

These samples show the use of raw Graph and OAuth2 http calls to establish agent ids in Microsoft Entra to use them from code. I consciously avoided developing with any toolkits - they either do not yet exist, are still incomplete or require somewhat obscure implementation (sidecars) to use. 

This code was developed using Microsoft's [Entra Agent ID documentation](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/autonomous-agent-request-tokens?tabs=Microsoft-graph-api).

There are two main components:

1. A set of Microsoft Graph calls to create agent blueprints and related objects. See this [folder](AgentSetup).
2. [A web app](Operation), showing token requests involved in obtaining access tokens for an autonomous or a OBO agent. Instructions for deploying it are in the same folder. It needs to be deployed to Azure to enable use of Managed Identities. Otherwise, it uses a symetric secret (not recommended in production).

The web app is [deployed here](website.lnk) (may take a minute or so to come up if not accessed for a while) but requires an account in my Entra tenant. If you are interested in running it, let me know and will add you as guest.
