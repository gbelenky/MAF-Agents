---
name: troubleshooting
description: Describe when to use this prompt
---
use all available telemtry (Azure Monitor, Application Insights, Log Analytics) to troubleshoot any issues with the bot deployment, connectivity, or functionality. Check for common issues such as:
- Deployment failures in Azure (check azd logs, Azure Portal)
- Application Insights telemetry not being sent (check connection string and instrumentation key)
- Log Analytics workspace issues (check workspace ID and logs)
- Bot connectivity issues (check Azure Bot Service channels and Teams configuration)
- Review Azure Bot Service logs for any errors or warnings  