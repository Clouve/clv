# clv
## Shell commands wrapped in docker images

clv commands are executed through docker images and transient containers. Each executed command instantiates a transient container by mapping its home directory to a local one (~/.clv/home). The container never persists, however, the home directory containing all the settings persists across executions.

### Available commands are:

- git
- node
- npm
- ncu (npm-check-updates)
- python
- python2
- clv (will run any docker image using the same setup)

To expose container ports, just add PORTS as an environment variable. For example:

`PORTS="8080 5432"`

For example, the following command will publish 8080 and 5432 ports:

`PORTS="8080 5432" npm start`