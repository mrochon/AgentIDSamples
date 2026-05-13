# Entra Agent ID raw

My experiements with Entra Agent ID related APIs. Roughly based on this [documentation](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/autonomous-agent-request-tokens?tabs=Microsoft-graph-api).

There are two main components:

1. A set of Microsoft Graph calls to create agent blueprints and related objects. See this [folder](AgentSetup).
2. [A web app](Operation), deployed to Azure (so it can use a Managed Identity) showing token requests involved in obtaining access tokens for an autonomous or a OBO agent. Instructions for deploying it are in the same folder.

The web app is [deployed here](website.lnk) (may take a minute or so to come up if not accessed for a while) but requires an account in my Entra tenant. If you are interested in running it, let me know and will add you as guest.
