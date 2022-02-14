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
        uses: im-open/transition-jira-tasks-by-query@v1.1.0
        with:
          domain-name: 'jira.com'
          jql-query: 'issuekey=PROJ-12345' or "filter='My Filter Name'"
          transition-name: 'Deployed'
          jira-username: 'some-user'
          jira-password: ${{ secrets.JIRA_USER_PASSWORD }}
```

## Contributing

When creating new PRs please ensure:
1. For major or minor changes, at least one of the commit messages contains the appropriate `+semver:` keywords listed under [Incrementing the Version](#incrementing-the-version).
2. The `README.md` example has been updated with the new version.  See [Incrementing the Version](#incrementing-the-version).
3. The action code does not contain sensitive information.

### Incrementing the Version

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
