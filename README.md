# clv
## Shell commands wrapped in docker images

Shell commands executed through docker images and transient containers. Each executed command instantiates a transient container by mapping its home directory to a local one (~/.clv/home). The container never persists, however, the home directory containing all the settings persists across executions.

### Available commands are:

- clv (a generic command that will run any docker image using the same setup)
- gcloud (https://cloud.google.com/sdk/gcloud/reference/)
- git (https://git-scm.com/docs)
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