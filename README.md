# IdentityGovernance as Code

POC for azure identityGovernance as Code

## Purpose

This repo is meant to test the feasability of maintaining azure identity governance as code.

## Limits of POC

This is strictly proof of concept. The core logic does not have adequate errorhandling - nor has there been written any automated tests.
The code is also dependent on BETA graph API at the moment (feb 2022).

The scope of this POC is limited to a simple example of how to express and create access packages for resource scopes belonging to teams, and sort them in catalogs accordingly.
Azure AD Roles, complete lifecycle of access packages, self-service options, audits and access reviews are currently out of scope. ( But indeed possible! )

## What it does

The code in this repo takes a json representation of access packages needed by a group of stakeholders in azure, for example an autonomous developement team.

```json
{
  "teamInfo": {
    "name": "teamexample",
    "teamLead": "dog@navutv.onmicrosoft.com"
  },
  "accessPackages": [
    {
      "name": "teamexample-online-dev-contributors",
      "scope": "/subscriptions/a7690e00-7d72-4724-876e-18ba2062dbdd",
      "role": "b24988ac-6180-42a0-ab88-20f7382dd24c"
    },
```
The info in this json will be used to create (if it doesn't already exist):
- an [aad security group](https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles) with name "teamexample-online-dev-contributors"
- a roleassignment on the [RBAC Scope](https://docs.microsoft.com/en-us/azure/role-based-access-control/scope-overview) defined with the [RBAC Role](https://docs.microsoft.com/en-us/azure/role-based-access-control/built-in-roles) listed, granted to the `group` created earlier
- a [catalog](https://docs.microsoft.com/en-us/azure/active-directory/governance/entitlement-management-catalog-create) in [identity governance](https://docs.microsoft.com/en-us/azure/active-directory/governance/identity-governance-overview) named after the team `teaminfo.name`
- an [access package](https://docs.microsoft.com/en-us/azure/active-directory/governance/entitlement-management-access-package-create) in the `catalog` that contains the `group` created earlier.
- an [access policy](https://docs.microsoft.com/en-us/azure/active-directory/governance/entitlement-management-access-package-create) based on default template expressed in json [example](.\src\json\strict-policy.json). This policy will be assigned to the access package created.

## How it works

The core logic in this example is based heavily on the [MS Graph Tutorial](https://docs.microsoft.com/en-us/graph/tutorial-access-package-api?toc=/azure/active-directory/governance/toc.json&bc=/azure/active-directory/governance/breadcrumb/toc.json) for handling Active Directory entitlement as code.

Powershell is used as a wrapper around REST calls to graph API, with user-spesific input being defined in json and supplied as parameter to the code.

This code requires to be run in context of a serviceprincipal with necessary permissions to create groups and assign rbac roles on all scopes deemed relevant.
It also requires the supply of an appId, secret and tenantId in order to create a token to use with the graph API.
The serviceprincipal must have the following [API permissions](https://docs.microsoft.com/en-us/graph/notifications-integration-app-registration#api-permissions).
`Group.ReadWrite.All EntitlementManagement.ReadWrite.All - Application`
This requires GA approval and are powerful permissions - whether or not you want to automate with such level of credentials should be subject to careful consideration.
