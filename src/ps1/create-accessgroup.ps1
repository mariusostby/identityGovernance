param (
  [Parameter()]
  [String]
  $TeamJsonPath = ".\teams\team-example\team-example.json",
  $appSecret,
  $appId,
  $tenantId
)
# run script with groups rw all, and rbac permissions on all LZs

# read info on team
$context = get-content $TeamJsonPath | ConvertFrom-Json

$context.accessPackages

# init
Import-Module .\src\ps1\accessMgmt.psm1
$token = Get-TokenByAppSecret -appID $appId -secret $appSecret -tenantID $tenantId
# create header
$header = @{
  "Authorization" = "Bearer $Token"
  "Content-type"  = 'application/json'
} 

# create catalog if it doesnt already exist
$uri = 'https://graph.microsoft.com/v1.0/identityGovernance/entitlementManagement/catalogs'
$payload = @{
  displayName         = $context.teamInfo.name
  description         = "Identity Governance for resources belonging to $($context.teamInfo.name)"
  state               = "published"
  isExternallyVisible = $true
}

# check if catalog exists
$filter = '?$filter=displayName eq ' + "'" + $payload.displayName + "'"
$filterUri = $uri + $filter
$catalog = Invoke-RestMethod -Method GET -uri $filterUri -Headers $header -ErrorAction SilentlyContinue

# if catalog doesnt exist, create it
if (!($catalog.value)) {
  $catalog = Invoke-RestMethod -Method POST -Body ($payload | ConvertTo-Json) -Uri $uri -Headers $header
}
else {
  Write-Host "Catalog exists - skipping creation"
}
# add catalogId to context
$context | add-member -Name catalogId -Value $catalog.value.id -MemberType NoteProperty -Force


#######################################################################################################
# LOOPING THROUGH TEAM CONFIG - CREATING :
# GROUP - ROLEASSIGNMENT - ACCESSPACKAGE - ACCESSPACKAGEROLEASSIGNMENT - ACCESSPACKAGEPOLICY
#######################################################################################################

foreach ($package in $context.accessPackages) {
  # check if groups already exist, create if not
  $group = Get-AzADGroup -DisplayName $package.name
  if (!($group)) {
    $group = New-AzADGroup -DisplayName $package.name -SecurityEnabled -MailNickname $package.name
  }

  # grant group desired role on scope

  $roleAssignment = Get-AzRoleAssignment -Scope $package.scope | Where-Object -FilterScript { $_.ObjectId -eq $group.Id -and $_.RoleDefinitionId -eq $package.role }
  if (!($roleAssignment)) {
    $roleAssignment = New-AzRoleAssignment -ObjectId $group.id -Scope $package.scope -RoleDefinitionId $package.role
  }


  # add group to catalog, if not already present
  $uri = "https://graph.microsoft.com/beta/identityGovernance/entitlementManagement/accessPackageCatalogs/$($context.catalogId)/accessPackageResources"
  $catalogGroups = (Invoke-RestMethod -Method Get -Uri $uri -Headers $header).value

  $accessRequestObject = @{
    "catalogId"             = $context.catalogId
    "requestType"           = "AdminAdd"
    "justification"         = ""
    "accessPackageResource" = @{
      "displayName"  = $group.DisplayName
      "description"  = $group.Description
      "resourceType" = "AadGroup"
      "originId"     = $group.id
      "originSystem" = "AadGroup"
    }
  }
  # need to check if group already exists in catalog
  $groupExists =
  try {
    $catalogGroups.originId.Contains($group.id)
  }
  catch {
    $false
  }

  if (!($groupExists)) {
    $uri = 'https://graph.microsoft.com/beta/identityGovernance/entitlementManagement/accessPackageResourceRequests'
    Write-Host "Group $($group.DisplayName) with id $($group.Id) not found in catalog $($context.catalogId)"
    Write-Host "Proceeding to add group..."
    Invoke-RestMethod -Uri $uri -Method Post -Headers $header -Body ($accessRequestObject | convertto-json) #todo add errorhandling
    # update catalogGroupsobject - needed for later operations!
    $uri = "https://graph.microsoft.com/beta/identityGovernance/entitlementManagement/accessPackageCatalogs/$($context.catalogId)/accessPackageResources"
    $catalogGroups = (Invoke-RestMethod -Method Get -Uri $uri -Headers $header).value
  }
  # determine internal groupId (a catalog-spesific id is created upon assignment)
  $internalGroupid = ($catalogGroups | Where-Object -FilterScript { $_.originId -eq $group.id }).id

  # create access package in catalog
  $uri = 'https://graph.microsoft.com/beta/identityGovernance/entitlementManagement/accessPackages'

  $payload = @{
    "catalogId"   = $context.catalogId
    "displayName" = $package.name
    "description" = $package.name
  }

  # check if accesspackage exists already:
  $filter = '?$filter=displayName eq ' + "'" + $package.name + "'"
  $filterUri = $uri + $filter
  $accessPackage = (Invoke-RestMethod -Uri  $filterUri -Method Get -Headers $header).value
  $accessPackage
  # if no accesspackage exists - create it
  if (!($accessPackage)) {
    $accessPackage = Invoke-RestMethod -Uri $uri -Method Post -Headers $header -Body ($payload | convertto-json)
    $accessPackage
  }
  else {
    Write-host "Accesspackage $($accesspackage).displayName already exists, skipping creation"
  }


  # link group to accesspackage 
  $uri = "https://graph.microsoft.com/beta/identityGovernance/entitlementManagement/accessPackages/$($accessPackage.id)/accessPackageResourceRoleScopes"

  $accessPackageResourceRoleScopeObject = @{
    accessPackageResourceRole  = @{
      originId              = "Member_$($group.Id)"
      displayName           = "Member"
      originSystem          = "AadGroup"
      accessPackageResource = @{
        id           = $internalGroupid
        resourceType = "Security Group"
        originId     = $group.Id
        originSystem = "AadGroup"
      }
    }
    accessPackageResourceScope = @{
      originId     = $group.Id
      originSystem = "AadGroup"
    }
  }

  # this post appears to be idempotent...
  Invoke-RestMethod -Method POST -Body ($accessPackageResourceRoleScopeObject | ConvertTo-Json) -Uri $uri -Headers $header

  # add policy to access package
  $uri = "https://graph.microsoft.com/beta/identityGovernance/entitlementManagement/accessPackageAssignmentPolicies"

  #getting baseline
  $policyBaseline = get-content .\src\json\strict-policy.json | convertfrom-json
  #configuring policy
  $policyBaseline.accessPackageId = $accessPackage.id
  # needs errorhandling - but this is a POC - add teamlead as secondary approver
  $policyBaseline.requestApprovalSettings.approvalStages.primaryApprovers[0].id = (get-azaduser -UserPrincipalName $context.teamInfo.teamLead).Id
  $policyBaseline.requestApprovalSettings.approvalStages.primaryApprovers[0].description = $context.teamInfo.teamLead

  # post appears idempotent...
  Invoke-RestMethod -Method Post -uri $uri -Headers $header -Body ($policyBaseline | convertto-json -Depth 100)

}