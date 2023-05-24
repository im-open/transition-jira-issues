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
| Parameter         | Is Required | Description                                                                                                                                                           |
| ----------------- | ----------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `domain-name`     | true        | The domain name for Jira.                                                                                                                                             |
| `jql-query`       | true        | The JQL query to use to find tickets that will be transitioned.                                                                                                       |
| `transition-name` | true        | The name of the transition to perform. Examples might include Open, In Progress, Deployed, etc.                                                                       |
| `jira-username`   | false       | The username to login to Jira with in order to perform the transition. Will be ignored if not set.                                                                    |
| `jira-password`   | false       | The password to login to Jira with in order to perform the transition. Must be set if jira-username is set. If set when jira-username is not set, it will be ignored. |

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
          # etc.
```

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
