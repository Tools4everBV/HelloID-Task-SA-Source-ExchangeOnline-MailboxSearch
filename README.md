# HelloID-Task-SA-Source-ExchangeOnline-MailboxSearch

## Prerequisites
- [ ] This script uses the Exchange Online Management PowerShell Module and requires an App Registration with App permissions:
  - [ ] Manage Exchange As Application <b><i>Exchange.ManageAsApp</i></b>
- [ ] And a role with the permissions for Exchange Online:
  - [ ] The **Exchange Administrator** role should provide the required permissions for any task in Exchange Online PowerShell. However, some actions may not be allowed, such as managing other admin accounts, for this the Global Administrator would be required. Please note that the required role may vary based on your configuration.

## Description

This code snippet executes the following tasks:

1. Imports the ExchangeOnlineManagement module.
2. Define a wildcard search query `$searchValue` based on the search parameter `$datasource.searchValue`
3. Creates a session to Exchange Online.
4. List all mailboxes in Exchange Online that match the wildcard search query `$searchValue` in their name or email addresses using the API call: [Get-EXOMailbox](https://learn.microsoft.com/en-us/powershell/module/exchange/get-exomailbox?view=exchange-ps)
   > The filter property **-filter** accepts different values [See the Microsoft Docs page](https://learn.microsoft.com/en-us/powershell/module/exchange/get-exomailbox?view=exchange-ps#-filter)
5. Return a hash table for each user account using the `Write-Output` cmdlet.

> To view an example of the data source output, please refer to the JSON code pasted below.

```json
{
    "searchValue": "Consultancy"
}
```