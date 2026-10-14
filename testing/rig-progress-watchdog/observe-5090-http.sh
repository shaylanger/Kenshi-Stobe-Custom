set -eu
printf 'HOST='; hostname
printf 'PORT14725 '
curl --silent --show-error --max-time 3 --output /dev/null --write-out 'http=%{http_code} total=%{time_total}\n' http://127.0.0.1:14725/health || true
printf 'PORT18098 '
curl --silent --show-error --max-time 3 --output /dev/null --write-out 'http=%{http_code} total=%{time_total}\n' http://127.0.0.1:18098/health || true
