# transition-jira-issues

This GitHub Action will query Jira using JQL provided as an input, and will transition any issues it finds to a given status.

## Requirements

If the Jira server is hosted on an internal network, then the action must run on a runner that has access to that network.

## Index <!-- omit in toc -->

- [transition-jira-issues](#transition-jira-issues)
  - [Requirements](#requirements)
  - [Inputs](#inputs)
  - [Outputs](#outputs)
  - [Usage Examples](#usage-examples)
  - [Updating Fields](#updating-fields)
    - [Update Fields Input](#update-fields-input)
    - [Update Operations Input](#update-operations-input)
  - [Contributing](#contributing)
    - [Incrementing the Version](#incrementing-the-version)
    - [Source Code Changes](#source-code-changes)
    - [Updating the README.md](#updating-the-readmemd)
  - [Code of Conduct](#code-of-conduct)
  - [License](#license)

## Inputs

Work items, tickets, etc. are referenced as "issues" in this action.

| Parameter                          | Is Required    | Description                                                                                                                                                                                                                                  |
|------------------------------------|----------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `domain-name`                      | true           | The domain name for Jira.                                                                                                                                                                                                                    |
| `jql-query`                        | conditionally* | The [JQL query](https://support.atlassian.com/jira-software-cloud/docs/jql-operators/) to use to find issues that will be transitioned. A max of 20 issues can be transitioned.                                                              |
| `issues`                           | conditionally* | Comma delimited list of issues to transition. Use `im-open/get-workitems-action` to identify list of issues for a PR or deployment.                                                                                                          |
| `transition-name`                  | true           | The name of the transition to perform. _Examples might include Open, In Progress, Deployed, etc._                                                                                                                                            |
| `update-fields`                    | false          | A [map](#updating-fields) of issue screen fields to overwrite, specifying the sub-field to update and its static value(s) for each field. When multiple sub-fields or other operations are required, use 'process-operations' input instead. |
| `process-operations`               | false          | A [map](#updating-fields) containing the field name and a list of operations to perform. _The fields included in here cannot be included in 'update-fields' input._                                                                          |
| `comment`                          | false          | Add a comment to the issue after the transition.                                                                                                                                                                                             |
| `missing-transition-as-successful` | false          | Mark as a successful if issue is missing the transition. _`true` by default._                                                                                                                                                                |
| `create-notice`                    | false          | Add notification to runner with details about successful transitioned issues. _`true` by default._                                                                                                                                           |
| `create-warnings`                  | false          | Add warning notifications to runner. _`true` by default._                                                                                                                                                                                    |
| `fail-on-transition-failure`       | false          | Fail if some issues failed transitioning. _`true` by default._                                                                                                                                                                               |
| `fail-if-issue-excluded`           | false          | Fail if some issues are excluded that are listed in the `issues` input but not identified by query. _`true` by default._                                                                                                                     |
| `fail-if-jira-inaccessible`        | false          | Fail if Jira is inaccessible at the moment. Sometimes Jira is down but shouldn't block the pipeline. _`false` by default._                                                                                                                   |
| `jira-username`                    | false          | The username to login to Jira with in order to perform the transition.                                                                                                                                                                       |
| `jira-password`                    | false          | The password to login to Jira with in order to perform the transition.                                                                                                                                                                       |

> <sup>*</sup> Either `jql-query` or `issues` input is required.  If both are provider, both will be included.

## Outputs

| Output                | Description                                                                                                                                           | Type                 |
|-----------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------|----------------------|
| `processed-issues`    | Issues successfully transitioned, skipped and (if enabled) with an unavailable transition.                                                            | Comma-delimited list |
| `transitioned-issues` | Issues successfully transitioned.                                                                                                                     | Comma-delimited list |
| `failed-issues`       | Issues in Jira not successfully processed.                                                                                                            | Comma-delimited list |
| `unavailable-issues`  | Issues missing the specified transition.                                                                                                              | Comma-delimited list |
| `excluded-issues`     | Issues excluded that are listed in the `issues` input but not identified by query.                                                                    | Comma-delimited list |
| `is-successful`       | One or more issues were transitioned successfully and/or skipped. _If `missing-transition-as-successful` enabled, also includes missing transitions._ | Boolean              |
| `some-identified`     | Some issues were found in Jira.                                                                                                                       | Boolean              |
| `some-transitioned`   | Some issues were transitioned successfully.                                                                                                           | Boolean              |
| `some-unavailable`    | Some issues do not have transition.                                                                                                                   | Boolean              |
| `some-skipped`        | Some issues skipped when already transitioned or other causes.                                                                                        | Boolean              |
| `some-excluded`       | Some issues were excluded.                                                                                                                            | Boolean              |

## Usage Examples

```yml
jobs:
  transition-jira-issue:
    runs-on: ubuntu-20.04
    steps:

      - name: Get work items
        uses: im-open/get-work-items-action@latest
        id: get-issues
        with:
          create-env-variable: true
          reference: v1.2.3
          github-token: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Transition Jira Issue to Deployed Status
        # You may also reference just the major or major.minor version
        uses: im-open/transition-jira-issues@v2.1.3
        id: transition
        with:
          jira-username: ${{ vars.JIRA_USERNAME }}
          jira-password: ${{ secrets.JIRA_PASSWORD }}
          domain-name: jira.com
          transition-name: Deployed
          
          issues: ${{ steps.get-issues.outputs.result-list }}
          # jql-query: 'issuekey=PROJ-12345'
          # jql-query: "filter='My Filter Name' AND issuekey=PROJ-12345"
          # jql-query: 'component IN ("System Infrastructure') AND "Deployment Version" ~ 'v1.2.1''
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

      # Some issue types don't have a transition status like others.  
      # In those cases, where you want to still transition, a second step will need to be invoked.  
      # You can pass in the `unavailable-issues` output to transition those remaining issues.
      - name: Transition Remaining Jira issues to Closed Status
        uses: im-open/transition-jira-issues@v2.1.3
        with:
          jira-username: ${{ vars.JIRA_USERNAME }}
          jira-password: ${{ secrets.JIRA_PASSWORD }}
          domain-name: jira.com
          transition-name: Closed
          issues: ${{ steps.transition.outputs.unavailable-issues }}
```

## Updating Fields

They are two different ways to update fields.  Passing a `update-fields` input or an `process-operations` input. You may not specify the same field name in both the `update-fields` and `process-operations` inputs.

If you are unsure what field names to use, run the [Get-Jira-Issue](../main/Test-Get-Jira-Issue.ps1) script locally.

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

> If a field doesn't exist on a given Issue Type, it will be ignored

### Update Operations Input

Update fields by operation(s). Adding multiple components, creating a link to another issue, adding additional values to a multi-select field, etc.  Updating operations allows you to add or remove additional values to fields without overwriting what is already there.

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

When creating PRs, please review the following guidelines:

- [ ] The action code does not contain sensitive information.
- [ ] At least one of the commit messages contains the appropriate `+semver:` keywords listed under [Incrementing the Version] for major and minor increments.
- [ ] The README.md has been updated with the latest version of the action.  See [Updating the README.md] for details.

### Incrementing the Version

This repo uses [git-version-lite] in its workflows to examine commit messages to determine whether to perform a major, minor or patch increment on merge if [source code] changes have been made.  The following table provides the fragment that should be included in a commit message to active different increment strategies.

| Increment Type | Commit Message Fragment                     |
|----------------|---------------------------------------------|
| major          | +semver:breaking                            |
| major          | +semver:major                               |
| minor          | +semver:feature                             |
| minor          | +semver:minor                               |
| patch          | _default increment type, no comment needed_ |

### Source Code Changes

The files and directories that are considered source code are listed in the `files-with-code` and `dirs-with-code` arguments in both the [build-and-review-pr] and [increment-version-on-merge] workflows.  

If a PR contains source code changes, the README.md should be updated with the latest action version.  The [build-and-review-pr] workflow will ensure these steps are performed when they are required.  The workflow will provide instructions for completing these steps if the PR Author does not initially complete them.

If a PR consists solely of non-source code changes like changes to the `README.md` or workflows under `./.github/workflows`, version updates do not need to be performed.

### Updating the README.md

If changes are made to the action's [source code], the [usage examples] section of this file should be updated with the next version of the action.  Each instance of this action should be updated.  This helps users know what the latest tag is without having to navigate to the Tags page of the repository.  See [Incrementing the Version] for details on how to determine what the next version will be or consult the first workflow run for the PR which will also calculate the next version.

## Code of Conduct

This project has adopted the [im-open's Code of Conduct](https://github.com/im-open/.github/blob/main/CODE_OF_CONDUCT.md).

## License

Copyright &copy; 2023, Extend Health, LLC. Code released under the [MIT license](LICENSE).

<!-- Links -->
[Incrementing the Version]: #incrementing-the-version
[Updating the README.md]: #updating-the-readmemd
[source code]: #source-code-changes
[usage examples]: #usage-examples
[build-and-review-pr]: ./.github/workflows/build-and-review-pr.yml
[increment-version-on-merge]: ./.github/workflows/increment-version-on-merge.yml
[git-version-lite]: https://github.com/im-open/git-version-lite
