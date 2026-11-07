# .exploratory.md — how exploratory sessions reach this project

<!--
Copy this file to your project root as .exploratory.md and replace every <...>
placeholder. Every section is optional: delete any you do not need. The format and
the reading rules are in this plugin's docs/project-environment.md.

This file never holds a secret value. Name an account by its fixture, or by the NAME
of the key that holds its credential in a gitignored secrets file. You may commit it.

Loading this file never authorizes a session. The explore skill shows you the hosts
and the harness command it loaded, and uses them only after you confirm them in that
session.
-->

## authorization

<!--
The two lines the explorer requires. Write yes only for a system you are authorized
to test that is not production. List every host:port a session may reach, including
each service the probe harness connects to.
-->

AUTHORIZED_NON_PRODUCTION: <yes, only for an authorized non-production target>
ALLOWED_HOSTS: <host:port>, <host:port>

## app

<!--
How to reach the running app. The developer starts it; a session never starts or
stops it.
-->

base_url: <scheme://host:port>
health_check: GET <path that must answer>
start: <how the developer starts the app>

## probe_harness

<!--
The one command that runs a scratch probe file under the project's test framework.
{probe_file} is the only placeholder, and it appears exactly once. probe_dir is
optional: project-relative, made only of letters, digits, . _ / and -, with no
empty, . or .. segment (so no trailing /) and none starting with -, ignored by git,
and not a symbolic link or below one; leave it out when the framework runs a file
from anywhere. Every service listed here must also be in ALLOWED_HOSTS; write none
when the harness connects to no service.
-->

command: <test command> {probe_file}
probe_dir: <optional project-relative directory that git ignores>
helpers: <fixture helpers a probe may use>
services: <host:port of each local service the harness connects to>

## accounts

<!--
The roles a feature can need, one per line, and how a probe gets each: a fixture
name, or a seeded account named by the KEY that holds its credential in a gitignored
secrets file. Never the value.
-->

- <role>: fixture <fixture or helper name>
- <role>: seeded account, credential under key <KEY_NAME> in <gitignored secrets file>

## observation

<!--
Tools the main conversation holds that the explorer does not, such as a browser on
the dev server, log tailing, or read-only database queries.
-->

- <tool the main conversation holds>

## constraints

<!--
Rules every session keeps, one per line.
-->

- <rule every session keeps>
