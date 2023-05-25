# transition-jira-tasks-by-query

This GitHub Action will query Jira using JQL provided as an input, and will transition any tickets it finds to a given status. Credentials can be provided in case they are necessary to perform the transition.

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

| Parameter                  | Is Required    | Description                                                                                                                                                                                                                      |
|----------------------------|----------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `domain-name`              | true           | The domain name for Jira.                                                                                                                                                                                                        |
| `jql-query`                | conditionally* | The JQL query to use to find tickets that will be transitioned.                                                                                                                                                                  |
| `issues`                   | conditionally* | Comma delimited list of issues to transition. Use `im-open/get-workitems-action` to identify list of issues for a PR or deployment.                                                                                              |
| `transition-name`          | true           | The name of the transition to perform. _Examples might include Open, In Progress, Deployed, etc._                                                                                                                                |
| `overwrite-fields`         | false          | A [map](#updating-fields) of issue screen fields to overwrite, specifying the sub-field to update and its static value(s) for each field. When multiple sub-fields or other operations are required, use 'update' input instead. | 
| `process-operations`        | false          | A [map](#updating-fields) containing the field name and a list of operations to perform. _The fields included in here cannot be included in 'fields' input._                                                                     |
| `comment`                  | false          | Add a comment to the ticket after the transition.                                                                                                                                                                                |
| `fail-if-issues-not-found` | false          |  Fail if no issues are found or no issues transitioned. _`false` by default._                                                                                                    |
| `fail-if-jira-inaccessible` | false          | Fail if Jira is inaccessible at the moment. Sometimes Jira is done but shouldn't block the pipeline. _`false` by default._                                                                                                       |
| `jira-username`            | false          | The username to login to Jira with in order to perform the transition. _Will be ignored if not set._                                                                                                                             |
| `jira-password`            | false          | The password to login to Jira with in order to perform the transition. _Must be set if `jira-username` is set. If set when `jira-username` is not set, it will be ignored._                                                      |

<sup>*</sup> Either `jql-query` or `issues` input is required.  If both are provider, `jql-query` will be used.

## Outputs

| Output                | Description                                                                             |
|-----------------------|-----------------------------------------------------------------------------------------|
| `identified-issues`    | Issues found in JIra using the `jql-query` or `issues` input.                           |
| `transitioned-issues` | Issues successfully transitioned.                                                       |
| `failed-issues`       | Issues that where not successfully transitioned which where identified.                 |
| `notfound-issues`     | Issues that were not found from the `issues` input.                                     |

## Example

```yml
jobs:
  transition-jira-ticket:
    runs-on: ubuntu-20.04
    steps:
      - name: 'Transition Jira Ticket to Deployed Status'
        # You may also reference just the major or major.minor version
        uses: im-open/transition-jira-tasks-by-query@v1.1.3
        with:
          jira-username: 'some-user'
          jira-password: ${{ secrets.JIRA_USER_PASSWORD }}
          domain-name: 'jira.com'
          transition-name: 'Deployed'
          
          jql-query: 'issuekey=PROJ-12345'
          # jql-query: "filter='My Filter Name' AND issuekey=PROJ-12345"
          # jql-query: 'component IN ("System Infrastructure') AND 'Deployment Version' ~ 'v1.2.1''
          # issues: TW-1234, TW-4455
          # issues: |
          #   TW-1234
          #   TW-4455
          # etc.

          # If you want to update or overwrite fields, you can use the following inputs:
          # overwrite-fields: |
          #   {
          #     "customfield_12345": "some value"
          #   } 
```

## Updating Fields

They are two different ways to update fields.  Passing a `overwrite-fields` input or an `process-operations` input. You may not specify the same field name in both the `overwrite-fields` and `process-operations` inputs.

If you are unsure what field names to use, run the [Get-Jira-Issue](../main/Get-Jira-Issue.ps1) script locally from your machine using your ExtendHealth username and password.

> See [Atlassian Edit Issues Example](https://developer.atlassian.com/server/jira/platform/jira-rest-api-example-edit-issues-6291632/) for additional help

### Overwrite Fields Input
The easiest solution is to pass `overwrite-fields` input with static changes. These must be screen fields -- fields that a user can edit in Jira on the specific issue type.  If the field doesn't exist on the issue type, it will be ignored.

_The `overwrite-fields` input would be something like:_

```
"fields": {
    "assignee": {
      "name": "bob"
    },
    "resolution": {
      "name": "Fixed"
    },
    "customfield_40000": {
      "value": "red"
    }
  }
```

### Update Operations Input

Update fields by operations. Like adding a comment, creating a link to another ticket, adding additional values to a multi-select field, etc.  Updates all you to add or remove additional values to fields without overwriting what is already there.

_The `updates` fields would be something like:_

```
"update" : {
  "components" : [{"remove" : {"name" : "Trans/A"}}, {"add" : {"name" : "Trans/M"}}]
}
```

> If a field is specific that is not on the issue type, the operation will fail.

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
