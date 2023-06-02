# transition-jira-tasks-by-query

This GitHub Action will query Jira using JQL provided as an input, and will transition any tickets it finds to a given status. Credentials can be provided in case they are necessary to perform the transition.

## Requirements

This action requires access to our on-prem network for accesss to the Jira servers.  You must run the action with a `self-hosted` or `coldstone` runner.

## Index

- [transition-jira-tasks-by-query](#transition-jira-tasks-by-query)
  - [Index](#index)
  - [Inputs](#inputs)
  - [Example](#example)
  - [Contributing](#contributing)
    - [Incrementing the Version](#incrementing-the-version)
  - [Code of Conduct](#code-of-conduct)
  - [License](#license)


## Inputs

| Parameter                          | Is Required    | Description                                                                                                                                                                                                                      |
|------------------------------------|----------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `domain-name`                      | true           | The domain name for Jira.                                                                                                                                                                                                        |
| `jql-query`                        | conditionally* | The JQL query to use to find tickets that will be transitioned. A max of 20 issues can be transitioned.                                                                                                                          |
| `issues`                           | conditionally* | Comma delimited list of issues to transition. Use `im-open/get-workitems-action` to identify list of issues for a PR or deployment.                                                                                              |
| `transition-name`                  | true           | The name of the transition to perform. _Examples might include Open, In Progress, Deployed, etc._                                                                                                                                |
| `update-fields`                    | false          | A [map](#updating-fields) of issue screen fields to overwrite, specifying the sub-field to update and its static value(s) for each field. When multiple sub-fields or other operations are required, use 'update' input instead. |
| `process-operations`               | false          | A [map](#updating-fields) containing the field name and a list of operations to perform. _The fields included in here cannot be included in 'fields' input._                                                                     |
| `comment`                          | false          | Add a comment to the ticket after the transition.                                                                                                                                                                                |
| `fail-if-issue-not-transitioned`   | false          | Fail if some issues where not transitioned. _`true` by default._                                                                                                                                                                 |
| `missing-transition-as-successful` | false          | Fail if some issues are missing the transition. _`true` by default._                                                                                                                                                             |
| `fail-if-issue-not-found`          | false          | Fail if some issues are not found that are listed in the `issues` input. _`true` by default._                                                                                                                                    |
| `fail-if-jira-inaccessible`        | false          | Fail if Jira is inaccessible at the moment. Sometimes Jira is down but shouldn't block the pipeline. _`false` by default._                                                                                                       |
| `jira-username`                    | false          | The username to login to Jira with in order to perform the transition. _Will be ignored if not set._                                                                                                                             |
| `jira-password`                    | false          | The password to login to Jira with in order to perform the transition. _Must be set if `jira-username` is set. If set when `jira-username` is not set, it will be ignored._                                                      |

> <sup>*</sup> Either `jql-query` or `issues` input is required.  If both are provider, `jql-query` will be used.

## Outputs

| Output                | Description                                                                                |
|-----------------------|--------------------------------------------------------------------------------------------|
| `identified-issues`   | Issues found in Jira using the `jql-query` or `issues` input.                              |
| `processed-issues`    | Issues successfully transitioned, skipped and (if enabled) with an unavailable transition. |
| `transitioned-issues` | Issues successfully transitioned.                                                          |
| `unavailable-issues`  | Issues missing the specificed transition.                                                  |
| `failed-issues`       | Issues identified but not successfully processed.                                          |
| `not-found-issues`    | Issues that were not found.                                                                |

## Example

```yml
jobs:
  transition-jira-ticket:
    runs-on: ubuntu-20.04
    steps:
      - name: Transition Jira Ticket to Deployed Status
        # You may also reference just the major or major.minor version
        uses: im-open/transition-jira-tasks-by-query@v2.0.0
        with:
          jira-username: ${{ vars.JIRA_USERNAME }}
          jira-password: ${{ secrets.JIRA_PASSWORD }}
          domain-name: jira.com
          transition-name: Deployed # You may also use the transition ID
          
          jql-query: 'issuekey=PROJ-12345'
          # jql-query: "filter='My Filter Name' AND issuekey=PROJ-12345"
          # jql-query: 'component IN ("System Infrastructure') AND 'Deployment Version' ~ 'v1.2.1''
          # issues: TW-1234, TW-4455
          # issues: |
          #   TW-1234
          #   TW-4455
          # etc.

          # If you want to update or overwrite fields, you can use the following inputs:
          # update-fields: |
          #   {
          #     "customfield_12345": "some value"
          #   } 
```

## Updating Fields

They are two different ways to update fields.  Passing a `update-fields` input or an `process-operations` input. You may not specify the same field name in both the `update-fields` and `process-operations` inputs.

If you are unsure what field names to use, run the [Get-Jira-Issue](../main/Test-Get-Jira-Issue.ps1) script locally from your machine using your ExtendHealth username and password.

> You may also use the field's display name

Related: 
- [Custom Fields](https://atlassianps.org/docs/JiraPS/about/custom-fields.html)
- [Atlassian Edit Issues Example](https://developer.atlassian.com/server/jira/platform/jira-rest-api-example-edit-issues-6291632/) for additional help

### Update Fields Input

The easiest solution is to pass `update-fields` input with static changes. These must be screen fields -- fields that a user can edit in Jira on the specific issue type.  If the field doesn't exist on the issue type, it will be ignored.

_The `update-fields` input would be something like:_

```json
{
    "assignee": {
      "name": "bob",
      "issueType": "Story"
    },
    "resolution": {
      "name": "Fixed",
      "issueType": ["Bug", "Story"]
    },
    "customfield_40000": {
      "value": "red"
    }
}
```

> If a field doesn't exist on a given Issue Type, it will be ignored

### Update Operations Input

Update fields by operation(s). Adding multiple components, creating a link to another ticket, adding additional values to a multi-select field, etc.  Updating operations allows you to add or remove additional values to fields without overwriting what is already there.

_The `process-operations` fields would be something like:_

```json
{
  "components" : [
    {
      "remove" : {
        "name" : "Trans/A"
      }
    }, 
    {
      "add" : {
        "name" : "Trans/M"
      }
    }
  ]
}
```

> If an operation doesn't exist on a given Issue Type, it will be ignored
 
## Contributing

When creating new PRs please ensure:

1. For major or minor changes, at least one of the commit messages contains the appropriate `+semver:` keywords listed under [Incrementing the Version](#incrementing-the-version).
1. The action code does not contain sensitive information.

When a pull request is created and there are changes to code-specific files and folders, the `auto-update-readme` workflow will run.  The workflow will update the action-examples in the README.md if they have not been updated manually by the PR author. The following files and folders contain action code and will trigger the automatic updates:

- `action.yml`
- `src/**`
There may be some instances where the bot does not have permission to push changes back to the branch though so this step should be done manually for those branches. See [Incrementing the Version](#incrementing-the-version) for more details.

### Incrementing the Version

The `auto-update-readme` and PR merge workflows will use the strategies below to determine what the next version will be.  If the `auto-update-readme` workflow was not able to automatically update the README.md action-examples with the next version, the README.md should be updated manually as part of the PR using that calculated version.

This action uses [git-version-lite] to examine commit messages to determine whether to perform a major, minor or patch increment on merge.  The following table provides the fragment that should be included in a commit message to active different increment strategies.
| Increment Type | Commit Message Fragment                     |
| -------------- | ------------------------------------------- |
| major          | +semver:breaking                            |
| major          | +semver:major                               |
| minor          | +semver:feature                             |
| minor          | +semver:minor                               |
| patch          | *default increment type, no comment needed* |

## Code of Conduct

This project has adopted the [im-open's Code of Conduct](https://github.com/im-open/.github/blob/master/CODE_OF_CONDUCT.md).

## License

Copyright &copy; 2021, Extend Health, LLC. Code released under the [MIT license](LICENSE).

[git-version-lite]: https://github.com/im-open/git-version-lite
