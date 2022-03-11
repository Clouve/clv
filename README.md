# clv
## Shell commands wrapped in docker images

Shell commands executed through docker images and transient containers. Each executed command instantiates a transient container by mapping its home directory to a local one (~/.clv/[CMD_HOME]). The container never persists, however, the home directory containing all the settings persists across executions.

### Available commands are:

- aws (https://aws.amazon.com/cli/)
- az (https://docs.microsoft.com/en-us/cli/azure/)
- gcloud (https://cloud.google.com/sdk/gcloud/reference/)
- git (https://git-scm.com/docs)
- go (https://pkg.go.dev/cmd/go)
- helm (https://helm.sh/docs/helm)
- ncu (https://www.npmjs.com/package/npm-check-updates)
- node (https://nodejs.org/api/cli.html)
- npm (https://docs.npmjs.com/cli-documentation/cli)
- prettier (https://prettier.io/docs/en/cli.html)
- python (https://docs.python.org/3/)
- python2 (https://docs.python.org/2/)

To expose container ports, just add PORTS as an environment variable. For example:

`PORTS="8080 5432"`

For example, the following command will publish 8080 and 5432 ports:

`PORTS="8080 5432" npm start`

### Install

Will install all or some of the available commands

Example 1: To install all commands:

`curl -s https://raw.githubusercontent.com/Clouve/clv/master/web/install | bash`

Example 2: To install only specific commands like go and node:

`curl -s https://raw.githubusercontent.com/Clouve/clv/master/web/install | bash -s -- go node`

Example 3: To install all but specific commands like git and python2:

`curl -s https://raw.githubusercontent.com/Clouve/clv/master/web/install | bash -s -- --skip git python2`

### Uninstall

Will uninstall all or some of the previously installed commands

Example 1: To uninstall all commands:

`curl -s https://raw.githubusercontent.com/Clouve/clv/master/web/uninstall | bash`

Example 2: To uninstall only specific commands like git and python2:

`curl -s https://raw.githubusercontent.com/Clouve/clv/master/web/uninstall | bash -s -- git python2`
