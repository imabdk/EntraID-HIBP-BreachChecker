# EntraID-BreachChecker

![PowerShell](https://img.shields.io/badge/PowerShell-7.0%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20Linux%20%7C%20macOS-lightgrey)

Automated PowerShell tool for checking Entra ID (Azure AD) group members against the Have I Been Pwned database. Generate professional HTML and PDF reports for security audits, compliance documentation, and executive briefings.

> **Everything can be done automatically** - [imab.dk](https://www.imab.dk)

## 🎯 Features

### 🔐 Comprehensive Breach Detection
- Automatically checks all group members for data breaches
- Displays detailed breach information including dates and exposed data types
- Identifies multiple breaches per account
- Supports nested group traversal

### 📊 Professional Reporting
- Generates modern, responsive HTML reports with custom branding
- Optional PDF generation for archival and distribution
- Executive summary with key metrics and statistics
- Color-coded status indicators and easy-to-read tables
- Clear breach details including affected data types

### ⚡ Smart Rate Limiting
- Supports all five Have I Been Pwned subscription tiers (Pwned 1-5)
- Automatically calculates optimal delays between API calls
- Shows estimated processing time before starting
- Prevents API throttling errors

| Tier | Requests/Min | Delay Per Request | Use Case |
|------|--------------|-------------------|----------|
| Pwned 1 | 10 | 6 seconds | Small teams |
| Pwned 2 | 50 | 1.2 seconds | Medium organizations |
| Pwned 3 | 100 | 600ms | Larger deployments |
| Pwned 4 | 500 | 120ms | Enterprise |
| Pwned 5 | 1000 | 60ms | Large enterprise |

### 🎯 Flexible Group Selection
- Search by group name or Object ID
- Supports multiple groups in a single run
- Handles nested groups automatically
- Processes both users and group members

## 📋 Prerequisites

1. **Have I Been Pwned API Key** - [Subscribe here](https://haveibeenpwned.com/API/Key)
2. **PowerShell 7.0 or later** - [Download here](https://github.com/PowerShell/PowerShell)
3. **Microsoft Graph PowerShell SDK**
4. **HaveIBeenPwned PowerShell Module**
5. **Entra ID Permissions**: `Group.Read.All` and `User.Read.All`

## 🚀 Installation

### Step 1: Install Required Modules

```powershell
# Install Microsoft Graph module
Install-Module Microsoft.Graph -Scope CurrentUser

# Install HaveIBeenPwned module
Install-Module HaveIBeenPwned -Scope CurrentUser
```

### Step 2: Download the Script

```powershell
# Clone the repository
git clone https://github.com/yourusername/EntraID-BreachChecker.git

# Or download directly
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/yourusername/EntraID-BreachChecker/main/Check-GroupMembersHaveIBeenPwned.ps1" -OutFile "Check-GroupMembersHaveIBeenPwned.ps1"
```

## 💻 Usage

### Basic Usage

```powershell
.\Check-GroupMembersHaveIBeenPwned.ps1 -GroupName "IT Department" -ApiKey "your-hibp-api-key"
```

### With PDF Generation

```powershell
.\Check-GroupMembersHaveIBeenPwned.ps1 `
    -GroupName "IT Department" `
    -ApiKey "your-hibp-api-key" `
    -GeneratePdf
```

### Specify Rate Limit (Pwned 3 subscription)

```powershell
.\Check-GroupMembersHaveIBeenPwned.ps1 `
    -GroupName "IT Department" `
    -ApiKey "your-hibp-api-key" `
    -RateLimitPerMinute '100'
```

### Multiple Groups by Object ID

```powershell
.\Check-GroupMembersHaveIBeenPwned.ps1 `
    -GroupId "12345678-1234-1234-1234-123456789abc" `
    -ApiKey "your-hibp-api-key"
```

### Check Nested Groups

```powershell
.\Check-GroupMembersHaveIBeenPwned.ps1 `
    -GroupName "All Employees" `
    -ApiKey "your-hibp-api-key" `
    -ExpandNestedGroups
```

## 📊 Example Output

The script provides clear console output throughout the process:

```
========================================
  imab.dk - Have I Been Pwned Tool
  Data Breach Check for Entra ID
========================================

API Rate Limit: 10 requests/minute
Delay between requests: 6000 ms
Checking 12 email addresses for breaches...
Estimated time: 2 minute(s)

Checking: user@domain.com
  [!] BREACHED: 2 breaches found
     - LinkedIn (Date: 2012-05-05)
       Data exposed: Email addresses, Passwords
     - Adobe (Date: 2013-10-04)
       Data exposed: Email addresses, Passwords, Usernames

Summary:
  Groups processed: 1
  Users checked: 12
  Breached accounts: 1
  Total breaches: 2
```

### Generated Reports

The HTML report includes:
- **Executive Summary**: Total members checked, breached accounts, total breaches, hit rate
- **Detailed Breach Information**: Email addresses, breach names, dates, exposed data types
- **Professional Design**: Modern, responsive layout with custom branding

## 📖 Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `GroupName` | String[] | No* | - | Display name(s) of the Entra ID group(s) to check |
| `GroupId` | String[] | No* | - | Object ID(s) of the group(s) to check |
| `ApiKey` | String | Yes | - | Have I Been Pwned API key |
| `RateLimitPerMinute` | String | No | '10' | API rate limit tier: '10', '50', '100', '500', '1000' |
| `ExpandNestedGroups` | Switch | No | False | Include members from nested groups |
| `SkipBreachCheck` | Switch | No | False | Only retrieve members without checking breaches |
| `GeneratePdf` | Switch | No | False | Generate PDF report (requires Chrome or Edge) |

*Either `GroupName` or `GroupId` must be specified.

## 🔒 Security Considerations

- **API Keys**: Never hardcoded; always passed as parameters
- **Authentication**: Uses Microsoft Graph with proper OAuth authentication
- **Data Privacy**: No breach data is stored; reports are generated locally
- **Permissions**: Only requires read-only Graph permissions (`Group.Read.All`, `User.Read.All`)
- **Rate Limiting**: Respects API limits to maintain service availability

## 🎯 Use Cases

- ✅ **Regular Security Audits** - Schedule monthly or quarterly breach checks
- ✅ **Onboarding Reviews** - Check new employees or contractors
- ✅ **High-Security Groups** - Monitor privileged access accounts
- ✅ **Compliance Requirements** - Document security monitoring for audits
- ✅ **Incident Response** - Quick assessment after public breach announcements
- ✅ **Executive Reporting** - Professional reports for management briefings

## 🛠️ Technical Details

**Built with:**
- PowerShell 7+
- Microsoft Graph PowerShell SDK
- HaveIBeenPwned PowerShell Module
- Have I Been Pwned API v3
- HTML5/CSS3 for report generation

**Supported Platforms:**
- Windows (PowerShell 7+)
- Linux (PowerShell 7+)
- macOS (PowerShell 7+)

## 📝 Examples

### Scheduled Security Audit

```powershell
# Create a scheduled task to run monthly
$Trigger = New-ScheduledTaskTrigger -Monthly -At 9am -DaysOfWeek Monday
$Action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument "-File C:\Scripts\Check-GroupMembersHaveIBeenPwned.ps1 -GroupName 'All Users' -ApiKey 'your-key'"
Register-ScheduledTask -TaskName "Monthly Breach Check" -Trigger $Trigger -Action $Action
```

### Check Multiple Groups

```powershell
$Groups = @("IT Department", "HR Team", "Finance")
foreach ($Group in $Groups) {
    .\Check-GroupMembersHaveIBeenPwned.ps1 -GroupName $Group -ApiKey "your-key"
}
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⚠️ Disclaimer

This script is provided "as-is" without any warranties or guarantees. While it has been tested thoroughly, you should always review and test any script before running it in production. The author takes no responsibility for any issues, damages, or unintended consequences that may arise from using this tool. Use at your own risk and always follow your organization's security and change management policies.

## 👤 Author

**Martin Bengtsson**  
Website: [imab.dk](https://www.imab.dk)  
Blog: [PowerShell Script: Automated Have I Been Pwned Breach Checks for Entra ID Groups](https://www.imab.dk/powershell-script-automated-have-i-been-pwned-breach-checks-for-entra-id-groups/)

## 🌟 Acknowledgments

- [Have I Been Pwned](https://haveibeenpwned.com) by Troy Hunt for the excellent breach database API
- [HaveIBeenPwned PowerShell Module](https://www.powershellgallery.com/packages/HaveIBeenPwned) community contributors
- Microsoft Graph team for the PowerShell SDK

## 📞 Support

If you encounter any issues or have questions:
- Open an [issue](https://github.com/yourusername/EntraID-BreachChecker/issues)
- Visit [imab.dk](https://www.imab.dk) for more automation tools
- Read the [blog post](https://www.imab.dk/powershell-script-automated-have-i-been-pwned-breach-checks-for-entra-id-groups/) for detailed information

---

**Remember**: Everything can be done automatically! 🚀
